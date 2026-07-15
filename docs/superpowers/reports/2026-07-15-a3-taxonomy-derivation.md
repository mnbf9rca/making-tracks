# WP-A3 Task 6 — Real Taxonomy Derivation (UK + Malaysia)

**Deliverable:** a complete replacement `pipeline/config/taxonomy.json`, derived **from the real UK + Malaysia audits** per Principle 13 (categories named from evidence, not invented). Every Wikidata P31 label was **verified via `wbgetentities`**, never guessed. Codex wires the JSON + any rule tweaks; this note justifies each category.

## Evidence base

| region | records | sources | notes |
|---|---:|---|---|
| Malaysia | 5,154 | osm 3,417 · wp 1,180 · wd 557 | **zero hehle, zero plaque** — the taxonomy must work on osm+wd alone |
| UK | 624,124 | hehle 379,678 · wd 145,603 · wp 21,604 · osm 59,868 · plaque 17,371 | hehle (listed buildings, grades II/II*/I) is 61% of records |

The provisional skeleton left **75% of Malaysia uncategorized**. This taxonomy brings the residual to **~5% (UK) / ~25% (Malaysia)** — and Malaysia's residual is almost entirely the **1,180 wp-only records (23%)** that carry no Wikidata-P31 or OSM tag to classify (a structural floor, not a taxonomy gap), plus the wd long-tail of `count=1` P31s.

## The 7 categories (each named from what the data actually contains)

