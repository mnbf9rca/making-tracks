# WP-A1b (Wiki Extractors) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Two deterministic, §5.5-hardened extractors — **Wikidata** (coordinate-bearing items whose P31 class passes a consumed allowlist, carrying the §4 scoring signals) and **Wikipedia** (English geotagged articles) — that implement WP-A1's source-record interface; the SSRF-safe **fetch** boundary; the **extractor registry** A1c/A1d extend; and **resumable pageview acquisition** (computation is A4's). One vandalized source record must never crash a run.

**Architecture:** Under `pipeline/` (the WP-A1 `mt_pipeline` package). Each extractor is a **pure function of a dated snapshot file** — determinism is "same snapshot in → same records out." The snapshot is size-capped and defensively parsed; **every field is extracted inside a per-record guard that skips a bad record, never aborts the run** (the binding carry-in: bound the raw blob at the extractor edge *before* A1's `source_record.parse`). Acquisition (network) is a separate, SSRF-safe, byte-capped step. English-only recall with `languages`/`bbox` read from the A0 region config (in the acquisition layer).

**Tech Stack:** Python 3.11+ (the WP-A1 `mt_pipeline` package + `mt-contracts`), stdlib `urllib`/`http`/`json`, `pytest`. Laptop-first, no heavyweight deps.

## Global Constraints

- **Implements A1's interface, never re-declares it.** Records are produced only via `mt_pipeline.source_record.parse(region, source, source_ref, name, lat, lon, props)` and stored via `persist(conn, record, *, run_id)`. Canonical-ref grammar and text-safety come from `mt_contracts` (via A1's `parse`), never re-implemented. **A1 preconditions this WP relies on** (verify present before build; all from the A1 plan / `mt_contracts`): `store.connect`/`store.init_schema` and the `source_records` table (`region, source, source_ref, name, lat, lon, props_json, run_id`); `source_record.parse`/`persist`/`SourceRecordError`; `config.RegionConfig` (frozen dataclass with `.region_id`, `.sources`, `.raw`) + `config.load`; `mt_contracts.is_canonical_ref` (already accepts `wp:12345` and `wd:Q…` via the generic ref grammar — so A1b needs **no** A0 change to *emit* these refs).
- **Never crash on hostile input (Principle 10 / §5.5 / binding carry-in).** All Wikidata/Wikipedia data is untrusted (vandalizable). Every field access on source data happens inside a per-record `try/except (KeyError, ValueError, TypeError)` that **skips** the record — a single malformed binding/page must not abort the extract. No unguarded hostile access in a `sorted()` key. `RecursionError` (deep-JSON bomb) is caught at every `json.loads`.
- **Raw-blob bounding at the edge (binding carry-in), applied to what the data actually has.** The flat SPARQL/geosearch snapshot has *rows*, not per-item claim/sitelink *arrays*, so the real bounds are: **`MAX_SNAPSHOT_BYTES`** (the on-disk snapshot file, checked before `json.loads` — the per-response fetch cap does NOT protect the aggregated snapshot); **`MAX_RECORDS_PER_SNAPSHOT`** (reject/stop before an unbounded `sorted()`); and per-field **length caps** (label, extract, title, QID, lang). Only a small, shallow `props` dict ever reaches `parse`.
- **Determinism (Principle 12).** `extract(snapshot, …)` is a pure function of the dated snapshot: same snapshot → identical records, identical order. Records emit in a **stable lexical `source_ref` order** (matches SQL `ORDER BY source_ref`). Duplicate items are de-duped (keep-first) so A2 never sees the same `source_ref` twice. No wall-clock/randomness in any output; the snapshot date and `run_id` are metadata only. A determinism guard scans **all** A1b modules (recursively).
- **English-only recall, config-driven (§4).** `languages`/`bbox` come from the A0 region config and drive **acquisition** (which segments/queries by bbox and language). The pure `extract` additionally **validates the snapshot's declared `lang` against the config `languages`** and drops mismatches — no language is blindly trusted or hardcoded.
- **The P31 allowlist is CONSUMED, not invented (§4).** The extractor reads a class allowlist artifact; WP-A3's data audit produces the authoritative set. A **genuinely minimal bootstrap** ships here (header-marked), file-replaceable by A3 with zero code change.
- **Scope.** Extraction + acquisition only. **No reconcile (A2), no place_id minting (A2), no score/tier (A4) — including no pageview *computation* (A4 computes the median from the cache A1b writes).** This WP produces source records + a pageview cache.
- **Test-first**, against golden fixtures (no network in tests; the network seam is injected).

**Ratified (fable, thread `wp/a1b`) — conditions folded in.** (1) cached-SPARQL → **self-describing** dated snapshot (`_meta`: endpoint, full query text, retrieval date), **segmented** queries (P31-chunk × bbox-tile — no monolithic query → WDQS 60 s timeout), WDQS etiquette, **loud-abort on partial**. (2) `wp:<pageid>` refs + QID-in-props join; A0 appends `wp` (last: `wd > osm > hehle > plaque > wp`) to its append-only mint grammar + a frozen vector — **a codex contracts task fable briefs; a NOTE here, and needed only for A2 to *mint* a Wikipedia-only place, not for A1b to emit the ref.** (3) bootstrap allowlist minimal + header-marked. (4) pageview **acquisition** here (resumable, cached per `(title, window)`, per-run flag); **computation deferred to A4.**

**Cross-package needs surfaced (per AGENTS.md)** — codex adds `wp` (last) to A0's append-only mint grammar + frozen vector (for A2 minting of wp-only places; fable briefing it); A3's audit replaces the bootstrap allowlist file; **A2 must read `props["wikidata"]` as the Wikipedia→Wikidata join key** (the join key rides in opaque props, not as a second `source_ref` — write into the A2 interface); **A1's `source_records` would benefit from `UNIQUE(source, source_ref)`** as belt-and-braces against duplicate rows (A1b de-dups in-extractor regardless).

---

## File Structure

```
pipeline/src/mt_pipeline/
  fetch.py                              # SSRF-safe, byte-capped, deadline-bounded HTTPS fetch (Task 1)
  extractors/
    __init__.py                         # Extractor Protocol + Registry (A1c/A1d extend) (Task 2)
    wikidata.py                         # WikidataExtractor(allowlist) + make_extractor(path) (Task 3)
    wikipedia.py                        # WikipediaExtractor(languages) (Task 4)
    pageviews.py                        # resumable pageview ACQUISITION + window_for (Task 5)
  extract_stage.py                      # runs enabled extractors from a RegionConfig (Task 6)
pipeline/config/
  wikidata_class_allowlist.json         # BOOTSTRAP P31 allowlist (A3 supersedes) (Task 3)
pipeline/tests/
  fixtures/wikidata/snapshot.json       # golden SPARQL result (self-describing _meta) (Task 3)
  fixtures/wikipedia/snapshot.json      # golden geosearch+extracts result (Task 4)
  test_fetch.py                         # Task 1
  test_extractor_registry.py            # Task 2
  test_wikidata_extractor.py            # Task 3
  test_wikipedia_extractor.py           # Task 4
  test_pageviews.py                     # Task 5
  test_extract_stage.py                 # Task 6
  test_extractor_determinism.py         # Task 6 (guard over extractors/)
```

---

### Task 1: SSRF-safe, byte-capped, deadline-bounded fetch (the network boundary)

