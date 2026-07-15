# WP-A1c (OSM Extractor) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A deterministic, §5.5-hardened **OSM extractor** — `pyosmium` **streaming** over a dated Geofabrik `.pbf` extract — that keeps candidate-tagged features (`historic=*`, `tourism∈{attraction,artwork,viewpoint}`, `memorial=*`, … from a consumed config), emits normalized source records via WP-A1's interface, and captures the `wikidata=*` tag as the A2 join key. Registers `osm` into the extractor registry WP-A1b established.

**Architecture:** Under `pipeline/` (the WP-A1 `mt_pipeline` package). The extractor **streams** the `.pbf` with `pyosmium` (bounded memory — never slurps a country into RAM; only the *filtered* candidate records are held), computing a **deterministic arithmetic-mean centroid** for ways from a node-location index. Coordinates for **nodes** are direct; **relations are deferred** (`WP-A1c-relations`). Every field is bounded at the extractor edge before A1's `source_record.parse` (the binding carry-in). The determinism boundary is the dated Geofabrik file, recorded self-describingly in a `<file>.pbf.meta.json` sidecar (URL, date, sha256, size); the extractor verifies the sha256 when the sidecar is present.

**Tech Stack:** Python 3.11+ (the WP-A1 `mt_pipeline` package + `mt-contracts`), **`pyosmium` (`osmium`)** — the spec's OSM reader (§5.2), stdlib `json`/`hashlib`/`logging`, `pytest`.

## Global Constraints

- **Implements A1's interface + extends A1b's registry, never re-declares them.** Records are produced only via `mt_pipeline.source_record.parse(...)` / `persist(...)`; `osm` registers into `mt_pipeline.extractors.Registry` (from A1b, merged on develop) and runs through `extract_stage.build_registry`. Canonical-ref grammar + text-safety are `mt_contracts`' (via `parse`). **A1 preconditions** (present on develop): `source_record.parse`/`persist`/`SourceRecordError`; `store`; `config.RegionConfig`; `extractors.Registry`/`Extractor`; `is_canonical_ref` already accepts `osm:node/…`, `osm:way/…`.
- **Streaming, bounded memory (fable).** `pyosmium` streams the file; the extractor holds only the *candidate* records (a filtered subset), never all nodes. The node-location index (for way centroids) uses pyosmium's location cache — in-memory for tests/regional extracts; a **disk-backed flex-mem index is the documented country-scale option** (a knob, not a code change).
- **Deterministic (Principle 12).** `extract(pbf, …)` is a pure function of the dated `.pbf`: same file → identical records, identical order. Records emit in **stable lexical `source_ref` order** (collected then sorted), de-duped by `source_ref`. The **way-centroid is the arithmetic mean of the way's node locations** — a fixed, order-independent formula (a fixture way with hand-computed centroid pins it). No wall-clock/randomness in outputs.
- **Never crash on hostile input, with a per-feature vs file-level split (Principle 10 / §5.5 / binding carry-in; verified against pyosmium 4.3.1).** Two distinct failure classes:
  - **Per-feature** hostile content *within OSM limits* (weird tag values, a feature with hundreds of tags, a missing `name`, an off-globe coordinate, a garbage `wikidata` tag): each per-feature body runs inside a `try/except` that **skips** the feature — never aborts the stream. Raw-blob bounding at the edge: `MAX_TAGS_PER_FEATURE` (props built once, bounded up front), `MAX_TAG_KEY_LEN`/`MAX_TAG_VAL_LEN`, `MAX_NAME_LEN` — a small, shallow `props` reaches `parse`. `wikidata` is shape+length validated (`Q[0-9]+`, `MAX_QID_LEN`) before it becomes an A2 join key (a garbage value drops only the key). `MAX_CANDIDATE_RECORDS` caps memory with a loud `TooManyCandidatesError`.
  - **File-level** corruption (an over-long tag value — OSM itself caps values at ~255, so this is only reachable via a corrupt file — or a truncated/garbage `.pbf`): pyosmium's **reader raises `ValueError`/`RuntimeError` at the C level, escaping the per-feature guards**. That is caught in `extract` and re-raised as a **typed `OsmParseError` — a loud, clean abort**, because a corrupt file is not extractable (and it is backstopped by the provenance sha256 check). This distinction was found by actually running pyosmium; a naive per-feature-only guard would let a corrupt file crash the run with an uncaught exception.
  Nothing from OSM is interpolated into shell/SQL/LLM.
