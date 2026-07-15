# WP-A1d (Register Extractors) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Two §5.5-hardened **register extractors** on WP-A1's interface — **Historic England** (NHLE, emits `hehle:<id>`, carries the heritage-grade §4 signal) and **Open Plaques** (emits `plaque:openplaques/<id>`, carries the plaque-presence §4 signal) — a shared **SSRF-safe single-file acquisition**, and a **written feasibility-verdict** for the Malaysia national heritage register (spec §4: included only if machine-readable, nothing depends on it). Completes Track A's extractor designs.

**Architecture:** Under `pipeline/` (the WP-A1 `mt_pipeline` package). Each extractor implements A1b's `Extractor` protocol and produces records only via `source_record.parse`/`persist`. Historic England consumes the NHLE as **GeoJSON** (RFC 7946 mandates WGS84 — sidesteps any OSGB→WGS84 transform) parsed with **`ijson` streaming** (bounded memory over ~400k entries); Open Plaques consumes the Open Plaques **JSON** dump. A shared `_snapshot.py` handles acquisition (one SSRF-safe, byte-capped, deadline-bounded download through A1b's protected opener) and a `sha256` provenance sidecar. `extract()` is a pure function of the local dated snapshot (tests need no network). The Malaysia register is a **written verdict** deliverable, not code.

**Tech Stack:** Python 3.11+ (`mt_pipeline` + `mt-contracts`), **`ijson`** (streaming JSON/GeoJSON), stdlib `json`/`csv`/`hashlib`/`urllib`/`logging`, `pytest`. Reuses A1b's `fetch` network boundary.

## Global Constraints

- **Implements A1's interface + extends A1b's registry, never re-declares them.** Records are produced only via `mt_pipeline.source_record.parse(region, source, source_ref, name, lat, lon, props)` / `persist(conn, record, *, run_id)`. Canonical-ref grammar + text-safety are `mt_contracts`' (via `parse`), never re-implemented.
- **DEPENDENCY — blocked on A1b impl landing (honest, per the A1c lesson).** A1b's *plan* is merged (PR #34) but its *impl is not yet on develop* (only the `wp-a1b-plan` branch: no `extractors/`, no `extract_stage.py`, no `fetch.py`). This plan is written against A1b's published interface; **A1d's impl is BLOCKED on A1b's impl landing first** — Tasks 1/5 modify A1b files (`fetch.py`, `extract_stage.py`) and Tasks 2/4 conform to A1b's `Extractor` protocol. **A1 preconditions** (present on develop, PR #33): `source_record.parse`/`persist`/`SourceRecordError`; `store.connect`/`store.init_schema` + the `source_records` table; `config.RegionConfig` (`.region_id`, `.sources`). `mt_contracts.is_canonical_ref` already accepts `hehle:…` and `plaque:openplaques/…` — **no A0 change is required for A1d.**
- **§4 signals are EMITTED, not scored (scoring is A4).** Historic England emits the listing **`grade`** in `props` → the §4 "heritage designation/grade" heuristic; Open Plaques' very presence (a `plaque:` ref clustered onto a place) is the §4 "plaque presence" heuristic, and the inscription/subject ride in `props`. A1d does not score, categorize, reconcile, or mint IDs.
- **Registry key = region-config `sources` key = snapshots key (A1b `run_extract` contract).** Register Historic England under **`"historic_england"`** (it emits `source="hehle"`, `source_ref="hehle:<id>"`) and Open Plaques under **`"open_plaques"`** (emits `source="plaque"`, `source_ref="plaque:openplaques/<id>"`). The registry key differing from the emitted source is fine — `parse` only checks the ref prefix against the `source` arg the extractor passes. `enabled_for` uses `sources.get(s) is True`, so both register exactly like `wikidata`/`wikipedia`.
- **Streaming, bounded memory (fable) — honestly.** The NHLE is ~400k entries; a whole-file `json.loads` would hold hundreds of MB. HE parses with **`ijson.items(f, "features.item")`** — one feature at a time, memory bounded by the per-feature dict, not the file. Open Plaques' dump is small (documented ≤ the download cap) and uses `json.loads`. In both cases the **download byte cap is the hard upper bound** on what reaches the parser.
- **Deterministic (Principle 12).** `extract(snapshot, …)` is a pure function of the dated snapshot: same file → identical records, identical order. Records emit in **stable lexical `source_ref` order** (collected then sorted), de-duped by `source_ref` (keep-first). Way/polygon points use a **deterministic arithmetic-mean (vertex) centroid of the outer ring with the repeated closing vertex dropped** (the A1c lesson — order fixed by the file, not by an associativity assumption). No wall-clock/randomness in `extract` outputs; the snapshot date and `run_id` are metadata only. **All A1d code modules live under `extractors/`** (`_snapshot.py`, `historic_england.py`, `open_plaques.py`) — covered by A1b's recursive determinism guard once it lands; the `a1d_sources.json` config is data, not code (no guard gap).
- **Never crash on hostile input, per-feature vs file-level (Principle 10 / §5.5 / binding carry-in).** Raw-blob bounding at the extractor edge BEFORE `parse`: `MAX_NAME_LEN`, `MAX_PROPS_KEYS`/`MAX_PROP_STR_LEN`, coordinate presence/finiteness. Each per-feature body runs in a `try/except` that **skips** the feature (dropped-feature counter + WARNING summary — never silent). File-level unparseability (truncated/garbage snapshot) is a **loud typed `SnapshotParseError`**. Nothing from a register is interpolated into shell/SQL/LLM.
- **SSRF-safe acquisition (fable condition — "low SSRF surface is not no SSRF surface").** A "single fixed-URL GET" still follows redirects. The shared download reuses **A1b's ONE protected opener** (`fetch._opener` → `_AllowlistRedirect`), re-validating the https + host allowlist **on every redirect hop**, plus a streaming byte cap, a wall-clock deadline (slowloris), and a rejected-`Content-Encoding` check — added as `fetch.get_to_file` so the security-critical opener stays **single-sourced in A1b** (no duplicated `_AllowlistRedirect`). A neuter-goes-red redirect test drives a real 302 to an off-allowlist host through `get_to_file` and asserts it is blocked.
- **Self-describing provenance (A1b/A1c precedent).** Acquisition writes a `<file>.meta.json` sidecar (`source_url`, `snapshot_date`, `sha256`, `size`); `extract` verifies the `sha256` when the sidecar is present (loud `ProvenanceError` on mismatch; absent → logged warning, dev convenience). The sidecar is **untrusted** (Principle 10): size-bounded before read, malformed/non-dict/oversized → typed `ProvenanceError`, never `AttributeError`.
- **Licensing/attribution is a plan-carried requirement.** **Historic England NHLE is OGL v3.0** → attribution is **required**: the attribution string travels in `a1d_sources.json` per source. **Open Plaques is CC0** (no obligation; courtesy credit). A1d does **not** build the surfacing UI: the **app credits screen is B-track**, and **WP-A7's manifest is the natural carrier** for per-source attribution strings so the app renders credits from data — **flagged as an A7 design input on issue #11**.
- **Consumed config, not invented.** Source URLs, allowed hosts, and attribution strings live in `pipeline/config/a1d_sources.json` (data the acquire step takes as input), header-marked so operations can update endpoints without a code change.
- **Test-first**, against tiny hand-built `.geojson`/`.json` fixtures (prod consumes the full dumps); the feasibility critic installs `ijson` and runs the real streaming parse against the fixture.

