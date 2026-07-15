# WP-A7 (Publisher) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The publish stage (§5.2 stage 5) — partition scored+categorized places into deterministic gzipped **z10 place-tiles** (winner ids only), cut a region **`.pmtiles` basemap** within the §5.1 pack budget, assemble a self-contained **manifest** (tile index + checksums + tier counts + prompt-version provenance + per-source **attribution**), and **publish it atomically and versioned to R2** — the app only ever sees complete versions, rollback is a pointer repoint (§5.6, §6). Local-first: the whole publish builds a **local staging dir with the identical R2 layout** (the testable default); the R2 upload is the thin final step.

**Architecture:** A new `mt_pipeline.publish` package orchestrating A0's frozen primitives (`select_tile_places` — the tier/score/place_id overflow rule; `gzip_tile` — deterministic gzip mtime=0 + canonical OS byte; `tile_winner_violations` — winners-only guard; caps; the tile/manifest schemas) — **consume them, never re-implement**. Places (A2) joined to categories (A3) + scores/tiers (A4) → partitioned by a z10 slippy function A7 owns → per-cell `select_tile_places` → `gzip_tile` + sha256 → manifest → **staging dir → R2**. The R2 layout is **two buckets**: PUBLIC tiles (behind `tiles.making-tracks.app`) and PRIVATE state (ID registry, LLM cache, future feedback) — the registry MUST never sit in the public bucket. Everything is a deterministic function of `(places, config, publish_version)`; `publish_version`/`generated_at` are run params, never wall-clock.

**Tech Stack:** Python 3.11+ (`mt_pipeline`, depends on `mt-contracts`), `boto3` (S3-compatible R2 client), the `pmtiles` CLI (`pmtiles extract` against Protomaps hosted builds — no planet download), `jsonschema`, `pytest`. R2 auth via the 1Password `op run` pattern (`docs/SECRETS.md`).

## Global Constraints

