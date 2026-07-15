# WP-A3 (Data Audit + Taxonomy) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Materialize the category taxonomy **from evidence, not invention** (§4): an **audit-as-code** tool that deterministically dumps the real Wikidata-P31-class + OSM-tag distribution over the `uk` and `malaysia` extracts; from that audit, derive **5–7 categories** + the **categorization rules** (class/tag → category) + the **refined P31 allowlist/blocklist**; and the **`categorize` stage** that applies the rules to reconciled places, leaving uncovered combos for A6's LLM long-tail.

**Architecture:** A new `mt_pipeline.audit` (the report tool) + `mt_pipeline.categorize` (the stage) under `pipeline/`. The taxonomy + rules + allowlist live as **config** (`pipeline/config/taxonomy.json`, `wikidata_class_allowlist.json`), derived from the audit and header-marked with the report they came from. The audit reads `source_records`; the categorize stage reads the WP-A2 `places` table + `source_records` and writes each place's `category` (an open ≤64-char SAFE_TEXT string — the schema does not enum it, so **the taxonomy config is the source of truth**, enforced by A3's rules).

**Tech Stack:** Python 3.11+ (`mt_pipeline` + `mt-contracts`), stdlib (`json`/`collections`), `pytest`. No new deps.

## Global Constraints

- **Taxonomy is DERIVED from the audit, never invented (§4).** "The taxonomy is a **pipeline deliverable, not a design-time invention**: the first extract run dumps the real distribution of Wikidata classes and OSM tags across both regions; 5–7 categories are derived from that audit, then chips are named from evidence." So this plan ships the **audit tool + the derivation method + the config format**, and a **PROVISIONAL** starter taxonomy that is **explicitly replaced by the real evidence-derived one in the final task** (Task 6). No category or class→category mapping in this plan is authoritative until it is re-derived from the real `uk`+`malaysia` audit.
- **Deterministic + re-runnable (Principle 12).** The audit and the categorize stage are **pure functions of their inputs** — same `source_records`/`places` + same config → **byte-identical** report, category assignments, and allowlist. Sorted iteration everywhere (histograms sorted by `(count desc, key asc)`; categories emitted in config order). **No wall-clock/randomness** in any output value (the report's "generated" provenance is the passed-in `--version`/`--run-id`, not `datetime.now()`); re-running the audit over the same extract produces the same file.
- **`category` is an open capped string, enforced by A3's rules not the schema.** `place.schema.json` allows any ≤64-char SAFE_TEXT string; A3's `taxonomy.json` is the authority on the valid set. The categorize stage emits **only** a label present in `taxonomy.json` (or the single reserved uncovered marker); a coverage test pins that no other string can be produced. `mt_contracts.strip_unsafe_text` guards the label (defence in depth — though our labels are our own, Principle 10).
- **Consume, never re-declare / re-invent (WP-A1 precedent).** A3 **refines** the P31 allowlist A1b shipped as a header-marked bootstrap ("superseded by WP-A3"); it does not fork the ref grammar, the schema, or the text-safety rules — those are A0's. The refined allowlist is a config the Wikidata extractor consumes on its next run (no extractor code change).
- **A3 rules cover the HEAD; A6 covers the long tail (§5.2 stage 4, §8 A6).** The categorization rules deterministically map the **head** of the class/tag distribution (the classes/tags covering most places). A place whose signals match no rule gets the reserved **`"uncategorized"`** marker — the seam WP-A6's LLM category task fills (emitting a label *within* A3's taxonomy, schema-validated on read). A3 builds the seam + measures coverage; it does **not** call an LLM. **`"uncategorized"` MUST NOT reach a published tile or a B8 filter chip (cross-package guarantee — flagged for A7/A6):** it is a schema-valid ≤64-char string, so nothing structural stops publish (A7, stage 5) emitting it, but A6 has no `STAGE_ORDER` slot — so **A7's publish must exclude/remap `uncategorized`, or A6 must be gated to run before publish** for every place. Flagged so A7 inherits it (parallel to the A5-ordering note).
- **§5.5 untrusted signals.** Class QIDs / OSM tags are source-derived and hostile-capable, but they only ever *look up* a category in a trusted config (no interpolation), and a place's coordinates/name were already A1-bounds-checked/scrubbed. A vandalized tag can mis-file one place into a wrong category (bounded, per-place, recoverable) — it can never inject an arbitrary category string (only config labels are emittable) or crash the stage (unknown signal → `uncategorized`).
- **Region-parameterised, both regions (§8 A3, §2).** The audit runs per region and the derivation spans **both `uk` and `malaysia`** (Malaysia stress-tests a thin-enrichment region: fewer HE/plaque signals, so its taxonomy weight rides on P31 + OSM tags).
- **Pipeline placement (§5.2).** `categorize` is stage 4 (`extract → reconcile → score → categorize → publish`), already in `stages.STAGE_ORDER`; A3 fills its body. The immediate-predecessor gate (score-first) is enforced by `run_stage`.

