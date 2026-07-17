# WP-A1c (OSM Extractor) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A deterministic, §5.5-hardened **OSM extractor** — `pyosmium` **streaming** over a dated Geofabrik `.pbf` extract — that keeps candidate-tagged features (`historic=*`, `tourism∈{attraction,artwork,viewpoint}`, `memorial=*`, … from a consumed config), emits normalized source records via WP-A1's interface, and captures the `wikidata=*` tag as the A2 join key. Registers `osm` into the extractor registry WP-A1b established.

**Architecture:** Under `pipeline/` (the WP-A1 `mt_pipeline` package). The extractor **streams** the `.pbf` with `pyosmium` — only the *filtered* candidate records are held (bounded by `MAX_CANDIDATE_RECORDS`), and the separate node-location index that way centroids require (O(all nodes)) uses a selectable backend (`index_type` → `apply_file(idx=...)`; in-RAM for regional/tests, disk-backed for a country `.pbf`). Way points are a **deterministic arithmetic-mean (vertex) centroid** with the repeated closing node of closed ways dropped; **node** coordinates are direct; **relations are deferred** (`WP-A1c-relations`). Every field is bounded at the extractor edge before A1's `source_record.parse` (the binding carry-in). The determinism boundary is the dated Geofabrik file, recorded self-describingly in a `<file>.pbf.meta.json` sidecar (URL, date, sha256, size); the extractor verifies the sha256 when the sidecar is present (defensively — the sidecar is itself untrusted).

**Tech Stack:** Python 3.11+ (the WP-A1 `mt_pipeline` package + `mt-contracts`), **`pyosmium` (`osmium`)** — the spec's OSM reader (§5.2), stdlib `json`/`hashlib`/`logging`, `pytest`.

## Global Constraints

- **Implements A1's interface + extends A1b's registry, never re-declares them.** Records are produced only via `mt_pipeline.source_record.parse(...)` / `persist(...)`; `osm` registers into `mt_pipeline.extractors.Registry` and runs through `extract_stage.build_registry`. Canonical-ref grammar + text-safety are `mt_contracts`' (via `parse`). **A1 preconditions** (present on develop, from the merged A1 impl PR #33): `source_record.parse`/`persist`/`SourceRecordError`; `store.connect`/`store.init_schema`; `config.RegionConfig`; `is_canonical_ref` already accepts `osm:node/…`, `osm:way/…`. **A1b preconditions** (`extractors.Registry`/`Extractor`, `extract_stage.build_registry`/`run_extract`, `wikidata.make_extractor`, `WikipediaExtractor`): the A1b **plan** is merged (PR #34) but its **impl is not yet on develop** (only the `wp-a1b-plan` branch exists). This plan is written against A1b's published interface; **A1c's impl is BLOCKED on A1b's impl landing first** — Task 2/4 conform to and modify symbols A1b introduces. Sequencing surfaced to fable, thread `wp/a1c` (see Cross-package needs).
- **Streaming, bounded memory (fable) — with the node-location index sized honestly.** `pyosmium` streams the file, and the extractor holds only the *candidate* records (a filtered subset) — that set is bounded by `MAX_CANDIDATE_RECORDS`. **The node-location index that way centroids need is a separate, larger cost:** `apply_file(locations=True)` caches the coordinate of **every node in the file** (O(all nodes), not O(candidates)), so a country `.pbf` (hundreds of millions of nodes) needs the right index backend. pyosmium's `apply_file(..., idx=...)` selects it; the extractor **exposes an `index_type` parameter** (default `"flex_mem"`, in-RAM — fine for tests/regional extracts) that is **threaded into `apply_file(idx=...)`**, so a country-scale run passes a disk-backed store (e.g. `"sparse_file_array,<path>"`). This is a real plumbed parameter, **not** a hardcoded call — the earlier "a knob, not a code change" framing was wrong and is corrected here.
- **Deterministic (Principle 12).** `extract(pbf, …)` is a pure function of the dated `.pbf`: same file → identical records, identical order. Records emit in **stable lexical `source_ref` order** (collected then sorted), de-duped by `source_ref`. The **way-centroid is the arithmetic mean of the way's node locations** (the *vertex* mean — a representative point, not the polygon-area centroid). Determinism rests on the **node iteration order being fixed by the file** (floating-point addition is not associative, so the "formula" alone is not order-free — the file pins the order, hence `.osm`/`.pbf` parity). **Closed ways** (the dominant polygon case: `nd 1,2,3,4,1`) repeat the first node as the last; the extractor **drops the repeated closing node before averaging** so a vertex is not double-weighted. A fixture way with a hand-computed centroid pins the mean (see Task 2). No wall-clock/randomness in outputs.
- **Never crash on hostile input, with a per-feature vs file-level split (Principle 10 / §5.5 / binding carry-in; verified against pyosmium 4.3.1).** Two distinct failure classes:
  - **Per-feature** hostile content *within OSM limits* (weird tag values, a feature with hundreds of tags, a missing `name`, an off-globe coordinate, a garbage `wikidata` tag): each per-feature body runs inside a `try/except` that **skips** the feature — never aborts the stream. Raw-blob bounding at the edge: `MAX_TAGS_PER_FEATURE` (props built once, bounded up front), `MAX_TAG_KEY_LEN`/`MAX_TAG_VAL_LEN`, `MAX_NAME_LEN` — a small, shallow `props` reaches `parse`. `wikidata` is shape+length validated (`Q[0-9]+`, `MAX_QID_LEN`) before it becomes an A2 join key (a garbage value drops only the key). `MAX_CANDIDATE_RECORDS` caps memory with a loud `TooManyCandidatesError`.
  - **File-level** corruption (an over-long tag value — OSM itself caps values at ~255, so this is only reachable via a corrupt file — or a truncated/garbage `.pbf`): pyosmium's **reader raises `ValueError`/`RuntimeError` at the C level, escaping the per-feature guards**. That is caught in `extract` and re-raised as a **typed `OsmParseError` — a loud, clean abort**, because a corrupt file is not extractable (and it is backstopped by the provenance sha256 check). This distinction was found by actually running pyosmium; a naive per-feature-only guard would let a corrupt file crash the run with an uncaught exception.
  Nothing from OSM is interpolated into shell/SQL/LLM.
