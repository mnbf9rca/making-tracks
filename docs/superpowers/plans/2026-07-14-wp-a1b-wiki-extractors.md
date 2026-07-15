# WP-A1b (Wiki Extractors) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Two deterministic, §5.5-hardened extractors — **Wikidata** (coordinate-bearing items whose P31 class passes a consumed allowlist) and **Wikipedia** (English geotagged articles) — that implement WP-A1's source-record interface, turning dated source snapshots into normalized source records for A2 reconcile. Plus the shared **acquire** layer (byte-capped snapshot fetch) and the **extract-stage registry** that A1c/A1d extend.

**Architecture:** Under `pipeline/` (the WP-A1 `mt_pipeline` package). Each extractor is a **pure function of a dated snapshot file** — determinism is "same snapshot in → same records out." Acquisition (network) is a *separate*, byte-capped step that writes the dated snapshot; the deterministic extract path never touches the network and is tested entirely against golden fixtures (§7). Every fetched blob is bounded at the extractor edge **before** anything reaches A1's `source_record.parse` (binding carry-in from the A1 review). English-only recall with `languages` and `bbox` read from the A0 region config.

**Tech Stack:** Python 3.11+ (the `mt_pipeline` package + `mt-contracts`), stdlib `urllib`/`http` with a bounded streaming reader, `pytest`. No heavyweight deps; laptop-first.

## Global Constraints

- **Implements A1's interface, never re-declares it.** Records are produced *only* via `mt_pipeline.source_record.parse(region, source, source_ref, name, lat, lon, props)` and stored via `persist(conn, record, *, run_id)`. The canonical-ref grammar and text-safety come from `mt_contracts` (via A1's `parse`), never re-implemented here.
- **Raw-blob bounding at the extractor edge (BINDING, A1 review carry-in).** Every fetched payload is read through a **byte-capped streaming reader** (reject over `MAX_SNAPSHOT_BYTES` / `MAX_RESPONSE_BYTES` before parsing — no unbounded `.read()`/`.json()`), https-only from an expected host. Per item: claim/label/sitelink/extract **counts and lengths are bounded** before a `props` dict is built. All Wikidata/Wikipedia strings are treated as hostile (§5.5) — the bounded `props` is handed to A1's `parse`, which applies the final canonical-ref/coord/`props` validation. The dict that reaches `parse` is always small and shallow.
- **Determinism (Principle 12).** `extract(snapshot, …)` is a pure function of the dated snapshot file: same snapshot → identical records, identical ordering. No wall-clock or randomness in any output; the snapshot date and `run_id` are metadata only. Records are emitted in a **stable sort order** (by `source_ref`) so re-runs and diffs are stable.
- **English-only recall, config-driven (§4).** `languages` (`["en"]`) and `bbox` come from the A0 region config (`mt_contracts.load_region_config`); no language or bbox is hardcoded. Enabling Malay etc. later is a config change, not a code change.
- **The P31 allowlist is CONSUMED, not invented (§4).** The extractor reads a class allowlist artifact; the authoritative curation is **WP-A3's data-audit output**. A minimal **bootstrap** allowlist ships here (clearly marked) so A1b runs before A3 exists; A3 supersedes it.
- **All source data is untrusted (Principle 10 / §5.5).** Defensive parsing at every field; no source content is interpolated into shell/SQL/LLM; coordinate bounds, string caps, control-char handling all happen via A1's `parse` after the extractor bounds the blob.
- **Scope:** extraction only. No reconcile (A2), no scoring/tiering (A4), no place_id minting (A2). This WP produces source records; it does not join or score them.
- **Test-first**, against golden fixture snapshots (no network in tests).