- **Self-describing provenance (A1b precedent).** The dated Geofabrik file is the determinism boundary. Acquisition (deferred, `WP-A1c-acquire`) writes a `<file>.pbf.meta.json` sidecar (`source_url`, `geofabrik_date`, `sha256`, `size`). Extract behaviour, pinned exactly: **sidecar present → verify the `.pbf` sha256, LOUD `ProvenanceError` on mismatch; sidecar absent (a hand-placed dev file) → proceed with a logged provenance warning.** (A truncated `.pbf` also fails pyosmium's own parse — an integrity backstop.)
- **Candidate tags are CONSUMED config, not code (§4).** A bootstrap tag-filter ships here (`historic=*`, `tourism∈{attraction,artwork,viewpoint}`, `memorial=*`, …), header-marked `BOOTSTRAP: superseded by WP-A3`; A3's data audit refines from the real tag distribution with zero code change. OSM tag-value rarity is an **A4** scoring signal — A1c only *emits* the candidate tags in `props`; it does not score.
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
  - Caps: `MAX_TAGS_PER_FEATURE = 200`, `MAX_TAG_KEY_LEN = 100`, `MAX_TAG_VAL_LEN = 300`, `MAX_NAME_LEN = 300`, `MAX_QID_LEN = 24`, `MAX_CANDIDATE_RECORDS = 5_000_000`.

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
    "man_made": ["obelisk", "tower"]
  }
}
```

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
        _log.warning("no provenance sidecar for %s — proceeding (hand-placed dev file)", pbf_path)
        return
    meta = json.loads(meta_path.read_text())
    actual = _sha256_file(pbf_path)
    if actual != meta.get("sha256"):
        raise ProvenanceError(f"sha256 mismatch for {pbf_path}: {actual} != {meta.get('sha256')}")
```

- [ ] **Step 5: Run to verify it passes**

Run: `cd pipeline && uv run python -m pytest tests/test_osm_extractor.py -q`
Expected: PASS (4 passed).

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
  - `osm.OsmExtractor(tag_config: dict)` — implements the A1b `Extractor` protocol: `extract(region, snapshot_path, conn, *, run_id) -> int`.
  - `osm.make_extractor(tag_config_path) -> OsmExtractor` (production factory: loads the bootstrap/A3 config).
  - Each kept feature emits `source=osm, source_ref=osm:{node|way}/<id>`, `name` from `tags["name"]` (bounded), and `props` = the bounded candidate tags + `wikidata?` (validated) — de-duped by `source_ref`, stable lexical order, every field guarded, relations skipped.

- [ ] **Step 1: Write the `.osm` fixture + failing tests**

`pipeline/tests/fixtures/osm/sample.osm` (nodes 1–4 form a candidate way whose centroid is easy to hand-compute; node 10 is a candidate; node 11 is non-candidate; a relation must be ignored):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<osm version="0.6" generator="test">
  <node id="1" lat="0.0" lon="0.0"/>
  <node id="2" lat="0.0" lon="2.0"/>
  <node id="3" lat="2.0" lon="2.0"/>
  <node id="4" lat="2.0" lon="0.0"/>
  <node id="10" lat="51.5" lon="-0.12" version="1">
    <tag k="historic" v="memorial"/>
    <tag k="name" v="A Memorial"/>
    <tag k="wikidata" v="Q42"/>
  </node>
  <node id="11" lat="51.4" lon="-0.10" version="1">
    <tag k="amenity" v="bench"/>
  </node>
  <way id="100" version="1">
    <nd ref="1"/><nd ref="2"/><nd ref="3"/><nd ref="4"/>
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