**Ratified (fable, thread `wp/a3`)** — audit-as-code (deterministic report artifact); taxonomy derived from real evidence with a provisional starter replaced in the final task; class/tag→category rules as config with an `uncategorized` A6 long-tail seam; refined P31 allowlist replacing A1b's bootstrap; categorize stage over the A2 places (impl depends on A2 landing); real uk+malaysia audit + histograms as the final task.

---

## File Structure

```
pipeline/src/mt_pipeline/
  audit.py                    # the audit tool: deterministic P31-class / OSM-tag / grade / plaque distribution
  categorize.py               # the categorize stage: apply taxonomy rules to A2 places -> category
  stages.py                   # MODIFY: reconcile-style `categorize` branch calls categorize.run
  store.py                    # MODIFY: add `category` to the places table (or a place_categories table)
  cli.py                      # MODIFY: `mt audit <region>` subcommand + categorize --version wiring
pipeline/config/
  taxonomy.json               # DERIVED (from the audit): categories + class_map + tag_map + precedence + fallback
  wikidata_class_allowlist.json  # REFINE (A1b's bootstrap → evidence-derived allowlist/blocklist)
pipeline/tests/
  test_audit.py
  test_categorize.py
  test_taxonomy_config.py
  fixtures/a3/...
docs/superpowers/reports/
  2026-07-15-a3-audit-uk.md / .json        # committed audit artifacts (Task 6, real data)
  2026-07-15-a3-audit-malaysia.md / .json
  2026-07-15-a3-taxonomy-derivation.md     # the evidence → 5–7 categories rationale (Task 6)
```

---

### Task 1: The audit tool — deterministic distribution dump

**Files:**
- Create: `pipeline/src/mt_pipeline/audit.py`
- Test: `pipeline/tests/test_audit.py`

**Interfaces:**
- Consumes: `source_records` rows (`source`, `props` — `props["p31"]` for `wd`; the tag dict for `osm`; `props["grade"]` for `hehle`).
- Produces:
  - `audit.audit_region(conn, region) -> AuditReport` — `dataclass(region, n_records, by_source: dict[str,int], p31_counts: list[tuple[str,int]], osm_tag_counts: list[tuple[str,int]], grade_counts: list[tuple[str,int]], plaque_count: int)`. Every list is sorted `(count desc, key asc)` — deterministic, **breaking `Counter.most_common()`'s insertion-order-dependent tie ordering** (a tie in `most_common()` alone leaks the DB row order into the report). `osm_tag_counts` keys are `"key=value"` strings counted **only for tags that pass `osm.is_candidate` against the shipped `osm_candidate_tags.json`** — i.e. the audit **consumes** the candidate config (respecting its value restrictions: `tourism∈{attraction,artwork,viewpoint}`, `man_made=obelisk`, …), NOT a hard-coded key list — so a candidate feature's incidental `tourism=hotel` is not counted as taxonomy evidence (consume-not-reinvent). `plaque_count` = the number of `source="plaque"` records (a plaque is a source, not a tag); `grade_counts` from `props["grade"]` on `source="hehle"` records.
  - `audit.render_markdown(report) -> str` and `audit.render_json(report) -> str` — deterministic (sorted) serializations for the committed artifact.