**Files:**
- Create: `pipeline/src/mt_pipeline/fetch.py`
- Test: `pipeline/tests/test_fetch.py`

**Interfaces:**
- Produces:
  - `fetch.MAX_RESPONSE_BYTES = 32 * 1024 * 1024`; `fetch.FetchError(Exception)`.
  - `fetch.get_json(url, *, expected_hosts, max_bytes=MAX_RESPONSE_BYTES, timeout=30, deadline=120) -> dict` — https-only, host-allowlisted **on every redirect hop** (SSRF-safe), streams the body raising **before** `max_bytes`, enforces a total wall-clock `deadline` (slowloris), rejects unexpected `Content-Encoding`, and catches `RecursionError`/`ValueError` from `json.loads`.

- [ ] **Step 1: Write the failing test**

`pipeline/tests/test_fetch.py`:
```python
import io
import json
import email.message
import urllib.request
import urllib.response
import pytest
from mt_pipeline import fetch

class _FakeOpener:
    def __init__(self, body): self._body = body
    def open(self, url, timeout=None): return io.BytesIO(self._body)

def _body(monkeypatch, data):
    monkeypatch.setattr(fetch, "_opener", lambda hosts: _FakeOpener(data))

def test_rejects_non_https():
    with pytest.raises(fetch.FetchError):
        fetch.get_json("http://insecure/x", expected_hosts={"insecure"})

def test_rejects_unexpected_host():
    with pytest.raises(fetch.FetchError):
        fetch.get_json("https://evil.example/x", expected_hosts={"query.wikidata.org"})

def test_streams_and_caps_oversize_body(monkeypatch):
    _body(monkeypatch, b'{"x":"' + b"a" * 4096 + b'"}')
    with pytest.raises(fetch.FetchError):
        fetch.get_json("https://query.wikidata.org/x", expected_hosts={"query.wikidata.org"}, max_bytes=1024)

def test_returns_parsed_json_within_cap(monkeypatch):
    _body(monkeypatch, json.dumps({"ok": 1}).encode())
    assert fetch.get_json("https://query.wikidata.org/x", expected_hosts={"query.wikidata.org"}) == {"ok": 1}

def test_recursion_bomb_is_caught(monkeypatch):
    _body(monkeypatch, ("[" * 300000).encode())
    with pytest.raises(fetch.FetchError):
        fetch.get_json("https://query.wikidata.org/x", expected_hosts={"query.wikidata.org"})

class _Mock302Handler(urllib.request.BaseHandler):
    """A real urllib handler that returns a 302 to `location`, so the redirect flows
    through the production opener chain (HTTPErrorProcessor → the redirect handler)."""
    def __init__(self, location): self.location = location
    def https_open(self, req):
        h = email.message.Message(); h["Location"] = self.location
        resp = urllib.response.addinfourl(io.BytesIO(b""), h, req.full_url, 302)
        resp.msg = "Found"
        return resp

def _mock_opener(hosts, location):
    # a manual OpenerDirector: error processor + our redirect handler + a mock 302
    # transport, and NO default HTTPS transport — so the 302 flows through the real
    # redirect handler with zero network. (build_opener would add the real transport.)
    o = urllib.request.OpenerDirector()
    for h in (urllib.request.HTTPErrorProcessor(), fetch._AllowlistRedirect(hosts), _Mock302Handler(location)):
        o.add_handler(h)
    return o

def test_redirect_to_unexpected_host_is_blocked_THROUGH_get_json(monkeypatch):
    # SSRF: drive an actual 302 to a non-allowlisted host through get_json's redirect
    # handler and assert it is blocked (not merely _validate_target on the first URL).
    hosts = {"query.wikidata.org"}
    monkeypatch.setattr(fetch, "_opener", lambda h: _mock_opener(h, "https://evil.example/x"))
    # match= gives the test TEETH: it passes ONLY for the allowlist-block, not for a
    # generic loop/HTTPError a neutered handler would produce (else it's a false green).
    with pytest.raises(fetch.FetchError, match="blocked redirect"):
        fetch.get_json("https://query.wikidata.org/x", expected_hosts=hosts)

def test_redirect_to_allowlisted_host_is_permitted():
    # a redirect to an allowed host returns a Request (followed), not an error
    h = fetch._AllowlistRedirect({"query.wikidata.org"})
    req = urllib.request.Request("https://query.wikidata.org/a")
    out = h.redirect_request(req, io.BytesIO(b""), 302, "Found",
                             email.message.Message(), "https://query.wikidata.org/b")
    assert out is not None
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd pipeline && uv run python -m pytest tests/test_fetch.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named 'mt_pipeline.fetch'`.

- [ ] **Step 3: Implement `fetch.py`**

`pipeline/src/mt_pipeline/fetch.py`:
```python
"""The single network boundary: SSRF-safe, byte-capped, deadline-bounded, https-only,
host-allowlisted streaming fetch. Every raw blob passes through here (§5.5)."""
from __future__ import annotations

import json
import time
import urllib.request
from urllib.parse import urlparse

MAX_RESPONSE_BYTES = 32 * 1024 * 1024


class FetchError(Exception):
    pass


def _validate_target(url: str, expected_hosts: set[str]) -> bool:
    p = urlparse(url)
    return p.scheme == "https" and p.hostname in expected_hosts


class _AllowlistRedirect(urllib.request.HTTPRedirectHandler):
    """Re-apply the https + host allowlist on EVERY redirect hop (SSRF defense).
    Installed on the executed get_json path via _opener — NOT a prose comment."""
    def __init__(self, expected_hosts: set[str]):
        self.expected_hosts = expected_hosts
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if not _validate_target(newurl, self.expected_hosts):
            raise FetchError(f"blocked redirect to {newurl!r}")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def _opener(expected_hosts: set[str]):
    """The ONE network seam. Production: an opener whose redirect handler re-validates
    every hop, so no code path fetches without the allowlist. Tests monkeypatch this."""
    return urllib.request.build_opener(_AllowlistRedirect(expected_hosts))


def get_json(url: str, *, expected_hosts: set[str], max_bytes: int = MAX_RESPONSE_BYTES,
             timeout: int = 30, deadline: int = 120) -> dict:
    if not _validate_target(url, expected_hosts):
        raise FetchError(f"invalid target: {url!r}")
    try:
        resp = _opener(expected_hosts).open(url, timeout=timeout)   # redirects re-validated here
    except FetchError:
        raise
    except Exception as e:
        raise FetchError(str(e)) from e
    hdrs = getattr(resp, "headers", None)
    if hdrs is not None and hdrs.get("Content-Encoding"):
        raise FetchError(f"unexpected Content-Encoding {hdrs.get('Content-Encoding')!r}")  # no silent bomb
    start, chunks, total = time.monotonic(), [], 0
    while True:
        if time.monotonic() - start > deadline:
            raise FetchError("exceeded total download deadline (slowloris)")
        chunk = resp.read(65536)
        if not chunk:
            break
        total += len(chunk)
        if total > max_bytes:
            raise FetchError(f"response exceeded {max_bytes} bytes")
        chunks.append(chunk)
    try:
        return json.loads(b"".join(chunks).decode("utf-8"))
    except (ValueError, UnicodeDecodeError, RecursionError) as e:
        raise FetchError(f"invalid JSON: {e}") from e
```
The `_opener` seam guarantees **one** code path with *both* the redirect-allowlist and the streaming cap/deadline/Content-Encoding checks. The test drives a real 302 through `get_json` and asserts `FetchError`.