def _db(tmp_path): c = store.connect(tmp_path / "w.db"); store.init_schema(c); return c
FIX = pathlib.Path(__file__).parent / "fixtures/osm/sample.osm"
CFG = {"historic": True, "tourism": ["attraction", "artwork", "viewpoint"], "memorial": True}

def test_extracts_nodes_and_way_centroids_skips_noncandidate_and_relations(tmp_path):
    conn = _db(tmp_path)
    n = osm.OsmExtractor(CFG).extract("uk", FIX, conn, run_id="r1")
    rows = conn.execute("SELECT source_ref, name, lat, lon FROM source_records ORDER BY source_ref").fetchall()
    assert n == 2                                        # node 10 + way 100; node 11 + relation 200 excluded
    assert rows[0][0] == "osm:node/10" and rows[1][0] == "osm:way/100"
    # way centroid = arithmetic mean of nodes (0,0),(0,2),(2,2),(2,0) = (1.0, 1.0)
    assert abs(rows[1][2] - 1.0) < 1e-9 and abs(rows[1][3] - 1.0) < 1e-9

def test_wikidata_tag_rides_in_props_as_the_a2_join_key(tmp_path):
    conn = _db(tmp_path)
    osm.OsmExtractor(CFG).extract("uk", FIX, conn, run_id="r1")
    props = json.loads(conn.execute("SELECT props_json FROM source_records WHERE source_ref='osm:node/10'").fetchone()[0])
    assert props["wikidata"] == "Q42" and props["historic"] == "memorial"

def test_deterministic_stable_order(tmp_path):
    a, b = _db(tmp_path / "a"), _db(tmp_path / "b")   # helper uses distinct dirs? use file names
def test_binary_pbf_parity_with_xml(tmp_path):
    # write the SAME data as a .pbf via pyosmium and assert identical records (kills format divergence)
    import osmium
    pbf = tmp_path / "sample.pbf"
    w = osmium.SimpleWriter(str(pbf))
    for nid, lat, lon, tags in [(1,0.0,0.0,{}),(2,0.0,2.0,{}),(3,2.0,2.0,{}),(4,2.0,0.0,{}),
                                (10,51.5,-0.12,{"historic":"memorial","name":"A Memorial","wikidata":"Q42"}),
                                (11,51.4,-0.10,{"amenity":"bench"})]:
        w.add_node(osmium.osm.mutable.Node(id=nid, location=(lon, lat), tags=tags))
    w.add_way(osmium.osm.mutable.Way(id=100, nodes=[1,2,3,4], tags={"historic":"castle","name":"A Castle"}))
    w.close()
    ca, cb = _db(tmp_path / "x"), _db(tmp_path / "y")
    osm.OsmExtractor(CFG).extract("uk", FIX, ca, run_id="r1")
    osm.OsmExtractor(CFG).extract("uk", pbf, cb, run_id="r1")
    xa = ca.execute("SELECT source_ref, name, lat, lon FROM source_records ORDER BY source_ref").fetchall()
    xb = cb.execute("SELECT source_ref, name, lat, lon FROM source_records ORDER BY source_ref").fetchall()
    assert xa == xb                                     # identical records from .osm and .pbf
