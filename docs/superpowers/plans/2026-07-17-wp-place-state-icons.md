# WP-place-state — hide/not-interested (#167) + per-category icons (#166)

**Status:** design (opus). One coherent design for two device-testing issues. Adversarial-gate → PR to
`develop`, `sourcery-review`. App changes target `ios`. Thread `p2p/fable__opus` (fable relays Rob).
Keeps the icon taxonomy extensible for **#162** (OSM type-layers, backlog — designed-for, not built).

## Why

Rob's device testing: (1) **#167** — *"save ones I like, hide ones I don't want to see again, so I can
focus on sorting the rest."* Hide joins save/seen as a **place-state triad** — all explicit user
actions, all local (privacy commitments; no server state). Must be **undoable** (show-hidden toggle +
unhide + a manage surface — Rob confirmed). (2) **#166** — different **icons per place type**, an icon
taxonomy over the category model that also serves #162's future layers.

## Grounded facts (recon: app on `origin/ios`; pipeline/contracts on `develop`; all cited)

- **GRDB is at migration `v1` only** (`Migrations.swift:14`) — a hide feature needs a new `register("v2")`.
  Tables: `visits` (seen = `EXISTS` a visit row), `lists` + `list_items` (composite PK, **no `added_by`**),
  `place_snapshots`. **SAVED = membership in ANY list** (`viewportState` queries `list_items` unfiltered,
  `Derivations.swift:62-68`), seeded system list "Want to go". **No hidden/not-interested/dismissed
  state exists** (grep-confirmed; the nearby-prompt "Dismiss" is a transient in-memory set, not persisted).
- **`viewportState(placeIDs)`** (`Derivations.swift:58-96`) is the **single choke point**: batched
  saved-set + visit-map → `[String: PinState]` where `PinState{ saved: Bool, visit: {none,visited,loved} }`
  (`PinState.swift`). `pinAppearance` maps the 6-cell saved×visit matrix → `{opacity, bookmark badge,
  heart badge}` (`PinAppearance.swift:18-24`, all 6 cells test-pinned).
- **Pins render** from one GeoJSON `MLNShapeSource "pins"` (`MLNMapViewRepresentable.swift`): a **circle
  layer** (`#E4572E`, r6) + **badge symbol layers** (`bookmark`/`heart`) whose images are **SF Symbols via
  `style.setImage`** (`:174-181`) — **no sprite sheet, no `"sprite"` URL** anywhere. Fade = data-driven
  opacity `match` on the `visit` feature prop; badges = layer filters (`saved==true`, `visit=="loved"`).
- **`category` is NOT plumbed to the map.** `FeatureEncoding.feature` emits only `{visit, saved,
  place_id, tier}` (`FeatureEncoding.swift:22-34`); `MapPlace` has only `id/lat/lon/tier` — **no category**
  (`MapPlace.swift`). `DecodedPlace`/`PlaceRef`/`PlaceSnapshot` DO carry `category`. So per-category icons
  require threading `category` `DecodedPlace → MapPlace → FeatureEncoding` first.
- **Category taxonomy** (`pipeline/config/taxonomy.json`): **7 values** — `religious, memorial,
  archaeological, historic_building, museum, attraction, artwork` — shipped on **every** tile
  (`place.schema.json:15` = free-form string 1–64, `additionalProperties:false`, `uncategorized` dropped
  pre-publish). **No pipeline change needed for #166.** The taxonomy has a **hard 5–7 cap**
  (`categorize.py:207-208`) and **no version field** — relevant to #162 extensibility.
- **#151 retention** (`TileClient`): `loadedPlaces` is **replaced wholesale with the current viewport**
  each resolve (`MakingTracksTiles.swift:1588`); `recentPlaceRefs` LRU cap 128; the GeoJSON is fully
  rebuilt per refresh. **So excluding hidden pins is cheap** — filter them out of the features list and
  they never enter the source; no retained set grows.
- **Place-card actions** (`MapScreen.swift:795-818`): Save / Visited / Love. A Hide action slots here.
  **No "manage hidden" or lists UI surface exists** (greenfield).

## 1. Hide state model (#167, D1)

- **New table (migration `v2`): `hidden_places(place_id TEXT PRIMARY KEY, hidden_at DATETIME NOT NULL)`.**
  Explicit, local, timestamped (drives manage-ordering + undo). **Unhide = delete the row** (reversible,
  nothing destroyed — the P3/§3.1 ethos). Mirrors the `visits`/`list_items` write pattern
  (`Interactions.swift`); a new `setHidden(_:)/unhide(_:)` on `AppDatabase` + a `CoreLoopController`
  method + a `MapScreenModel.setHidden` routed from the card, exactly like Save/Visited.
  - **Downgrade consequence [doc note].** The migration is *additive and forward-safe*, but shipping `v2`
    means a **v1-only older build (or a downgrade) fails closed** on the now-`v2` DB via the existing
    `databaseFromNewerAppVersion` guard (`Migrations.swift:76`) — the DB won't open on a build predating
    `v2`. Expected and correct (never silently misread), but a user-visible consequence the "additive,
    safe" framing should state, not a defect.
