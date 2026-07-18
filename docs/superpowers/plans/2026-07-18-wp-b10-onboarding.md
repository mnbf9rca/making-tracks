# WP-B10 — Onboarding / first-run

**Status:** design (opus). First-run flow + the cold-start fix. Adversarial-gate → PR to `develop`,
`sourcery-review`. App changes target `ios`. Thread `p2p/fable__opus`. Spec §2/§5.6/§9; issue #21.

## Why

Rob: welcome + the open-source-data story + an about page; a first-run flow that steers users to an
offline pack (privacy), primes location in context, and **kills the cold-start black screen**. Today the
app boots **straight into `MapScreen`** with no onboarding and a black first frame.

## Grounded facts (recon: app on `origin/ios` + `origin/wp-map-chrome-2`; all cited)

- **Onboarding is entirely GREENFIELD.** `MakingTracksApp.swift` boots `WindowGroup { MapScreen(...) }`
  directly; **no first-run detection, no persisted flag** (no `UserDefaults`/`@AppStorage`/GRDB
  onboarding flag — grep-empty), no welcome/about/intro screen.
- **Cold-start black screen is real and has NO stopgap [corrects the assignment].** Before MapLibre fires
  `didFinishLoadingStyle` the `ZStack` (`MapScreen.swift:93`) has only the map + overlays, so the first
  frame is MapLibre's bare (black) surface. The only `ProgressView` is inside `PlaceCardSheet`
  (unrelated). `TileLoadState` is set **post-load**, so it doesn't cover the black window. **There is no
  codex loading-placeholder** on either branch — B10 owns building it (flag: if codex has one unpushed,
  reconcile).
- **Location-permission component is BUILT** (`LocationPermission.swift`, both branches):
  `@Published authorizationStatus`, `currentCoordinate`, `isLocationOff` (**the declined-state signal**),
  `requestWhenInUseIfNeeded()` (one-shot priming), `requestCurrentLocation()`. *(Correction: the
  `LocationManaging` injection protocol was **removed in #164** — injection is now the concrete
  `AppLocationManager`, `MapScreen.swift:81`.)* Settings deep-link = `MapScreen.openLocationSettings()`.
  **Locate-me button already exists.** B10's permission step **consumes** this — builds no new manager.
- **Offline download engine is BUILT, UI is not.** `OfflineRegionDownloader.downloadCurrentRegion()`,
  `OfflineRegionStore.updatePlan(for:) → {tilesToFetch, bytesToFetch, …}`, `StorageHeadroom.hasHeadroom(…)`
  (512 MB reserve), background discretionary `OfflineDownloadSession`. **No download UI** (only a DEBUG
  launch-arg path). **`downloadCurrentRegion()` has NO incremental progress callback** — B10 must add one
  (only the up-front `bytesToFetch` is known).
