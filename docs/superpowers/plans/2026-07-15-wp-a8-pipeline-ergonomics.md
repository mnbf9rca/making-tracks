# WP-A8 (Pipeline Ergonomics) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the pipeline fast and re-runnable **without ever sacrificing determinism**: run the five extractors as **concurrent processes** merged in fixed source order (byte-identical output regardless of completion order), a **`--only-source`** transactional re-extract, a **stage short-circuit** that skips a stage whose inputs are unchanged (a fingerprint memoization — the cache-invalidation trap designed hardest), and a **pinned telemetry format** monitors can rely on. The §5.2 stage-ORDER gate and the per-source success metadata A2 consumes stay exactly as they are.

**Architecture:** A new `mt_pipeline.ergonomics` package plus a re-shaped `run_extract`. Parallelism is **process-per-source into an isolated staging SQLite** (no concurrent writers to the working store), followed by a **deterministic merge** in the registry's fixed source order — so the working store's single-writer invariant is preserved *by construction* and the output is a pure function of the inputs, not of scheduling. Stage short-circuiting stores an **input fingerprint** per `(region, stage)`; an identical fingerprint → a loud SKIP (`--force` overrides). The reconcile-invalidated-by-any-extract-change invariant is **enforced** (reconcile fingerprints the `source_records` content-hash), not documented. Telemetry is a pinned, greppable line format.

