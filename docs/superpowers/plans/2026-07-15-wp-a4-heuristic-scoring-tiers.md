# WP-A4 (Heuristic Scoring + Tiers) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The `score` stage — a per-place **composite score in [0,1]** from config-driven weights over the §4 heuristic signals, bucketed into **T1–T4 tiers** (integer 1–4). The composite **renormalizes over the signals actually present**, so a place is never penalized for *our* missing data (an empty pageview cache, an unwritten LLM slot) — which is exactly what makes the **Malaysia non-LLM sanity floor** hold. The LLM curiosity signal is one optional weighted slot A6 fills later; A4 computes no LLM value.

**Architecture:** A new `mt_pipeline.score` package. Pure signal functions (`signal → [0,1]`) + a corpus tag-value-rarity pass + a config-weighted composite + tier bucketing — all deterministic. The `score` stage reads the WP-A2 `places` table joined to `source_records.props_json` for each member's signals, writes an **A4-owned `place_scores(place_id, region, score, tier, signals_json, run_id)`** table (the `signals_json` column reserves the LLM slot A6 writes). Weights + tier thresholds live in versioned `pipeline/config/scoring.json`.

**Tech Stack:** Python 3.11+ (`mt_pipeline` + `mt-contracts`), stdlib (`json`/`math`/`statistics`/`collections`), `pytest`. No new deps.

## Global Constraints