- **In-memory: an exact `Set<String>` of hidden `place_id`s** (fable's ruling, which I concur with):
  hydrated once from `hidden_places` at launch, updated **incrementally** on hide/unhide. Worst case
  (~54k catalog IDs, absurd) is a few MB and O(1) membership; realistic sets are tens–hundreds.
  **NOT a bloom filter** — a false positive would hide a **never-hidden** place (silent content
  disappearance), an unacceptable failure mode for a user-facing hide list. (Recorded per fable; I agree.)
- **`hidden` is a place-state axis orthogonal to the save×visit matrix,** but **dominant in effect**:
  a hidden place is *absent from the discovery map* regardless of its saved/visit cell. It does **not**
  add a 7th appearance cell — the matrix stays 6 cells; hidden is a **pre-filter** (below), except in
  show-hidden mode where it gets one distinct treatment.

## 2. Viewport filtering + memory (#167, D2)

- **Filter in `features(in:zoom:)` on `@MainActor` (`MapScreen.swift:965`), NOT in the off-main
  `viewportState` DB call [gate — concurrency].** The hidden `Set` is `@MainActor`-owned on
  `MapScreenModel`; the membership filter drops `place_id ∈ hidden Set` from the assembled `[(MapPlace,
  PinState)]` before it reaches the source. (Keeping the filter on the main actor, where the feature
  list is built, avoids sharing the `Set` into the `Task.detached` SQLite resolve — clean under Swift 6
  strict concurrency.) Default (show-hidden **off**): hidden pins **never enter the GeoJSON source**.
  Cheap: a `Set` filter over the already-viewport-bounded places; the source rebuilds per refresh anyway,
  so **no retained set grows** (recon-confirmed lighter than a `hidden` property + layer filter).
- **Hide/unhide MUST trigger a `features(in:)` REBUILD, not the incremental `observeChanges` remap
  [gate — the correctness gap].** Routing hide "like Save/Visited" (§1) is right for the *write*, but
  **not for the render**: `observeChanges` (`MapScreen.swift:506-514`) is a pure `features.map { … }` that
  re-derives *appearance* on the **existing** feature set — it **cannot add or remove a feature**. Save/
  Visited only change a pin's look, so that path suffices for them; **hide/unhide changes feature
  MEMBERSHIP** (the pin must appear/vanish), which only happens on a full `features(in:)` rebuild
  (`refreshViewport`). So `setHidden`/`unhide` must **request a viewport features rebuild** (or splice the
  one feature out/in), so the pin disappears/reappears immediately — the "pin vanishes on hide / Undo
  restores it" behaviour (§3) depends on this. Update the hidden `Set` first, then rebuild.
- **Show-hidden mode (on):** do **not** filter; instead resolve `hidden` for the viewport (extend
  `viewportState` to return `PinState{ saved, visit, hidden }`, a third batched set from `hidden_places`)
  and render hidden pins with **one distinct "hidden" treatment** (e.g. desaturated + a small "hidden"
  glyph) that **overrides** the save×visit appearance — so the user can see what's hidden and tap → unhide.
  Rendering precedence: **hidden (show mode) > category icon > save×visit matrix.**
- **Cross-feature — the nearby-prompt needs an UNCONDITIONAL hidden-`Set` guard, NOT one derived from the
  features filter [gate — fable, the show-hidden hole].** The foreground nearby-prompt is **built** on
  `origin/ios` (`nearbyPromptCandidate`, `MapScreen.swift:306-334`, "You're near X — seen it?") — not a
  future WP. It must skip hidden places (you hid it; don't nudge "seen it?"). **Do NOT rely on §2's
  features filter for this:** in **show-hidden mode the filter is OFF**, so hidden places re-enter
  `features`, and `nearbyPromptCandidate` (which gates only on `visit == .none` + the transient dismiss
  set) would then nudge for a place the user explicitly hid. WP-HIDE must add a **direct
  `hidden.contains(place.id)` guard inside `nearbyPromptCandidate`, independent of the show-hidden
  toggle.** *(Also corrects location design #155, which mis-described the nearby-prompt as to-be-built —
  it is built; noting for that PR.)*

## 3. Manage-hidden surface + undo (#167, D3)

- **Immediate undo:** hiding from the card dismisses the card and the pin vanishes; surface a transient
  **"Hidden — Undo"** affordance (snackbar/toast) that reverses instantly (delete the just-inserted row).
  This is the low-friction reversal for the common "oops" case.
- **Show-hidden toggle:** a map control (sibling to the §17 "Fresh snow / My tracks" toggle) that flips
  §2's show-hidden mode. When on, hidden pins appear (marked); tap → card → **Unhide** action (the card's
  action row shows Unhide instead of Hide when the place is hidden).
- **Manage-hidden screen:** a list of hidden places (from `hidden_places`, `hidden_at` DESC), each with
  unhide, plus bulk "unhide all". This is **list-shaped** and naturally lives with **B5 Lists** when that
  UI is built; until then it can be a standalone "Hidden" screen reached from settings/the toggle. (No
  lists UI exists yet — greenfield either way.)

## 4. Hide scope — map-only (recommended; the one open fork) (#167, D4)

- **Recommendation: hide = a MAP-DISCOVERY exclusion, NOT a delete.** A hidden place still exists in the
  catalog, still belongs to any **list** it was saved to (lists render their members), and is still
  **findable via search**. Opening a hidden place from search or a list shows its card with **Unhide** —
  so you can reverse from anywhere you meet it. This parallels the "Fresh snow" map filter and keeps
  hide ≠ delete. Search results for a hidden place may mark it "hidden" so the state is legible.
- **`saved` + `hidden` precedence:** hide affects the **map**; save affects **list membership**. A place
  you saved then hid is absent from the discovery map but still in your saved list (you explicitly saved
  it) — both the list and the manage-hidden screen show it; the card offers Unhide. Defined, not an error.
- **[OPEN — fable/Rob confirm]** This is a product-scope fork (map-only vs also suppress from
  search/lists). It is **not privacy-adjacent** (hide is local + explicit), so I designed the map-only
  default rather than block — but flag it: if Rob wants hide to also hide from search/lists, that's a
  scope expansion (and raises "how do I ever re-find it to unhide?" → the manage screen becomes the only
  path). Recommend map-only.

## 5. Icon system — per-category pins (#166, D5)

- **Plumb `category` end-to-end (app-side only; pipeline already ships it):** add `category` to `MapPlace`
  and emit it in `FeatureEncoding.feature`. (`DecodedPlace`/`PlaceRef` already carry it.)
- **A category is a colored pin + a category GLYPH — reuse the existing substrate.** Keep the colored
  **circle** layer (the saturated "pins are the only colour" base, §5.1) with its **fade** opacity
  expression, and add **one `pins-icon` SYMBOL layer** whose `icon-image` is a **`match` on the `category`
  property → a glyph name**, centered on the circle, riding the same fade. Badges (bookmark/heart) stay
  as overlay symbol layers. This is the minimal, spec-§5.1-consistent extension (circle + symbol layers,
  data-driven).
- **The icon layer MUST set `icon-allow-overlap: true` + `icon-ignore-placement: true` [gate].** MapLibre's
  default symbol collision would otherwise silently cull the centered category glyphs against the badge
  symbol layers and neighbouring pins (the existing badge layers already set allow-overlap; the new layer
  must too, or glyphs vanish in dense areas). **Size the glyph to the r6 (12 px) pin** — register the SF
  Symbol at an explicit `SymbolConfiguration(pointSize:)` and/or set `icon-size` so it fits the disc; the
  badge substrate renders SF Symbols at default point size (too large) if reused verbatim.
- **Glyph assets: SF Symbols via `style.setImage`, extending the existing badge pattern** — zero hosting,
  **offline**, no new privacy surface (the badges already do this). Map each of the 7 categories → an SF
  Symbol (e.g. `religious`→`building.columns`/`cross`, `museum`→`building.columns`, `historic_building`→
  `building.2`, `archaeological`→`hammer`, `memorial`→`figure.stand`/`star`, `attraction`→`star`,
  `artwork`→`paintpalette` — final glyphs a design detail, tunable). A **self-hosted sprite sheet** on
  `tiles.making-tracks.app` (parallel to the glyphs URL) is a future polish if bespoke art is wanted —
  noted, not required for v1.
- **MANDATORY fallback glyph [gate — open-string safety].** `category` is a free-form string the app
  never rejects, and #162 will add new values. The `match` expression **must** have a **default/fallback
  glyph** (e.g. a generic `mappin`/dot) for any unmapped category — otherwise a new pipeline category
  ships pins with no icon. This fallback is also what makes the app **forward-compatible** with #162 (§6).
- **Granularity limit — icons are per TOP-LEVEL category only (honest scope).** Only `category` ships on
  the tile (`place.schema` has no P31/OSM-tag/subtype field), so `religious` covers church/mosque/temple
  with **one** icon, etc. Finer per-type icons would need a **new published subtype field (place-schema +
  version bump)** or a larger category set (the 5–7 cap) — out of scope here, noted for #162.

## 6. Icons + hide interactions; extensibility for #162 (D6)

- **Fade/badges:** the category glyph rides the circle's fade (visited/loved fade); badges unchanged.
- **Clustering (§5.1/B8):** clusters span categories, so at cluster zoom the category icons collapse into
  the existing count-cluster circle (category-agnostic). Category icons render at un-clustered zoom. (A
  dominant-category cluster hint is out of scope — note.)
- **Hide precedence:** in show-hidden mode the hidden treatment overrides the category icon (§2).
- **#162 extensibility (designed-for, not built):** because `category` is an **open string** and the app
  has a **fallback icon**, the pipeline can add categories (`restaurant`, `pub`) and **old apps render
  them with the fallback** — forward-compatible, no app rebuild. To finish #162 later: (app) add the new
  category→glyph mappings; (pipeline) **raise the 5–7 taxonomy cap** + add `tag_map` entries
  (`amenity=restaurant`→`restaurant`) + **add a taxonomy version field** (there is none today) so the app
  can reason about new categories. The icon `match`+fallback is the single extension point the design
  commits to now.

## Build-WP decomposition (proposed)

| WP | side | scope | depends on |
|---|---|---|---|
| **WP-HIDE** hide state + filter | **app (`ios`)** | `v2` migration `hidden_places`; `setHidden/unhide` writes; in-memory hidden `Set` (hydrate + incremental); `viewportState`/features exclusion (off) + `PinState.hidden` (show mode); card Hide/Unhide action; nearby-prompt exclusion hook | B4 card (built), #151 (built) |
| **WP-HIDE-UX** manage + undo | **app (`ios`)** | show-hidden map toggle + distinct hidden pin treatment; "Hidden — Undo" toast; manage-hidden screen (unhide, bulk) — aligns with B5 Lists | WP-HIDE |
| **WP-ICONS** per-category icons | **app (`ios`)** | thread `category` → `MapPlace` → `FeatureEncoding`; `pins-icon` symbol layer + category→SF-Symbol `match` + **fallback**; keep circle/fade/badges | B2 map (built) |

**Not built (recorded):** #162 layers (taxonomy cap raise + version field + OSM type categories + app
layer toggles) — the icon fallback makes the app forward-compatible meanwhile.

