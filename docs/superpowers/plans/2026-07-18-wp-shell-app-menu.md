# WP-SHELL — App-shell menu: the one menu chip + sheet (surface spec for the ratified #176 IA)

**Status:** design (opus). Adversarial-gate → PR to `develop`, `sourcery-review`. App → `ios`. Thread
`p2p/fable__opus`. **Brief = the ratified #176 IA (Rob-approved 2026-07-17); this is the SURFACE spec,
not an IA proposal — the IA decisions are already made.** Depends on nothing to build the scaffold; the
Lists / Offline-maps rows are entry points whose destinations B5 (#182) and WP-RM (#177) own.

## Why

#176: as features multiply, downloads / settings / credits must live in **one menu**, not be crammed into
the attribution box. The credits pane moves into the menu; the OSM attribution on the map **stays visible
but becomes inert**. This WP is the connective tissue three ratified designs now reach through: **B5's
Lists entry, B10's About surface, WP-RM's Offline-maps entry + active-download progress chip.**

## Grounded facts (recon: app `origin/ios` @ `fb12b8b`; cited)

- **The entire shell is ONE screen.** `MapScreen` (`Map/MapScreen.swift:46`) — a `ZStack` over
  `MLNMapViewRepresentable` with four corner `.overlay`s: `.topTrailing` status chrome, `.bottomLeading`
  the attribution button, `.bottomTrailing` locate-me + "Location is off" banner, `.bottom` nearby prompt.
  **Presentation is `.sheet` ONLY** (Credits + the place card); **no menu chip, nav bar, tab bar, Layers
  control, or search UI exist.** No `.fullScreenCover`.
- **`CreditsView` EXISTS** (`MapScreen.swift:599`) — a `NavigationStack { ScrollView … }` with **three
  sections**: **Build** (`Build <git commit>` from bundled `BuildInfo.plist`), **Manifest attribution**
  (live `[Attribution]` from the tile client — OSM ODbL etc., via `CreditEntryView`), **OSS
  acknowledgements** (bundled `OSSCredits.json` → `OpenSourceCreditView`). Reached from the
  **`attributionButton`** (`MapScreen.swift:245`, a "© OpenStreetMap" `.ultraThinMaterial` Capsule
  `Button`) via `.sheet(isPresented: $showCredits)`. This is exactly the map-corner tap target #176 wants
  migrated.
- **Navigation / routing / deep-linking is GREENFIELD** — no app-level router, no `NavigationStack` at the
  top level (the only one is *inside* the Credits sheet), no `onOpenURL`, no URL scheme. All navigation is
  `@State` booleans/items → `.sheet`. **Nothing exists for a progress chip to deep-link into.**
- **Themes: a data model exists, unused, and the brief's names don't match [gate — factual correction].**
  `MapTheme` (`MakingTracksMapStyle/PaperStyle.swift:22`) has tokens **`.snow` / `.definedPaper` /
  `.streetContrast` / `.verdantKL`** (`allCandidates`, :138) — **NOT the "snow/sand/mud" the #176 body
  names** (only `snow` exists; there is no `sand`/`mud`). It is **hardcoded to `.definedPaper`**
  (`paperBasemapStyle(theme:)` default, `PaperStyle.swift:281`; called with no arg at
  `MLNMapViewRepresentable.swift:92`); zero `App/`-layer references. No picker exists.
- **Settings / Storage / Lists / About: GREENFIELD as UI.** Only surface is the location→system-Settings
  deep link (`openLocationSettings()`, `MapScreen.swift:477`) + the "Location is off" banner
  (`LocationPermission.isLocationOff`). `StorageHeadroom` + `OfflineRegionStore` exist headless (no UI).
  `PlaceList`/`ListItem` models exist with no surface. No `AboutView`, no privacy pane.
- **Download progress DATA does not exist.** `OfflineRegionDownloader.downloadCurrentRegion()`
  (`MakingTracksTiles.swift:950`) returns a **single result, no progress stream**; the only invocation is
  a `#if DEBUG` test hook. A live progress chip needs a progress publisher **this WP does not build** —
  it is WP-RM-B / WP-B10d (the background-`URLSession` + incremental-persist wiring).

## 1. The menu chip + the ONE menu sheet (D1)

- **One menu chip on the map.** Recommend **`.topLeading`** (the one free corner — status chrome is
  `.topTrailing`, attribution `.bottomLeading`, locate `.bottomTrailing`); the **B9 search pill sits along
  the bottom** (thumb reach). A single SF-Symbol chip (`line.3.horizontal` / `ellipsis.circle`), same
  `.ultraThinMaterial` capsule idiom as the existing chrome, VoiceOver "Menu". *(Placement is a surface
  call — flag 1.)*
- **The chip opens ONE sheet — the menu hub — a self-contained `NavigationStack` [gate — reconcile
  rule 2].** The hub's root is the four rows (**Lists · Offline maps · Settings · About**); selecting a
  row **pushes its detail within the same sheet**. This is **one sheet over the map (depth 1)** with
  internal navigation — it does NOT add app-level push-navigation (the map stays the only home), and it is
  the exact idiom `CreditsView` already uses. Reading of #176 rule 2 ("sheets over the map, never
  push-navigation; the map is home"): the ban is on a **push-nav app spine**, not on a NavigationStack
  *inside a modal leaf*. *(If Rob/fable read rule 2 literally — no NavigationStack even inside a sheet —
  the fallback is swap-sheets: selecting a row dismisses the hub and presents that destination's own
  sheet, still depth 1. Recommend the internal-NavigationStack hub; flag 2.)*
- **Sheet detents:** the hub is a full-height sheet (`.large`), distinct from moment overlays (the card is
  `.medium`). The menu is a library/admin surface, not a moment overlay — it does not auto-vanish.

## 2. Routing seam + the download-progress deep-link (D2)

- **A single in-app navigation intent — NOT a URL scheme** (there is no external-deep-link requirement;
  a URL scheme would be unused surface). Define:
  ```
  enum MenuDestination { case lists, offlineMaps, settings, about }   // + later: offlineMaps(regionID?)
  @Observable final class AppShellModel { var openMenuTo: MenuDestination? = nil }  // nil = menu closed
  ```
  The chip sets `openMenuTo = .about`-agnostic (opens to the root list); a deep-link sets a specific case;
  the hub presents when non-nil and seeds its `NavigationStack` path to that destination.
- **The download-progress chip is an on-map overlay that appears ONLY during an active download**, and
  **tapping it sets `openMenuTo = .offlineMaps`** (the deep-link contract). The chip's **presence + percent
  is driven by a progress publisher this WP CONSUMES but does not build** — WP-RM-B / WP-B10d owns the
  actual `AsyncStream`/`@Published` progress (today `downloadCurrentRegion()` has none). WP-SHELL defines
  the chip UI + the `openMenuTo` contract against an **injected progress source that is `nil` when idle**;
  the chip renders nothing until that source is wired. *(So the chip is buildable + testable here with a
  stub publisher; the real data lands with WP-RM-B/B10d.)*
- **The Lists and Offline-maps ROWS are entry points into a seam B5 / WP-RM fill.** WP-SHELL owns the row
  + the route; **B5 (#182) plugs its Lists sheet content, WP-RM (#177) plugs the region-manager content**
  into `.lists` / `.offlineMaps`. Until each lands, its row shows a **"coming soon" disabled state** (not a
  dead push). WP-SHELL is buildable independently of B5/WP-RM on this seam.

## 3. About — the CreditsView migration + inert attribution (D3)

- **Attribution on the map becomes INERT text.** Replace `attributionButton` (the `Button` → `showCredits`)
  with **non-interactive `Text`** ("© OpenStreetMap", same `.ultraThinMaterial` capsule, VoiceOver static),
  **no tap target**. ODbL compliance = attribution **visible + legible**; interactivity is not required.
  Remove the `.sheet(isPresented: $showCredits)` from `MapScreen`.
- **`CreditsView`'s three sections MOVE into About** (`About` = a hub destination). About renders **Privacy
  (plain language) · Credits/Attribution · Build hash · OSS licenses**: the **Build / Manifest-attribution /
  OSS** sections migrate verbatim from `CreditsView` (still consuming the **live** `[Attribution]` from
  `MapScreenModel`, not a snapshot — pass it into the hub). `CreditsView` is deleted from `MapScreen.swift`;
  its subviews (`CreditEntryView`, `OpenSourceCreditView`, the `OSSCredits.json` loader) move with About.
- **Privacy plain-language is B10 overlap [seam].** #176 About wants "privacy in plain language"; B10
  (#174) owns that copy (and its privacy claims were gated — no overclaiming "no one can see where you
  look"). WP-SHELL builds the About **container + a privacy row**; the **plain-language content is B10's**
  — if B10's pane hasn't built, About ships Credits/Build/Licenses now and the privacy content lands with
  B10 (the row is present, the copy is sequenced). Flag 4.

## 4. Settings — theme picker (live) + location status + storage (D4)

- **Theme picker over the REAL tokens.** Expose `MapTheme.allCandidates`
  (`.snow / .definedPaper / .streetContrast / .verdantKL`), **not** the brief's "snow/sand/mud" (which
  don't exist). *(The brief's theme naming is a #128 tuning question, not an IA decision — picker ships
  over the real candidates; any rename/retheme is #128. Flag 3.)*
- **The reload wiring is REAL, three-part build work — the `onStyleWillReload` seam CANNOT do it [gate —
  wrong-seam correction].** `onStyleWillReload` (`MLNMapViewRepresentable.swift:34/113` on `wp-ios-polish`)
  is an **outbound `()->Void` the Coordinator fires DURING a reload** (it re-applies pins — `MapScreen.swift`
  supplies a closure that resets `isMapReady`/pins), **not a trigger a caller invokes**; and
  `needsStyleReload` (:91) keys **only on the two PMTiles URLs**, so a theme-only change (URLs unchanged)
  **never trips a reload** and the map stays on `.definedPaper`. So WP-SHELL-b must:
  1. **persist** the choice (`@AppStorage`), default `nil → .definedPaper` (`MapTheme.named`,
     `PaperStyle.swift:140` — matches today's hardcode, so first-launch/offline is unchanged; the style
     JSON is built locally, no network);
  2. **add a `theme` input to `MLNMapViewRepresentable`** and thread it through
     `styleURL(…)` → `paperBasemapStyle(worldPMTilesURL:regionPMTilesURL:theme:)` (the `theme:` param already
     exists, `PaperStyle.swift:285`, defaulting `.definedPaper`; `styleURL()` takes none today, :143);
  3. **track `currentTheme` in the Coordinator and add `currentTheme != theme` to the `needsStyleReload`
     gate** (:91) so a theme delta forces `map.styleURL` reassignment even when the PMTiles URLs are
     unchanged — `onStyleWillReload` then fires as its normal post-reload re-apply hook.
- **Location status: READ-only display** — reuse `LocationPermission.isLocationOff` + the existing
  `openLocationSettings()` (→ system Settings) as the action. No new permission logic.
- **Storage: READ-only display** — surface `StorageHeadroom` (headroom math exists) + installed-pack size
  from `OfflineRegionStore`. **Management actions (delete packs) belong to WP-RM's region manager**, not
  here — Settings shows the number, Offline-maps does the managing.

## Build-WP decomposition

| WP | side | scope | depends on |
|---|---|---|---|
| **WP-SHELL-a** menu + About + inert attribution | **app (`ios`)** | the `.topLeading` menu chip; the hub sheet (self-contained `NavigationStack`, four rows); the `AppShellModel`/`MenuDestination` routing seam; **inert attribution** (`attributionButton` → `Text`, drop `showCredits`); **About** (migrate `CreditsView`'s Build/attribution/OSS out of `MapScreen.swift` + a privacy row seam); the **download-progress chip + `openMenuTo=.offlineMaps` deep-link** against a stub progress source; Lists/Offline rows as disabled-until-plugged entry points; a11y (#163) | B4/card (unaffected); **live `[Attribution]` from `MapScreenModel`** |
| **WP-SHELL-b** Settings | **app (`ios`)** | the Settings hub destination: **theme picker** (`MapTheme.allCandidates` → `@AppStorage`; **add `theme` to `MLNMapViewRepresentable` → thread through `styleURL()` → `paperBasemapStyle(theme:)`; add `currentTheme` to the Coordinator + `currentTheme != theme` to the `needsStyleReload` gate** so a theme-only change repaints — `onStyleWillReload` is the post-reload re-apply hook, NOT the trigger, §4); location-status read (`LocationPermission` + `openLocationSettings`); storage read (`StorageHeadroom` + `OfflineRegionStore` size) | WP-SHELL-a (the hub); **`wp-ios-polish` (the reload gate lives there)** |

**Consumed seams (NOT built here):** B5 (#182) plugs Lists into `.lists`; WP-RM (#177) plugs the region
manager into `.offlineMaps`; **WP-RM-B / WP-B10d** provides the real download-progress publisher the chip
consumes; **B10 (#174)** provides the About privacy plain-language copy.

## Open flags (fable/Rob)

1. **Menu-chip placement** — recommend `.topLeading` (only free corner), search pill along the bottom.
   Confirm the corner (surface call, no IA impact).
2. **Rule-2 reading** — recommend the hub is **one sheet with an internal `NavigationStack`** (depth 1,
   the `CreditsView` idiom); confirm that satisfies "never push-navigation" (fallback = swap-sheets).
3. **Theme names** — the brief says "snow/sand/mud"; the code has `snow / defined-paper / street-contrast /
   verdant-kl`. Recommend the picker ships over the **real candidates**; any rename/retheme is #128, not
   this WP. Confirm (factual correction, not a policy change).
4. **About privacy copy = B10 overlap** — WP-SHELL builds the container + privacy row; the plain-language
   content is B10's (gated, no overclaims). Confirm the sequencing (container now, copy with B10).

## Gate & acceptance

- **Adversarial gate (done): 3 critics + verify, 5 raised, 2 survived (same defect, folded).** The
  survivor: **the theme-reload plumbing pointed at the wrong seam** — `onStyleWillReload` is an outbound
  re-apply hook fired *during* a URL-driven reload, and `needsStyleReload` keys only on the PMTiles URLs,
  so a theme-only change would never repaint; corrected §4/WP-SHELL-b to the real three-part wiring (add
  `theme` input → thread to `paperBasemapStyle(theme:)` → extend the `needsStyleReload` gate with a
  `currentTheme` delta). Verified NOT a problem: first-launch/offline persistence (`.named(nil)` →
  `.definedPaper` matches the current hardcode; style JSON is local). The rest held — IA fidelity, the
  `CreditsView` migration keeping live attribution, the routing seam, the progress-chip stub, ODbL
  inert-attribution, and the B10 privacy-copy seam all survived verification.
- **Remaining acceptance dimensions:** IA-fidelity (one chip, one menu, sheets-over-map, no tab bar,
  attribution inert-but-visible — ODbL); feasibility (the migration keeps live attribution; the theme
  picker actually repaints per the corrected wiring; the routing seam presents + deep-links; the progress
  chip renders against a stub and stays hidden when idle); coherence (Lists/Offline rows are seams B5/WP-RM
  fill, not dead ends; Settings shows storage, Offline-maps manages it); privacy (About copy doesn't
  overclaim — B10 gate); a11y (chip + hub + rows Dynamic Type/VoiceOver — #163).
- **Acceptance:** the map shows one menu chip + inert attribution; the chip opens a single menu sheet with
  Lists/Offline/Settings/About; About carries the migrated credits (build/attribution/OSS) with attribution
  live; Settings' theme picker changes the basemap and persists; a simulated active download shows a chip
  that deep-links to Offline maps; no surface uses push-navigation or a tab bar.
- PR → `develop`, `sourcery-review` only, report `p2p/fable__opus`. No self-merge; fable reviews; `main`
  is Rob's.
