# WP-RM — Region manager: hierarchical zone catalog + selection UX + pack lifecycle

**Status:** design (opus). Adversarial-gate → PR to `develop`, `sourcery-review`. Pipeline parts →
`develop`, app parts → `ios`. Thread `p2p/fable__opus`. Builds on: region-index (WP-P, shipped), the
BUILT offline pack store (WP-B7), #131 cover-traffic rulings, and the selection-UX research
(`offline-selection-research.md`). Rob's rulings folded (hybrid selection; extracted hierarchy).

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
  its polygon to the z10 cell-set** (rule: **a cell is in the zone iff its centre is inside the polygon**
  — one deterministic rule, so boundary cells belong to exactly one zone; state it so it is testable).
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
- **Delete + GC are PER-ZONE (per-pack), NOT per-cell.** Deleting a zone = `delete(region: zone_id)`; the
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
  built store"; named-zone packs work on the store as-is.**
- **Incremental-persist is MANDATORY [Rob requirement, not a suggestion].** RAM-buffering the whole pack
  is **unacceptable** ("how big is this going to get" — the device was **jetsam-killed today** at far
  smaller working sets). `downloadCurrentRegion` today buffers all tiles in RAM + installs at end
  (`:950-990`; kill = restart from zero); the background `OfflineDownloadSession` is **dead-wired**
  (production = foreground ephemeral `HTTPTileFetcher`). Required rework (shared WP-B10d engine): **stream
  each verified object to the content-addressed store on arrival → CONSTANT memory bound regardless of
  pack size**; an interrupted download then **resumes object-granular for free** via `updatePlan` sha-skip;
  **wire the background `URLSession`**; and **adjust failed-install GC (`:1084, :1281`) to RETAIN
  in-progress objects** (else the resume set is reclaimed). One rework serves WP-B10d + WP-RM.
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
**MANDATORY** in every pack = **place tiles + basemap + description sidecars + image-index sidecars**;
**OPTIONAL** = **image thumbs** (the one user-declinable component — the "include images" toggle,
aligning with B10/WP-IMG-B2). See the **Offline completeness invariant (§7)** for the full runtime-asset
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
    deltas become the **identical free hash-diff**: an unchanged basemap cell = same sha = skipped. This
    **unifies the store** (basemap cells are objects like tile cells → the incremental-persist + resume +
    dedup + cover-traffic cohort all apply uniformly), and directly delivers Rob's "no GB every time."
    **Cost / the key feasibility fork:** MapLibre renders a **single `pmtiles://` source**, so per-cell
    objects mean the app must **render the basemap from the per-cell object grid** (a local tile source,
    or reassemble) instead of one pmtiles file — a **pipeline cut + an app basemap-source change**
    (flag as the load-bearing feasibility question for WP-RM-P/G). **CDN/cover-traffic:** per-cell basemap
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
  (codex4 #173) are per-tile files, not content-addressed blobs — so to delta them, the pack **manifest
  must carry a per-sidecar `{sha, bytes}` entry** exactly like it does for place tiles, so an unchanged
  description tile is sha-skipped and only changed ones re-download. **State this as a manifest
  requirement** (the description-index files join the manifest's sha-listed content set, alongside the
  place tiles). Same for the image-index sidecars.
- **Net:** every pack content type (tiles/basemap-cells in the manifest; thumbs/description+image-index
  sidecars in the **pack-descriptor**) is a **sha-listed object** → the whole pack deltas uniformly via
  `updatePlan` sha-skip, streams to disk incrementally, and shares one cover-traffic cohort. No content
  type re-downloads whole.

## 7. Offline completeness INVARIANT (D7) — Rob requirement

**The invariant (→ an acceptance test in every build WP):** *a fresh install + ONE downloaded bundle +
airplane mode = a fully working region* — map + **labels** + place cards + **blurbs** + (if opted) photos,
with **zero** network. If anything the map needs at runtime is not in the bundle or app-shipped, offline
is broken. Audit of the completeness set:

- **Place tiles, basemap(-cells), description + image-index sidecars** — in the pack, mandatory (§6).
- **Image thumbs** — in the pack, the one optional component (§6).
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

**Acceptance test (build WPs):** install → download one bundle (with images) → airplane mode → the region
renders with labels, pins with category icons, cards with photos + blurbs + attribution. Neuter any one
completeness component → the test goes red.

## Build-WP decomposition

| WP | side | scope | depends on |
|---|---|---|---|
| **WP-RM-P** zone extraction + catalog | **pipeline (`develop`)** | OSM `boundary=administrative` sub-extractor (polygon/name/translations/QID/admin_level); region-config `zone_levels` map; polygon→z10 cell-set rasteriser; catalog materialiser (parent, size-from-cells, dedup-aware); the prune-list gate; `zone-catalog` schema | region-index (shipped); OSM extractor (built); Rob-gated instances |
| **WP-RM-B** region-manager UX | **app (`ios`)** | named-hierarchy browser (install a zone = install its **pack**, size up front); grid coverage feedback + **per-ZONE** update/delete (whole-pack, §4); consumes `OfflineRegionStore` (pack unit) + the catalog | WP-RM-P; the built pack store; WP-IMG-B2 |
| **WP-RM-B2** custom-rectangle path | **app + pipeline** | drag-rectangle→cells + confirm (size + decoy cost + halo); **needs a store extension** (synthetic-manifest cell-set install) OR composes published sub-zone packs — **new engine work, not free on the built store** | WP-RM-B; a store extension |
| **WP-RM-CT** cover-traffic | **app (`ios`)** | apply #131: decoy budget scales with mosaic distinctiveness; named = minimal; the fetch layer's decoy wrapper (WP-B7/fetch-model) | WP-RM-B; #131 rulings; Rob's decoy numbers |

**Seam to B10:** B10's first-run "region pick" is the **entry point** into this catalog (pick a
top-level zone → offer its pack); WP-RM owns the full manager, B10 owns the first-run moment. (Resolves
the B10 open flag.)

## Open flags (fable/Rob)

1. **Cell-set encoding** — bitmap-over-region-grid vs run-length vs bbox+exceptions; confirm with WP-P
   (compactness + O(1) membership for the app's grid render). Recommend a per-region tile-grid bitmap.
2. **Catalog: extend `region-index` vs a sibling `zone-catalog`** — recommend a **sibling** (region-index
   stays the lightweight "what regions exist"; zone-catalog carries the heavy cell-sets), confirm.
3. **Decoy budget numbers (#131)** — Rob-gated; WP-RM applies the mechanism.

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
- PR → `develop`, `sourcery-review` only, report `p2p/fable__opus`. No self-merge; fable reviews; `main`
  is Rob's.
