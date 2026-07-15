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
- **A3 rules cover the HEAD; A6 covers the long tail (§5.2 stage 4, §8 A6).** The categorization rules deterministically map the **head** of the class/tag distribution (the classes/tags that cover most places). A place whose signals match no rule gets the reserved **`"uncategorized"`** marker — the seam WP-A6's LLM category task fills (emitting a label *within* A3's taxonomy, schema-validated on read). A3 builds the seam + measures coverage; it does **not** call an LLM.
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
  - `audit.audit_region(conn, region) -> AuditReport` — `dataclass(region, n_records, by_source: dict[str,int], p31_counts: list[tuple[str,int]], osm_tag_counts: list[tuple[str,int]], grade_counts: list[tuple[str,int]], plaque_count: int)`. Every list is sorted `(count desc, key asc)` — deterministic. `osm_tag_counts` keys are `"key=value"` strings, counted only for the **candidate** tag keys (`historic`, `tourism`, `memorial`, `man_made`, … — the A1c candidate set, since a place's non-candidate tags are noise for taxonomy).
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
    # deterministic render: re-render twice, byte-identical
    assert audit.render_json(rep) == audit.render_json(rep)
    assert "Q16970" in audit.render_markdown(rep)
```

- [ ] **Steps 2–4:** implement `audit_region` (a single pass over `source_records`, `collections.Counter` per signal, `.most_common()` then re-sorted by `(count desc, key asc)` for determinism) + `render_markdown`/`render_json` (sorted keys). No wall-clock.
- [ ] **Step 5: Commit** — `"Add A3 audit tool: deterministic P31/OSM-tag/grade distribution dump"`

---

### Task 2: Taxonomy config — format, schema, derivation method, PROVISIONAL starter

**Files:**
- Create: `pipeline/config/taxonomy.json`, `pipeline/tests/test_taxonomy_config.py`

**Interfaces / format:**
- `taxonomy.json` (DERIVED — the real values come from Task 6's audit; this task pins the **format** + a clearly-marked provisional starter):
```json
{
  "_header": "PROVISIONAL — replaced by WP-A3 Task 6 from the real uk+malaysia audit (docs/.../a3-audit-*). Categories named from evidence, not invented (§4). 5-7 categories.",
  "categories": ["history", "architecture", "religious", "culture", "memorials", "nature", "oddities"],
  "uncovered": "uncategorized",
  "precedence": ["wd_p31", "osm_tag", "hehle", "plaque"],
  "class_map": { "Q16970": "religious", "Q33506": "culture", "Q23413": "history" },
  "tag_map": { "historic=castle": "history", "tourism=artwork": "culture", "memorial=*": "memorials" }
}
```
- The **derivation method** (documented, executed in Task 6): take the audit's `p31_counts` + `osm_tag_counts` head (the classes/tags covering ≥ ~90% of places); group them into **5–7** human-meaningful buckets; name each from evidence (the class labels / tag semantics); every mapped signal points at exactly one category; the long tail is left for `uncovered`. The `precedence` list resolves a place with multiple signals (`wd_p31` wins by default — the curated class is the strongest taxonomy signal).
- Validation: `test_taxonomy_config.py` pins the **format invariants** that must hold for any (provisional or real) `taxonomy.json`: 5 ≤ `len(categories)` ≤ 7; `uncovered` not in `categories`; every `class_map`/`tag_map` value ∈ `categories`; every category ≤ 64 chars + SAFE_TEXT (`mt_contracts.strip_unsafe_text(c) == c`); `precedence` ⊆ the known signal kinds.

- [ ] **Steps 1–5:** write the provisional `taxonomy.json` + `test_taxonomy_config.py` (the invariants above — these hold for the real one too, so they are permanent teeth), run, commit `"Add taxonomy config format + invariants + provisional starter (real categories derived in Task 6)"`.

---

### Task 3: The `categorize` stage — apply rules to A2 places

**Files:**
- Create: `pipeline/src/mt_pipeline/categorize.py`
- Modify: `pipeline/src/mt_pipeline/store.py` (add `category` column to `places`), `stages.py`, `cli.py`
- Test: `pipeline/tests/test_categorize.py`

**Interfaces:**
- `categorize.category_for(signals, taxonomy) -> str` — the **pure** rule: given a place's `signals` (`{"wd_p31": {Q…}, "osm_tag": {"key=value",…}, "hehle": bool, "plaque": bool}`), walk `taxonomy["precedence"]`; the first signal kind with a `class_map`/`tag_map` hit (supporting a `"key=*"` wildcard for tag keys) returns its category; no hit → `taxonomy["uncovered"]`. Deterministic (within a kind, iterate the mapped keys in sorted order; a place matching two categories within one kind resolves to the **lexically-first category** — documented, deterministic).
- `categorize.run(conn, region, *, run_id) -> dict` — reads the WP-A2 `places` table (each place → its `member_refs`), joins to `source_records` to gather each member's signals (`props["p31"]`, the candidate OSM tags, `grade`, plaque presence), computes `category_for`, writes `places.category`, returns a `{category: count}` histogram (incl. `uncategorized`). Wired into `stages.run_stage(..., "categorize", ...)`; predecessor (`score`) gate already enforced.

- [ ] **Step 1: Failing tests** (`test_categorize.py`):
```python
from mt_pipeline import categorize as CZ

TAX = {"categories": ["history", "culture", "memorials"], "uncovered": "uncategorized",
       "precedence": ["wd_p31", "osm_tag", "hehle", "plaque"],
       "class_map": {"Q23413": "history", "Q33506": "culture"},
       "tag_map": {"historic=castle": "history", "memorial=*": "memorials"}}

def test_wd_class_wins_by_precedence():
    s = {"wd_p31": {"Q33506"}, "osm_tag": {"historic=castle"}, "hehle": False, "plaque": False}
    assert CZ.category_for(s, TAX) == "culture"          # wd_p31 precedes osm_tag

def test_osm_tag_wildcard():
    s = {"wd_p31": set(), "osm_tag": {"memorial=statue"}, "hehle": False, "plaque": False}
    assert CZ.category_for(s, TAX) == "memorials"        # memorial=* wildcard

def test_uncovered_goes_to_marker_never_crashes():
    s = {"wd_p31": {"Q999999"}, "osm_tag": {"amenity=bench"}, "hehle": False, "plaque": False}
    assert CZ.category_for(s, TAX) == "uncategorized"    # A6 long-tail seam

def test_only_config_labels_are_emittable():
    # coverage/teeth: over many hostile signal combos, every output is a config label or the marker.
    import itertools
    allowed = set(TAX["categories"]) | {TAX["uncovered"]}
    for p31, tag in itertools.product(["Q23413","Q33506","QX"], ["historic=castle","memorial=x","junk=1"]):
        out = CZ.category_for({"wd_p31": {p31}, "osm_tag": {tag}, "hehle": False, "plaque": False}, TAX)
        assert out in allowed
```

- [ ] **Steps 2–4:** implement `category_for` + `run` (join places→members→signals) + `store` `category` column + `stages`/`cli` wiring. **Teeth:** `test_only_config_labels_are_emittable` reds if any raw signal string leaks into the output; the precedence test reds if the order is ignored.
- [ ] **Step 5: Commit** — `"Add categorize stage: precedence rules -> category, uncovered A6 seam, config-label-only output"`

---

### Task 4: Refine the P31 allowlist/blocklist from evidence

**Files:**
- Modify: `pipeline/config/wikidata_class_allowlist.json` (A1b's bootstrap → evidence-derived)
- Test: `pipeline/tests/test_taxonomy_config.py` (append)

**Interfaces:** the allowlist is the **recall gate** (§4) the Wikidata extractor consumes; A3 refines it from the audit's `p31_counts`, **explicitly excluding parishes / companies / events / admin boundaries** (§4). Format unchanged (A1b's), header re-marked "derived from WP-A3 audit". A blocklist of the noise classes the audit surfaces (admin/parish/company/event QIDs) is documented so a re-run of extract drops them.

- [ ] **Steps 1–5:** append a test asserting the allowlist is valid JSON of QIDs, the header cites the A3 audit, and (once Task 6 lands) the known noise classes are absent; commit `"Refine P31 allowlist from A3 audit (exclude parishes/companies/events/admin)"`. (The **real** QID lists are filled in Task 6 from the audit — this task pins the format + the exclusion policy.)

---

### Task 5: Determinism guard

**Files:**
- Test: `pipeline/tests/test_audit.py` + `test_categorize.py` (append)

- [ ] **Steps 1–3:** a test that runs `audit_region` + `categorize.run` twice over a shuffled copy of a multi-source fixture and asserts identical reports + identical `places.category` (order-independent). Reds if any `Counter`/dict iteration leaks order into output. Commit.

---

### Task 6: REAL uk+malaysia audit → derive the taxonomy → commit (Rob's demonstrability bar)

**Files:** the committed report + config artifacts. **This task produces the evidence-derived deliverables — no category is authoritative before it.**

**⛔ BLOCKED-ON `wp-acquire-impl` + successful real extracts (declared, not discovered — the same shape as A2's Task 9).** Deriving the real taxonomy needs the real `uk`+`malaysia` `source_records`, which require codex's `wp-acquire-impl` (real acquisition) to have run successful extracts. **Tasks 1–5 are all executable NOW on fixtures** (the audit tool, the config format + invariants, the categorize stage, the determinism guard); **Task 6 runs only after real extracts exist.** Until then, `taxonomy.json`/`wikidata_class_allowlist.json` carry the **PROVISIONAL** starter (Task 2) — clearly header-marked, and never shipped as authoritative. Do not fabricate a "real" audit from fixture data.

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
- **P31 class-label resolution** — the audit dumps class QIDs (the extractor emits `p31` but not the class's human label); T6's derivation resolves the top ~50 QIDs to labels (a bounded one-time lookup, recorded in the derivation doc). Flag: a future audit could join a class-label snapshot to annotate QIDs inline.
- **The refined allowlist** is consumed by the Wikidata extractor (A1b) on its next run — no extractor code change, a config swap.
- **A5 ordering (fable):** WP-A5's golden-area dumps carry `category` labels, so the **real evidence-derived `taxonomy.json` (Task 6) must land before A5 generates its dumps** — otherwise A5's golden data + hand-labels reference provisional categories that then change. A5's design should note this dependency (real taxonomy → A5 dumps); flagged so A5 inherits the ordering.
- **Task 6 blocked on `wp-acquire-impl`** (real extracts) — Tasks 1–5 ship on fixtures; the authoritative taxonomy/allowlist are produced only from real data.

**Adversarial review (per AGENTS.md gate) — TO RUN before PR:** (1) fixes on the **executed path**; (2) **teeth** — the config-label-only test reds if a raw signal leaks into `category`; the determinism test reds if `Counter`/dict order leaks; the taxonomy-invariants test reds on <5 or >7 categories or an off-taxonomy map value; (3) **the feasibility/coherence critic runs the audit + categorize** on real (or realistic) `source_records` in the venv and confirms the report is deterministic (byte-identical re-run) and every emitted `category` is a config label; (4) confirm **no category/mapping is invented in-plan** — the authoritative values are all produced in T6 from the real audit — and that the categorize stage never crashes on an unknown signal (→ `uncategorized`).