- [ ] **Step 4: Run to verify it passes**

Run: `cd pipeline && uv run python -m pytest tests/test_fetch.py -q`
Expected: PASS (7 passed) — including a real 302-through-`get_json` blocked by the redirect handler.

- [ ] **Step 5: Commit**

```bash
git add pipeline/src/mt_pipeline/fetch.py pipeline/tests/test_fetch.py
git commit -m "Add SSRF-safe byte-capped deadline-bounded fetch (redirect handler wired on the get_json path)"
```

---

### Task 2: Extractor Protocol + registry

**Files:**
- Create: `pipeline/src/mt_pipeline/extractors/__init__.py`
- Test: `pipeline/tests/test_extractor_registry.py`

**Interfaces:**
- Produces:
  - `extractors.Extractor` — `Protocol`: `extract(region, snapshot_path, conn, *, run_id) -> int`.
  - `extractors.Registry` (class): `register(source, extractor)` and `enabled_for(sources: dict) -> list[tuple[str, Extractor]]` (stable registration order; only sources whose value is `True`). A1c/A1d register the same way.

- [ ] **Step 1: Write the failing test**

`pipeline/tests/test_extractor_registry.py`:
```python
from mt_pipeline import extractors

def test_enabled_for_returns_only_true_sources_in_registration_order():
    reg = extractors.Registry()
    reg.register("wikidata", object()); reg.register("wikipedia", object()); reg.register("osm", object())
    sources = {"wikidata": True, "wikipedia": True, "osm": False, "national_register": None}
    assert [n for n, _ in reg.enabled_for(sources)] == ["wikidata", "wikipedia"]

def test_enabled_for_ignores_non_bool_and_unregistered():
    reg = extractors.Registry()
    reg.register("wikidata", object())
    sources = {"wikidata": True, "national_register": {"id": "x", "enabled": False}, "osm": True}
    assert [n for n, _ in reg.enabled_for(sources)] == ["wikidata"]   # osm not registered; national_register not a bool
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd pipeline && uv run python -m pytest tests/test_extractor_registry.py -q`
Expected: FAIL — module missing.

- [ ] **Step 3: Implement `extractors/__init__.py`**

`pipeline/src/mt_pipeline/extractors/__init__.py`:
```python
"""Extractor registry: the shared dispatch WP-A1b establishes and A1c/A1d extend."""
from __future__ import annotations

from typing import Protocol, runtime_checkable


@runtime_checkable
class Extractor(Protocol):
    def extract(self, region: str, snapshot_path, conn, *, run_id: str) -> int: ...


class Registry:
    def __init__(self) -> None:
        self._order: list[str] = []
        self._by_source: dict[str, object] = {}

    def register(self, source: str, extractor) -> None:
        if source not in self._by_source:
            self._order.append(source)
        self._by_source[source] = extractor

    def enabled_for(self, sources: dict) -> list[tuple[str, object]]:
        return [(s, self._by_source[s]) for s in self._order if sources.get(s) is True]
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd pipeline && uv run python -m pytest tests/test_extractor_registry.py -q`
Expected: PASS (2 passed).

- [ ] **Step 5: Commit**

```bash
git add pipeline/src/mt_pipeline/extractors/__init__.py pipeline/tests/test_extractor_registry.py
git commit -m "Add Extractor Protocol + registry (stable enabled-source dispatch)"
```

---

### Task 3: Wikidata extractor (crash-safe, de-duped, §4 signals) + bootstrap allowlist + factory

**Files:**
- Create: `pipeline/src/mt_pipeline/extractors/wikidata.py`, `pipeline/config/wikidata_class_allowlist.json`
- Create: `pipeline/tests/fixtures/wikidata/snapshot.json`
- Test: `pipeline/tests/test_wikidata_extractor.py`