## Open questions (fable/Rob)

1. **Hide scope (§4)** — map-only (recommended) vs also suppress from search/lists. Not privacy-adjacent;
   designed map-only, flag for confirmation.
2. **Manage-hidden home** — standalone "Hidden" screen now, or fold into B5 Lists when built? (Recommend
   standalone until B5.)

## Gate & acceptance

- **Privacy [gate note]:** hide is **local-only** — `hidden_places` + the in-memory `Set` never leave
  the device (iCloud device-backup scope is fine, like the rest of the user DB; no sync/telemetry path).
  **Hide is NOT an opt-in-stats event** — the stats event set is `{visited, bookmarked, loved}` only;
  hiding a place emits nothing, so the map filter carries no preference signal off-device.
- **Adversarial gate (done): 4 critics (privacy / coherence / feasibility / extensibility) → verify.
  Raised 9, 0 survived verification — but on independent review 6 were real doc-precision/correctness
  gaps the verify dismissed too charitably ("implied by reference" / "build detail"), and are folded:**
  - **Hide/unhide needs a `features(in:)` REBUILD, not the `observeChanges` remap** — verified against the
    tree (`:511` is a pure `.map`, can't add/remove features); without it the pin wouldn't vanish/return
    (§2). The substantive one.
  - **The nearby-prompt already EXISTS** (`nearbyPromptCandidate` `:306-334`) — WP-HIDE patches it, not a
    future WP, with an **unconditional** hidden-`Set` guard (fable's fallback-review fold: the §2 filter
    is OFF in show-hidden mode, so it can't be relied on) (§2). (Also corrects location design #155.)
  - **Filter on `@MainActor` in `features(in:)`**, not the off-main `viewportState` — Swift 6 clarity (§2).
  - **Icon layer needs `icon-allow-overlap`/`icon-ignore-placement` + explicit glyph sizing** for the r6
    pin, or glyphs are collision-culled / oversized (§5).
  - **Icons are top-level-category only** (finer type isn't on the tile) — acknowledged (§6).
  The architecture (hidden_places + exact `Set` + viewport-boundary filter; category `match` + fallback)
  survived; the folds were precision, not redesign.
- PR → `develop`, `sourcery-review` only, report `p2p/fable__opus`. No self-merge; fable reviews; `main`
  is Rob's.