- **Composite = weighted sum RENORMALIZED over PRESENT weights (the Malaysia-floor mechanism).** `score = Σ(wᵢ·sᵢ for present i) / Σ(wᵢ for present i)`, clamped to [0,1]. Signals split into: **always-computed** (article, sitelinks, heritage-grade, plaque, image, tag-rarity, class-penalty — a value of 0 means "no evidence", which correctly lowers the score and is NOT the same as absent) and **optional** (`pageviews`, `llm_curiosity` — *absent when the source is unavailable*: an empty/disabled pageview cache, or an A6 slot A6 hasn't written). An **absent** signal drops out of **both** numerator and denominator, so its weight mass renormalizes over the present signals — a place isn't punished for our missing acquisition. Turning `pageviews` + `llm_curiosity` off therefore renormalizes over the 6 remaining signals: the §4 Malaysia floor (heritage + tag-rarity + article + image still rank) holds by construction.
- **Fame is not the product (Principle 2 / §4).** A config-weighted **boost term** deliberately lifts the overlooked-but-verified: `boost = w_boost · (1 − pageview_norm) · evidence_norm`, where `evidence_norm` = the mean of the independent-evidence signals (heritage, plaque, article). When pageviews are absent (Malaysia), `pageview_norm` is treated as **0** (unknown fame → treated as low-fame → the boost rewards evidence) — aligning the boost with the floor. Big-Ben-style high-pageview places get no boost; a plaque/heritage place with low fame does.
- **`score ∈ [0,1]`, `tier ∈ {1,2,3,4}` (place.schema.json).** `score` is a `number` in `[0,1]`; `tier` an `integer` `1–4` on the wire (`T1 landmark → T4 oddity` are presentation labels). Tiering is `score → tier` via **config thresholds** (deterministic, version-pinned — NOT data-dependent quantiles that shift with the corpus). A5's eval tunes the weights + thresholds; A4 ships defaults.
- **The LLM curiosity signal is A6's, optional, never the sole gate (§4, §8, Principle 13).** A4 runs and is evaluated **before A6 exists** (A4 deps A2 only). The composite treats `llm_curiosity` as an **optional slot** — absent by default (renormalized away), filled later by A6 writing into `place_scores.signals_json`. A4 computes **no** LLM value and leaves exactly the named slot + the config weight; "the LLM is never the sole gate" is guaranteed because the composite is valid and tested with the slot absent.
- **OSM tag-value rarity is A4's own corpus computation (no A3 dependency).** A4 deps A2 only; A1c deliberately carries the **full bounded tag set** in each OSM record's `props` for this. A4 builds a **corpus-wide tag-value frequency** over the region's `source_records`, and a place's rarity signal is higher for rarer tag-values (`rarity = f(1/frequency)`, normalized). Deterministic (a single sorted pass). This is **not** wired to A3's audit.
- **Median pageviews: computed by A4 from A1b's cache, which A4 tolerates EMPTY (§4 floor).** A1b acquires a resumable `(title, window)` pageview cache (disabled by default; live network is codex's `wp-acquire-impl`). A4 **computes the median** from the cache; when the cache is empty/absent for a place, `pageviews` is **absent** (renormalized away), never 0-penalized. So Malaysia (no reliable pageviews) is the normal path, not a special case.
- **Deterministic + re-runnable, versioned config (Principle 11/12, §5.6).** Same `places`+`source_records`+`scoring.json` → identical scores/tiers. Sorted iteration; no wall-clock/randomness in any output value. `scoring.json` carries a `version` (§5.6 "scoring config carries versions"); the composite is a pure function of `(signals, config)`.
- **A4-owned output table; store-version coordination (fable carry-note).** A4 writes a **new `place_scores` table** — it does **not** add a `score`/`tier` column to A2's `places` (that would fork A2's schema). **Store-version convention (durable note):** `acquire` (v3, codex), A2's `places`, A3's `place_categories`, and A4's `place_scores` each add schema to `store.py` (`WORKING_STORE_VERSION` today = 2). Whoever lands **each** bumps `WORKING_STORE_VERSION` sequentially and updates the migration; **A4's impl reconciles to whatever version is current at landing** and adds `place_scores` as an additive migration (never a fork of another WP's table).
- **BLOCKED-ON declarations (up front — the A2/A3 lesson).** A2 is merged as **plan only**: there is **no `reconcile` package or `places` table in code yet** (`store.py` has only `meta`/`source_records`/`stage_runs`; the `score` stage is a wired no-op stub). So: the **pure signal functions + rarity + composite + tiering (Tasks 1–5, 7) are fixture-testable NOW**; the **`score` stage (reads `places`) + the real malaysia run (Tasks 6, 8) are BLOCKED-ON A2 impl landing**; the **pageview signal on real data is BLOCKED-ON `wp-acquire-impl`** (and A4 tolerates the empty cache until then). Nothing claims to run against `places`/real data before those land.
- **§5.5 untrusted signals.** Signal inputs are source-derived; each is clamped to [0,1] (a hostile sitelink count or tag can't push the composite out of range), coordinates/text were A1-scrubbed, and nothing is interpolated. A vandalized signal shifts one place's score/tier (bounded, per-place, recoverable) — it can't produce an out-of-range score or crash the stage.

**Ratified (fable, thread `wp/a4`)** — composite renormalized over present weights (the floor mechanism); fame-not-product boost; LLM as an optional A6-filled slot the composite tolerates absent; A4 computes tag-rarity over the corpus (no A3 dep); pageviews from A1b's cache, empty-tolerant; config thresholds for tiers; A4-owned `place_scores` + store-version-at-landing convention; score stage + real run BLOCKED-ON A2 impl; the Malaysia non-LLM floor as an explicit acceptance test.

---

## File Structure

```
pipeline/src/mt_pipeline/score/
  __init__.py
  signals.py          # pure signal(place_signals) -> [0,1] for each always-computed + optional signal
  rarity.py           # corpus tag-value frequency + per-place rarity
  composite.py        # config-weighted renormalized composite + fame-boost -> score in [0,1]
  tiers.py            # score -> tier (config thresholds) -> int 1-4
  score_stage.py      # the stage: read places+source_records -> compute -> write place_scores  [BLOCKED-ON A2]
pipeline/config/
  scoring.json        # versioned weights + tier thresholds + LLM slot + class penalties
pipeline/src/mt_pipeline/
  store.py            # MODIFY: additive place_scores table (+ version bump reconciled at landing)  [A2-coordinated]
  stages.py           # MODIFY: score branch calls score_stage.run
  cli.py              # MODIFY: score wiring
pipeline/tests/
  test_score_signals.py
  test_score_rarity.py
  test_score_composite.py     # incl. the renormalize-over-present + fame-boost tests
  test_score_tiers.py
  test_score_malaysia_floor.py   # the non-LLM floor acceptance test (KL fixture)
  test_score_stage.py            # [BLOCKED-ON A2]
  fixtures/score/...
```

---

### Task 1: Pure signal functions (each → [0,1])

**Files:** Create `pipeline/src/mt_pipeline/score/signals.py`; Test `pipeline/tests/test_score_signals.py`

**Interfaces:** each is a pure function of a place's aggregated member signals (a `PlaceSignals` dict). Every output is clamped to `[0,1]`. Returns `None` for an **optional** signal that is absent (`pageviews` with no cache; `llm_curiosity` unset) — `None` means "renormalize away", distinct from `0.0` ("computed, no evidence").
- `signals.article(sig) -> float` — `0` if no `wp` member; else a saturating function of `extract` length (`min(1, len/ARTICLE_FULL_LEN)`).
- `signals.sitelinks(sig) -> float` — `min(1, log1p(n)/log1p(SITELINK_SAT))` (log-scaled, saturating).
- `signals.heritage(sig) -> float` — grade → weight (`I→1.0, II*→0.7, II→0.5`, other/none→0) from config.
- `signals.plaque(sig) -> float` — `1.0` if a `plaque` member else `0.0`.
- `signals.image(sig) -> float` — `1.0` if `wd` `image` present else `0.0`.
- `signals.class_penalty(sig) -> float` — a **subtractive** signal in `[0,1]` (1 = no penalty) from the P31 class penalty config (low-interest classes penalized).
- `signals.pageviews(sig) -> float | None` — median of the place's cached pageviews; **`None` if the cache has no data** for it.
- `signals.llm_curiosity(sig) -> float | None` — the value A6 wrote into `signals_json`, else **`None`**.

- [ ] **Step 1: Failing tests** (`test_score_signals.py`):
```python
from mt_pipeline.score import signals as S

def test_article_zero_without_wp_saturates_with_length():
    assert S.article({"wp": None}) == 0.0
    assert 0 < S.article({"wp": {"extract": "x" * 100}}) < 1
    assert S.article({"wp": {"extract": "x" * 100000}}) == 1.0     # saturates at 1

def test_optional_signals_return_None_when_absent():
    assert S.pageviews({"pageviews": None}) is None                # empty cache -> renormalize away
    assert S.llm_curiosity({}) is None                             # A6 hasn't written it
    assert S.image({"wd": {}}) == 0.0                              # always-computed: 0, not None

def test_all_signals_clamped_0_1():
    assert S.sitelinks({"wd": {"sitelinks": 10**9}}) == 1.0        # hostile huge -> clamped
    assert 0.0 <= S.heritage({"hehle": {"grade": "I"}}) <= 1.0
```

- [ ] **Steps 2–4:** implement per the interface (constants from `scoring.json` in Task 5; hard-code here + read config in the stage). **Teeth:** the None-vs-0 distinction test reds if an optional signal returns 0 when absent (which would wrongly penalize); the clamp test reds on an unclamped signal.
- [ ] **Step 5: Commit** — `"Add pure scoring signal functions (article/sitelinks/heritage/plaque/image/class; optional pageviews/llm -> None)"`

---

### Task 2: OSM tag-value rarity (corpus frequency)

**Files:** Create `pipeline/src/mt_pipeline/score/rarity.py`; Test `pipeline/tests/test_score_rarity.py`

**Interfaces:**
- `rarity.tag_value_frequency(conn, region) -> dict[str,int]` — a single pass over the region's `osm` `source_records`, counting `"key=value"` occurrences across the **full bounded tag sets** (A1c carries them). Deterministic.
- `rarity.rarity_score(place_tags, freq) -> float` — a place with tag-values `{k=v,…}` scores by the **rarest** of its tag-values: `max over its tags of (1 − freq[t]/max_freq)` — a value seen once in the corpus → ~1.0, a ubiquitous value → ~0.0. `0.0` if the place has no OSM tags. Deterministic (iterate sorted).

- [ ] **Step 1: Failing test** (`test_score_rarity.py`):
```python
from mt_pipeline.score import rarity as R

def test_rare_tag_scores_higher_than_common():
    freq = {"amenity=bench": 1000, "historic=folly": 1}          # folly is rare
    assert R.rarity_score({"historic=folly"}, freq) > R.rarity_score({"amenity=bench"}, freq)
    assert R.rarity_score(set(), freq) == 0.0
```

- [ ] **Steps 2–4:** implement `tag_value_frequency` (Counter over `osm` props tags, sorted) + `rarity_score`. **Teeth:** rarer > common; empty → 0.
- [ ] **Step 5: Commit** — `"Add OSM tag-value rarity (corpus frequency; rarer scores higher)"`

---

### Task 3: The composite (renormalize over present + fame-boost)

**Files:** Create `pipeline/src/mt_pipeline/score/composite.py`; Test `pipeline/tests/test_score_composite.py`

**Interfaces:**
- `composite.score(signal_values: dict[str,float|None], cfg) -> float` — `signal_values` maps each signal name → its value (or `None` if absent). Compute `num = Σ cfg.weights[k]·v` and `den = Σ cfg.weights[k]` over **only the `k` whose `v is not None`**; `base = num/den` (0 if `den==0`). Add the fame-boost: `evidence = mean(present of heritage, plaque, article); pv = signal_values.get("pageviews") or 0.0; base += cfg.boost_weight·(1−pv)·evidence`. Return `min(1.0, max(0.0, base))`.

- [ ] **Step 1: Failing tests** (`test_score_composite.py`):
```python
from mt_pipeline.score import composite as C

CFG = type("Cfg", (), {"weights": {"article":1,"sitelinks":1,"heritage":1,"image":1,"pageviews":1,"llm_curiosity":1},
                       "boost_weight": 0.0})()

def test_absent_signal_renormalizes_not_penalizes():
    # a place with heritage=1 and everything else absent scores 1.0 (renormalized over the ONE present signal),
    # NOT 1/6 (which a "0 for absent" bug would give). THIS is the Malaysia-floor mechanism.
    v = {"article": None, "sitelinks": None, "heritage": 1.0, "image": None,
         "pageviews": None, "llm_curiosity": None}
    assert C.score(v, CFG) == 1.0

def test_llm_and_pageviews_off_still_scores_from_the_floor_signals():
    v = {"article": 0.8, "sitelinks": 0.2, "heritage": 1.0, "image": 1.0,
         "pageviews": None, "llm_curiosity": None}     # both optional off
    s = C.score(v, CFG)
    assert 0 < s <= 1                                   # a real score from the 4 present signals

def _cfg(bw): return type("Cfg", (), {"weights": {"pageviews": 1, "heritage": 1}, "boost_weight": bw})()

def test_fame_boost_CHANGES_THE_ORDER_of_the_pair():
    # Principle 2 teeth: a low-pageview heritage-graded oddity vs a high-pageview generic thing.
    # WITHOUT the boost the generic thing ranks higher (base 0.5 > 0.3); WITH the boost the oddity
    # overtakes it (0.6 > 0.5). Neutering boost_weight -> the ORDER REVERSES -> this test reds.
    oddity = {"pageviews": 0.0, "heritage": 0.6}          # overlooked-but-graded
    generic = {"pageviews": 1.0, "heritage": 0.0}         # famous-but-empty
    assert C.score(generic, _cfg(0.0)) > C.score(oddity, _cfg(0.0))   # no boost: generic wins
    assert C.score(oddity, _cfg(0.5)) > C.score(generic, _cfg(0.5))   # with boost: oddity wins (order flips)
```

- [ ] **Steps 2–4:** implement. **Teeth:** `test_absent_signal_renormalizes_not_penalizes` reds if absent signals are treated as `0` (the floor-breaking bug); the fame-boost test reds if the boost ignores pageviews.
- [ ] **Step 5: Commit** — `"Add composite score: renormalize over present weights + fame-not-product boost"`

---

### Task 4: Tiering (config thresholds → int 1–4)

**Files:** Create `pipeline/src/mt_pipeline/score/tiers.py`; Test `pipeline/tests/test_score_tiers.py`

**Interfaces:** `tiers.tier_for(score, cfg) -> int` — config thresholds `t1_min > t2_min > t3_min` map `score → {1,2,3,4}` (T1 landmark = highest scores; T4 oddity = the rest). Deterministic, always returns 1–4 for any `score ∈ [0,1]`.

- [ ] **Steps 1–4:** test (`score ≥ t1_min → 1`; boundaries; `0.0 → 4`; every `[0,1]` score → a valid 1–4) + implement. **Teeth:** a score just below a threshold reds if the boundary is `>` vs `>=` wrong; an out-of-band score must still return 1–4 (clamped).
- [ ] **Step 5: Commit** — `"Add tier bucketing (config thresholds -> int 1-4)"`

---

### Task 5: `scoring.json` — versioned weights + thresholds + LLM slot

**Files:** Create `pipeline/config/scoring.json`; Test `pipeline/tests/test_score_composite.py` (append config-load test)

- `scoring.json` (versioned, §5.6): `{"version":"1", "weights": {"article":…, "sitelinks":…, "heritage":…, "plaque":…, "image":…, "tag_rarity":…, "class_penalty":…, "pageviews":…, "llm_curiosity":…}, "boost_weight":…, "tiers": {"t1_min":…, "t2_min":…, "t3_min":…}, "heritage_grades": {"I":1.0,"II*":0.7,"II":0.5}, "class_penalties": {"<QID>":0.3}}`. The `llm_curiosity` weight is present (A6's slot) though A4 never computes its value. Defaults are **provisional — A5's eval tunes them** (Principle 13: weights earn their place by beating the harness).
- [ ] **Steps 1–5:** a test asserting `scoring.json` is valid, carries `version`, has a weight for every signal (incl. `llm_curiosity`), and `t1_min > t2_min > t3_min`; commit.

---

### Task 6: The `score` stage → `place_scores` table  `[BLOCKED-ON A2 impl]`

**Files:** Modify `store.py` (add `place_scores`), `stages.py`, `cli.py`; Create `score/score_stage.py`; Test `test_score_stage.py`

> **⛔ BLOCKED-ON A2 impl landing.** `score_stage.run` reads the WP-A2 `places` table (identity + `member_refs_json`), which does not exist in code yet (A2 is merged as plan only; `store.py` has no `places`). This task lands **after A2's `places`**; the pure Tasks 1–5/7 do not depend on it.

**Interfaces:** `score_stage.run(conn, region, *, run_id) -> dict` — builds the corpus tag frequency (Task 2); for each `places` row, gathers its members' `PlaceSignals` from `source_records.props_json` (via `member_refs_json`) + the pageview cache; computes each signal, the composite (Task 3), the tier (Task 4); writes a **`place_scores(place_id TEXT PRIMARY KEY, region, score REAL, tier INTEGER, signals_json TEXT, run_id TEXT)`** row (`signals_json` records the per-signal values incl. the reserved `llm_curiosity: null` slot A6 later fills); returns a `{tier: count}` histogram. **`signals_json` is bounded like everything we store (fable rider):** a `MAX_SIGNALS_JSON_BYTES` cap (a named `caps.py`-style constant) is enforced on write, and its shape is a **documented soft contract** — the expected keys are exactly the signal names `{article, sitelinks, heritage, plaque, image, tag_rarity, class_penalty, pageviews, llm_curiosity}` (each a `number|null`); A6 writes `llm_curiosity` and is validated on read (§5.5 — even our own stored JSON is untrusted). A test pins the key set + the byte cap. Wired into `stages.run_stage(..., "score", ...)` (predecessor `reconcile` gate already enforced). **`store.py` adds `place_scores` as an additive migration + reconciles `WORKING_STORE_VERSION` to the current value at landing (see constraint).**
- [ ] **Steps 1–5 (after A2):** a stage test over a seeded `places`+`source_records` fixture asserting `place_scores` rows have `score ∈ [0,1]`, `tier ∈ 1–4`, `signals_json` includes the LLM slot, and a **re-run is identical** (determinism). Commit.

---

### Task 7: Malaysia non-LLM sanity floor — acceptance test

**Files:** Create `pipeline/tests/test_score_malaysia_floor.py`; fixtures

**Interfaces:** consumes Tasks 1–5. **Fixture-testable NOW** (pure composite over a hand-built KL golden set — does not need the stage/real data).

- [ ] **Steps 1–3:** a curated KL fixture of `PlaceSignals` — a few **known-interesting** places (a graded temple with a Wikipedia article + a rare OSM tag; a heritage-listed shophouse row) and a few **noise** places (a bare `amenity=bench`, an unremarkable node). Score them all with **`pageviews` and `llm_curiosity` BOTH off** (the §4 floor condition). Assert the known-interesting places all outrank all the noise places (the non-degenerate-ranking floor). **Teeth:** if the composite treated absent optional signals as `0` (breaking renormalization), the floor collapses — the interesting places (which rely on heritage/tag-rarity/article/image) would be dragged down and the ranking degrades; this test reds. (WP-A5 does the full precision@k against real hand-labels; this pins the *mechanism* on a fixture now.)
- [ ] **Step 4: Commit** — `"Add Malaysia non-LLM floor acceptance test (pageviews+LLM off, floor signals rank KL golden fixture)"`

---

### Task 8: Determinism guard + REAL malaysia scored+tiered run  `[BLOCKED-ON A2 impl + real extracts]`

> **⛔ BLOCKED-ON A2 impl (the `places` table) + `wp-acquire-impl` (real extracts).** Same declared shape as A2 Task 9 / A3 Task 6 — not discovered, declared. The pure determinism of signals/composite/tiers is guarded in Tasks 1–7 now; the real run waits.

- [ ] **Step 1 (now):** a determinism test running the composite+tiering twice over a shuffled fixture → identical scores/tiers.
- [ ] **Step 2 (after A2 impl + real extracts):** `mt reconcile malaysia … && mt score malaysia --run-id r1`; a report script prints the **tier histogram** (T1–T4 counts), the **signal-coverage** (% of places with each signal present — expect pageviews ~0% for Malaysia, exercising the floor), and the **re-run-identical** confirmation. Commit `docs/superpowers/reports/2026-07-15-a4-malaysia-scoring.md`.
- [ ] **Step 3: Commit** — `"Add scoring determinism guard + real malaysia tier-histogram report (after A2 impl)"`

---

## Review Record

**Author self-review** — deliverables map to tasks: pure signal functions (T1), corpus tag-rarity (T2), the renormalized composite + fame-boost (T3), tier bucketing (T4), versioned `scoring.json` (T5), the `score` stage → `place_scores` (T6, BLOCKED-ON A2), the Malaysia non-LLM floor acceptance test (T7), the determinism guard + real run (T8, BLOCKED-ON A2 impl + real extracts). The composite **renormalizes over present weights** so absent signals (empty pageview cache, unwritten LLM slot) don't penalize — the §4 Malaysia floor holds by construction; the LLM is one optional A6-filled slot, never the sole gate; tag-rarity is A4's own corpus computation (no A3 dep); tiers use config thresholds; `score ∈ [0,1]`, `tier ∈ 1–4`; deterministic + versioned config. A4 owns `place_scores` (no fork of A2's `places`).

**Ratifications (fable, thread `wp/a4`)** — renormalize-over-present composite (floor mechanism); fame-not-product boost; optional A6 LLM slot; A4 tag-rarity over the corpus; empty-tolerant pageviews; config tier thresholds; A4-owned `place_scores` + store-version-at-landing; BLOCKED-ON A2 impl for the stage + real run; Malaysia floor as an explicit acceptance test.

**Cross-package needs surfaced:**
- **`score` stage + real run BLOCKED-ON A2 impl** (the `places` table + `reconcile` package are plan-only today); **pageview signal BLOCKED-ON `wp-acquire-impl`** (A4 tolerates the empty cache — the floor path).
- **Store-version coordination (fable carry-note):** `acquire`(v3)/A2 `places`/A3 `place_categories`/A4 `place_scores` each add schema; whoever lands each bumps `WORKING_STORE_VERSION` sequentially; A4 reconciles to the current version at landing and adds `place_scores` additively.
- **A5 consumes A4:** the eval harness scores **any `scoring.json`** against hand-labels (precision@k) and runs the **LLM-off** check — A4's config is A5's knob; **A4's defaults are provisional (Principle 13 — A5 is the arbiter).** A5's golden dumps carry `tier`/`score` (and A3's `category`) — so A4 (+ the real A3 taxonomy) should land before A5's dumps.
- **A6 fills the `llm_curiosity` slot** — writes into `place_scores.signals_json`; the composite already weights + renormalizes it. A6 earns its weight only by beating A5's harness.
- **B8 zoom-gates tiers** (city z → T1–T2, street → all) — reads the `tier` A4 emits.

**Adversarial review (per AGENTS.md gate) — TO RUN before PR:** (1) fixes on the **executed path**; (2) **teeth** — the renormalize-over-present test reds if an absent optional signal is treated as `0` (the floor-breaking bug); the Malaysia-floor test reds if the composite can't rank with pageviews+LLM off; the clamp/tier-boundary tests red on out-of-range or off-by-one; the fame-boost test reds if the boost ignores fame; (3) **the coherence critic runs the pure composite/signals/rarity/tiering on fixtures** and confirms determinism (shuffle-identical), `score ∈ [0,1]`, `tier ∈ 1–4`, and that **absent signals renormalize** (not zero-penalize); (4) confirm A4 computes **no LLM value** (only the slot), does **not** depend on A3, and that the stage/real-run tasks are honestly **BLOCKED-ON A2 impl** (Tasks 1–5/7 fixture-executable, the executed-path claim not over-reaching — the A3 lesson).