**Tech Stack:** Python 3.11+ (`mt_pipeline`, on `wp-acquire-impl`'s extract surface), stdlib `multiprocessing` (spawn) + `sqlite3` (per-source staging DBs), `hashlib` (fingerprints), `pytest`. No new deps.

## Global Constraints

- **Determinism is the whole point (Principle 12) — but `id` is NOT part of the contract (hostile H5 / spec-fidelity / coherence M2, execution-proven).** A **full** extract run's merged `source_records` is byte-identical *regardless of completion order* (the mandatory completion-order-shuffle test) — achieved by merging into a **freshly recreated** table in fixed source order (so surrogate `id`s restart deterministically per run). But `source_records.id` is a rowid alias, and a `--only-source` re-extract does `DELETE`+`INSERT` into a populated table → freed rowids are not reused → the re-extracted store is content-equal but **id-different** from a clean full run (verified: osm ids `3,4 → 6,7`). So: **`id` carries no meaning and is excluded from every fingerprint and from the byte-identical claim; nothing downstream may key on it — the stable identity is the `(source, source_ref)` UNIQUE tuple.** The determinism guarantee is over CONTENT (the `(source,source_ref,name,lat,lon,props_json)` tuple), completion-order-invariant; it is NOT an id-stability claim across `--only-source`. Fingerprints are content hashes, never timestamps, never ids.
- **Single-writer WITHIN a run by construction; ACROSS runs by a lock (hostile H7).** Extractors never write the working store concurrently: each writes its OWN ephemeral staging SQLite (`staging/{run_id}/{source}.db`), and a SINGLE **merge** is the only writer of `source_records`. But two CLI *invocations* (`mt extract uk` + `mt extract uk --only-source osm`) are two OS processes both merging → a working-store **exclusive lock** (a flock lockfile `mt-extract-{region}.lock`, or a `BEGIN EXCLUSIVE` spanning the whole merge) serialises them; a second invocation blocks or aborts loudly. The "no cross-process lock" is false across invocations.
- **The full merge is ONE transaction — merge + `source_status_json` + the stage fingerprint/completion commit TOGETHER (hostile H8/M6/M8).** A per-source-atomic merge still leaves a *whole-run* hole: a crash between source 2 and source 3 mixes two runs' `source_records`. So the entire multi-source merge, the metadata write, AND the completion+fingerprint row are ONE `BEGIN…COMMIT` — a partial store is NEVER marked complete, and reconcile refuses it. **But the acquire-branch helpers `record_extract_run_metadata` and `mark_stage_complete` each `conn.commit()` INTERNALLY (fable review D3) — reusing them as-is would be THREE transactions, not one.** So A8 must refactor them to **no-commit variants** (take the open transaction / a `commit=False` param) and issue the single `COMMIT` at the end — otherwise the one-transaction atomicity claim is false. A test drives a crash between the metadata write and the completion write and asserts the store is NOT left marked-complete.
- **Failure semantics are FAIL-FAST by default — UNCHANGED from the ratified sequential contract (spec-fidelity HIGH-2 / coherence M3).** The acquire-branch `run_extract` raises on any source failure (records the `failure` status, then `raise`), aborting the run — the §6 "source down → run aborts" contract A2 relies on. A8's parallel path **preserves this**: all sources extract into staging in parallel, per-source statuses are recorded truthfully, and if ANY required source failed, the merge does NOT run and the stage raises (no partial store). So **`parallel==sequential` holds** (identical on all-success; both fail-fast on failure). Isolate-and-continue (merge healthy sources, skip the failed one) is a DISTINCT behaviour behind an explicit `--continue-on-source-failure` flag (dev/diagnostic only) — NOT the default. **Ratified condition (fable, thread `wp/a8`): even in continue mode, a failed source is recorded in `source_status_json` as `{status:"failure", error}` — NEVER merely ABSENT.** A2's three-case tombstone logic + the staleness clock distinguish *failed* (don't tombstone — the source was down) from *succeeded-but-empty* (do tombstone — the place genuinely vanished); a continued run that dropped a failed source to "absent" would corrupt that decision. So continue mode changes only whether the RUN aborts, never the truthfulness of the per-source metadata. My original "isolate by default" was a silent contract change; this reverts it.
- **Per-source ALL-OR-NOTHING; `source_status_json` stays TRUTHFUL even for a CRASHED worker (fable's rule + hostile H6).** A source either fully populates its staging DB (→ eligible to merge) or fails (→ not merged). **A worker that segfaults / is OOM-killed is NOT a Python exception** — so status is inferred from `process.exitcode` after `join()` (nonzero/`None` → `failure`) AND an explicit success sentinel the child writes into its staging DB; **never** from "no exception in the parent." Otherwise a killed worker records `success, count=0` and A2's tombstone gate mass-deletes that source's places. `record_extract_run_metadata(source_statuses=…)` gets `{status:"success", count}` / `{status:"failure", error}` — A2 reads real state.
- **The §5.2 stage-ORDER gate is UNCHANGED.** `stages.run_stage`'s predecessor-completed check stays exactly as it is (extract→reconcile→score→categorize→publish). A8 adds a fingerprint SKIP *inside* a stage's execution, never a reordering or a bypass of the order gate.
- **Acquisition is UNTOUCHED.** The acquire side (snapshot download) already has its ratified concurrency policy (bounded `ThreadPoolExecutor` at the network boundary, WDQS sequential). A8 parallelises only the **extract STAGE** (parsing already-downloaded snapshots into `source_records`) — CPU/IO-bound local work, no network etiquette to honour.
- **`--force` is the only override; a SKIP is LOUD.** A short-circuit SKIP prints a pinned telemetry line naming the stage + the matched fingerprint; it is never silent. `--force` recomputes and re-runs regardless. A stale-serve (running with an unchanged fingerprint when an input actually changed) is **the most confidence-inspiring way to lie** — every fingerprint component gets a neuter-goes-red test.
- **WORKING_STORE_VERSION coordination — integer assigned AT LAND, not pre-claimed (spec-fidelity MED).** A8 adds a `stage_fingerprints` table (a schema addition → a bump). Acquire is v3; A2-impl (places), A3 (place_categories), A4 (place_scores), and A8 all bump the SAME `WORKING_STORE_VERSION` constant and the same linear `elif` migration chain — so **A8 must NOT hardcode an integer** (every WP pre-claiming "v4" is a guaranteed merge collision). Instead: the migration ladder is single-owner (A2-impl owns it); A8's migration step is **appended at integration time** and its integer is whatever the tip is then. The plan pins the *step* (`CREATE TABLE stage_fingerprints`), not the number. Staging DBs are EPHEMERAL (not the working-store schema) → no version implication.
- **BLOCKED-ON `wp-acquire-impl`'s extract surface.** A8 re-shapes `run_extract`/`extract_run_metadata` which live on `wp-acquire-impl` (WORKING_STORE_VERSION=3, `extract_run_metadata.source_status_json`, `run_extract(..., status_recorder=…)`), not yet merged to develop. Design targets that branch tip; the real parallel run + `--only-source` + short-circuit on real snapshots are BLOCKED-ON the acquire PR landing + real extracts. The merge logic, fingerprinting, and telemetry format are fixture-testable NOW.

**Assignment (fable, thread `wp/a8`)** — the four ratified pieces designed properly: (1) parallel extractors, per-source staging, deterministic fixed-order merge, single-writer, per-source all-or-nothing with truthful metadata; (2) `--only-source` transactional delete-and-replace, reconcile-invalidated-by-any-extract-change ENFORCED; (3) stage short-circuit via a per-stage input fingerprint (exact components pinned), `--force` override, neuter-goes-red per component; (4) pinned telemetry (PROGRESS format, phase START/DONE, heartbeats, log-path). Determinism throughout; stage-order gate unchanged; acquisition untouched.

---

## File Structure

```
pipeline/src/mt_pipeline/ergonomics/
  __init__.py
  staging.py       # per-source staging DB: open_staging(run_id, source) -> conn; the source_records schema (shared)
  merge.py         # merge_sources(main_conn, staged: dict[source, staging_path], order) -> source_statuses (deterministic)
  parallel.py      # run_extract_parallel(...) -> spawn process per source into staging, then merge (drop-in for run_extract)
  fingerprint.py   # stage_fingerprint(conn, region, stage, *, config_paths, code_marker) -> str; should_skip(...)
  selective.py     # reextract_one_source(conn, region_config, source, snapshot, run_id, registry) -> status
  telemetry.py     # progress(), phase_start()/phase_done(), heartbeat(), log_path reporting — PINNED format
pipeline/src/mt_pipeline/
  extract_stage.py # run_extract gains a `parallel=True` path (delegates to ergonomics.parallel) — same signature/contract
  stages.py        # run_stage gains fingerprint short-circuit (SKIP unless changed / --force) — order gate unchanged
  store.py         # + stage_fingerprints table (coordinated WORKING_STORE_VERSION bump on the A2 ladder)
  cli.py           # + --only-source, --force, --parallel/--sequential, --fail-fast
pipeline/tests/
  test_ergonomics_merge.py       # the completion-order-shuffle determinism test (MANDATORY)
  test_ergonomics_fingerprint.py # neuter-goes-red per fingerprint component + reconcile-invalidation
  test_ergonomics_selective.py   # --only-source transactional delete-replace + reconcile invalidated
  test_ergonomics_telemetry.py   # the pinned format
docs/superpowers/reports/
  2026-07-15-a8-ergonomics.md    # real parallel UK run + timings + a short-circuit skip (BLOCKED-ON acquire impl)
```

---

### Task 1: Per-source staging + deterministic fixed-order merge (the determinism core)

**Files:** Create `pipeline/src/mt_pipeline/ergonomics/{__init__.py,staging.py,merge.py}`; Test `pipeline/tests/test_ergonomics_merge.py`

**Interfaces:**
- Consumes: `store`'s `source_records` schema (the acquire-branch shape).
- Produces:
  - `staging.open_staging(root, run_id, source) -> sqlite3.Connection` — an ephemeral per-source DB with the `source_records` schema; **creates FRESH** (truncates/refuses any pre-existing file so a reused `run_id` or a crashed prior run can't leak stale rows — hostile M4); the run `rm -rf`s `staging/{run_id}/` on entry and in a **`finally` — cleaned up on BOTH the success AND the fail-fast failure path** (fable review D6 — a failed run must not leak its staging dir).
  - `staging.STAGING_ORDER` — the FIXED source order (the registry's registration order: `wikidata, wikipedia, osm, historic_england, open_plaques`) used for the merge — deterministic, independent of completion.
  - `merge.merge_sources(main_conn, staged: dict[str, str], succeeded: set[str], *, order=STAGING_ORDER, full: bool) -> None` — in ONE transaction (the whole-run atomicity guarantee): for a **`full` run, DROP+recreate `source_records`** then INSERT every succeeded source in `order`, each sorted by `source_ref` → **surrogate ids restart deterministically per run** (a fresh table, not `max(rowid)+1` — hostile H5); for a **`--only-source`** merge (`full=False`), `DELETE FROM source_records WHERE source=?` then re-INSERT just that source (ids for THAT source churn — documented, and `id` is not in the contract). Sources absent from `succeeded` are NOT merged. Fixed order + within-source sort ⇒ a full run is **byte-identical regardless of completion order**.

- [ ] **Step 1: Write the failing test — the MANDATORY completion-order-shuffle**

```python
import sqlite3, itertools
from mt_pipeline.ergonomics import merge as M, staging as S

def _stage(root, run_id, source, rows):
    conn = S.open_staging(root, run_id, source)
    for ref, name in rows:
        conn.execute("INSERT INTO source_records(source,source_ref,region,name,lat,lon,props_json,run_id) "
                     "VALUES(?,?,?,?,?,?,?,?)", (source, ref, "uk", name, 0.0, 0.0, "{}", run_id))
    conn.commit(); return S.staging_path(root, run_id, source)

def _merged_dump(order, staged, succeeded):
    main = sqlite3.connect(":memory:"); _init_source_records(main)
    M.merge_sources(main, {s: staged[s] for s in order}, succeeded, order=M.STAGING_ORDER)
    return main.execute("SELECT id,source,source_ref,name FROM source_records ORDER BY id").fetchall()

def test_merge_is_byte_identical_across_completion_orders(tmp_path):
    staged = {"wikidata": _stage(tmp_path,"r","wikidata",[("wd:Q2","B"),("wd:Q1","A")]),
              "osm":      _stage(tmp_path,"r","osm",[("osm:node/9","W")])}
    succeeded = {"wikidata","osm"}
    baseline = _merged_dump(["wikidata","osm"], staged, succeeded)
    # every completion order (the shuffle) must merge to the IDENTICAL table, ids included:
    for perm in itertools.permutations(staged):
        assert _merged_dump(list(perm), staged, succeeded) == baseline

def test_a_failed_source_is_not_merged(tmp_path):
    staged = {"wikidata": _stage(tmp_path,"r","wikidata",[("wd:Q1","A")]),
              "osm":      _stage(tmp_path,"r","osm",[("osm:node/9","W")])}
    dump = _merged_dump(["wikidata","osm"], staged, succeeded={"wikidata"})   # osm failed
    assert all(r[1] == "wikidata" for r in dump)                             # no osm rows merged
```

- [ ] **Step 2: Run to verify it fails** — `uv run pytest pipeline/tests/test_ergonomics_merge.py -v` → FAIL (module not found).
- [ ] **Step 3: Implement** `open_staging` (schema shared with `store`), `merge_sources` (fixed order, per-source transaction, within-source `ORDER BY source_ref`).
- [ ] **Step 4: Run to verify it passes.** **Teeth:** the shuffle test reds if the merge order depends on completion (e.g. merging in dict/iteration order) — the surrogate ids would differ across permutations; the failed-source test reds if a not-succeeded source leaks rows.
- [ ] **Step 5: Commit** — `"Add per-source staging + deterministic fixed-order merge (completion-order-shuffle proven)"`

---

### Task 2: Parallel process execution + per-source failure isolation

**Files:** Create `pipeline/src/mt_pipeline/ergonomics/parallel.py`; Modify `extract_stage.py` (`run_extract` gains a `parallel` path); Test extends `test_ergonomics_merge.py`

**Interfaces:**
- Consumes: `staging`, `merge`, the acquire-branch `registry.enabled_for`, `record_extract_run_metadata`.
- Produces:
  - `parallel.run_extract_parallel(conn, region_config, snapshots, *, run_id, registry, status_recorder=None, extractor_options=None, max_workers=None, continue_on_source_failure=False) -> dict[str,int]` — a **drop-in for `run_extract`** (SAME signature, incl. `extractor_options` — spec-fidelity MED, not dropped): spawn one process per enabled source (`multiprocessing`, **`spawn`** start method), passing each child only **picklable args** (region_config, the source's snapshot path, allowlist/tag-config paths, `extractor_options`) and **rebuilding the registry inside the child via `build_registry(...)`** rather than pickling extractor instances (hostile M7 / L4 — robust to a future non-picklable extractor). Each child runs `assert_disk_floor` then its extractor into `open_staging(...)` and writes a **success sentinel** on clean completion. Parent: `join(timeout=…)` per worker (a hung extractor is `terminate()`+`failure` — hostile M3); derive each status from `exitcode` + the sentinel (a crashed worker → `failure`, never `success/0` — hostile H6); check the disk floor for **N concurrent stagings** before spawning (hostile M5). Then, in ONE transaction, `merge.merge_sources(full=True)` the succeeded set + record `source_statuses` + commit the fingerprint/completion. **FAIL-FAST by default**: if any required source failed, record statuses and `raise` WITHOUT merging (matching sequential + §6); `continue_on_source_failure=True` opts into isolate-and-merge-healthy (flagged for re-ratification).
  - `extract_stage.run_extract(..., parallel: bool = True, continue_on_source_failure: bool = False)` — `parallel=True` delegates to `run_extract_parallel`; `parallel=False` keeps the sequential path (the differential oracle). **On an all-SUCCESS run both paths produce the identical working store** (a test asserts sequential == parallel on all-success; on a failure both fail-fast, so the store is identically absent — the equivalence is scoped to the success path, coherence M3).

- [ ] **Step 1: Write the failing tests**

```python
from mt_pipeline import extract_stage as X

def test_parallel_equals_sequential_on_all_success(tmp_path, uk_config, fixture_snapshots, registry):
    seq = _run_and_dump(X, uk_config, fixture_snapshots, registry, parallel=False)
    par = _run_and_dump(X, uk_config, fixture_snapshots, registry, parallel=True)
    assert seq == par                                             # identical store on an all-success run

def test_fail_fast_is_the_default_and_matches_sequential(uk_config, registry):
    snaps = {**fixture_snapshots, "osm": None}                    # osm snapshot missing -> that source fails
    statuses = {}
    import pytest
    with pytest.raises(Exception):                               # parallel fail-fast, like sequential (§6)
        X.run_extract(main_conn, uk_config, snaps, run_id="r", registry=registry, parallel=True,
                      status_recorder=lambda s, st: statuses.__setitem__(s, st))
    assert statuses["osm"]["status"] == "failure"                # status recorded truthfully BEFORE the raise
    assert main_conn.execute("SELECT COUNT(*) FROM source_records").fetchone()[0] == 0   # NO partial merge

def test_a_killed_worker_records_failure_not_success_zero(uk_config, registry):
    # a segfault/OOM-kill is not a Python exception; the parent must infer failure from exitcode+sentinel
    statuses = {}
    with pytest.raises(Exception):
        X.run_extract(main_conn, uk_config, fixture_snapshots, run_id="r", registry=_registry_that_SIGKILLs("osm"),
                      parallel=True, status_recorder=lambda s, st: statuses.__setitem__(s, st))
    assert statuses["osm"]["status"] == "failure"                # NOT success/count=0 (which would mass-tombstone in A2)

def test_continue_mode_still_records_a_failed_source_as_FAILURE_not_absent(uk_config, registry):
    # ratified condition: --continue-on-source-failure merges the healthy sources BUT the failed source
    # must appear as {status:"failure"} in source_status_json, never merely omitted (A2 needs failed != absent).
    snaps = {**fixture_snapshots, "osm": None}
    statuses = {}
    X.run_extract(main_conn, uk_config, snaps, run_id="r", registry=registry, parallel=True,
                  continue_on_source_failure=True, status_recorder=lambda s, st: statuses.__setitem__(s, st))
    assert statuses["osm"]["status"] == "failure"                # recorded FAILED, not dropped
    assert "osm" in statuses and statuses["wikidata"]["status"] == "success"   # healthy source merged; failed one present
```

- [ ] **Step 2–4:** implement `run_extract_parallel` (spawn-per-source, rebuild-registry-in-child, `assert_disk_floor`, `join(timeout)`, exitcode+sentinel status, one-transaction merge, fail-fast default). **Teeth:** the equivalence test reds if parallel diverges from sequential on all-success; the fail-fast test reds if a failure produces a partial merge or doesn't raise; the killed-worker test reds if a `SIGKILL`ed child is recorded `success` (the A2 mass-tombstone vector). Use `spawn` (not `fork`).
- [ ] **Step 5: Commit** — `"Add parallel process-per-source extract (staging+merge; per-source failure isolation; parallel==sequential)"`

---

### Task 3: Stage short-circuit — the input fingerprint (the cache-invalidation trap, designed hardest)

**Files:** Create `pipeline/src/mt_pipeline/ergonomics/fingerprint.py`; Modify `stages.py` (`run_stage` short-circuit), `store.py` (`stage_fingerprints` table); Test `pipeline/tests/test_ergonomics_fingerprint.py`

**Interfaces:**
- Consumes: `store` (the working store + the new table), the config files, the stage inputs.
- Produces:
  - `store.stage_fingerprints` table `(region, stage, fingerprint, completed_at, PRIMARY KEY(region,stage))` (WORKING_STORE_VERSION bump, integer assigned at land).
  - `fingerprint.content_hash(conn, region, table, cols) -> str` — sha256 over the rows of `table` for `region`, **`ORDER BY region, source, source_ref` (or the table's natural key) — an EXPLICIT order, never sqlite's physical order** (hostile H3 — an unordered SELECT hashes non-deterministically), with **floats quantized (`round(lat/lon, 7)`) and any JSON column canonicalized (`json.dumps(parsed, sort_keys, fixed separators)`)** so semantically-equal data hashes equal and equal-hash implies equal-meaning (hostile M2). `cols` is the EXACT column set the consuming stage reads.
  - `fingerprint.STAGE_INPUTS` — the PINNED, EXACT input set per stage (fable's list, corrected):
    - **`extract`**: `sha256(each snapshot file CONTENT)` + `sha256(wikidata_class_allowlist.json)` + `sha256(osm_candidate_tags.json)` + **the region's ENABLED-`sources` set** (hostile H2) + **the region's `languages` set** (fable review D1 — `WikipediaExtractor` filters on `if lang not in self.languages`, editable with unchanged snapshots; the identical argument as enabled-sources) + `MODULE_MARKER["extract"]`.
    - **`reconcile`**: `content_hash(source_records, cols=(source, source_ref, name, lat, lon, props_json))` — **the FULL logical row reconcile clusters on** (the crown fix — execution-proven; `id`/`run_id` excluded) + **`succeeded_sources`** (fable review D2 — derived NOW from `source_status_json`; a *failed* osm and a *succeeded-but-empty* osm content-hash IDENTICALLY yet must reconcile differently via the three-case tombstone logic, so the succeeded set is a load-bearing reconcile input, NOT blocked) + `[BLOCKED-ON A2 impl:` the **existing-registry content-hash** + the **`--version`/run param** (A2's own determinism inputs — reconcile mints against the prior registry; named as seams now) + `sha256(redirect_map)` + `sha256(thresholds)]` + `MODULE_MARKER["reconcile"]`.
    - **`score`** `[BLOCKED-ON A3/A4 impl]`: `content_hash(places, cols=score-reads)` + `sha256(scoring.json)` + `sha256(pageview_cache)` + `MODULE_MARKER["score"]`.
    - **`categorize`** `[BLOCKED-ON A3 impl]`: `content_hash(places, cols=categorize-reads)` + `sha256(taxonomy.json)` + `MODULE_MARKER["categorize"]`.
  - `fingerprint.MODULE_MARKER[stage]` — **AUTO-DERIVED: `sha256(the stage module's own source bytes)`, NOT a hand-typed constant** (hostile H4 — a hand-bumped marker forgotten after a logic change = a permanent silent stale-serve; a source-hash invalidates automatically, and a false positive from a comment edit is safe while a false negative is catastrophic). Immutable.
  - `fingerprint.stage_fingerprint(conn, region, stage, *, inputs) -> str` — ONE signature (spec-fidelity MED): sha256 over the sorted-canonical `STAGE_INPUTS[stage]`. `inputs` is a resolver carrying the run's snapshot paths + resolved config paths + the region config (threaded from `run_stage`, which gains them — the extract fingerprint needs per-run snapshot paths that `(conn,region,stage)` alone can't supply).
  - `fingerprint.should_skip(...)` → LOUD SKIP or run; **the fingerprint is written in the SAME transaction that commits the stage's output** (hostile M6). `--force` overrides.
  - `fingerprint.STAGE_READS[stage]` + **the META-TEST (fable review — the systemic fix that turns this class from review-catchable to CI-catchable).** `STAGE_READS` declares every input a stage CONSUMES (its extractor-constructor args, the config files it loads, the region-config fields it reads, the DB columns it queries); a meta-test asserts **`STAGE_READS[stage] ⊆ (the components STAGE_INPUTS[stage] fingerprints)`** — a stage that reads something absent from its fingerprint FAILS CI (a stale-serve vector). To keep `STAGE_READS` itself honest, it is cross-checked by INTROSPECTION where possible (e.g. the extract stage's `build_registry` constructor arguments — `languages`, the allowlist path, the tag-config path — are enumerated from the signatures, so adding a new constructor arg without fingerprinting it reds the meta-test). **This is the completion criterion: fixing one gap is not completing a fingerprint — the exhaustive reads-vs-fp diff, as a test, is** (the crown lesson + D1/D2 would ALL have been caught by it).

- [ ] **Step 1: Write the failing tests — neuter-goes-red on EVERY component**

```python
from mt_pipeline.ergonomics import fingerprint as F

def test_reconcile_fp_moves_on_EVERY_reconcile_column(populated_conn, inputs):   # the crown fix — per-column
    base = F.stage_fingerprint(populated_conn, "uk", "reconcile", inputs=inputs)
    for col, val in [("lat", 99.9), ("lon", 88.8), ("name", "'RENAMED'"), ("props_json", "'{\"x\":1}'")]:
        populated_conn.execute(f"UPDATE source_records SET {col}={val!r if col!='name' and col!='props_json' else val} WHERE id=1")
        populated_conn.commit()
        assert F.stage_fingerprint(populated_conn, "uk", "reconcile", inputs=inputs) != base   # lat/lon/name/props ALL move it
        populated_conn.rollback_fixture()   # restore
    # coherence-proven gap: hashing only (source,source_ref,props_json) leaves lat/lon/name UNGUARDED -> stale-serve

def test_content_hash_is_order_and_whitespace_stable(populated_conn, inputs):
    a = F.stage_fingerprint(populated_conn, "uk", "reconcile", inputs=inputs)
    populated_conn.execute("VACUUM")                                          # physical reorder, same content
    populated_conn.execute("UPDATE source_records SET props_json='{ \"x\" : 1 }' WHERE id=1")  # whitespace-only
    # (props canonicalized + ORDER BY pinned) -> hash unchanged by physical order / JSON whitespace
    ... # assert equal after restoring the canonical value

def test_enabled_sources_and_module_marker_each_invalidate(populated_conn, inputs, uk_config):
    base = F.stage_fingerprint(populated_conn, "uk", "extract", inputs=inputs)
    uk_config.disable("osm")                                                  # toggle a source off (files unchanged)
    assert F.stage_fingerprint(populated_conn, "uk", "extract", inputs=inputs) != base   # H2: enabled-set is a component
    # MODULE_MARKER is sha256(module source): a logic edit auto-invalidates (no hand-bump), tested by a golden source-hash

def test_identical_inputs_skip_unless_forced(populated_conn, inputs):
    fp = F.stage_fingerprint(populated_conn, "uk", "extract", inputs=inputs)
    F.record(populated_conn, "uk", "extract", fp)
    assert F.should_skip(populated_conn, "uk", "extract", fp, force=False) is True
    assert F.should_skip(populated_conn, "uk", "extract", fp, force=True) is False    # --force overrides

def test_META_every_input_a_stage_reads_is_fingerprinted():   # the reads-vs-fp diff as CI (fable) — catches the whole class
    for stage, reads in F.STAGE_READS.items():
        missing = reads - F.fingerprint_covers(stage)   # inputs the stage consumes but doesn't hash
        assert missing == set(), f"{stage} READS {missing} but does NOT fingerprint them -> stale-serve vector"
    # and STAGE_READS is tied to code: the extract build path's constructor args are introspected, so a NEW
    # extractor arg that isn't added to STAGE_READS+STAGE_INPUTS reds here — the class is now CI-catchable, not review-catchable.
```

- [ ] **Step 2–4 (SPLIT — spec-fidelity MED, the executable-now honesty):** implement + test the `extract` fingerprint (snapshots+allowlist+tag-config+enabled-sources+marker) and the `source_records` component of `reconcile` **NOW**; **mark `reconcile`'s `redirect_map`/`thresholds` (BLOCKED-ON A2 impl) and the entire `score`/`categorize` fingerprints (BLOCKED-ON A3/A4 — `scoring.json`/`taxonomy.json`/`places`/`place_scores`/`place_categories` don't exist on the acquire tip)** as the `STAGE_INPUTS` seam, wired when they land. Wire the fingerprint into `run_stage` (compute → skip-or-run → store fp IN the output transaction; the §5.2 order gate stays). **Teeth (host-verified): EVERY component of `STAGE_INPUTS` has a neuter-goes-red test** — `lat`/`lon`/`name`/`props_json` each move reconcile's fp (the crown, proven); the enabled-sources toggle moves extract's fp; the module-source-hash marker moves on a logic edit; identical inputs skip; a component you can delete without turning a test red is a stale-serve vector.
- [ ] **Step 5: Commit** — `"Add stage short-circuit: full-row content-hash (per-column neuter) + enabled-sources + auto-marker; extract+source_records now, score/categorize BLOCKED-ON A3/A4"`

---

### Task 4: `--only-source` selective re-extract (transactional; reconcile-invalidation automatic)

**Files:** Create `pipeline/src/mt_pipeline/ergonomics/selective.py`; Modify `cli.py`; Test `pipeline/tests/test_ergonomics_selective.py`

**Interfaces:**
- Consumes: `staging`/`merge`, `fingerprint`, the registry, `record_extract_run_metadata`.
- Produces:
  - `selective.reextract_one_source(conn, region_config, source, snapshot, *, run_id, registry) -> dict` — under the **working-store lock** (H7), re-extract ONLY `source` from its cached `snapshot`: extract into staging, then `merge_sources(conn, {source: staging}, {source}, full=False)` — the per-source transaction is `DELETE FROM source_records WHERE source=?` then re-insert (a **transactional delete-and-replace of just that source's rows**; other sources untouched). Update that source's `source_statuses` entry, and re-record the fingerprint in the same transaction. Returns the new status/count. **That source's surrogate ids churn** (documented — `id` is not in the contract; the stable key is `(source, source_ref)`).
  - **The reconcile-invalidation is AUTOMATIC, not a separate step (fable: "enforce, don't document"):** because `reconcile`'s fingerprint includes the `source_records` content-hash (Task 3), replacing one source's rows changes that hash → reconcile's fingerprint no longer matches → the next `reconcile` run does NOT skip. `--only-source` does not need to (and must not) manually clear reconcile's completion; the fingerprint mechanism enforces it.

- [ ] **Step 1: Write the failing tests**

```python
from mt_pipeline.ergonomics import selective as SEL, fingerprint as F

def test_only_source_replaces_just_that_source(populated_conn, uk_config, registry, osm_snapshot):
    before_wd = populated_conn.execute("SELECT COUNT(*) FROM source_records WHERE source='wikidata'").fetchone()[0]
    SEL.reextract_one_source(populated_conn, uk_config, "osm", osm_snapshot, run_id="r2", registry=registry)
    after_wd = populated_conn.execute("SELECT COUNT(*) FROM source_records WHERE source='wikidata'").fetchone()[0]
    assert after_wd == before_wd                                 # other sources untouched (transactional, scoped)

def test_only_source_invalidates_reconcile_when_content_ACTUALLY_changed(populated_conn, uk_config, registry, changed_osm_snapshot):
    # the fixture snapshot MUST genuinely differ (a moved coord) — else this test is vacuous (fable review D5)
    fp_before = F.stage_fingerprint(populated_conn, "uk", "reconcile", inputs=inputs)
    SEL.reextract_one_source(populated_conn, uk_config, "osm", changed_osm_snapshot, run_id="r2", registry=registry)
    assert F.stage_fingerprint(populated_conn, "uk", "reconcile", inputs=inputs) != fp_before   # content changed -> re-run

def test_identical_reextract_does_NOT_invalidate_reconcile(populated_conn, uk_config, registry, same_osm_snapshot):
    # the complementary no-op (D5): a re-extract with IDENTICAL content must NOT move the fp,
    # even though osm's surrogate ids churn (id is out of the contract) — else the cache is useless.
    fp_before = F.stage_fingerprint(populated_conn, "uk", "reconcile", inputs=inputs)
    SEL.reextract_one_source(populated_conn, uk_config, "osm", same_osm_snapshot, run_id="r2", registry=registry)
    assert F.stage_fingerprint(populated_conn, "uk", "reconcile", inputs=inputs) == fp_before   # id churn alone != invalidation
```

- [ ] **Step 2–4:** implement `reextract_one_source` (staging → scoped delete-replace merge → status update) + the `--only-source <name>` CLI flag. **Teeth:** the scoping test reds if the re-extract touches another source's rows (a non-transactional or unscoped delete); the invalidation test reds if a one-source re-extract leaves reconcile's fingerprint unchanged (which would let a stale reconcile skip — the exact bug the enforced invariant prevents).
- [ ] **Step 5: Commit** — `"Add --only-source transactional re-extract (scoped delete-replace; reconcile-invalidation enforced via fingerprint)"`

---

### Task 5: Telemetry — the pinned, greppable format

**Files:** Create `pipeline/src/mt_pipeline/ergonomics/telemetry.py`; Test `pipeline/tests/test_ergonomics_telemetry.py`

**Interfaces:**
- Produces (the FORMAT is the contract — monitors grep it, so it is PINNED and tested):
  - `telemetry.progress(stage, region, *, done, total, extra="") -> str` — emits `PROGRESS stage=<stage> region=<region> done=<n> total=<n> pct=<0-100> [<extra>]` to stderr. Greppable on `^PROGRESS `. **`pct = floor(100*done/total)` (truncation, pinned); `total=0 → pct=0`** (no div-by-zero — coherence L6/L1; a test pins a non-exact case `2/3 → 66` and `total=0`).
  - `telemetry.phase_start(stage, region)` / `phase_done(stage, region, *, counts, duration_s)` — `PHASE start stage=… region=…` and `PHASE done stage=… region=… duration_s=… <k=v counts>` (**`duration_s` is REQUIRED — AGENTS.md #60; fable review D4** — my elapsed-only-clock constraint had dropped it).
  - `telemetry.heartbeat(stage, region, *, done, elapsed_s)` — emitted every **10,000 items OR 30 seconds**, whichever comes first: `HEARTBEAT stage=… region=… done=… elapsed_s=… rate=…` (**`rate` = items/s is REQUIRED — AGENTS.md #60, D4**). `elapsed_s`/`rate`/`duration_s` are the only clock-derived fields, telemetry-only — **never fingerprinted**.
  - `telemetry.report_log_path(path)` — on a detached/background launch, prints `LOG path=<abs path>` so a monitor knows where to tail. (Satisfies AGENTS.md #60 "no silent long-running work"; A8 pins the exact tokens.)

- [ ] **Step 1: Write the failing tests** (assert the EXACT format — a monitor depends on it):

```python
from mt_pipeline.ergonomics import telemetry as T

def test_progress_line_format_is_pinned():
    line = T.progress("extract", "uk", done=250, total=1000)
    assert line == "PROGRESS stage=extract region=uk done=250 total=1000 pct=25"

def test_phase_and_heartbeat_tokens_are_stable():
    assert T.phase_done("reconcile", "uk", duration_s=12, counts={"places": 4200, "clusters": 4100}) == \
        "PHASE done stage=reconcile region=uk duration_s=12 places=4200 clusters=4100"   # D4: duration required
    assert T.heartbeat("extract", "uk", done=10000, elapsed_s=40) == \
        "HEARTBEAT stage=extract region=uk done=10000 elapsed_s=40 rate=250"             # D4: rate=items/s required

def test_pct_truncates_and_handles_zero_total():                                         # L1/L6
    assert T.progress("extract", "uk", done=2, total=3).endswith("pct=66")               # floor, not round
    assert T.progress("extract", "uk", done=0, total=0).endswith("pct=0")                # no div-by-zero
```

- [ ] **Step 2–4:** implement the emitters with the pinned tokens; the heartbeat fires on the 10k-items-or-30s rule. **Teeth:** the format tests red if any token/order changes (a monitor's grep would silently break — the format IS the contract). `elapsed_s` is telemetry-only.
- [ ] **Step 5: Commit** — `"Add pinned telemetry: PROGRESS/PHASE/HEARTBEAT/LOG format (greppable, monitor-stable)"`

---

### Task 6: CLI wiring + the real ergonomics run  `[real run BLOCKED-ON the acquire PR + real snapshots]`

**Files:** Modify `cli.py`; the report stub.

**Interfaces:** `mt <stage> <region> [--parallel/--sequential] [--force] [--fail-fast]` and `mt extract <region> --only-source <name>`. The short-circuit + telemetry are wired into every stage; parallel is the default for `extract`.

- [ ] **Step 1 (after the acquire PR lands + real snapshots on the VPS):** on the VPS (heavy-run policy), `mt extract uk` (parallel) → timings vs `--sequential`; re-run `mt extract uk` → the LOUD short-circuit SKIP; `mt extract uk --only-source osm` → osm re-extracted, then `mt reconcile uk` runs (NOT skipped — the fingerprint invalidation) while `score`/`categorize` still short-circuit if their inputs are unchanged. Commit `docs/superpowers/reports/2026-07-15-a8-ergonomics.md` (wall-clock before/after, the shuffle-determinism confirmation on real data, the skip/force behaviour).
- [ ] **Step 2: Commit** — `"Add mt CLI ergonomics flags + real parallel/only-source/short-circuit run (after acquire)"`

---

## Review Record

**Author self-review** — deliverables map to tasks: per-source staging + deterministic fixed-order merge (T1, the completion-order-shuffle core), parallel process-per-source with failure isolation (T2), the stage short-circuit fingerprint (T3, the cache-invalidation trap), `--only-source` with enforced reconcile-invalidation (T4), the pinned telemetry format (T5), the CLI + real run (T6). Determinism is preserved by construction (fixed-order merge, content-hash fingerprints, `spawn`); the §5.2 order gate and the `source_status_json` A2 contract are unchanged; acquisition is untouched.

**Ratifications (fable, thread `wp/a8`)** — the four pieces designed properly; determinism throughout; stage-order gate unchanged; acquisition untouched; BLOCKED-ON the acquire PR's extract surface.

**Cross-package needs surfaced:**
- **BLOCKED-ON `wp-acquire-impl`** — A8 re-shapes `run_extract`/`extract_run_metadata`/`registry` (WORKING_STORE_VERSION=3, `source_status_json`, `status_recorder`), not yet merged. Design targets the branch tip; the real parallel run + `--only-source` + short-circuit are BLOCKED-ON the acquire PR + real snapshots (heavy run on the VPS).
- **WORKING_STORE_VERSION bump on the A2-owned migration ladder** — the `stage_fingerprints` table stacks on acquire's v3; codex adds the migration (not forked). Staging DBs are ephemeral (no version implication).
- **A2 consumes the truthful `source_status_json`** — A8's per-source all-or-nothing keeps it truthful under parallelism (a failed source is `failure`, never optimistically `success`), so A2's `succeeded_sources` tombstone gate reads real state.
- **`score`/`categorize` fingerprint inputs (`scoring.json`, `taxonomy.json`, `place_scores`, `place_categories`) are BLOCKED-ON A3/A4 impls** — those config files + tables don't exist yet; the fingerprint framework is defined now and wired when they land (the `STAGE_INPUTS` map is the seam).
- **Telemetry format is a monitor contract** — pinned + tested so `/babysit`-style monitors and the AGENTS.md #60 "no silent long-running work" rule can rely on the exact tokens.

**fable independent review (thread `wp/a8`) — CHANGES REQUIRED, 6 fixed:** TWO MORE crown-class stale-serve gaps survived the first fix (found by diffing what-each-stage-READS vs what-it-fingerprints): **D1** — the extract fp omitted `languages` (filters `WikipediaExtractor` output) → added. **D2** — the reconcile fp omitted `succeeded_sources` (a *failed* vs *succeeded-but-empty* source content-hashes identically but must reconcile differently via the three-case tombstone logic — derivable NOW, host-verified) + the existing-registry hash + `--version` (A2 seams) → added. **D3** — the one-transaction atomicity claim was contradicted by `record_extract_run_metadata`/`mark_stage_complete` each `conn.commit()`-ing internally → refactor to no-commit variants joined in one COMMIT. **D4** — telemetry violated AGENTS.md #60 (PHASE-done lacked `duration_s`, HEARTBEAT lacked `rate`) → added, telemetry-only. **D5** — the `--only-source` invalidation test was vacuous unless the fixture genuinely differs → documented + a complementary no-op test (identical re-extract does NOT invalidate; id churn alone must not move the fp). **D6** — staging cleanup missing on the fail-fast failure path → `finally`. **And the systemic fix (fable's idea): a META-TEST asserting `STAGE_READS ⊆ fingerprinted-inputs` per stage** — the exhaustive reads-vs-fp diff as CI, cross-checked by introspecting the stage's build-path constructor args, so the WHOLE class (the crown + D1 + D2) becomes CI-catchable, not review-catchable. *The sharpened lesson: fixing a fingerprint gap is NOT completing the fingerprint — completion is the exhaustive reads-vs-fp diff, as a test.*

**Adversarial review (per AGENTS.md gate) — RAN before merge; 3 critics (spec-fidelity, hostile-data/determinism/concurrency, coherence-that-BUILDS-and-RUNS the merge+fingerprints+telemetry against real sqlite/hashlib/multiprocessing). All survivors folded; every fix host-verified.**

*Crown finding (all three critics, execution-proven):* the reconcile content-hash was over `(source, source_ref, props_json)` only — so a `--only-source` that fixes a **coordinate or name** (reconcile's most load-bearing input) left the fingerprint UNMOVED → reconcile stale-serves the old clustering, and my own Task-3 test mutated only `props_json` so the gap shipped green (the "test proves nothing about the omission" trap, applied to me). **Fixed:** the content-hash is over the FULL logical row `(source, source_ref, name, lat, lon, props_json)` with a **per-column neuter test** (lat/lon/name/props each move it — host-verified), floats quantized + JSON canonicalized, and an EXPLICIT `ORDER BY` (an unordered SELECT hashed non-deterministically). `id`/`run_id` excluded.

*Spec-fidelity + hostile HIGH:* the parallel path silently changed `run_extract` from **fail-fast to isolate-and-continue** (and `parallel=True` was default) → reverted to **fail-fast by default** (parallel preserves the ratified §6 contract; isolate is an explicit `--continue-on-source-failure` flag, re-ratification-flagged). A **crashed/OOM-killed worker isn't a Python exception** → status inferred from `exitcode`+a success sentinel, never "no exception" (else A2 mass-tombstones a `success/0` source). The full merge is now **ONE transaction** (merge + statuses + fingerprint) so a mid-run crash never marks a partial store complete (whole-run atomicity, not just per-source). A **working-store lock** serialises concurrent invocations. `id` is **out of the determinism contract** (autoincrement churns on `--only-source`; verified) — the stable key is `(source, source_ref)`; a full run drop+recreates for deterministic ids.

*Other survivors:* the `CODE_MARKER` is **auto-derived from the stage module's source hash** (a hand-bumped constant forgotten after a logic change = permanent silent stale-serve). The extract fingerprint gains the **enabled-`sources` set** (toggling a source off with unchanged files must invalidate). Task 3 **split** — extract + `source_records`-reconcile testable now; `redirect_map`/`thresholds`/`score`/`categorize` BLOCKED-ON A2/A3/A4 (the executable-now over-claim, corrected). `run_extract_parallel` carries `extractor_options` + `assert_disk_floor` (per child + for N stagings) + `join(timeout)`; children **rebuild the registry from config paths** (spawn-robust). Staging DBs open fresh + cleaned up. `stage_fingerprint` single signature threading the run's paths. WORKING_STORE_VERSION integer **assigned at land** (not pre-claimed — avoids the parallel-WP ladder collision). Telemetry `pct=floor`, `total=0→0`.

*Held under execution (coherence, verified):* the completion-order-shuffle merge is byte-identical across all permutations; the fingerprint neuter-goes-red on every INCLUDED component + is order/whitespace-stable; the telemetry strings match character-for-character; `spawn` is real+deterministic; and the BLOCKED-ON honesty holds (`mt_pipeline.ergonomics` absent; the acquire-branch `run_extract`/`extract_run_metadata`/`source_status_json`/WORKING_STORE_VERSION=3 signatures all match). A8 changes only the extract STAGE execution model — the §5.2 order gate, acquisition, and the A2 metadata contract are otherwise untouched.