**Ratified (fable, thread `wp/a1d`)** — three deliverables (HE + Open Plaques extractors + Malaysia written-verdict spike); BUILD acquisition **with A1b's per-hop redirect discipline** (the neuter-goes-red redirect test comes with it); GeoJSON/WGS84 NHLE + outer-ring-mean-with-closing-vertex-dedup + `ijson` streaming with an honest memory claim; spike = written verdict, default-excluded, follow-up-recommendation-only (never code in A1d); no A0 change; OGL attribution plan-carried with surfacing routed to A7's manifest (issue #11). Time-sensitive region-config flag resolved: codex's A1b impl is pinned to the **shipped** `sources` schema (bool or `{id,enabled}` object; **null not used**; absence allowed), and `enabled_for` keeps boolean-only semantics until the register seam is designed.

---

## File Structure

```
pipeline/src/mt_pipeline/
  fetch.py                              # MODIFY (A1b): add get_to_file (streaming-to-disk counterpart of get_json, SAME _opener)
  extractors/
    _snapshot.py                        # shared: download_snapshot (via fetch.get_to_file) + write_sidecar + verify_sha256_sidecar; SnapshotError/SnapshotParseError/ProvenanceError
    historic_england.py                 # HistoricEnglandExtractor (GeoJSON/ijson; grade; Point + outer-ring-mean centroid) + make_extractor
    open_plaques.py                     # OpenPlaquesExtractor (JSON dump; inscription/subject; name derivation) + make_extractor
  extract_stage.py                      # MODIFY (A1b): register historic_england + open_plaques in build_registry
pipeline/config/
  a1d_sources.json                      # BOOTSTRAP: source URLs, allowed_hosts, attribution strings (HE=OGL, plaques=CC0)
pipeline/tests/
  fixtures/registers/he_sample.geojson  # FeatureCollection: Point entry + asymmetric closed Polygon entry + non-digit id + missing name
  fixtures/registers/plaques_sample.json# array: geolocated plaque + null-coord plaque + non-digit id
  test_register_snapshot.py             # acquisition (SSRF/redirect/cap/deadline) + provenance sidecar
  test_historic_england.py              # Task 2/3
  test_open_plaques.py                  # Task 4
  test_extract_stage_registers.py       # Task 5
docs/superpowers/spikes/
  2026-07-15-wp-a1d-malaysia-register-feasibility.md   # Task 6: the WRITTEN VERDICT (not code)
```

---

### Task 1: Shared SSRF-safe acquisition + provenance sidecar

**Files:**
- Modify: `pipeline/src/mt_pipeline/fetch.py` (add `get_to_file`)
- Create: `pipeline/src/mt_pipeline/extractors/_snapshot.py`
- Test: `pipeline/tests/test_register_snapshot.py`

**Interfaces:**
- Consumes (A1b): `fetch._opener`, `fetch._AllowlistRedirect`, `fetch.FetchError` (the single protected opener path).
- Produces:
  - `fetch.get_to_file(url, dest, *, expected_hosts, max_bytes=MAX_RESPONSE_BYTES, timeout=30, deadline=120) -> int` — streams the response to `dest` through the SAME `_opener(expected_hosts)` (https + host allowlist re-validated on every redirect hop), raising `FetchError` **before** exceeding `max_bytes`, enforcing the wall-clock `deadline`, and rejecting an unexpected `Content-Encoding`. Returns bytes written.
  - `_snapshot.SnapshotError`, `_snapshot.SnapshotParseError`, `_snapshot.ProvenanceError`; `MAX_SIDECAR_BYTES = 64 * 1024`.
  - `_snapshot.download_snapshot(source_key, dest_dir, *, config, fetch_fn=fetch.get_to_file, enabled=False) -> pathlib.Path` — reads `config[source_key]` (`url`, `allowed_hosts`, `max_bytes?`); when `enabled`, downloads via `fetch_fn` and writes the `<dest>.meta.json` sidecar (`source_url`, `snapshot_date` from config, `sha256`, `size`). Injected `fetch_fn` keeps tests network-free.
  - `_snapshot.verify_sha256_sidecar(snapshot_path) -> None` — sidecar present → verify `sha256` (loud `ProvenanceError` on mismatch); absent → logged warning; malformed/oversized/non-dict → typed `ProvenanceError`.

- [ ] **Step 1: Write the failing tests**

`pipeline/tests/test_register_snapshot.py`:
```python
import io
import json
import hashlib
import pathlib
import urllib.request
import email.message
import pytest
from mt_pipeline import fetch
from mt_pipeline.extractors import _snapshot


# ---- get_to_file: SSRF + cap ----
class _FakeOpener:
    def __init__(self, body): self._body = body
    def open(self, url, timeout=None): return io.BytesIO(self._body)

def test_get_to_file_rejects_non_https(tmp_path):
    with pytest.raises(fetch.FetchError):
        fetch.get_to_file("http://insecure/x", tmp_path / "o", expected_hosts={"historicengland.org.uk"})

def test_get_to_file_streams_and_caps(tmp_path, monkeypatch):
    monkeypatch.setattr(fetch, "_opener", lambda hosts: _FakeOpener(b"x" * 5000))
    with pytest.raises(fetch.FetchError):
        fetch.get_to_file("https://historicengland.org.uk/x", tmp_path / "o",
                          expected_hosts={"historicengland.org.uk"}, max_bytes=1024)

def test_get_to_file_writes_bytes(tmp_path, monkeypatch):
    monkeypatch.setattr(fetch, "_opener", lambda hosts: _FakeOpener(b"HELLO"))
    n = fetch.get_to_file("https://historicengland.org.uk/x", tmp_path / "o",
                          expected_hosts={"historicengland.org.uk"})
    assert n == 5 and (tmp_path / "o").read_bytes() == b"HELLO"

# ---- the SSRF teeth: a real 302 to an off-allowlist host must be BLOCKED on the executed path ----
class _Mock302Handler(urllib.request.BaseHandler):
    def __init__(self, location): self.location = location
    def https_open(self, req):
        m = email.message.Message(); m["Location"] = self.location
        fp = io.BytesIO(b""); fp.headers = m
        return urllib.request.HTTPError(req.full_url, 302, "Found", m, fp)

def _mock_opener(hosts, location):
    o = urllib.request.OpenerDirector()
    for h in (urllib.request.HTTPErrorProcessor(), fetch._AllowlistRedirect(hosts), _Mock302Handler(location)):
        o.add_handler(h)
    return o

def test_get_to_file_blocks_redirect_to_offallowlist_host(tmp_path, monkeypatch):
    monkeypatch.setattr(fetch, "_opener", lambda h: _mock_opener(h, "https://evil.example/x"))
    with pytest.raises(fetch.FetchError, match="blocked redirect"):
        fetch.get_to_file("https://historicengland.org.uk/x", tmp_path / "o",
                          expected_hosts={"historicengland.org.uk"})


# ---- provenance sidecar ----
def test_verify_sha256_sidecar_loud_on_mismatch(tmp_path):
    snap = tmp_path / "he.geojson"; snap.write_bytes(b"DATA")
    good = hashlib.sha256(b"DATA").hexdigest()
    (tmp_path / "he.geojson.meta.json").write_text(json.dumps({"source_url": "u", "snapshot_date": "2026-07-14", "sha256": good, "size": 4}))
    _snapshot.verify_sha256_sidecar(snap)
    (tmp_path / "he.geojson.meta.json").write_text(json.dumps({"sha256": "deadbeef"}))
    with pytest.raises(_snapshot.ProvenanceError):
        _snapshot.verify_sha256_sidecar(snap)

def test_verify_sidecar_absent_warns(tmp_path, caplog):
    snap = tmp_path / "dev.json"; snap.write_bytes(b"x")
    _snapshot.verify_sha256_sidecar(snap)
    assert any("provenance" in r.message.lower() for r in caplog.records)

def test_verify_sidecar_malformed_is_typed(tmp_path):
    snap = tmp_path / "he.geojson"; snap.write_bytes(b"DATA")
    meta = tmp_path / "he.geojson.meta.json"
    meta.write_text("[1,2,3]")                                   # not a dict
    with pytest.raises(_snapshot.ProvenanceError):
        _snapshot.verify_sha256_sidecar(snap)
    meta.write_bytes(b"{" + b" " * (_snapshot.MAX_SIDECAR_BYTES + 10))  # oversized
    with pytest.raises(_snapshot.ProvenanceError):
        _snapshot.verify_sha256_sidecar(snap)

def test_download_snapshot_writes_sidecar_via_injected_fetch(tmp_path):
    cfg = {"historic_england": {"url": "https://historicengland.org.uk/nhle.geojson",
                                "allowed_hosts": ["historicengland.org.uk"], "snapshot_date": "2026-07-14"}}
    def fake_fetch(url, dest, *, expected_hosts, **kw):
        pathlib.Path(dest).write_bytes(b"GEOJSON"); return 7
    path = _snapshot.download_snapshot("historic_england", tmp_path, config=cfg, fetch_fn=fake_fetch, enabled=True)
    meta = json.loads(pathlib.Path(str(path) + ".meta.json").read_text())
    assert meta["sha256"] == hashlib.sha256(b"GEOJSON").hexdigest() and meta["size"] == 7
    _snapshot.verify_sha256_sidecar(path)                        # round-trips
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd pipeline && uv run python -m pytest tests/test_register_snapshot.py -q`
Expected: FAIL — `fetch.get_to_file` / `mt_pipeline.extractors._snapshot` not defined.

- [ ] **Step 3: Add `fetch.get_to_file`**

Append to `pipeline/src/mt_pipeline/fetch.py` (reuses the existing `_opener`/`_AllowlistRedirect`/`FetchError`/`MAX_RESPONSE_BYTES` from A1b — do NOT re-declare them):
```python
def get_to_file(url: str, dest, *, expected_hosts: set[str], max_bytes: int = MAX_RESPONSE_BYTES,
                timeout: int = 30, deadline: int = 120) -> int:
    """Stream url -> dest through the ONE protected opener (https + host allowlist re-validated on
    every redirect hop by _AllowlistRedirect), byte-capped and deadline-bounded. Counterpart of
    get_json for large files. Single-sources the SSRF-critical opener — never a second open path."""
    import time
    if not _validate_target(url, expected_hosts):
        raise FetchError(f"refusing non-https or off-allowlist url: {url}")
    start = time.monotonic()
    written = 0
    try:
        resp = _opener(expected_hosts).open(url, timeout=timeout)   # redirects re-validated here
    except urllib.error.HTTPError as e:                             # _AllowlistRedirect raised on a bad hop
        raise FetchError(f"blocked redirect or http error: {e}") from e
    enc = (resp.headers.get("Content-Encoding") or "").lower()
    if enc and enc not in ("identity",):
        raise FetchError(f"unexpected Content-Encoding: {enc}")
    with open(dest, "wb") as out:
        while True:
            if time.monotonic() - start > deadline:
                raise FetchError("exceeded total download deadline (slowloris)")
            chunk = resp.read(1 << 16)
            if not chunk:
                break
            written += len(chunk)
            if written > max_bytes:
                raise FetchError(f"response exceeded max_bytes={max_bytes}")
            out.write(chunk)
    return written
```
*(`_AllowlistRedirect.redirect_request` raises `FetchError("blocked redirect ...")` when a hop leaves the allowlist — A1b's behaviour; the test drives a real 302 through this path. If A1b surfaces the block as an `HTTPError`, the `except` above normalizes it to a `FetchError` whose message contains "blocked redirect".)*

- [ ] **Step 4: Implement `_snapshot.py`**

`pipeline/src/mt_pipeline/extractors/_snapshot.py`:
```python
"""Shared register-snapshot acquisition + provenance. Acquisition is SSRF-safe (via A1b's one
protected opener through fetch.get_to_file), byte-capped, deadline-bounded, injected for tests.
extract() elsewhere is a pure function of the local snapshot; the sidecar is untrusted (Principle 10)."""
from __future__ import annotations

import hashlib
import json
import logging
import pathlib

from .. import fetch

MAX_SIDECAR_BYTES = 64 * 1024
_log = logging.getLogger(__name__)


class SnapshotError(Exception):
    pass


class SnapshotParseError(SnapshotError):
    """The snapshot FILE could not be parsed (truncated/garbage) — a loud, clean abort."""


class ProvenanceError(SnapshotError):
    pass


def _sha256_file(path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def download_snapshot(source_key, dest_dir, *, config, fetch_fn=fetch.get_to_file, enabled=False) -> pathlib.Path:
    entry = config[source_key]
    dest = pathlib.Path(dest_dir) / f"{source_key}.snapshot"
    if not enabled:
        _log.info("acquisition disabled for %s — expecting a pre-placed snapshot at %s", source_key, dest)
        return dest
    size = fetch_fn(entry["url"], dest, expected_hosts=set(entry["allowed_hosts"]),
                    max_bytes=entry.get("max_bytes", fetch.MAX_RESPONSE_BYTES))
    sidecar = {"source_url": entry["url"], "snapshot_date": entry.get("snapshot_date"),
               "sha256": _sha256_file(dest), "size": size}
    pathlib.Path(str(dest) + ".meta.json").write_text(json.dumps(sidecar, sort_keys=True))
    return dest


def verify_sha256_sidecar(snapshot_path) -> None:
    meta_path = pathlib.Path(str(snapshot_path) + ".meta.json")
    if not meta_path.exists():
        _log.warning("no provenance sidecar for %s — proceeding (hand-placed dev file)", snapshot_path)
        return
    if meta_path.stat().st_size > MAX_SIDECAR_BYTES:
        raise ProvenanceError(f"provenance sidecar for {snapshot_path} exceeds {MAX_SIDECAR_BYTES} bytes")
    try:
        meta = json.loads(meta_path.read_text())
    except (ValueError, RecursionError) as e:
        raise ProvenanceError(f"unparseable provenance sidecar for {snapshot_path}: {e}") from e
    if not isinstance(meta, dict) or not isinstance(meta.get("sha256"), str):
        raise ProvenanceError(f"provenance sidecar for {snapshot_path} lacks a string 'sha256'")
    actual = _sha256_file(snapshot_path)
    if actual != meta["sha256"]:
        raise ProvenanceError(f"sha256 mismatch for {snapshot_path}: {actual} != {meta['sha256']}")
```

- [ ] **Step 5: Run to verify it passes**

Run: `cd pipeline && uv run python -m pytest tests/test_register_snapshot.py -q`
Expected: PASS (8 passed) — incl. the redirect-to-evil block (neuter `_AllowlistRedirect` → this reds).

- [ ] **Step 6: Commit**

```bash
git add pipeline/src/mt_pipeline/fetch.py pipeline/src/mt_pipeline/extractors/_snapshot.py \
        pipeline/tests/test_register_snapshot.py
git commit -m "Add SSRF-safe get_to_file + shared register-snapshot acquisition/provenance"
```

---

### Task 2: Historic England extractor (NHLE GeoJSON, ijson streaming, grade signal, polygon centroid)

**Files:**
- Create: `pipeline/src/mt_pipeline/extractors/historic_england.py`
- Modify: `pipeline/pyproject.toml` (add `ijson`)
- Create: `pipeline/config/a1d_sources.json`
- Test: `pipeline/tests/test_historic_england.py`, `pipeline/tests/fixtures/registers/he_sample.geojson`

**Interfaces:**
- Consumes: `ijson`, `source_record.parse`/`persist`, `_snapshot.verify_sha256_sidecar`.
- Produces:
  - `historic_england.HistoricEnglandExtractor(attribution: str)` — implements A1b's `Extractor`: `extract(region, snapshot_path, conn, *, run_id) -> int`.
  - `historic_england.make_extractor(sources_config_path) -> HistoricEnglandExtractor` (loads the attribution string from `a1d_sources.json`).
  - Each kept feature emits `source="hehle"`, `source_ref="hehle:<ListEntry>"` (`ListEntry` validated `[0-9]+`), `name` from `properties.Name` (bounded), `props = {"grade": <str>}` when present (the §4 heritage-grade signal). GeoJSON `coordinates` are `[lon, lat]`; **Point** → direct; **Polygon/MultiPolygon** → arithmetic-mean of the **outer ring**, closing vertex dropped. De-duped by `source_ref`, stable lexical order, per-feature skip-never-crash.

- [ ] **Step 1: Write the fixture + failing tests**

`pipeline/tests/fixtures/registers/he_sample.geojson` — a Point entry (1000001), an **asymmetric closed Polygon** entry (1000002; outer ring `[0,0],[0,2],[2,2],[4,0],[0,0]` in `[lon,lat]` → dedup-mean `lon=1.5, lat=1.0`, distinct from bbox-center `lon=2.0`), a non-digit ListEntry (skipped), and a name-less entry (skipped by A1):
```json
{"type": "FeatureCollection", "features": [
  {"type": "Feature", "properties": {"ListEntry": "1000001", "Name": "Church of St Mary", "Grade": "I"},
   "geometry": {"type": "Point", "coordinates": [-0.12, 51.5]}},
  {"type": "Feature", "properties": {"ListEntry": "1000002", "Name": "Old Guildhall", "Grade": "II*"},
   "geometry": {"type": "Polygon", "coordinates": [[[0.0,0.0],[0.0,2.0],[2.0,2.0],[4.0,0.0],[0.0,0.0]]]}},
  {"type": "Feature", "properties": {"ListEntry": "NOT-A-NUMBER", "Name": "Bad Id", "Grade": "II"},
   "geometry": {"type": "Point", "coordinates": [-0.1, 51.4]}},
  {"type": "Feature", "properties": {"ListEntry": "1000003", "Grade": "II"},
   "geometry": {"type": "Point", "coordinates": [-0.1, 51.4]}}
]}
```

`pipeline/tests/test_historic_england.py`:
```python
import json
import pathlib
import pytest
from mt_pipeline import store
from mt_pipeline.extractors import historic_england as he

def _db(p): c = store.connect(str(p) + ".db"); store.init_schema(c); return c
FIX = pathlib.Path(__file__).parent / "fixtures/registers/he_sample.geojson"

def test_extracts_point_and_polygon_centroid_with_grade(tmp_path):
    conn = _db(tmp_path / "w")
    n = he.HistoricEnglandExtractor("© Historic England, OGL v3.0").extract("uk", FIX, conn, run_id="r1")
    rows = conn.execute("SELECT source_ref, name, lat, lon FROM source_records ORDER BY source_ref").fetchall()
    assert n == 2                                        # 1000001 + 1000002; non-digit id + name-less skipped
    assert rows[0][0] == "hehle:1000001" and rows[1][0] == "hehle:1000002"
    assert abs(rows[0][2] - 51.5) < 1e-9 and abs(rows[0][3] + 0.12) < 1e-9    # point: lat, lon (from [lon,lat])
    # polygon outer ring [0,0],[0,2],[2,2],[4,0] (closing vertex dropped): mean lon=1.5, lat=1.0.
    # a bbox-center impl would give lon=2.0 and FAIL here.
    assert abs(rows[1][2] - 1.0) < 1e-9 and abs(rows[1][3] - 1.5) < 1e-9

def test_grade_rides_in_props_as_the_heritage_signal(tmp_path):
    conn = _db(tmp_path / "w")
    he.HistoricEnglandExtractor("attr").extract("uk", FIX, conn, run_id="r1")
    props = json.loads(conn.execute("SELECT props_json FROM source_records WHERE source_ref='hehle:1000001'").fetchone()[0])
    assert props["grade"] == "I"

def test_make_extractor_loads_attribution(tmp_path):
    cfg = pathlib.Path(__file__).parents[1] / "config/a1d_sources.json"
    x = he.make_extractor(cfg)
    assert "Historic England" in x.attribution and "OGL" in x.attribution.upper()
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd pipeline && uv run python -m pytest tests/test_historic_england.py -q`
Expected: FAIL — module/`HistoricEnglandExtractor` not defined.

- [ ] **Step 3: Add `ijson` dep + the bootstrap config + implement**

Add to `pipeline/pyproject.toml` `dependencies`: `"ijson>=3.2"`. Then `uv sync`.

`pipeline/config/a1d_sources.json`:
```json
{
  "_header": "BOOTSTRAP: register source endpoints + attribution. Ops updates URLs without a code change. HE=OGL v3.0 (attribution REQUIRED); Open Plaques=CC0.",
  "historic_england": {
    "url": "https://services.historicengland.org.uk/nhle/national-heritage-list-for-england.geojson",
    "allowed_hosts": ["services.historicengland.org.uk", "historicengland.org.uk"],
    "snapshot_date": null,
    "license": "OGL-3.0",
    "attribution": "Contains Historic England data licensed under the Open Government Licence v3.0."
  },
  "open_plaques": {
    "url": "https://openplaques.org/data/all_plaques.json",
    "allowed_hosts": ["openplaques.org"],
    "snapshot_date": null,
    "license": "CC0-1.0",
    "attribution": "Plaque data from Open Plaques (openplaques.org), released under CC0 1.0."
  }
}
```

`pipeline/src/mt_pipeline/extractors/historic_england.py`:
```python
"""Historic England (NHLE) extractor: streams the register GeoJSON with ijson (bounded memory
over ~400k entries), emits hehle:<ListEntry> with the listing grade (§4 heritage-designation
signal), and computes a deterministic outer-ring centroid for polygons. GeoJSON is WGS84 by
RFC 7946, so no projection transform. Every field bounded before A1's source_record.parse."""
from __future__ import annotations

import json
import logging
import pathlib
import re

import ijson

from .. import source_record
from . import _snapshot

MAX_NAME_LEN = 300
MAX_PROP_STR_LEN = 300
_LIST_ENTRY = re.compile(r"[0-9]+")
_log = logging.getLogger(__name__)


def _ring_centroid(ring):
    # ring = list of [lon, lat]; drop the repeated closing vertex, arithmetic-mean the rest.
    pts = ring[:-1] if len(ring) >= 2 and ring[0] == ring[-1] else ring
    lon = sum(p[0] for p in pts) / len(pts)
    lat = sum(p[1] for p in pts) / len(pts)
    return lat, lon


def _point_of(geometry):
    # returns (lat, lon) or raises (skipped per-feature). GeoJSON coordinates are [lon, lat].
    gtype = geometry["type"]
    coords = geometry["coordinates"]
    if gtype == "Point":
        return coords[1], coords[0]
    if gtype == "Polygon":
        return _ring_centroid(coords[0])                 # outer ring
    if gtype == "MultiPolygon":
        return _ring_centroid(coords[0][0])              # first polygon's outer ring (deterministic)
    raise ValueError(f"unsupported geometry {gtype}")


class HistoricEnglandExtractor:
    def __init__(self, attribution: str) -> None:
        self.attribution = attribution

    def extract(self, region: str, snapshot_path, conn, *, run_id: str) -> int:
        _snapshot.verify_sha256_sidecar(snapshot_path)
        records: dict[str, dict] = {}
        dropped = 0
        try:
            with open(snapshot_path, "rb") as f:
                for feat in ijson.items(f, "features.item"):   # STREAMING: one feature at a time
                    try:
                        props = feat.get("properties") or {}
                        raw_id = str(props.get("ListEntry", ""))
                        if not _LIST_ENTRY.fullmatch(raw_id):
                            dropped += 1; continue
                        ref = f"hehle:{raw_id}"
                        if ref in records:
                            continue
                        lat, lon = _point_of(feat["geometry"])
                        name = str(props.get("Name") or "")[:MAX_NAME_LEN]
                        out = {}
                        grade = props.get("Grade")
                        if isinstance(grade, str):
                            out["grade"] = grade[:MAX_PROP_STR_LEN]
                        records[ref] = {"lat": lat, "lon": lon, "name": name, "props": out}
                    except Exception as e:                     # one bad feature never aborts the stream
                        dropped += 1
                        _log.debug("skipped HE feature: %s: %s", type(e).__name__, e)
        except (ijson.JSONError, ValueError) as e:             # file-level unparseable → loud typed abort
            raise _snapshot.SnapshotParseError(f"could not parse NHLE GeoJSON {snapshot_path}: {e}") from e
        if dropped:
            _log.warning("HE extract %s: skipped %d malformed feature(s)", snapshot_path, dropped)
        count = 0
        for ref in sorted(records):
            r = records[ref]
            try:
                rec = source_record.parse(region=region, source="hehle", source_ref=ref,
                                          name=r["name"], lat=r["lat"], lon=r["lon"], props=r["props"])
            except source_record.SourceRecordError:
                continue
            source_record.persist(conn, rec, run_id=run_id)
            count += 1
        return count


def make_extractor(sources_config_path) -> HistoricEnglandExtractor:
    cfg = json.loads(pathlib.Path(sources_config_path).read_text())
    return HistoricEnglandExtractor(cfg["historic_england"]["attribution"])
```
*(`ijson.items(f, "features.item")` yields each feature dict from the `features` array without loading the whole FeatureCollection — bounded memory. Verify the `ijson.JSONError` symbol against the installed version in the feasibility run.)*

- [ ] **Step 4: Run to verify it passes**

Run: `cd pipeline && uv run python -m pytest tests/test_historic_england.py -q`
Expected: PASS — point + polygon-centroid `(lat 1.0, lon 1.5)`, grade signal, attribution loaded.

- [ ] **Step 5: Commit**

```bash
git add pipeline/src/mt_pipeline/extractors/historic_england.py pipeline/config/a1d_sources.json \
        pipeline/pyproject.toml pipeline/tests/fixtures/registers/he_sample.geojson \
        pipeline/tests/test_historic_england.py
git commit -m "Add Historic England NHLE extractor (ijson streaming, grade signal, outer-ring centroid)"
```

---

### Task 3: Historic England edge-hardening tests (hostile GeoJSON, skip-never-crash, teeth)

**Files:**
- Test: `pipeline/tests/test_historic_england.py` (append)

**Interfaces:** consumes Task 2. Pins the §5.5 binding-carry-in invariants and the centroid teeth.

- [ ] **Step 1: Write the hardening tests**

`test_historic_england.py` (append):
```python
def _geojson(features):
    return '{"type":"FeatureCollection","features":[' + ",".join(features) + "]}"

def test_corrupt_geojson_is_a_loud_typed_error(tmp_path):
    bad = tmp_path / "b.geojson"; bad.write_text('{"type":"FeatureCollection","features":[ NOT JSON')
    with pytest.raises(he._snapshot.SnapshotParseError):
        he.HistoricEnglandExtractor("attr").extract("uk", bad, _db(tmp_path / "b"), run_id="r1")

def test_hostile_grade_length_is_bounded(tmp_path):
    f = ('{"type":"Feature","properties":{"ListEntry":"1000009","Name":"X","Grade":"'
         + "z" * 5000 + '"},"geometry":{"type":"Point","coordinates":[-0.1,51.4]}}')
    p = tmp_path / "g.geojson"; p.write_text(_geojson([f]))
    conn = _db(tmp_path / "g")
    he.HistoricEnglandExtractor("attr").extract("uk", p, conn, run_id="r1")
    props = json.loads(conn.execute("SELECT props_json FROM source_records").fetchone()[0])
    assert len(props["grade"]) <= he.MAX_PROP_STR_LEN

def test_malformed_geometry_feature_is_skipped_not_crashed(tmp_path):
    good = ('{"type":"Feature","properties":{"ListEntry":"1000010","Name":"Good"},'
            '"geometry":{"type":"Point","coordinates":[-0.1,51.4]}}')
    bad = '{"type":"Feature","properties":{"ListEntry":"1000011","Name":"NoGeom"},"geometry":null}'
    p = tmp_path / "m.geojson"; p.write_text(_geojson([bad, good]))
    conn = _db(tmp_path / "m")
    assert he.HistoricEnglandExtractor("attr").extract("uk", p, conn, run_id="r1") == 1   # bad skipped, good kept

def test_polygon_centroid_is_arithmetic_mean_not_bbox(tmp_path):
    # asymmetric closed ring: mean lon=1.5, bbox-center lon=2.0. Neuter _ring_centroid -> bbox and this reds.
    f = ('{"type":"Feature","properties":{"ListEntry":"1000012","Name":"Poly"},'
         '"geometry":{"type":"Polygon","coordinates":[[[0.0,0.0],[0.0,2.0],[2.0,2.0],[4.0,0.0],[0.0,0.0]]]}}')
    p = tmp_path / "p.geojson"; p.write_text(_geojson([f]))
    conn = _db(tmp_path / "p")
    he.HistoricEnglandExtractor("attr").extract("uk", p, conn, run_id="r1")
    lon = conn.execute("SELECT lon FROM source_records WHERE source_ref='hehle:1000012'").fetchone()[0]
    assert abs(lon - 1.5) < 1e-9

def test_deterministic_same_file_same_records(tmp_path):
    ca = _db(tmp_path / "a"); cb = _db(tmp_path / "b")
    he.HistoricEnglandExtractor("attr").extract("uk", FIX, ca, run_id="r1")
    he.HistoricEnglandExtractor("attr").extract("uk", FIX, cb, run_id="r2")
    q = "SELECT source_ref, lat, lon FROM source_records ORDER BY id"
    assert ca.execute(q).fetchall() == cb.execute(q).fetchall()
```

- [ ] **Step 2: Run + commit**

Run: `cd pipeline && uv run python -m pytest tests/test_historic_england.py -q`
Expected: PASS (all HE tests).

```bash
git add pipeline/tests/test_historic_england.py
git commit -m "Add Historic England edge-hardening tests (corrupt file, grade bound, skip-never-crash, centroid teeth)"
```

---

### Task 4: Open Plaques extractor (JSON dump, plaque-presence signal, name derivation)

**Files:**
- Create: `pipeline/src/mt_pipeline/extractors/open_plaques.py`
- Test: `pipeline/tests/test_open_plaques.py`, `pipeline/tests/fixtures/registers/plaques_sample.json`

**Interfaces:**
- Consumes: `source_record.parse`/`persist`, `_snapshot.verify_sha256_sidecar`.
- Produces:
  - `open_plaques.OpenPlaquesExtractor(attribution: str)` — implements `Extractor`.
  - `open_plaques.make_extractor(sources_config_path) -> OpenPlaquesExtractor`.
  - Each geolocated plaque emits `source="plaque"`, `source_ref="plaque:openplaques/<id>"` (`id` validated `[0-9]+`), `name` derived from `title` → else `lead_subject_name` → else the bounded `inscription` (a non-empty name is required or A1 skips it), `props = {"inscription"?, "lead_subject"?}`. Plaques with null/missing coordinates are skipped. De-duped by `source_ref`, stable lexical order, per-feature skip-never-crash. **The plaque's presence is the §4 signal** (A4 detects a `plaque:` ref on a clustered place).

- [ ] **Step 1: Write the fixture + failing tests**

`pipeline/tests/fixtures/registers/plaques_sample.json` — a geolocated plaque (9876), a null-coord plaque (skipped), a non-digit id (skipped), a title-less plaque (name from lead subject):
```json
[
  {"id": 9876, "title": "Ada Lovelace plaque", "inscription": "Ada Lovelace lived here",
   "lead_subject_name": "Ada Lovelace", "latitude": 51.52, "longitude": -0.14},
  {"id": 9999, "title": "Ungeolocated", "inscription": "somewhere", "latitude": null, "longitude": null},
  {"id": "bad-id", "title": "Bad", "latitude": 51.5, "longitude": -0.1},
  {"id": 9877, "title": null, "inscription": "In memory", "lead_subject_name": "Grace Hopper",
   "latitude": 51.53, "longitude": -0.15}
]
```

`pipeline/tests/test_open_plaques.py`:
```python
import json
import pathlib
import pytest
from mt_pipeline import store
from mt_pipeline.extractors import open_plaques as op

def _db(p): c = store.connect(str(p) + ".db"); store.init_schema(c); return c
FIX = pathlib.Path(__file__).parent / "fixtures/registers/plaques_sample.json"

def test_extracts_geolocated_plaques_skips_ungeolocated_and_bad_id(tmp_path):
    conn = _db(tmp_path / "w")
    n = op.OpenPlaquesExtractor("CC0").extract("uk", FIX, conn, run_id="r1")
    rows = conn.execute("SELECT source_ref, name FROM source_records ORDER BY source_ref").fetchall()
    assert n == 2                                        # 9876 + 9877; null-coord + bad-id skipped
    assert rows[0][0] == "plaque:openplaques/9876" and rows[1][0] == "plaque:openplaques/9877"

def test_name_falls_back_to_lead_subject_when_title_missing(tmp_path):
    conn = _db(tmp_path / "w")
    op.OpenPlaquesExtractor("CC0").extract("uk", FIX, conn, run_id="r1")
    name = conn.execute("SELECT name FROM source_records WHERE source_ref='plaque:openplaques/9877'").fetchone()[0]
    assert name == "Grace Hopper"

def test_inscription_rides_in_props(tmp_path):
    conn = _db(tmp_path / "w")
    op.OpenPlaquesExtractor("CC0").extract("uk", FIX, conn, run_id="r1")
    props = json.loads(conn.execute("SELECT props_json FROM source_records WHERE source_ref='plaque:openplaques/9876'").fetchone()[0])
    assert "Ada Lovelace" in props["inscription"]
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd pipeline && uv run python -m pytest tests/test_open_plaques.py -q`
Expected: FAIL — module/`OpenPlaquesExtractor` not defined.

- [ ] **Step 3: Implement**

`pipeline/src/mt_pipeline/extractors/open_plaques.py`:
```python
"""Open Plaques extractor: the Open Plaques JSON dump → plaque:openplaques/<id>. The plaque's
presence is the §4 'plaque presence' signal; inscription/subject ride in props. Ungeolocated
plaques are skipped. Every field bounded before A1's source_record.parse. CC0 data."""
from __future__ import annotations

import json
import logging
import pathlib
import re

from .. import source_record
from . import _snapshot

MAX_NAME_LEN = 300
MAX_PROP_STR_LEN = 300
_PLAQUE_ID = re.compile(r"[0-9]+")
_log = logging.getLogger(__name__)


class OpenPlaquesExtractor:
    def __init__(self, attribution: str) -> None:
        self.attribution = attribution

    def extract(self, region: str, snapshot_path, conn, *, run_id: str) -> int:
        _snapshot.verify_sha256_sidecar(snapshot_path)
        try:
            data = json.loads(pathlib.Path(snapshot_path).read_text())
        except (ValueError, RecursionError) as e:                 # file-level unparseable → loud abort
            raise _snapshot.SnapshotParseError(f"could not parse Open Plaques JSON {snapshot_path}: {e}") from e
        if not isinstance(data, list):
            raise _snapshot.SnapshotParseError("Open Plaques dump must be a JSON array")
        records: dict[str, dict] = {}
        dropped = 0
        for item in data:
            try:
                if not isinstance(item, dict):
                    dropped += 1; continue
                raw_id = str(item.get("id", ""))
                if not _PLAQUE_ID.fullmatch(raw_id):
                    dropped += 1; continue
                ref = f"plaque:openplaques/{raw_id}"
                if ref in records:
                    continue
                lat, lon = item.get("latitude"), item.get("longitude")
                if lat is None or lon is None:
                    dropped += 1; continue                        # ungeolocated plaque
                title = item.get("title")
                subject = item.get("lead_subject_name")
                inscription = item.get("inscription")
                name = next((str(v)[:MAX_NAME_LEN] for v in (title, subject, inscription) if isinstance(v, str) and v.strip()), "")
                out = {}
                if isinstance(inscription, str):
                    out["inscription"] = inscription[:MAX_PROP_STR_LEN]
                if isinstance(subject, str):
                    out["lead_subject"] = subject[:MAX_PROP_STR_LEN]
                records[ref] = {"lat": lat, "lon": lon, "name": name, "props": out}
            except Exception as e:
                dropped += 1
                _log.debug("skipped plaque: %s: %s", type(e).__name__, e)
        if dropped:
            _log.warning("Open Plaques extract %s: skipped %d record(s)", snapshot_path, dropped)
        count = 0
        for ref in sorted(records):
            r = records[ref]
            try:
                rec = source_record.parse(region=region, source="plaque", source_ref=ref,
                                          name=r["name"], lat=r["lat"], lon=r["lon"], props=r["props"])
            except source_record.SourceRecordError:
                continue
            source_record.persist(conn, rec, run_id=run_id)
            count += 1
        return count


def make_extractor(sources_config_path) -> OpenPlaquesExtractor:
    cfg = json.loads(pathlib.Path(sources_config_path).read_text())
    return OpenPlaquesExtractor(cfg["open_plaques"]["attribution"])
```

- [ ] **Step 4: Run + hardening + commit**

Add these hardening tests to `test_open_plaques.py`, then run:
```python
def test_corrupt_dump_is_a_loud_typed_error(tmp_path):
    bad = tmp_path / "b.json"; bad.write_text("{ not json")
    with pytest.raises(op._snapshot.SnapshotParseError):
        op.OpenPlaquesExtractor("CC0").extract("uk", bad, _db(tmp_path / "b"), run_id="r1")

def test_non_array_dump_is_rejected(tmp_path):
    bad = tmp_path / "o.json"; bad.write_text('{"plaques": []}')
    with pytest.raises(op._snapshot.SnapshotParseError):
        op.OpenPlaquesExtractor("CC0").extract("uk", bad, _db(tmp_path / "o"), run_id="r1")

def test_hostile_inscription_length_bounded(tmp_path):
    p = tmp_path / "h.json"
    p.write_text(json.dumps([{"id": 5, "title": "T", "inscription": "z" * 5000, "latitude": 51.5, "longitude": -0.1}]))
    conn = _db(tmp_path / "h")
    op.OpenPlaquesExtractor("CC0").extract("uk", p, conn, run_id="r1")
    props = json.loads(conn.execute("SELECT props_json FROM source_records").fetchone()[0])
    assert len(props["inscription"]) <= op.MAX_PROP_STR_LEN
```

Run: `cd pipeline && uv run python -m pytest tests/test_open_plaques.py -q`
Expected: PASS (all Open Plaques tests).

```bash
git add pipeline/src/mt_pipeline/extractors/open_plaques.py \
        pipeline/tests/fixtures/registers/plaques_sample.json pipeline/tests/test_open_plaques.py
git commit -m "Add Open Plaques extractor (plaque-presence signal, name derivation, hardened JSON parse)"
```

---

### Task 5: Register both extractors in the extract stage

**Files:**
- Modify: `pipeline/src/mt_pipeline/extract_stage.py`
- Test: `pipeline/tests/test_extract_stage_registers.py`

**Interfaces:**
- Extend `build_registry` to also register `historic_england` and `open_plaques` (defaulting the sources-config path to the shipped `a1d_sources.json` so both are **always registered** — the A1c silent-skip lesson). `run_extract` is unchanged.

- [ ] **Step 1: Write the failing test**

`pipeline/tests/test_extract_stage_registers.py`:
```python
import pathlib
from dataclasses import dataclass
from mt_pipeline import store, extract_stage

REG_FIX = pathlib.Path(__file__).parent / "fixtures/registers"

@dataclass(frozen=True)
class RC:
    region_id: str
    sources: dict

def _reg():
    return extract_stage.build_registry(
        allowlist_path=pathlib.Path(__file__).parents[1] / "config/wikidata_class_allowlist.json",
        languages={"en"})

def test_registers_are_registered_by_default_and_run_when_enabled(tmp_path):
    conn = store.connect(tmp_path / "w.db"); store.init_schema(conn)
    reg = _reg()                                        # no explicit register-config path
    cfg = RC("uk", {"wikidata": False, "wikipedia": False, "osm": False,
                    "historic_england": True, "open_plaques": True})
    counts = extract_stage.run_extract(conn, cfg, {
        "historic_england": str(REG_FIX / "he_sample.geojson"),
        "open_plaques": str(REG_FIX / "plaques_sample.json"),
    }, run_id="r1", registry=reg)
    assert counts == {"historic_england": 2, "open_plaques": 2}

def test_national_register_object_is_not_treated_as_enabled(tmp_path):
    # enabled_for uses `is True`; the Malaysia national_register object must NOT register/run.
    conn = store.connect(tmp_path / "w.db"); store.init_schema(conn)
    reg = _reg()
    cfg = RC("malaysia", {"historic_england": False, "open_plaques": True,
                          "national_register": {"id": "malaysia_heritage", "enabled": False}})
    counts = extract_stage.run_extract(conn, cfg, {"open_plaques": str(REG_FIX / "plaques_sample.json")},
                                       run_id="r1", registry=reg)
    assert counts == {"open_plaques": 2}                # national_register absent — object is not `is True`
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd pipeline && uv run python -m pytest tests/test_extract_stage_registers.py -q`
Expected: FAIL — `build_registry` does not register the register extractors.

- [ ] **Step 3: Modify `build_registry`**

In `pipeline/src/mt_pipeline/extract_stage.py`, extend `build_registry` (composes with A1c's `osm_tag_config_path` default — keep it):
```python
import pathlib
from .extractors import historic_england, open_plaques

DEFAULT_A1D_SOURCES = pathlib.Path(__file__).resolve().parents[2] / "config/a1d_sources.json"

def build_registry(allowlist_path, languages, *, osm_tag_config_path=None, a1d_sources_path=None):
    reg = Registry()
    reg.register("wikidata", wikidata.make_extractor(allowlist_path))
    reg.register("wikipedia", WikipediaExtractor(languages))
    reg.register("osm", osm_extractor.make_extractor(osm_tag_config_path or DEFAULT_OSM_TAG_CONFIG))
    sources = a1d_sources_path or DEFAULT_A1D_SOURCES
    reg.register("historic_england", historic_england.make_extractor(sources))
    reg.register("open_plaques", open_plaques.make_extractor(sources))
    return reg
```

- [ ] **Step 4: Run + full suite + commit**

Run: `cd pipeline && uv run python -m pytest -q`
Expected: PASS (all A1 + A1b + A1c + A1d tests green).

```bash
git add pipeline/src/mt_pipeline/extract_stage.py pipeline/tests/test_extract_stage_registers.py
git commit -m "Register Historic England + Open Plaques extractors in the extract stage"
```

---

### Task 6: Malaysia heritage-register feasibility spike (WRITTEN VERDICT — not code)

**Files:**
- Create: `docs/superpowers/spikes/2026-07-15-wp-a1d-malaysia-register-feasibility.md`

**This task produces a written verdict document, not code — there is no TDD cycle.** Spec §4: the Malaysia national heritage register "is included only if machine-readable, and nothing depends on it." The shipped `contracts/regions/malaysia.json` already encodes the pending-verdict default: `"national_register": {"id": "malaysia_heritage", "enabled": false}`. The spike's job is to **produce the verdict that either keeps that default or recommends a follow-up** — never to add code in A1d.

- [ ] **Step 1: Investigate machine-readability (the spike method)**

Check, in order, whether Malaysia's national heritage register (Jabatan Warisan Negara / Department of National Heritage — the *Daftar Warisan Kebangsaan* under the National Heritage Act 2005) is available as **structured, machine-readable data**:
1. **Malaysia's open-data portal** (`data.gov.my`) — search for a heritage/`warisan` dataset (CSV/JSON/API).
2. **Jabatan Warisan Negara's own site/portal** — is the register a downloadable dataset, or only HTML pages / PDF gazette notifications?
3. **A national geoportal** (e.g. MyGeoportal) — is there a heritage layer with per-site coordinates and stable ids?
4. **Wikidata coverage as a proxy/fallback** — how many Malaysian heritage sites already carry a QID (already covered by the Wikidata extractor's union, so not a new source).

- [ ] **Step 2: Apply the acceptance criteria**

"**Machine-readable**" (the bar for inclusion) requires ALL of: (a) a **downloadable structured dataset or a documented API** (not PDF/HTML scraping); (b) a **stable per-entry identifier** (for an append-only `source_ref` prefix); (c) **coordinates or reliably geocodable addresses**; (d) a **usable licence** for redistribution/derivation. Anything less → **NOT machine-readable → excluded**.

- [ ] **Step 3: Write the verdict document with this exact structure**

```markdown
# WP-A1d Spike — Malaysia National Heritage Register Feasibility

**Question:** Is Malaysia's national heritage register machine-readable enough to include as a pipeline source? (spec §4: included only if machine-readable; nothing depends on it.)

## Sources investigated
(one row per source from Step 1: name, URL, format observed, per-entry id?, coordinates?, licence — with the date checked)

## Acceptance criteria (Step 2) — met / not met
(a) structured dataset/API · (b) stable id · (c) coordinates/geocodable · (d) usable licence

## VERDICT: {MACHINE-READABLE | PARTIAL | NOT MACHINE-READABLE}

## Consequence
- NOT machine-readable (default) → register stays EXCLUDED; `malaysia.json` `national_register.enabled` stays `false`; Malaysia recall relies on Wikidata + OSM + Open Plaques, and §4's "Malaysia sanity floor" (heritage designations from OSM/Wikidata, tag rarity, article existence, image availability) plus WP-A5's LLM-off eval carry ranking. Nothing to build.
- MACHINE-READABLE → recommend a follow-up **WP-A1d-malaysia-register**: (1) an **append-only** A0 addition — new `source_ref` prefix (e.g. `myheritage:<id>`), priority entry (append LAST), conformance vectors — never altering existing grammars; (2) a new extractor on the A1 interface; (3) flip `national_register.enabled` to `true`; (4) resolve the `enabled_for` nested-`{enabled}`-object seam (an A1b/A2 design item — `is True` does not match the object today). This is scoped as its own WP, not folded into A1d.

## Recommendation
(one paragraph: the verdict + the single next action)
```

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/spikes/2026-07-15-wp-a1d-malaysia-register-feasibility.md
git commit -m "Add Malaysia heritage-register feasibility spike (written verdict; default-excluded per §4)"
```

---

## Review Record

**Author self-review** — deliverables map to tasks: shared SSRF-safe acquisition + provenance sidecar (T1); Historic England extractor with the grade §4 signal, `ijson` streaming, and outer-ring centroid (T2) + edge-hardening (T3); Open Plaques extractor with the plaque-presence signal (T4); registry wiring, always-registered (T5); the Malaysia written-verdict spike, default-excluded (T6). Implements A1's `parse` interface; extends A1b's registry; consumes (not invents) the source config; emits `hehle:`/`plaque:openplaques/` refs already in A0's frozen grammar (**no A0 change**). **One vandalized record never crashes a run** (per-feature guard + dropped-feature counter). Deterministic (stable `source_ref` order; outer-ring-mean centroid with closing-vertex dedup). §4 signals emitted (grade, plaque presence), never scored (A4). Streaming, bounded-memory NHLE parse (honest — `ijson`, not `json.loads`).

**Ratifications (fable, thread `wp/a1d`)** — HE + Open Plaques extractors + Malaysia written-verdict spike; BUILD acquisition with A1b's per-hop redirect discipline (neuter-goes-red redirect test included); GeoJSON/WGS84 + outer-ring-mean + closing-vertex dedup + `ijson` honest memory; spike = written verdict, default-excluded, follow-up-only; no A0 change; OGL attribution plan-carried, surfacing routed to A7's manifest (issue #11).

**Global-constraint / cross-package flags surfaced:**
- **Blocked on A1b impl landing** (registry, `extract_stage`, `fetch`) — same posture as A1c; stated honestly, not over-claimed.
- **Region-config `sources` type**: pinned to the **shipped** schema (bool or `{id,enabled}` object; **null not used**; absence allowed). The stale `null` usage in the A0-plan draft and A1b's fixtures was flagged time-sensitively; codex's A1b impl is now pinned to the shipped form.
- **`enabled_for` nested-object seam**: today `sources.get(s) is True` correctly skips `national_register` (an object) — right for the spike. A future register extractor needs `enabled_for` to understand the `{enabled}` shape; an **A1b/A2 seam, flagged not edited from A1d**.
- **OGL attribution surfacing** → **WP-A7 manifest as per-source attribution carrier; A7 design input on issue #11** (app credits screen is B-track).
- **`fetch.get_to_file`** single-sources the SSRF-critical opener in A1b (no duplicated `_AllowlistRedirect`) — coordinate with codex so the addition lands in A1b's `fetch.py`.
- **Determinism guard coverage**: all A1d code lives under `extractors/` (A1b's recursive rglob guard covers it once landed); config is data. No guard gap.

**Adversarial review (per AGENTS.md gate) — TO RUN before PR, with the strengthened checklist:** (1) fixes verified on the **executed path**; (2) tests have **teeth** — *neuter the fix, confirm the test goes red* (the redirect-allowlist block, the polygon centroid vs bbox, the grade/inscription length bounds, the sidecar sha256 mismatch, the `is True` register gate); (3) **every strict comparison gets a test a loose comparison fails**; (4) the **feasibility critic installs `ijson`** into a scratch venv and runs the real streaming parse against `he_sample.geojson` — **if the sandbox blocks the install, request escalation explicitly (do not silently degrade)** — verifying `ijson.items(f, "features.item")`, the exact `ijson` error symbol, the `[lon,lat]` order, and the outer-ring centroid `(lat 1.0, lon 1.5)`; and drives a real 302 through `fetch.get_to_file` to confirm the off-allowlist redirect is blocked.

**Cross-package needs surfaced** — `WP-A1d-malaysia-register` (only if the spike says machine-readable: append-only A0 prefix + extractor + `enabled_for` seam); A2 clusters `hehle:`/`plaque:` refs onto places (register refs join the union-of-refs registry, §5.2); A4 consumes `props["grade"]` (heritage-designation signal) and plaque presence; A7's manifest carries per-source attribution (issue #11); `fetch.get_to_file` lands in A1b's `fetch.py`.
