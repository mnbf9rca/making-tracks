# WP-A5 (Eval Harness) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The golden-area eval harness — dump ranked candidate places for two golden areas (a London patch + a KL patch) to a trivially-editable hand-label file (*yes / meh / no*), and a **precision@k** report that scores **any `scoring.json` config** against those labels by **re-scoring offline from the dumped per-signal breakdown** (no pipeline re-run). It doubles as the ranking **regression suite** (Principle 13: the eval is the arbiter), checks the **Malaysia LLM-off floor**, and is the substrate A6's model bake-off rides on.

**Architecture:** A new `mt_pipeline.eval` package. The dump reads the WP-A2 `places` + WP-A3 `place_categories` + WP-A4 `place_scores` (incl. `signals_json`) for the candidates in a named bounding box. The **re-scorer imports A4's composite** (`mt_pipeline.score.composite.score`, injected so it's testable now and can't diverge in production) — so scoring a new weight config, or an LLM-off run, or a candidate LLM signal column (A6), needs only the dumped signals, never the pipeline. Labels are human judgments of *places* (config-independent), tied to the dump's data version.

**Tech Stack:** Python 3.11+ (`mt_pipeline`), stdlib (`json`/`csv`), `pytest`. No new deps.

## Global Constraints

- **Re-score OFFLINE from the dumped signals against ANY config — the load-bearing design (and the A6 seam).** The golden dump carries every place's **full per-signal breakdown** (from A4's `place_scores.signals_json`) plus a nullable `llm_curiosity` slot. The evaluator re-computes each place's composite from `(its signal values, a candidate `scoring.json`)` using **A4's own composite function** — never by re-running the pipeline. So: any weight config is scored "in an afternoon" (§4); the **LLM-off run** is just dropping the `llm_curiosity` signal (→ the Malaysia floor check); and **A6's model bake-off** writes a candidate model's curiosity value into the `llm_curiosity` slot and re-evals — the harness scores an **arbitrary signal column** with zero A5 change.
- **Consume A4's composite, never re-implement it.** The re-scorer takes an injected `score_fn` defaulting to `mt_pipeline.score.composite.score` — the same function the pipeline uses — so offline eval == pipeline scoring **by construction** (a re-implementation would silently diverge and make the eval lie). Tests inject a fake `score_fn` to exercise the harness logic in isolation.
- **Labels are place-intrinsic (config-INDEPENDENT), tied to the DUMP/data version.** A `yes/meh/no` label is a human judgment of a *place* ("is this interesting?"), not of a scoring config — the whole point is scoring **different weight configs against the SAME fixed labels**. The dump records its **data version** (`run_id`/snapshot) so labels are refreshed when the candidate **set** changes (new places appear), per §5.2 "eval labels stay tied to the config that generated them" (the *candidate*-generating config, i.e. the data/extract version — not the scoring weights).
- **Deterministic (Principle 12).** The dump is a pure function of `(places, place_categories, place_scores)` — sorted by `(score desc, place_id asc)`, fixed column order; re-dumping the same data → byte-identical. The re-scorer + precision@k are pure functions of `(labeled rows, config)`. No wall-clock/randomness.
- **Doubles as the ranking regression suite (§5.2, §7).** A **baseline config's precision@k on the committed labeled golden set is pinned in a test**; a weight change that drops precision@k below the baseline **reds** — so a ranking regression is caught by CI, not by shipping. (This is why the labeled golden set is committed once Rob labels it.)
- **Malaysia LLM-off floor (§4).** The report runs precision@k on the **KL** golden area **with `llm_curiosity` off**, and asserts it clears an acceptable bar — the §4 "a KL golden area ranks acceptably with the LLM signal switched off". (A4's non-LLM floor test pins the *mechanism*; A5's is the *empirical* precision@k on real labels.)
- **Human-editable + robust (§5.5 — the label file is human/edited input).** The hand-label file is a **TSV** Rob edits by hand (name/category/score visible, one `label` column to fill). The loader is **tolerant**: it validates `label ∈ {yes, meh, no, ""}` (blank = unlabeled, skipped), tolerates reordered/extra rows and trailing whitespace, keys by `place_id`, and **never crashes** on a malformed row (skips it with a warning). Names are A1-scrubbed (no tabs/control chars — SAFE_TEXT strips C0), so TSV is safe.
- **BLOCKED-ON declarations (up front — the A2/A3/A4 lesson).** A2/A3 are merged as **plan only** and A4 is **PR #48 (unmerged)** — none of `places`/`place_categories`/`place_scores`/the A4 composite exist in code yet. So: the **pure dump-format, label-loader, re-scorer (with an injected fake `score_fn`), precision@k, and report logic are fixture-testable NOW**; the **real london+kl dumps (reading the three tables + A4's composite) are BLOCKED-ON A2/A3/A4 impls + real extracts**; Rob labels the real dumps in the morning. Nothing claims to read the tables or produce real dumps before those land.
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
  golden_areas.json      # named bboxes: {"london": [minlon,minlat,maxlon,maxlat], "kl": [...]}
