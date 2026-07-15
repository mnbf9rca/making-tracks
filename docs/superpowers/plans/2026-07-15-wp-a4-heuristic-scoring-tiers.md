# WP-A4 (Heuristic Scoring + Tiers) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The `score` stage — a per-place **composite score in [0,1]** from config-driven weights over the §4 heuristic signals, bucketed into **T1–T4 tiers** (integer 1–4). The composite **renormalizes over the signals actually present**, so a place is never penalized for *our* missing data (an empty pageview cache, an unwritten LLM slot) — which is exactly what makes the **Malaysia non-LLM sanity floor** hold. The LLM curiosity signal is one optional weighted slot A6 fills later; A4 computes no LLM value.

**Architecture:** A new `mt_pipeline.score` package. Pure signal functions (`signal → [0,1]`) + a corpus tag-value-rarity pass + a config-weighted composite + tier bucketing — all deterministic. The `score` stage reads the WP-A2 `places` table joined to `source_records.props_json` for each member's signals, writes an **A4-owned `place_scores(place_id, region, score, tier, signals_json, run_id)`** table (the `signals_json` column reserves the LLM slot A6 writes). Weights + tier thresholds live in versioned `pipeline/config/scoring.json`.

**Tech Stack:** Python 3.11+ (`mt_pipeline` + `mt-contracts`), stdlib (`json`/`math`/`statistics`/`collections`), `pytest`. No new deps.

## Global Constraints

