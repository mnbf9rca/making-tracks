# WP-A8 (Pipeline Ergonomics) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the pipeline fast and re-runnable **without ever sacrificing determinism**: run the five extractors as **concurrent processes** merged in fixed source order (byte-identical output regardless of completion order), a **`--only-source`** transactional re-extract, a **stage short-circuit** that skips a stage whose inputs are unchanged (a fingerprint memoization — the cache-invalidation trap designed hardest), and a **pinned telemetry format** monitors can rely on. The §5.2 stage-ORDER gate and the per-source success metadata A2 consumes stay exactly as they are.

**Architecture:** A new `mt_pipeline.ergonomics` package plus a re-shaped `run_extract`. Parallelism is **process-per-source into an isolated staging SQLite** (no concurrent writers to the working store), followed by a **deterministic merge** in the registry's fixed source order — so the working store's single-writer invariant is preserved *by construction* and the output is a pure function of the inputs, not of scheduling. Stage short-circuiting stores an **input fingerprint** per `(region, stage)`; an identical fingerprint → a loud SKIP (`--force` overrides). The reconcile-invalidated-by-any-extract-change invariant is **enforced** (reconcile fingerprints the `source_records` content-hash), not documented. Telemetry is a pinned, greppable line format.

**Tech Stack:** Python 3.11+ (`mt_pipeline`, on `wp-acquire-impl`'s extract surface), stdlib `multiprocessing` (spawn) + `sqlite3` (per-source staging DBs), `hashlib` (fingerprints), `pytest`. No new deps.

## Global Constraints

- **Determinism is the whole point (Principle 12).** Every A8 mechanism is a pure function of its declared inputs — never of thread/process scheduling or wall-clock. The parallel extract's merged `source_records` (including surrogate ids) is **byte-identical regardless of which extractor finishes first** — a **completion-order-shuffle test is MANDATORY** on every parallel path. Fingerprints are content hashes, never timestamps.
- **Single-writer to the working store, preserved BY CONSTRUCTION.** Extractors never write the working store concurrently: each writes its OWN ephemeral staging SQLite (`staging/{run_id}/{source}.db`, the same `source_records` shape), and a SINGLE sequential **merge** in fixed source order is the only writer of the real `source_records`. No cross-process lock on the working store is needed because no two processes touch it.
- **Per-source ALL-OR-NOTHING; the `source_status_json` A2 consumes stays TRUTHFUL (fable's failure rule).** A source either fully populates its staging DB (→ merged) or fails (→ NOT merged, its staging discarded). Each source's merge into the working store is ONE transaction (`delete-then-insert` that source's rows), so a mid-run failure never leaves a half-merged source. The existing `record_extract_run_metadata(source_statuses=…)` contract is written truthfully: `{status:"success", count}` per merged source, `{status:"failure", error}` per failed one — A2's `succeeded_sources` gate (which decides tombstoning) reads real state, never an optimistic one.
- **The §5.2 stage-ORDER gate is UNCHANGED.** `stages.run_stage`'s predecessor-completed check stays exactly as it is (extract→reconcile→score→categorize→publish). A8 adds a fingerprint SKIP *inside* a stage's execution, never a reordering or a bypass of the order gate.
- **Acquisition is UNTOUCHED.** The acquire side (snapshot download) already has its ratified concurrency policy (bounded `ThreadPoolExecutor` at the network boundary, WDQS sequential). A8 parallelises only the **extract STAGE** (parsing already-downloaded snapshots into `source_records`) — CPU/IO-bound local work, no network etiquette to honour.
- **`--force` is the only override; a SKIP is LOUD.** A short-circuit SKIP prints a pinned telemetry line naming the stage + the matched fingerprint; it is never silent. `--force` recomputes and re-runs regardless. A stale-serve (running with an unchanged fingerprint when an input actually changed) is **the most confidence-inspiring way to lie** — every fingerprint component gets a neuter-goes-red test.
- **WORKING_STORE_VERSION coordination (the migration ladder codex owns).** A8 adds a `stage_fingerprints` table (per `(region, stage)`: the last fingerprint + completion). That is a schema addition → a WORKING_STORE_VERSION bump stacked on `wp-acquire-impl`'s v3 (like A3/A4 extended it) — **the migration is added to A2-impl's ladder, coordinated, not forked.** Staging DBs are EPHEMERAL (not the working-store schema) → no version implication.
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
  - `staging.open_staging(root, run_id, source) -> sqlite3.Connection` — an ephemeral per-source DB with the `source_records` schema; an extractor writes ONLY here.
  - `staging.STAGING_ORDER` — the FIXED source order (the registry's registration order: `wikidata, wikipedia, osm, historic_england, open_plaques`) used for the merge — deterministic, independent of completion.
  - `merge.merge_sources(main_conn, staged: dict[str, str], succeeded: set[str], *, order=STAGING_ORDER) -> None` — for each source in `order` that is in `succeeded`, in ONE transaction: `DELETE FROM source_records WHERE source=?` then `INSERT` that source's staged rows **sorted by `source_ref`** (deterministic within-source order → deterministic surrogate ids). Sources absent from `succeeded` are NOT merged. Fixed order + within-source sort ⇒ the merged table is **byte-identical regardless of completion order**.

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
  - `parallel.run_extract_parallel(conn, region_config, snapshots, *, run_id, registry, status_recorder=None, max_workers=None) -> dict[str,int]` — a **drop-in for `run_extract`** with the SAME contract: spawn one process per enabled source (`multiprocessing`, `spawn` start method for determinism), each running its extractor into `open_staging(...)`; collect per-source `(succeeded|failed, count|error)`; then `merge.merge_sources` the succeeded set in fixed order into `conn`; record the SAME `source_statuses` map via the existing `status_recorder`/`record_extract_run_metadata`. Returns per-source counts (merged sources only). Each source is independent (all-or-nothing).
  - `extract_stage.run_extract(..., parallel: bool = True)` — `parallel=True` delegates to `run_extract_parallel`; `parallel=False` keeps the existing sequential path (kept for debugging + as the differential oracle). **Both paths produce the identical working store** (a test asserts sequential == parallel output).

- [ ] **Step 1: Write the failing tests**

```python
from mt_pipeline import extract_stage as X

def test_parallel_equals_sequential_output(tmp_path, uk_config, fixture_snapshots, registry):
    seq = _run_and_dump(X, uk_config, fixture_snapshots, registry, parallel=False)
    par = _run_and_dump(X, uk_config, fixture_snapshots, registry, parallel=True)
    assert seq == par                                             # same source_records, ids included

def test_one_failing_extractor_isolates_and_records_truthfully(tmp_path, uk_config, registry):
    snaps = {**fixture_snapshots, "osm": None}                    # osm snapshot missing -> that source fails
    statuses = {}
    X.run_extract(main_conn, uk_config, snaps, run_id="r", registry=registry, parallel=True,
                  status_recorder=lambda s, st: statuses.__setitem__(s, st))
    assert statuses["osm"]["status"] == "failure"                 # truthful
    assert statuses["wikidata"]["status"] == "success"           # the healthy source still merged
    assert main_conn.execute("SELECT COUNT(*) FROM source_records WHERE source='osm'").fetchone()[0] == 0
```

- [ ] **Step 2–4:** implement `run_extract_parallel` (spawn-per-source into staging → merge succeeded → record statuses) + the `parallel` flag. **Teeth:** the equivalence test reds if parallel diverges from sequential (the determinism guarantee); the failure test reds if a failed source corrupts the store or its status lies (`success` when it failed). Use `spawn` (not `fork`) so no inherited state makes a run non-reproducible.
- [ ] **Step 5: Commit** — `"Add parallel process-per-source extract (staging+merge; per-source failure isolation; parallel==sequential)"`

---

### Task 3: Stage short-circuit — the input fingerprint (the cache-invalidation trap, designed hardest)

**Files:** Create `pipeline/src/mt_pipeline/ergonomics/fingerprint.py`; Modify `stages.py` (`run_stage` short-circuit), `store.py` (`stage_fingerprints` table); Test `pipeline/tests/test_ergonomics_fingerprint.py`

**Interfaces:**
- Consumes: `store` (the working store + the new table), the config files, the stage inputs.
- Produces:
  - `store.stage_fingerprints` table `(region, stage, fingerprint, completed_at, PRIMARY KEY(region,stage))` (WORKING_STORE_VERSION bump, coordinated).
  - `fingerprint.STAGE_INPUTS` — the PINNED, EXACT input set per stage (fable's list — enforced, not documented):
    - **`extract`**: `sha256(each snapshot file)` + `sha256(wikidata_class_allowlist.json)` + `sha256(osm_candidate_tags.json)` + `CODE_MARKER["extract"]`.
    - **`reconcile`**: `source_records CONTENT-hash` (a stable hash over `(source, source_ref, props_json)` sorted — so ANY extract change, incl. a single `--only-source`, changes it) + `sha256(redirect_map)` + `sha256(thresholds)` + `CODE_MARKER["reconcile"]`.
    - **`score`**: `places content-hash` + `sha256(scoring.json)` + `sha256(pageview_cache)` + `CODE_MARKER["score"]`.
    - **`categorize`**: `places content-hash` + `sha256(taxonomy.json)` + `CODE_MARKER["categorize"]`.
  - `fingerprint.stage_fingerprint(conn, region, stage) -> str` — sha256 over the sorted-canonical tuple of that stage's inputs. `CODE_MARKER` is a per-stage constant bumped when the stage's logic changes (invalidates the cache on a code change — the "code marker" fable named).
  - `fingerprint.should_skip(conn, region, stage, fp, *, force) -> bool` — `True` iff `not force` AND the stage previously completed AND its stored fingerprint `== fp`. `stages.run_stage` computes `fp`, and if `should_skip` → emit a LOUD SKIP telemetry line and return without re-running; else run + store `fp`.

- [ ] **Step 1: Write the failing tests — neuter-goes-red on EVERY component**

```python
from mt_pipeline.ergonomics import fingerprint as F

def test_each_input_change_changes_the_fingerprint(tmp_path, populated_conn, configs):
    base = F.stage_fingerprint(populated_conn, "uk", "reconcile")
    # 1. a source_records content change (a single --only-source) MUST move the reconcile fingerprint:
    populated_conn.execute("UPDATE source_records SET props_json='{\"x\":1}' WHERE id=1"); populated_conn.commit()
    assert F.stage_fingerprint(populated_conn, "uk", "reconcile") != base    # extract change -> reconcile invalidated
    # 2. neuter: if source_records were NOT in the fingerprint, this assertion would FAIL -> the component is load-bearing

def test_config_and_code_marker_each_invalidate(tmp_path, populated_conn, configs):
    base = F.stage_fingerprint(populated_conn, "uk", "score")
    configs.write("scoring.json", {"weights": {"article": 0.6}})              # config change
    assert F.stage_fingerprint(populated_conn, "uk", "score") != base
    old = F.CODE_MARKER["score"]; F.CODE_MARKER["score"] = old + "!"          # code change (marker bump)
    assert F.stage_fingerprint(populated_conn, "uk", "score") != base

def test_identical_inputs_skip_unless_forced(populated_conn, configs):
    fp = F.stage_fingerprint(populated_conn, "uk", "extract")
    F.record(populated_conn, "uk", "extract", fp)                             # a prior completed run
    assert F.should_skip(populated_conn, "uk", "extract", fp, force=False) is True
    assert F.should_skip(populated_conn, "uk", "extract", fp, force=True) is False    # --force overrides
```

- [ ] **Step 2–4:** implement the table + `stage_fingerprint` (each component in `STAGE_INPUTS`, sorted-canonical, sha256) + `should_skip` + wire into `run_stage` (compute fp → skip-or-run → store fp; the order gate stays). **Teeth:** the reconcile test reds if `source_records` isn't fingerprinted (a stale reconcile after an extract change — the trap); the config/marker tests red if a config or the code marker escapes the fingerprint (a stale-serve after a weight change); the skip test reds if `--force` doesn't override or an identical fingerprint doesn't skip. **Every component of `STAGE_INPUTS` has a neuter-goes-red test — a component you can remove without reding a test is a stale-serve vector.**
- [ ] **Step 5: Commit** — `"Add stage short-circuit: per-stage input fingerprint (reconcile-invalidation enforced; --force; neuter-goes-red per component)"`

---

### Task 4: `--only-source` selective re-extract (transactional; reconcile-invalidation automatic)

**Files:** Create `pipeline/src/mt_pipeline/ergonomics/selective.py`; Modify `cli.py`; Test `pipeline/tests/test_ergonomics_selective.py`

**Interfaces:**
- Consumes: `staging`/`merge`, `fingerprint`, the registry, `record_extract_run_metadata`.
- Produces:
  - `selective.reextract_one_source(conn, region_config, source, snapshot, *, run_id, registry) -> dict` — re-extract ONLY `source` from its cached `snapshot`: extract into staging, then `merge_sources(conn, {source: staging}, {source})` — whose per-source transaction is `DELETE FROM source_records WHERE source=? ` then re-insert (a **transactional delete-and-replace of just that source's rows**; other sources untouched). Update that source's `source_statuses` entry. Returns the new status/count.
  - **The reconcile-invalidation is AUTOMATIC, not a separate step (fable: "enforce, don't document"):** because `reconcile`'s fingerprint includes the `source_records` content-hash (Task 3), replacing one source's rows changes that hash → reconcile's fingerprint no longer matches → the next `reconcile` run does NOT skip. `--only-source` does not need to (and must not) manually clear reconcile's completion; the fingerprint mechanism enforces it.

- [ ] **Step 1: Write the failing tests**

```python
from mt_pipeline.ergonomics import selective as SEL, fingerprint as F

def test_only_source_replaces_just_that_source(populated_conn, uk_config, registry, osm_snapshot):
    before_wd = populated_conn.execute("SELECT COUNT(*) FROM source_records WHERE source='wikidata'").fetchone()[0]
    SEL.reextract_one_source(populated_conn, uk_config, "osm", osm_snapshot, run_id="r2", registry=registry)
    after_wd = populated_conn.execute("SELECT COUNT(*) FROM source_records WHERE source='wikidata'").fetchone()[0]
    assert after_wd == before_wd                                 # other sources untouched (transactional, scoped)

def test_only_source_invalidates_reconcile_via_the_fingerprint(populated_conn, uk_config, registry, osm_snapshot):
    fp_before = F.stage_fingerprint(populated_conn, "uk", "reconcile")
    SEL.reextract_one_source(populated_conn, uk_config, "osm", osm_snapshot, run_id="r2", registry=registry)
    assert F.stage_fingerprint(populated_conn, "uk", "reconcile") != fp_before   # ANY extract change -> reconcile re-runs
```

- [ ] **Step 2–4:** implement `reextract_one_source` (staging → scoped delete-replace merge → status update) + the `--only-source <name>` CLI flag. **Teeth:** the scoping test reds if the re-extract touches another source's rows (a non-transactional or unscoped delete); the invalidation test reds if a one-source re-extract leaves reconcile's fingerprint unchanged (which would let a stale reconcile skip — the exact bug the enforced invariant prevents).
- [ ] **Step 5: Commit** — `"Add --only-source transactional re-extract (scoped delete-replace; reconcile-invalidation enforced via fingerprint)"`

---

### Task 5: Telemetry — the pinned, greppable format

**Files:** Create `pipeline/src/mt_pipeline/ergonomics/telemetry.py`; Test `pipeline/tests/test_ergonomics_telemetry.py`

**Interfaces:**
- Produces (the FORMAT is the contract — monitors grep it, so it is PINNED and tested):
  - `telemetry.progress(stage, region, *, done, total, extra="") -> str` — emits `PROGRESS stage=<stage> region=<region> done=<n> total=<n> pct=<0-100> [<extra>]` to stderr. Greppable on `^PROGRESS `.
  - `telemetry.phase_start(stage, region)` / `phase_done(stage, region, *, counts)` — `PHASE start stage=… region=…` and `PHASE done stage=… region=… <k=v counts>`.
  - `telemetry.heartbeat(stage, region, *, done)` — emitted every **10,000 items OR 30 seconds**, whichever first: `HEARTBEAT stage=… region=… done=… elapsed_s=…` (`elapsed_s` is the only clock-derived field, and it's telemetry-only — never fingerprinted).
  - `telemetry.report_log_path(path)` — on a detached/background launch, prints `LOG path=<abs path>` so a monitor knows where to tail. (Satisfies AGENTS.md #60 "no silent long-running work"; A8 pins the exact tokens.)

- [ ] **Step 1: Write the failing tests** (assert the EXACT format — a monitor depends on it):

```python
from mt_pipeline.ergonomics import telemetry as T

def test_progress_line_format_is_pinned():
    line = T.progress("extract", "uk", done=250, total=1000)
    assert line == "PROGRESS stage=extract region=uk done=250 total=1000 pct=25"

def test_phase_and_heartbeat_tokens_are_stable():
    assert T.phase_done("reconcile", "uk", counts={"places": 4200, "clusters": 4100}) == \
        "PHASE done stage=reconcile region=uk places=4200 clusters=4100"
    assert T.heartbeat("extract", "uk", done=10000, elapsed_s=31).startswith("HEARTBEAT stage=extract region=uk done=10000")
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

**Adversarial review (per AGENTS.md gate) — TO RUN before PR:** (1) fixes on the **executed path**; (2) **teeth** — the completion-order-shuffle test reds if the merge order depends on scheduling (surrogate ids diverge); parallel==sequential reds on any divergence; a failed source neither corrupts the store nor lies in `source_status_json`; **every fingerprint component has a neuter-goes-red test** (remove it → a stale-serve → red), especially reconcile's `source_records` content-hash (the trap); `--only-source` is scoped+transactional and invalidates reconcile via the fingerprint (not a manual clear); the telemetry tokens are pinned; (3) **the coherence critic RUNS the merge + fingerprint + telemetry on fixtures** (real sqlite, real hashing, shuffled completion orders) and confirms byte-identical merges + per-component fingerprint sensitivity + the pinned format; (4) confirm the **BLOCKED-ON honesty** — the real parallel/only-source/short-circuit runs on the acquire branch + real snapshots + A3/A4 config, no executed-path over-claim, and that A8 changes only the extract STAGE execution model (acquisition + the order gate + the A2 metadata contract all untouched).
