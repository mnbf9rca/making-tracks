# Design Session — Rulings

Batched design review of the seven design-gated Track-B iOS issues.
Packet drawn 2026-07-22; ruled by Rob 2026-07-23. Mockup: `design-session.html` in this directory.

Rob's decisions are recorded verbatim where the wording matters. This file is the
durable record; the HTML is the drawn version.

---

## #376 — Place card photo aspect ratios

**Ruled: adaptive height** (Rob: "376 Adaptive height - frame fits photo"). Confirmed
directly by Rob after the Option-B letter ambiguity was surfaced.

- The photo frame height adapts to fit the photo.
- The card does not crop the subject and does not fill odd crops with letterbox bars.
- This is the adaptive-height treatment originally recommended in the packet.

> Labelling note for the record: the packet mislabelled options by mixing a "current state"
> panel with lettered options, which shifted Rob's letters by one. Rob was asked directly
> after that ambiguity was surfaced; the ruled treatment is **adaptive height**, not
> aspect-fit letterbox.

## #360 — Coverage boundary (empty-here vs no-data-here)

**Ruled: Option A (catalog boundary line) WITH a required refinement.**

Rob, verbatim:
> "how will it read as unmapped? needs a slight shading or something otherwise how do i
> interpret it when the edge is outside viewport?"

- The published-zone bbox from `regions.json` draws the boundary line.
- **Refinement (required):** the region *beyond* coverage carries a low-contrast hatch/tint so
  "am I outside coverage?" reads from any viewport, including when the boundary line is
  off-screen. Line marks the transition; tint answers which side you're on.
- Shares visual grammar with the shipped offline-pack shading (#229/#234): one family,
  "downloaded" vs "published-but-not-here".
- Open build knobs (low-stakes): tint weight (must not fight a basemap still wanted); whether
  the standing "outside coverage" label shows always-when-beyond or only on first cross; hatch
  vs flat tint vs desaturated basemap for the fill.
- Grounded: closed #229 shipped offline-pack shading only; there is no path from live
  `regions.json` / `MapRegion.viewportBBox` into the map style. This is new work.

## #359 — Loading affordance for in-flight CDN fetches

**Ruled: Option A (top bar + pin shimmer) WITH progress-not-presence semantics.**

Rob's caveat (the same he gave the rejected spinner option): "if slow, reads as stuck."

- The top bar must be driven by real fetch progress (bytes / tile count) so it visibly
  **advances** — a slow link makes it crawl forward, reading as progress, never as a frozen
  indicator. Bar fades out on completion; never full-but-idle.
- Pin shimmer localises "places arriving here"; resolves into real pins.
- Shares grammar with #349's download progress.
- Fallback: if true byte-progress isn't available from the fetch layer, use a slow
  indeterminate **sweep** (still directional), not a static bar or a bare spinner.

**Routed separately (codex4, evidence-first):** the deeper e2e question Rob raised — CDN index
optimization, light index first + lazy detail pull. Governs how often this affordance fires;
the *look* is ruled here, the fetch architecture is its own thread.

## #378 — Welcome flow

**Reordered per Rob; refined.** Five screens:

1. **Hook** — "every place has a story", pins on paper. Product shown immediately, not a logo splash.
2. **The promise** — privacy as the pitch, in Rob's voice ("no us to send it to"). The fix for "bland".
3. **How you keep track** *(new)* — save / seen / hide, one line each, on the real action bar.
   Rob: "the story doesnt explain the save/hide/seen — a single pane might help? keep it simple
   but dont teach them to suck eggs."
4. **Location** — permission, moved to **before** the region step. Real "not now" that still lands
   in a usable map.
5. **First region** — moved to **last**, and skippable: a clear low-emphasis **Skip** under the
   region grid, with copy that the app works without a download. Region list sourced from the
   live catalog (resilient per #420). Rob: "location permission BEFORE the region step; region
   choice LAST with explicit low-emphasis Skip below the region grid and copy making clear the
   app works without a download."

Next: detail each screen's final copy and layout once the order is confirmed.

## #266 — Unify menu›Tracks and Lists›My tracks

**Accepted by default** (Rob did not object). Menu›Tracks opens the protected virtual My tracks
surface; **lands on the list detail** (recommended), retrace map one tap away via "Show on map".
Verdict editing folds onto the rows; membership stays protected (re-judge, never remove) —
PRINCIPLES §Product 7.

## #257 — Retrace timeline / line character / event-paced replay

**Accepted by default** on the drawn character: continuous dotted line, event-paced axis with
equal beat spacing, silent re-indexing on filter (no hidden-count), consistent curvature.
**Still owed by Rob:** three tunables — beat spacing (pure-equal vs slight dwell-weight), label
decimation threshold, and whether the active leg is drawn orange or inherits the #387 arc-glide
colour. On his pending list, not blocking.

## #361 — Block reorder (same-day rows)

**Accepted by default:** build the long-press → multi-select → block-move affordance **only if
it is nearly free** on the existing drag engine (#395), per Rob's original "later if hard"
ruling. If it needs a bespoke selection system, park it. `visits.id` stays row identity,
`visit_order` stays persistence truth; focused/filtered views must not reorder hidden rows.

---

## Cross-cutting

- **Theming (#350):** Rob liked the mockup look/feel and asked about #350 and the hamburger IA.
  #350 stays **parked** per his own #335 rule; the 15-surface inventory is ready; pulling it
  forward is his live option, no action unless he does.
- **§Product 7 held throughout:** no option hides, thins, tiers, or samples pins.
- **Objection window:** the trio defaults (#266/#257/#361) stand unless Rob objects.