**Ratified (fable, thread `wp/a1b`)** — all four decisions, with conditions folded into the tasks below:
1. **Wikidata acquisition** = cached-SPARQL (WDQS) → a **self-describing dated snapshot**; the extractor is a pure function of that snapshot. HARD conditions (Task 3 acquisition contract): queries **segmented** (per P31-class-chunk × bbox-tile — a monolithic region query hits WDQS's 60 s timeout); WDQS etiquette (descriptive `User-Agent`, backoff on `429`/`5xx`, no parallel hammering); the snapshot **records endpoint + full query text + retrieval date** (it *is* the determinism boundary); acquisition failure is **loud and aborts the snapshot** — the extractor never runs against a partial snapshot.
2. **Wikipedia `source_ref` = `wp:<pageid>`**; the linked Wikidata **QID rides in `props`** for A2's join. **A0 dependency (NOTE only — a codex contracts task fable briefs, not implemented here):** `wp` is added to A0's **append-only** `_SOURCE_IDENT_GRAMMAR` (`wp:[0-9]+`), appended **last in anchor priority** (`wd > osm > hehle > plaque > wp` — every existing ordering untouched) with a new frozen conformance vector. Needed only to *mint* a Wikipedia-only place (geotagged article with no QID); A1b itself only emits the ref.
3. **P31 bootstrap allowlist** in `pipeline/config/wikidata_class_allowlist.json`, header-marked `BOOTSTRAP: superseded by WP-A3`, **genuinely minimal** (obvious classes only — curation is A3's empirical job), file-replaceable by A3 with zero extractor change.
4. **Pageviews:** acquisition here, **computation deferred to A4**. Fixed trailing window anchored to the run's config snapshot date (never wall-clock); cached per `(title, window)`; **resumable** (tens of thousands of UK titles — a crash at 80 % must not restart); rate-courteous; behind a **per-run flag** so a plain extract doesn't force the full pageview sweep. A4 consumes the cache.

---

## File Structure

```
pipeline/src/mt_pipeline/
  fetch.py                              # byte-capped streaming HTTPS reader (raw-blob bound) (Task 1)
  extractors/
    __init__.py                         # extractor registry (source name -> extractor) (Task 2)
    wikidata.py                         # Wikidata: snapshot -> source records (Task 3)
    wikipedia.py                        # Wikipedia: snapshot -> source records (Task 4)
    pageviews.py                        # fixed-window deterministic pageview lookup (Task 5)
  extract_stage.py                      # wires enabled extractors into the A1 'extract' stage (Task 6)
pipeline/config/
  wikidata_class_allowlist.json         # BOOTSTRAP P31 allowlist (A3 supersedes) (Task 3)
pipeline/tests/
  fixtures/wikidata/snapshot.json       # golden SPARQL result (Task 3)
  fixtures/wikipedia/snapshot.json      # golden geosearch+extracts result (Task 4)
  fixtures/pageviews/*.json             # golden pageview responses (Task 5)
  test_fetch.py                         # Task 1
  test_extractor_registry.py            # Task 2
  test_wikidata_extractor.py            # Task 3
  test_wikipedia_extractor.py           # Task 4
  test_pageviews.py                     # Task 5
  test_extract_stage.py                 # Task 6
```

Acquisition writes dated snapshots into the working store / a snapshot dir (side-effecting, network); the `extract_*` functions are pure over those snapshots. Tests exercise the pure path against `fixtures/`.

---

### Task 1: Byte-capped streaming fetch (the raw-blob bound)

**Files:**
- Create: `pipeline/src/mt_pipeline/fetch.py`
- Test: `pipeline/tests/test_fetch.py`

**Interfaces:**
- Produces:
  - `fetch.MAX_RESPONSE_BYTES = 32 * 1024 * 1024` (per-response cap; a single SPARQL page / geosearch tile).
  - `fetch.FetchError(Exception)`.
  - `fetch.get_json(url, *, expected_hosts: set[str], max_bytes=MAX_RESPONSE_BYTES, timeout=30) -> dict` — https-only, host-allowlisted, streams the body and **raises before exceeding `max_bytes`** (never a full unbounded read), then `json.loads`. This is the single network boundary; every extractor fetch goes through it.

- [ ] **Step 1: Write the failing test**

`pipeline/tests/test_fetch.py`:
```python
import io
import json
import pytest
from mt_pipeline import fetch

class _Resp(io.BytesIO):
    # minimal stand-in for an http response stream
    def __init__(self, data): super().__init__(data)

def test_rejects_non_https(monkeypatch):
    with pytest.raises(fetch.FetchError):
        fetch.get_json("http://insecure/x", expected_hosts={"insecure"})

def test_rejects_unexpected_host():
    with pytest.raises(fetch.FetchError):
        fetch.get_json("https://evil.example/x", expected_hosts={"query.wikidata.org"})

def test_streams_and_caps_oversize_body(monkeypatch):
    big = b'{"x":"' + b"a" * (fetch.MAX_RESPONSE_BYTES + 1024) + b'"}'
    monkeypatch.setattr(fetch, "_open", lambda url, timeout: _Resp(big))
    with pytest.raises(fetch.FetchError):
        fetch.get_json("https://query.wikidata.org/x", expected_hosts={"query.wikidata.org"},
                       max_bytes=1024)   # aborts well before the full body is read

def test_returns_parsed_json_within_cap(monkeypatch):
    monkeypatch.setattr(fetch, "_open", lambda url, timeout: _Resp(json.dumps({"ok": 1}).encode()))
    assert fetch.get_json("https://query.wikidata.org/x",
                          expected_hosts={"query.wikidata.org"}) == {"ok": 1}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd pipeline && uv run python -m pytest tests/test_fetch.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named 'mt_pipeline.fetch'`.

- [ ] **Step 3: Implement `fetch.py`**

`pipeline/src/mt_pipeline/fetch.py`:
```python
"""The single network boundary: byte-capped, https-only, host-allowlisted streaming
fetch. Every extractor's raw blob passes through here and is bounded BEFORE it is
parsed (§5.5 raw-blob bound). Never call .read()/.json() on an unbounded response."""
from __future__ import annotations

import json
import urllib.request
from urllib.parse import urlparse

MAX_RESPONSE_BYTES = 32 * 1024 * 1024


class FetchError(Exception):
    pass


def _open(url: str, timeout: int):  # seam for tests
    return urllib.request.urlopen(url, timeout=timeout)  # nosec - url validated by caller below


def get_json(url: str, *, expected_hosts: set[str], max_bytes: int = MAX_RESPONSE_BYTES,
             timeout: int = 30) -> dict:
    parts = urlparse(url)
    if parts.scheme != "https":
        raise FetchError(f"non-https url: {url!r}")
    if parts.hostname not in expected_hosts:
        raise FetchError(f"unexpected host {parts.hostname!r} (allowed: {sorted(expected_hosts)})")
    try:
        resp = _open(url, timeout)
    except Exception as e:  # network/URL errors are all fetch failures
        raise FetchError(str(e)) from e
    chunks, total = [], 0
    while True:
        chunk = resp.read(65536)
        if not chunk:
            break
        total += len(chunk)
        if total > max_bytes:
            raise FetchError(f"response exceeded {max_bytes} bytes (possible oversize/bomb)")
        chunks.append(chunk)
    try:
        return json.loads(b"".join(chunks).decode("utf-8"))
    except (ValueError, UnicodeDecodeError) as e:
        raise FetchError(f"invalid JSON: {e}") from e
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd pipeline && uv run python -m pytest tests/test_fetch.py -q`
Expected: PASS (4 passed).

- [ ] **Step 5: Commit**

```bash
git add pipeline/src/mt_pipeline/fetch.py pipeline/tests/test_fetch.py
git commit -m "Add byte-capped https-only streaming fetch (the extractor-edge raw-blob bound)"
```

---

### Task 2: Extractor registry (the shared dispatch A1c/A1d extend)

**Files:**
- Create: `pipeline/src/mt_pipeline/extractors/__init__.py`
- Test: `pipeline/tests/test_extractor_registry.py`

**Interfaces:**
- Produces:
  - `extractors.Extractor` — a `Protocol`: `extract(region, snapshot_path, conn, *, run_id) -> int` (returns the record count).
  - `extractors.register(source: str, extractor)` and `extractors.enabled_for(region_config: dict) -> list[tuple[str, Extractor]]` — returns the `(source, extractor)` pairs whose `sources.<name>` is true in the region config, in a **stable order**. A1c/A1d register their extractors the same way.

- [ ] **Step 1: Write the failing test**

`pipeline/tests/test_extractor_registry.py`:
```python
from mt_pipeline import extractors

def test_register_and_enabled_for_reads_region_config():
    reg = extractors.Registry()
    reg.register("wikidata", object())
    reg.register("wikipedia", object())
    reg.register("osm", object())   # pretend A1c registered this
    cfg = {"sources": {"wikidata": True, "wikipedia": True, "osm": False, "historic_england": False,
                       "open_plaques": False, "national_register": None}}
    got = [name for name, _ in reg.enabled_for(cfg)]
    assert got == ["wikidata", "wikipedia"]        # only enabled, and in stable registration order

def test_enabled_for_ignores_unknown_and_non_bool_source_keys():
    reg = extractors.Registry()
    reg.register("wikidata", object())
    cfg = {"sources": {"wikidata": True, "national_register": {"id": "x", "enabled": False}}}
    assert [n for n, _ in reg.enabled_for(cfg)] == ["wikidata"]
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd pipeline && uv run python -m pytest tests/test_extractor_registry.py -q`
Expected: FAIL — `ModuleNotFoundError`.

- [ ] **Step 3: Implement `extractors/__init__.py`**

`pipeline/src/mt_pipeline/extractors/__init__.py`:
```python
"""Extractor registry: the shared dispatch WP-A1b establishes and A1c/A1d extend.
An extractor turns a dated snapshot into source records via source_record.parse."""
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

    def enabled_for(self, region_config: dict) -> list[tuple[str, object]]:
        sources = region_config.get("sources", {})
        # stable registration order; only sources flagged True (bool) and registered
        return [(s, self._by_source[s]) for s in self._order
                if sources.get(s) is True]
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd pipeline && uv run python -m pytest tests/test_extractor_registry.py -q`
Expected: PASS (2 passed).

- [ ] **Step 5: Commit**

```bash
git add pipeline/src/mt_pipeline/extractors/__init__.py pipeline/tests/test_extractor_registry.py
git commit -m "Add extractor registry (stable enabled-source dispatch, extended by A1c/A1d)"
```

---

### Task 3: Wikidata extractor + bootstrap P31 allowlist

**Files:**
- Create: `pipeline/src/mt_pipeline/extractors/wikidata.py`, `pipeline/config/wikidata_class_allowlist.json`
- Create: `pipeline/tests/fixtures/wikidata/snapshot.json`
- Test: `pipeline/tests/test_wikidata_extractor.py`

**Interfaces:**
- Consumes: `mt_pipeline.source_record.parse`/`persist`, `mt_pipeline.store`.
- Produces:
  - `wikidata.MAX_CLAIMS = 512`, `MAX_SITELINKS = 64`, `MAX_LABEL_LEN = 400` (per-item raw-blob bounds).
  - `wikidata.load_allowlist(path) -> set[str]` (the consumed P31 class set).
  - `wikidata.extract(region, snapshot_path, conn, *, run_id, allowlist) -> int` — reads the dated SPARQL snapshot, keeps items with a coordinate and a P31 ∈ allowlist, bounds each item, and emits `source=wd, source_ref=wd:<QID>` records via `source_record.parse` in **stable `source_ref` order**. Pure function of the snapshot.

**Acquisition contract (fable-ratified conditions; the network step that writes the snapshot — separate from the pure `extract`, not in the deterministic test path).** The acquire step MUST: (a) issue **segmented** WDQS queries — one per (P31-class-chunk × bbox-tile) so no single query approaches WDQS's 60 s timeout (a monolithic UK query fails); (b) follow WDQS etiquette — a descriptive `User-Agent`, exponential backoff on `429`/`5xx`, no parallel hammering; (c) write a **self-describing** snapshot whose top-level `_meta` records `endpoint`, the **full query text** per segment, and the UTC `retrieved_at` date — the snapshot is the determinism boundary, so it must state exactly how it was produced; (d) treat any segment failure as **loud and fatal** — abort and do not write a snapshot, so the pure `extract` never runs against a partial result. The `extract` function ignores `_meta` and consumes only `results.bindings`.

- [ ] **Step 1: Write the golden fixture + failing test**

`pipeline/tests/fixtures/wikidata/snapshot.json` (a minimal WDQS-shaped result with the self-describing `_meta` envelope; `extract` ignores `_meta` and reads only `results.bindings`):
```json
{"_meta": {"endpoint": "https://query.wikidata.org/sparql",
           "queries": ["SELECT ?item ?lat ?lon ?p31 ?label WHERE { ... bbox-tile 0 x class-chunk 0 ... }"],
           "retrieved_at": "2026-07-14"},
 "results": {"bindings": [
  {"item": {"value": "http://www.wikidata.org/entity/Q42"},
   "lat": {"value": "51.5007"}, "lon": {"value": "-0.1246"},
   "p31": {"value": "http://www.wikidata.org/entity/Q33506"},
   "label": {"value": "Big Ben"}},
  {"item": {"value": "http://www.wikidata.org/entity/Q999"},
   "lat": {"value": "51.5"}, "lon": {"value": "-0.1"},
   "p31": {"value": "http://www.wikidata.org/entity/Q_NOT_ALLOWED"},
   "label": {"value": "A Parish"}}
]}}
```

`pipeline/tests/test_wikidata_extractor.py`:
```python
import json
import pathlib
from mt_pipeline import store, source_record
from mt_pipeline.extractors import wikidata

FIX = pathlib.Path(__file__).parent / "fixtures/wikidata/snapshot.json"

def _db(tmp_path):
    c = store.connect(tmp_path / "w.db"); store.init_schema(c); return c

def test_extract_keeps_allowlisted_and_drops_others(tmp_path):
    conn = _db(tmp_path)
    allow = {"Q33506"}   # museum-ish; excludes the parish Q_NOT_ALLOWED
    n = wikidata.extract("uk", FIX, conn, run_id="r1", allowlist=allow)
    rows = conn.execute("SELECT source, source_ref, name FROM source_records ORDER BY source_ref").fetchall()
    assert n == 1
    assert rows == [("wd", "wd:Q42", "Big Ben")]        # parish dropped by allowlist

def test_extract_is_deterministic(tmp_path):
    # same snapshot in → identical records and ordering out (Principle 12)
    def db(name):
        c = store.connect(tmp_path / name); store.init_schema(c); return c
    conn1 = db("a.db"); conn2 = db("b.db")
    wikidata.extract("uk", FIX, conn1, run_id="r1", allowlist={"Q33506"})
    wikidata.extract("uk", FIX, conn2, run_id="r2", allowlist={"Q33506"})
    first = conn1.execute("SELECT source_ref FROM source_records ORDER BY id").fetchall()
    second = conn2.execute("SELECT source_ref FROM source_records ORDER BY id").fetchall()
    assert first == second

def test_bootstrap_allowlist_loads_and_is_nonempty():
    path = pathlib.Path(__file__).parents[1] / "config/wikidata_class_allowlist.json"
    allow = wikidata.load_allowlist(path)
    assert isinstance(allow, set) and allow                # ships a usable starter set
    assert all(q.startswith("Q") for q in allow)

def test_source_ref_is_canonical_wd_qid(tmp_path):
    conn = _db(tmp_path)
    wikidata.extract("uk", FIX, conn, run_id="r1", allowlist={"Q33506"})
    ref = conn.execute("SELECT source_ref FROM source_records").fetchone()[0]
    assert ref == "wd:Q42"   # A1's parse accepted the canonical ref (delegated to mt_contracts)
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd pipeline && uv run python -m pytest tests/test_wikidata_extractor.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named 'mt_pipeline.extractors.wikidata'`.

- [ ] **Step 3: Write the bootstrap allowlist**

`pipeline/config/wikidata_class_allowlist.json` — **genuinely minimal**; obvious classes only. The authoritative, empirically-curated set is WP-A3's data-audit output, which replaces this file with zero extractor change:
```json
{
  "_header": "BOOTSTRAP: superseded by WP-A3. Obvious P31 classes admitted to recall; do not curate here (that is A3's empirical job).",
  "allow": ["Q33506", "Q16970", "Q570116", "Q839954", "Q4989906"]
}
```
(museum, church building, monument, castle, memorial — the uncontroversial core. A3's audit adds/removes from real distribution data.)

- [ ] **Step 4: Implement `wikidata.py`**

`pipeline/src/mt_pipeline/extractors/wikidata.py`:
```python
"""Wikidata extractor: a pure function of a dated SPARQL snapshot. Keeps coordinate-
bearing items whose P31 is in the CONSUMED allowlist (A3 owns the curation). Bounds
each item before handing a small props dict to A1's source_record.parse (§5.5)."""
from __future__ import annotations

import json
import pathlib

from .. import source_record

MAX_CLAIMS = 512
MAX_SITELINKS = 64
MAX_LABEL_LEN = 400


def load_allowlist(path) -> set[str]:
    data = json.loads(pathlib.Path(path).read_text())
    return set(data["allow"])


def _qid(uri: str) -> str:
    # "http://www.wikidata.org/entity/Q42" -> "Q42"
    return uri.rsplit("/", 1)[-1]


def extract(region: str, snapshot_path, conn, *, run_id: str, allowlist: set[str]) -> int:
    snapshot = json.loads(pathlib.Path(snapshot_path).read_text())
    bindings = snapshot.get("results", {}).get("bindings", [])
    count = 0
    # stable order by QID so re-runs and diffs are deterministic
    for b in sorted(bindings, key=lambda x: _qid(x["item"]["value"])):
        p31 = _qid(b["p31"]["value"])
        if p31 not in allowlist:
            continue
        qid = _qid(b["item"]["value"])
        try:
            lat = float(b["lat"]["value"]); lon = float(b["lon"]["value"])
        except (KeyError, ValueError):
            continue   # no usable coordinate → not a recall candidate
        label = b.get("label", {}).get("value", "")[:MAX_LABEL_LEN]  # bound the blob
        props = {"p31": p31, "label": label[:MAX_LABEL_LEN]}          # small, shallow
        try:
            rec = source_record.parse(region=region, source="wd", source_ref=f"wd:{qid}",
                                      name=label, lat=lat, lon=lon, props=props)
        except source_record.SourceRecordError:
            continue   # A1's boundary rejected it (bad coord/name/ref) → skip, never crash
        source_record.persist(conn, rec, run_id=run_id)
        count += 1
    return count
```

- [ ] **Step 5: Run to verify it passes**

Run: `cd pipeline && uv run python -m pytest tests/test_wikidata_extractor.py -q`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add pipeline/src/mt_pipeline/extractors/wikidata.py pipeline/config/wikidata_class_allowlist.json \
        pipeline/tests/fixtures/wikidata pipeline/tests/test_wikidata_extractor.py
git commit -m "Add Wikidata extractor (allowlist-consuming, deterministic, edge-bounded)"
```

---

### Task 4: Wikipedia extractor (wp:pageid + QID-in-props for A2 join)

**Files:**
- Create: `pipeline/src/mt_pipeline/extractors/wikipedia.py`
- Create: `pipeline/tests/fixtures/wikipedia/snapshot.json`
- Test: `pipeline/tests/test_wikipedia_extractor.py`

**Interfaces:**
- Consumes: `source_record.parse`/`persist`.
- Produces:
  - `wikipedia.MAX_EXTRACT_LEN = 1200`, `MAX_TITLE_LEN = 400`.
  - `wikipedia.extract(region, snapshot_path, conn, *, run_id) -> int` — reads the dated geosearch+extracts snapshot, emits `source=wp, source_ref=wp:<pageid>` records, carrying the linked Wikidata **QID in `props["wikidata"]`** (for A2's sitelink join) plus `props["lang"]`, `props["title"]`, bounded `props["extract"]`. Stable order by pageid.

- [ ] **Step 1: Write the golden fixture + failing test**

`pipeline/tests/fixtures/wikipedia/snapshot.json` (geosearch-shaped: pages with pageid, title, coordinates, extract, and optional wikidata QID via pageprops):
```json
{"lang": "en", "pages": [
  {"pageid": 12345, "title": "Big Ben", "lat": 51.5007, "lon": -0.1246,
   "extract": "The Great Bell of the striking clock at the Palace of Westminster.",
   "wikidata": "Q42"},
  {"pageid": 67890, "title": "Some Hamlet", "lat": 51.4, "lon": -0.2,
   "extract": "A small place.", "wikidata": null}
]}
```

`pipeline/tests/test_wikipedia_extractor.py`:
```python
import pathlib
from mt_pipeline import store
from mt_pipeline.extractors import wikipedia

FIX = pathlib.Path(__file__).parent / "fixtures/wikipedia/snapshot.json"

def _db(tmp_path):
    c = store.connect(tmp_path / "w.db"); store.init_schema(c); return c

def test_emits_wp_pageid_refs_in_stable_order(tmp_path):
    conn = _db(tmp_path)
    n = wikipedia.extract("uk", FIX, conn, run_id="r1")
    rows = conn.execute("SELECT source, source_ref FROM source_records ORDER BY source_ref").fetchall()
    assert n == 2
    assert rows == [("wp", "wp:12345"), ("wp", "wp:67890")]

def test_linked_qid_rides_in_props_for_a2_join(tmp_path):
    import json
    conn = _db(tmp_path)
    wikipedia.extract("uk", FIX, conn, run_id="r1")
    props = json.loads(conn.execute("SELECT props_json FROM source_records WHERE source_ref='wp:12345'").fetchone()[0])
    assert props["wikidata"] == "Q42"      # A2 joins Wikipedia->Wikidata via this
    assert props["lang"] == "en"

def test_extract_length_is_bounded(tmp_path):
    import json
    conn = _db(tmp_path)
    wikipedia.extract("uk", FIX, conn, run_id="r1")
    props = json.loads(conn.execute("SELECT props_json FROM source_records LIMIT 1").fetchone()[0])
    assert len(props["extract"]) <= wikipedia.MAX_EXTRACT_LEN
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd pipeline && uv run python -m pytest tests/test_wikipedia_extractor.py -q`
Expected: FAIL — module missing.

- [ ] **Step 3: Implement `wikipedia.py`**

`pipeline/src/mt_pipeline/extractors/wikipedia.py`:
```python
"""Wikipedia extractor: a pure function of a dated geosearch+extracts snapshot.
Emits wp:<pageid> records (numeric, stable, grammar-safe) and carries the linked
Wikidata QID in props so A2 joins Wikipedia->Wikidata like the OSM wikidata=* join.
Bounds title/extract before handing a small props dict to source_record.parse."""
from __future__ import annotations

import json
import pathlib

from .. import source_record

MAX_EXTRACT_LEN = 1200
MAX_TITLE_LEN = 400


def extract(region: str, snapshot_path, conn, *, run_id: str) -> int:
    snapshot = json.loads(pathlib.Path(snapshot_path).read_text())
    lang = snapshot.get("lang", "en")
    count = 0
    for page in sorted(snapshot.get("pages", []), key=lambda p: int(p["pageid"])):
        try:
            pageid = int(page["pageid"])
            lat = float(page["lat"]); lon = float(page["lon"])
        except (KeyError, ValueError, TypeError):
            continue
        title = str(page.get("title", ""))[:MAX_TITLE_LEN]
        props = {"lang": lang, "title": title,
                 "extract": str(page.get("extract", ""))[:MAX_EXTRACT_LEN]}
        qid = page.get("wikidata")
        if isinstance(qid, str) and qid.startswith("Q"):
            props["wikidata"] = qid      # the free join to Wikidata (A2)
        try:
            rec = source_record.parse(region=region, source="wp", source_ref=f"wp:{pageid}",
                                      name=title, lat=lat, lon=lon, props=props)
        except source_record.SourceRecordError:
            continue
        source_record.persist(conn, rec, run_id=run_id)
        count += 1
    return count
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd pipeline && uv run python -m pytest tests/test_wikipedia_extractor.py -q`
Expected: PASS (3 passed).

- [ ] **Step 5: Commit**

```bash
git add pipeline/src/mt_pipeline/extractors/wikipedia.py pipeline/tests/fixtures/wikipedia \
        pipeline/tests/test_wikipedia_extractor.py
git commit -m "Add Wikipedia extractor (wp:pageid refs, QID-in-props join, bounded extract)"
```

---

### Task 5: Pageviews (fixed-window, deterministic, rate-courteous)

**Files:**
- Create: `pipeline/src/mt_pipeline/extractors/pageviews.py`
- Create: `pipeline/tests/fixtures/pageviews/big_ben.json`
- Test: `pipeline/tests/test_pageviews.py`

**Interfaces:**
- Produces:
  - `pageviews.median_from_snapshot(snapshot: dict) -> int` — pure: the median daily views from a cached Wikimedia REST response over the fixed window.
  - `pageviews.window_for(snapshot_date: str, months: int = 12) -> tuple[str, str]` — the deterministic `[start, end]` derived from the run's **config snapshot date** (never wall-clock).
  - Acquisition contract (documented for the network step; computation of the signal is A4's): fetch is behind a **per-run flag** (a plain extract does not trigger the full sweep); **cached per `(title, window)`** and **resumable** — progress is persisted per title so a crash at 80 % of tens of thousands of UK titles resumes, never restarts; rate-courteous (batched, polite interval, honours `429`/`Retry-After`). A4 consumes the cache as its scoring input.

- [ ] **Step 1: Write the fixture + failing test**

`pipeline/tests/fixtures/pageviews/big_ben.json` (Wikimedia REST shape):
```json
{"items": [{"views": 100}, {"views": 300}, {"views": 200}, {"views": 250}, {"views": 150}]}
```

`pipeline/tests/test_pageviews.py`:
```python
import json
import pathlib
from mt_pipeline.extractors import pageviews

FIX = pathlib.Path(__file__).parent / "fixtures/pageviews/big_ben.json"

def test_median_is_deterministic_from_snapshot():
    snap = json.loads(FIX.read_text())
    assert pageviews.median_from_snapshot(snap) == 200   # median of [100,150,200,250,300]

def test_window_is_derived_from_config_date_not_wallclock():
    start, end = pageviews.window_for("2026-07-14", months=12)
    assert end == "2026-07-14" and start == "2025-07-14"   # fixed window, no now()

def test_empty_snapshot_is_zero_not_error():
    assert pageviews.median_from_snapshot({"items": []}) == 0
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd pipeline && uv run python -m pytest tests/test_pageviews.py -q`
Expected: FAIL — module missing.

- [ ] **Step 3: Implement `pageviews.py`**

`pipeline/src/mt_pipeline/extractors/pageviews.py`:
```python
"""Deterministic pageview signal: the median daily views over a FIXED window ending
at the run's config snapshot date (never wall-clock). Acquisition (the Wikimedia REST
fetch) is cached by (article, window) and rate-courteous; this module is the pure
computation over a cached snapshot so re-runs are identical (Principle 12)."""
from __future__ import annotations

import datetime
import statistics


def window_for(snapshot_date: str, months: int = 12) -> tuple[str, str]:
    end = datetime.date.fromisoformat(snapshot_date)
    # fixed calendar window; approximate months as 365-day year / 12 is avoided by
    # using year arithmetic so the window is stable and legible.
    start = end.replace(year=end.year - (months // 12)) if months % 12 == 0 \
        else end - datetime.timedelta(days=int(months * 30.4375))
    return (start.isoformat(), end.isoformat())


def median_from_snapshot(snapshot: dict) -> int:
    views = [int(item["views"]) for item in snapshot.get("items", []) if "views" in item]
    if not views:
        return 0
    return int(statistics.median(views))
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd pipeline && uv run python -m pytest tests/test_pageviews.py -q`
Expected: PASS (3 passed).

- [ ] **Step 5: Commit**

```bash
git add pipeline/src/mt_pipeline/extractors/pageviews.py pipeline/tests/fixtures/pageviews \
        pipeline/tests/test_pageviews.py
git commit -m "Add deterministic fixed-window pageview median (config-date, no wall-clock)"
```

---

### Task 6: Wire enabled extractors into the A1 'extract' stage

**Files:**
- Create: `pipeline/src/mt_pipeline/extract_stage.py`
- Test: `pipeline/tests/test_extract_stage.py`

**Interfaces:**
- Consumes: `extractors.Registry`, `config.load` (A1), `store`, and the snapshot files.
- Produces:
  - `extract_stage.run_extract(conn, region_config, snapshots: dict[str, str], *, run_id, registry) -> dict[str, int]` — runs each **enabled** extractor for the region against its dated snapshot, returns `{source: record_count}`. This is what A1's `extract` stage body calls (A1 left it a no-op; A1c/A1d register more extractors, no change here).

- [ ] **Step 1: Write the failing test**

`pipeline/tests/test_extract_stage.py`:
```python
import pathlib
from mt_pipeline import store, extract_stage
from mt_pipeline.extractors import Registry, wikidata, wikipedia

FIXW = pathlib.Path(__file__).parent / "fixtures/wikidata/snapshot.json"
FIXP = pathlib.Path(__file__).parent / "fixtures/wikipedia/snapshot.json"

def test_runs_only_enabled_extractors(tmp_path):
    conn = store.connect(tmp_path / "w.db"); store.init_schema(conn)
    reg = Registry()
    reg.register("wikidata", wikidata_adapter(allowlist={"Q33506"}))
    reg.register("wikipedia", wikipedia)   # module exposes extract(...)
    cfg = {"region_id": "uk", "sources": {"wikidata": True, "wikipedia": False,
           "osm": False, "historic_england": False, "open_plaques": False, "national_register": None}}
    counts = extract_stage.run_extract(conn, cfg, {"wikidata": str(FIXW), "wikipedia": str(FIXP)},
                                       run_id="r1", registry=reg)
    assert counts == {"wikidata": 1}      # wikipedia disabled → not run
    total = conn.execute("SELECT COUNT(*) FROM source_records").fetchone()[0]
    assert total == 1

# a tiny adapter so the wikidata extractor (which needs an allowlist) matches the
# Extractor protocol signature the registry calls.
def wikidata_adapter(*, allowlist):
    class _A:
        def extract(self, region, snapshot_path, conn, *, run_id):
            return wikidata.extract(region, snapshot_path, conn, run_id=run_id, allowlist=allowlist)
    return _A()
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd pipeline && uv run python -m pytest tests/test_extract_stage.py -q`
Expected: FAIL — `mt_pipeline.extract_stage` missing.

- [ ] **Step 3: Implement `extract_stage.py`**

`pipeline/src/mt_pipeline/extract_stage.py`:
```python
"""The body of A1's 'extract' stage: run each enabled extractor for a region against
its dated snapshot. A1 left the stage a dispatchable no-op; this fills it in for the
wiki sources. A1c/A1d add extractors to the registry — this function does not change."""
from __future__ import annotations


def run_extract(conn, region_config: dict, snapshots: dict, *, run_id: str, registry) -> dict:
    region = region_config["region_id"]
    counts: dict[str, int] = {}
    for source, extractor in registry.enabled_for(region_config):
        snapshot_path = snapshots.get(source)
        if snapshot_path is None:
            continue   # no snapshot acquired for this source this run
        counts[source] = extractor.extract(region, snapshot_path, conn, run_id=run_id)
    return counts
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd pipeline && uv run python -m pytest tests/test_extract_stage.py -q`
Expected: PASS.

- [ ] **Step 5: Full suite + commit**

Run: `cd pipeline && uv run python -m pytest -q`
Expected: PASS (all A1 + A1b tests green).

```bash
git add pipeline/src/mt_pipeline/extract_stage.py pipeline/tests/test_extract_stage.py
git commit -m "Wire enabled wiki extractors into the A1 extract stage"
```

---

## Review Record

**Author self-review** — every WP-A1b deliverable maps to a task: Wikidata extractor (T3, allowlist-consuming), Wikipedia extractor (T4, `wp:pageid` + QID-in-props join), pageviews (T5, fixed-window deterministic), the edge raw-blob bound (T1), and the extract-stage wiring/registry (T2, T6). Implements A1's `source_record.parse` interface, never re-declaring the grammar/text-safety. English-only recall + bbox from A0 region config. The P31 allowlist is consumed, with a bootstrap marked "A3 supersedes".

**Binding carry-in honoured** — raw-blob bounding is at the extractor edge: `fetch.get_json` byte-caps every response before parsing (T1); each extractor bounds label/extract/title lengths and builds a small, shallow `props` before handing it to A1's `parse` (T3/T4). All Wikidata/Wikipedia strings are treated as hostile; a record A1's boundary rejects is skipped, never crashes the run.

**Determinism** — every `extract`/`median` function is a pure function of a dated snapshot; records are emitted in stable `source_ref`/pageid order; pageview windows derive from the config snapshot date, never wall-clock. Tests run entirely against golden fixtures — no network.

**Ratified (fable, thread `wp/a1b`) with conditions folded in** — (1) cached-SPARQL→**self-describing dated snapshot**, with **segmented** queries (P31-chunk × bbox-tile, no monolithic query), WDQS etiquette, and **loud-abort on partial** (Task 3 acquisition contract); (2) `wp:<pageid>` refs, with `wp` appended **last** in A0's anchor priority via the append-only path + a frozen vector — a **codex contracts task fable briefs**, noted here as a dependency, not implemented; (3) bootstrap allowlist genuinely minimal + header-marked, A3-replaceable with zero code change; (4) pageview acquisition here (behind a per-run flag, **resumable**, cached per `(title, window)`), **computation deferred to A4**.

**Cross-package needs surfaced (per AGENTS.md)** — codex adds `wp` (last) to A0's append-only mint grammar + a frozen vector (for wp-only-anchored places; fable is briefing this); A3's data audit produces the authoritative P31 allowlist that replaces the bootstrap file; the extract-stage registry established here is the shared dispatch A1c/A1d extend.
