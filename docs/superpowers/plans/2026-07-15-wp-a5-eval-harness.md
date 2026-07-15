# WP-A5 (Eval Harness) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The golden-area eval harness — dump ranked candidate places for two golden areas (a London patch + a KL patch) to a trivially-editable hand-label file (*yes / meh / no*), and a **precision@k** report that scores **any `scoring.json` config** against those labels by **re-scoring offline from the dumped per-signal breakdown** (no pipeline re-run). It doubles as the ranking **regression suite** (Principle 13: the eval is the arbiter), checks the **Malaysia LLM-off floor**, and is the substrate A6's model bake-off rides on.

**Architecture:** A new `mt_pipeline.eval` package. The dump reads the WP-A2 `places` + WP-A3 `place_categories` + WP-A4 `place_scores` (incl. `signals_json`) for the candidates in a named bounding box. The **re-scorer imports A4's composite** (`mt_pipeline.score.composite.score`, injected so it's testable now and can't diverge in production) — so scoring a new weight config, or an LLM-off run, or a candidate LLM signal column (A6), needs only the dumped signals, never the pipeline. Labels are human judgments of *places* (config-independent), tied to the dump's data version.

**Tech Stack:** Python 3.11+ (`mt_pipeline`), stdlib (`json`/`csv`), `pytest`. No new deps.

## Global Constraints

