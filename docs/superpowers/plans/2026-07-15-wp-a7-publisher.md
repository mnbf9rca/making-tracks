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
- **Per-source ATTRIBUTION in the manifest — append-only A0 schema field, single-sourced from `a1d_sources.json` (issue #11).** The manifest is the natural carrier so the app renders a credits screen from DATA, not hardcoded strings. The `manifest.schema.json` gains an **optional `attribution` array** (append-only; the schema is unshipped so no `schema_version`/reader bump — but the field is OPTIONAL so a region with only public-domain sources still validates). A7 populates it **only for the sources actually used in the region**, copying `license` + `attribution` text verbatim from `a1d_sources.json` (never re-typed): **Historic England OGL v3.0 is MANDATORY** when `historic_england` contributed; Open Plaques PDDL-1.0 is a courtesy credit. A test asserts the OGL string is present whenever an HE-sourced place ships.
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
contracts/  (A0 append-only — coordinated small change)
  schemas/manifest.schema.json   # + OPTIONAL `attribution: [{source, license, text}]`
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
  - `partition.lonlat_to_z10(lat: float, lon: float) -> tuple[int, int]` — the standard Web-Mercator slippy-tile formula at z=10, returning `(x, y)` each clamped to `[0, 1023]` (matches the tile/manifest schema `0..1023`). Places at the poles/antimeridian clamp into range, never out.
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

### Task 2: Attribution + the append-only manifest schema field

**Files:** Modify `contracts/schemas/manifest.schema.json` (+ optional `attribution`), `contracts/src/mt_contracts/caps.py` (+ attribution caps); Create `pipeline/src/mt_pipeline/publish/attribution.py`; Test `pipeline/tests/test_publish_attribution.py`

**Interfaces:**
- Consumes: `pipeline/config/a1d_sources.json` (the `license` + `attribution` fields per source — already present).
- Produces:
  - Manifest schema gains OPTIONAL `attribution`: `array` (maxItems 32) of `{source: string≤32, license: string≤32, text: string≤512}`, `additionalProperties:false`. Append-only; the schema is unshipped so no `schema_version` bump; OPTIONAL so a public-domain-only region still validates. Caps added to `caps.py` + `CAPS_SCHEMA_MAP` (the drift-guard).
  - `attribution.attribution_for(sources_used: set[str], a1d_sources: Mapping) -> list[dict]` — for each source key in `sources_used`, emit `{source, license, text}` copying `a1d_sources[source]["license"]`/`["attribution"]` **verbatim** (never re-typed). Sorted by `source` (deterministic). Sources with no attribution entry contribute nothing.

- [ ] **Step 1: Write the failing tests**

```python
import json, pathlib
from mt_pipeline.publish import attribution as A

A1D = json.loads(pathlib.Path("pipeline/config/a1d_sources.json").read_text())

def test_HE_OGL_attribution_is_present_and_verbatim_when_HE_used():
    out = A.attribution_for({"historic_england", "wikidata"}, A1D)
    he = [a for a in out if a["source"] == "historic_england"][0]
    assert he["license"] == "OGL-3.0"
    assert he["text"] == A1D["historic_england"]["attribution"]     # verbatim, not re-typed
    assert "Open Government Licence" in he["text"]                    # the OGL string actually ships

def test_public_domain_only_region_needs_no_attribution():
    out = A.attribution_for({"wikidata", "osm"}, A1D)                 # neither in a1d_sources
    assert out == []                                                 # optional field -> empty is valid

def test_manifest_schema_accepts_attribution_and_caps_are_mapped():
    schema = json.loads(pathlib.Path("contracts/schemas/manifest.schema.json").read_text())
    assert "attribution" in schema["properties"]                     # append-only field landed
    assert "attribution" not in schema["required"]                   # OPTIONAL
    from mt_contracts.caps import CAPS_SCHEMA_MAP                     # drift-guard: caps single-sourced
    assert any(k[0] == "manifest" and "attribution" in k[1] for k in CAPS_SCHEMA_MAP)
```

- [ ] **Step 2–4:** add the schema field + caps + `attribution_for`; validate a manifest carrying attribution. **Teeth:** the HE test reds if the OGL text is dropped or paraphrased (licence breach); the public-domain test reds if attribution is wrongly required; the caps test reds if the new field escapes the `CAPS_SCHEMA_MAP` drift-guard.
- [ ] **Step 5: Commit** — `"Add manifest attribution field (append-only) + attribution_for (HE OGL mandatory, verbatim)"`

---

### Task 3: Tile emission — select + exclude-uncategorized + winners-only + deterministic gzip

**Files:** Create `pipeline/src/mt_pipeline/publish/tiles.py`; Test `pipeline/tests/test_publish_tiles.py`

**Interfaces:**
- Consumes: **A0's `mt_contracts.caps.select_tile_places`, `mt_contracts.tilecodec.gzip_tile`, `mt_contracts.registry.tile_winner_violations`** (UNCHANGED); `partition.partition_places`.
- Produces:
  - `tiles.PublishCounts` — `frozen(total_published, by_tier: tuple[int,int,int,int], uncategorized_excluded, overflow_dropped)`.
  - `tiles.TileArtifact` — `frozen(x, y, gz_bytes: bytes, sha256: str, byte_len: int)`.
  - `tiles.emit_tiles(places, registry_records) -> tuple[list[TileArtifact], PublishCounts]` — (1) **exclude `category == "uncategorized"`** places (counted into `uncategorized_excluded`); (2) partition; (3) per cell, `select_tile_places` (kept/dropped → `overflow_dropped`); (4) **assert `tile_winner_violations(kept_ids, registry_records) == []`** — a superseded/non-winner id in a tile RAISES `NonWinnerInTileError` (winners-only, §5.2); (5) build the `tile.schema.json` object, `gzip_tile` it, sha256 the bytes. Deterministic: same inputs → byte-identical `gz_bytes` + identical sha256.

- [ ] **Step 1: Write the failing tests**

```python
import pytest
from mt_pipeline.publish import tiles as T

def _p(pid, tier, score, cat="history", lat=51.5, lon=-0.1):
    return {"place_id": pid, "name": "n", "lat": lat, "lon": lon, "category": cat,
            "tier": tier, "score": score, "source_refs": ["wd:Q1"]}

def test_uncategorized_is_excluded_and_counted_not_silent():
    places = [_p("mt1_a", 1, 0.9), _p("mt1_b", 4, 0.1, cat="uncategorized")]
    arts, counts = T.emit_tiles(places, registry_records=[])
    assert counts.uncategorized_excluded == 1 and counts.total_published == 1
    # and no shipped tile contains an 'uncategorized' place (the teeth-ful gate):
    import json; from mt_contracts.tilecodec import safe_gunzip
    shipped = [pl for a in arts for pl in json.loads(safe_gunzip(a.gz_bytes))["places"]]
    assert all(pl["category"] != "uncategorized" for pl in shipped)

def test_non_winner_id_in_a_tile_raises(monkeypatch):
    # a superseded place_id must never ship — winners only (§5.2)
    from mt_contracts import registry as R
    rec = [R.RegistryRecord(place_id="mt1_old", refs={"wd:Q1"}, mint_anchor="wd:Q1", status="tombstoned",
                            superseded_by="mt1_new", first_shipped_version="20260101T000000Z",
                            last_seen_version="20260101T000000Z", schema_version=1)]
    with pytest.raises(T.NonWinnerInTileError):
        T.emit_tiles([_p("mt1_old", 1, 0.9)], registry_records=rec)

def test_emission_is_byte_identical_on_repeat():
    places = [_p("mt1_a", 1, 0.9), _p("mt1_c", 2, 0.5)]
    a1, _ = T.emit_tiles(places, []); a2, _ = T.emit_tiles(places, [])
    assert [x.gz_bytes for x in a1] == [x.gz_bytes for x in a2]      # deterministic (gzip mtime=0)
```

- [ ] **Step 2–4:** implement; **exclude before partition**, `select_tile_places` per cell, `tile_winner_violations` assertion, `gzip_tile` + `hashlib.sha256`. **Teeth (host-verifiable now):** the uncategorized test reds if the exclusion is silent or a `"uncategorized"` place ships; the winners test reds if a superseded id isn't rejected (neuter the `tile_winner_violations` check → a tombstoned id ships → red); the determinism test reds if gzip isn't `mtime=0` (it consumes A0's `gzip_tile`, so it can't drift).
- [ ] **Step 5: Commit** — `"Add tile emission: exclude-uncategorized (counted) + winners-only + deterministic gzip+sha256"`

---

### Task 4: Manifest assembly (schema-validated, self-contained)

**Files:** Create `pipeline/src/mt_pipeline/publish/manifest.py`; Test `pipeline/tests/test_publish_manifest.py`

**Interfaces:**
- Consumes: `tiles.TileArtifact`/`PublishCounts`, `attribution.attribution_for`, `basemap.BasemapArtifact` (Task 5), the frozen `manifest.schema.json`.
- Produces:
  - `manifest.assemble_manifest(*, region, publish_version, generated_at, tiles, counts, basemap, provenance, attribution) -> dict` — builds the manifest: `schema_version=1`, `min_reader_version`, `region`, `publish_version` (PARAM), `generated_at` (PARAM), `tile_z=10`, `tiles` (sorted `(x,y)`, each `{x,y,sha256,bytes}`), `counts` (`total` + `by_tier[4]` from `PublishCounts`), `basemap` (from the cut), `provenance` (the `(task_id,model,prompt_version)` set from A6's cache era / A4 config — `≥1`), `attribution`. **Validates against `manifest.schema.json` before returning** (raises `ManifestInvalid` otherwise).

- [ ] **Step 1: Write the failing tests**

```python
from mt_pipeline.publish import manifest as M

def test_manifest_validates_and_counts_are_consistent(sample_tiles, sample_basemap):
    man = M.assemble_manifest(region="uk", publish_version="20260715T120000Z", generated_at="2026-07-15T12:00:00Z",
                              tiles=sample_tiles, counts=sample_counts, basemap=sample_basemap,
                              provenance=[{"task_id":"curiosity","model":"m","prompt_version":"curiosity-v1"}],
                              attribution=[])
    assert man["tiles"] == sorted(man["tiles"], key=lambda t: (t["x"], t["y"]))   # deterministic order
    assert man["counts"]["total"] == sum(man["counts"]["by_tier"])                # counts consistent
    assert man["publish_version"] == "20260715T120000Z"                           # param, not wall-clock

def test_manifest_rejects_an_oversize_tile(sample_basemap):
    bad = [{"x":0,"y":0,"sha256":"0"*64,"bytes": 2*1024*1024}]                     # > MAX_TILE_COMPRESSED_BYTES (1MiB)
    import pytest
    with pytest.raises(M.ManifestInvalid):
        M.assemble_manifest(region="uk", publish_version="20260715T120000Z", generated_at="2026-07-15T12:00:00Z",
                            tiles=bad, counts=sample_counts, basemap=sample_basemap,
                            provenance=[{"task_id":"curiosity","model":"m","prompt_version":"v1"}], attribution=[])
```

- [ ] **Step 2–4:** implement; validate with `jsonschema` against `manifest.schema.json`. **Teeth:** the consistency test reds if `by_tier` doesn't sum to `total`; the oversize-tile test reds if the schema's `bytes` maximum isn't enforced (the app would reject the manifest at read).
- [ ] **Step 5: Commit** — `"Add manifest assembly (schema-validated; param version; consistent counts)"`

---

### Task 5: Region basemap cut (`pmtiles extract`, budget-checked)  `[real cut BLOCKED-ON pmtiles CLI + Protomaps source]`

**Files:** Create `pipeline/src/mt_pipeline/publish/basemap.py`; Test `pipeline/tests/test_publish_basemap.py`

**Interfaces:**
- Consumes: the region-config `basemap` descriptor (`source_pmtiles`, `maxzoom=14`, `subregions`, `size_budget_bytes`, `measured_archive_bytes`); `mt_contracts.caps.PACK_BUDGET_CEILING_BYTES` (3GiB), `BASEMAP_MAXZOOM` (14).
- Produces:
  - `basemap.BasemapArtifact` — `frozen(filename, maxzoom=14, sha256, bytes, bbox)` (the manifest `basemap` shape).
  - `basemap.plan_cuts(region_config) -> list[Cut]` — if the whole-country `measured_archive_bytes` exceeds `size_budget_bytes`, return one `Cut` per `subregion` (the §5.1 sub-region-pack knob); else one country `Cut`. Pure — testable now.
  - `basemap.cut_basemap(cut, out_path) -> BasemapArtifact` — invoke `pmtiles extract <source_pmtiles> <out> --maxzoom=14 --bbox=<cut.bbox>`, then **verify `bytes ≤ min(size_budget_bytes, PACK_BUDGET_CEILING_BYTES)`** (raise `BasemapOverBudget` otherwise), sha256 the file, return the artifact. **(The `pmtiles` invocation is BLOCKED-ON the CLI + a real Protomaps source; the cut-planning + budget-check logic is testable now with a small fixture `.pmtiles`.)**

- [ ] **Step 1: Write the failing tests** (the pure planning + budget logic runs now):

```python
from mt_pipeline.publish import basemap as B

def test_over_budget_country_splits_into_subregion_cuts():
    cfg = {"basemap": {"source_pmtiles": "s.pmtiles", "maxzoom": 14, "size_budget_bytes": 3_000_000_000,
                       "measured_archive_bytes": 5_000_000_000, "bbox": [-8.6,49.8,1.8,60.9],
                       "subregions": [{"id":"england","bbox":[-6,50,2,56]},{"id":"scotland","bbox":[-8,55,-0.7,60.9]}]}}
    cuts = B.plan_cuts(cfg)
    assert [c.id for c in cuts] == ["england", "scotland"]        # over budget -> sub-region packs

def test_within_budget_is_one_country_cut():
    cfg = {"basemap": {"source_pmtiles": "s.pmtiles", "maxzoom": 14, "size_budget_bytes": 3_000_000_000,
                       "measured_archive_bytes": 1_400_000_000, "bbox": [-8.6,49.8,1.8,60.9], "subregions": []}}
    assert len(B.plan_cuts(cfg)) == 1

def test_a_cut_over_the_pack_ceiling_raises(tmp_path, small_pmtiles):   # budget guard has teeth
    import pytest
    with pytest.raises(B.BasemapOverBudget):
        B.cut_basemap(B.Cut(id="x", bbox=[-180,-85,180,85], source="s.pmtiles"), tmp_path/"x.pmtiles",
                      size_budget_bytes=1)                        # 1-byte budget forces the guard
```

- [ ] **Step 2–4:** implement `plan_cuts` (pure) + `cut_basemap` (subprocess `pmtiles extract` + budget check + sha256). **Teeth:** the split test reds if the over-budget country doesn't fan out to subregions; the budget test reds if a cut exceeding the budget isn't rejected (a 3GiB+ pack would blow the §5.1 download budget). Mark the `pmtiles` subprocess BLOCKED-ON the CLI.
- [ ] **Step 5: Commit** — `"Add basemap cut planning + pmtiles extract (budget-checked; sub-region fan-out)"`

---

### Task 6: Local-first staging + atomic versioned publish (manifest LAST, rollback = repoint)

**Files:** Create `pipeline/src/mt_pipeline/publish/staging.py`, `pipeline/src/mt_pipeline/publish/r2.py`, `pipeline/config/r2_layout.json`; Test `pipeline/tests/test_publish_atomic.py`

**Interfaces:**
- Consumes: `tiles`/`manifest`/`basemap` artifacts; `r2_layout.json`.
- Produces:
  - `staging.build_staging(root, region, publish_version, *, tile_arts, manifest_obj, basemap_path) -> Path` — writes the **identical R2 layout to a local dir**: `{region}/{publish_version}/tiles/10/{x}/{y}.json.gz`, `{region}/{publish_version}/{region}.pmtiles`, `{region}/{publish_version}/manifest.json`. Pure filesystem, no creds — the testable default.
  - `r2.PublishPlan` — the ordered op list: `put` every tile + basemap under `{public}/{region}/{publish_version}/`, **then** `put` `manifest.json`, **then** `put` `{public}/{region}/current.json` = `{"publish_version": …}` (the atomic flip), **then** `put` the registry `last_seen_version` to `{private}/…`. `manifest_index()` returns the index of the manifest op (for the ordering test).
  - `r2.publish_to_r2(staging, layout, *, client, upload=False) -> PublishResult` — execute the plan against an S3-compatible client (diff-aware: skip tiles whose sha256 matches what's already there — #54). `upload=False` (default) is a dry-run that returns the plan without calling R2. **Registry/cache paths are asserted to target the PRIVATE bucket only.**

- [ ] **Step 1: Write the failing tests** (staging + plan ordering + bucket split run now, no R2):

```python
import json
from mt_pipeline.publish import staging as S, r2 as R

def test_staging_has_the_identical_r2_layout(tmp_path, sample_arts, sample_manifest):
    d = S.build_staging(tmp_path, "uk", "20260715T120000Z", tile_arts=sample_arts,
                        manifest_obj=sample_manifest, basemap_path=None)
    assert (d/"uk/20260715T120000Z/manifest.json").exists()
    assert (d/f"uk/20260715T120000Z/tiles/10/{sample_arts[0].x}/{sample_arts[0].y}.json.gz").exists()

def test_manifest_is_the_LAST_content_op_then_current_flip():
    plan = R.PublishPlan.for_version(layout, "uk", "20260715T120000Z", sample_arts, basemap=True)
    mi = plan.manifest_index()
    assert all(op.kind == "tile" or op.kind == "basemap" for op in plan.ops[:mi])   # all content BEFORE manifest
    assert plan.ops[mi].kind == "manifest"
    assert plan.ops[mi+1].kind == "current"                                          # the atomic flip is AFTER manifest

def test_registry_never_targets_the_public_bucket():
    plan = R.PublishPlan.for_version(layout, "uk", "20260715T120000Z", sample_arts, basemap=True, registry_blob={"x":1})
    reg = [op for op in plan.ops if op.kind == "registry"][0]
    assert reg.bucket == layout["private_bucket"] and reg.bucket != layout["public_bucket"]
```

- [ ] **Step 2–4:** implement `build_staging`, `PublishPlan` (ordered, bucket-tagged), `publish_to_r2` (boto3 against R2; diff-aware; `upload=False` dry-run). **Teeth:** the ordering test reds if the manifest isn't the last content op or `current` flips before the manifest exists (a partial publish the app could see — §6); the bucket test reds if any registry/cache op targets the public bucket (the never-public invariant). **The live R2 upload is BLOCKED-ON Rob's scoped R2 token.**
- [ ] **Step 5: Commit** — `"Add local-first staging + atomic publish plan (manifest last, current flip, private-registry, diff-aware)"`

---

### Task 7: CLI + the publish stage + real publish  `[real run BLOCKED-ON A2/A3/A4 impls + R2 creds + pmtiles]`

**Files:** Modify `cli.py` (the `publish` stage), `pipeline/src/mt_pipeline/publish/publish_stage.py`; the report stub.

**Interfaces:** `publish_stage.run(conn, region, *, publish_version, generated_at, upload=False)` is the `STAGE_ORDER` **`publish`** body (predecessor-gated after `categorize`): join A2 `places` + A3 `place_categories` + A4 `place_scores`, load the registry, `emit_tiles` → `cut_basemap` → `assemble_manifest` → `build_staging` → `publish_to_r2`; **the registry `last_seen_version` is written only on a successful publish (§6).** `mt publish <region> --publish-version <v> [--generated-at <ts>] [--upload]`.

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
- **BLOCKED-ON A2/A3/A4 impls** — the publish joins `places`/`place_categories`/`place_scores`, all merged plan-only (none in code). Real extracts are `wp-acquire-impl`.
- **BLOCKED-ON the `pmtiles` CLI + a Protomaps source** for the real basemap cut; the cut-planning + budget logic is testable now.
- **BLOCKED-ON Rob's R2 token** — an S3-compatible token scoped to EXACTLY `mt-tiles` (public) + `mt-state` (private), read+write, stored in 1Password (`R2_ACCOUNT_ID`/`R2_ACCESS_KEY_ID`/`R2_SECRET_ACCESS_KEY`) + `.env.tpl`. One `op run` per publish run (`docs/SECRETS.md`).
- **A0 append-only change** — `manifest.schema.json` + `caps.py` gain the `attribution` field + caps (coordinated, like A2/A3/A4 extended the working store; unshipped schema so additive-safe).
- **Registry write coupling (A2):** A7 writes the registry `last_seen_version` on successful publish only (§6) — to the PRIVATE bucket. A2 owns the registry shape; A7 is a writer of one field on publish success.
- **Two-bucket layout is a security invariant** — the registry/cache never enter the public bucket; a test enforces it.

**Adversarial review (per AGENTS.md gate) — TO RUN before PR:** (1) fixes on the **executed path**; (2) **teeth** — uncategorized is excluded + counted (not silent) and no `"uncategorized"` place ships; a superseded id in a tile raises (neuter `tile_winner_violations` → a tombstoned id ships → red); tiles are byte-identical on re-emit (consumes A0 `gzip_tile`); the manifest is the LAST content op and `current` flips only after it (no partial publish, §6); the registry never targets the public bucket; the HE OGL string ships verbatim; a cut over the pack budget raises; (3) **the coherence critic RUNS the local staging chain on fixtures** (partition → emit_tiles → assemble_manifest → build_staging) against a real `mt_contracts` venv and confirms determinism (byte-identical re-publish), the winners-only + uncategorized gates, schema validity, and the manifest-last/atomic ordering; (4) confirm the **BLOCKED-ON honesty** — real tiles on A2/A3/A4 impls, the basemap on `pmtiles`+Protomaps, the upload on Rob's scoped R2 token — no executed-path over-claim (the A2–A6 lesson), and that A0's tile primitives are CONSUMED, not re-implemented.