```
(Fix `_db` to accept distinct paths: `def _db(p): c = store.connect(p if str(p).endswith('.db') else str(p)+'.db'); store.init_schema(c); return c` — or give each call a unique filename in tmp_path.)

- [ ] **Step 2: Run to verify it fails**

Run: `cd pipeline && uv run python -m pytest tests/test_osm_extractor.py -q`
Expected: FAIL — `OsmExtractor` not defined.

- [ ] **Step 3: Add `osmium` to deps + implement the extractor**

Add to `pipeline/pyproject.toml` `dependencies`: `"osmium>=3.6"` (pyosmium; wheels available). Then `uv sync`.

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
            if o.location.valid():
                self._consider("node", o.id, o.location.lat, o.location.lon, o)
        except TooManyCandidatesError:
            raise                               # loud abort propagates
        except Exception:
            return                              # one bad feature NEVER aborts the stream

    def way(self, o) -> None:
        try:
            locs = [(n.location.lat, n.location.lon) for n in o.nodes if n.location.valid()]
            if locs:
                lat = sum(a for a, _ in locs) / len(locs)   # arithmetic-mean centroid (deterministic)
                lon = sum(b for _, b in locs) / len(locs)
                self._consider("way", o.id, lat, lon, o)
        except TooManyCandidatesError:
            raise
        except Exception:
            return
    # relations intentionally NOT handled → WP-A1c-relations


class OsmExtractor:
    def __init__(self, tag_config: dict) -> None:
        self.tag_config = tag_config

    def extract(self, region: str, snapshot_path, conn, *, run_id: str) -> int:
        verify_provenance(snapshot_path)                  # sidecar sha256 (loud) or dev-file warning
        handler = _CandidateHandler(self.tag_config)
        try:
            handler.apply_file(str(snapshot_path), locations=True)   # streams; locations for way centroids
        except TooManyCandidatesError:
            raise
        except (ValueError, RuntimeError) as e:
            # pyosmium's READER raises at the C level for an over-long tag / corrupt / truncated
            # file — this escapes the per-feature guards, so a corrupt FILE is a loud, clean abort
            # (backstopped by the provenance sha256 check), NOT a silent skip.
            raise OsmParseError(f"pyosmium could not parse {snapshot_path}: {e}") from e
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
*(pyosmium API — **verified against 4.3.1 on this host**: `SimpleHandler` + `apply_file(path, locations=True)` gives ways their node locations via `o.nodes[i].location` (valid via `.valid()`); iterate `o.tags` for `.k`/`.v`; `o.location.valid()`/`.lat`/`.lon` for nodes; `SimpleWriter` + `osmium.osm.mutable.Node(id=, location=(lon, lat), tags=)`/`.Way(id=, nodes=[...], tags=)`. The reader raises `ValueError`/`RuntimeError` on a malformed file — caught and re-raised as `OsmParseError`.)*

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
    tags = '<tag k="historic" v="x"/>' + "".join(f'<tag k="k{i}" v="v"/>' for i in range(osm.MAX_TAGS_PER_FEATURE + 50))
    p = tmp_path / "m.osm"; p.write_text(_osm(f'<node id="1" lat="1" lon="1" version="1">{tags}</node>'))
    conn = _db(tmp_path / "d")
    osm.OsmExtractor(CFG).extract("uk", p, conn, run_id="r1")
    props = json.loads(conn.execute("SELECT props_json FROM source_records").fetchone()[0])
    assert len(props) <= osm.MAX_TAGS_PER_FEATURE

def test_garbage_wikidata_tag_is_dropped_record_kept(tmp_path):
    p = tmp_path / "g.osm"; p.write_text(_osm('<node id="1" lat="1" lon="1" version="1">'
        '<tag k="historic" v="castle"/><tag k="wikidata" v="Qwerty; drop"/></node>'))
    conn = _db(tmp_path / "d")
    osm.OsmExtractor(CFG).extract("uk", p, conn, run_id="r1")
    props = json.loads(conn.execute("SELECT props_json FROM source_records").fetchone()[0])
    assert "wikidata" not in props                    # malformed QID never poisons the A2 join

def test_offglobe_coordinate_is_dropped_via_a1_parse(tmp_path):
    p = tmp_path / "o.osm"; p.write_text(_osm('<node id="1" lat="99" lon="1" version="1"><tag k="historic" v="x"/></node>'))
    conn = _db(tmp_path / "d")
    assert osm.OsmExtractor(CFG).extract("uk", p, conn, run_id="r1") == 0   # A1 parse rejects → skipped

def test_deterministic_same_file_same_records(tmp_path):
    ca = _db(tmp_path / "a"); cb = _db(tmp_path / "b")
    osm.OsmExtractor(CFG).extract("uk", FIX, ca, run_id="r1")
    osm.OsmExtractor(CFG).extract("uk", FIX, cb, run_id="r2")
    q = "SELECT source_ref, lat, lon FROM source_records ORDER BY id"
    assert ca.execute(q).fetchall() == cb.execute(q).fetchall()
```
(Adjust `_db` to take a path: `def _db(p): c = store.connect(str(p) + ".db"); store.init_schema(c); return c`.)

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
- Modify `extract_stage.build_registry(allowlist_path, languages, *, osm_tag_config_path=None)` to also `register("osm", osm.make_extractor(osm_tag_config_path))` when a tag-config path is supplied. `run_extract` is unchanged (registry-driven).