- **Re-score OFFLINE from the dumped signals against ANY config — the load-bearing design (and the A6 seam).** The golden dump carries every place's **full per-signal breakdown** (from A4's `place_scores.signals_json`) plus a nullable `llm_curiosity` slot. The evaluator re-computes each place's composite from `(its signal values, a candidate `scoring.json`)` using **A4's own composite function** — never by re-running the pipeline. So: any weight config is scored "in an afternoon" (§4); the **LLM-off run** is just dropping the `llm_curiosity` signal (→ the Malaysia floor check); and **A6's model bake-off** writes a candidate model's curiosity value into the `llm_curiosity` slot and re-evals — the harness scores an **arbitrary signal column** with zero A5 change.
- **Consume A4's composite, never re-implement it.** The re-scorer takes an injected `score_fn` defaulting to `mt_pipeline.score.composite.score` — the same function the pipeline uses — so offline eval == pipeline scoring **by construction** (a re-implementation would silently diverge and make the eval lie). Tests inject a fake `score_fn` to exercise the harness logic in isolation. **The exact A4 signature this depends on is a BLOCKED-ON contract owed by A4's impl (spec-fidelity critic MED): `composite.score(signals: Mapping[str, float|None], config) -> float`** — signals keyed as A4's `place_scores.signals_json` writes them, `config` the weight dict. If A4's real signature differs (a `Signals` object, a place row, or `(config, signals)` order), "offline == pipeline by construction" silently degrades into "offline == a divergent adapter" — the exact failure this constraint forbids. So Task 6 includes an **integration test that binds the REAL `composite.score` and fails loudly if the signature/keys differ**, and the default injection is *not* asserted equivalent until that test passes.
- **Labels are place-intrinsic (config-INDEPENDENT), tied to the DUMP/data version.** A `yes/meh/no` label is a human judgment of a *place* ("is this interesting?"), not of a scoring config — the whole point is scoring **different weight configs against the SAME fixed labels**. The dump records its **data version** (`run_id`/snapshot) so labels are refreshed when the candidate **set** changes (new places appear). Authority = **fable's ratified rider** ("labels place-intrinsic, tied to the dump/data version"); labels refresh on **candidate-set** change, while scoring-weight changes are exactly what the fixed labels are re-scored against. (Note: §5.2's "eval labels stay tied to the config that generated them" is the *prompt-version/tiering provenance* mechanism — a related but distinct concern; it is not the citation for this data-version tie.)
- **The `data_version` must live in the artifact Rob labels — the TSV, not only the JSONL (spec-fidelity critic HIGH).** `GoldenRow` carries a `data_version` field; `render_tsv` emits it as a **second `#`-comment metadata line** (`# data_version: <run_id>`) — the TSV is what Rob labels and commits as the pinned golden set, so the label↔data-version tie must be legible from the TSV *alone*, not just its sibling JSONL. `parse_labeled_tsv` reads it back; `merge_labels` compares it so a labeled TSV whose `data_version` is stale against the current candidate set is **detectable** (a test pins this).
- **Deterministic (Principle 12).** The dump is a pure function of `(places, place_categories, place_scores)` — sorted by `(score desc, place_id asc)`, fixed column order; re-dumping the same data → byte-identical. The re-scorer + precision@k are pure functions of `(labeled rows, config)`. No wall-clock/randomness.
- **Doubles as the ranking regression suite (§5.2, §7).** A **baseline config's precision@k on the committed labeled golden set is pinned in a test**; a weight change that drops precision@k below the baseline **reds** — so a ranking regression is caught by CI, not by shipping. (This is why the labeled golden set is committed once Rob labels it.)
- **Malaysia LLM-off floor (§4).** The report runs precision@k on the **KL** golden area **with `llm_curiosity` off**, and asserts it clears an acceptable bar — the §4 "a KL golden area ranks acceptably with the LLM signal switched off". (A4's non-LLM floor test pins the *mechanism*; A5's is the *empirical* precision@k on real labels.)
- **Human-editable + robust (robustness-to-human-edit — NOT the §5.5 untrusted-data posture).** The hand-label file is a **TSV** Rob edits by hand (name/category/score visible, one `label` column to fill). Rob's labels are *trusted-but-fallible*, not adversarial — so the tolerant loader is justified by fat-finger risk, not §5.5 (§5.5 governs *hostile external* source data — vandalised Wikipedia/OSM/C2 feedback). The loader is **tolerant**: identifies `place_id`/`label` **by header NAME, not end-relative position** (hostile-data critic HIGH-2); **pads/truncates each row to the header column count** (missing trailing cells → blank — so a freshly-dumped unlabeled row whose last cells are empty is NOT dropped; coherence critic MED); **normalises `label = raw.strip().lower()`** then validates `∈ {yes, meh, no, ""}` (blank → `None`; so `YES`/` Yes `/`no\t` survive — hostile-data MED-4); validates `place_id` against the `^mt1_[0-9A-Za-z]{26}$` grammar (hostile-data LOW-10); **never crashes**.
- **Silent skips are a data-loss machine — the loader MUST reconcile (hostile-data critic HIGH-1).** "Skips a malformed row with a warning" silently discards the exact label Rob meant to apply (he fat-fingered a tab), and the committed set the **regression baseline pins against** is then quietly computed on fewer labels than he thinks. So `parse_labeled_tsv` returns a **reconciliation summary** — `parsed`, `labeled`, and a `skipped: list[(place_id_or_line, reason)]` — and the report/CLI **surfaces a non-empty skip list loudly** (banner + non-zero exit), never a lone stderr warning. **Malformed is DEFINED** = header/name resolution fails, `place_id` fails the grammar, or (after normalisation) `label` is out of set. **Duplicate `place_id`:** last **non-blank** label wins; two conflicting non-blank labels for one `place_id` is a **counted warning**, not a silent overwrite (hostile-data MED-5).
- **TSV safety is render-side defense-in-depth, not an upstream assumption (hostile-data MED-8).** `render_tsv` applies `strip_unsafe_text` (which removes C0 incl. TAB 0x09 / LF 0x0A — *verified* in `mt_contracts.text`) to every text cell **at render time regardless of upstream**, so a place `name`/`category` (A3's open SAFE_TEXT category, read straight from a plan-only table) that somehow carries a tab can never shift a column. This is independent of the parse-path robustness above — the two do not share a justification. One TSV mechanism both directions (`\t`-join / `\t`-split, `QUOTE_NONE`, embedded quotes literal — hostile-data LOW-9).
- **BLOCKED-ON declarations (up front — the A2/A3/A4 lesson).** A2/A3/A4 are merged as **plan only** (A4 = PR #48, merged plan-only 2026-07-15) — none of `places`/`place_categories`/`place_scores`/the A4 `composite.score` exist in code yet (verified: `mt_pipeline.score.composite` is absent from `develop`). So: the **pure dump-format, label-loader, re-scorer (with an injected fake `score_fn`), precision@k, and report logic are fixture-testable NOW**; the **real london+kl dumps (reading the three tables + A4's composite) are BLOCKED-ON A2/A3/A4 impls + real extracts**; Rob labels the real dumps in the morning. Nothing claims to read the tables or produce real dumps before those land.
- **Scope.** A5 computes **no LLM value** and runs **no model** — it only provides the slot + the harness A6's bake-off rides on (A6 is key-gated, after A5). A5 does not re-derive signals or re-run scoring — it re-scores from the dump.

**Ratified (fable, thread `wp/a5`)** — offline re-score-from-dumped-signals via A4's composite (the afternoon speed + the A6 seam); labels place-intrinsic + config-independent, tied to the dump/data version; deterministic TSV dump + JSONL; precision@k against any config; regression-suite baseline; KL LLM-off floor; the A6-side hooks (llm_curiosity slot + full breakdown + arbitrary-signal re-scorer + on/off toggle) frozen now; real dumps BLOCKED-ON A2/A3/A4 impls.

---

## File Structure

```
pipeline/src/mt_pipeline/eval/
  __init__.py
  golden.py       # dump_area(conn, area) -> rows; render_tsv/render_jsonl; parse_labeled_tsv (tolerant)
  rescore.py      # rescore(rows, config, *, score_fn=composite.score, llm_on=True) -> ranked
  metrics.py      # precision_at_k(ranked, positive, k)
  report.py       # eval_report(labeled, config, baseline=None) -> EvalReport (per-area, LLM on/off, regression)
pipeline/config/
  golden_areas.json      # VERSIONED committed config (rider 2): {"version":"1","areas":{"london":[minlon,minlat,maxlon,maxlat],"kl":[...]}}
pipeline/tests/
  test_eval_golden.py
  test_eval_rescore.py
  test_eval_metrics.py
  test_eval_report.py
  fixtures/eval/labeled_golden_sample.tsv     # committed hand-labeled fixture — ≥24 labeled rows so k=5/10/20 are interior (regression teeth)
docs/superpowers/eval/
  2026-07-15-golden-london.tsv / .jsonl       # real dumps (Task 6, BLOCKED-ON impls) — Rob labels the .tsv
  2026-07-15-golden-kl.tsv / .jsonl
```

---

### Task 1: Golden-area dump (candidates → editable TSV + machine JSONL)

**Files:** Create `pipeline/src/mt_pipeline/eval/golden.py`, `pipeline/config/golden_areas.json`; Test `pipeline/tests/test_eval_golden.py`

**Interfaces:**
- `golden.GoldenRow` — `dataclass(place_id, area, name, lat, lon, category, tier, score, signals: dict[str,float|None], label: str|None, data_version: str, active: bool = True)`. `data_version` binds the row to the dump/data snapshot; `active=False` marks a **retired** row (was labeled, no longer a candidate) so it persists in the committed file without re-appearing blank.
- `golden.ParseResult` — `dataclass(rows: list[GoldenRow], parsed: int, labeled: int, skipped: list[tuple[str, str]], data_version: str | None)`. The reconciliation summary — `skipped` is `(place_id_or_line, reason)`; a non-empty `skipped` is surfaced loudly by the CLI/report.
- `golden.dump_area(conn, area, bbox, *, data_version) -> list[GoldenRow]` — the places within `bbox` (from A2 `places`), joined to `place_categories.category` (A3) and `place_scores.score/tier/signals_json` (A4), **sorted `(score desc, place_id asc)`**. `label=None`, `active=True`, `data_version` stamped on every row. **(BLOCKED-ON the three tables — see below; the join is specified, the pure render/parse below run now.)**
- `golden.render_tsv(rows) -> str` — **two `#`-comment lines first:** line 0 the rider-3 instruction (`# Label the 'label' column only: yes = worth a detour · meh = fine but skippable · no = not interesting · (blank = skip). Do NOT edit other columns.`), line 1 the metadata (`# data_version: <run_id>`) — then a header + one row per place: `place_id, name, lat, lon, category, tier, score, <each signal>, label`. **`label=None` renders as an EMPTY cell — never the literal string `"None"`** (else every fresh dump parses as all-skipped; coherence critic MED / hostile-data MED-7). Every text cell passes `strip_unsafe_text` at render time. Retired (`active=False`) rows are emitted too (so their labels persist), tagged in the JSONL mirror. Deterministic.
- `golden.render_jsonl(rows) -> str` — the machine mirror (full signals + `data_version` + `active`), sorted.
- `golden.parse_labeled_tsv(text) -> ParseResult` — reads Rob's edited TSV back; **skips `#`-comment + blank lines** (reading `data_version` from the metadata comment); identifies `place_id`/`label` **by header name**; **pads/truncates each row to header length**; normalises `label = raw.strip().lower()`, validates `∈ {yes,meh,no,""}` (blank → `None`); validates `place_id` grammar; **counts every skip into `ParseResult.skipped` with a reason** (never a silent drop); duplicate `place_id` → last non-blank wins, conflicting non-blank → counted warning; never crashes.
- `golden.merge_labels(new_rows, existing_labeled) -> tuple[list[GoldenRow], list[GoldenRow]]` — **label survival across a data refresh (rider 1 — never orphan Rob's morning work):** labels are place-intrinsic, so when the candidate set changes, a `place_id` already labeled in `existing_labeled` **keeps its label**; a genuinely-new candidate arrives **blank**; a previously-labeled `place_id` **no longer in the new candidate set is NOT dropped** — it is returned in a second **`retired`** list (`active=False`, its label preserved). **`existing_labeled` MUST be the union of the last merge's active + retired rows** (the retired pool is persisted in the committed file, not thrown away) — so a place dropped in refresh N and re-added in refresh N+2 **resurrects its original label** instead of arriving blank (spec-fidelity MED / hostile-data MED-6). If `data_version` differs between `new_rows` and `existing_labeled`, that's the expected refresh case; an *identical* `data_version` with a changed candidate set is flagged. Deterministic.

- [ ] **Step 1: Failing tests** (`test_eval_golden.py`) — the pure render/parse run NOW:
```python
from dataclasses import replace
from mt_pipeline.eval import golden as G

A = "mt1_" + "a" * 26                                        # valid place_id grammar
B = "mt1_" + "b" * 26
C = "mt1_" + "c" * 26
def row(pid, name, score, label=None, active=True, dv="v1", **sig):
    return G.GoldenRow(pid, "london", name, 51.5, -0.1, "cat", 1, score,
                       {"article": sig.get("article", 0.0), "llm_curiosity": None},
                       label, data_version=dv, active=active)
ROWS = [row(A, "St Paul's", 0.9, article=0.9), row(B, "A Bench", 0.1, article=0.0)]

def test_tsv_layout_and_is_deterministic():
    tsv = G.render_tsv(ROWS)
    assert G.render_tsv(ROWS) == tsv                          # deterministic
    lines = tsv.splitlines()
    assert lines[0].startswith("# Label the 'label' column")  # rider-3 instruction is line 0
    assert lines[1] == "# data_version: v1"                   # data_version metadata is line 1 (in the TSV!)
    assert lines[2].startswith("place_id\t") and "\tlabel" in lines[2]   # header is line 2
    assert "\tNone" not in tsv                                # label=None renders EMPTY, never literal "None"

def test_fresh_dump_round_trips_as_all_unlabeled():
    # a freshly dumped (unlabeled) TSV whose last cell is empty must NOT lose its last row
    res = G.parse_labeled_tsv(G.render_tsv(ROWS))
    assert res.parsed == 2 and res.labeled == 0 and res.skipped == []
    assert [r.place_id for r in res.rows] == [A, B] and all(r.label is None for r in res.rows)
    assert res.data_version == "v1"                           # read back from the metadata comment

def _set_label(tsv, pid, raw):                               # edit the label (last) cell of pid's row
    out = []
    for ln in tsv.splitlines():
        f = ln.split("\t")
        if f and f[0] == pid:                                # skips '#'-comment + header rows
            f[-1] = raw
        out.append("\t".join(f))
    return "\n".join(out) + "\n"

def test_label_survives_edit_and_is_normalised():
    # Rob types a messy UPPERCASE-with-trailing-space label on A's row via the label column:
    edited = _set_label(G.render_tsv(ROWS), A, "YES ")
    res = G.parse_labeled_tsv(edited)
    assert res.labeled == 1
    assert {r.place_id: r.label for r in res.rows}[A] == "yes"   # strip().lower() normalised

def test_malformed_row_is_counted_not_silently_dropped():
    bad = G.render_tsv(ROWS) + "mt1_BADID\tx\n"                # bad grammar + short row
    res = G.parse_labeled_tsv(bad)
    assert res.parsed == 2                                    # the two real rows survive
    assert len(res.skipped) == 1 and "place_id" in res.skipped[0][1]   # skip is VISIBLE + reasoned

def test_labels_survive_and_resurrect_across_two_refreshes():
    labeled = [row(A, "St Paul's", 0.9, "yes", dv="v1"), row(B, "A Bench", 0.1, "no", dv="v1")]
    # refresh v2 drops B (→ retired) and adds C
    m1, retired1 = G.merge_labels([row(A, "St Paul's", 0.92, dv="v2"), row(C, "New Find", 0.6, dv="v2")], labeled)
    assert {r.place_id: r.label for r in m1} == {A: "yes", C: None}    # A kept; C blank
    assert [r.place_id for r in retired1] == [B] and retired1[0].label == "no" and not retired1[0].active
    # refresh v3 RE-ADDS B — its 'no' must resurrect (existing = union of active + retired pool)
    m2, _ = G.merge_labels([row(A, "St Paul's", 0.9, dv="v3"), row(B, "A Bench", 0.1, dv="v3")], m1 + retired1)
    assert {r.place_id: r.label for r in m2}[B] == "no"       # never went blank
```

- [ ] **Steps 2–4:** implement `render_tsv`/`render_jsonl`/`parse_labeled_tsv` (returning `ParseResult`)/`merge_labels` (pure, now) + `dump_area` (the join — **BLOCKED-ON A2/A3/A4 tables**, marked). **`golden_areas.json` is VERSIONED committed CONFIG, not code (rider 2):** `{"version":"1", "areas": {"london": [minlon,minlat,maxlon,maxlat], "kl": […]}}` — the area identity is stable across runs and adding a third golden area is a config edit, not a code change (§4 targets 3–4 areas; two now + config-extensibility meets it deliberately, not by oversight). **Teeth (all execution-verified on host):** deterministic layout (`data_version` on TSV line 1, empty label cell never `"None"`) + fresh-dump-round-trips-all-unlabeled (pad-to-header saves the trailing-empty last row) + label-normalisation (`YES ` → `yes`) + **malformed-is-counted-not-silently-dropped** (`ParseResult.skipped` non-empty + reasoned) + **label-survival-AND-resurrection-across-two-refreshes**.
- [ ] **Step 5: Commit** — `"Add golden-area dump: deterministic TSV/JSONL + tolerant hand-label loader"`

---

### Task 2: The offline re-scorer (imports A4's composite)

**Files:** Create `pipeline/src/mt_pipeline/eval/rescore.py`; Test `pipeline/tests/test_eval_rescore.py`

**Interfaces:**
- `rescore.rescore(rows, config, *, score_fn=None, llm_on=True) -> list[GoldenRow]` — for each row, compute `score_fn(signal_values, config)` where `signal_values` is the row's dumped `signals` (with `llm_curiosity` forced to `None` when `llm_on=False`), and **write the recomputed value back into the returned `GoldenRow`'s `score`** (`dataclasses.replace(row, score=new)`) before returning them **re-sorted `(new score desc, place_id asc)`**. The writeback is load-bearing for the LLM-off tooth: without it, `llm_on=False` merely re-sorts identical rows and a fixture whose curiosity order coincides with `place_id` order leaves the ranking invariant — the neuter proves nothing (coherence critic MED; the A2/A4 lesson). `score_fn` defaults to `mt_pipeline.score.composite.score` (A4 — so offline == pipeline); tests inject a fake. **This is the A6 seam:** an arbitrary signal (a candidate model's `llm_curiosity`) already present in `signals` is scored by any config with zero change here.

- [ ] **Step 1: Failing tests** (`test_eval_rescore.py`) — inject a fake `score_fn`, runs NOW:
```python
from mt_pipeline.eval import rescore as RS
# sample rows reuse Task 1's `row(...)`; the LLM fixture puts high llm_curiosity on the
# lexically-LATER place_id so the LLM signal FLIPS the order (neuter → order reverts).
def fake_score(sig, cfg):                                    # a stand-in for A4's composite
    return sum(cfg.get(k, 0) * v for k, v in sig.items() if v is not None)

def test_rescore_ranks_by_config_offline():
    rows = [row(A, "x", 0.0, article=0.9), row(B, "y", 0.0, article=0.1)]
    ranked = RS.rescore(rows, {"article": 1.0}, score_fn=fake_score)
    assert [r.place_id for r in ranked] == [A, B]            # higher article ranks first

def test_llm_off_flips_the_ranking():
    # A: article .5, llm 0.0 ; Z: article .5, llm 0.9 — with LLM on, Z (lexically later) wins.
    rows = [G.GoldenRow(A, "l", "a", 0, 0, "c", 1, 0, {"article": .5, "llm_curiosity": 0.0}, None, "v1"),
            G.GoldenRow(Z, "l", "z", 0, 0, "c", 1, 0, {"article": .5, "llm_curiosity": 0.9}, None, "v1")]
    on  = [r.place_id for r in RS.rescore(rows, {"article": 1, "llm_curiosity": 1}, score_fn=fake_score, llm_on=True)]
    off = [r.place_id for r in RS.rescore(rows, {"article": 1, "llm_curiosity": 1}, score_fn=fake_score, llm_on=False)]
    assert on == [Z, A] and off == [A, Z]                    # LLM on flips order; off reverts (Malaysia floor tooth)
```
(`Z = "mt1_" + "z" * 26`.) **Teeth (host-verified):** `test_llm_off_flips_the_ranking` asserts the *ordering* changes, not dataclass inequality — it reds if `llm_on` is ignored OR if the writeback is dropped. The config test reds if weights aren't applied.

- [ ] **Steps 2–4:** implement (default `score_fn` imports A4's composite; `llm_on=False` sets `signals["llm_curiosity"]=None`; **writeback via `replace`**). **Consume-not-reinvent teeth:** the default `score_fn` IS `composite.score` — a divergent re-implementation is forbidden (the real binding is exercised by Task 6's integration test).
- [ ] **Step 5: Commit** — `"Add offline re-scorer (imports A4 composite; LLM on/off toggle; arbitrary-signal ready)"`

---

### Task 3: precision@k

**Files:** Create `pipeline/src/mt_pipeline/eval/metrics.py`; Test `pipeline/tests/test_eval_metrics.py`

**Interfaces:** `metrics.precision_at_k(ranked, k, *, positive) -> float | None` — of the top-`min(k, n_labeled)` **labeled** rows (skip `label=None`), the fraction whose `label ∈ positive`. **Divisor is pinned `denom = min(k, n_labeled)`; if `denom == 0` return `None` ("undefined") — NEVER divide by zero** (hostile-data critic HIGH-3; `k=0`, empty ranking, and an all-unlabeled set all → `None`, verified on host). Reported for `positive={"yes"}` (strict) **and** `positive={"yes","meh"}` (lenient), at several `k`.
- **Ranking sensitivity holds only while `k < n_labeled`.** Once `k ≥ n_labeled`, precision@k = (total positives)/(total labeled) — **order-independent**, so no ranking regression can move it (coherence critic HIGH, execution-proven). The regression gate (Task 4) MUST pin `k` values *interior* to the committed fixture's labeled-row count.

- [ ] **Steps 1–4:** tests (a known ranking + labels → exact precision@k; **mis-ordered vs correct at `k < n_labeled` → strictly lower** — the ranking-quality tooth; `k=0` → `None`; empty ranking → `None`; all-`None` labels → `None`; all-yes → 1.0; all-no → 0.0) + implement. **Teeth (host-verified):** correct order @2 = 1.0 vs mis-ordered @2 = 0.0.
- [ ] **Step 5: Commit** — `"Add precision@k (strict yes + lenient yes|meh, multiple k)"`

---

### Task 4: The eval report + regression baseline + LLM-off floor

**Files:** Create `pipeline/src/mt_pipeline/eval/report.py`; a committed labeled fixture `pipeline/tests/fixtures/eval/labeled_golden_sample.tsv`; Test `pipeline/tests/test_eval_report.py`

**Interfaces:**
- `report.eval_report(labeled_rows, config, *, score_fn=None) -> EvalReport` — per area: precision@k (strict + lenient, at 5/10/20) for the config, **and** the LLM-off variant. Deterministic.
- `report.assert_no_regression(labeled_rows, config, baseline: dict) -> None` — the **regression gate**: re-score + precision@k for `config`; **raise if any metric drops below the pinned `baseline`** (a change that worsens ranking fails CI). This is the "doubles as the regression suite".

- [ ] **Step 1–4:** a **committed hand-labeled fixture that is BIG ENOUGH for the pinned k to be interior** — **≥ 24 labeled rows** (heritage places labeled `yes` with high `article`/low `sitelinks`, junk labeled `no` with the inverse), so `k=5/10/20 < n_labeled` and a ranking regression can actually move precision@k (coherence critic HIGH: on the original "handful" fixture, k=5/10/20 were blind — good==worse==0.5 — and `assert_no_regression` did NOT red; verified on host that a 24-yes/24-no fixture reds at k=5/10/20, good=1.0 vs worse=0.0). Tests: (a) `eval_report` produces stable precision@k; (b) `assert_no_regression` **passes** for the baseline config and **REDS** for a deliberately-worse config (all-weight-on-`sitelinks` when labels favour heritage) **at the pinned interior k on the committed fixture** — assert the red explicitly, and also pin one small `k < n_labeled` explicitly sized to the fixture; (c) an **LLM-off** run on the fixture clears a **pinned numeric floor constant** (a concrete `>= FLOOR` red/green assertion, not "acceptably"; the real KL floor bar is recorded in Task 6 Step 3). **Teeth:** the regression test reds if `assert_no_regression` doesn't compare against the baseline AND if the fixture is too small for the pinned k (a too-small fixture would make the worse-config case NOT red — the fixture-size assertion guards this).
- [ ] **Step 5: Commit** — `"Add eval report + regression-gate + LLM-off floor (baseline pinned on a labeled fixture)"`

---

### Task 5: CLI + golden_areas config

**Files:** Modify `cli.py` (an `mt eval` group); `golden_areas.json`

**Interfaces:** `mt eval dump <area>` (writes the TSV+JSONL for `london`/`kl` — BLOCKED-ON impls) and `mt eval report <labeled.tsv> --config scoring.json` (runs precision@k + the regression gate against any config — fixture-runnable now). `eval` is a **tool, not a `STAGE_ORDER` stage** (it reads the pipeline's output, doesn't sit in the extract→…→publish chain).

- [ ] **Steps 1–5:** wire the CLI subcommands (the `report` path runs now on a labeled fixture; `dump` is BLOCKED-ON the tables); commit.

---

### Task 6: REAL london + kl golden dumps  `[BLOCKED-ON A2/A3/A4 impls + real extracts]`

> **⛔ BLOCKED-ON A2/A3/A4 impls (the `places`/`place_categories`/`place_scores` tables + A4's composite) + `wp-acquire-impl` (real extracts).** Declared, not discovered (the A2/A3/A4 lesson). Tasks 1–5 are fixture-executable now (the dump *format*, the re-scorer with an injected fake, precision@k, the report/regression gate on a committed labeled fixture). Task 6 generates the **real** dumps once the pipeline produces real scored+categorized places.

- [ ] **Step 0 (after A4 impl lands — the composite-signature contract check):** an **integration test that imports the REAL `mt_pipeline.score.composite.score` and asserts its signature is `(signals: Mapping[str, float|None], config) -> float`** with the `signals_json` key set A4 actually writes — `rescore` binds it as its default `score_fn` and **fails loudly if the signature/keys differ** (spec-fidelity MED). Until this passes, "offline == pipeline by construction" is not asserted — the default injection could otherwise silently become a divergent adapter.
- [ ] **Step 1 (after impls):** `mt extract/reconcile/score/categorize uk` then `mt eval dump london`; same for `mt eval dump kl`. Commit `docs/superpowers/eval/2026-07-15-golden-london.tsv`/`.jsonl` + the KL pair (the unlabeled dumps).
- [ ] **Step 2 (Rob, morning):** Rob hand-labels the `.tsv`s (`yes/meh/no`). Commit the labeled TSVs — **this is the golden set the regression suite pins against**.
- [ ] **Step 3:** `mt eval report docs/…/golden-kl.tsv --config scoring.json` → confirm the **KL LLM-off precision@k clears the Malaysia floor bar** (§4); run the London report; record the baseline precision@k the regression gate pins. Commit `docs/superpowers/reports/2026-07-15-a5-eval.md`.
- [ ] **Step 4: Commit** — `"Add real london+kl golden dumps + labeled sets + baseline eval report (after impls)"`

---

## Review Record

**Author self-review** — deliverables map to tasks: the golden dump + tolerant label loader (T1), the offline re-scorer importing A4's composite (T2), precision@k (T3), the eval report + regression gate + LLM-off floor (T4), the CLI (T5), and the real london+kl dumps + labeled sets (T6, BLOCKED-ON impls). The eval **re-scores offline from the dumped per-signal breakdown against any config via A4's own composite** — the afternoon speed, the regression suite, and the A6 bake-off seam, all from one design. Labels are place-intrinsic and config-independent (tied to the dump/data version). Deterministic; human-editable + robust; A5 computes no LLM value.

**Ratifications (fable, thread `wp/a5`)** — offline re-score via A4's composite; labels place-intrinsic; deterministic TSV+JSONL; precision@k any-config; regression-suite baseline; KL LLM-off floor; the A6-side hooks frozen now; real dumps BLOCKED-ON A2/A3/A4 impls.

**Cross-package needs surfaced:**
- **A6 bake-off rides on A5 (the seam is frozen HERE):** the dump/label schema includes the `llm_curiosity` slot + the full per-signal breakdown; the re-scorer scores an **arbitrary signal→value map** against any config; the LLM-on/off toggle is built. A6 writes a candidate model's curiosity value into the slot and re-evals — **no A5-side change needed later** (the pre-emptive hook fable asked for). A6 is key-gated + after A5.
- **BLOCKED-ON A2/A3/A4 impls** — the dump reads `places`/`place_categories`/`place_scores` + A4's `composite.score`, none in code yet (A2/A3/A4 are all merged **plan-only**; `mt_pipeline.score.composite` verified absent from `develop`). Real extracts are `wp-acquire-impl`. **The exact `composite.score` signature is a contract owed by A4's impl, checked by Task 6 Step 0's integration test.**
- **Real taxonomy + scoring before real dumps (the A3→A5 ordering fable flagged):** the golden dumps carry `category` (A3) + `score`/`tier` (A4), so the real A3 taxonomy + A4 config must land before the dumps are generated — else Rob labels against provisional categories.
- **Rob hand-labels the real dumps** (morning) — the committed labeled TSVs become the regression baseline.
- **Store shapes:** reads A2 `places` (`place_id, region, name, lat, lon, member_refs_json`), A3 `place_categories` (`category`), A4 `place_scores` (`score, tier, signals_json`).

**Adversarial review (per AGENTS.md gate) — RAN before merge; 3 critics (spec-fidelity, hostile-data, coherence-that-RUNS-on-a-live-interpreter). All survivors folded; each fix host-verified.**

*Crown finding (coherence, HIGH — execution-proven):* the regression tooth was **FALSE** at the pinned `k=5/10/20` on a "handful" fixture — precision@k with `k ≥ n_labeled` is order-independent, so `assert_no_regression` did **not** red on a worse config. This is the "neuter leaves the output invariant" lesson (A2/A4) recurring in metric form. **Fixed:** committed fixture is now **≥24 labeled rows** (k interior) + the gate pins one small `k < n_labeled`; host-verified good=1.0 vs worse=0.0 reds at k=5/10/20.

*Hostile-data (HIGH×3):* silent row-skip = silent destruction of Rob's labels behind an unseen warning → **`parse_labeled_tsv` now returns a `ParseResult` reconciliation summary** (`parsed`/`labeled`/`skipped[reason]`) surfaced loudly. "Malformed" is **defined** (header-name keying, pad-to-header, place_id grammar) not end-relative guessing. precision@k divisor **pinned `min(k, n_labeled)`, 0 → `None`** (no div-by-zero). SAFE_TEXT/tab claim **confirmed true** (strips C0 incl. TAB/LF) but re-cast as **render-side defense-in-depth**, decoupled from the parse-path robustness rationale.

*Coherence (MED×2):* the LLM-off `on != off` tooth was **conditionally FALSE** (no writeback + coincidental ordering) → `rescore` now **writes the recomputed score back** and the fixture puts high curiosity on the lexically-later id so the neuter **flips the order** (host: on=[Z,A], off=[A,Z]); the original tolerance test was **vacuously green** and dropped the last row → rewritten to actually set/normalise a label (`YES ` → `yes`) and pad-to-header saves the trailing-empty row.

*Spec-fidelity (HIGH + MED):* `data_version` had **no home in the TSV Rob labels** → added to `GoldenRow` + a `# data_version:` metadata line + read-back + stale-detection. Rider-1's `retired` list had **no persistence sink** → `active` flag + `existing_labeled = union(active, retired)` + a **two-refresh resurrection** test (host-verified B's `no` survives drop-then-readd). Misapplied §5.2 (prompt-version provenance) and §5.5 (hostile-external posture) citations **corrected** to cite fable's rider / robustness-to-human-edit. The `composite.score` **signature is now an explicit BLOCKED-ON contract** with a Task 6 integration test that fails loudly on drift.

*Honesty preserved:* the real-dump task stays **BLOCKED-ON A2/A3/A4 impls**; the stale "(unmerged)" wording for PR #48 corrected to "merged plan-only". A6 seam confirmed complete (arbitrary signal column + on/off + full breakdown) — no A5-side change needed later.