- [ ] **Step 1: Failing test** (`test_audit.py`):
```python
import sqlite3, json
from mt_pipeline import store, audit

def _seed(rows):
    c = store.connect(":memory:"); store.init_schema(c)
    for r in rows:
        c.execute("INSERT INTO source_records (region,source,source_ref,name,lat,lon,props_json,run_id) "
                  "VALUES (?,?,?,?,?,?,?,?)", r)
    c.commit(); return c

def test_audit_counts_p31_and_osm_tags_sorted():
    rows = [
        ("uk","wd","wd:Q1","A",1,1, json.dumps({"p31":"Q16970","label":"A"}), "r"),   # church
        ("uk","wd","wd:Q2","B",1,1, json.dumps({"p31":"Q16970","label":"B"}), "r"),   # church (x2)
        ("uk","wd","wd:Q3","C",1,1, json.dumps({"p31":"Q33506","label":"C"}), "r"),   # museum
        ("uk","osm","osm:node/1","D",1,1, json.dumps({"historic":"castle","name":"D"}), "r"),
        ("uk","osm","osm:node/2","E",1,1, json.dumps({"historic":"castle"}), "r"),
        ("uk","hehle","hehle:9","F",1,1, json.dumps({"grade":"I"}), "r"),
    ]
    rep = audit.audit_region(_seed(rows), "uk")
    assert rep.p31_counts[0] == ("Q16970", 2)                    # most-common class first (sorted)
    assert ("Q33506", 1) in rep.p31_counts
    assert rep.osm_tag_counts[0] == ("historic=castle", 2)
    assert rep.grade_counts == [("I", 1)]
    assert "Q16970" in audit.render_markdown(rep)

def test_audit_is_deterministic_across_row_order_with_TIES():
    # the real determinism risk: Counter.most_common() ties leak insertion order. Build two seeds
    # from the SAME rows in DIFFERENT orders, WITH tie-count classes, and compare DISTINCT reports.
    # (The shipped `render_json(rep)==render_json(rep)` was tautological — same object twice.)
    rows = [("uk","wd",f"wd:Q{i}","N",1,1, json.dumps({"p31":c}), "r")
            for i, c in enumerate(["Q100","Q200","Q300","Q100","Q200","Q300"])]  # three classes, tie count 2
    import random
    a = list(rows); b = list(reversed(rows))
    ra = audit.render_json(audit.audit_region(_seed(a), "uk"))
    rb = audit.render_json(audit.audit_region(_seed(b), "uk"))
    assert ra == rb                                     # byte-identical despite reversed row order (ties sorted key-asc)
```

- [ ] **Steps 2–4:** implement `audit_region` (a single pass over `source_records`, `collections.Counter` per signal, `.most_common()` then re-sorted by `(count desc, key asc)` for determinism) + `render_markdown`/`render_json` (sorted keys). No wall-clock.
- [ ] **Step 5: Commit** — `"Add A3 audit tool: deterministic P31/OSM-tag/grade distribution dump"`

---

### Task 2: Taxonomy config — format, schema, derivation method, PROVISIONAL starter

**Files:**
- Create: `pipeline/config/taxonomy.json`, `pipeline/tests/test_taxonomy_config.py`