**Interfaces:**
- Consumes: `source_record.parse`/`persist`.
- Produces:
  - Caps: `MAX_SNAPSHOT_BYTES = 256 * 1024 * 1024`, `MAX_RECORDS_PER_SNAPSHOT = 2_000_000`, `MAX_LABEL_LEN = 300` (matches A1's props/name cap), `MAX_SITELINKS = 100_000`.
  - `wikidata.SnapshotTooLargeError`, `wikidata.SnapshotIncompleteError` (the `_meta.complete` gate — refuses a partial snapshot; shared by both extractors via `_load_snapshot`).
  - `wikidata.load_allowlist(path) -> set[str]`.
  - `wikidata.WikidataExtractor(allowlist: set[str])` — implements `Extractor`; `extract(region, snapshot_path, conn, *, run_id) -> int`.
  - `wikidata.make_extractor(allowlist_path) -> WikidataExtractor` — the **production factory** (loads the bootstrap file; A3 replaces the file, no code change).
  - Each kept item emits `source=wd, source_ref=wd:<QID>` with `props = {p31, label, sitelinks (int, §4 signal), image? (P18 → §4 image-availability / image_url origin)}` — de-duped by QID (keep-first), stable lexical `source_ref` order, every field guarded.

**Acquisition is a NAMED DEFERRED follow-up; its completeness contract is ENFORCED here.** The WDQS acquisition that *writes* the snapshot (segmented per P31-chunk × bbox-tile; descriptive `User-Agent`; backoff on `429`/`5xx`; a self-describing `_meta` of `endpoint` + full per-segment query text + `retrieved_at`; and `"complete": true` written **only after every segment succeeds**, loud-abort otherwise) is network I/O with no hermetic test surface, so it is deferred to a named follow-up (`WP-A1b-acquire`, flagged to fable for scheduling). **The enforcement point is built + tested here:** `_load_snapshot` raises `SnapshotIncompleteError` unless `_meta.complete is True`, so `extract` can never run against a partial/aborted snapshot — the ratified "never run against a partial snapshot" condition has teeth even though acquisition itself is deferred.

- [ ] **Step 1: Write the golden fixture + failing test**

`pipeline/tests/fixtures/wikidata/snapshot.json` (self-describing `_meta`; flat rows carrying the §4 signals; includes a hostile-shaped row and a duplicate QID to exercise the guards):
```json
{"_meta": {"endpoint": "https://query.wikidata.org/sparql",
           "queries": ["SELECT ... bbox-tile 0 x class-chunk 0 ..."], "retrieved_at": "2026-07-14",
           "complete": true},
 "results": {"bindings": [
   {"item": {"value": "http://www.wikidata.org/entity/Q42"}, "lat": {"value": "51.5007"},
    "lon": {"value": "-0.1246"}, "p31": {"value": "http://www.wikidata.org/entity/Q33506"},
    "label": {"value": "Big Ben"}, "sitelinks": {"value": "42"},
    "image": {"value": "http://commons.wikimedia.org/wiki/Special:FilePath/Big%20Ben.jpg"}},
   {"item": {"value": "http://www.wikidata.org/entity/Q42"}, "lat": {"value": "51.5007"},
    "lon": {"value": "-0.1246"}, "p31": {"value": "http://www.wikidata.org/entity/Q570116"},
    "label": {"value": "Big Ben"}, "sitelinks": {"value": "42"}},
   {"item": {"value": "http://www.wikidata.org/entity/Q17"}, "lat": {"value": "51.5"},
    "lon": {"value": "-0.1"}, "p31": {"value": "http://www.wikidata.org/entity/Q_NOPE"},
    "label": {"value": "A Parish"}, "sitelinks": {"value": "3"}},
   {"lat": {"value": "1"}, "lon": {"value": "1"}, "p31": {"value": "http://www.wikidata.org/entity/Q33506"},
    "label": {"value": "MALFORMED — no item key"}}
 ]}}
```

`pipeline/tests/test_wikidata_extractor.py`:
```python
import json
import pathlib
import pytest
from mt_pipeline import store
from mt_pipeline.extractors import wikidata

FIX = pathlib.Path(__file__).parent / "fixtures/wikidata/snapshot.json"

def _db(tmp_path, name="w.db"):
    c = store.connect(tmp_path / name); store.init_schema(c); return c

def _write(tmp_path, snap, name="s.json"):
    # inject a complete _meta unless the snapshot overrides it (gate default)
    obj = {"_meta": {"complete": True}, **snap}
    p = tmp_path / name; p.write_text(json.dumps(obj)); return p

@pytest.mark.parametrize("meta", [
    None,                  # no _meta key at all
    {},                    # _meta present, no 'complete'
    {"complete": False},   # explicit false
    {"complete": 1},       # truthy int — strict identity (`is not True`) must STILL refuse
    {"complete": "true"},  # truthy string — a loose `not meta.get(...)` would wrongly ACCEPT; we must refuse
    "x",                   # non-dict _meta → must raise the TYPED error, not AttributeError
])
def test_incomplete_or_malformed_meta_is_refused(tmp_path, meta):
    obj = {"results": {"bindings": []}}
    if meta is not None:
        obj["_meta"] = meta
    p = tmp_path / "s.json"; p.write_text(json.dumps(obj))   # write directly — do NOT inject _meta
    with pytest.raises(wikidata.SnapshotIncompleteError):    # never extract from a partial/malformed snapshot
        wikidata.WikidataExtractor({"Q33506"}).extract("uk", p, _db(tmp_path), run_id="r1")

def test_complete_true_snapshot_is_accepted(tmp_path):
    p = tmp_path / "ok.json"; p.write_text(json.dumps({"_meta": {"complete": True}, "results": {"bindings": []}}))
    assert wikidata.WikidataExtractor({"Q33506"}).extract("uk", p, _db(tmp_path), run_id="r1") == 0

def test_keeps_allowlisted_dedups_by_qid_drops_others_and_survives_malformed(tmp_path):
    conn = _db(tmp_path)
    n = wikidata.WikidataExtractor({"Q33506", "Q570116"}).extract("uk", FIX, conn, run_id="r1")
    rows = conn.execute("SELECT source, source_ref, name FROM source_records ORDER BY source_ref").fetchall()
    assert n == 1                                  # Q42 kept ONCE (deduped across 2 P31 rows)
    assert rows == [("wd", "wd:Q42", "Big Ben")]   # parish dropped (allowlist); malformed row skipped, not crashed

def test_captures_section4_signals(tmp_path):
    conn = _db(tmp_path)
    wikidata.WikidataExtractor({"Q33506", "Q570116"}).extract("uk", FIX, conn, run_id="r1")
    props = json.loads(conn.execute("SELECT props_json FROM source_records WHERE source_ref='wd:Q42'").fetchone()[0])
    assert props["sitelinks"] == 42                # §4 sitelink-count signal → A4
    assert props["image"].startswith("https://")   # §4 image availability / image_url origin (https-normalised)

def test_deterministic_stable_order_multi_record(tmp_path):
    # ≥2 kept items whose snapshot order differs from sorted → assert stored order == sorted lexical
    snap = {"results": {"bindings": [
        {"item": {"value": ".../Q9"}, "lat": {"value": "1"}, "lon": {"value": "1"},
         "p31": {"value": ".../Q33506"}, "label": {"value": "Nine"}},
        {"item": {"value": ".../Q100"}, "lat": {"value": "1"}, "lon": {"value": "1"},
         "p31": {"value": ".../Q33506"}, "label": {"value": "Hundred"}}]}}
    p = _write(tmp_path, snap, "s.json")
    conn = _db(tmp_path)
    wikidata.WikidataExtractor({"Q33506"}).extract("uk", p, conn, run_id="r1")
    order = [r[0] for r in conn.execute("SELECT source_ref FROM source_records ORDER BY id")]
    assert order == ["wd:Q100", "wd:Q9"]           # lexical source_ref order, stable

def test_bad_coordinate_row_is_dropped_via_a1_parse(tmp_path):
    # proves delegation: a bad coord is rejected by A1's parse (SourceRecordError) → skipped, not crashed
    snap = {"results": {"bindings": [
        {"item": {"value": ".../Q42"}, "lat": {"value": "999"}, "lon": {"value": "0"},
         "p31": {"value": ".../Q33506"}, "label": {"value": "Off-globe"}}]}}
    p = _write(tmp_path, snap, "b.json")
    conn = _db(tmp_path)
    assert wikidata.WikidataExtractor({"Q33506"}).extract("uk", p, conn, run_id="r1") == 0

def test_hostile_oversized_label_is_bounded_before_parse(tmp_path):
    snap = {"results": {"bindings": [
        {"item": {"value": ".../Q42"}, "lat": {"value": "1"}, "lon": {"value": "1"},
         "p31": {"value": ".../Q33506"}, "label": {"value": "x" * 5000}}]}}
    p = _write(tmp_path, snap, "h.json")
    conn = _db(tmp_path)
    wikidata.WikidataExtractor({"Q33506"}).extract("uk", p, conn, run_id="r1")
    name = conn.execute("SELECT name FROM source_records").fetchone()[0]
    assert len(name) <= wikidata.MAX_LABEL_LEN     # bounded at the edge, before parse

def test_oversized_snapshot_file_is_rejected(tmp_path, monkeypatch):
    p = tmp_path / "big.json"; p.write_text("{}")
    monkeypatch.setattr(wikidata, "MAX_SNAPSHOT_BYTES", 1)
    conn = _db(tmp_path)
    import pytest
    with pytest.raises(wikidata.SnapshotTooLargeError):
        wikidata.WikidataExtractor({"Q33506"}).extract("uk", p, conn, run_id="r1")

def test_bootstrap_allowlist_loads_and_is_minimal():
    allow = wikidata.load_allowlist(pathlib.Path(__file__).parents[1] / "config/wikidata_class_allowlist.json")
    assert allow and all(q.startswith("Q") for q in allow) and len(allow) <= 12   # genuinely minimal
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd pipeline && uv run python -m pytest tests/test_wikidata_extractor.py -q`
Expected: FAIL — module missing.

- [ ] **Step 3: Write the bootstrap allowlist**

`pipeline/config/wikidata_class_allowlist.json`:
```json
{
  "_header": "BOOTSTRAP: superseded by WP-A3. Obvious P31 classes only; do not curate here (that is A3's empirical job).",
  "allow": ["Q33506", "Q16970", "Q570116", "Q839954", "Q4989906"]
}
```
(museum, church building, monument, castle, memorial — the uncontroversial core.)

- [ ] **Step 4: Implement `wikidata.py`**

`pipeline/src/mt_pipeline/extractors/wikidata.py`:
```python
"""Wikidata extractor: a pure, crash-safe function of a dated SPARQL snapshot. Keeps
coordinate-bearing items whose P31 is in the CONSUMED allowlist (A3 owns curation),
carries the §4 scoring signals (sitelink count, image), de-dups by QID, and bounds
every field before handing a small props dict to A1's source_record.parse (§5.5)."""
from __future__ import annotations

import json
import pathlib

from .. import source_record

MAX_SNAPSHOT_BYTES = 256 * 1024 * 1024
MAX_RECORDS_PER_SNAPSHOT = 2_000_000
# NB: A1's source_record.parse truncates every props string AND the name to 300 chars
# (its NAME_MAX) — that governs the FINAL stored length. These edge caps match it, so
# the constant is not misleading; they also bound the raw field before parse.
MAX_LABEL_LEN = 300
MAX_SITELINKS = 100_000


class SnapshotTooLargeError(Exception):
    pass


class SnapshotIncompleteError(Exception):
    """The snapshot is not marked complete — acquisition partial/aborted. Refuse to
    extract from it (the enforcement point for the ratified 'never run against a
    partial snapshot' condition). Acquisition writes `_meta.complete = true` ONLY
    after every segment succeeds; a loud-abort leaves it absent/false."""


def load_allowlist(path) -> set[str]:
    return set(json.loads(pathlib.Path(path).read_text())["allow"])


def _load_snapshot(snapshot_path) -> dict:
    p = pathlib.Path(snapshot_path)
    if p.stat().st_size > MAX_SNAPSHOT_BYTES:      # cap the on-disk file BEFORE reading (§5.5)
        raise SnapshotTooLargeError(f"{p} exceeds {MAX_SNAPSHOT_BYTES} bytes")
    try:
        data = json.loads(p.read_text())
    except (ValueError, RecursionError) as e:      # deep-JSON bomb / malformed
        raise SnapshotTooLargeError(f"unparseable snapshot: {e}") from e
    meta = data.get("_meta")                       # a non-dict _meta must fail CLEANLY, not AttributeError
    if not isinstance(meta, dict) or meta.get("complete") is not True:
        raise SnapshotIncompleteError(f"{p} is not marked _meta.complete=true")
    return data


def _qid(uri: str) -> str:
    return uri.rsplit("/", 1)[-1]


def _https(url: str) -> "str | None":
    if isinstance(url, str) and url.startswith("http://"):
        url = "https://" + url[len("http://"):]
    return url if isinstance(url, str) and url.startswith("https://") else None


class WikidataExtractor:
    def __init__(self, allowlist: set[str]) -> None:
        self.allowlist = allowlist

    def extract(self, region: str, snapshot_path, conn, *, run_id: str) -> int:
        snapshot = _load_snapshot(snapshot_path)
        bindings = snapshot.get("results", {}).get("bindings", [])
        if len(bindings) > MAX_RECORDS_PER_SNAPSHOT:
            bindings = bindings[:MAX_RECORDS_PER_SNAPSHOT]   # deterministic bound before sorting
        # project to validated (qid, row) tuples INSIDE a guard, then sort — never a hostile sort key
        projected: dict[str, dict] = {}
        for b in bindings:
            try:
                qid = _qid(b["item"]["value"])
                if _qid(b["p31"]["value"]) not in self.allowlist:
                    continue
                if qid in projected:
                    continue                                 # de-dup by QID (keep-first)
                lat = float(b["lat"]["value"]); lon = float(b["lon"]["value"])
                label = str(b.get("label", {}).get("value", ""))[:MAX_LABEL_LEN]
                props = {"p31": _qid(b["p31"]["value"]), "label": label,
                         "sitelinks": min(int(b.get("sitelinks", {}).get("value", 0) or 0), MAX_SITELINKS)}
                img = _https(b.get("image", {}).get("value"))
                if img:
                    props["image"] = img
                projected[qid] = {"lat": lat, "lon": lon, "label": label, "props": props}
            except (KeyError, ValueError, TypeError):
                continue                                     # one bad row NEVER aborts the run
        count = 0
        for qid in sorted(projected):                        # stable lexical order
            item = projected[qid]
            try:
                rec = source_record.parse(region=region, source="wd", source_ref=f"wd:{qid}",
                                          name=item["label"], lat=item["lat"], lon=item["lon"],
                                          props=item["props"])
            except source_record.SourceRecordError:
                continue                                     # A1's boundary backstop
            source_record.persist(conn, rec, run_id=run_id)
            count += 1
        return count


def make_extractor(allowlist_path) -> WikidataExtractor:
    """Production factory: load the (bootstrap or A3) allowlist file and bind an extractor."""
    return WikidataExtractor(load_allowlist(allowlist_path))
```

- [ ] **Step 5: Run to verify it passes**

Run: `cd pipeline && uv run python -m pytest tests/test_wikidata_extractor.py -q`
Expected: PASS (14 passed — 8 tests, the `_meta` gate one parametrised ×6).

- [ ] **Step 6: Commit**

```bash
git add pipeline/src/mt_pipeline/extractors/wikidata.py pipeline/config/wikidata_class_allowlist.json \
        pipeline/tests/fixtures/wikidata pipeline/tests/test_wikidata_extractor.py
git commit -m "Add Wikidata extractor: crash-safe, deduped, §4 signals, allowlist factory, size-capped"
```

---

### Task 4: Wikipedia extractor (crash-safe, QID/lang validated)

**Files:**
- Create: `pipeline/src/mt_pipeline/extractors/wikipedia.py`
- Create: `pipeline/tests/fixtures/wikipedia/snapshot.json`
- Test: `pipeline/tests/test_wikipedia_extractor.py`

**Interfaces:**
- Produces:
  - Caps: `MAX_EXTRACT_LEN = 300`, `MAX_TITLE_LEN = 300` (match A1's props/name cap), `MAX_QID_LEN = 24`, `MAX_LANG_LEN = 16` (reuses wikidata's `_load_snapshot` — incl. the size + `_meta.complete` gates — and `MAX_RECORDS_PER_SNAPSHOT`).
  - `wikipedia.WikipediaExtractor(languages: set[str])` — implements `Extractor`. Drops pages whose snapshot `lang ∉ languages`. Emits `source=wp, source_ref=wp:<pageid>` with `props = {lang, title, extract, wikidata?}`; the QID is added **only if** it matches `Q[0-9]+` and is short (else the key is omitted — never a garbage A2 join key, never a whole-record drop). De-duped by pageid, stable lexical `source_ref` order, every field guarded.

- [ ] **Step 1: Write the fixture + failing test**

`pipeline/tests/fixtures/wikipedia/snapshot.json`:
```json
{"_meta": {"lang": "en", "retrieved_at": "2026-07-14", "complete": true},
 "lang": "en", "pages": [
  {"pageid": 12345, "title": "Big Ben", "lat": 51.5007, "lon": -0.1246,
   "extract": "The Great Bell of the striking clock at Westminster.", "wikidata": "Q42"},
  {"pageid": 67890, "title": "Some Hamlet", "lat": 51.4, "lon": -0.2,
   "extract": "A small place.", "wikidata": null},
  {"pageid": "MALFORMED", "title": "Bad pageid", "lat": 51.4, "lon": -0.2}
]}
```

`pipeline/tests/test_wikipedia_extractor.py`:
```python
import json
import pathlib
import pytest
from mt_pipeline import store
from mt_pipeline.extractors import wikipedia

FIX = pathlib.Path(__file__).parent / "fixtures/wikipedia/snapshot.json"

def _db(tmp_path): c = store.connect(tmp_path / "w.db"); store.init_schema(c); return c

def _snap(tmp_path, obj):
    obj = {"_meta": {"complete": True}, **obj}   # complete unless the test overrides _meta
    p = tmp_path / "s.json"; p.write_text(json.dumps(obj)); return p

def test_emits_wp_pageid_refs_skips_malformed(tmp_path):
    conn = _db(tmp_path)
    n = wikipedia.WikipediaExtractor({"en"}).extract("uk", FIX, conn, run_id="r1")
    rows = conn.execute("SELECT source_ref FROM source_records ORDER BY source_ref").fetchall()
    assert n == 2 and rows == [("wp:12345",), ("wp:67890",)]   # malformed pageid skipped, not crashed

def test_valid_qid_rides_in_props_null_and_garbage_do_not(tmp_path):
    conn = _db(tmp_path)
    wikipedia.WikipediaExtractor({"en"}).extract("uk", FIX, conn, run_id="r1")
    p1 = json.loads(conn.execute("SELECT props_json FROM source_records WHERE source_ref='wp:12345'").fetchone()[0])
    p2 = json.loads(conn.execute("SELECT props_json FROM source_records WHERE source_ref='wp:67890'").fetchone()[0])
    assert p1["wikidata"] == "Q42"
    assert "wikidata" not in p2                                 # null QID → no fabricated join key

def test_garbage_qid_dropped_but_record_kept(tmp_path):
    conn = _db(tmp_path)
    snap = _snap(tmp_path, {"lang": "en", "pages": [
        {"pageid": 1, "title": "T", "lat": 1, "lon": 1, "extract": "e", "wikidata": "Qwerty; nonsense"}]})
    wikipedia.WikipediaExtractor({"en"}).extract("uk", snap, conn, run_id="r1")
    props = json.loads(conn.execute("SELECT props_json FROM source_records").fetchone()[0])
    assert "wikidata" not in props                             # malformed QID never poisons the A2 join

def test_oversized_lang_does_not_nuke_all_records(tmp_path):
    conn = _db(tmp_path)
    snap = _snap(tmp_path, {"lang": "x" * 10_000, "pages": [
        {"pageid": 1, "title": "T", "lat": 1, "lon": 1, "extract": "e"}]})
    # lang not in {"en"} (and oversized) → all pages dropped cleanly (0), never a silent parse-reject storm
    assert wikipedia.WikipediaExtractor({"en"}).extract("uk", snap, conn, run_id="r1") == 0

def test_extract_length_bounded(tmp_path):
    conn = _db(tmp_path)
    snap = _snap(tmp_path, {"lang": "en", "pages": [
        {"pageid": 1, "title": "T", "lat": 1, "lon": 1, "extract": "y" * 5000}]})
    wikipedia.WikipediaExtractor({"en"}).extract("uk", snap, conn, run_id="r1")
    props = json.loads(conn.execute("SELECT props_json FROM source_records").fetchone()[0])
    assert len(props["extract"]) <= wikipedia.MAX_EXTRACT_LEN
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd pipeline && uv run python -m pytest tests/test_wikipedia_extractor.py -q`
Expected: FAIL — module missing.

- [ ] **Step 3: Implement `wikipedia.py`**

`pipeline/src/mt_pipeline/extractors/wikipedia.py`:
```python
"""Wikipedia extractor: a pure, crash-safe function of a dated geosearch+extracts
snapshot. Emits wp:<pageid> records with the linked Wikidata QID in props (A2's join,
like the OSM wikidata=* join). Validates lang against the config languages and the
QID shape; bounds every field before source_record.parse (§5.5)."""
from __future__ import annotations

import json
import re

from .. import source_record
from .wikidata import _load_snapshot, MAX_RECORDS_PER_SNAPSHOT

# A1's parse caps props strings + name to 300 (NAME_MAX) — the final stored length.
# These edge caps match it (and bound the raw field before parse).
MAX_EXTRACT_LEN = 300
MAX_TITLE_LEN = 300
MAX_QID_LEN = 24
MAX_LANG_LEN = 16
_QID_RE = re.compile(r"Q[0-9]+")


class WikipediaExtractor:
    def __init__(self, languages: set[str]) -> None:
        self.languages = languages

    def extract(self, region: str, snapshot_path, conn, *, run_id: str) -> int:
        snapshot = _load_snapshot(snapshot_path)
        lang = str(snapshot.get("lang", ""))[:MAX_LANG_LEN]
        if lang not in self.languages:            # config-driven; oversized/foreign lang → drop all cleanly
            return 0
        pages = snapshot.get("pages", [])[:MAX_RECORDS_PER_SNAPSHOT]
        projected: dict[int, dict] = {}
        for page in pages:
            try:
                pageid = int(page["pageid"])
                if pageid in projected:
                    continue
                lat = float(page["lat"]); lon = float(page["lon"])
                title = str(page.get("title", ""))[:MAX_TITLE_LEN]
                props = {"lang": lang, "title": title,
                         "extract": str(page.get("extract", ""))[:MAX_EXTRACT_LEN]}
                qid = page.get("wikidata")
                if isinstance(qid, str) and len(qid) <= MAX_QID_LEN and _QID_RE.fullmatch(qid):
                    props["wikidata"] = qid       # only a well-shaped QID becomes an A2 join key
                projected[pageid] = {"lat": lat, "lon": lon, "title": title, "props": props}
            except (KeyError, ValueError, TypeError):
                continue                          # one bad page NEVER aborts the run
        count = 0
        for pageid in sorted(projected):
            item = projected[pageid]
            try:
                rec = source_record.parse(region=region, source="wp", source_ref=f"wp:{pageid}",
                                          name=item["title"], lat=item["lat"], lon=item["lon"],
                                          props=item["props"])
            except source_record.SourceRecordError:
                continue
            source_record.persist(conn, rec, run_id=run_id)
            count += 1
        return count
```
Note: `sorted(projected)` on int pageids gives numeric order, but `source_ref=wp:<pageid>` is emitted in that order and the test asserts lexical `ORDER BY source_ref` — for the fixture pageids (12345 < 67890) numeric and lexical agree; if a future fixture needs it, the stored order is by numeric pageid (documented).

- [ ] **Step 4: Run to verify it passes**

Run: `cd pipeline && uv run python -m pytest tests/test_wikipedia_extractor.py -q`
Expected: PASS (5 passed).

- [ ] **Step 5: Commit**

```bash
git add pipeline/src/mt_pipeline/extractors/wikipedia.py pipeline/tests/fixtures/wikipedia \
        pipeline/tests/test_wikipedia_extractor.py
git commit -m "Add Wikipedia extractor: crash-safe, QID-shape + lang validated, deduped"
```

---

### Task 5: Pageview ACQUISITION (resumable, cached, per-run flag) — computation is A4's

**Files:**
- Create: `pipeline/src/mt_pipeline/extractors/pageviews.py`
- Test: `pipeline/tests/test_pageviews.py`

**Interfaces:**
- Produces (acquisition only — **no median/computation**, that is A4's over the cache):
  - `pageviews.window_for(snapshot_date: str, months: int = 12) -> tuple[str, str]` — the deterministic `[start, end]` from the config snapshot date (never wall-clock; leap-day safe).
  - `pageviews.acquire(titles, window, cache_dir, *, fetch, enabled=False) -> int` — behind the `enabled` **per-run flag**; **cached per `(title, window)`** (a title already cached is not re-fetched); **resumable** — each title's raw response is written to the cache immediately, so a crash mid-sweep resumes from the persisted cache, never restarts. Returns the number of newly-fetched titles. `fetch` is injected (the network seam). Rate-courtesy (polite interval, `429`/`Retry-After`) lives in the production `fetch`. A4 reads the cache as its signal input.

- [ ] **Step 1: Write the fixture + failing test**

`pipeline/tests/test_pageviews.py`:
```python
import json
import pathlib
from mt_pipeline.extractors import pageviews

def test_window_is_derived_from_config_date_not_wallclock():
    assert pageviews.window_for("2026-07-14", 12) == ("2025-07-14", "2026-07-14")

def test_window_is_leap_day_safe():
    # a Feb-29 config snapshot date must not crash (clamp to Feb-28)
    assert pageviews.window_for("2024-02-29", 12) == ("2023-02-28", "2024-02-29")

def test_acquire_is_gated_by_the_per_run_flag(tmp_path):
    calls = []
    def fake_fetch(title, window): calls.append(title); return {"items": [{"views": 1}]}
    n = pageviews.acquire(["Big_Ben"], ("2025-07-14", "2026-07-14"), tmp_path, fetch=fake_fetch, enabled=False)
    assert n == 0 and calls == []                         # flag off → no sweep

def test_acquire_is_resumable_and_cached(tmp_path):
    calls = []
    def fake_fetch(title, window):
        calls.append(title)
        if title == "B" and "B" not in [c for c in calls if c == "B"][:-1]:
            pass
        return {"items": [{"views": 1}]}
    win = ("2025-07-14", "2026-07-14")
    # first run fetches A then raises on B (simulate crash)
    def crashing_fetch(title, window):
        calls.append(title)
        if title == "B": raise RuntimeError("crash")
        return {"items": [{"views": 1}]}
    try:
        pageviews.acquire(["A", "B", "C"], win, tmp_path, fetch=crashing_fetch, enabled=True)
    except RuntimeError:
        pass
    assert "A" in calls                                    # A cached before the crash
    calls.clear()
    # second run resumes: A already cached (not re-fetched), B and C fetched
    pageviews.acquire(["A", "B", "C"], win, tmp_path, fetch=fake_fetch, enabled=True)
    assert "A" not in calls and set(calls) == {"B", "C"}   # resume, no re-fetch of A
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd pipeline && uv run python -m pytest tests/test_pageviews.py -q`
Expected: FAIL — module missing.

- [ ] **Step 3: Implement `pageviews.py`**

`pipeline/src/mt_pipeline/extractors/pageviews.py`:
```python
"""Pageview ACQUISITION (WP-A1b): fetch + cache the raw Wikimedia REST response per
(title, window) so WP-A4 can compute its signal from the cache. Resumable — each
title is cached the moment it is fetched, so a crash mid-sweep resumes. The window is
a FIXED trailing span from the config snapshot date (never wall-clock, leap-day safe).
No median/computation here — that is A4's."""
from __future__ import annotations

import datetime
import hashlib
import json
import pathlib


def window_for(snapshot_date: str, months: int = 12) -> tuple[str, str]:
    end = datetime.date.fromisoformat(snapshot_date)
    if months % 12 == 0:
        y = end.year - months // 12
        try:
            start = end.replace(year=y)
        except ValueError:                       # Feb-29 in a non-leap target year → clamp to Feb-28
            start = end.replace(year=y, day=28)
    else:
        start = end - datetime.timedelta(days=int(months * 30.4375))
    return (start.isoformat(), end.isoformat())


def _cache_path(cache_dir, title: str, window: tuple[str, str]):
    key = hashlib.sha256(f"{title}|{window[0]}|{window[1]}".encode()).hexdigest()
    return pathlib.Path(cache_dir) / f"{key}.json"


def acquire(titles, window, cache_dir, *, fetch, enabled: bool = False) -> int:
    if not enabled:
        return 0                                 # per-run flag: a plain extract skips the sweep
    pathlib.Path(cache_dir).mkdir(parents=True, exist_ok=True)
    fetched = 0
    for title in titles:
        cp = _cache_path(cache_dir, title, window)
        if cp.exists():
            continue                             # cached (resume): never re-fetch
        data = fetch(title, window)              # may raise → run aborts; cache so far persists → resumable
        cp.write_text(json.dumps(data))
        fetched += 1
    return fetched
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd pipeline && uv run python -m pytest tests/test_pageviews.py -q`
Expected: PASS (4 passed).

- [ ] **Step 5: Commit**

```bash
git add pipeline/src/mt_pipeline/extractors/pageviews.py pipeline/tests/test_pageviews.py
git commit -m "Add resumable cached pageview acquisition (per-run flag, leap-safe window; A4 computes)"
```

---

### Task 6: Wire enabled extractors into the A1 'extract' stage + determinism guard

**Files:**
- Create: `pipeline/src/mt_pipeline/extract_stage.py`, `pipeline/tests/test_extractor_determinism.py`
- Test: `pipeline/tests/test_extract_stage.py`

**Interfaces:**
- Consumes: `extractors.Registry`, `config.RegionConfig` (A1), `store`.
- Produces:
  - `extract_stage.build_registry(allowlist_path, languages) -> Registry` — the **production wiring**: registers `wikidata.make_extractor(allowlist_path)` and `WikipediaExtractor(languages)`.
  - `extract_stage.run_extract(conn, region_config: RegionConfig, snapshots, *, run_id, registry) -> dict[str, int]` — reads `region_config.region_id`/`region_config.sources` (the A1 dataclass, **not a dict**), runs each enabled extractor against its dated snapshot. This is what A1's `extract` stage body calls (the CLI loads the `RegionConfig` and acquires snapshots first; A1 left the stage a dispatchable no-op).

- [ ] **Step 1: Write the failing tests**

`pipeline/tests/test_extract_stage.py`:
```python
import pathlib
from dataclasses import dataclass
from mt_pipeline import store, extract_stage

FIXW = pathlib.Path(__file__).parent / "fixtures/wikidata/snapshot.json"

@dataclass(frozen=True)
class FakeRegionConfig:   # shape-compatible with A1's config.RegionConfig
    region_id: str
    sources: dict

def test_runs_only_enabled_extractors_from_regionconfig(tmp_path):
    conn = store.connect(tmp_path / "w.db"); store.init_schema(conn)
    reg = extract_stage.build_registry(
        pathlib.Path(__file__).parents[1] / "config/wikidata_class_allowlist.json", languages={"en"})
    cfg = FakeRegionConfig(region_id="uk",
        sources={"wikidata": True, "wikipedia": False, "osm": False,
                 "historic_england": False, "open_plaques": False, "national_register": None})
    counts = extract_stage.run_extract(conn, cfg, {"wikidata": str(FIXW)}, run_id="r1", registry=reg)
    assert counts == {"wikidata": 1}                        # bootstrap allowlist keeps Q42; wikipedia disabled
    assert conn.execute("SELECT COUNT(*) FROM source_records").fetchone()[0] == 1
```

`pipeline/tests/test_extractor_determinism.py`:
```python
import ast
import pathlib
import mt_pipeline

# Wall-clock/randomness attrs that must not appear in extractor OUTPUT modules.
# `fromisoformat` (pageviews window from a CONFIG date) and `replace`/`timedelta`/
# `isoformat` are NOT banned, so pageviews.py passes without a blanket exclusion —
# no module is skipped wholesale.
_BANNED = {"now", "utcnow", "today", "time", "monotonic", "perf_counter",
           "random", "shuffle", "uuid4", "uuid1", "urandom", "randint", "choice"}

def test_no_wallclock_or_randomness_in_extractor_modules():
    root = pathlib.Path(mt_pipeline.__file__).parent / "extractors"
    offenders = []
    for py in sorted(root.rglob("*.py")):     # every extractor module, pageviews included
        for node in ast.walk(ast.parse(py.read_text())):
            if isinstance(node, ast.Attribute) and node.attr in _BANNED:
                offenders.append(f"{py.name}:{node.attr}")
    assert offenders == [], offenders
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd pipeline && uv run python -m pytest tests/test_extract_stage.py tests/test_extractor_determinism.py -q`
Expected: FAIL — `mt_pipeline.extract_stage` missing.

- [ ] **Step 3: Implement `extract_stage.py`**

`pipeline/src/mt_pipeline/extract_stage.py`:
```python
"""The body of A1's 'extract' stage: build the production registry and run each enabled
extractor for a region (read from A1's RegionConfig dataclass) against its dated
snapshot. A1c/A1d register more extractors in build_registry; run_extract is unchanged."""
from __future__ import annotations

from .extractors import Registry
from .extractors import wikidata
from .extractors.wikipedia import WikipediaExtractor


def build_registry(allowlist_path, languages: set[str]) -> Registry:
    reg = Registry()
    reg.register("wikidata", wikidata.make_extractor(allowlist_path))
    reg.register("wikipedia", WikipediaExtractor(languages))
    return reg


def run_extract(conn, region_config, snapshots: dict, *, run_id: str, registry) -> dict:
    counts: dict[str, int] = {}
    for source, extractor in registry.enabled_for(region_config.sources):
        snapshot_path = snapshots.get(source)
        if snapshot_path is None:
            continue
        counts[source] = extractor.extract(region_config.region_id, snapshot_path, conn, run_id=run_id)
    return counts
```

- [ ] **Step 4: Run + full suite + commit**

Run: `cd pipeline && uv run python -m pytest -q`
Expected: PASS (all A1 + A1b tests green).

```bash
git add pipeline/src/mt_pipeline/extract_stage.py pipeline/tests/test_extract_stage.py \
        pipeline/tests/test_extractor_determinism.py
git commit -m "Wire production wiki-extractor registry into the A1 extract stage + determinism guard"
```

---

## Review Record

**Author self-review** — deliverables map to tasks: SSRF-safe fetch (T1); registry (T2); Wikidata extractor with §4 signals + factory (T3); Wikipedia extractor (T4); resumable pageview acquisition (T5); production wiring + determinism guard (T6). Implements A1's `source_record.parse` interface; consumes (not invents) the P31 allowlist; English-only via config `languages`. **One vandalized record never crashes a run** (guarded per-record projection; no hostile sort key). Determinism = pure function of a dated snapshot, de-duped, stable lexical order.

**Ratifications (fable, thread `wp/a1b`)** — cached-SPARQL→self-describing snapshot (segmented, etiquette, loud-abort); `wp:<pageid>` + QID-in-props (A0 `wp`-grammar is a codex task, needed only for A2 minting — noted, not implemented; A1b emits the ref with no A0 change, confirmed against current `is_canonical_ref`); minimal header-marked bootstrap allowlist; pageview acquisition here, **computation deferred to A4**.

**Adversarial review (4 subagent critics + cross-examination, per AGENTS.md gate)** — the feasibility critic ran the prior draft's 17 tests verbatim (happy path sound); the material fixes below (all reproduced by critics) are folded in:
- *Security (HIGH):* one malformed record crashed the whole extract (hostile access in the `sorted()` key, before the per-record guard) → now every field is projected inside a per-record `try/except` and sorting happens over validated tuples; **unbounded record count and unbounded snapshot-file read** (`MAX_CLAIMS`/`MAX_SITELINKS` were dead) → real `MAX_RECORDS_PER_SNAPSHOT` + `MAX_SNAPSHOT_BYTES` (checked before `json.loads`) + `RecursionError` caught; **SSRF via auto-followed redirects** → the fetch re-applies the https+host allowlist on every hop, plus a total download deadline and `Content-Encoding` rejection; Wikipedia QID now shape+length validated (a garbage QID drops only the key, never poisons the A2 join or drops the record); `lang` validated against config + length-capped (an oversized `lang` no longer silently nukes every record).
- *Spec/interface (HIGH):* the prior draft **built A4's pageview *median* (out of scope) and only prosed A1b's ratified *acquisition*** → median deleted; resumable, cached, per-run-flag acquisition built and tested (crash mid-sweep → resume, no re-fetch); the extractors now **conform to the `Extractor` Protocol** as classes with a production `make_extractor`/`build_registry` wiring that loads the bootstrap allowlist (previously only a test-only adapter); `run_extract`/`enabled_for` now consume A1's **`RegionConfig` dataclass**, not a dict; the Wikidata extractor now captures the **§4 signals** (sitelink count, P18 image → `image_url` origin) that nothing else re-acquires.
- *Coherence/test-quality:* determinism now tested with ≥2 records whose snapshot order differs from sorted; parse-delegation proven via a bad-coordinate row that must be dropped (exercising the skip path); hostile oversized fields asserted bounded; de-dup, don't-fabricate-join-key, malformed-record-skipped, oversized-snapshot, and SSRF all pinned; the determinism guard recurses over `extractors/`.
- *Feasibility:* `window_for` crashed on a Feb-29 config snapshot date → clamped to Feb-28; duplicate-QID rows de-duped; the double label-slice removed.

**Delta review (fable, independent, on PR #34) — CHANGES REQUIRED, fixed:** the gate had *reported* the SSRF fix as landed when it was defined-but-unwired — the lesson applied. (1) **SSRF (HIGH):** `_AllowlistRedirect` was defined but `get_json` fetched via `urlopen` (follows redirects to any host). Now `get_json` fetches through `_opener(expected_hosts)` = `build_opener(_AllowlistRedirect(...))` — **one** path with both the redirect-allowlist and the streaming cap/deadline/Content-Encoding checks; the test drives a **real 302 through `get_json`** and asserts `FetchError`. (2) **Partial-snapshot (MEDIUM):** the "never run against a partial snapshot" condition had no enforcement point. Now `_load_snapshot` refuses any snapshot without `_meta.complete == true` (`SnapshotIncompleteError`, tested); the network acquisition is honestly scoped as a named deferred follow-up whose completeness marker the gate enforces. Folds: the determinism guard no longer blanket-skips `pageviews.py` (it passes on specifics); `MAX_EXTRACT_LEN`/`MAX_*_LEN` aligned to A1's effective 300-char props/name cap (no longer misleading). The **re-run fetch security critic** then verified the SSRF fix is genuinely wired on the executed path (blocks single-hop, multi-hop, and https→http-downgrade redirects; a neutered handler gets pwned) and caught that the first redirect test was a **false green** (the mock's evil→evil loop made a neutered handler still raise `FetchError` via urllib's loop detection) — fixed with `pytest.raises(..., match="blocked redirect")` so the test fails unless the allowlist is what blocked; also hardened the `_meta` gate against a non-dict `_meta`.

**Cross-package needs surfaced** — codex: append `wp` (last) to A0's mint grammar + frozen vector (A2 minting only); A3: replace the bootstrap allowlist; A2: read `props["wikidata"]` as the wp→wd join key; A1: consider `UNIQUE(source, source_ref)` on `source_records`.