- **Self-describing provenance (A1b precedent) — and the sidecar is itself untrusted (Principle 10).** The dated Geofabrik file is the determinism boundary. Acquisition (deferred, `WP-A1c-acquire`) writes a `<file>.pbf.meta.json` sidecar (`source_url`, `geofabrik_date`, `sha256`, `size`). Extract behaviour, pinned exactly: **sidecar present → verify the `.pbf` sha256, LOUD `ProvenanceError` on mismatch; sidecar absent (a hand-placed dev file) → proceed with a logged provenance warning.** The sha256 is **integrity, not authenticity** (a coordinated file+sidecar swap passes; absent-sidecar-bypass is available to anyone with input-dir write access) — so the absent→warn policy is for *dev convenience*; production acquisition (`WP-A1c-acquire`) is expected to **fail closed**. The sidecar is parsed **defensively**: its size is bounded before reading, and any malformed/oversized/wrong-shape sidecar (non-dict JSON, missing `sha256`, giant/deeply-nested file) raises a typed `ProvenanceError`, never an uncaught `AttributeError`/`RecursionError`. (A truncated `.pbf` also fails pyosmium's own parse — an integrity backstop.)
- **Candidate tags are CONSUMED config, not code (§4).** A bootstrap tag-filter ships here (`historic=*`, `tourism∈{attraction,artwork,viewpoint}`, `memorial=*`, …), header-marked `BOOTSTRAP: superseded by WP-A3`; A3's data audit refines from the real tag distribution with zero code change. OSM tag-value rarity is an **A4** scoring signal — A1c does not score. **`props` carries the full *bounded* tag set** (first `MAX_TAGS_PER_FEATURE`, each key/value length-capped) plus a validated `wikidata`, **not** only the matched candidate keys — A4's tag-value-rarity signal needs the whole tag distribution, and the candidate filter decides *whether* a feature is kept, not *which* of its tags survive. (`name` therefore appears both as the record's `name` field and in `props["name"]` — an intentional, harmless redundancy.)
- **`wikidata=*` is the free join (§5.2).** An OSM feature's `wikidata` tag rides in `props["wikidata"]` so A2 clusters it onto the QID-anchored place, exactly like A1b's `wp→wd` join. (A2 must read `props["wikidata"]` — already on issue #6.)
- **Relations deferred (`WP-A1c-relations`), justified.** Recall for big multipolygon sites (castles, abbeys, parks) is COVERED: those places virtually always have coordinate-bearing Wikidata items, so the union already includes them — the OSM relation adds geometry *precision*, not *existence*. v1 = nodes + ways.
- **Test-first**, against `.osm` XML fixtures **plus one `.pbf` parity test** (write the same data with `pyosmium.SimpleWriter`, assert identical records from `.osm` and `.pbf`) so tests cover the binary path production actually parses.
- **English/region config.** The candidate-tag filter and bbox are region-agnostic tag logic; the `.pbf` is the per-region Geofabrik extract (region resolved by the acquisition step).

**Ratified (fable, thread `wp/a1c`)** — all five: nodes+way-centroids (relations → `WP-A1c-relations`, justified) with a pinned deterministic centroid; `.osm` fixtures + a binary `.pbf` parity test; bootstrap tag allowlist in pipeline config; deferred acquisition + self-describing `.pbf.meta.json` sidecar (present→verify sha256 loud; absent→warn); `osmium` dependency (escalate if the sandbox blocks the install — do not silently degrade to XML-only verification).

---

## File Structure

```
pipeline/src/mt_pipeline/extractors/
  osm.py                                # OsmExtractor + make_extractor(tag_config_path); centroid; provenance
pipeline/config/
  osm_candidate_tags.json               # BOOTSTRAP candidate-tag filter (A3 supersedes)
pipeline/src/mt_pipeline/
  extract_stage.py                      # MODIFY: register "osm" in build_registry (Task 4)
pipeline/tests/
  fixtures/osm/sample.osm               # .osm XML: candidate node, candidate way, non-candidate node, a relation
  test_osm_extractor.py                 # Task 2/3
  test_extract_stage_osm.py             # Task 4
```

---

### Task 1: Bootstrap candidate-tag config + the tag-match + provenance helpers

**Files:**
- Create: `pipeline/config/osm_candidate_tags.json`
- Create: `pipeline/src/mt_pipeline/extractors/osm.py` (helpers only this task)
- Test: `pipeline/tests/test_osm_extractor.py` (helper tests this task)

**Interfaces:**
- Produces:
  - `osm.load_tag_config(path) -> dict[str, object]` — the consumed candidate-tag filter (`{key: True}` for key=*, `{key: [values]}` for key∈values).
  - `osm.is_candidate(tags: dict, config) -> bool`.
  - `osm.ProvenanceError`, `osm.OsmParseError` (file-level parse failure → loud abort), `osm.TooManyCandidatesError` (memory-bounded abort); `osm.verify_provenance(pbf_path) -> None` (sidecar present → verify sha256, raise on mismatch; absent → log warning, return).
  - Caps: `MAX_TAGS_PER_FEATURE = 200`, `MAX_TAG_KEY_LEN = 100`, `MAX_TAG_VAL_LEN = 300`, `MAX_NAME_LEN = 300`, `MAX_QID_LEN = 24`, `MAX_CANDIDATE_RECORDS = 5_000_000`, `MAX_SIDECAR_BYTES = 64 * 1024` (the untrusted sidecar is size-bounded before it is read/parsed).

- [ ] **Step 1: Write the failing helper tests**

`pipeline/tests/test_osm_extractor.py`:
```python
import json
import hashlib
import pathlib
import pytest
from mt_pipeline.extractors import osm

def test_is_candidate_matches_key_wildcard_and_value_set():
    cfg = {"historic": True, "tourism": ["attraction", "artwork", "viewpoint"], "memorial": True}
    assert osm.is_candidate({"historic": "castle"}, cfg)          # key=* wildcard
    assert osm.is_candidate({"tourism": "artwork"}, cfg)          # value in set
    assert not osm.is_candidate({"tourism": "hotel"}, cfg)        # value NOT in set
    assert not osm.is_candidate({"amenity": "bench"}, cfg)        # key not in config

def test_bootstrap_tag_config_loads_and_is_minimal():
    cfg = osm.load_tag_config(pathlib.Path(__file__).parents[1] / "config/osm_candidate_tags.json")
    assert cfg and "historic" in cfg
    assert cfg["tourism"] == ["attraction", "artwork", "viewpoint"]

def test_provenance_verifies_sha256_and_is_loud_on_mismatch(tmp_path):
    pbf = tmp_path / "uk.pbf"; pbf.write_bytes(b"PBFDATA")
    sha = hashlib.sha256(b"PBFDATA").hexdigest()
    (tmp_path / "uk.pbf.meta.json").write_text(json.dumps({"source_url": "u", "geofabrik_date": "2026-07-14", "sha256": sha, "size": 7}))
    osm.verify_provenance(pbf)                                    # matches → no raise
    (tmp_path / "uk.pbf.meta.json").write_text(json.dumps({"sha256": "deadbeef"}))
    with pytest.raises(osm.ProvenanceError):
        osm.verify_provenance(pbf)                                # mismatch → LOUD

def test_provenance_absent_sidecar_proceeds_with_warning(tmp_path, caplog):
    pbf = tmp_path / "dev.pbf"; pbf.write_bytes(b"x")
    osm.verify_provenance(pbf)                                    # no sidecar → returns (dev file)
    assert any("provenance" in r.message.lower() for r in caplog.records)

def test_provenance_malformed_sidecar_is_a_typed_error_not_attributeerror(tmp_path):
    # The sidecar is UNTRUSTED (Principle 10). A non-dict / missing-key / oversized sidecar
    # must raise the typed ProvenanceError — never an uncaught AttributeError/RecursionError.
    pbf = tmp_path / "uk.pbf"; pbf.write_bytes(b"PBFDATA")
    meta = tmp_path / "uk.pbf.meta.json"
    meta.write_text('["not", "a", "dict"]')                      # JSON list, not an object
    with pytest.raises(osm.ProvenanceError):
        osm.verify_provenance(pbf)
    meta.write_text(json.dumps({"source_url": "u"}))             # dict but NO sha256 key
    with pytest.raises(osm.ProvenanceError):
        osm.verify_provenance(pbf)
    meta.write_bytes(b"{" + b" " * (osm.MAX_SIDECAR_BYTES + 10)) # oversized → refused before parse
    with pytest.raises(osm.ProvenanceError):
        osm.verify_provenance(pbf)
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd pipeline && uv run python -m pytest tests/test_osm_extractor.py -q`
Expected: FAIL — `ModuleNotFoundError: No module named 'mt_pipeline.extractors.osm'`.

- [ ] **Step 3: Write the bootstrap config**

`pipeline/config/osm_candidate_tags.json`:
```json
{
  "_header": "BOOTSTRAP: superseded by WP-A3. Obvious OSM candidate tags only; A3's audit refines from real tag distribution.",
  "tags": {
    "historic": true,
    "tourism": ["attraction", "artwork", "viewpoint"],
    "memorial": true,
    "man_made": ["obelisk"]
  }
}
```
*(`man_made=tower` is deliberately **excluded** — it matches high-volume utility/water/telecom towers, recall noise A3 would have to prune; `obelisk` is a monument. The bootstrap errs toward precision; A3's audit widens/narrows from the real tag distribution.)*

- [ ] **Step 4: Implement the helpers in `osm.py`**

`pipeline/src/mt_pipeline/extractors/osm.py` (helper portion; the extractor class is Task 2):
```python
"""OSM extractor: pyosmium streaming over a dated Geofabrik .pbf. Keeps candidate-
tagged features (consumed config), computes a deterministic arithmetic-mean way
centroid, captures wikidata=* as the A2 join key, and bounds every field before
A1's source_record.parse (§5.5). Nodes + ways; relations are WP-A1c-relations."""
from __future__ import annotations

import hashlib
import json
import logging
import pathlib

MAX_TAGS_PER_FEATURE = 200
MAX_TAG_KEY_LEN = 100
MAX_TAG_VAL_LEN = 300           # defense-in-depth: OSM itself caps tag values at 255 (pyosmium rejects longer)
MAX_NAME_LEN = 300
MAX_QID_LEN = 24
MAX_CANDIDATE_RECORDS = 5_000_000   # loud-abort ceiling on candidates held (a real region is far smaller)
MAX_SIDECAR_BYTES = 64 * 1024       # the UNTRUSTED provenance sidecar is size-bounded before read/parse

_log = logging.getLogger(__name__)


class ProvenanceError(Exception):
    pass


class OsmParseError(Exception):
    """The FILE could not be parsed by pyosmium (over-long tag, corrupt/truncated .pbf).
    A file-level parse error escapes apply_file and is NOT a per-feature skip — it is a
    loud, clean abort (a corrupt file is not extractable; provenance sha256 backstops it)."""


class TooManyCandidatesError(Exception):
    """More than MAX_CANDIDATE_RECORDS candidate features — a hostile/wrong file. Loud abort,
    memory-bounded (we stop rather than grow unbounded)."""


def load_tag_config(path) -> dict:
    return json.loads(pathlib.Path(path).read_text())["tags"]


def is_candidate(tags: dict, config: dict) -> bool:
    for key, allowed in config.items():
        if key in tags:
            if allowed is True or (isinstance(allowed, list) and tags[key] in allowed):
                return True
    return False


def _sha256_file(path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def verify_provenance(pbf_path) -> None:
    meta_path = pathlib.Path(str(pbf_path) + ".meta.json")
    if not meta_path.exists():
        # Absent sidecar → integrity check skipped. This is a DEV convenience (a hand-placed
        # file); it is NOT authentication and is bypassable by anyone who can write the input
        # dir. Production acquisition (WP-A1c-acquire) is expected to fail closed, not warn.
        _log.warning("no provenance sidecar for %s — proceeding (hand-placed dev file)", pbf_path)
        return
    # The sidecar is UNTRUSTED (Principle 10): bound its size BEFORE reading, and turn every
    # malformed/oversized/wrong-shape case into a typed ProvenanceError (never AttributeError).
    if meta_path.stat().st_size > MAX_SIDECAR_BYTES:
        raise ProvenanceError(f"provenance sidecar for {pbf_path} exceeds {MAX_SIDECAR_BYTES} bytes")
    try:
        meta = json.loads(meta_path.read_text())
    except (ValueError, RecursionError) as e:
        raise ProvenanceError(f"unparseable provenance sidecar for {pbf_path}: {e}") from e
    if not isinstance(meta, dict) or not isinstance(meta.get("sha256"), str):
        raise ProvenanceError(f"provenance sidecar for {pbf_path} lacks a string 'sha256'")
    actual = _sha256_file(pbf_path)
    if actual != meta["sha256"]:
        raise ProvenanceError(f"sha256 mismatch for {pbf_path}: {actual} != {meta['sha256']}")
```

- [ ] **Step 5: Run to verify it passes**

Run: `cd pipeline && uv run python -m pytest tests/test_osm_extractor.py -q`
Expected: PASS (5 passed).

- [ ] **Step 6: Commit**

```bash
git add pipeline/config/osm_candidate_tags.json pipeline/src/mt_pipeline/extractors/osm.py \
        pipeline/tests/test_osm_extractor.py
git commit -m "Add OSM candidate-tag config + tag-match + provenance-sidecar helpers"
```

---

### Task 2: The pyosmium streaming extractor (nodes + way-centroids, crash-safe, deterministic)

**Files:**
- Modify: `pipeline/src/mt_pipeline/extractors/osm.py` (add the extractor)
- Modify: `pipeline/pyproject.toml` (add `osmium` dependency)
- Test: `pipeline/tests/test_osm_extractor.py`, `pipeline/tests/fixtures/osm/sample.osm`

**Interfaces:**
- Consumes: `osmium`, `source_record.parse`/`persist`.
- Produces:
  - `osm.OsmExtractor(tag_config: dict)` — implements the A1b `Extractor` protocol: `extract(region, snapshot_path, conn, *, run_id, index_type="flex_mem") -> int`. `index_type` selects pyosmium's node-location index backend (`"flex_mem"` in-RAM default; a country-scale caller passes a disk-backed store such as `"sparse_file_array,<path>"`), threaded into `apply_file(idx=index_type)`.
  - `osm.make_extractor(tag_config_path) -> OsmExtractor` (production factory: loads the bootstrap/A3 config).
  - Each kept feature emits `source=osm, source_ref=osm:{node|way}/<id>`, `name` from `tags["name"]` (bounded), and `props` = the **full bounded tag set** (first `MAX_TAGS_PER_FEATURE`, each key/value length-capped) + a validated `wikidata?` — **not** only the matched candidate keys (A4 needs the whole tag distribution) — de-duped by `source_ref`, stable lexical order, every field guarded, relations skipped, dropped-feature count logged.

- [ ] **Step 1: Write the `.osm` fixture + failing tests**

`pipeline/tests/fixtures/osm/sample.osm`. The way is **closed** (`nd 1,2,3,4,1` — the real polygon case) and **asymmetric** so its arithmetic-mean centroid is distinct from the bbox-center — this is what gives the centroid test teeth (a bbox-center or area-centroid impl computes a *different* point and fails). Nodes: `(0,0),(0,2),(2,2),(4,0)`. Dedup-mean = `((0+0+2+4)/4, (0+2+2+0)/4)` = **`(1.5, 1.0)`**; bbox-center would be `((0+4)/2,(0+2)/2)` = `(2.0, 1.0)` — different, so the assertion discriminates. Node 10 is a candidate; node 11 is non-candidate; a relation must be ignored:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<osm version="0.6" generator="test">
  <node id="1" lat="0.0" lon="0.0"/>
  <node id="2" lat="0.0" lon="2.0"/>
  <node id="3" lat="2.0" lon="2.0"/>
  <node id="4" lat="4.0" lon="0.0"/>
  <node id="10" lat="51.5" lon="-0.12" version="1">
    <tag k="historic" v="memorial"/>
    <tag k="name" v="A Memorial"/>
    <tag k="wikidata" v="Q42"/>
  </node>
  <node id="11" lat="51.4" lon="-0.10" version="1">
    <tag k="amenity" v="bench"/>
  </node>
  <way id="100" version="1">
    <nd ref="1"/><nd ref="2"/><nd ref="3"/><nd ref="4"/><nd ref="1"/>
    <tag k="historic" v="castle"/>
    <tag k="name" v="A Castle"/>
  </way>
  <relation id="200" version="1">
    <member type="way" ref="100" role="outer"/>
    <tag k="historic" v="ruins"/>
  </relation>
</osm>
```

`test_osm_extractor.py` (append):
```python
from mt_pipeline import store

# ONE _db helper, used by every OSM test (Task 2 + Task 3). store.connect does NOT mkdir and
# init_schema is separate (verified against A1's store.py), so take a full path and add ".db".
def _db(p): c = store.connect(str(p) + ".db"); store.init_schema(c); return c
FIX = pathlib.Path(__file__).parent / "fixtures/osm/sample.osm"
CFG = {"historic": True, "tourism": ["attraction", "artwork", "viewpoint"], "memorial": True}

def test_extracts_nodes_and_way_centroids_skips_noncandidate_and_relations(tmp_path):
    conn = _db(tmp_path / "w")
    n = osm.OsmExtractor(CFG).extract("uk", FIX, conn, run_id="r1")
    rows = conn.execute("SELECT source_ref, name, lat, lon FROM source_records ORDER BY source_ref").fetchall()
    assert n == 2                                        # node 10 + way 100; node 11 + relation 200 excluded
    assert rows[0][0] == "osm:node/10" and rows[1][0] == "osm:way/100"
    # CLOSED asymmetric way, nodes (0,0),(0,2),(2,2),(4,0) with closing node 1 dropped:
    # arithmetic-mean centroid = (1.5, 1.0). A bbox-center impl would give (2.0, 1.0) and FAIL here.
    assert abs(rows[1][2] - 1.5) < 1e-9 and abs(rows[1][3] - 1.0) < 1e-9

def test_wikidata_tag_rides_in_props_as_the_a2_join_key(tmp_path):
    conn = _db(tmp_path / "w")
    osm.OsmExtractor(CFG).extract("uk", FIX, conn, run_id="r1")
    props = json.loads(conn.execute("SELECT props_json FROM source_records WHERE source_ref='osm:node/10'").fetchone()[0])
    assert props["wikidata"] == "Q42" and props["historic"] == "memorial"

def test_binary_pbf_parity_with_xml(tmp_path):
    # write the SAME data as a .pbf via pyosmium and assert identical records (kills format divergence).
    # The way is closed (nodes 1,2,3,4,1) exactly as in the .osm fixture.
    import osmium
    pbf = tmp_path / "sample.pbf"
    w = osmium.SimpleWriter(str(pbf))
    for nid, lat, lon, tags in [(1,0.0,0.0,{}),(2,0.0,2.0,{}),(3,2.0,2.0,{}),(4,4.0,0.0,{}),
                                (10,51.5,-0.12,{"historic":"memorial","name":"A Memorial","wikidata":"Q42"}),
                                (11,51.4,-0.10,{"amenity":"bench"})]:
        w.add_node(osmium.osm.mutable.Node(id=nid, location=(lon, lat), tags=tags))
    w.add_way(osmium.osm.mutable.Way(id=100, nodes=[1,2,3,4,1], tags={"historic":"castle","name":"A Castle"}))
    w.close()
    ca, cb = _db(tmp_path / "x"), _db(tmp_path / "y")
    osm.OsmExtractor(CFG).extract("uk", FIX, ca, run_id="r1")
    osm.OsmExtractor(CFG).extract("uk", pbf, cb, run_id="r1")
    xa = ca.execute("SELECT source_ref, name, lat, lon FROM source_records ORDER BY source_ref").fetchall()
    xb = cb.execute("SELECT source_ref, name, lat, lon FROM source_records ORDER BY source_ref").fetchall()
    assert xa == xb                                     # identical records from .osm and .pbf
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd pipeline && uv run python -m pytest tests/test_osm_extractor.py -q`
Expected: FAIL — `OsmExtractor` not defined.

- [ ] **Step 3: Add `osmium` to deps + implement the extractor**

Add to `pipeline/pyproject.toml` `dependencies`: `"osmium>=4.0"` (pyosmium; wheels available). The 4.x floor is required — the extractor uses the 4.x API surface (`apply_file(idx=...)`, `osmium.osm.mutable.Node(location=(lon, lat))`, `Location.valid()` enforcing Earth range), all verified against 4.3.1. Then `uv sync`.

Append to `pipeline/src/mt_pipeline/extractors/osm.py`:
```python
import osmium

from .. import source_record


def _validate_qid(value):
    import re
    return isinstance(value, str) and len(value) <= MAX_QID_LEN and re.fullmatch(r"Q[0-9]+", value)


def _bounded_props(o) -> dict:
    # build the props dict ONCE from the TagList, bounded up front (never > MAX_TAGS_PER_FEATURE
    # keys, each key/value length-capped) — so hostile tag bulk can't blow memory or reach parse.
    props: dict = {}
    for i, t in enumerate(o.tags):
        if i >= MAX_TAGS_PER_FEATURE:
            break
        props[t.k[:MAX_TAG_KEY_LEN]] = t.v[:MAX_TAG_VAL_LEN]
    wd = props.pop("wikidata", None)
    if _validate_qid(wd):
        props["wikidata"] = wd                 # only a well-shaped QID becomes an A2 join key
    return props


class _CandidateHandler(osmium.SimpleHandler):
    def __init__(self, config: dict) -> None:
        super().__init__()
        self.config = config
        self.records: dict[str, dict] = {}     # source_ref -> record (dedup); only CANDIDATES held
        self.dropped = 0                        # per-feature skips (auditability — see extract())

    def _consider(self, typ: str, oid: int, lat: float, lon: float, o) -> None:
        props = _bounded_props(o)
        if not is_candidate(props, self.config):
            return
        ref = f"osm:{typ}/{oid}"
        if ref in self.records:
            return
        if len(self.records) >= MAX_CANDIDATE_RECORDS:      # memory-bounded loud abort
            raise TooManyCandidatesError(f"exceeded {MAX_CANDIDATE_RECORDS} candidates")
        name = (props.get("name") or "")[:MAX_NAME_LEN]
        self.records[ref] = {"lat": lat, "lon": lon, "name": name, "props": props}

    def node(self, o) -> None:
        try:
            # o.location.valid() is FALSE for any off-Earth coordinate (verified: lat 91/99/200
            # all invalid), and reading .lat on an invalid location raises — so guard THEN read.
            if o.location.valid():
                self._consider("node", o.id, o.location.lat, o.location.lon, o)
        except TooManyCandidatesError:
            raise                               # loud abort propagates
        except Exception as e:                  # one bad feature NEVER aborts the stream...
            self.dropped += 1                   # ...but the drop is counted + logged (not silent)
            _log.debug("skipped node %s: %s: %s", getattr(o, "id", "?"), type(e).__name__, e)

    def way(self, o) -> None:
        try:
            nodes = list(o.nodes)
            # CLOSED ways repeat node[0] as the last ref; drop it so a vertex is not double-weighted
            # (verified: refs [1,2,3,4,1] → mean 1.2 WITH dup vs 1.5 deduped). Only valid locations
            # contribute (invalid/off-globe vertices are excluded, never laundered into an in-range mean).
            if len(nodes) >= 2 and nodes[0].ref == nodes[-1].ref:
                nodes = nodes[:-1]
            locs = [(n.location.lat, n.location.lon) for n in nodes if n.location.valid()]
            if locs:
                lat = sum(a for a, _ in locs) / len(locs)   # arithmetic-mean (vertex) centroid
                lon = sum(b for _, b in locs) / len(locs)
                self._consider("way", o.id, lat, lon, o)
        except TooManyCandidatesError:
            raise
        except Exception as e:
            self.dropped += 1
            _log.debug("skipped way %s: %s: %s", getattr(o, "id", "?"), type(e).__name__, e)
    # relations intentionally NOT handled → WP-A1c-relations


class OsmExtractor:
    def __init__(self, tag_config: dict) -> None:
        self.tag_config = tag_config

    def extract(self, region: str, snapshot_path, conn, *, run_id: str,
                index_type: str = "flex_mem") -> int:
        verify_provenance(snapshot_path)                  # sidecar sha256 (loud) or dev-file warning
        handler = _CandidateHandler(self.tag_config)
        try:
            # locations=True builds a node-location index (needed for way centroids). idx selects
            # the backend: "flex_mem" (in-RAM, default) for tests/regional; a disk-backed store
            # (e.g. "sparse_file_array,<path>") for a country .pbf whose node count won't fit in RAM.
            handler.apply_file(str(snapshot_path), locations=True, idx=index_type)
        except TooManyCandidatesError:
            raise
        except (ValueError, RuntimeError) as e:
            # pyosmium's READER raises at the C level for an over-long tag / corrupt / truncated
            # file — this escapes the per-feature guards, so a corrupt FILE is a loud, clean abort
            # (backstopped by the provenance sha256 check), NOT a silent skip.
            raise OsmParseError(f"pyosmium could not parse {snapshot_path}: {e}") from e
        if handler.dropped:                               # mass-drops are visible, never silent
            _log.warning("osm extract %s: skipped %d malformed feature(s)", snapshot_path, handler.dropped)
        count = 0
        for ref in sorted(handler.records):               # stable lexical source_ref order
            r = handler.records[ref]
            try:
                rec = source_record.parse(region=region, source="osm", source_ref=ref,
                                          name=r["name"], lat=r["lat"], lon=r["lon"], props=r["props"])
            except source_record.SourceRecordError:
                continue                                  # per-feature: A1's boundary rejected it → skip
            source_record.persist(conn, rec, run_id=run_id)
            count += 1
        return count


def make_extractor(tag_config_path) -> OsmExtractor:
    return OsmExtractor(load_tag_config(tag_config_path))
```
*(pyosmium API — **verified against 4.3.1 on this host**: `SimpleHandler` + `apply_file(path, locations=True, idx="flex_mem")` gives ways their node locations via `o.nodes[i].location` (valid via `.valid()`); `o.nodes[i].ref` is the node id (used for the closing-node dedup); iterate `o.tags` for `.k`/`.v`; `o.location.valid()`/`.lat`/`.lon` for nodes — `.valid()` is FALSE for any off-Earth coordinate and reading `.lat` on an invalid location raises `InvalidLocationError`. `SimpleWriter` + `osmium.osm.mutable.Node(id=, location=(lon, lat), tags=)`/`.Way(id=, nodes=[...], tags=)`. An exception raised inside a callback propagates **as its own type** through `apply_file` (so `TooManyCandidatesError` is caught before the `(ValueError, RuntimeError)` arm — verified). The reader raises `ValueError` (over-long tag) / `RuntimeError` (garbage `.pbf`) on a malformed file — caught and re-raised as `OsmParseError`. `idx` accepts `flex_mem`/`sparse_file_array`/`dense_file_array`/… — the disk-backed knob.)*

- [ ] **Step 4: Run to verify it passes**

Run: `cd pipeline && uv run python -m pytest tests/test_osm_extractor.py -q`
Expected: PASS — nodes+way-centroid, wikidata join key, `.osm`/`.pbf` parity all green.

- [ ] **Step 5: Commit**

```bash
git add pipeline/src/mt_pipeline/extractors/osm.py pipeline/pyproject.toml \
        pipeline/tests/fixtures/osm pipeline/tests/test_osm_extractor.py
git commit -m "Add pyosmium OSM extractor: streaming, crash-safe, arithmetic-mean way centroid, .pbf parity"
```

---

### Task 3: Edge-hardening tests (hostile input, skip-never-crash, determinism)

**Files:**
- Test: `pipeline/tests/test_osm_extractor.py` (append)

**Interfaces:** consumes Task 2. Pins the §5.5 binding-carry-in invariants.

- [ ] **Step 1: Write the hardening tests**

`test_osm_extractor.py` (append):
```python
def _osm(nodes_xml):
    return '<?xml version="1.0"?><osm version="0.6">' + nodes_xml + '</osm>'

def test_corrupt_file_is_a_loud_typed_OsmParseError(tmp_path):
    # A file-level parse error escapes pyosmium's reader (NOT a per-feature skip). It must
    # surface as a clean typed OsmParseError, not an uncaught ValueError/RuntimeError.
    # (OSM caps tag values at ~255, so an over-long tag is only reachable via a corrupt file.)
    over = tmp_path / "over.osm"
    over.write_text(_osm('<node id="1" lat="1" lon="1" version="1"><tag k="d" v="' + "z" * 5000 + '"/></node>'))
    with pytest.raises(osm.OsmParseError):
        osm.OsmExtractor(CFG).extract("uk", over, _db(tmp_path / "o"), run_id="r1")
    garbage = tmp_path / "g.pbf"; garbage.write_bytes(b"not a real pbf")
    with pytest.raises(osm.OsmParseError):
        osm.OsmExtractor(CFG).extract("uk", garbage, _db(tmp_path / "g"), run_id="r1")

def test_too_many_candidates_is_a_loud_bounded_abort(tmp_path, monkeypatch):
    monkeypatch.setattr(osm, "MAX_CANDIDATE_RECORDS", 3)
    nodes = "".join(f'<node id="{i}" lat="1" lon="1" version="1"><tag k="historic" v="x"/></node>' for i in range(10))
    p = tmp_path / "many.osm"; p.write_text(_osm(nodes))
    with pytest.raises(osm.TooManyCandidatesError):
        osm.OsmExtractor(CFG).extract("uk", p, _db(tmp_path / "m"), run_id="r1")

def test_too_many_tags_are_bounded(tmp_path):
    # NOTE: a valid `name` tag is REQUIRED or A1.parse drops the record (empty name) and the
    # SELECT below fetches None → TypeError. The invariant under test is the tag-COUNT bound.
    tags = ('<tag k="historic" v="x"/><tag k="name" v="Many Tags"/>'
            + "".join(f'<tag k="k{i}" v="v"/>' for i in range(osm.MAX_TAGS_PER_FEATURE + 50)))
    p = tmp_path / "m.osm"; p.write_text(_osm(f'<node id="1" lat="1" lon="1" version="1">{tags}</node>'))
    conn = _db(tmp_path / "d")
    osm.OsmExtractor(CFG).extract("uk", p, conn, run_id="r1")
    props = json.loads(conn.execute("SELECT props_json FROM source_records").fetchone()[0])
    assert len(props) <= osm.MAX_TAGS_PER_FEATURE

def test_long_tag_key_is_truncated_at_the_edge(tmp_path):
    # A ~150-char key is valid OSM (< 255) yet exceeds MAX_TAG_KEY_LEN=100 → the extractor edge
    # truncates it BEFORE parse. Teeth: neuter the `t.k[:MAX_TAG_KEY_LEN]` slice and this goes red
    # (the full 150-char key would then appear; A1 caps keys at 300 so it would survive parse).
    longkey = "k" * 150
    p = tmp_path / "lk.osm"; p.write_text(_osm(f'<node id="1" lat="1" lon="1" version="1">'
        f'<tag k="historic" v="castle"/><tag k="name" v="LongKey"/><tag k="{longkey}" v="v"/></node>'))
    conn = _db(tmp_path / "lk")
    osm.OsmExtractor(CFG).extract("uk", p, conn, run_id="r1")
    props = json.loads(conn.execute("SELECT props_json FROM source_records").fetchone()[0])
    assert ("k" * osm.MAX_TAG_KEY_LEN) in props and longkey not in props   # truncated to 100

def test_garbage_wikidata_tag_is_dropped_record_kept(tmp_path):
    # `name` required (see note above) — the invariant under test is that a malformed QID drops
    # only the wikidata key while the record itself survives.
    p = tmp_path / "g.osm"; p.write_text(_osm('<node id="1" lat="1" lon="1" version="1">'
        '<tag k="historic" v="castle"/><tag k="name" v="Bad QID"/><tag k="wikidata" v="Qwerty; drop"/></node>'))
    conn = _db(tmp_path / "d")
    osm.OsmExtractor(CFG).extract("uk", p, conn, run_id="r1")
    props = json.loads(conn.execute("SELECT props_json FROM source_records").fetchone()[0])
    assert "wikidata" not in props and props["historic"] == "castle"   # malformed QID never poisons the A2 join, record kept

def test_offglobe_coordinate_is_skipped_in_handler(tmp_path):
    # pyosmium's Location.valid() is FALSE for any off-Earth coordinate (verified: lat=99 invalid),
    # so the node is skipped IN THE HANDLER (`if o.location.valid()`) and never reaches parse.
    # The node carries a valid `name` so the ONLY reason it is dropped is the coordinate.
    p = tmp_path / "o.osm"; p.write_text(_osm('<node id="1" lat="99" lon="1" version="1">'
        '<tag k="historic" v="x"/><tag k="name" v="Off Globe"/></node>'))
    conn = _db(tmp_path / "d")
    assert osm.OsmExtractor(CFG).extract("uk", p, conn, run_id="r1") == 0

def test_source_record_rejects_offglobe_coordinate_directly(tmp_path):
    # The extractor can't feed parse an off-globe coordinate (osmium drops it first), so pin A1's
    # coordinate-range rejection at its OWN boundary — teeth for the -90..90 / -180..180 check.
    from mt_pipeline import source_record
    with pytest.raises(source_record.SourceRecordError):
        source_record.parse(region="uk", source="osm", source_ref="osm:node/1",
                            name="X", lat=99.0, lon=1.0, props={})

def test_deterministic_same_file_same_records(tmp_path):
    ca = _db(tmp_path / "a"); cb = _db(tmp_path / "b")
    osm.OsmExtractor(CFG).extract("uk", FIX, ca, run_id="r1")
    osm.OsmExtractor(CFG).extract("uk", FIX, cb, run_id="r2")
    q = "SELECT source_ref, lat, lon FROM source_records ORDER BY id"
    assert ca.execute(q).fetchall() == cb.execute(q).fetchall()
```

- [ ] **Step 2: Run to verify it passes**

Run: `cd pipeline && uv run python -m pytest tests/test_osm_extractor.py -q`
Expected: PASS (all OSM tests — helpers, extract, parity, hardening, determinism).

- [ ] **Step 3: Commit**

```bash
git add pipeline/tests/test_osm_extractor.py
git commit -m "Add OSM edge-hardening tests (tag-len/count bounds, garbage-QID, off-globe skip, determinism)"
```

---

### Task 4: Register `osm` in the extract stage

**Files:**
- Modify: `pipeline/src/mt_pipeline/extract_stage.py`
- Test: `pipeline/tests/test_extract_stage_osm.py`

**Interfaces:**
- Modify `extract_stage.build_registry(allowlist_path, languages, *, osm_tag_config_path=None)`. `osm_tag_config_path` **defaults to the shipped bootstrap config** (`DEFAULT_OSM_TAG_CONFIG`) so `osm` is **always registered** — exactly like `wikidata`/`wikipedia`, which register unconditionally. A caller may still pass an A3-refined config path to override the bootstrap. `run_extract` is unchanged (registry-driven).
- **Why not conditional registration:** if `osm` were registered only when a path is passed, a region config with `sources.osm = True` but a caller that omits the path would yield **zero OSM records with no error** — a silent misconfiguration at exactly the seam that should fail loud. Defaulting the path removes that footgun. (A complementary belt-and-suspenders — `run_extract` asserting every *enabled* source is *registered* — belongs in A1b's `run_extract`; **surfaced to fable on thread `wp/a1b`** rather than edited here from A1c.)

- [ ] **Step 1: Write the failing tests**

`pipeline/tests/test_extract_stage_osm.py`:
```python
import pathlib
from dataclasses import dataclass
from mt_pipeline import store, extract_stage

FIX = pathlib.Path(__file__).parent / "fixtures/osm/sample.osm"
CFG = pathlib.Path(__file__).parents[1] / "config/osm_candidate_tags.json"

@dataclass(frozen=True)
class RC:
    region_id: str
    sources: dict

def test_osm_registered_and_run_when_enabled(tmp_path):
    conn = store.connect(tmp_path / "w.db"); store.init_schema(conn)
    reg = extract_stage.build_registry(
        allowlist_path=pathlib.Path(__file__).parents[1] / "config/wikidata_class_allowlist.json",
        languages={"en"}, osm_tag_config_path=CFG)
    cfg = RC("uk", {"wikidata": False, "wikipedia": False, "osm": True,
                    "historic_england": False, "open_plaques": False, "national_register": None})
    counts = extract_stage.run_extract(conn, cfg, {"osm": str(FIX)}, run_id="r1", registry=reg)
    assert counts == {"osm": 2}

def test_osm_registered_by_default_without_explicit_config_path(tmp_path):
    # The silent-skip guard: omitting osm_tag_config_path must STILL register osm (defaults to the
    # shipped bootstrap), so an enabled-osm region can never no-op. Neuter the default → this reds.
    conn = store.connect(tmp_path / "w.db"); store.init_schema(conn)
    reg = extract_stage.build_registry(
        allowlist_path=pathlib.Path(__file__).parents[1] / "config/wikidata_class_allowlist.json",
        languages={"en"})                                  # NO osm_tag_config_path
    cfg = RC("uk", {"wikidata": False, "wikipedia": False, "osm": True,
                    "historic_england": False, "open_plaques": False, "national_register": None})
    counts = extract_stage.run_extract(conn, cfg, {"osm": str(FIX)}, run_id="r1", registry=reg)
    assert counts == {"osm": 2}                            # registered via the default bootstrap config
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd pipeline && uv run python -m pytest tests/test_extract_stage_osm.py -q`
Expected: FAIL — `build_registry` has no `osm_tag_config_path` / does not register `osm`.

- [ ] **Step 3: Modify `extract_stage.build_registry`**

In `pipeline/src/mt_pipeline/extract_stage.py`, extend `build_registry`:
```python
import pathlib
from .extractors import osm as osm_extractor   # add import

# Ships in the repo (pipeline/config/); __file__ is pipeline/src/mt_pipeline/extract_stage.py.
DEFAULT_OSM_TAG_CONFIG = pathlib.Path(__file__).resolve().parents[2] / "config/osm_candidate_tags.json"

def build_registry(allowlist_path, languages, *, osm_tag_config_path=None):
    reg = Registry()
    reg.register("wikidata", wikidata.make_extractor(allowlist_path))
    reg.register("wikipedia", WikipediaExtractor(languages))
    # Default to the shipped bootstrap so osm is ALWAYS registered (never a silent skip when
    # a region enables osm but the caller omits the path). A3-refined configs override it.
    reg.register("osm", osm_extractor.make_extractor(osm_tag_config_path or DEFAULT_OSM_TAG_CONFIG))
    return reg
```

- [ ] **Step 4: Run + full suite + commit**

Run: `cd pipeline && uv run python -m pytest -q`
Expected: PASS (all A1 + A1b + A1c tests green).

```bash
git add pipeline/src/mt_pipeline/extract_stage.py pipeline/tests/test_extract_stage_osm.py
git commit -m "Register osm extractor in the extract-stage build_registry"
```

---

## Review Record

**Author self-review** — deliverables map to tasks: candidate-tag config + tag-match + provenance sidecar (T1); the pyosmium streaming extractor with nodes + arithmetic-mean way-centroids, crash-safe, deterministic, `.osm`+`.pbf` parity (T2); edge-hardening tests (T3); registry wiring (T4). Implements A1's `parse` interface; extends A1b's registry; consumes (not invents) the candidate-tag config; `wikidata=*` → `props` A2 join key. **One vandalized feature never crashes the stream** (per-feature guard). Deterministic (stable `source_ref` order, arithmetic-mean centroid). Relations deferred (`WP-A1c-relations`) — recall covered by the Wikidata union.

**Ratifications (fable, thread `wp/a1c`)** — nodes + way-centroids (relations deferred, justified); `.osm` fixtures + a binary `.pbf` parity test (`SimpleWriter`); bootstrap tag config; deferred acquisition (`WP-A1c-acquire`) + self-describing `.pbf.meta.json` sidecar (present → verify sha256 loud; absent → warn); `osmium` dep.

**Feasibility pre-verified (author, real pyosmium 4.3.1 in a scratch venv).** Ran the extractor end-to-end against the `.osm` fixture and a `SimpleWriter` `.pbf`: node + way-centroid, `wikidata` join key captured, non-candidate + relation skipped, `.osm`/`.pbf` records identical. **This caught a real bug inspection would have missed:** pyosmium's reader raises `ValueError`/`RuntimeError` at the C level for an over-long tag / corrupt `.pbf`, escaping the per-feature guards — now wrapped as a loud typed `OsmParseError` (a naive per-feature-only guard would have crashed the run). Also confirmed a 250-tag node is accepted (tag-count bound is real) and the candidate cap raises **as `TooManyCandidatesError`** (an in-callback exception keeps its type across `apply_file`).

**Adversarial review (per AGENTS.md gate) — COMPLETED. 3 independent critics (security/untrusted-OSM; spec+interface fidelity; coherence+test-quality-run-against-the-venv). Raised 21, deduped to ~15 distinct; 2 refuted by re-running the real code; the rest fixed.**
- **Refuted (empirically, not accepted):** (a) "`TooManyCandidatesError` may be wrapped as `RuntimeError` across the C boundary" — verified it propagates as its own type, so the failure-class split is sound. (b) "a way with nodes at lat +99/−99 launders an off-globe pair into an in-range mean" — verified `Location.valid()` is FALSE at ±99 (enforces Earth range), so both node guard and way filter drop such vertices *before* averaging; the attack is impossible.
- **Fixed — HIGH:** (1) **Node-location index memory** was O(all nodes) with the disk-backed option unexposed and the "knob, not a code change" claim false → added a real `index_type` parameter threaded into `apply_file(idx=...)`, prose corrected. (2) **A1b dependency over-claim** ("merged on develop") → A1b *impl* is not on develop; plan now states A1c impl is BLOCKED on A1b impl landing (sequencing surfaced to fable). (3) **Centroid test had no teeth** (symmetric square: mean==bbox==area==(1,1)) → asymmetric **closed** fixture `(0,0),(0,2),(2,2),(4,0)`, asserts mean `(1.5,1.0)` ≠ bbox `(2.0,1.0)`. (4) **Two hardening fixtures crashed** (no `name` → `parse` drops → `None[0]` TypeError) → added `name` tags.
- **Fixed — MEDIUM:** (5) **Conditional `osm` registration** silently no-op'd an enabled region → `osm_tag_config_path` defaults to the shipped bootstrap, always registered. (6) **Closed ways double-counted** the repeated closing node → deduped before averaging. (7) **`props` prose said "only candidate tags"** while code emits the full bounded set (A4 needs it) → prose corrected in 3 places. (8) **Off-globe test passed for the wrong reason** (skipped in handler, not parse) → re-scoped + added a direct `source_record` range test. (9) **Sidecar parsed unsafely** (unbounded read, non-dict `AttributeError`) → size-bounded, typed `ProvenanceError`, tested. (10) **Blind `except` was silent** → dropped-feature counter + WARNING summary. (11) **`_db` helper broken/triplicated** (parent dir missing) → one definition taking a full path. (12) **Empty determinism stub** was a false green → deleted (real determinism test lives in Task 3).
- **Fixed — LOW:** (13) **Tag-key truncation was untested** → added a 150-char-key teeth test; the value cap is documented defense-in-depth (osmium refuses >255 at parse, A1 re-caps at 300). (14) **`man_made=tower`** (utility-tower noise) dropped from the bootstrap; `obelisk` kept.
- **Method (per [[adversarial-gate-verify-executed-path]]):** every fix carries a test that goes RED when the fix is neutered; strict checks (`is`-shape QID, sha256 identity, closed-way dedup) each have a case a loose impl fails; the coherence critic **ran** the code against pyosmium 4.3.1 rather than reading the plan — which is how the two refutations and the two crashing fixtures were caught.

**Cross-package needs surfaced** — `WP-A1c-relations` (multipolygon geometry, deferred); `WP-A1c-acquire` (Geofabrik `.pbf` download; **two distinct hashes at two stages, not a conflict:** at download it verifies the file against **Geofabrik's published `.md5`** — *upstream* integrity, their choice of hash — then it writes our `<file>.pbf.meta.json` sidecar recording a **`sha256`** — *our* provenance boundary, our choice of hash — which `extract`'s `verify_provenance` checks. So: loud-abort if the download ≠ Geofabrik's md5 at acquisition; loud `ProvenanceError` if the file ≠ our sidecar's sha256 at extract); A2 reads `props["wikidata"]` for the OSM free join (already on issue #6); the candidate-tag config is A3-replaceable with zero code change.