**Interfaces / format:**
- `taxonomy.json` (DERIVED — the real values come from Task 6's audit; this task pins the **format** + a **deliberately skeletal**, all-reachable provisional starter so it does not anchor the Task-6 derivation):
```json
{
  "_header": "PROVISIONAL & SKELETAL — replaced by WP-A3 Task 6 from the real uk+malaysia audit. Categories named FROM evidence, not invented (§4). Every category below is reachable by a map entry; the real set (5-7) is derived, not this.",
  "categories": ["history", "religious", "culture", "architecture", "memorials"],
  "uncovered": "uncategorized",
  "precedence": ["wd_p31", "osm_tag", "hehle", "plaque"],
  "class_map": { "Q16970": "religious", "Q33506": "culture", "Q23413": "history" },
  "tag_map": { "historic=castle": "history", "tourism=artwork": "culture", "memorial=*": "memorials" },
  "source_map": { "hehle": "architecture", "plaque": "memorials" }
}
```
- **`source_map` (fixes the dead `precedence` entries the gate found):** `precedence` lists `hehle` and `plaque`, but `class_map`/`tag_map` only cover `wd_p31`/`osm_tag` — so an HE-only listed building or a plaque-only place (a *large* fraction of UK places) would fall to `uncategorized`, structurally inflating A6's workload and corrupting Task 6's coverage STOP-gate. `source_map` gives the `hehle`/`plaque` precedence kinds a real category (derived in Task 6 — a grade-I listing is `architecture`/heritage, a plaque is `memorials`/history). `category_for` consults `source_map` for those kinds. **A `hehle=True` and a `plaque=True` test are added (the shipped tests all hard-coded them `False`, so the dead path had zero coverage).**
- The **derivation method** (documented, executed in Task 6): take the audit's `p31_counts` + `osm_tag_counts` head (the classes/tags covering ≥ ~90% of places); group them into **5–7** evidence-named buckets; every category is reachable by ≥1 `class_map`/`tag_map`/`source_map` entry; the long tail is `uncovered`. `precedence` resolves multi-signal places (`wd_p31` wins by default — the curated class is the strongest taxonomy signal).
- Validation: `test_taxonomy_config.py` pins invariants for any (provisional or real) `taxonomy.json`: 5 ≤ `len(categories)` ≤ 7; `uncovered` not in `categories`; every `class_map`/`tag_map`/`source_map` value ∈ `categories`; **every category is REACHABLE — appears as a value in at least one map (the reverse invariant the gate found missing; else a real taxonomy could declare a category nothing emits)**; every category ≤ 64 chars + SAFE_TEXT; `precedence` ⊆ `{wd_p31, osm_tag, hehle, plaque}`.

- [ ] **Steps 1–5:** write the provisional `taxonomy.json` + `test_taxonomy_config.py` (the invariants above — these hold for the real one too, so they are permanent teeth), run, commit `"Add taxonomy config format + invariants + provisional starter (real categories derived in Task 6)"`.

---

### Task 3: The `categorize` stage — apply rules to A2 places

**Files:**
- Create: `pipeline/src/mt_pipeline/categorize.py`
- Modify: `pipeline/src/mt_pipeline/store.py` (add an **A3-owned `place_categories` table**), `stages.py`, `cli.py`
- Test: `pipeline/tests/test_categorize.py`

**Interfaces:**
- `categorize.category_for(signals, taxonomy) -> str` — the **pure** rule (Task 3a, fixture-testable NOW): given `signals` (`{"wd_p31": {Q…}, "osm_tag": {"key=value",…}, "hehle": bool, "plaque": bool}`), walk `taxonomy["precedence"]`; the first kind with a hit returns a category — `wd_p31`→`class_map`, `osm_tag`→`tag_map` (with a `"key=*"` wildcard), **`hehle`/`plaque`→`source_map`** (fixes the dead precedence kinds). No hit anywhere → `taxonomy["uncovered"]`. **Tie-break pinned unambiguously (gate found it self-contradictory):** within a kind, collect ALL matched categories and return **`sorted(hits)[0]` — the lexically-first CATEGORY** (declaration-order-independent; NOT the lexically-first key).
- **Task 3b (BLOCKED-ON A2 — same declared shape as Task 6):** `categorize.run(conn, region, *, run_id) -> dict` reads the WP-A2 `places` table (place → `member_refs`), joins `source_records` for each member's signals (`props["p31"]`; the candidate OSM tags; `props["grade"]`⇒`hehle`; a member with `source="plaque"`⇒`plaque`), computes `category_for`, writes an **A3-owned `place_categories(place_id PRIMARY KEY, region, category, run_id)`** row per place (NOT a `places.category` column — that would fork A2's table + collide with the `WORKING_STORE_VERSION==2` gate; the additive table is A3's to own, and any version bump is handled additively), returns the `{category: count}` histogram. **`run`, the store table, and the `stages`/`cli` wiring are NOT fixture-executable until A2's `places` lands** — only `category_for` runs now.
- **Stage dispatch seam:** `stages.run_stage` currently only checks the predecessor gate + `mark_stage_complete` (it dispatches to no body — even `extract` runs via `extract_stage.run_extract`). A3 (or A2, whoever lands first) **introduces the body-dispatch convention** in `run_stage` (`categorize` → `categorize.run`), and adds the `audit`/`categorize` CLI entry points reconciled with the real `--region`-flag + positional-stage form (audit is a tool, not a `STAGE_ORDER` stage — a separate `mt audit <region>` subcommand). This is a real change, not a one-line MODIFY.

- [ ] **Step 1 (Task 3a): Failing `category_for` tests** (`test_categorize.py`) — pure, run NOW:
```python
from mt_pipeline import categorize as CZ

TAX = {"categories": ["history", "culture", "memorials", "architecture"], "uncovered": "uncategorized",
       "precedence": ["wd_p31", "osm_tag", "hehle", "plaque"],
       "class_map": {"Q23413": "history", "Q33506": "culture"},
       "tag_map": {"historic=castle": "history", "memorial=*": "memorials"},
       "source_map": {"hehle": "architecture", "plaque": "memorials"}}

def _s(**kw): return {"wd_p31": set(), "osm_tag": set(), "hehle": False, "plaque": False, **kw}

def test_wd_class_wins_by_precedence():
    assert CZ.category_for(_s(wd_p31={"Q33506"}, osm_tag={"historic=castle"}), TAX) == "culture"

def test_osm_tag_wildcard():
    assert CZ.category_for(_s(osm_tag={"memorial=statue"}), TAX) == "memorials"

def test_hehle_and_plaque_map_via_source_map():      # the previously-dead precedence path
    assert CZ.category_for(_s(hehle=True), TAX) == "architecture"
    assert CZ.category_for(_s(plaque=True), TAX) == "memorials"
    # precedence: a hehle place that ALSO has a mapped class takes the class (wd_p31 precedes hehle)
    assert CZ.category_for(_s(wd_p31={"Q23413"}, hehle=True), TAX) == "history"

def test_tiebreak_is_lexically_first_CATEGORY_not_key():
    tax = {**TAX, "class_map": {"Q1": "zebra", "Q2": "apple"}, "categories": ["zebra", "apple"]}
    assert CZ.category_for(_s(wd_p31={"Q1", "Q2"}), tax) == "apple"   # smallest CATEGORY, not key Q1->zebra

def test_uncovered_goes_to_marker_never_crashes():
    assert CZ.category_for(_s(wd_p31={"Q999999"}, osm_tag={"amenity=bench"}), TAX) == "uncategorized"

def test_only_config_labels_are_emittable():
    import itertools
    allowed = set(TAX["categories"]) | {TAX["uncovered"]}
    for p31, tag, h, p in itertools.product(["Q23413","QX"], ["historic=castle","junk=1"], [False,True], [False,True]):
        assert CZ.category_for(_s(wd_p31={p31}, osm_tag={tag}, hehle=h, plaque=p), TAX) in allowed
```

- [ ] **Steps 2–4:** implement `category_for` (Task 3a — pure, run now); then Task 3b `run`/`place_categories`/`stages`/`cli` **once A2's `places` lands**. **Teeth:** `test_only_config_labels_are_emittable` reds on any raw-signal leak; `test_tiebreak_...` reds if the tie-break uses the key not the category; the precedence + `source_map` tests red if a kind is skipped.
- [ ] **Step 5: Commit** — `"Add categorize category_for (precedence + source_map, config-label-only, pinned tie-break); run/store/cli deferred to A2-landing (Task 3b)"`

---

### Task 4: Refine the P31 allowlist from evidence (exclusion = ABSENCE, not a blocklist field)

**Files:**
- Modify: `pipeline/config/wikidata_class_allowlist.json` (A1b's bootstrap → evidence-derived)
- Test: `pipeline/tests/test_taxonomy_config.py` (append)

**Interfaces:** the allowlist is the **recall gate** (§4) the Wikidata extractor consumes — and it reads **only** `data["allow"]` (`wikidata.py::load_allowlist` returns `set(data["allow"])`; a binding is kept iff `p31 in allowlist`). **Exclusion is therefore achieved by ABSENCE from `allow`, not by a blocklist field** — adding a `block`/`blocklist` key would be silently ignored (no extractor reads it), so the plan does **not** pretend a config blocklist "drops" anything (the gate caught this false claim). A3 refines `allow` from the audit's `p31_counts` — including the interesting classes, **omitting** parishes / companies / events / admin boundaries (§4) — and re-marks the header "derived from the WP-A3 audit". The considered-and-omitted noise classes (with their QIDs, from the audit) are recorded as **derivation rationale in the report**, not as a config field.

- [ ] **Steps 1–5:** append a test asserting `allow` is a JSON list of valid QIDs and the header cites the A3 audit; (once Task 6 lands) that the known noise-class QIDs the audit surfaced are **absent from `allow`**; commit `"Refine P31 allowlist from A3 audit (interesting classes in allow; parishes/companies/events/admin omitted)"`. (The **real** `allow` list is filled in Task 6 from the audit; this task pins the format + the absence-is-exclusion policy.)

---

### Task 5: Determinism guards

**Files:**
- Test: `pipeline/tests/test_audit.py` (the audit guard — run NOW) + `test_categorize.py` (the categorize guard — Task 3b, after A2)

- [ ] **Step 1 (now):** the audit determinism guard is `test_audit_is_deterministic_across_row_order_with_TIES` (Task 1) — it builds two seeds from the same rows in reversed order **with tie-count classes** and asserts byte-identical `render_json` across **distinct** report objects (the shipped `render_json(rep)==render_json(rep)` was tautological). Reds if the `(count desc, key asc)` re-sort is dropped and `Counter.most_common()` leaks row order.
- [ ] **Step 2 (Task 3b, after A2 `places` lands):** the categorize guard — run `categorize.run` twice over a shuffled copy of a multi-source `places`+`source_records` fixture and assert identical `place_categories` rows (order-independent). Reds if member/dict iteration leaks order into the assigned category or histogram. Commit.

---

### Task 6: REAL uk+malaysia audit → derive the taxonomy → commit (Rob's demonstrability bar)

**Files:** the committed report + config artifacts. **This task produces the evidence-derived deliverables — no category is authoritative before it.**

**⛔ BLOCKED-ON `wp-acquire-impl` + successful real extracts (declared, not discovered — the same shape as A2's Task 9).** Deriving the real taxonomy needs the real `uk`+`malaysia` `source_records`, which require codex's `wp-acquire-impl` to have run successful extracts. **Executable NOW on fixtures:** Task 1 (audit tool + its tie-count determinism guard), Task 2 (config format + invariants + skeletal starter), **Task 3a** (the pure `category_for`), Task 4 (allowlist format). **BLOCKED:** **Task 3b** (`categorize.run`/`place_categories`/`stages`/`cli`) is blocked on **A2's `places` table landing**; **Task 6** (the real audit + derived taxonomy) is blocked on **`wp-acquire-impl`** (real extracts). Until Task 6, `taxonomy.json`/`wikidata_class_allowlist.json` carry the **PROVISIONAL** skeletal starter — header-marked, never shipped as authoritative. Do not fabricate a "real" audit from fixture data.

- [ ] **Step 1: Run the real audit** over the real extracts codex produced (or produce them: `mt extract uk` / `mt extract malaysia`, then):
```bash
cd pipeline
uv run mt audit uk       > ../docs/superpowers/reports/2026-07-15-a3-audit-uk.md
uv run mt audit malaysia > ../docs/superpowers/reports/2026-07-15-a3-audit-malaysia.md
# (+ the .json evidence artifacts)
```
- [ ] **Step 2: Derive the real 5–7 categories** from the two audits (the method in Task 2): group the head of `p31_counts`+`osm_tag_counts` into 5–7 evidence-named buckets; resolve the top P31 class QIDs to labels (look up the top ~50 QIDs — a bounded, one-time step; record the QID→label map in the derivation doc); write the **real** `taxonomy.json` (`class_map`/`tag_map`/`categories`) and the **real** refined `wikidata_class_allowlist.json`, replacing the provisional starters. Write `docs/superpowers/reports/2026-07-15-a3-taxonomy-derivation.md` — the evidence → categories rationale (which classes/tags map where, and why; the coverage %).
- [ ] **Step 3: Run categorize + report coverage** (Rob's bar):
```bash
uv run mt reconcile uk --run-id r1 --version <v>   # A2 (once landed)
uv run mt score uk --run-id r1                      # A4 (once landed) — categorize is predecessor-gated on score
uv run mt categorize uk --run-id r1
```
Print, per region: the **per-category place counts** (the histogram), and the **coverage** — % of places assigned by rules vs the `uncategorized` long tail (the A6 workload). A coverage far below the audit's head-% is a STOP (the rules don't match the evidence). Commit the reports + the real `taxonomy.json`/`wikidata_class_allowlist.json`.
- [ ] **Step 4: Commit** — `"Add real uk+malaysia audit + evidence-derived 5-7 categories + refined allowlist + coverage report"`

---

## Review Record

**Author self-review** — deliverables map to tasks: the audit tool (T1), the taxonomy config format + invariants + provisional starter (T2), the categorize stage with precedence rules + the `uncategorized` A6 seam (T3), the evidence-refined P31 allowlist (T4), the determinism guard (T5), and the real uk+malaysia audit → derived taxonomy → coverage report (T6). **Nothing invented:** the categories, class/tag maps, and allowlist are all **derived from the real audit** in T6 (§4); this plan ships the tool + method + format + a provisional starter that T6 replaces. Deterministic (sorted, no wall-clock, re-run byte-identical); `category` emitted only from the config's labels (schema is an open string, config is the authority); A6 owns the long tail (the `uncategorized` seam). Consumes A0/A1b (refines the bootstrap allowlist, no re-declaration).

**Ratifications (fable, thread `wp/a3`)** — audit-as-code; taxonomy derived-from-evidence with a provisional-replaced-in-T6 starter; class/tag→category config rules + `uncategorized` A6 seam; refined P31 allowlist; categorize over A2 places (impl depends on A2 landing); real audit + histograms as the final task.

**Cross-package needs surfaced:**
- **Categorize depends on the A2 `places` table** (PR #45, my plan — not yet merged). A3's impl is written against A2's `places` shape and is **blocked on A2's impl landing** (same pattern as A1c/A1d on A1b). The audit itself only needs `source_records` (A1b/c/d, merged).
- **A6 (LLM category long-tail)** consumes A3's `taxonomy.json` + the `uncategorized` places (the coverage report quantifies its workload); A6 emits labels **within** A3's taxonomy, schema-validated on read.
- **P31 class-label resolution** — the audit dumps class **QIDs** (the extractor emits `p31`, the item's own label, but NOT the class's human label — the class QID→label is nowhere in `source_records`), so naming categories from evidence needs an **external lookup off the current data path**. Named mechanism: T6 resolves the top ~50 class QIDs via **a bounded one-shot WDQS `rdfs:label` query (or a small bundled `{QID: label}` class-label snapshot)**, recording the QID→label map in the derivation doc. This is a `wp/acquire` sibling (flag to codex); T6 is blocked on it too.
- **The refined allowlist** is consumed by the Wikidata extractor (A1b) on its next run — no extractor code change, a config swap.
- **A5 ordering (fable):** WP-A5's golden-area dumps carry `category` labels, so the **real evidence-derived `taxonomy.json` (Task 6) must land before A5 generates its dumps** — otherwise A5's golden data + hand-labels reference provisional categories that then change. A5's design should note this dependency (real taxonomy → A5 dumps); flagged so A5 inherits the ordering.
- **Task 6 blocked on `wp-acquire-impl`** (real extracts) — Tasks 1–5 ship on fixtures; the authoritative taxonomy/allowlist are produced only from real data.

**Adversarial review (per AGENTS.md gate) — COMPLETED. 2 critics, one building + running the audit/categorize on fixtures (Python 3.11), one spec/taxonomy-grounding against the real merged code. All shipped tests passed and the teeth bit, but the critics found real coherence gaps — all fixed.**
- **Fixed — HIGH:** `precedence` listed `hehle`/`plaque` with **no map** → HE-only/plaque-only places (a large UK fraction) all fell to `uncategorized`, corrupting Task 6's coverage STOP-gate — **and every shipped test hard-coded `hehle/plaque=False`, so the dead path had zero coverage** → added `source_map` + `hehle=True`/`plaque=True` tests. **My "Tasks 1–5 executable NOW" over-claim** (my own executed-path lesson): `categorize.run` needs A2's `places` (unlanded) → split Task 3 into **3a (pure `category_for`, now)** + **3b (BLOCKED-ON A2)**.
- **Fixed — MED:** the shipped determinism assertion was **tautological** (`render_json(rep)==render_json(rep)` — same object; `Counter.most_common()` ties leak row order) → a real tie-count reversed-order guard across **distinct** reports; the tie-break spec was self-contradictory (sorted-key vs sorted-category) → pinned `sorted(hits)[0]` (lexically-first **category**) + a key-order-vs-category-order test; the "blocklist" config field was **inert** (the extractor reads only `allow`) → exclusion is absence-from-`allow`, noise classes documented as rationale not a field; `places.category` would **fork A2's schema** + collide with `WORKING_STORE_VERSION==2` → an A3-owned `place_categories` table; the reachability invariant was **one-directional** (map⊆cats but not reverse) → added "every category reachable"; the provisional starter shrank to a **skeletal all-reachable** set (dropped un-evidenced `nature`/`oddities`, which could anchor T6); `run_stage` has no body-dispatch + `cli` no subcommands → stated as a real seam A3/A2 introduces.
- **Fixed — LOW:** the audit now **consumes `osm_candidate_tags.json`** (value restrictions) instead of a hard-coded key list; `plaque_count`/plaque-signal pinned (`source="plaque"`); the class-QID→label lookup mechanism named (WDQS/snapshot, a `wp/acquire` sibling).
- **Affirmed (verified):** derived-not-invented (every authoritative value in T6 from real evidence; structural invariants only pre-audit); `category` open-string / config-is-authority with real teeth; A3/A6 split + `uncategorized` seam; allowlist consume-not-fork; determinism (per the corrected test); scope (no scoring/LLM/extractor-code). **Before PR:** re-run Task 3a's `category_for` tests + the tie-count audit determinism + the taxonomy invariants on fixtures; confirm the neutered variants make their tests go red.