- [ ] **Step 1: Write the failing test**

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
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd pipeline && uv run python -m pytest tests/test_extract_stage_osm.py -q`
Expected: FAIL — `build_registry` has no `osm_tag_config_path` / does not register `osm`.

- [ ] **Step 3: Modify `extract_stage.build_registry`**

In `pipeline/src/mt_pipeline/extract_stage.py`, extend `build_registry`:
```python
from .extractors import osm as osm_extractor   # add import

def build_registry(allowlist_path, languages, *, osm_tag_config_path=None):
    reg = Registry()
    reg.register("wikidata", wikidata.make_extractor(allowlist_path))
    reg.register("wikipedia", WikipediaExtractor(languages))
    if osm_tag_config_path is not None:
        reg.register("osm", osm_extractor.make_extractor(osm_tag_config_path))
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

**Feasibility pre-verified (author, real pyosmium 4.3.1 installed on host).** Ran the extractor end-to-end against the `.osm` fixture and a `SimpleWriter` `.pbf`: node + way-centroid `(1.0, 1.0)` (hand-computed mean confirmed), `wikidata` join key captured, non-candidate + relation skipped, `.osm`/`.pbf` records identical. **This caught a real bug inspection would have missed:** pyosmium's reader raises `ValueError`/`RuntimeError` at the C level for an over-long tag / corrupt `.pbf`, escaping the per-feature guards — now wrapped as a loud typed `OsmParseError` (a naive per-feature-only guard would have crashed the run). Also confirmed a 250-tag node is accepted (so the tag-count bound is real) and the candidate cap raises.

**Adversarial review (per AGENTS.md gate) — TO RUN before PR, with the strengthened checklist:** (1) fixes verified on the **executed path** (not prose); (2) tests have **teeth** — *neuter the fix, confirm the test goes red* (esp. the centroid formula, the tag bounds, the provenance sha256 mismatch, the wikidata shape validation); (3) **every strict comparison gets a test a loose comparison fails**; (4) the **feasibility critic installs `osmium`** into a scratch venv and runs the extractor against the fixtures — **if the sandbox blocks the C-extension build, request escalation explicitly (do not silently degrade to XML-only)**; it must verify the exact pyosmium API (`SimpleHandler.apply_file(locations=True)`, `o.nodes[i].location`, `o.tags`, `SimpleWriter`) against the installed version and confirm the hand-computed way centroid `(1.0, 1.0)`.

**Cross-package needs surfaced** — `WP-A1c-relations` (multipolygon geometry, deferred); `WP-A1c-acquire` (Geofabrik `.pbf` download + `.pbf.meta.json` sidecar with sha256, loud-abort on md5 mismatch); A2 reads `props["wikidata"]` for the OSM free join (already on issue #6); the candidate-tag config is A3-replaceable with zero code change.