- **Composite = weighted sum RENORMALIZED over PRESENT weights (the Malaysia-floor mechanism).** `score = Σ(wᵢ·sᵢ for present i) / Σ(wᵢ for present i)`, clamped to [0,1]. Signals split into: **always-computed** (article, sitelinks, heritage-grade, plaque, image, tag-rarity, class-penalty — a value of 0 means "no evidence", which correctly lowers the score and is NOT the same as absent) and **optional** (`pageviews`, `llm_curiosity` — *absent when the source is unavailable*: an empty/disabled pageview cache, or an A6 slot A6 hasn't written). An **absent** signal drops out of **both** numerator and denominator, so its weight mass renormalizes over the present signals — a place isn't punished for our missing acquisition. Turning `pageviews` + `llm_curiosity` off therefore renormalizes over the 6 remaining signals: the §4 Malaysia floor (heritage + tag-rarity + article + image still rank) holds by construction.
- **Fame is not the product (Principle 2 / §4).** A config-weighted **boost term** deliberately lifts the overlooked-but-verified: `boost = w_boost · (1 − pageview_norm) · evidence_norm`, where `evidence_norm` = the mean over the **present** of {heritage, plaque, article} (0.0 if none present — never `mean([])`, the Malaysia-common case). When pageviews are absent (Malaysia), `pageview_norm` is treated as **0** — and a genuine `0.0` (measured zero fame) and absent are **deliberately equivalent** here (both = "not famous" → both earn the boost). Note (acknowledged, for A5's tuning): heritage/plaque/article are weighted in `base` **and** re-counted in `evidence` — a deliberate double-count that couples `boost_weight` with those signal weights; A5 tunes them together. Big-Ben-style high-pageview places get no boost; a low-fame plaque/heritage place does.
- **`score ∈ [0,1]`, `tier ∈ {1,2,3,4}` (place.schema.json).** `score` is a `number` in `[0,1]`; `tier` an `integer` `1–4` on the wire (`T1 landmark → T4 oddity` are presentation labels). Tiering is `score → tier` via **config thresholds** (deterministic, version-pinned — NOT data-dependent quantiles that shift with the corpus). A5's eval tunes the weights + thresholds; A4 ships defaults.
- **The LLM curiosity signal is A6's, optional, never the sole gate (§4, §8, Principle 13).** A4 runs and is evaluated **before A6 exists** (A4 deps A2 only). The composite treats `llm_curiosity` as an **optional slot** — absent by default (renormalized away), filled later by A6 writing into `place_scores.signals_json`. A4 computes **no** LLM value and leaves exactly the named slot + the config weight; "the LLM is never the sole gate" is guaranteed because the composite is valid and tested with the slot absent.
- **OSM tag-value rarity is A4's own corpus computation (no A3 dependency).** A4 deps A2 only; A1c deliberately carries the **full bounded tag set** in each OSM record's `props` for this. A4 builds a **corpus-wide tag-value frequency** over the region's `source_records`, and a place's rarity signal is higher for rarer tag-values (`rarity = f(1/frequency)`, normalized). Deterministic (a single sorted pass). This is **not** wired to A3's audit.
- **Median pageviews: computed by A4 from A1b's cache, which A4 tolerates EMPTY (§4 floor).** A1b acquires a resumable `(title, window)` pageview cache (disabled by default; live network is codex's `wp-acquire-impl`). A4 **computes the median** from the cache; when the cache is empty/absent/present-but-empty for a place, `pageviews` is **absent** (`None`, renormalized away), never `median([])` and never 0-penalized. **Reader contract (F5 — cross-package, flag to codex/A1b):** `pageviews.py` today has only `acquire`/`window_for` and no reader, and the cached JSON shape is undefined. A4 needs a **pinned cache-entry schema shared with `wp-acquire-impl`** — `{"title", "window": [start,end], "daily": [int, …]}` — plus a new `pageviews.read(cache_dir, title, window) -> list[int] | None` that clamps + **schema-validates on read (§5.5 — even our own stored JSON is untrusted)**; and the stage must thread the region's `snapshot_date` into `window_for` to key the cache. Until that lands, `pageviews` is uniformly absent (the floor path).
- **Deterministic + re-runnable, versioned config (Principle 11/12, §5.6).** Same `places`+`source_records`+`scoring.json` → identical scores/tiers. Sorted iteration; no wall-clock/randomness in any output value. `scoring.json` carries a `version` (§5.6 "scoring config carries versions"); the composite is a pure function of `(signals, config)`.
- **A4-owned output table; store-version coordination (fable carry-note).** A4 writes a **new `place_scores` table** — it does **not** add a `score`/`tier` column to A2's `places` (that would fork A2's schema). **Store-version convention (durable note):** `acquire` (v3, codex), A2's `places`, A3's `place_categories`, and A4's `place_scores` each add schema to `store.py` (`WORKING_STORE_VERSION` today = 2). Whoever lands **each** bumps `WORKING_STORE_VERSION` sequentially and updates the migration; **A4's impl reconciles to whatever version is current at landing** and adds `place_scores` as an additive migration (never a fork of another WP's table). **Migration-ladder gap (F6 — flag):** `store.py` today has **no migration mechanism** — `init_schema` is `CREATE IF NOT EXISTS` + a strict-equality version gate that *hard-raises* on any mismatch. So the first WP to land a new table (**A2**, whose `places` A4 reads) must **introduce the migration ladder** (upgrade an old DB rather than reject it); A4 **extends** that ladder — it must not just `CREATE IF NOT EXISTS place_scores` and leave the strict gate to reject mismatched DBs. This is folded into the BLOCKED-ON-A2 note.
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

**Interfaces:** each is a pure function of a place's **deterministically aggregated** member signals (a `PlaceSignals` dict). Every output is clamped to `[0,1]`. Returns `None` for an **optional** signal that is absent (`pageviews` with no cache; `llm_curiosity` unset) — `None` means "renormalize away", distinct from `0.0` ("computed, no evidence").
- **Member aggregation pinned (F3 — a place has N members; iteration order must not leak, Principle 12):** the `PlaceSignals` builder (Task 6) collapses a place's members deterministically — **union** of tag-values (for rarity), **max** for numeric signals (sitelinks / article-length / pageviews-median), **grade precedence `I > II* > II`** for heritage (the strongest grade wins), and sorted-first for any remaining tie. State this in the builder + a two-members-same-source determinism test.
- `signals.article(sig) -> float` — `0` if no `wp` member; else `min(1, len(extract)/ARTICLE_FULL_LEN)`. **Note (F4): `extract` is capped at `MAX_EXTRACT_LEN = 300` upstream (wikipedia.py), so this is EXISTENCE-DOMINATED — set `ARTICLE_FULL_LEN = 300` and treat a short extract as a stub. True article byte-length is a would-be A1b prop (cross-package — flag, do not pretend the 300-char lead supports it).**
- `signals.sitelinks(sig) -> float` — `min(1, log1p(max(0, n))/log1p(SITELINK_SAT))`. **`max(0, n)` FIRST (F/coh — `log1p(n)` raises `ValueError: math domain error` for `n ≤ −1`; a hostile negative sitelink count must clamp to 0, not crash, §5.5).**
- `signals.heritage(sig) -> float` — grade → weight (`I→1.0, II*→0.7, II→0.5`, other/none→0) from `scoring.json` `heritage_grades`.
- `signals.plaque(sig) -> float` — `1.0` if a `plaque` member else `0.0`.
- `signals.image(sig) -> float` — `1.0` if `wd` `image` present else `0.0`.
- `signals.class_penalty(sig) -> float` — a **multiplier** in `[0,1]` (1 = no penalty) from the P31 class penalty config; applied multiplicatively in the composite (Task 3), NOT summed.
- `signals.pageviews(sig) -> float | None` — median of the place's cached pageviews; **`None` if the cache has no data OR is present-but-empty** (never `median([])`, which raises).
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

def test_heritage_grade_table_exact():                            # was a vacuous range check
    assert S.heritage({"hehle": {"grade": "I"}}) == 1.0
    assert S.heritage({"hehle": {"grade": "II*"}}) == 0.7
    assert S.heritage({"hehle": {"grade": "II"}}) == 0.5
    assert S.heritage({"hehle": {"grade": "???"}}) == 0.0
    assert S.heritage({}) == 0.0                                   # no hehle member

def test_hostile_inputs_clamp_not_crash():
    assert S.sitelinks({"wd": {"sitelinks": 10**9}}) == 1.0        # hostile huge -> clamped
    assert S.sitelinks({"wd": {"sitelinks": -5}}) == 0.0          # negative -> max(0,n) FIRST, no math-domain crash
    assert S.pageviews({"pageviews": []}) is None                 # present-but-empty -> None, not median([]) crash
```

- [ ] **Steps 2–4:** implement per the interface (constants from `scoring.json` in Task 5; hard-code here + read config in the stage). **Teeth:** the None-vs-0 distinction test reds if an optional signal returns 0 when absent (which would wrongly penalize); the clamp test reds on an unclamped signal.
- [ ] **Step 5: Commit** — `"Add pure scoring signal functions (article/sitelinks/heritage/plaque/image/class; optional pageviews/llm -> None)"`

---

### Task 2: OSM tag-value rarity (corpus frequency)

**Files:** Create `pipeline/src/mt_pipeline/score/rarity.py`; Test `pipeline/tests/test_score_rarity.py`

**Interfaces:**
- **`RARITY_KEYS` — a curated, versioned allowlist of CATEGORICAL tag keys** in `scoring.json` (`historic`, `tourism`, `memorial`, `amenity`, `building`, `man_made`, `leisure`, `natural`, …). **Only these keys' `key=value` pairs count for rarity (F2 — the fix for the degenerate signal).** Free-text / identifier keys — `name`, `*_name`, `ref`, `wikidata`, `wikipedia`, `website`, `url`, `image`, `addr:*`, `source`, `operator`, `brand`, `note`, `description` — are **excluded** (they are near-unique across the corpus, so counting them made `freq≈1 → rarity≈1.0` for *every* named feature, collapsing the signal to a constant and breaking one of the four Malaysia-floor discriminators).
- `rarity.tag_value_frequency(conn, region) -> dict[str,int]` — a single pass over the region's `osm` `source_records`, counting `"key=value"` occurrences **only for keys in `RARITY_KEYS`**. Deterministic.
- `rarity.rarity_score(place_tags, freq) -> float` — over the place's `RARITY_KEYS`-filtered tag-values, `max of (1 − freq[t]/max_freq)` (rarest categorical value → ~1.0; ubiquitous → ~0.0). `0.0` if the place has no counted tags. Deterministic (iterate sorted).

- [ ] **Step 1: Failing test** (`test_score_rarity.py`):
```python
from mt_pipeline.score import rarity as R

RARITY_KEYS = {"historic", "tourism", "memorial", "amenity", "building", "man_made", "leisure", "natural"}

def test_rare_categorical_tag_scores_higher_than_common():
    freq = R.tag_value_frequency_from_tagsets(   # (helper for the test; the real one reads the DB)
        [{"historic": "castle"}, {"historic": "castle"}, {"historic": "folly"}], RARITY_KEYS)
    assert R.rarity_score({"historic=folly"}, freq) > R.rarity_score({"historic=castle"}, freq)

def test_identifier_and_name_tags_are_NOT_counted():
    # F2 teeth: a place whose only "rare" tag is a near-unique name/wikidata must NOT score high rarity.
    freq = R.tag_value_frequency_from_tagsets(
        [{"name": "Unique Place A", "historic": "castle"}, {"name": "Unique Place B", "historic": "castle"}], RARITY_KEYS)
    assert "name=Unique Place A" not in freq                     # name excluded
    assert R.rarity_score({"name=Something Never Seen"}, freq) == 0.0   # a name-only place -> 0, not ~1.0
```

- [ ] **Steps 2–4:** implement `tag_value_frequency` (Counter over `osm` props, **filtered to `RARITY_KEYS`**, sorted) + `rarity_score`. **Teeth:** the name/identifier test reds if the full tag set (incl. `name`/`wikidata`) is counted — the degenerate-saturation bug.
- [ ] **Step 5: Commit** — `"Add OSM tag-value rarity (corpus frequency; rarer scores higher)"`

---

### Task 3: The composite (renormalize over present + fame-boost)

**Files:** Create `pipeline/src/mt_pipeline/score/composite.py`; Test `pipeline/tests/test_score_composite.py`

**Interfaces:**
- `composite.score(signal_values: dict[str,float|None], cfg) -> float` — `signal_values` maps each signal name → its value (or `None` if absent).
  - **Base:** `num = Σ cfg.weights[k]·v` and `den = Σ cfg.weights[k]` over **only the additive signals** whose `v is not None` — i.e. `{article, sitelinks, heritage, plaque, image, tag_rarity, pageviews, llm_curiosity}` (**NOT `class_penalty`**); `base = num/den` (0 if `den==0`).
  - **Fame-boost:** `evidence = mean(over the PRESENT of {heritage, plaque, article})` (0.0 if none present — never `mean([])`); `pv = signal_values.get("pageviews") or 0.0` (a genuine `0.0` and absent both mean "not famous" → both get the boost — a deliberate equivalence); `base += cfg.boost_weight·(1−pv)·evidence`.
  - **Class penalty is MULTIPLICATIVE, applied OUTSIDE the renormalized sum (F1 — it cannot penalize as a positive weighted term):** `score = clamp01((base) · class_penalty)` where `class_penalty ∈ [0,1]` (1 = no penalty; a low-interest class like a parish → e.g. 0.3, which strictly lowers the score by a real margin). Return `min(1.0, max(0.0, …))`.

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

def test_class_penalty_multiplies_and_strictly_lowers():
    # F1 teeth: class_penalty is a MULTIPLIER outside the sum, not a positive term. Two places with
    # identical additive signals but penalty 1.0 vs 0.3 -> the 0.3 place ranks strictly below by a real
    # margin. Neuter (fold class_penalty into the additive sum) -> the margin collapses -> this reds.
    cfg = type("Cfg", (), {"weights": {"heritage": 1}, "boost_weight": 0.0})()
    clean = {"heritage": 1.0, "class_penalty": 1.0}
    penalized = {"heritage": 1.0, "class_penalty": 0.3}
    assert C.score(penalized, cfg) == 0.3 * C.score(clean, cfg) < C.score(clean, cfg)

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

- `scoring.json` (versioned, §5.6): `{"version":"1", "weights": {"article":…, "sitelinks":…, "heritage":…, "plaque":…, "image":…, "tag_rarity":…, "pageviews":…, "llm_curiosity":…}, "boost_weight":…, "tiers": {"t1_min":…, "t2_min":…, "t3_min":…}, "heritage_grades": {"I":1.0,"II*":0.7,"II":0.5}, "class_penalties": {"<QID>":0.3}, "rarity_keys": ["historic","tourism","memorial","amenity","building","man_made","leisure","natural"]}`. Note: **`class_penalty` is NOT in `weights`** — it is a multiplier (`class_penalties` map + a default 1.0), applied outside the sum (F1). The `llm_curiosity` weight is present (A6's slot) though A4 never computes its value. `rarity_keys` is the F2 categorical-tag allowlist. Defaults are **provisional — A5's eval tunes them** (Principle 13).
- **`SIGNAL_NAMES` single source of truth (F8):** a module constant `SIGNAL_NAMES = ("article","sitelinks","heritage","plaque","image","tag_rarity","pageviews","llm_curiosity")` (the additive signals) `+ "class_penalty"` (the multiplier), referenced by `signals.py`, the composite, the `scoring.json` weight-key test, and the `signals_json` key test — so a rename can't silently drop a signal from the composite/evidence.
- [ ] **Steps 1–5:** a test asserting `scoring.json` is valid, carries `version`, has a weight for every additive signal in `SIGNAL_NAMES` (incl. `llm_curiosity`, excl. `class_penalty`), `t1_min > t2_min > t3_min`, and `rarity_keys` present; commit.

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

- [ ] **Steps 1–3:** a curated KL fixture of `PlaceSignals` — a few **known-interesting** places (a graded temple with a Wikipedia article + a **rare** categorical OSM tag; a heritage-listed shophouse row) and a few **noise** places (a common `amenity=bench`, an unremarkable node). Score them all with **`pageviews` and `llm_curiosity` BOTH off** (the §4 floor condition). Assert the known-interesting places all outrank all the noise places. **What this test actually guards (corrected — the gate showed the earlier "renormalize-neuter reds this" claim is FALSE):** because the always-computed signals are never absent, turning pageviews+LLM off is a *uniform per-place rescale* — it cannot change the ranking, so a broken renormalization would NOT red this test. What DOES red it is a **floor SIGNAL that fails to discriminate** — e.g. the F2 degenerate tag-rarity (every place scores ~1.0), or a broken heritage/article/image signal — which is exactly the real Malaysia-floor risk (§4: those four signals must rank without pageviews). **The renormalization *mechanism* is guarded by Task 3's `test_absent_signal_renormalizes_not_penalizes`** (single present signal: real `1.0` vs neuter `0.1667`). (WP-A5 does the full precision@k against real hand-labels; this pins floor-signal discrimination on a fixture now.)
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

**Adversarial review (per AGENTS.md gate) — COMPLETED. 2 critics, one building + running the pure signals/rarity/composite/tiers on fixtures (Python 3.11), one spec-fidelity against the merged extractor code. All shipped tests passed and the renormalize + fame-boost teeth bit, but the critics found signal-level defects that would ship a green suite over a ranking that degrades on real data — all fixed.**
- **Fixed — HIGH:** (1) **`class_penalty` was additive** — a positive term blends toward the mean, it can't penalize (§4's "decisive" class exclusion defeated), and no test touched it → made it a **multiplier outside the sum** (`score = base·class_penalty`) + an order teeth test. (2) **tag-value rarity was degenerate** — counting the full tag set, `name`/`wikidata`/`ref` are near-unique → `rarity≈1.0` for *every* named feature, collapsing a Malaysia-floor signal → a **curated `rarity_keys` categorical allowlist** (excludes free-text/identifier keys) + a name-only-→-0 teeth test. (3) **the Malaysia-floor test's teeth claim was FALSE** (my own "neuter-must-change-the-output" lesson): the always-computed signals are never absent, so the pageviews+LLM-off neuter is a *uniform per-place rescale* → ranking invariant → the test can't detect a broken renormalization → **corrected the claim** (the floor test guards floor-*signal* discrimination — it reds on the F2 degenerate rarity; the renormalize *mechanism* is Task 3's guard). (4) **negative sitelinks crashed** (`log1p(n)`, `n≤−1` → `ValueError`) → `max(0,n)` first.
- **Fixed — MED:** member aggregation was unspecified (N members → iteration-order non-determinism) → pinned per-signal (union tags, max numeric, grade `I>II*>II`) + a test; the `evidence` mean crashed on `None` in one wording → "mean over PRESENT of {…}" in both; the heritage grade table was untested (vacuous range check) → exact `I→1.0/II*→0.7/II→0.5` asserts; article-length is existence-dominated (`extract` capped at 300) → reframed, `ARTICLE_FULL_LEN=300`, real length flagged as an A1b prop; the pageview **reader contract** (cache schema + `read()` + §5.5 validation + present-empty→None + window threading) is unpinned → specified + flagged cross-package; the **migration ladder** doesn't exist (strict-equality gate) → A2 introduces it, A4 extends (folded into BLOCKED-ON-A2).
- **Fixed — LOW:** fame-boost double-count + present-0≡absent acknowledged; `SIGNAL_NAMES` single source of truth.
- **Affirmed (verified vs real code):** all 8 §4 signals present + correctly sourced; LLM-optional faithful (A4 computes none; renormalized-away slot; deps A2 only, no A3 import); renormalize teeth (Task 3) + fame-boost order-flip both genuine; config-threshold tiers (not quantiles) the right determinism call; `score∈[0,1]`/`tier∈1–4`; determinism (200 shuffles → 1 score); BLOCKED-ON honesty accurate. **Before PR:** re-run the pure tests + neuters (class_penalty→additive reds; full-tag-set rarity reds the name-only test; boost→0 reverses the pair) on fixtures.