- **Region selection: no picker.** `ViewportSeed` (default `.kl`) is the startup camera; `MapRegion
  {malaysia, uk}`; `selectedRegion` **auto-derives from the viewport** (`MapScreen.swift:1152-1154`) — not
  hardcoded. So a first-run pick only needs to **persist the startup seed** (`chosenRegion` → seed); the
  region then follows the seeded viewport. It kicks the downloader for that region. **The full region manager is WP-RM (gated by Rob's open region-selection-UX ruling) —
  B10 designs the first-run pick as a seam, not the manager.**
- **Update-required logic exists, UI doesn't.** `VersionGate.reader` → `TileLoadState.updateRequired`
  (`minReaderVersion > readerVersion` + no cache), surfaced only as a tiny text chip. B10 §5.6 builds the
  real blocking surface.
- **Stats opt-in: greenfield** (v1.5 / C1 activates). **Settings/About: none** — only `CreditsView`
  (Build + manifest attribution + OSS credits), reached via the attribution chip. The natural anchor for
  the About page / open-source-data story / (later) the stats toggle.

## 1. First-run detection + the flag (D1)

- A persisted **`hasCompletedOnboarding`** boolean (`@AppStorage`/`UserDefaults` — a UI flag, not user
  data, so not GRDB). First launch (`false`) → onboarding; thereafter → straight to the map. The flag
  flips only when the user **finishes or explicitly skips to the end** (so a mid-flow kill re-shows it).
- **[gate — SUBSTANTIVE: the region pick must SURVIVE RELAUNCH].** Today `startupViewport` is a per-launch
  constant defaulting to `.kl` (`MakingTracksApp.swift:10`) and `selectedRegion` **auto-derives from the
  viewport** (`MapScreen.swift:1152-1154`) — **nothing persists the choice**, so a UK user's second cold
  start re-seeds to KL. So B10 also persists a **second value: `chosenRegion`** (`@AppStorage`) →
  `MakingTracksApp` seeds `startupViewport` from it on every launch (not the hardcoded `.kl`). **WP-RM
  inherits/migrates `chosenRegion`** (the region manager's persisted selection supersedes it) — this is
  the load-bearing part of the B10↔WP-RM seam. "Replay onboarding" + the About page are reachable later
  from Settings (§6).

## 2. Kill the cold-start black screen — a launch placeholder (D2, EVERY cold start, not just first-run)

- A **launch overlay** in the `ZStack` above the map: the **paper/muted background** (the basemap's own
  palette, so it reads as "map loading," not a foreign splash) + the app name + a subtle indicator, shown
  while the style is not yet loaded. **[gate — dismiss on the map-READINESS signal, NOT `TileLoadState`].**
  `TileLoadState` is manifest/**network** state — keying the overlay on it holds it hostage to the network
  and masks offline-with-cache startup. **Consume codex's `onMapReady` closure** (being added on
  `wp-ios-polish`: `MLNMapViewRepresentable.onMapReady`, fired from `mapView(_:didFinishLoading:)` after
  the style loads — confirmed on thread) — do **not** invent a parallel signal. Dismiss on `onMapReady`
  (the basemap can paint; pins may trail — don't wait for `onFeaturesApplied`), with a **B10-owned timeout
  fallback** (no style-failure callback exists yet; optionally pin a small additive `onMapLoadFailed`).
  This covers the black window on **every** launch — distinct from the first-run flow (which sits *in
  front of* the map on first launch only).

## 3. The first-run flow (D3)

A short, skippable, paged flow (each step **Skip**-able; a progress dots indicator):

1. **Welcome** — the promise + the metaphor teased: "Interesting places around you — the map is *fresh
   snow*; exploring marks it."
2. **Where places come from / About (Rob's ask)** — open data (Wikipedia, OpenStreetMap, heritage
   registers), credited; the app is **open source**; privacy framing **[gate — use privacy.md's scoped
   wording, not an ungated overclaim]:** *"Nothing **you save** leaves your device unless you choose to
   share it"* (privacy.md:9's exact qualifier — my draft dropped "you save," which is false: viewport
   tile requests + IP go to Cloudflare, place-card image URLs + IP to Wikimedia today, and a launch
   `current.json` ping). Do **not** say "nothing leaves your device" unqualified. Acceptance check: the
   About copy must match a privacy.md commitment verbatim (not paraphrase off the qualifier). This screen
   *is* the About page (§6 anchors it in Settings too).
3. **Region pick** — **UK or Malaysia** (the two v1 regions from `MapRegion`); sets `ViewportSeed` +
   `selectedRegion`. **Seam to WP-RM** — a minimal two-choice pick now; the full region manager +
   Rob's region-selection UX is WP-RM. *(Pre-select-from-location is a **dead branch on true first run** —
   permission priming is step 5, so location isn't known yet; mark it **replay-only**, or drop it.)*
4. **Offline pack offer — privacy-framed, HONESTLY (spec §9; onboarding steers to a pack)** — [gate —
   the copy must not overclaim]:
   - **Today's honest copy** (before WP-IMG-B2): *"Download <region> (~<`bytesToFetch`>) so the **map**
     works with no connection."* **Do NOT claim "no one can see where you look"** yet — place-card
     **photos still stream live from Wikimedia** (`ImageLoader` → Wikimedia hosts; the built pack bundles
     **only tiles + basemap**, no thumbnails), and a full pack **still pings `current.json` on launch**
     (the manifest/version check — the §4-region-model "check on launch, never on a schedule" poll).
   - **The strong claim ("no one can see where you look") is GATED on WP-IMG-B2** (single-origin
     `tiles.making-tracks.app` thumbs **bundled in the pack**, from the card overhaul) — only once photos
     are single-origin + pack-bundled does the offline pack actually eliminate the per-place image leak.
     Until then the **"include images" toggle is inert / hidden** (the built downloader fetches no thumbs
     — a live toggle would be a dead control, the gate's exact catch). Add an **acceptance test: neuter
     pack image-bundling → the strong privacy claim must go red.**
   - Shows the size (from `updatePlan`) + a `StorageHeadroom` check. **Skippable** → online-first
     (works immediately; honestly weaker on the tile channel).
5. **Location priming — in context** — "Show your position to find places near you?" →
   `requestWhenInUseIfNeeded()` **fired ONLY on the affirmative tap** (never on the step's appearance — no
   cold iOS prompt) (consumes `LocationPermission`). **Skippable**; **declined-state handled**
   (`isLocationOff` → the app is fully usable; a Settings deep-link is offered later, never nagged). Never
   the raw iOS prompt cold — always the in-context explainer first.
6. **Snow-metaphor intro** — teach **"Fresh snow / My tracks"**: seen places fade as you visit them
   (faded = progress, not loss). Brief, over the now-populated map.
7. **Stats opt-in — DESIGN ONLY, inactive in v1 (§5.5).** The step exists, offered once, plain-language,
   **default off**; the toggle persists but **collection is C1/v1.5**. In v1 it may be omitted or shown as
   "coming later" — recommend **omit from v1 onboarding** and add it when C1 ships (avoid a dead toggle).

## 4. Empty / unsupported region + update-required surfaces (D4)

- **Unsupported/out-of-coverage region:** a located user outside UK/Malaysia (the location-design
  out-of-coverage case) → a plain **"No map for your area yet — v1 covers the UK and Malaysia"** state
  (not a wrong far-region load). Onboarding sets expectations here.
- **Update required (§5.6):** a fresh install on a too-old app (`TileLoadState.updateRequired`, no cache)
  → a **blocking sheet** with copy ("This version is too old to read the latest map — please update") +
  an **App Store link**. B10 builds this real surface (logic exists; UI doesn't). `.updateAvailable`
  (cache present) is a **non-blocking** banner instead.

## 5. Download progress + the foreground/background reality (D5) [gate — not a "small add"]

- **`downloadCurrentRegion()` is FOREGROUND, in-memory, all-or-nothing today** — it fetches every tile
  serially and accumulates them in a `[TileCoordinate: Data]` dict in RAM, installing at the end. It is
  **not** the "discretionary background session" my §3.4 draft implied (that config exists but this path
  doesn't use it). Consequences B10 must state honestly, not paper over:
  - **v1 (minimum): foreground download** — a progress bar (add an `AsyncStream`/closure:
    `bytesFetched / bytesToFetch`, `@MainActor`) that **only advances while the app is frontmost**;
    **large packs risk memory pressure + interruption**. State this limit in the offer copy ("keep the
    app open while downloading").
  - **The real WiFi-preferred BACKGROUND download is UNBUILT engine work** — scope it as WP-B10d, not a
    "hook". **The rework (fable's tree-verified evidence):** downloads are **not resumable** today
    (`downloadCurrentRegion` buffers ALL tiles in RAM, installs once at end, `:950-990`; kill = restart
    from zero); the `OfflineDownloadSession` background config exists but is **dead-wired** (production
    uses the foreground ephemeral `HTTPTileFetcher`). Fix = **incremental-persist:** write each
    **verified** object to the content-addressed store **as it arrives** → an interrupted download
    **resumes object-granular for FREE** via the existing `updatePlan` skip (no byte-range resume needed);
    plus **wire the background `URLSession`** + the progress stream. **Adjust failed-install GC** (`:1084,
    :1281`) to **retain in-progress objects** (else the resume set is GC'd). Don't claim background/
    resumable download until this is built.

### 5.1 B10d amendment — background URLSession redirect conflict

WP-B10d's safe implementation ships the engine rework on guarded foreground/ephemeral sessions: verified
object downloads stage incrementally, pause interrupts and preserves completed objects for a later
`updatePlan` resume, cancel/delete discard in-progress roots, and progress is reported for the foreground
session path.

`OfflineDownloadSession` remains configured but intentionally unwired for object fetches. Apple documents
that background `URLSession` tasks automatically follow redirects and do not call the redirection delegate;
that conflicts with Making Tracks' single-origin redirect pinning invariant for tiles and basemaps.

The possible background upgrade is a Rob risk-acceptance call: use background downloads, verify the final
response/file URL host after completion, then discard and fail closed on mismatch. The residual risk is one
request-metadata leak per object to the redirect target if `tiles.making-tracks.app` is compromised or
misconfigured into redirecting.

## 6. About + Settings anchor (D6)

- A minimal **Settings/About** surface (extend/repurpose `CreditsView` or a sibling): the open-source-data
  story + OSS credits (exists) + version, **"Replay onboarding,"** the location **Settings deep-link**
  when off, and (when C1 ships) the **stats opt-in** toggle. Reachable from the map (the attribution chip
  → About, generalised). Keeps the card/map uncluttered while giving the About page a home.

## 7. Accessibility (D7 — measurable, #163) [gate — was absent]

The onboarding flow is a11y-dense (paged flow, progress dots, size strings, toggles, the blocking
update-required sheet) — acceptance criteria, applied to **WP-B10a** (flow) and **WP-B10c** (surfaces):
- **Dynamic Type:** every step's text uses semantic fonts and **reflows** at accessibility sizes (no
  truncated copy; the Skip/Next controls stay reachable; the pack-size string wraps).
- **VoiceOver:** each step is a focusable screen with a label; **Skip/Next/affirmative** buttons carry
  labels; progress dots announce "step N of M"; the pack-size + storage strings are announced; the
  update-required sheet is announced as an alert with its App-Store action labelled.
- **Never gate a step behind a gesture** a switch-control/VoiceOver user can't perform; the named/tap
  paths are the accessible primary routes.

## Build-WP decomposition

| WP | side | scope | depends on |
|---|---|---|---|
| **WP-B10a** onboarding flow | **app (`ios`)** | first-run flag **+ persisted `chosenRegion`→seed** (§1); the paged flow (welcome / about-open-data-scoped-copy / region-pick seam / pack-offer / location-prime-on-tap / metaphor); Skip + **a11y** (§7); consumes `LocationPermission`. **Pack-offer progress depends on WP-B10d's stream** — else a **fire-and-forget** download with a determinate spinner from `updatePlan.bytesToFetch` | B4 (built), `LocationPermission` (built), **WP-B10d** (progress) |
| **WP-B10b** cold-start placeholder | **app (`ios`)** | the launch overlay (paper bg + indicator) dismissed on `didFinishLoadingStyle` + timeout — **every** cold start | map (built) |
| **WP-B10c** update-required + empty-region surfaces | **app (`ios`)** | blocking update-required sheet + App Store link; unsupported-region state | `VersionGate`/`TileLoadState` (built) |
| **WP-B10d** download progress + background rework | **app (`ios`)** | v1: a foreground progress stream (§5, frontmost-only, memory caveat); **the real WiFi-preferred background download (survives backgrounding, streams to disk) is an engine rework** — not a hook | the built downloader (needs background rework) |
| **WP-B10e** About/Settings anchor | **app (`ios`)** | About page (open-data story + OSS) + replay-onboarding + settings-deeplink; stats toggle when C1 ships | `CreditsView` (built) |

## Open flags (fable/Rob)

1. **Region-pick vs WP-RM** — B10 does a minimal UK/Malaysia first-run pick; the full region manager +
   Rob's region-selection-UX ruling is WP-RM. Confirm the seam (does WP-RM subsume the first-run pick, or
   does B10 own the two-choice pick and WP-RM the manager?).
2. **Stats opt-in in v1 onboarding** — recommend **omit** until C1 (no dead toggle); confirm.
3. **Cold-start placeholder ownership** — recon found **no** codex stopgap; B10 owns it. Confirm codex
   has nothing unpushed to reconcile.

## Gate & acceptance

- **Adversarial gate (done): 4 critics + verify, 12 raised, 4 survived, all folded.** All in the pack
  offer — my privacy copy overclaimed:
  - **"No one can see where you look" was FALSE** — place-card photos still stream live from Wikimedia
    (`ImageLoader` → Wikimedia hosts; the built pack bundles only tiles+basemap) and privacy.md *commits*
    photos-in-bundle. Copy softened to today's truth ("the map works with no connection") and the strong
    claim + the "include images" toggle **gated on WP-IMG-B2** (single-origin pack thumbs); acceptance
    test: neuter image-bundling → the claim goes red (§3.4).
  - **"Needs nothing from our servers" ignored the launch `current.json` poll** → scoped to the map
    drawing offline, with the launch manifest/version check noted as the exception (§3.4).
  - **`downloadCurrentRegion` is foreground/in-memory/all-or-nothing**, not the background session I
    implied → v1 is a foreground progress bar (frontmost-only, memory caveat); the real background
    download is scoped as engine rework, not a "hook" (§5, WP-B10d).
  The flow/placeholder/permission/update-state architecture survived; folds were honesty about what the
  offline pack does *today* vs after WP-IMG-B2.
- PR → `develop`, `sourcery-review` only, report `p2p/fable__opus`. No self-merge; fable reviews; `main`
  is Rob's.
