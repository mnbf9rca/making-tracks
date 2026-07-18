# WP-RM — Region manager: hierarchical zone catalog + selection UX + pack lifecycle

**Status:** design (opus). Adversarial-gate → PR to `develop`, `sourcery-review`. Pipeline parts →
`develop`, app parts → `ios`. Thread `p2p/fable__opus`. Builds on: region-index (WP-P, shipped), the
BUILT offline pack store (WP-B7), #131 cover-traffic rulings, and the selection-UX research
(`docs/research/2026-07-17-offline-selection-ux.md`, committed with this PR). Rob's rulings folded
(hybrid selection; extracted hierarchy).

## Why

Rob wants to download **named zones** (not just whole countries), *"predefined zones… higher level than
London"* — a **hierarchy** (country → region → metro/county), plus a custom drag-rectangle path. The
hierarchy is **extracted from data, not authored**, and **declared in config, not per-zone**. This
design covers: the **catalog contract**, the **extraction** that materialises it, the **selection UX**,
**pack lifecycle** on the shipped store, **cover-traffic** interplay, size estimation, and staleness
nudges.

## Grounded facts (recon: contracts/pipeline on `develop`; app pack store on `origin/ios`; cited)

- **Cells = z10 tiles.** `TILE_ZOOM = 10`; tile `x/y ∈ 0..1023` (`caps.py`). A **zone = its set of z10
  cells**; a "cell" is a z10 tile the pipeline already emits.
- **Region-index (`regions.json`, WP-P shipped)** already carries a **`parent`** (hierarchy-ready) plus
  `{id, display_name, parent, bbox, publish_version, basemap_bytes, tile_count, bytes_without_thumbs,
  bytes_with_thumbs}`. **Missing for zones:** a **cell-set**, **admin_level/zone-level**, **name
  translations**, and a **version** — WP-RM extends it (or a sibling `zone-catalog`).
- **Region-config** = `{schema_version, region_id, display_name, bbox, languages, sources, pageviews,
  basemap}` — **[gate — correction] region-config DOES already carry authored `basemap.subregions` +
  `pack_granularity`** (nested under `basemap`; my top-level grep missed them), and those already
  populate `region-index.parent`. So WP-RM's **extracted** zone hierarchy must be **RECONCILED with the
  existing authored subregions** (§1): the extracted catalog is the general mechanism; the authored
  `basemap.subregions` are a hand-declared subset that predates it. **Reconciliation:** the per-country
  `zone_levels` map + extraction **supersede/subsume** manual `basemap.subregions` (extraction is the
  path forward; existing authored subregions become either seed entries or are migrated into the pruned
  catalog) — state this explicitly so the two mechanisms don't both claim the hierarchy. The
  **`zone_levels` level-map is the NEW config field**; `basemap.subregions` is existing.
- **OSM admin boundaries are NOT extracted today.** The OSM extractor captures point places
  (geosearch), not `boundary=administrative` relations/polygons. **Extracting admin boundaries (polygon
  + name + translations + `wikidata` QID + `admin_level`) is a NEW pipeline capability.**
- **The offline pack store is BUILT + content-addressed** (`OfflineRegionStore`:
  `objects/tiles/{sha}.json.gz`, `objects/basemaps/{sha}.pmtiles`, atomic install + rollback, GC of
  unreferenced objects, storage-headroom; background discretionary `OfflineDownloadSession`;
  `updatePlan` reuse-by-sha). **Overlapping zones dedup for free** — a shared cell's tile object is
  stored once and reference-counted. (No `.webp` thumbs yet — WP-IMG-B2 adds that.)
- **#131 cover-traffic rulings (ratified):** sub-region downloads ship with cover-traffic; a decoy is
  cover only if indistinguishable on every axis (spatial spread, timing/order, size/count, edge-reaching,
  location-independent cohort); the privacy win is chunky prefetch + decoys. Numbers are Rob's.

## 1. The zone catalog is EXTRACTED, not authored (D1) — Rob's ruling

- **Zone source = OSM `boundary=administrative` relations** from the acquired snapshot: polygon + `name`
  + name translations (`name:xx`) + `wikidata` QID + `admin_level`. A **new boundary sub-extractor**
  (a relation pass, distinct from the point-place geosearch) captures these into the working store.
- **Per-country level-map in region-config (a few config lines, never per-zone).** `admin_level`
  semantics differ by country, so region-config gains a **`zone_levels`** map declaring which admin
  levels form the tree, e.g. UK `{2: country, 4: region, 6: county}`, Malaysia `{2: country, 4: state}`.
  This is the ONLY human-authored input — a handful of lines per country.
- **The pipeline materialises the catalog:** for each admin relation at a declared level → **rasterise
  its polygon to the z10 cell-set** (rule: **a cell is in the zone iff it INTERSECTS the polygon**
  [gate — not centre-in-polygon: centre-in loses up to ~half a boundary cell of in-zone territory
  offline-dark, and the uniqueness it would buy is **not** load-bearing because overlap is **free via
  content-addressed dedup**; intersects covers the boundary, dedup makes the shared cells cost nothing.
  A boundary cell simply belongs to *both* adjacent zones' cell-sets — fine]. Deterministic + testable.
  → **the zone IS its cell-set**; **parent = the smallest higher-declared-level zone whose polygon
  CONTAINS this zone's polygon** (strict admin containment by area-majority; **tie-break: the parent with
  the greatest area overlap, then the lower `zone_id`** — so a child straddling two parents resolves
  deterministically; a zone with no containing parent is top-level). `size` = the **actual**
  `bytes_with/without_thumbs` summed over the zone's cells
  at publish (not an estimate). **Overlapping zones are free** via B7 content-addressing — a cell shared
  by London and South-East England is one tile object, reference-counted; **state this dedupe
  explicitly** so size math never double-counts a device's on-disk footprint (catalog size is
  per-zone-nominal; installed footprint is the union of cells).