1. **religious** — the largest UK cluster: `Q16970 church building` (28,035), `Q108325 chapel` (9,538), `Q2977 cathedral`, Catholic/Protestant church buildings, `Q160742 abbey`, and religious crosses/wells/fonts (churchyard/wayside/high crosses, `Q1371047 holy well`, `Q208820 baptismal font`). Present in Malaysia via `Q44539 temple`, mosques/cathedrals, and `historic=wayside_shrine` (32). OSM `historic=church/chapel/cathedral/monastery/wayside_shrine`.
2. **memorial** — commemorative works, huge in both: `Q575759 war memorial` (6,607), `Q4989906 monument` (5,119/25), `Q5003624 memorial`, `Q179700 statue`, `Q170980 obelisk`, `Q721747 commemorative plaque`, chest tombs/tombstones/mausolea. The **17,371 UK plaque-source records** (blue plaques) map here via `source_map`. OSM `memorial=*` (wildcard) + `historic=memorial/monument`.
3. **archaeological** — ancient & prehistoric remains: `Q839954 archaeological site` (6,465/11), barrows (`Q2046310 bowl barrow` 3,093, round/long/disc barrows), cairns, `Q2330559 standing stone` / `Q193475 menhir` / `Q1935728 stone circle` / `Q101659 dolmen`, hut circles, `Q21751582 deserted medieval village`, Roman structures/roads/villas. OSM `historic=archaeological_site/ruins/tumulus/standing_stone/roman_road/earthworks`.
4. **historic_building** — buildings, structures, heritage vessels & wayside markers: the **379,678 hehle listed buildings** (via `source_map`), `Q23413 castle` (141/70), manors/`Q1343246 English country house`, forts, towers, city gates & walls, mills/kilns, `historic=mine` (industrial heritage), canals/bridges/lighthouses, the large UK **maritime cluster** (`Q11446 ship` 14,529, `Q852190 shipwreck` 5,770, sloops/steamships/submarines) — folded here rather than a UK-only 8th slot (near-empty for Malaysia) — **and the UK wayside-marker cluster** (`Q10145 milestone` 10,351, `Q921099 boundary marker`, `Q80793 sundial`, guidestones/coal-tax posts). Markers are not literally buildings; they have no cleaner home in a 7-category budget and are heritage *structures*, so they are folded here explicitly rather than dropped to uncovered (they'd otherwise cost ~2 pts of UK coverage), and A4 scoring tiers these low-visit-value points down regardless.
5. **museum** — Malaysia's **#1 Wikidata P31** (`Q33506 museum` 164/1,561) plus `Q207694 art museum`, `Q2772772 military museum`, `Q2087181 historic house museum`, national/local/university/transport/maritime museums.
6. **attraction** — visitor & leisure sites, the dominant Malaysia signal: `tourism=attraction` (1,474/5,483), `tourism=viewpoint` (414/1,353), `Q43501 zoo`, `Q194195 amusement park` / `Q740326 water park` / `Q2416723 theme park` / `Q2281788 public aquarium`, gardens, fountains (`Q483453` 558), `Q35509 cave`.
7. **artwork** — public art & sculpture, big in both: `tourism=artwork` (848/9,758) — murals, installations, sculpture. Kept distinct from `attraction` because it is a large (~10.6k combined) and recognizably different discovery category, and it serves **both** regions (unlike maritime).

## Key design calls (justified)

- **Malaysia-first, without hehle/plaque.** Every load-bearing Malaysia signal (`tourism=attraction/artwork/viewpoint`, museums, monuments, temples/shrines, ruins/tombs) maps through `class_map`/`tag_map` — the 0% `source_map` coverage for Malaysia is expected and fine. OSM tag coverage for Malaysia is **~99.9%** (only a handful of `count=1` mis-tags like `historic=crash_site` fall through).
- **Maritime folded into `historic_building`, not its own category.** The UK ship/shipwreck cluster is ~30k records but Malaysia has ~zero; giving it a 7th slot would spend the category budget on a UK-only concern and steal the slot from `artwork` (which serves both). A historic vessel/wreck is a heritage structure, so the fold is defensible; the scoring stage (A4) down-ranks non-visitable Wikidata vessel entries regardless.
- **Precedence `wd_p31 > osm_tag > hehle > plaque`** (the signal that wins when a place has several). A reconciled listed **church** (hehle + osm `historic=church`) resolves to `religious` via `osm_tag` before falling to `hehle`; a listed building with no other signal falls to `historic_building` via `hehle`. Verified against the real `categorize.category_for`.
- **Long-tail stays uncovered by design.** After the review's coverage pass, the mappable *head/shoulder* of the uncovered band was folded in (parish/former churches, milecastle/castrum/bell barrow/stone row, ledger stone/table tomb, yawl, heritage centre — ~1k UK records). What remains uncovered is genuine long-tail and mis-tags: `count=1..2` P31s + junk like `Q1933634 snow`, `Q163740 nonprofit organization`, `Q110161282 toll plaza`, `Q1188866 guard rail` — they map to `uncovered = "uncategorized"`, which A3's coverage STOP-gate and A7 (uncategorized-never-published) already handle.
- **Known category-boundary imprecisions (P31 can't always disambiguate).** `Q179700 statue` / `historic=statue` → `memorial` is a deliberate commemorative-bias call — a purely decorative statue lands in `memorial` rather than `artwork` because the P31 alone can't distinguish (the `tourism=artwork` tag does route true public art to `artwork`). Generic `historic=cross` → `religious` (most bare crosses are churchyard/preaching crosses; qualified `wayside_cross`/`high_cross` are already religious). These are residual-bucket calls, low-volume, and A4/eval can revisit.

## Residual estimate (method + numbers)

Applied this taxonomy back to the audit histograms (a coherence check on the maps): a record is covered if any of its signals maps. `source_map` gives UK a 64% floor (hehle+plaque); wd P31 histogram coverage is **UK ~96% / Malaysia ~78%**; OSM tag coverage is **UK ~99% / Malaysia ~99.9%**. Conservatively treating wp-only records as uncovered:

- **UK: ~5% residual uncategorized** (from ~undefined in the skeleton).
- **Malaysia: ~25% residual** — of which ~23 pts is the wp-only signal-less fraction; the taxonomy-addressable residual is only a few percent (the wd `count=1` tail).

## Verification

- Every Wikidata P31 label in `class_map` was fetched from `wbgetentities` (`props=labels&languages=en`) — no guessed labels.
- The final `taxonomy.json` **loads and passes `categorize.load_taxonomy`'s validation** (5-7 categories, all `class_map`/`tag_map`/`source_map` targets ∈ categories, precedence kinds ∈ `{wd_p31, osm_tag, hehle, plaque}`, SAFE_TEXT labels) and `category_for` returns the intended category for churches, the `memorial=*` wildcard, `tourism=artwork`, ships, museums, `tourism=attraction`, and the hehle/plaque source fallbacks; an unknown P31 → `uncategorized`.

**For codex:** wire `pipeline/config/taxonomy.json` (a drop-in replacement — same schema). No rule changes required; the real `categorize.category_for` consumes it unchanged. If desired, extend `class_map` down the wd long-tail later, but the head+shoulders of both distributions are covered.

## Review record (3-dimensional Workflow gate)

A parallel Workflow reviewed the taxonomy across **miscategorization**, **coverage-honesty**, and **evidence-fidelity**, each verifying against the audits + Wikidata. It confirmed the Principle-13 derivation, the Malaysia zero-hehle/plaque constraint, and the artwork/attraction split are sound, and surfaced 5 MED + several LOW defects — all folded:

- **`historic=cemetery` → memorial** (was `religious` — a cemetery is a burial ground, and it was internally inconsistent with grave/tomb/mausoleum → memorial).
- **Mappable head/shoulder QIDs added** (were wrongly framed as "count=1..2 tail"): parish/former/cemetery churches → religious; milecastle/castrum/Ogham site/bell barrow/stone row → archaeological; ledger stone/table tomb → memorial; yawl → historic_building; heritage centre → museum (~1k UK records).
- **Two contradictions fixed**: `Q1570646 hogback` and `Q918230 Roman villa` → archaeological (they clashed with `historic=hogback`→archaeological and the note's Roman-remains statement).
- **Wayside markers owned** (milestone 10,351 etc. kept in historic_building, explicitly justified rather than silently mislabeled).
- **LOW**: `historic=cross` → religious; `historic=battlefield` → memorial; market cross → historic_building; `historic=crash_site` added; the "Malaysia 100%" claim softened to ~99.9%.

Post-fold: **UK residual ~4%, Malaysia ~25%** (its floor is the 1,180 wp-only signal-less records). The final JSON re-passes `categorize.load_taxonomy` validation.
