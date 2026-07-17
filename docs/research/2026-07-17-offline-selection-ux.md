# Offline map area-selection UX — prior-art survey (2026-07-17)

Commissioned by Rob: "i think there must be something else out there which we can base this on... perhaps you drag over a map with grid boxes covering the areas you want?"

## Comparison table

| App | Selection mechanism | Granularity | Typical sizes | Update / delete UX |
|---|---|---|---|---|
| **Google Maps** | Viewport-as-rectangle ("Select your own map", pan/pinch a blue frame); auto-suggested "Recommended maps" | One rectangle per download, up to ~25 areas | ~500 MB–2 GB large metros; estimate shown pre-download | ~15-day expiry warnings; Wi-Fi auto-update; per-area manage/delete |
| **Apple Maps (iOS 17+)** | True drag-rectangle with corner handles; live storage estimate | One rectangle, ~5 GB cap | ~100 MB town → 1–2 GB dense metro | Resize-and-redownload in place; auto-update default; Optimize Storage |
| **Organic Maps / Maps.me** | Named-region list (country → state); prompts for the region you're browsing | Whole countries/states only | ~100–800 MB per country (vector) | Refreshed ~twice monthly; outdated flag; delete per region |
| **OsmAnd** | Named list + tap-region-on-world-map; raster path has draw-a-box with per-zoom tile counts | Country/sub-region files; raster = true tile grid | World basemap ~275 MB; Japan ~700 MB | Monthly releases; quota on free tier; paid live diffs |
| **HERE WeGo** | Named list, continent → country → region | Country-scale packs | GBs for large countries | Pause/resume; stale-pack alerts |
| **Gaia GPS** | Drag-rectangle + corridor-along-route | Rectangle × layers; tile caps | Layer/zoom dependent | Re-download refresh; per-download list |
| **AllTrails** | Per-trail corridor, park packs, custom viewport rectangle | Trail/park/rectangle | Capped by tile limits | Downloads list; per-item delete |
| **onX** | Frame area + Low/Med/High detail tradeoff | One area per download | Estimate + storage-remaining shown | Re-save to update |
| **komoot** | Named pre-cut region catalog (monetized: ~$3.99/region, World Pack) | Pre-cut polygons only, three size tiers | Modest per-region vector | Lifetime unlocks; re-download per region |
| **Backcountry Navigator** | **GRID BOXES** — tap blocks; downloaded blocks stay marked | Fixed grid cells | Per-block | Grid doubles as coverage map |
| **Topo GPS** | **Grid squares as purchase units** (UK/BE): tap priced squares | Fixed squares; else country IAP | Per-square | Purchases include future updates; owned squares shown |
| OruxMaps / Locus | Rectangle over tile grid, per-zoom checkboxes | True tile granularity | Exact, user-controlled | Whole-tile mosaics only |

## The grid-box pattern

Shipping, but niche: Backcountry Navigator (canonical), Topo GPS (priced squares), and power tools (OruxMaps, Locus, OsmAnd raster, MOBAC). Strengths map onto our constraints: cell = fixed pre-cut unit → perfectly predictable size; coverage state visible at a glance; natural incremental top-ups; per-cell update/delete. Failure modes (why it stayed in expert tools): higher cognitive load than framing a rectangle; tedium painting many cells; the **edge problem** (a town straddling a boundary forces 2–4 cells or a map that dies mid-street); grid lines mean nothing semantically — users must translate "Snowdonia" into a lattice. No mass-market app ships paint-the-grid; they converged on one rectangle (Google/Apple/Gaia/onX) or a named list (Organic/HERE/komoot).

## Recommendation (fits pre-cut bundles + privacy decoys)

Architectural relatives are komoot/Organic (pre-cut units), not Google/Apple — and both chose NAMED units. Privacy: popular named bundles = large anonymity sets; a unique 7-cell mosaic ≈ location fingerprint (decoy budget must grow with cell-count to blur a distinctive shape).

1. **Named packs as the primary UI** — metros/parks/regions, one tap, size up front (komoot/Organic style). Best discoverability AND best privacy; boundary is semantic so no partial-coverage confusion.
2. **Drag-rectangle as the custom path, silently decomposed into cells** — Apple-style handles; confirmation shows which pre-cut cells the rectangle resolves to + summed size; whole cells only, optional 1-cell halo (rounding up doubles as privacy padding).
3. **Grid as feedback, never as input** — cells visualize coverage/ownership after selection and drive per-cell update/delete (Backcountry Navigator's genuinely good idea), but users never paint cells to select.
4. Borrow the two best update behaviors: Apple's resize-and-redownload + auto-update default; Google's staleness nudge. Per-cell diffs make both cheap.

(Sources with URLs in the research transcript; key ones: Google/Apple support docs, OsmAnd docs, komoot regions, Backcountry Navigator features, Topo GPS manual, Locus download docs.)