pipeline/tests/
  test_eval_golden.py
  test_eval_rescore.py
  test_eval_metrics.py
  test_eval_report.py
  fixtures/eval/labeled_golden_sample.tsv     # a tiny hand-labeled fixture (for the regression test)
docs/superpowers/eval/
  2026-07-15-golden-london.tsv / .jsonl       # real dumps (Task 6, BLOCKED-ON impls) — Rob labels the .tsv
  2026-07-15-golden-kl.tsv / .jsonl
```

---

### Task 1: Golden-area dump (candidates → editable TSV + machine JSONL)

**Files:** Create `pipeline/src/mt_pipeline/eval/golden.py`, `pipeline/config/golden_areas.json`; Test `pipeline/tests/test_eval_golden.py`

**Interfaces:**
- `golden.GoldenRow` — `dataclass(place_id, area, name, lat, lon, category, tier, score, signals: dict[str,float|None], label: str|None)`.
- `golden.dump_area(conn, area, bbox, *, data_version) -> list[GoldenRow]` — the places within `bbox` (from A2 `places`), joined to `place_categories.category` (A3) and `place_scores.score/tier/signals_json` (A4), **sorted `(score desc, place_id asc)`**. `label=None`. Records `data_version`. **(BLOCKED-ON the three tables — see below; the join is specified, the pure render/parse below run now.)**
- `golden.render_tsv(rows) -> str` — **a `#`-comment instruction line first (rider 3 — zero-doc labeling):** `# Label the 'label' column only: yes = worth a detour · meh = fine but skippable · no = not interesting · (blank = skip). Do NOT edit other columns.` — then a header + one row per place: `place_id, name, lat, lon, category, tier, score, <each signal>, label`. Deterministic; the `label` cell is empty for Rob to fill.
- `golden.render_jsonl(rows) -> str` — the machine mirror (full signals + `data_version`), sorted.
- `golden.parse_labeled_tsv(text) -> list[GoldenRow]` — reads Rob's edited TSV back; **skips `#`-comment + blank lines**; **tolerant** (validates `label ∈ {yes,meh,no,""}`; blank → `label=None`; skips malformed rows with a warning; keys by `place_id`); never crashes.
- `golden.merge_labels(new_rows, existing_labeled) -> tuple[list[GoldenRow], list[GoldenRow]]` — **label survival across a data refresh (rider 1 — never orphan Rob's morning work):** labels are place-intrinsic, so when the candidate set changes, a `place_id` already labeled in `existing_labeled` **keeps its label**; a genuinely-new candidate arrives **blank**; a previously-labeled `place_id` **no longer in the new candidate set is NOT dropped** — it is returned in a second **`retired`** list (its label preserved, flagged inactive, so it never re-appears blank for Rob and its labeling effort is never lost). Deterministic.

- [ ] **Step 1: Failing tests** (`test_eval_golden.py`) — the pure render/parse run NOW:
```python
from mt_pipeline.eval import golden as G

ROWS = [G.GoldenRow("mt1_a", "london", "St Paul's", 51.5, -0.1, "religious", 1, 0.9,
                    {"article": 0.9, "llm_curiosity": None}, None),
        G.GoldenRow("mt1_b", "london", "A Bench", 51.5, -0.1, "uncategorized", 4, 0.1,
                    {"article": 0.0, "llm_curiosity": None}, None)]

def test_tsv_round_trips_and_is_deterministic():
    tsv = G.render_tsv(ROWS)
    assert G.render_tsv(ROWS) == tsv                          # deterministic
    lines = tsv.splitlines()
    assert lines[0].startswith("# Label the 'label' column")  # rider-3 instruction line is line 0
    assert lines[1].startswith("place_id\t") and "label" in lines[1]  # header is line 1
    back = G.parse_labeled_tsv(tsv)
    assert [r.place_id for r in back] == ["mt1_a", "mt1_b"]

def test_label_loader_is_tolerant():
    tsv = G.render_tsv(ROWS)
    # Rob edits: labels a row 'yes', another 'no', leaves a stray blank line + trailing spaces
    edited = tsv.replace("mt1_a\t", "mt1_a\t").rstrip() + "\n\n"   # (labels applied via the label column)
    edited = edited.replace("\tNone\n", "\t\n")                    # blank labels tolerated
    rows = G.parse_labeled_tsv(edited)
    assert all(r.label in (None, "yes", "meh", "no") for r in rows)   # only valid labels

def test_malformed_row_is_skipped_not_crashed():
    bad = G.render_tsv(ROWS) + "not\ta\tvalid\trow\n"
    rows = G.parse_labeled_tsv(bad)                               # skips the bad row + the # comment, no crash
    assert len(rows) == 2

def test_labels_survive_a_data_refresh():
    # Rob labeled the old set; a new data version drops 'mt1_b' and adds 'mt1_c'. His labels must survive.
    labeled = [G.GoldenRow("mt1_a", "london", "St Paul's", 51.5, -0.1, "religious", 1, 0.9, {}, "yes"),
               G.GoldenRow("mt1_b", "london", "A Bench", 51.5, -0.1, "uncategorized", 4, 0.1, {}, "no")]
    new = [G.GoldenRow("mt1_a", "london", "St Paul's", 51.5, -0.1, "religious", 1, 0.92, {}, None),  # re-dumped
           G.GoldenRow("mt1_c", "london", "New Find", 51.5, -0.1, "history", 2, 0.6, {}, None)]      # new candidate
    merged, retired = G.merge_labels(new, labeled)
    assert {r.place_id: r.label for r in merged} == {"mt1_a": "yes", "mt1_c": None}   # a keeps 'yes'; c blank
    assert [r.place_id for r in retired] == ["mt1_b"]             # b's 'no' is preserved, flagged inactive
```

- [ ] **Steps 2–4:** implement `render_tsv`/`render_jsonl`/`parse_labeled_tsv`/`merge_labels` (pure, now) + `dump_area` (the join — **BLOCKED-ON A2/A3/A4 tables**, marked). **`golden_areas.json` is VERSIONED committed CONFIG, not code (rider 2):** `{"version":"1", "areas": {"london": [minlon,minlat,maxlon,maxlat], "kl": […]}}` — the area identity is stable across runs and adding a third golden area is a config edit, not a code change. **Teeth:** round-trip + tolerance + malformed-skip + **label-survival-across-refresh**.
- [ ] **Step 5: Commit** — `"Add golden-area dump: deterministic TSV/JSONL + tolerant hand-label loader"`

---

### Task 2: The offline re-scorer (imports A4's composite)

**Files:** Create `pipeline/src/mt_pipeline/eval/rescore.py`; Test `pipeline/tests/test_eval_rescore.py`

**Interfaces:**
- `rescore.rescore(rows, config, *, score_fn=None, llm_on=True) -> list[GoldenRow]` — for each row, compute `score_fn(signal_values, config)` where `signal_values` is the row's dumped `signals` (with `llm_curiosity` forced to `None` when `llm_on=False`), returning the rows **re-sorted `(new score desc, place_id asc)`**. `score_fn` defaults to `mt_pipeline.score.composite.score` (A4 — so offline == pipeline); tests inject a fake. **This is the A6 seam:** an arbitrary signal (a candidate model's `llm_curiosity`) already present in `signals` is scored by any config with zero change here.

