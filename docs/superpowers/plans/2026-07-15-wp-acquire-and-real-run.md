# WP Acquire + Real Run Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the deferred source-acquisition layer and prove it by running real Malaysia and UK extraction.

**Architecture:** Add a `mt_pipeline.acquire` module that writes deterministic local snapshots under an ignored data directory. The CLI gets an `acquire` command and an extract path that can consume those snapshots. Network code remains behind injected fetch functions and the existing hardened `fetch` boundary.

**Tech Stack:** Python 3.11+, `urllib`, existing `fetch.get_json` / `fetch.get_to_file`, `ijson`, `osmium`, SQLite.

## Global Constraints

- Never break the `place_id` or source-ref contracts.
- All network source data is untrusted: validate shape, sizes, hosts, hashes, and sidecars.
- Determinism: snapshots are the boundary; extraction from snapshots must not use wall-clock or randomness.
- Tests must not hit the network; acquisition tests use injected fetchers/downloaders.
- Real-run data files are not committed; only small stats/sample JSON outputs may be committed.

---

### Task 1: Acquisition Config And Ignore Rules

**Files:**
- Create: `.gitignore`
- Create: `pipeline/config/acquire_sources.json`

**Interfaces:**
- Produces source URLs and caps consumed by `mt_pipeline.acquire`.

- [ ] Add ignored runtime directories: `.mt-data/`, `pipeline/.mt-data/`, `run-audit/`.
- [ ] Add `acquire_sources.json` with WDQS endpoint, Wikipedia API endpoint, and Geofabrik PBF URLs/hosts for Malaysia and UK.

### Task 2: Wiki Acquisition

**Files:**
- Create: `pipeline/src/mt_pipeline/acquire.py`
- Create: `pipeline/tests/test_acquire_wiki.py`

**Interfaces:**
- `acquire_wikidata(region_config, allowlist_path, dest, *, fetch_json, retrieved_at, user_agent, class_chunk_size=..., tile_degrees=...) -> pathlib.Path`
- `acquire_wikipedia(region_config, dest, *, fetch_json, retrieved_at, user_agent) -> pathlib.Path`

- [ ] Write tests for P31-chunk x bbox-tile segmentation and strict `_meta.complete`.
- [ ] Write tests for WDQS retry/backoff on 429/5xx using injected fetcher/sleeper.
- [ ] Write tests for Wikipedia geosearch pages with complete meta and language.
- [ ] Implement minimal acquisition code to pass tests.

### Task 3: OSM Acquisition

**Files:**
- Modify: `pipeline/src/mt_pipeline/acquire.py`
- Create: `pipeline/tests/test_acquire_osm.py`

**Interfaces:**
- `acquire_osm(region_config, dest_dir, *, download_file, fetch_text, retrieved_at) -> pathlib.Path`

- [ ] Write tests for Geofabrik `.md5` mismatch loud abort.
- [ ] Write tests for `.pbf.meta.json` sha256 sidecar on successful download.
- [ ] Implement Geofabrik download + MD5 verification + sidecar.

### Task 4: CLI Wiring

**Files:**
- Modify: `pipeline/src/mt_pipeline/cli.py`
- Modify: `pipeline/src/mt_pipeline/stages.py` if needed.
- Test: `pipeline/tests/test_cli.py`

**Interfaces:**
- `mt-pipeline --region <id> acquire --data-dir <dir>`
- `mt-pipeline --region <id> extract --db <db> --snapshot-dir <dir> [--osm-index-type <idx>]`

- [ ] Write tests for acquire command invoking acquisition with injected seams where possible.
- [ ] Write tests that extract with snapshots calls `run_extract` and prints counts.
- [ ] Keep legacy no-snapshot skeleton behavior for existing tests.

### Task 5: Verification And Real Run

**Files:**
- Create: `run-audit/<region>-extract-stats.json`

- [ ] Run pipeline and contracts tests.
- [ ] Acquire and extract Malaysia first; record commands, counts, wall time, dropped/log notes, and 5 spot-check records.
- [ ] Acquire and extract UK second with disk-backed OSM index; record the same stats.
- [ ] Commit only code/tests/config, `.gitignore`, plan, and small audit JSON.