- **Auto-catalog is a PROPOSAL; production is a PRUNE LIST (Rob's gate).** The pipeline emits the full
  extracted catalog; **production config declares which zones ship** (a prune/allow list) — Rob's
  existing sub-region gate becomes *"which of the proposed zones go live,"* not authorship. Production
  sub-region declarations stay Rob-gated; this design ships the **contract + extraction**, he declares
  the instances.

## 2. Catalog contract (D2)

- **`zone-catalog` schema** (extend `region-index` or a sibling; versioned, `min_reader_version`,
  `additionalProperties:false`). Per zone: `{zone_id, parent (nullable = top), admin_level,
  name + name_translations (lang→string), cell_set (the z10 cells — a compact encoding, e.g. run-length
  or a bbox + a bitmap; NOT 4000 loose ints), bbox (for the map frame), bytes_without_thumbs,
  bytes_with_thumbs, publish_version, version}`. Untrusted (§5.5): size-capped, `zone_id`/lang validated,
  `name` plain-text length-capped, cell coords bounded `0..1023`. Written-last/atomic like the
  region-index. (Confirm cell-set encoding with WP-P/codex — a bitmap over the region's tile grid is
  compact and O(1)-testable.)
- **`zone_id` is DERIVED from the OSM relation id + STABLE across republish [gate — it keys packs,
  updates, AND the §5 decoy cohort; an unstable id breaks all three].** `zone_id = osm_r<relation_id>`
  (e.g. `osm_r65606`) — survives re-publish (the OSM relation id is durable), fits `^[a-z][a-z0-9_]{0,63}$`.
  Fallback to the zone's `wikidata` QID (`wd_q...`) where a relation id is known to churn. Never derive it
  from name/bbox/cell-set (those change).
- **Hierarchy is DATA** (parent pointers) — adding/removing zones is a pipeline re-publish, **no app
  release**. New countries add a `zone_levels` config block.

## 3. Selection UX (D3) — hybrid, per the research + Rob

- **(a) Named packs = the PRIMARY UI.** Browse the hierarchy (country → region → metro/county); **one
  tap downloads at ANY level**; **size shown up front** (from the catalog). Best discoverability AND best
  privacy (a popular named zone = a large anonymity set; the boundary is semantic, no partial-coverage
  confusion). This is komoot/Organic-style, which fits our pre-cut-cell model.
- **(b) Drag-rectangle = the CUSTOM path, silently decomposed into cells.** Apple-style corner handles;
  the confirm sheet shows **which pre-cut cells the rectangle resolves to** + the **summed size** +
  (privacy) the decoy cost. **Whole cells only**, with an **optional 1-cell halo** (rounding up doubles
  as privacy padding). Never a raw viewport download — always resolve to the shared cell grid.
- **(c) Grid = FEEDBACK, never input.** The cell grid **visualises coverage/ownership** after selection
  and drives **per-ZONE update/delete** (the built store deletes whole packs, not cells — §4) — but the user **never paints
  cells to select** (the research's clear anti-pattern: cognitive load + the edge problem). Coverage is
  shown as filled cells over the map.
- **Accessibility (#163):** the named list is the accessible primary path (VoiceOver-friendly, Dynamic
  Type); the rectangle/grid are enhancements with accessible size/coverage read-outs, not the only route.

## 4. Pack lifecycle (D4) — CORRECTED: the store's unit is a PACK, not a cell-subset

**[gate — SEV-2: the built `OfflineRegionStore` installs a whole REGION/PACK (a `region_id` + its
`manifest.json` + its tiles + ONE basemap); it has NO cell-subset install, NO per-cell delete, NO
per-cell reference-counting (GC is mark-and-sweep over installed pack manifests; delete is
`delete(region:)`), and NO per-zone basemap slice. The first draft's "resolve to a cell-set → install
cells → per-cell delete/dedup for free" does not exist. Reframed:]**

- **A named zone IS a first-class PACK.** The pipeline publishes each shipped zone as its own
  `region_id = zone_id` with its **own `manifest.json`** listing exactly the zone's cells (+ a basemap,
  below). Installing a zone = installing that pack on the existing store. **Dedup is real but at the
  content-addressed OBJECT level, ACROSS packs:** a cell shared by "London" and "South-East England" is
  one `objects/tiles/{sha}` object referenced by both packs' manifests — the store's existing per-pack
  reference-count keeps it while any installed pack needs it. So dedup/GC **do** fall out of the built
  store — but the **unit is the pack, not the cell**.
- **Download PROGRESS surface [gate — a requirement, not just GC bookkeeping].** A zone/pack download must
  show a **user-facing progress UI** (per-zone %/bytes, cancel/pause) driven by **WP-B10d's progress
  stream** (the same incremental-persist engine) — "in-progress objects" is GC/resume language, distinct
  from this UX. WP-RM-B owns the surface.
- **Delete + GC are PER-ZONE (per-pack) in v1, NOT per-cell [Open flag 4 — the research recommends
  per-cell; per-zone now, per-cell later via WP-RM-B2].** Deleting a zone = `delete(region: zone_id)`; the
  store's mark-and-sweep GC reclaims objects no remaining installed pack references. **The grid feedback
  (§3c) shows per-ZONE ownership + per-ZONE delete** — not per-cell delete (correct §3c: the grid
  visualises which zones are installed, coloured by pack).
- **Basemap [gate — no per-zone slice exists].** There is one atomic basemap per pack today. Either
  (a) a zone-pack **reuses its parent region/subregion basemap** (no new basemap fetched; the size UX
  must reflect that the basemap is shared/already-present), or (b) add **per-zone basemap slicing** to the
  pipeline (new work — `pack_granularity` has no zone tier). Recommend (a); make the size estimate accurate
  either way.
- **The custom-rectangle path needs a STORE EXTENSION [gate — not free].** An arbitrary rectangle is not
  a pre-published pack, and the store can't install an ad-hoc cell-set. Options: (a) a new
  **synthetic-manifest install** (the client assembles a manifest from the catalog's per-cell shas + the
  store installs it as an ad-hoc pack) — real new work; or (b) the rectangle **snaps to / composes
  published sub-zone packs** (coarser). **Flag: the rectangle path is new engine work, not "rides the
  built store".**
- **BLOCKER [gate — installing a zone pack does NOT make it RENDER].** "Named-zone packs work on the store
  as-is" is true only for *install/GC*; **rendering is single-region today** — `MapScreen.selectedRegion`
  drives **one** `TileClient(region:)` pinned to a **country** id, so an installed `london` pack is
  **invisible** to `TileClient("uk")` (it renders nothing). Downloading a zone must feed the map. **New
  named WP (WP-RM-B3): viewport→installed-pack resolution across N packs** — the map, for a viewport,
  resolves tiles from **any installed pack covering it** (not one pinned region), reconciled with
  `MapRegion`/the catalog. This is a real app-architecture change and is on the critical path (a zone pack
  is useless until the map reads it).
- **Incremental-persist — BUILT (#193, WP-B10d) [was a Rob requirement; now merged].** RAM-buffering the
  whole pack was **unacceptable** (the device was **jetsam-killed** at far smaller working sets), and #193
  fixed it: `downloadCurrentRegion` now **streams each verified object to the content-addressed store on
  arrival** (`stageDownloadedTileObject`/`stageDownloadedBasemapObject` → `install`) → constant memory
  bound; an interrupted download **resumes object-granular** via `updatePlan` sha-skip; and GC **RETAINS
  in-progress objects** (`referencedInProgressObjects`). *(Earlier revisions of this bullet described the
  RAM-buffer as current and this as "required rework" — corrected on the #193 merge; the full safety audit
  is §8.)* **Still open:** the background `OfflineDownloadSession` is **dead-wired** (production = foreground
  ephemeral `HTTPTileFetcher`, to preserve single-origin redirect pinning) → **wiring it + relaunch task
  adoption is #197's target** (§8 INV-10), and the §8 INV-1/5/6/7/8/9 engine-hardening gaps are owned by
  the proposed **WP-DL-SAFETY**.
- **Update (Apple resize-and-redownload + auto-update):** a pack records its `publish_version`; a new
  publish → the pack's manifest sha-diffs → fetch only changed cells (reuse-by-sha). Auto-update default
  (WiFi, discretionary), user-toggleable — **and this recurring fetch carries cover-traffic (§5).**
- **Staleness nudge:** installed packs older than the live `publish_version` → a non-blocking "update
  available" nudge (`TileLoadState.updateAvailable`). Blocking only on `min_reader_version` (§5.6).

## 5. Cover-traffic interplay (D5) — apply #131 in its RATIFIED terms

**[gate — SEV-2 corrections: the first draft revived the WITHDRAWN k-anonymity floor and dropped
intersection-resistance. #131/the ratified amendment (item 3) withdrew "anonymity-set size" and replaced
it with a COVER-TRAFFIC REQUIREMENT. This section is reframed in those terms.]**

- **Every sub-country download (named OR rectangle) is a movement trace over the user's real IP → carries
  cover-traffic (#131 item 3), independent of how "popular" a zone is.** There is **no** "named zones are
  a large anonymity set, so minimal decoys" argument — that is the retired reasoning; do not use it. The
  privacy axis is **precision** (a rectangle can pinpoint a street; a county is county-precision), not
  popularity.
- **Decoys must be INTERSECTION-RESISTANT (imported verbatim from #131):** a **fixed cohort per session,
  NOT fresh-random per fetch** (else a longitudinal attacker intersects candidate sets and recovers the
  real mosaic), **spread**, **location-independent**, size/count/timing-indistinguishable. **A pack's
  decoy cohort must be STABLE across its update fetches.**
- **The recurring UPDATE path needs cover-traffic too [gate — the biggest leak]:** §4's auto-update
  re-fetches the pack's **real** changed cells on every `publish_version` bump — a recurring, cell-granular
  exposure of exactly your mosaic. The sha-diff/auto-update fetches **must carry the same cover-traffic**
  (the stable cohort) as the initial download; it is precisely the recurring trace #131 item 3 targets.
- **Budget keys off a real precision/exposure signal, not "named":** a rectangle mosaic scales the decoy
  budget with cell-count/distinctiveness; **a small/rare named zone (an extracted county/metro can be
  low-population) is NOT automatically safe** — key its budget off an actual signal (population, or the
  amendment-item-4 aggregate download count), with a **small-zone threshold below which a named zone is
  treated like a distinctive selection.** The threshold + all decoy **numbers** are **Rob-gated #131
  parameters** — WP-RM applies the mechanism, sets no number.
- **The confirm sheet surfaces the cost honestly** (a specific selection costs more decoy traffic; the
  1-cell halo is free padding). **Do NOT assert "named = the privacy-preferred default" unconditionally**
  — it holds for large named zones, not small ones.

## 6. Delta updates (D6) — Rob REQUIREMENT: no "GB every time"

**A pack bundles the WHOLE offline experience [Rob ruling: "a bundle must contain EVERYTHING needed for
that region offline. Perhaps let users choose not to download images. But everything else."]:**
**MANDATORY** in every pack = **place tiles + basemap + description sidecars**; **OPTIONAL** = the
**"include images" component = image-index sidecars + thumbs together** [gate — reconciliation: the
relayed ruling put image-index in MANDATORY, but an image-index entry is **useless offline without its
thumb** (and the card cost model bundles image-index in `bytes_with_thumbs`), so a without-images pack
carries **neither** — image-index rides *with* thumbs as the one declinable unit, not "everything else."
**Flagged to fable** as a refinement of the mandatory/optional split]. See the **Offline completeness invariant (§7)** for the full runtime-asset
audit (glyphs, world tier, sprites).

**[gate correction — where the sha-list lives]:** the tile `manifest.json` is **frozen**
(`schema_version const 1`, `additionalProperties:false`) and **cannot carry new content types** — only
tiles + basemap ride the manifest. **All the added content (thumbs / description + image-index sidecars /
search index) is `{filename, sha256, bytes, schema_version}`-listed in the versioned PACK-DESCRIPTOR
file** (the new schema #131 §6 mandates — sidecars "cannot ride the manifest"). So "sha-listed" below
means **manifest (tiles/basemap) + pack-descriptor (everything else)**; `updatePlan` sha-skips over both.
**Each content type must be DELTA-capable** — the mechanism per type:

- **Place tiles — delta FREE (protect it).** Cells are content-addressed `objects/tiles/{sha}`;
  an unchanged cell is the **same sha → skipped** by `updatePlan` on any refresh. **State this as a
  protected invariant:** a re-publish never re-downloads unchanged place cells. (This is exactly the
  content-addressing delta Rob wants preserved — call it out so no future change breaks it.)
- **The GAP is the MONOLITHIC basemap `pmtiles`** — one whole-file archive per pack; today **any refresh
  re-downloads the entire GB** (Rob's "GB every time" fear). A basemap delta strategy is required. Two
  options, argued:
  - **(a) Range-based partial `pmtiles` sync.** `pmtiles` is a single archive addressed by internal byte
    ranges (natively HTTP-range-friendly). On update, diff the new vs old archive directory → fetch only
    changed byte ranges. **Verdict: fragile** — a re-cut basemap typically **reshuffles tile order/offsets**
    (pmtiles isn't append-only), so ranges don't align and the "diff" degrades to a near-full re-download
    unless the pipeline emits **byte-stable, deterministically-ordered** archives (a strong new pipeline
    constraint). It's also a **separate CDN/decoy pattern** (range requests vs whole-object GETs) — harder
    to cover-traffic uniformly.
  - **(b) Per-cell content-addressed basemap objects (RECOMMENDED).** Cut the basemap into per-z10-cell
    objects (`objects/basemap/{sha}`), content-addressed on the **same grid as place tiles** → basemap
    deltas become the **identical free hash-diff**: an unchanged basemap cell = same sha = skipped.
    **[gate — the z7–9 mid-zoom gap]:** z0–6 is app-bundled (world tier), z≥10 fits the cell grid, but
    **z7–9 (mid-zoom) has no home** — it can't ride z10 cells and isn't in the world tier. Assign it:
    ship z7–9 as **a small shared per-region object** (content-addressed, one per region, delta-free like
    a cell) fetched with the first pack of that region — or extend the app-bundled base to z0–8 if the
    size is trivial. Pin z7–9's home before claiming the basemap deltas end-to-end. This
    **unifies the store** (basemap cells are objects like tile cells → the incremental-persist + resume +
    dedup + cover-traffic cohort all apply uniformly), and directly delivers Rob's "no GB every time."
    **Cost / the key feasibility fork:** MapLibre renders a **single `pmtiles://` source**, so per-cell
    objects mean the app must **render the basemap from the per-cell object grid** (a local tile source,
    or reassemble) instead of one pmtiles file — this splits into a **pipeline cut (WP-RM-P)** and an
    **app basemap-source render change (WP-RM-G)**, the latter being the load-bearing MapLibre feasibility
    fork (single-`pmtiles://`-source → per-cell-object grid). **CDN/cover-traffic:** per-cell basemap
    objects are whole-object content-addressed GETs → **the same decoy cohort as place cells** (no new
    channel, uniform), which (a) is not.
  - **Recommendation: (b)** — it makes the basemap delta *free* on the content-addressing already in place,
    unifies the store + cover-traffic, and is the honest answer to "GB every time"; (a) only helps under a
    byte-stable-pmtiles constraint and fragments the CDN/decoy story. Confirm the app basemap-source change
    is acceptable (or basemap-as-many-small-pmtiles as a middle path).
- **Image thumbs — delta FREE.** Thumbs are already content-addressed `thumbs/{sha}.webp` (WP-IMG-B2), so
  they **inherit the sha-diff**: an unchanged photo = same sha = skipped; only new/changed thumbs fetch.
  Bundle them in the pack (the WP-IMG-B2 pack extension) and they delta like place tiles.
- **Description sidecars — delta needs per-tile SHA entries.** The `descriptions/10/{x}/{y}.json` sidecars
  (codex4 #173, MERGED) are per-tile files, not content-addressed blobs — so to delta them, the
  **pack-descriptor must carry a per-sidecar `{sha, bytes}` entry** (the way `manifest.tiles[]` carries
  per-tile shas for place tiles), so an unchanged description tile is sha-skipped and only changed ones
  re-download. **State this as a pack-descriptor requirement** (the description-index files join the
  descriptor's sha-listed content set). Same for the image-index sidecars.
- **Net:** every pack content type is a **sha-listed object** — but mind the listing home [gate — N1]:
  the frozen `manifest` (`const 1`, `additionalProperties:false`) holds only **z10 place tiles**
  (`manifest.tiles[]`) + the **single** legacy `manifest.basemap` object. **The N per-cell basemap
  objects + the z7–9 per-region object + all sidecars (thumbs/description/image-index/search) therefore
  ride the versioned PACK-DESCRIPTOR, NOT the manifest** (per-cell basemap cannot fit the manifest's one
  basemap slot). *(Alternative: a `manifest` v2 with a `min_reader_version` bump to carry basemap-cells —
  heavier; recommend the pack-descriptor.)* With that, the whole pack deltas uniformly via `updatePlan`
  sha-skip, streams to disk incrementally, and shares one cover-traffic cohort. No content type
  re-downloads whole.

## 7. Offline completeness INVARIANT (D7) — Rob requirement

**The invariant (→ an acceptance test in every build WP):** *a fresh install + ONE downloaded bundle +
airplane mode = a fully working region* — map + **labels** + place cards + **blurbs** + (if opted) photos,
with **zero** network. If anything the map needs at runtime is not in the bundle or app-shipped, offline
is broken. Audit of the completeness set:

- **Place tiles, basemap(-cells), description sidecars** — in the pack, **mandatory** (§6).
- **Image-index sidecars + image thumbs** — the **optional "include images" unit** (§6, N2 fix — the
  image-index rides *with* thumbs, not mandatory). **Without-images acceptance branch:** a without-images
  pack renders the full map + cards with **blurbs + attribution, no photos** — the invariant holds sans
  photos (which are the one declinable component).
- **GLYPHS / fonts [gate — the hidden runtime leak].** Map labels are rendered from glyph PBFs **fetched
  at runtime** from `tiles.making-tracks.app/global/fonts/{fontstack}/{range}.pbf` (`PaperStyle.swift:2`)
  — so **offline, region labels break** unless glyphs are local. Glyphs are **GLOBAL** (one Noto Sans
  fontstack, not per-region), so the right answer is **bundle-ONCE, app-side** (ship the glyph PBFs in the
  app binary, or a one-time global asset download cached globally) — **NOT per-pack** (which would
  duplicate a global asset in every bundle). **New work: an offline-glyph story** (app-ship or
  global-once); flag the multi-language glyph range for Malaysia (Jawi/Arabic) so the shipped set covers
  the labelled scripts.
- **World basemap z0–6** — already **app-bundled** (region-model §2); state it (the offline world tier is
  present without a pack).
- **Sprites / category icons** — **SF Symbols, app-side** (WP-ICONS) — no remote sprite → offline-fine.
  State it (no sprite URL in the style).
- **The place card's image/description attribution + links** — the credit text is in the sidecars (in the
  pack); the outbound *links* (Wikipedia/CC) simply don't open offline — acceptable (the credit renders).

**Acceptance test (build WPs), BOTH branches:**
- **With images:** install → download one bundle *with images* → airplane mode → the region renders with
  labels, pins with category icons, cards with **photos + blurbs + attribution**.
- **Without images:** download the *same bundle without images* → airplane mode → the region renders with
  labels, pins, cards with **blurbs + attribution, NO photos** (and no orphan image-index / no online
  image fetch attempt).
Neuter any one *mandatory* completeness component → the test goes red; dropping the *optional* images
must NOT break the without-images branch.

## 8. Download safety contract (D8) — Rob commission: one testable contract

The offline-download safety conditions, scattered across #193 (WP-B10d engine) / #190 / #177 / the open
#196 / #197, stated **once** as ten invariants with a today-vs-target marker, evidence, an owning WP for
each gap, and the acceptance test that pins it. **Audited against merged `origin/ios`
`Sources/MakingTracksTiles/MakingTracksTiles.swift`** (post-#193/#190) — not against summaries; where the
audit contradicted the commission's framing it is marked **[framing correction]**. Status legend:
✅ satisfied · ◐ partial · ❌ violated · ▷ target (unbuilt, owned).

- **INV-1 Object atomicity — ◐ effectively satisfied, ASYMMETRIC [framing correction].** *An object is
  verified-in-store or absent; no readable partials.* Objects are content-addressed by **expected** sha
  (`tileObjectURL` L1975, `basemapObjectURL` L1979). **Basemap = true verify-then-rename**
  (`prepareVerifiedBasemapObject` L2011 hashes a `.pmtiles.tmp`, `movePreparedBasemapObject` L2031 renames
  only on pass). **Tiles = write-to-final-THEN-verify** (`writeVerifiedTileObject` L1983 does
  `data.write(.atomic)` to the *final* path, then verifies; a sha mismatch throws but **leaves the
  mis-sha'd file at its final name**). It is safe only because **every consumer re-verifies sha**
  (`loadTile`→`TileCodec.decode` L2830; `install`/`updatePlan` re-verify L1428/L1869) and the bad object
  self-heals on retry — not because the write was atomic-correct. **Gap/owner:** mirror the basemap's
  verify-then-rename for tiles → **WP-DL-SAFETY** (low severity). **Test:** stage a tile whose bytes match
  but sha does not; assert the stage throws **and** `objects/tiles/{sha}.json.gz` does not exist after
  (fails today).
- **INV-2 Resume across every interruption class — ✅ satisfied (object-granular).** *Pause/crash/kill/
  net-drop/background/power-loss all degrade to object-granular resume; only explicit cancel discards.*
  Resume is driven by what is already in-store: `updatePlanLocked` (L1860) skips present objects and fetches
  only the rest; fetched objects live in the shared content-addressed `objects/` tree and survive process
  death; the `in-progress/{region}/{pv}/pack-index.json` marker (`beginDownload` L1372) keeps them
  GC-referenced. **Pause** throws `downloadPaused` (L1124) and is *not* caught as cancel (L1298) → intact;
  **cancel** → `discardDownload` (L1405) removes the marker + GCs. **The one non-guarantee is SUB-object
  resume** (a half-streamed basemap restarts from zero) — that is INV-4, not a resume-logic defect.
  **Test:** stage N of M tiles, rebuild the downloader, assert `reusedTileCount == N` and only `M−N`
  fetches; pause → marker present + re-run completes; cancel → marker gone.
- **INV-3 Idempotence via content-addressing — ✅ satisfied.** *Re-running identical content is a no-op.*
  Sha-addressed names (L1975/L1979) + skip-if-present at every layer (`updatePlanLocked` L1868;
  `writeVerified*` early-return L1985/L2006; `movePreparedBasemapObject` no-op L2033). **Test:** run
  `downloadCurrentRegion` twice against one manifest with a call-counting fetcher; assert **zero** fetches
  on the second run.
- **INV-4 Chunking bound — ❌ VIOLATED by the basemap; the per-cell strategy (§6) is the SAFETY fix, not
  just a delta optimisation.** *No single UNRESUMABLE transfer unit above a small threshold.* Tiles satisfy
  it naturally (≤1 MiB, L358). The **basemap is one monolithic `.pmtiles`** fetched by a single
  `session.download(for:)` (L143/L1279) with **`Basemap.validate` permitting ~3 GB** (L384) and **no resume
  data captured** on interruption → a drop at 99% restarts the entire multi-GB transfer. **This is the same
  object §6 reframes for *delta*; state it here as a SAFETY requirement too** — an unresumable multi-GB unit
  is a safety defect independent of bandwidth. **Gap/owner:** §6 option (b) **per-cell content-addressed
  basemap objects** (z10 grid, each ≤ the tile bound) — the **pipeline cut → WP-RM-P** (+ the z7–9 shared
  mid-zoom object) and the **app render change → WP-RM-G** (the MapLibre single-`pmtiles://`-source →
  per-cell-grid fork, §6b). **Test:** with a basemap object >
  threshold and a fetcher failing at 50%, assert the retry does not re-transfer the fetched bytes (fails
  today); post-fix, assert the basemap plans as N per-cell objects each ≤ the tile bound.
- **INV-5 GC soundness — ◐ partial; MORE gaps than the one known [framing correction].** *Never collects
  installed- or live-in-progress-referenced objects; always eventually collects abandoned staging.* The
  **mark** side is sound: `referencedObjects` (L2120, all installed `pack-index.json`) ∪
  `referencedInProgressObjects` (L2138, all live in-progress) are protected before the sweep. The **sweep**
  is too narrow — it cleans only `objects/tiles/*.gz` and `objects/basemaps/*.pmtiles` by exact extension
  (L2116, filter L2162), so it **never sweeps: (1)** crash-stranded `objects/basemaps/*.pmtiles.tmp` (the
  #193 residual — confirmed), **(2)** `root/tmp/{uuid}` install temp/backup dirs (L1432, cleaned only on
  the in-line success/error paths, never by GC), and GC **(3) never runs at plain app launch** (only on
  install-success / discard / delete), so a *killed* download's orphans linger until the next such op.
  **Gap/owner:** add a launch-time + `beginDownload` sweep of `*.pmtiles.tmp` and `root/tmp/*` →
  **WP-DL-SAFETY**. **Test:** drop a `deadbeef.pmtiles.tmp` + a `root/tmp/{uuid}` dir, trigger GC, assert
  both gone (fails today); positive control — an in-progress pack-index's tile sha survives GC (passes).
- **INV-6 Crash-window consistency — ✅ satisfied for reader consistency (single-writer).** *The store is
  consistent at every instant, incl. mid-install and mid-GC.* Install writes+verifies all objects first
  (L1438), builds a temp pack dir, renames `temp→final`, and **only then flips the `current-pack.json`
  pointer** (L1461); readers resolve exclusively through `installedCurrentPackLocked` (L1765), so a
  half-moved pack is invisible; a thrown error restores the backup (L1472). All mutations + GC run under one
  `NSLock` (L2233), GC **inside** the install lock (L1467). **Residual (→ INV-5's orphan sweep):** a crash
  *between* `temp→final` and the pointer write leaves a well-formed but unreferenced pack dir (harmless —
  invisible, objects retained — but uncollected); `NSLock` is in-process only (fine on single-instance iOS;
  would break under an app-extension writer). **Owner:** WP-DL-SAFETY (orphan-dir sweep). **Test:** fault
  after `temp→final` but before the pointer write; assert `installedPublish` still returns the *previous*
  version and the store reads.
- **INV-7 Disk safety — ◐ partial: no corruption on ENOSPC, but a raw error not a graceful pause.**
  *Headroom checked incl. transient peaks; ENOSPC mid-download → resumable pause, never corruption.*
  Headroom is checked **once** before `beginDownload` (`hasHeadroom(requiredBytes: plan.bytesToFetch…)`
  L1248, static 512 MiB reserve L1011) — **not per-object, and it does not model the 2× staging peak**
  (URLSession temp + the `.atomic` write both hold a copy; `stageDownloadedTileObject` also reads the whole
  file into memory L1386). On **ENOSPC mid-write** the atomic write throws `NSFileWriteOutOfSpaceError`
  (all-or-nothing → **no partial/corrupt object**), which is not `downloadCancelled` → rethrown without
  discard → the marker + staged objects survive → **resumable**. So: no corruption ✅, but it surfaces as an
  opaque throw, not a "paused" state, and there is no transient-peak accounting. **Gap/owner:** per-object
  headroom re-check for the 2× peak + map ENOSPC → resumable pause → **WP-DL-SAFETY** (the per-cell basemap,
  §6/WP-RM-P, also shrinks the peak). **Test:** inject an ENOSPC writer at object k; assert (i) no
  partial/corrupt object at its final path, (ii) marker survives, (iii) a re-run with space resumes reusing
  0..k−1.
- **INV-8 Concurrency — ◐ partial; enforcement is UI-ONLY today [framing correction — no review threads
  exist to cite].** *Parallel regions isolated; double-start of the same region impossible;
  delete-during-download defined.* **Different regions:** isolated (separate markers; shared objects written
  under the lock, idempotent). **Same-region double-start:** **no ENGINE guard** — `downloadCurrentRegion`
  (L1234) has no single-flight; the *only* guard is the **OPEN #196** UI (`startDownload` tracks one
  `activeDownloadID` in MapScreen), i.e. per-view, not engine-wide. **Delete-during-download:** **racy** —
  `deleteLocked` (L1927) removes the in-progress marker then GCs, so a concurrent download's staged objects
  can be swept and its later `install` fails verification; #196 adds `discardInProgressDownloads(region:)`
  for *cooperative* cleanup, not mutual exclusion. **(The commission asked to cite #196/#197 "review
  findings" as the enforcement tests — there are NONE: both PRs have 0 review comments, labels never
  applied. The guards are the PRs' own code + tests, not review threads.)** **Gap/owner:** push a per-region
  single-flight lease + a defined delete-vs-download precedence **into the engine** (not MapScreen) →
  **WP-DL-SAFETY**, with **#196** as the natural UI consumer. **Test:** (i) start two downloaders for one
  region → the second is rejected/coalesced; (ii) `delete` while k objects are staged → defined outcome
  (clean download failure OR delete refused) and the store never references a GC'd object.
- **INV-9 Honest progress — ◐ satisfied only in the OPEN #196 UI; the engine has no status [framing
  correction].** *A paused download reports "paused", never "downloading"/fabricated progress.* The engine's
  `OfflineRegionDownloadProgress` (L1062) carries bytes/objects/fraction **but no status field** — pause is
  an out-of-band throw. **#196** reconstructs honest status in MapScreen (`downloadPaused` → a distinct
  `pausedRegion` state + `.paused` row, diff L441/L503), and no value is fabricated (`fractionComplete`
  clamps to real staged bytes L1086). So paused ≠ "downloading" **once #196 lands** — but it is UI wiring
  atop an engine that models pause as an error. **Gap/owner:** #196 owns the UI contract today; if "honest
  progress" must be an **engine** guarantee, expose a paused/running status → **WP-DL-SAFETY** (scope call,
  Open flag 6). **Test:** pause mid-download; assert the surfaced status is exactly "paused" and the last
  `fractionComplete` = real staged/total, never advancing while paused.
- **INV-10 Relaunch task adoption — ▷ TARGET, owned by #197 [confirmed].** *After app death, a background
  URLSession's completions are re-adopted on relaunch.* **Not wired today:**
  `OfflineDownloadSession.backgroundConfiguration` exists (L1032) but carries the standing comment that it
  is "*not wired into offline object fetches yet*" (background sessions follow redirects without the
  delegate, conflicting with single-origin pinning); the live path uses foreground/ephemeral sessions
  (`offlineForeground()` L119). No `handleEventsForBackgroundURLSession`, no launch-event registry in merged
  code. **Owner: #197 (OPEN)** — its diff removes the comment, adds `offlineBackground(identifier:)`, an
  `OfflineDownloadSessionEventRegistry`, the app-delegate `handleEventsForBackgroundURLSession`, and
  post-redirect origin re-validation (`validateDownloadedFile`). **Test:** enqueue a background download,
  terminate, relaunch; assert the handler fires, the session is re-created by identifier, the completed file
  re-passes origin pinning, and the object lands verified.

**What this contract adds to the build queue:** most invariants are ✅ today; the gaps cluster into a few
owners — §6/**WP-RM-P** (INV-4 per-cell basemap *pipeline cut*) + **WP-RM-G** (INV-4 *app* basemap-source
render), both from the already-ratified §6b, reframed here as *safety*; **#197** (INV-10 background
adoption, already open); and a **NEW WP-DL-SAFETY** (engine hardening: INV-1
tile verify-then-rename, INV-5/6 GC + orphan-dir sweep incl. launch-time GC, INV-7 per-object headroom +
ENOSPC→pause, INV-8 engine single-flight + delete precedence, INV-9 engine status if first-class). See Open
flag 5 (commission WP-DL-SAFETY) and flag 6 (INV-8/9 engine-vs-UI scope).

## Build-WP decomposition

| WP | side | scope | depends on |
|---|---|---|---|
| **WP-RM-P** zone extraction + catalog + basemap cut | **pipeline (`develop`)** | OSM `boundary=administrative` sub-extractor (polygon/name/translations/QID/admin_level); region-config `zone_levels` map; polygon→z10 cell-set rasteriser; catalog materialiser (parent, size-from-cells, dedup-aware); the prune-list gate; `zone-catalog` schema; **per-z10-cell content-addressed basemap object cutting (§6b) + the z7–9 shared per-region basemap object** (the pipeline half of the INV-4 chunking fix) | region-index (shipped); OSM extractor (built); Rob-gated instances |
| **WP-RM-G** per-cell basemap RENDER (app half of §6b/INV-4) | **app (`ios`)** | render the basemap from the **per-cell content-addressed object grid** instead of a single `pmtiles://` source (the load-bearing MapLibre feasibility fork, §6b) — the app half of the INV-4 chunking-bound safety fix; consumes WP-RM-P's cut basemap objects | **WP-RM-P** (basemap cut); WP-RM-B3 (pack resolution); the built store |
| **WP-RM-B3** multi-pack RENDERING (BLOCKER, critical path) | **app (`ios`)** | **viewport→installed-pack resolution across N packs**: the map resolves a viewport's tiles from **any installed pack covering it**, not one pinned `selectedRegion`/`TileClient(region:)`; `MapRegion`/catalog reconciliation. **A zone pack is useless until this ships** | B3 (built); the built store |
| **WP-RM-B** region-manager UX | **app (`ios`)** | named-hierarchy browser (install a zone = install its **pack**, size up front); a **download-progress surface** (inherits WP-B10d's progress stream — per-zone %/bytes, cancel/pause); grid coverage feedback + **per-ZONE** update/delete (whole-pack, §4; per-cell is an Open flag); consumes `OfflineRegionStore` (pack unit) + the catalog. **NOT user-shippable before WP-RM-CT** (a sub-country download without cover-traffic is a privacy regression — CT is in B's release gate) | WP-RM-P; **WP-RM-B3**; **WP-B10d** (progress/incremental-persist); **WP-RM-CT** (release gate); the built store; WP-IMG-B2 |
| **WP-RM-B2** custom-rectangle path | **app + pipeline** | drag-rectangle→cells + confirm (size + decoy cost + halo); **needs a store extension** (synthetic-manifest cell-set install) OR composes published sub-zone packs — **new engine work, not free on the built store** | WP-RM-B; a store extension |
| **WP-RM-CT** cover-traffic | **app (`ios`)** | apply #131 in RATIFIED terms (intersection-resistant cohort, budget scales with distinctiveness); the fetch layer's decoy wrapper (WP-B7/fetch-model) | WP-RM-B; #131 rulings; Rob's decoy numbers |
| **WP-DL-SAFETY** engine hardening (§8) | **app (`ios`)** | close the download-safety gaps §8 names: **INV-1** tile verify-then-rename (mirror the basemap); **INV-5/6** GC + orphan-dir sweep (`*.pmtiles.tmp`, `root/tmp/*`) **incl. launch-time GC**; **INV-7** per-object headroom (2× staging peak) + ENOSPC→resumable-pause; **INV-8** engine per-region single-flight lease + delete-vs-download precedence; **INV-9** engine paused/running status (if made first-class, flag 6). Each ships with the §8 acceptance test (neuter → red) | the #193 engine (merged); #196 (UI consumer of INV-8/9); **Rob commission (flag 5)** |

**Seam to B10:** B10's first-run "region pick" is the **entry point** into this catalog (pick a
top-level zone → offer its pack). **B10 persists `chosenRegion` → the startup seed; WP-RM inherits/
migrates that `chosenRegion`** (the region manager's persisted selection supersedes B10's; the handshake
is `chosenRegion` — one persisted key both write). WP-RM owns the full manager, B10 owns the first-run
moment.

## Open flags (fable/Rob)

1. **Cell-set encoding** — bitmap-over-region-grid vs run-length vs bbox+exceptions; confirm with WP-P
   (compactness + O(1) membership for the app's grid render). Recommend a per-region tile-grid bitmap.
2. **Catalog: extend `region-index` vs a sibling `zone-catalog`** — recommend a **sibling** (region-index
   stays the lightweight "what regions exist"; zone-catalog carries the heavy cell-sets), confirm.
3. **Decoy budget numbers (#131)** — Rob-gated; WP-RM applies the mechanism.
4. **Per-ZONE vs per-CELL update/delete [gate — genuine tension].** The built store deletes/updates a
   whole **pack (zone)**, so v1 is **per-zone**; but the selection-UX research
   (`docs/research/2026-07-17-offline-selection-ux.md`) recommends **per-cell** update/delete (grid as a
   coverage-manager). **Recommended default: per-zone now; per-cell later via the WP-RM-B2
   synthetic-manifest path** (a rectangle/cell-set installed as an ad-hoc pack is then per-cell-deletable).
   **Logged on the WP-RM issue body for Rob's morning.** Confirm.
5. **Commission WP-DL-SAFETY [§8].** The download-safety audit found the engine mostly sound but with a
   real cluster of hardening gaps (INV-1/5/6/7/8/9) that today have **no owner** — per the plan-language
   law they must become a named WP, so §8 defines **WP-DL-SAFETY**. It needs commissioning (it is not part
   of any merged/queued WP). None is a data-corruption bug today (INV-6 holds, ENOSPC doesn't corrupt), but
   INV-5 (stranded temp files) and INV-8 (delete-during-download race) are the sharpest. Confirm the WP +
   its priority.
6. **INV-8/INV-9 engine-vs-UI scope [§8].** The same-region single-flight guard (INV-8) and paused-status
   honesty (INV-9) live in the **UI (#196)** today. Recommend pushing **INV-8 into the engine** (a
   per-view guard doesn't prevent two agents/paths racing the same region) and leaving **INV-9 as the #196
   UI contract** unless a non-UI caller needs engine-level status. Confirm the split.

## Gate & acceptance

- **Adversarial gate (done): 3 critics + verify, 15 raised, 9 survived, all folded.** The gate caught two
  serious classes:
  - **PRIVACY — I revived the WITHDRAWN k-anonymity floor** ("named = large anonymity set → minimal
    decoys") that #131/the ratified amendment retired, dropped **intersection-resistance**, and gave the
    recurring **auto-update** path no cover-traffic. §5 fully reframed in the ratified terms: every
    sub-country fetch carries cover-traffic; fixed intersection-resistant cohort, stable across updates;
    the update path carries decoys; budget keys off a real precision/exposure signal (small named zones
    are NOT auto-safe); all numbers Rob-gated. *(A real lapse — I wrote that amendment; the gate held me
    to it.)*
  - **ARCHITECTURE — the built store's unit is a PACK, not a cell-subset.** No cell-subset install, no
    per-cell delete/reference-count, no per-zone basemap slice. §4 corrected: **a named zone is a
    first-class pack** (`region_id = zone_id` + its own manifest); dedup/GC ride the existing **per-pack**
    mechanism at the content-addressed **object** level; delete is per-zone; basemap reuses the parent (or
    slicing is new work); **the custom-rectangle path needs a store extension (new WP-RM-B2), not free.**
  - **COHERENCE:** corrected the mis-grounded "region-config has no subregions" (it has authored
    `basemap.subregions` + `pack_granularity`) → added the extracted-vs-authored reconciliation; pinned a
    deterministic cell-in-polygon rule + parent-containment tie-break.
  The extracted-not-authored catalog + hybrid selection UX survived; the folds were the privacy reframe,
  the pack-unit correction, and the config reconciliation.
- **§8 download-safety-contract addition (2026-07-18, Rob commission) — gate: 2 critics + verify, 4 raised,
  3 survived, all folded.** Survivors: (1) this doc's own §4 still described #193's merged incremental-
  persist as pending "required rework" (present-tense-unbuilt = plan-language-law violation) — corrected to
  BUILT; (2) INV-4's per-cell basemap fix routed to a phantom "WP-RM-P/G" with the app-render half unowned
  (WP-RM-P is pipeline-only) — added a real **WP-RM-G** row (app basemap-source render) and split INV-4's
  owner into pipeline (WP-RM-P) + app (WP-RM-G); (3) WP-RM-P's scope cell omitted the basemap-object
  cutting the invariant routes to it — added it. The 10-invariant contract was independently
  code-audited against merged `origin/ios` first; the gate then caught the doc-internal ownership/staleness
  defects the audit didn't cover.
- PR → `develop`, `sourcery-review` only, report `p2p/fable__opus`. No self-merge; fable reviews; `main`
  is Rob's.