- [ ] **Step 1: Failing tests** (`test_eval_rescore.py`) — inject a fake `score_fn`, runs NOW:
```python
from mt_pipeline.eval import rescore as RS

def fake_score(sig, cfg):                                    # a stand-in for A4's composite
    return sum(cfg.get(k, 0) * v for k, v in sig.items() if v is not None)

def test_rescore_ranks_by_config_offline(sample_rows):       # sample_rows: two GoldenRows
    ranked = RS.rescore(sample_rows, {"article": 1.0}, score_fn=fake_score)
    assert [r.place_id for r in ranked] == ["mt1_a", "mt1_b"]   # higher article ranks first

def test_llm_off_drops_the_llm_signal(sample_rows_with_llm):
    on = RS.rescore(sample_rows_with_llm, {"llm_curiosity": 1.0}, score_fn=fake_score, llm_on=True)
    off = RS.rescore(sample_rows_with_llm, {"llm_curiosity": 1.0}, score_fn=fake_score, llm_on=False)
    assert on != off                                         # LLM contributes on; is absent off (Malaysia floor)
```

- [ ] **Steps 2–4:** implement (default `score_fn` imports A4's composite; `llm_on=False` sets `signals["llm_curiosity"]=None`). **Teeth:** the LLM-off test reds if `llm_on` is ignored; the ranking test reds if the config isn't applied. **Consume-not-reinvent teeth:** the default `score_fn` IS `composite.score` — a divergent re-implementation is forbidden.
- [ ] **Step 5: Commit** — `"Add offline re-scorer (imports A4 composite; LLM on/off toggle; arbitrary-signal ready)"`

---

### Task 3: precision@k

**Files:** Create `pipeline/src/mt_pipeline/eval/metrics.py`; Test `pipeline/tests/test_eval_metrics.py`

**Interfaces:** `metrics.precision_at_k(ranked, k, *, positive) -> float` — of the top-`k` **labeled** rows (skip `label=None`), the fraction whose `label ∈ positive`. Reported for `positive={"yes"}` (strict) **and** `positive={"yes","meh"}` (lenient), at several `k` (e.g. 5, 10, 20).

- [ ] **Steps 1–4:** tests (a known ranking + labels → exact precision@k; `k` beyond the labeled count; all-yes → 1.0; all-no → 0.0) + implement. **Teeth:** a mis-ordered ranking gives a lower precision@k (the metric actually measures ranking quality).
- [ ] **Step 5: Commit** — `"Add precision@k (strict yes + lenient yes|meh, multiple k)"`

---

### Task 4: The eval report + regression baseline + LLM-off floor

**Files:** Create `pipeline/src/mt_pipeline/eval/report.py`; a committed labeled fixture `pipeline/tests/fixtures/eval/labeled_golden_sample.tsv`; Test `pipeline/tests/test_eval_report.py`

**Interfaces:**
- `report.eval_report(labeled_rows, config, *, score_fn=None) -> EvalReport` — per area: precision@k (strict + lenient, at 5/10/20) for the config, **and** the LLM-off variant. Deterministic.
- `report.assert_no_regression(labeled_rows, config, baseline: dict) -> None` — the **regression gate**: re-score + precision@k for `config`; **raise if any metric drops below the pinned `baseline`** (a change that worsens ranking fails CI). This is the "doubles as the regression suite".

- [ ] **Step 1–4:** a **committed tiny hand-labeled fixture** (a handful of `GoldenRow`s with realistic signals + `yes/meh/no` labels) + tests: (a) `eval_report` produces stable precision@k; (b) `assert_no_regression` **passes** for the baseline config and **reds** for a deliberately-worse config (e.g. all-weight-on-`sitelinks` when the labels favor heritage) — the regression teeth; (c) an **LLM-off** run on the fixture clears a floor bar (the Malaysia-floor precision@k on real labels comes in Task 6 on the KL data; here it's pinned on the fixture). **Teeth:** the regression test reds if `assert_no_regression` doesn't compare against the baseline; the worse-config case must red.
- [ ] **Step 5: Commit** — `"Add eval report + regression-gate + LLM-off floor (baseline pinned on a labeled fixture)"`

---

### Task 5: CLI + golden_areas config

**Files:** Modify `cli.py` (an `mt eval` group); `golden_areas.json`

**Interfaces:** `mt eval dump <area>` (writes the TSV+JSONL for `london`/`kl` — BLOCKED-ON impls) and `mt eval report <labeled.tsv> --config scoring.json` (runs precision@k + the regression gate against any config — fixture-runnable now). `eval` is a **tool, not a `STAGE_ORDER` stage** (it reads the pipeline's output, doesn't sit in the extract→…→publish chain).

- [ ] **Steps 1–5:** wire the CLI subcommands (the `report` path runs now on a labeled fixture; `dump` is BLOCKED-ON the tables); commit.

---

### Task 6: REAL london + kl golden dumps  `[BLOCKED-ON A2/A3/A4 impls + real extracts]`

> **⛔ BLOCKED-ON A2/A3/A4 impls (the `places`/`place_categories`/`place_scores` tables + A4's composite) + `wp-acquire-impl` (real extracts).** Declared, not discovered (the A2/A3/A4 lesson). Tasks 1–5 are fixture-executable now (the dump *format*, the re-scorer with an injected fake, precision@k, the report/regression gate on a committed labeled fixture). Task 6 generates the **real** dumps once the pipeline produces real scored+categorized places.

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
- **BLOCKED-ON A2/A3/A4 impls** — the dump reads `places`/`place_categories`/`place_scores` + A4's `composite.score`, none in code yet (A2/A3 are plan-only; A4 is PR #48). Real extracts are `wp-acquire-impl`.
- **Real taxonomy + scoring before real dumps (the A3→A5 ordering fable flagged):** the golden dumps carry `category` (A3) + `score`/`tier` (A4), so the real A3 taxonomy + A4 config must land before the dumps are generated — else Rob labels against provisional categories.
- **Rob hand-labels the real dumps** (morning) — the committed labeled TSVs become the regression baseline.
- **Store shapes:** reads A2 `places` (`place_id, region, name, lat, lon, member_refs_json`), A3 `place_categories` (`category`), A4 `place_scores` (`score, tier, signals_json`).

**Adversarial review (per AGENTS.md gate) — TO RUN before PR:** (1) fixes on the **executed path**; (2) **teeth** — the regression gate reds for a deliberately-worse config; the LLM-off toggle test reds if `llm_on` is ignored; precision@k reds for a mis-ordered ranking; the label loader must skip malformed rows (not crash) and reject invalid labels; (3) **the coherence critic runs the dump-render/parse + re-scorer (fake `score_fn`) + precision@k + report on fixtures** and confirms determinism (byte-identical re-dump), tolerance (edited/malformed TSV), and that the re-scorer's default `score_fn` **is** A4's `composite.score` (no divergent re-implementation — the eval must not lie); (4) confirm the **A6 seam is complete** (arbitrary signal column + on/off + full breakdown) so nothing A5-side is needed later, and that the real-dump task is honestly **BLOCKED-ON A2/A3/A4 impls** (the A2/A3/A4 lesson — no executed-path over-claim).