- **Consume A0's tile primitives, never re-implement them (the consume-don't-reinvent rule, applied to the oldest contract).** `select_tile_places(places, max_per_tile=4000, byte_budget=8MiB)` is THE overflow rule (sorts `(tier asc, score desc, place_id asc)`, keeps ≤4000 within the byte budget, returns `(kept, dropped)`); `gzip_tile(obj)` is THE tile codec (JSON `sort_keys` + compact separators, `mtime=0`, OS byte normalised to 255, caps enforced); `tile_winner_violations(ids, records)` is THE winners-only check. A7 orchestrates; a re-implementation would silently diverge from what the app validates.
- **Deterministic + versioned (§5.6, Principle 12).** The publish is a pure function of `(places, categories, scores, registry, region-config, publish_version)`. `publish_version` (format `^[0-9]{8}T[0-9]{6}Z$`) and `generated_at` are **run PARAMS, not wall-clock** (the A2 versions-are-params lesson) — so a re-publish of the same inputs is byte-identical (the substrate for #54's diff-aware upload). Tiles are gzipped deterministically; the manifest is the only place a timestamp could leak, and it's a param.
- **NO partial publishes; manifest written LAST; atomic; rollback = repoint (§5.2, §5.6, §6).** The app reaches a version only via a stable `current` pointer → the version's `manifest.json` → its tiles. So: upload all tiles + basemap under `{publish_version}/`, write `manifest.json` LAST, then **atomically flip the region's `current` pointer** to `{publish_version}`. A failure before the manifest write leaves orphan tiles the app never sees (GC'd later); a failure at the flip leaves `current` on the previous good version. **Rollback = repoint `current`** to the prior version (its tiles are still in R2). The **ID registry is updated only on successful publish** (§6).
- **Two R2 buckets — PUBLIC tiles vs PRIVATE state; the registry is NEVER public (ratified).** PUBLIC bucket (served behind `tiles.making-tracks.app`): manifests, place-tiles, region `.pmtiles`. PRIVATE bucket (no public route): the ID registry (A2), the LLM cache (A6), future feedback (C2). A7 writes tiles/manifest/basemap to public and the registry `last_seen_version` to private — a test asserts no registry/cache path is ever addressed to the public bucket.
- **UNCATEGORIZED IS NEVER PUBLISHED — A7 EXCLUDES it, counts it, and asserts none ship (my call, issue #11).** A3 emits `category = "uncategorized"` for the residue it can't classify; A6's category long-tail has **no `STAGE_ORDER` slot before publish**. Of the three options (exclude / remap / gate-on-A6), A7 **excludes**: gating-on-A6 couples publish to an optional, key-gated stage (brittle, could block publish indefinitely); remapping ships a *guessed* category (violates A3's derived-not-invented). Excluding is the conservative, deterministic choice — an uncategorized place simply isn't ready to ship, the residue shrinks as A3/A6 improve. The exclusion is **COUNTED** in the publish report (`uncategorized_excluded`) so the drop is VISIBLE, never silent (the reconciliation-count lesson), and A7 **asserts no published tile contains a `category == "uncategorized"` place** (a teeth-ful gate).
- **Per-source ATTRIBUTION in the manifest — append-only A0 schema field, single-sourced from `a1d_sources.json` (issue #11).** The manifest carries a credits payload so the app renders from DATA, not hardcoded strings. The `manifest.schema.json` gains an **optional `attribution` array** (scrubbed strings). A7 populates it **only for the sources actually shipped in the region** — derived from the places' `source_refs` via the pinned `PREFIX_TO_SOURCE_KEY` map — copying `license` + `attribution` **verbatim** from `a1d_sources.json`: **Historic England OGL v3.0 MANDATORY** when HE ships, **OSM ODbL** when OSM data ships, Open Plaques PDDL courtesy. Because attribution carries a **legally required** credit and the frozen schema is `additionalProperties:false`, a manifest with attribution sets **`min_reader_version=2`** (a reader that can't render credits REFUSES rather than shipping HE/OSM data uncredited — spec-fidelity MED); a public-domain-only (CC0) region carries no attribution and stays reader 1. A test asserts the OGL/ODbL string ships verbatim whenever such a place is present.
- **Tiles are untrusted-on-read even though we publish them (§5.5 defence-in-depth).** A7 produces tiles that decode under the frozen `tile.schema.json` + caps (the app re-validates; the bucket could be compromised). A7 validates every emitted tile against `tile.schema.json` and every manifest against `manifest.schema.json` before upload — a malformed artifact never leaves staging.
- **Local-first (the testable default).** `build_staging` writes the **identical R2 layout to a local directory** with NO creds — the whole publish (partition → select → gzip → sha256 → winners-check → uncategorized-exclusion → manifest assemble+validate → basemap budget-check) is fixture-testable now. The R2 upload + `current`-flip is the thin final step; **diff-aware upload** (only changed tiles) is noted for issue #54's rerun optimisation.
- **R2 auth via the `op run` pattern (`docs/SECRETS.md`).** One `op run` per publish RUN (rate limits); the R2 credentials are an **S3-compatible token scoped to EXACTLY the two buckets** (read+write on `mt-tiles` + `mt-state`, nothing else). **Rob must create:** an R2 API token so scoped, stored in 1Password (`R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, bucket names), added to `.env.tpl` — noted as a BLOCKED-ON input.
- **BLOCKED-ON declarations (up front — the A2/A3/A4/A5/A6 lesson).** Real tiles are BLOCKED-ON the A2 `places` / A3 `place_categories` / A4 `place_scores` impls (all merged **plan-only** — none in code) + `wp-acquire-impl` real extracts. The real basemap is BLOCKED-ON the `pmtiles` CLI + a Protomaps source. The R2 upload is BLOCKED-ON Rob's R2 token. The pure partition/select/gzip/manifest/attribution/staging logic is fixture-testable NOW.
- **Scope.** A7 does NOT score, categorize, or reconcile — it reads their outputs. It does not run the LLM. It emits winners only (superseded ids are A2's tombstone concern, asserted here).

**Assignment (fable, thread `wp/a7`)** — the LAST pipeline design. Deps satisfied: A0 contracts + A4 plan merged. Core: place-tile emission (z10, deterministic gzip, per-tile sha256), manifest assembly (tile index, checksums, provenance, schema versions), versioned atomic R2 publish (manifest last, rollback = repoint), pmtiles basemap cutting (z14 budget), the two-bucket public/private R2 split (registry never public), R2 auth via `op run`, local-first staging, BLOCKED-ON declarations. Issue #11 inputs folded: per-source attribution field; uncategorized-never-published.

---

## File Structure

```
pipeline/src/mt_pipeline/publish/
  __init__.py
  partition.py     # lonlat_to_z10(lat, lon) -> (x, y); partition_places(places) -> dict[(x,y), list]
  attribution.py   # attribution_for(sources_used, a1d_sources) -> list[{source,license,text}] (OGL mandatory)
  tiles.py         # emit_tiles(partitioned, registry) -> (TileArtifacts, PublishCounts) — select+exclude+winners+gzip+sha256
  manifest.py      # assemble_manifest(...) -> dict (schema-validated); PublishCounts
  basemap.py       # cut_basemap(region_config, out) -> BasemapArtifact  [pmtiles extract; budget check]
  staging.py       # build_staging(region, publish_version, ...) -> staging_dir (IDENTICAL R2 layout, LOCAL-FIRST)
  r2.py            # publish_to_r2(staging, layout, *, upload) -> atomic (tiles+basemap, manifest LAST, flip current) [BLOCKED-ON creds]
  publish_stage.py # run(conn, region, *, publish_version, generated_at, upload=False) — the STAGE_ORDER 'publish' body
pipeline/config/
  r2_layout.json   # {public_bucket:"mt-tiles", private_bucket:"mt-state", domain:"tiles.making-tracks.app", paths:{...}}
contracts/  (A0 append-only — coordinated; schema unshipped so additive-safe)
  schemas/manifest.schema.json   # + OPTIONAL scrubbed `attribution` + `"score"` provenance enum + min_reader_version=2 rule
  schemas/current.schema.json    # NEW — the {schema_version, publish_version} pointer contract B-track consumes
  src/mt_contracts/caps.py       # + ATTRIBUTION_* caps + CAPS_SCHEMA_MAP entries
pipeline/tests/
  test_publish_partition.py  test_publish_attribution.py  test_publish_tiles.py
  test_publish_manifest.py   test_publish_basemap.py      test_publish_atomic.py
  fixtures/publish/           # a few GoldenRow-shaped places + a tiny region-config + a small .pmtiles
docs/superpowers/reports/
  2026-07-15-a7-publish.md    # real UK publish report (BLOCKED-ON impls + creds)
```

---

### Task 1: z10 partition (lat/lon → tile; A7 owns it — A0 has no such fn)

**Files:** Create `pipeline/src/mt_pipeline/publish/partition.py`; Test `pipeline/tests/test_publish_partition.py`

**Interfaces:**
- Consumes: `mt_contracts.caps.TILE_ZOOM` (=10).
- Produces:
  - `partition.lonlat_to_z10(lat: float, lon: float) -> tuple[int, int]` — the standard Web-Mercator slippy-tile formula at z=10, returning `(x, y)` each clamped to `[0, 1023]` (matches the tile/manifest schema `0..1023`). Places at the poles/antimeridian clamp into range, never out. **Requires FINITE, in-range inputs — the caller (`emit_tiles`, Task 3) validates `lat∈[-90,90]`/`lon∈[-180,180]` and `math.isfinite` BEFORE calling** (a `NaN` lat is JSON-schema-VALID — verified — so the schema won't catch it; `int(NaN)` raises. The finite/range check is `emit_tiles`'s per-place quarantine, hostile-data LOW-1).
  - `partition.partition_places(places: Iterable[Mapping]) -> dict[tuple[int,int], list]` — group places by their z10 `(x, y)`. Deterministic (sorted keys on iteration).

- [ ] **Step 1: Write the failing test**

```python
from mt_pipeline.publish import partition as P

def test_known_lonlat_maps_to_z10_tile():
    # z10 slippy tiles (host-verified): London (51.5074,-0.1278)->(511,340); KL (3.139,101.6869)->(801,503).
    assert P.lonlat_to_z10(51.5074, -0.1278) == (511, 340)
    assert P.lonlat_to_z10(3.139, 101.6869) == (801, 503)

def test_extremes_clamp_into_range_not_out():
    for lat, lon in [(90, 180), (-90, -180), (85.06, 179.9), (-85.06, -179.9)]:
        x, y = P.lonlat_to_z10(lat, lon)
        assert 0 <= x <= 1023 and 0 <= y <= 1023          # schema range, never out-of-bounds

def test_partition_groups_deterministically():
    places = [{"place_id": "a", "lat": 51.5, "lon": -0.1}, {"place_id": "b", "lat": 51.5, "lon": -0.1},
              {"place_id": "c", "lat": 3.1, "lon": 101.7}]
    g = P.partition_places(places)
    assert len(g[P.lonlat_to_z10(51.5, -0.1)]) == 2 and len(g) == 2
```

- [ ] **Step 2: Run to verify it fails** — `uv run pytest pipeline/tests/test_publish_partition.py -v` → FAIL (module not found).
- [ ] **Step 3: Implement** the slippy formula (`n = 2**10`; `x = int((lon+180)/360*n)`; `y = int((1 - asinh(tan(radians(lat)))/pi)/2*n)`), each `min(1023, max(0, ...))`; `partition_places` groups by the tuple.
- [ ] **Step 4: Run to verify it passes.** **Teeth:** the known-tile test reds if the formula is wrong; the clamp test reds if a pole/antimeridian coordinate escapes `[0,1023]` (which would fail the tile/manifest schema).
- [ ] **Step 5: Commit** — `"Add z10 lat/lon partition (clamped to schema range)"`

---

### Task 2: A0 manifest extensions (attribution + heuristic provenance + current-pointer) + attribution derivation

**Files:** Modify `contracts/schemas/manifest.schema.json`, `contracts/src/mt_contracts/caps.py`; Create `contracts/schemas/current.schema.json`, `pipeline/src/mt_pipeline/publish/attribution.py`, add `osm` to `pipeline/config/a1d_sources.json`; Test `pipeline/tests/test_publish_attribution.py`

**A0 append-only changes (coordinated — the schema is unshipped, so additive-safe; a drift-guard covers caps):**
- **`attribution`** — OPTIONAL `array` (maxItems 32) of `{source, license, text}`, each string carrying the **SAME control-char-excluding `pattern` as `place.name`/`blurb`** (hostile-data MED-2 — the manifest's "every string is bounded" promise must actually hold; a control char in an attribution string FAILS validation → fail-closed, never a broken credits screen), lengths `source≤32/license≤32/text≤512`. `additionalProperties:false`. Caps + `CAPS_SCHEMA_MAP` entries added.
- **Provenance enum widened to include `"score"`** (spec-fidelity HIGH / coherence MED — the crown fix): a no-LLM/heuristic publish has NO curiosity/blurb/category/reconcile entry, yet `provenance` requires `minItems:1`. Adding `"score"` lets A7 ALWAYS emit a heuristic-tiering provenance entry `{task_id:"score", model:"heuristic", prompt_version:<A4 scoring-config version>}` (records the config that produced the tiering — §5.2), so provenance is `≥1` even with the LLM off. Verified: empty provenance still rejected; a `"score"` entry validates once the enum includes it.
- **`current.schema.json`** (NEW) — the pointer contract B-track's tile client consumes: `{schema_version:1, publish_version}` (`publish_version` same pattern), `additionalProperties:false`. `current.json` is a new cross-track artifact (spec-fidelity MED) — it MUST be a pinned A0 contract, not an ad-hoc file. (Note: §5.6's "rollback = repoint the manifest" is realised as immutable-per-version manifests + a repointed `current` — the reinterpretation is stated.)
- **`min_reader_version`**: a manifest carrying `attribution` sets `min_reader_version = 2` (spec-fidelity MED — attribution carries a LEGALLY REQUIRED credit; a reader that can't render credits must REFUSE/upgrade rather than ship HE data uncredited); a public-domain-only manifest with no attribution stays `1`.
- **`a1d_sources.json` gains `osm`** (spec-fidelity MED — **OSM is ODbL, attribution REQUIRED**; my earlier "osm → no attribution" was legally wrong): `{"license":"ODbL-1.0","attribution":"Place data © OpenStreetMap contributors, licensed under ODbL."}`. (The basemap layer also shows OSM attribution, but place-DATA from OSM needs its own credit.)

**Interfaces:**
- Consumes: `a1d_sources.json` (`license` + `attribution` per source); the emitted places' `source_refs` (place.schema `prefix:id`).
- Produces:
  - `attribution.PREFIX_TO_SOURCE_KEY` — the pinned map from a `source_ref` prefix to an `a1d_sources` key (`{"hehle":"historic_england","plaque":"open_plaques","osm":"osm","wd":"wikidata","wp":"wikidata"}`) — single-sourced + tested (spec-fidelity MED: places carry short prefixes like `hehle:12345`, NOT the long a1d keys; without this map "OGL when HE ships" never fires; the A2 SOURCE_KEY_TO_PREFIX lesson).
  - `attribution.sources_used(places) -> set[str]` — derive the a1d keys from the actually-shipped places' `source_refs` via `PREFIX_TO_SOURCE_KEY`.
  - `attribution.attribution_for(sources_used: set[str], a1d_sources: Mapping) -> list[dict]` — for each key in `sources_used`, emit `{source, license, text}` copying `a1d_sources[key]["license"]`/`["attribution"]` **verbatim**. Sorted by `source` (deterministic). Keys with no attribution entry contribute nothing.

- [ ] **Step 1: Write the failing tests**

```python
import json, pathlib
from mt_pipeline.publish import attribution as A

A1D = json.loads(pathlib.Path("pipeline/config/a1d_sources.json").read_text())

def test_HE_OGL_ships_verbatim_when_an_HE_place_is_present():
    places = [{"place_id": "mt1_"+"0"*25+"A", "source_refs": ["hehle:12345"]},   # HE-sourced (short prefix!)
              {"place_id": "mt1_"+"0"*25+"B", "source_refs": ["wd:Q1"]}]
    used = A.sources_used(places)
    assert used == {"historic_england", "wikidata"}                  # prefix map derives the a1d keys
    he = [a for a in A.attribution_for(used, A1D) if a["source"] == "historic_england"][0]
    assert he["license"] == "OGL-3.0" and he["text"] == A1D["historic_england"]["attribution"]  # verbatim
    assert "Open Government Licence" in he["text"]

def test_OSM_is_ODbL_and_ships_attribution():                        # OSM is NOT public-domain (ODbL)
    out = A.attribution_for(A.sources_used([{"place_id":"mt1_"+"0"*26,"source_refs":["osm:node/1"]}]), A1D)
    assert any(a["source"] == "osm" and "ODbL" in a["license"] for a in out)

def test_cc0_only_region_needs_no_attribution():
    assert A.attribution_for({"wikidata"}, A1D) == []                # CC0 -> optional field empty is valid

def test_heuristic_score_provenance_and_current_pointer_are_contracted():
    schema = json.loads(pathlib.Path("contracts/schemas/manifest.schema.json").read_text())
    assert "score" in schema["properties"]["provenance"]["items"]["properties"]["task_id"]["enum"]   # no-LLM path
    for s in ("attribution",):
        assert s in schema["properties"] and s not in schema["required"]                             # optional
    cur = json.loads(pathlib.Path("contracts/schemas/current.schema.json").read_text())              # pointer contract exists
    assert "publish_version" in cur["properties"] and cur["additionalProperties"] is False
    from mt_contracts.caps import CAPS_SCHEMA_MAP                     # drift-guard: attribution caps single-sourced
    assert any(k[0] == "manifest" and "attribution" in k[1] for k in CAPS_SCHEMA_MAP)

def test_attribution_string_with_a_control_char_fails_validation():  # hostile-data MED-2 (fail-closed)
    import jsonschema, pytest
    schema = json.loads(pathlib.Path("contracts/schemas/manifest.schema.json").read_text())
    bad_attr = {"source": "x", "license": "y", "text": "credit‮evil"}   # RTL override
    with pytest.raises(jsonschema.ValidationError):
        jsonschema.validate({"attribution": [bad_attr]}, {"type":"object","properties":{"attribution":
            schema["properties"]["attribution"]}})
```

- [ ] **Step 2–4:** add the schema changes (attribution + `"score"` enum + `current.schema.json` + min_reader rule) + caps + `PREFIX_TO_SOURCE_KEY`/`sources_used`/`attribution_for`; add `osm` to `a1d_sources.json`. **Teeth (host-verified):** the HE test reds if the prefix map or verbatim copy is wrong (licence breach); the OSM test reds if ODbL is dropped; the control-char test reds if attribution lacks the scrub pattern; the score/current test reds if the no-LLM provenance path or the pointer contract is missing.
- [ ] **Step 5: Commit** — `"Add manifest attribution + heuristic 'score' provenance + current-pointer schema (append-only) + prefix-mapped attribution_for (HE OGL / OSM ODbL, verbatim)"`

---

### Task 3: Tile emission — select + exclude-uncategorized + winners-only + deterministic gzip

**Files:** Create `pipeline/src/mt_pipeline/publish/tiles.py`; Test `pipeline/tests/test_publish_tiles.py`

**Interfaces:**
- Consumes: **A0's `mt_contracts.caps.select_tile_places`, `mt_contracts.tilecodec.gzip_tile`, `mt_contracts.registry.tile_winner_violations`/`resolve_superseded`** (UNCHANGED); `partition.partition_places`; `contracts/schemas/{place,tile}.schema.json`.
- Produces:
  - `tiles.PublishCounts` — `frozen(total_published, by_tier: tuple[int,int,int,int], uncategorized_excluded, invalid_excluded, non_winner_excluded, overflow_dropped)`.
  - `tiles.TileArtifact` — `frozen(x, y, gz_bytes: bytes, sha256: str, byte_len: int)`.
  - `tiles.emit_tiles(places, registry_records) -> tuple[list[TileArtifact], PublishCounts]`:
    1. **Per-place validate + QUARANTINE (hostile-data MED-3 + LOW-1, coherence MED-2):** each joined place is validated against `place.schema.json` AND `lat`/`lon` checked `math.isfinite` + in range (a `NaN` lat is schema-VALID — verified — so the explicit finite check is load-bearing; `int(NaN)` would crash partition). An invalid place is DROPPED and counted (`invalid_excluded`) — **one vandalised row must not abort the whole regional publish** (availability); the drop is visible, never silent.
    2. **Exclude `category == "uncategorized"`** (counted `uncategorized_excluded`).
    3. **Reject non-winner / non-live ids (winners-only, §5.2 — hostile-data MED-5):** for each kept id, exclude it if `tile_winner_violations` flags it (superseded) OR its registry record `status` is not live (`tombstoned`/`withdrawn`, **even with `superseded_by=None`** — `resolve_superseded` returns the id itself for a no-successor tombstone, so the winner check ALONE misses it). Counted `non_winner_excluded`. (A brand-new id absent from the registry is NOT rejected — `resolve_superseded(unknown)==unknown`, verified.)
    4. **Partition** the survivors to z10 cells.
    5. Per cell, `select_tile_places` (kept/dropped → `overflow_dropped`); build the `tile.schema.json` object; `gzip_tile`. **If `gzip_tile` raises the 1 MiB COMPRESSED cap** (its default `select_tile_places` budget is 8 MiB *uncompressed* — a dense cell can pass that yet exceed 1 MiB compressed; spec-fidelity MED), **drop the lowest-priority kept place and re-gzip until it fits** (deterministic — the select order is fixed), the extra drops counted into `overflow_dropped`. sha256 the final bytes.
  - **Every emitted tile is validated against `tile.schema.json` before it leaves `emit_tiles`** (belt-and-braces; with per-place quarantine it should never fire). Deterministic: same inputs → byte-identical `gz_bytes` + identical sha256.

- [ ] **Step 1: Write the failing tests**

```python
import json, pytest
from mt_pipeline.publish import tiles as T
from mt_contracts import registry as R
from mt_contracts.tilecodec import safe_gunzip

def _vid(c): return "mt1_" + "0"*25 + c                              # a VALID 26-char Crockford id (schema-passing)
def _p(pid, tier, score, cat="history", lat=51.5, lon=-0.1):
    return {"place_id": pid, "name": "n", "lat": lat, "lon": lon, "category": cat,
            "tier": tier, "score": score, "source_refs": ["wd:Q1"]}

def test_uncategorized_and_invalid_are_excluded_and_counted_not_silent():
    places = [_p(_vid("A"), 1, 0.9), _p(_vid("B"), 4, 0.1, cat="uncategorized"),
              _p("mt1_SHORT", 1, 0.9), _p(_vid("C"), 1, 0.9, lat=float("nan"))]   # bad id + NaN lat
    arts, counts = T.emit_tiles(places, registry_records=[])
    assert counts.uncategorized_excluded == 1 and counts.invalid_excluded == 2 and counts.total_published == 1
    shipped = [pl for a in arts for pl in json.loads(safe_gunzip(a.gz_bytes))["places"]]
    assert all(pl["category"] != "uncategorized" for pl in shipped)  # nothing uncategorized ships
    # and every emitted tile validates against tile.schema.json (coherence MED-2):
    import jsonschema, pathlib
    ts = json.loads(pathlib.Path("contracts/schemas/tile.schema.json").read_text())
    for a in arts: jsonschema.validate(json.loads(safe_gunzip(a.gz_bytes)), ts, resolver=_place_resolver())

def test_superseded_AND_tombstoned_without_successor_are_both_excluded():
    recs = [R.RegistryRecord(place_id=_vid("D"), refs={"wd:Q1"}, mint_anchor="wd:Q1", status="tombstoned",
                             superseded_by=_vid("E"), first_shipped_version="20260101T000000Z",
                             last_seen_version="20260101T000000Z", schema_version=1),
            R.RegistryRecord(place_id=_vid("F"), refs={"wd:Q2"}, mint_anchor="wd:Q2", status="tombstoned",
                             superseded_by=None,   # NO successor -> resolve_superseded returns it -> winner check MISSES it
                             first_shipped_version="20260101T000000Z", last_seen_version="20260101T000000Z", schema_version=1)]
    arts, counts = T.emit_tiles([_p(_vid("D"),1,0.9), _p(_vid("F"),1,0.9), _p(_vid("A"),1,0.9)], registry_records=recs)
    assert counts.non_winner_excluded == 2 and counts.total_published == 1   # both dead ids dropped; only the live one ships

def test_dense_cell_reselects_under_the_compressed_cap():
    from mt_contracts.caps import MAX_TILE_COMPRESSED_BYTES
    dense = [_p(_vid(chr(48+i)) if i < 10 else _vid(chr(55+i)), 1, 1.0 - i*1e-6) for i in range(30)]
    for p in dense: p["blurb"] = "A"*600                            # rich places: pass 8MiB uncompressed, risk 1MiB compressed
    arts, _ = T.emit_tiles(dense, [])
    assert all(a.byte_len <= MAX_TILE_COMPRESSED_BYTES for a in arts)   # re-select kept every tile under the cap (no crash)

def test_emission_is_byte_identical_on_repeat():
    places = [_p(_vid("A"), 1, 0.9), _p(_vid("C"), 2, 0.5)]
    a1, _ = T.emit_tiles(places, []); a2, _ = T.emit_tiles(places, [])
    assert [x.gz_bytes for x in a1] == [x.gz_bytes for x in a2]      # deterministic (gzip mtime=0)
```

- [ ] **Step 2–4:** implement in the order above (validate+quarantine → exclude-uncategorized → reject-non-winner/non-live → partition → select+gzip with compressed-cap re-select). **Teeth (host-verified vs real `mt_contracts`):** the exclude test reds if uncategorized/invalid drops are silent or an uncategorized/short-id/NaN place ships; the winners test reds if a superseded OR a tombstoned-without-successor id ships (neuter either check → a dead id ships → red — the second is the hole the winner-primitive alone misses); the dense-cell test reds if a >1 MiB-compressed tile isn't re-selected (it would crash `gzip_tile`); the determinism test consumes A0's `gzip_tile` (can't drift). All fixture ids are valid 26-char Crockford (else `place.schema` rejects them — coherence MED-2).
- [ ] **Step 5: Commit** — `"Add tile emission: exclude-uncategorized (counted) + winners-only + deterministic gzip+sha256"`

---

### Task 4: Manifest assembly (schema-validated, self-contained)

**Files:** Create `pipeline/src/mt_pipeline/publish/manifest.py`; Test `pipeline/tests/test_publish_manifest.py`

**Interfaces:**
- Consumes: `tiles.TileArtifact`/`PublishCounts`, `attribution.attribution_for`, `basemap.BasemapArtifact` (Task 5), the frozen `manifest.schema.json`.
- Produces:
  - `manifest.assemble_manifest(*, region, publish_version, generated_at, tiles, counts, basemap, scoring_config_version, llm_provenance=(), attribution=()) -> dict` — builds the manifest: `schema_version=1`, `region`, `publish_version` (PARAM), `generated_at` (PARAM), `tile_z=10`, `tiles` (sorted `(x,y)`, each `{x,y,sha256,bytes}`), `counts` (`total` + `by_tier[4]`), `basemap`, `attribution`. **Provenance is ALWAYS ≥1** (spec-fidelity HIGH / coherence MED): it prepends the heuristic-tiering entry `{task_id:"score", model:"heuristic", prompt_version:scoring_config_version}` (records the A4 config that produced the tiering, §5.2) to any `llm_provenance` entries A6 supplied — so a no-LLM publish still has a legal provenance. **`min_reader_version` = 2 when `attribution` is non-empty** (a legally-required credit must be rendered — else `1`; spec-fidelity MED). **Validates against `manifest.schema.json` before returning** (raises `ManifestInvalid`).

- [ ] **Step 1: Write the failing tests**

```python
import pytest
from mt_pipeline.publish import manifest as M

def test_no_LLM_publish_still_gets_a_valid_manifest_with_score_provenance(sample_tiles, sample_basemap):
    # LLM off / A6 never ran -> llm_provenance empty. The manifest MUST still validate (provenance >=1).
    man = M.assemble_manifest(region="uk", publish_version="20260715T120000Z", generated_at="2026-07-15T12:00:00Z",
                              tiles=sample_tiles, counts=sample_counts, basemap=sample_basemap,
                              scoring_config_version="scoring-v1", llm_provenance=(), attribution=())
    assert man["provenance"][0] == {"task_id":"score","model":"heuristic","prompt_version":"scoring-v1"}
    assert man["tiles"] == sorted(man["tiles"], key=lambda t: (t["x"], t["y"]))   # deterministic order
    assert man["counts"]["total"] == sum(man["counts"]["by_tier"])                # counts consistent
    assert man["min_reader_version"] == 1                                         # no attribution -> reader 1

def test_attribution_bumps_min_reader_version(sample_tiles, sample_basemap):
    man = M.assemble_manifest(region="uk", publish_version="20260715T120000Z", generated_at="2026-07-15T12:00:00Z",
                              tiles=sample_tiles, counts=sample_counts, basemap=sample_basemap,
                              scoring_config_version="scoring-v1",
                              attribution=[{"source":"historic_england","license":"OGL-3.0","text":"Contains HE data..."}])
    assert man["min_reader_version"] == 2                                         # HE OGL must be rendered -> reader >=2

def test_manifest_rejects_an_oversize_tile(sample_tiles, sample_basemap):
    bad = [{"x":0,"y":0,"sha256":"0"*64,"bytes": 2*1024*1024}]                     # > MAX_TILE_COMPRESSED_BYTES (1MiB)
    with pytest.raises(M.ManifestInvalid):
        M.assemble_manifest(region="uk", publish_version="20260715T120000Z", generated_at="2026-07-15T12:00:00Z",
                            tiles=bad, counts=sample_counts, basemap=sample_basemap, scoring_config_version="scoring-v1")
```

- [ ] **Step 2–4:** implement; prepend the `score` provenance entry, derive `min_reader_version`, validate with `jsonschema` against `manifest.schema.json`. **Teeth (host-verified):** the no-LLM test reds if provenance can be empty (the crown coherence hole); the min-reader test reds if attribution doesn't bump the reader floor (HE data would ship uncredited); the oversize-tile test reds if the schema's `bytes` maximum isn't enforced.
- [ ] **Step 5: Commit** — `"Add manifest assembly (schema-validated; param version; consistent counts)"`

---

### Task 5: Region basemap cut (`pmtiles extract`, budget-checked)  `[real cut BLOCKED-ON pmtiles CLI + Protomaps source]`

**Files:** Create `pipeline/src/mt_pipeline/publish/basemap.py`; Test `pipeline/tests/test_publish_basemap.py`

**Interfaces:**
- Consumes: the region-config `basemap` descriptor (`source_pmtiles`, `maxzoom=14`, `bbox`, `size_budget_bytes`, `measured_archive_bytes`); `mt_contracts.caps.PACK_BUDGET_CEILING_BYTES` (3GiB), `BASEMAP_MAXZOOM` (14).
- Produces:
  - `basemap.BasemapArtifact` — `frozen(filename, maxzoom=14, sha256, bytes, bbox)` (the manifest `basemap` shape — exactly ONE per region, matching the manifest's single required `basemap` object).
  - `basemap.cut_basemap(region_config, out_path) -> BasemapArtifact` — **ONE cut for THIS region's bbox** (spec-fidelity HIGH-2): invoke `pmtiles extract <source_pmtiles> <out> --maxzoom=14 --bbox=<region bbox>`, then **verify `bytes ≤ min(size_budget_bytes, PACK_BUDGET_CEILING_BYTES)`** — raise `BasemapOverBudget` otherwise, naming the region. sha256 the file. filename matches the manifest `basemap.filename` pattern (`{region}.pmtiles`).
  - **Sub-region packs are SEPARATE REGIONS, not a fan-out inside one publish (spec-fidelity HIGH-2).** A country that exceeds its budget is NOT auto-split here — the manifest holds exactly one basemap and the tiles were partitioned for one region, so a multi-cut-in-one-publish produces an **unpublishable** artifact set. Instead: `cut_basemap` **FAILS LOUD** (`BasemapOverBudget`) telling ops to define sub-region region-configs (e.g. `uk_england`, `uk_scotland` — each its own `region`, bbox, manifest, tile partition, and publish). That's the §5.1 sub-region-pack knob at the right layer (region-config expansion), a pipeline config change, not an A7 code path. **(The `pmtiles` invocation is BLOCKED-ON the CLI + a real Protomaps source; the budget-check logic is testable now with a small fixture `.pmtiles`.)**

- [ ] **Step 1: Write the failing tests**

```python
import pytest
from mt_pipeline.publish import basemap as B

def test_within_budget_produces_one_basemap_matching_the_manifest_shape(tmp_path, small_pmtiles):
    cfg = {"region": "uk", "basemap": {"source_pmtiles": str(small_pmtiles), "maxzoom": 14,
           "size_budget_bytes": 3_000_000_000, "measured_archive_bytes": 1_400_000_000, "bbox": [-8.6,49.8,1.8,60.9]}}
    art = B.cut_basemap(cfg, tmp_path/"uk.pmtiles")
    assert art.maxzoom == 14 and art.filename == "uk.pmtiles" and art.bytes >= 1   # single basemap, manifest-shaped

def test_over_budget_region_fails_loud_directing_ops_to_subregion_configs(tmp_path, small_pmtiles):
    cfg = {"region": "uk", "basemap": {"source_pmtiles": str(small_pmtiles), "maxzoom": 14,
           "size_budget_bytes": 1, "measured_archive_bytes": 5_000_000_000, "bbox": [-8.6,49.8,1.8,60.9]}}
    with pytest.raises(B.BasemapOverBudget):                       # NOT an auto-split -> ops defines sub-region regions
        B.cut_basemap(cfg, tmp_path/"uk.pmtiles")
```

- [ ] **Step 2–4:** implement `cut_basemap` (subprocess `pmtiles extract` + single-region budget check + sha256). **Teeth:** the budget test reds if an over-budget cut isn't rejected (a 3GiB+ pack blows the §5.1 download budget), and the fail-loud is the deliberate signal to split via region-config, not to emit an unpublishable multi-basemap set. Mark the `pmtiles` subprocess BLOCKED-ON the CLI.
- [ ] **Step 5: Commit** — `"Add single-region basemap cut (pmtiles extract; fail-loud over budget -> sub-region region-configs)"`

---

### Task 6: Local-first staging + atomic versioned publish (manifest LAST, rollback = repoint)

**Files:** Create `pipeline/src/mt_pipeline/publish/staging.py`, `pipeline/src/mt_pipeline/publish/r2.py`, `pipeline/config/r2_layout.json`; Test `pipeline/tests/test_publish_atomic.py`

**Interfaces:**
- Consumes: `tiles`/`manifest`/`basemap` artifacts; `r2_layout.json`; the `region`/`publish_version` schema patterns.
- Produces:
  - `r2.validate_path_components(region, publish_version)` — **asserts `region` matches `^[a-z][a-z0-9_]*$` and `publish_version` matches `^[0-9]{8}T[0-9]{6}Z$` BEFORE any path/key is built** (hostile-data HIGH-1 — `mt publish "../../mt-state" --publish-version "../current"` must be refused; a raw `region`/`version` joined into a filesystem path or R2 key traverses out of staging or addresses a sibling/private prefix). Raises `UnsafePathComponent`. Called at the TOP of `build_staging`, `PublishPlan.for_version`, and `publish_stage.run`.
  - `staging.build_staging(root, region, publish_version, *, tile_arts, manifest_obj, basemap_path) -> Path` — validates components, then writes the **identical R2 layout to a local dir**: `{region}/{publish_version}/tiles/10/{x}/{y}.json.gz`, `{region}/{publish_version}/{region}.pmtiles`, `{region}/{publish_version}/manifest.json`. Pure filesystem, no creds — the testable default.
  - `r2.PublishPlan` — validates components, then the ordered op list: `put` every tile + basemap under `{public}/{region}/{publish_version}/`, **then** `put` `manifest.json`, **then** `put` `{public}/{region}/current.json`, **then** `put` the registry blob to `{private}/…`. **Construction ASSERTS `layout["public_bucket"] != layout["private_bucket"]`** (raise `LayoutInvalid`) and that **EVERY private-kind op (`registry`/`cache`/`feedback`) targets the private bucket and no public-kind op carries the private bucket** (hostile-data MED-1 — generalised beyond just the registry, so A6's cache + C2's feedback are covered). `manifest_index()` returns the manifest op index.
  - `r2.publish_to_r2(staging, layout, *, client, upload=False, uploaded_ledger) -> PublishResult` — **version-immutability guard (hostile-data HIGH-2 + MED-6):** refuse if `publish_version` is already the live `current`, or if the target `{region}/{publish_version}/` prefix already exists and is not a proven byte-identical re-run; acquire a **per-region publish lock** (a lease object `{private}/{region}/publish.lock` with TTL, conditional-PUT) before upload, release after. **Diff-aware upload (spec-fidelity LOW / hostile-data MED-4):** the skip decision is driven by a **trusted local `uploaded_ledger`** of `(publish_version, x, y, sha256)` A7 itself recorded — NEVER a remote R2 ETag (ETag ≠ sha256 for multipart; a truncated remote object can match metadata). Since tiles are version-path-scoped, a fresh version has NO ledger → every object is PUT (no false skip → no 404); #54's cross-version reuse would content-address by sha256 or copy-forward, not skip against a per-version path. `upload=False` (default) = dry-run returning the plan, no R2.

- [ ] **Step 1: Write the failing tests** (staging + plan ordering + guards run now, no R2):

```python
import json, pytest
from mt_pipeline.publish import staging as S, r2 as R

def test_unsafe_region_or_version_is_refused_before_any_path_is_built():   # hostile-data HIGH-1
    for region, ver in [("../../mt-state", "20260715T120000Z"), ("uk", "../current"), ("UK", "20260715T120000Z")]:
        with pytest.raises(R.UnsafePathComponent):
            R.validate_path_components(region, ver)
    R.validate_path_components("uk", "20260715T120000Z")               # the valid pair passes

def test_manifest_is_the_LAST_content_op_then_current_flip():
    plan = R.PublishPlan.for_version(layout, "uk", "20260715T120000Z", sample_arts, basemap=True)
    mi = plan.manifest_index()
    assert all(op.kind in ("tile", "basemap") for op in plan.ops[:mi])   # all content BEFORE manifest
    assert plan.ops[mi].kind == "manifest" and plan.ops[mi+1].kind == "current"   # flip AFTER manifest

def test_all_private_kind_ops_target_the_private_bucket_and_layout_is_distinct():
    plan = R.PublishPlan.for_version(layout, "uk", "20260715T120000Z", sample_arts, basemap=True,
                                     registry_blob={"x":1}, cache_blob={"y":1})
    for op in plan.ops:
        if op.kind in ("registry", "cache", "feedback"):
            assert op.bucket == layout["private_bucket"]                # never public (crown security invariant)
        if op.kind in ("tile", "basemap", "manifest", "current"):
            assert op.bucket == layout["public_bucket"]
    bad = {**layout, "private_bucket": layout["public_bucket"]}         # a misconfigured (equal) layout
    with pytest.raises(R.LayoutInvalid):
        R.PublishPlan.for_version(bad, "uk", "20260715T120000Z", sample_arts, basemap=True)

def test_the_real_r2_layout_config_has_two_distinct_buckets():          # hostile-data MED-1 (test the REAL config)
    layout = json.loads(open("pipeline/config/r2_layout.json").read())
    assert layout["public_bucket"] != layout["private_bucket"]
```

- [ ] **Step 2–4:** implement `validate_path_components`, `build_staging`, `PublishPlan` (ordered, bucket-tagged, layout-distinct + private-kind guard), `publish_to_r2` (boto3; version-immutability + lock; ledger-driven diff-aware; `upload=False` dry-run). **Teeth:** the path test reds if an unsafe `region`/`version` reaches a path/key; the ordering test reds if the manifest isn't last or `current` flips early (partial publish, §6); the bucket test reds if any private-kind op targets public OR the layout isn't distinct (the never-public invariant, now covering cache+feedback); the real-config test reds if `r2_layout.json` ever collapses the two buckets. **The live R2 upload + lock are BLOCKED-ON Rob's scoped R2 token.**
- [ ] **Step 5: Commit** — `"Add staging + atomic publish (path-validated, layout-distinct, version-immutable + lock, ledger-diff-aware, private-state)"`

---

### Task 7: CLI + the publish stage + real publish  `[real run BLOCKED-ON A2/A3/A4 impls + R2 creds + pmtiles]`

**Files:** Modify `cli.py` (the `publish` stage), `pipeline/src/mt_pipeline/publish/publish_stage.py`; the report stub.

**Interfaces:** `publish_stage.run(conn, region, *, publish_version, generated_at, scoring_config_version, upload=False)` is the `STAGE_ORDER` **`publish`** body (predecessor-gated after `categorize`): **`validate_path_components(region, publish_version)` FIRST**, then join A2 `places` + A3 `place_categories` + A4 `place_scores`, load the registry, `emit_tiles` → `cut_basemap` → `assemble_manifest` → `build_staging` → `publish_to_r2`. **On successful publish, the registry mutation is routed through an A2-OWNED function `registry.mark_shipped(records, shipped_ids, publish_version)`** that sets `first_shipped_version` (on first ship — the §5.2 "never reassigned" audit trail) AND `last_seen_version` — A7 is NOT a second independent registry writer; A2 owns the registry shape and the single-writer discipline (spec-fidelity MED). `mt publish <region> --publish-version <v> --scoring-config-version <cv> [--generated-at <ts>] [--upload]`.

- [ ] **Step 1 (local, after A2/A3/A4 impls + real extracts):** `mt extract/reconcile/score/categorize uk` then `mt publish uk --publish-version 20260715T120000Z` (no `--upload`) → the full local staging tree + the publish report (counts incl. `uncategorized_excluded`, `overflow_dropped`, tile total, by_tier, basemap bytes). Commit `docs/superpowers/reports/2026-07-15-a7-publish.md`.
- [ ] **Step 2 (BLOCKED-ON Rob's R2 token + `pmtiles` CLI):** with the scoped R2 credentials in 1Password + `.env.tpl`, `op run --env-file=.env.tpl -- uv run mt publish uk --publish-version <v> --upload` → real versioned publish to `mt-tiles` (+ registry to `mt-state`); verify the app-visible `current` → manifest → tiles chain; verify a rollback (repoint `current`) restores the prior version. One `op run` per publish run.
- [ ] **Step 3: Commit** — `"Add publish stage + CLI + real UK publish (staging local; R2 upload after creds)"`

---

## Review Record

**Author self-review** — deliverables map to tasks: the z10 partition (T1), the append-only attribution field + `attribution_for` (T2), tile emission with exclude-uncategorized + winners-only + deterministic gzip (T3), schema-validated manifest assembly (T4), budget-checked basemap cutting (T5), local-first staging + atomic versioned publish with the public/private bucket split (T6), and the CLI + publish stage (T7). A7 **consumes A0's `select_tile_places`/`gzip_tile`/`tile_winner_violations` unchanged** (consume-don't-reinvent). The publish is deterministic (`publish_version`/`generated_at` are params), atomic (manifest last + `current` flip), and non-partial (§6); rollback is a repoint. A7 is the last pipeline design.

**Issue #11 inputs folded:**
- **Attribution** → an append-only OPTIONAL `manifest.attribution` field, populated verbatim from `a1d_sources.json`; HE OGL v3.0 mandatory when HE ships, Open Plaques PDDL courtesy. (Append-only A0 schema change, unshipped → no reader bump; caps drift-guarded.)
- **Uncategorized-never-published** → A7 **EXCLUDES** `category=="uncategorized"` (my call over remap/gate-on-A6, justified: no A6 slot before publish; remap would ship a guessed category), **COUNTS** the exclusion (visible, not silent), and **ASSERTS** none ship.

**Cross-package needs surfaced:**
- **BLOCKED-ON A2/A3/A4 impls** — the publish joins `places`/`place_categories`/`place_scores`, all merged plan-only (none in code). Real extracts are `wp-acquire-impl`. **§8 lists A7 deps as A0+A4 only, but A7 genuinely reads A2 (places+registry) + A3 (categories) — that undeclared dependency is surfaced here** (spec-fidelity MED).
- **BLOCKED-ON the `pmtiles` CLI + a Protomaps source** for the real basemap cut; the budget logic is testable now.
- **BLOCKED-ON Rob's R2 token** — an S3-compatible token scoped to EXACTLY `mt-tiles` (public) + `mt-state` (private), read+write, in 1Password (`R2_ACCOUNT_ID`/`R2_ACCESS_KEY_ID`/`R2_SECRET_ACCESS_KEY`) + `.env.tpl`. One `op run` per publish run (`docs/SECRETS.md`).
- **A0 append-only changes (coordinated; schema unshipped → additive-safe; caps drift-guarded):** `manifest.schema.json` gains OPTIONAL `attribution` (scrubbed strings) + the `"score"` provenance-enum member (the no-LLM path) + the `min_reader_version=2` rule; a NEW `current.schema.json` pins the pointer B-track consumes. `caps.py` gains the attribution caps + `CAPS_SCHEMA_MAP` entries. **Before editing `manifest/1` in place, verify no shipped/pinned consumer exists** (B1 merged, B2+ in flight — the tile client B3 is unbuilt).
- **Registry mutation via an A2-owned `mark_shipped` (single writer):** A7 does NOT write the registry directly — it calls A2's `registry.mark_shipped(records, ids, publish_version)` which sets `first_shipped_version` (first ship) + `last_seen_version`, on publish success only (§6), to the PRIVATE bucket. A2 owns the registry contract + the single-writer discipline.
- **Two-bucket layout is a security invariant** — the registry/cache/feedback never enter the public bucket; a runtime guard + a real-config test enforce it.
- **A7 is NOT the markup-XSS defense layer (by design):** `place.schema` deliberately permits `<`/`>`/`&` in `blurb` (only control chars are excluded), so a vandalised summary ships as-is; the **plain-text-only render is the APP's contract (§5.5, hostile-data LOW-2)** — flagged so B-track owns the neutralization, not silently assumed.

**Adversarial review (per AGENTS.md gate) — RAN before merge; 3 critics (spec-fidelity, hostile-data/security, coherence-that-BUILDS-and-RUNS-the-staging-chain against real `mt_contracts` + real schemas). All survivors folded; every fix host-verified.**

*Crown finding (spec-fidelity HIGH + coherence MED, execution-proven):* a **no-LLM/heuristic-only publish was structurally IMPOSSIBLE** — `provenance` requires `minItems:1` but the enum was all-LLM (`curiosity/blurb/category/reconcile`), so a pure-heuristic run had nothing legal to put there, AND it contradicted the plan's own "don't couple publish to optional A6" argument. **Fixed:** the append-only A0 change adds a `"score"` provenance kind and `assemble_manifest` ALWAYS prepends `{task_id:"score", model:"heuristic", prompt_version:<A4 config>}` (records the config that produced the tiering, §5.2) — provenance is `≥1` even with the LLM off (host-verified: validates with the enum widened; empty still rejected).

*Spec-fidelity HIGH + MED:* the sub-region basemap **fan-out produced an unpublishable set** (manifest holds ONE basemap) → collapsed to one cut per region, over-budget FAILS LOUD directing ops to define sub-region region-configs. The `source_refs` **prefix→a1d-key mapping was undefined** (so "OGL when HE ships" couldn't fire) → pinned `PREFIX_TO_SOURCE_KEY` + derive `sources_used` from shipped places. **OSM is ODbL** (my "osm→no attribution" was legally wrong) → added OSM ODbL to `a1d_sources.json`. Attribution added to a frozen `additionalProperties:false` schema isn't backward-safe → **`min_reader_version=2`** when attribution present (HE data never ships uncredited). `current.json` was an uncontracted cross-track artifact → a pinned `current.schema.json`. The 8 MiB-uncompressed / 1 MiB-compressed budget mismatch could crash a dense cell → **compressed-cap re-select** (host-verified).

*Hostile-data HIGH + MED:* `region`/`publish_version` were joined into paths/keys **unvalidated** (traversal into the private bucket) → `validate_path_components` before any path/key. No **version-immutability guard** (republish over a live version breaks atomicity) → refuse existing/live prefixes + a per-region publish **lock**. The two-bucket invariant had **no runtime guard** and the test used a fixture → runtime `public!=private` assert + a test of the REAL `r2_layout.json` + generalised to cache/feedback ops. Attribution shipped **verbatim without a scrub pattern** → the control-char-excluding pattern (fail-closed). One hostile place **aborted the whole publish** → per-place validate+quarantine (`invalid_excluded`), one vandalised row never denies the region. Diff-aware upload **trusted a remote ETag** → a trusted local ledger, never ETag. The winners gate **missed a tombstoned-without-successor** place → also reject non-live status (host-verified: the winner primitive alone lets it ship).

*Held under execution (coherence, all TRUE):* the z10 tile numbers (London (511,340), KL (801,503) — the wrong KL value I'd hard-coded was caught pre-gate), the uncategorized + winners-only teeth (+ neuters go red), determinism (A0 `gzip_tile` mtime=0), manifest validation, attribution verbatim, the manifest-last/atomic ordering + private-bucket routing, and BLOCKED-ON honesty (`mt_pipeline.publish` genuinely absent; the pure chain needs no pmtiles/R2/A2-A4 tables). A0 primitives CONSUMED, not re-implemented.
