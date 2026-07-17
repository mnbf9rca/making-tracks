# WP-location — user location, follow-me, and the snow-marking loop (B6 doorstep)

**Status:** design (opus). All sections designed; **§6 snow-marking RULED (A) spec-faithful by Rob** —
no passive trail. Adversarial-gate → PR to `develop`, `sourcery-review`. App changes target `ios`.
Thread `docs/location-design`.

## Why

Rob's #1 app-first priority: *"user location + follow-me on the map"*, and *"the app doesn't even have a
locate-me button — that's an oversight."* codex ships the **bare** locate-me button + blue dot; this
design owns everything beyond it: **follow-me camera (+ heading), backgrounding/battery, permission
strategy, the locate-me↔region interplay**, and the first real slice of the **B6 snow-marking loop**.
Privacy is structural and freshly codified (privacy.md + the ratified P14/P15 amendment): **location
runs only while the app is open, is NEVER stored (no coordinate is ever written to disk, DB, or log —
the only persisted history is the deliberate, place-anchored `visits` log), and is never sent;
everything off until turned on.** *(The word "trail" appears in this doc only as the metaphor for the
constellation of deliberately-marked places — never a stored location track. Per Rob's (A) ruling.)*

## Grounded facts (recon: app on `origin/ios` @ 941fda1; contracts/spec on `develop`; all cited)

- **The whole location surface is GREENFIELD.** No `CLLocationManager`, no `map.showsUserLocation`,
  no `MLNUserTrackingMode`, no heading, no locate-me button, on **either** branch. *(Correction to the
  assignment: `#153` = **WP-G bundled world basemap**, not a locate-me button; `origin/wp-map-chrome-2`
  does not exist as a remote — only a local `wp-map-chrome-2` at the #151 parent. So codex's bare
  locate-me is **not yet on `origin`** — flag to confirm its branch before WP-LOC-B builds on it.)*
- **The `@MainActor` MapLibre boundary is correct** — `MLNMapViewRepresentable` (`:748`) and its
  `Coordinator: MLNMapViewDelegate` (`:794`) are both `@MainActor`, under project-wide
  `SWIFT_STRICT_CONCURRENCY: complete`, `@preconcurrency import MapLibre`. The only camera call today is
  one `map.setCenter(startupViewport.center, zoom, animated:false)` at startup (`MLNMapViewRepresentable.swift:771`);
  no animated camera, no user-location delegate callbacks.
- **A viewport→region loop already exists** and is exactly the "camera lands in UK → UK loads" substrate:
  `MapRegion { malaysia; uk }` with `viewportBBox` each; `MapRegion.select(for:current:)` picks by bbox
  intersection + hysteresis, else nearest-center (**default `.malaysia`**). Driven by
  `onCameraIdle → refreshViewport → selectClient(for:)` (`MapScreen.swift:70-81,716-725`). Tile clients
  are per-region, lazily cached.
- **Startup camera default is hardcoded KL** (`ViewportSeed.selected` defaults `.kl`), overridable only
  by a UI-testing arg. WP-G's "single configurable default (NOT a picker)" is documented but **not yet
  a config**. #153 also **"serialize map screen model state"** — a persisted last-viewport may exist to
  build the default on.
- **`visits` is strictly place-anchored — NO trail storage.** `visits(id, place_id, visited_at, verdict,
  created_at)` (`Migrations.swift:15-22`); no lat/lon/coordinate/heading column; **no trail / track /
  location_history table anywhere**. `place_snapshots` holds a place's lat/lon (place metadata, not user
  movement). A movement trail would require a **new `v2` migration + table** (greenfield).
- **No app-lifecycle handling.** No `scenePhase`, no `UIApplicationDelegate`, no `UIBackgroundModes`,
  no `Info.plist` location usage strings (must be added in **both** `Info.plist` and `project.yml` —
  XcodeGen regenerates). Any location manager needs its **own** `scenePhase` gating.

## 1. Locate-me + blue dot — codex's bare slice (this design's lower boundary)

codex ships: a recenter button in `mapChrome`; `CLLocationManager` (when-in-use); the blue dot via
MapLibre's built-in `map.showsUserLocation = true` (`MLNUserLocationAnnotationView` — no custom
shape-source needed for the bare dot). This design assumes that substrate and builds follow-me,
battery, permission, and region-interplay on top. **[flag]** confirm codex's actual branch/scope
(recon found no locate-me on `origin` yet) so WP-LOC-B doesn't collide or double-build the manager.

## 2. Follow-me camera mode (+ heading) (D1)

- **Substrate: MapLibre's native `MLNUserTrackingMode`** — `.none / .follow / .followWithHeading /
  .followWithCourse`. Use it rather than hand-rolling camera math; the button drives the mode, MapLibre
  drives the camera.
- **[gate — resolve the manager ownership: inject a custom `MLNLocationManager`].** In native tracking
  mode MapLibre reads location/heading from *its own* location manager, so the app cannot set
  `desiredAccuracy`/`distanceFilter`/heading on it — which would make §3's battery discipline
  unenforceable. Resolution: **inject an app-owned `MLNLocationManager` via `MLNMapView.locationManager`**,
  wrapping a `CLLocationManager` the app configures (accuracy, `distanceFilter`, when-in-use, heading
  start/stop, `scenePhase` stop). Native mode then drives the camera **through the app's manager**, so
  §3's tunables apply and there is exactly **one** `CLLocationManager` (shared with the permission
  component, §4) — not MapLibre's hidden one plus the app's. This is the single reconciliation of "let
  MapLibre drive" (§2) with "the app owns accuracy/heading/lifecycle" (§3).
- **Button state machine (owned by `MapScreenModel`, `@MainActor`):** a single locate/follow control
  cycles **`.none` → `.follow` (recenter, north-up) → `.followWithHeading` (rotates to compass) →
  `.none`**, the familiar Maps/Google pattern. **Any user pan/rotate gesture breaks follow → `.none`**
  (the user always regains manual control instantly — an explicit `regionDidChange` "was-user-gesture"
  check). Button icon reflects the mode (locate → filled → heading-arrow).
- **Heading choice — compass (`followWithHeading`), not course.** For a *discovery* map you stand and
  look ("which way to face to see that building?"), so device heading beats direction-of-travel.
  Course-up (`followWithCourse`) is a flagged alternative if user-testing prefers it while walking.
  Heading updates (`startUpdatingHeading`) run **only** in `.followWithHeading`; stopped otherwise.
- **Feeds the existing region loop:** follow-me pans the camera → `regionDidChangeAnimated` →
  `onCameraIdle` → `MapRegion.select` → follow into the UK loads UK tiles. No new region logic.
  **[gate — correction: there is NO debounce today].** `onCameraIdle`'s `viewportRequestID`/`stateEpoch`
  guard is *last-writer-wins result coalescing*, **not** call throttling — every `regionDidChangeAnimated`
  fully runs `TileClient.places(inViewport:)` + the DB `viewportState`. Under continuous follow that is a
  full viewport/region/DB refresh per location update — contradicting §3's battery posture. **WP-LOC-B
  MUST add real throttling** (leading+trailing coalesce, ~250–500 ms tunable) between the follow camera
  stream and this loop, before follow feeds it.
- **Concurrency:** `CLLocationManager`/`CLHeading` delegate callbacks hop to the main actor; the follow
  state and all `map.*` camera/mode mutations stay on `@MainActor` (the existing boundary). MLN objects
  never cross an actor hop.

## 3. Battery + backgrounding (D2)

- **When-in-use ONLY — follow-me is a FOREGROUND mode.** No `UIBackgroundModes` `location`, no
  background updates. This *is* the privacy posture ("location only while the app is open") and the
  battery posture at once.
- **`scenePhase` gating (new — greenfield):** on `.background`/`.inactive` →
  `stopUpdatingLocation` + `stopUpdatingHeading`, drop follow to `.none` (or a visibly *paused* state).
  On return to `.active` → **do not silently resume location** (P5 "nothing consumed silently"); the
  button reflects its last mode but a fresh fix requires the manager to be (re)started by the user's
  presence in the mode — spelled out in WP-LOC-B so resume can't leak into a background beacon.
- **Battery discipline:** `desiredAccuracy = kCLLocationAccuracyNearestTenMeters` (a discovery map does
  not need `Best`); a `distanceFilter` (~5–10 m) to suppress jitter updates; heading updates only in
  heading-follow; everything stops on background. All tunables (earned-not-baked), documented.

## 4. Permission strategy (D3)

- **When-in-use only** (`NSLocationWhenInUseUsageDescription`) — never Always/Background. Add the key
  to **both** `Info.plist` and `project.yml`.
- **Requested IN CONTEXT** — on the **first locate-me tap**, never at launch (P5 + best practice). The
  usage string states the discovery purpose ("shows your position on the map so you can find
  interesting places around you").
- **Degrade gracefully — the app is fully usable without location** (search / jump-to-location already
  cover navigation):
  - `notDetermined` → request on tap.
  - `denied`/`restricted` → the button shows a muted/prompt state; tapping offers an "Open Settings"
    path; **no nagging**, no feature is blocked behind location.
  - `authorizedWhenInUse` → locate/follow works.
  - **Reduced accuracy** (precise-location off): the dot is coarse, follow still works; optionally
    request temporary full accuracy for follow via a purpose key (`NSLocationTemporaryUsageDescriptionDictionary`)
    — flagged optional, not required for v1.
- **Reusable permission-flow component (Rob's fold — B10 consumes it).** The authorization logic — a
  `CLLocationManager` authorization observer, the status→UX mapping (request / muted-prompt /
  Open-Settings deep-link `UIApplication.openSettingsURLString`), and the "tell the user, don't nag"
  copy — is a **single reusable component**, not inlined in the locate button. **codex is building this
  helper now on `wp/map-chrome-2`** — this design **references/owns its contract** so two consumers share
  one implementation:
  - **the locate-me/follow button** (denied → tell the user + deep-link Settings), and
  - **onboarding (B10)** — Rob wants first-run to offer location as an **OPTIONAL step** (skippable,
    never a gate), with the **same** declined-state handling. B10 consumes the component; it does not
    re-implement authorization.
  Contract the component must expose: current `CLAuthorizationStatus` (+ accuracy), an `async` request,
  a published stream of changes (so both button and onboarding react), and a "route to Settings" action.
  **[flag]** align with codex's in-flight helper before WP-LOC-B — one manager, one authorization owner
  (two `CLLocationManager`s racing authorization is a bug class).

## 5. Locate-me ↔ region interplay, post-WP-G (D4)

- **The interplay is automatic through the existing loop:** locate → camera to the user's fix →
  `onCameraIdle(bbox)` → `MapRegion.select` picks the region whose bbox intersects → its `TileClient`
  loads. Locating in the UK loads UK; no new region code.
- **Out-of-coverage located state [gate — corrected against `MapRegion.select`].** For a fix outside
  every region bbox, `MapRegion.select` does **not** reach nearest-center in the normal case: the
  **hysteresis branch `if let current { return current }` retains the *current* region** (the wrong
  far-region "load" is really the app *staying* on its current region, not a nearest-center →
  `.malaysia` jump). So the fix must run **caller-side, BEFORE trusting `select`**: in the locate
  handler, if the located fix ∉ **every** `MapRegion.viewportBBox` (an explicit point-in-bbox
  **contains?** check), show the blue dot + a gentle **"no map for your area yet"** empty state and
  **skip `select`/tile-load** entirely. Alternatively a top-of-`select` contains-guard with a
  signature change to `MapRegion?` (a new no-coverage case). WP-LOC-B owns it; the point is the guard
  precedes the hysteresis/nearest-center paths, not patches them.
- **Startup camera (coordinate with WP-G):** recommended precedence — **last-viewed viewport IF #153's
  serialized map-screen state actually persists a reusable viewport** (recon flagged that #153
  "serialize map screen model state" is *not confirmed* to include the viewport — **verify before
  relying on it**; if it doesn't, this tier is vaporware and WP-G's default is the real top tier) →
  **WP-G's single configurable default** → **never auto-locate at launch** (no surprise permission
  prompt; P5). Location enters only on an explicit locate tap. WP-G owns the configurable default; this
  design just declines to auto-locate.

## 6. The snow-marking loop — RULED (A) spec-faithful (Rob, 2026-07-17)

**Rob ruled (A):** *"we build tracks by looking at the timestamps on visited items but that comes
later."* No passive location trail; **§3.4 / P5 / P6 stay untouched.** The escalated (B) passive-trail
option is **off the table** (it would have needed an argued §3.4/P5/P6 amendment; Rob declined it). The
snow is marked by the **deliberate** loop, and location *serves* that loop — it never writes it.

**The in-scope snow mechanic — the foreground nearby-prompt loop (spec §3.4 / B8):**
- Follow-me shows where you are → as you move, the app compares your fix against the **already-loaded
  viewport places** (spec §5.4: an in-memory scan, no spatial query, no new storage) → when you're near
  an un-seen place it offers a **foreground prompt** *"You're near X — seen it?"* → **one tap** marks it
  seen (spec §3.4, unchanged) → that pin fades. This is "moving marks the snow," done deliberately.
- **Foreground-only, v1** (spec §3.4): no background nudges (that's a v2 always-on-location decision).
  The prompt is a gentle, dismissible surface — never a nag; declining is free and silent (P5).
- **"Fresh snow / My tracks" toggle** (spec §17/§3.2) renders trodden vs untrodden: your "trail" is the
  **constellation of places you've marked**, not a GPS line. (The toggle itself is B8's; this design
  only wires the located loop that feeds it.)

**Settled B6 direction — recorded, deferred (Rob pre-affirmed, NOT this design's build scope):**
Tracks is a **derived view over the `visits` log's timestamps** — the chronological constellation of
deliberately-marked places, rendered via `place_snapshots` (spec §3.1/B6). No separate history model,
no location data. **Deferred to the B6 work package**; recorded here so it is not re-litigated. This
design ships the *located loop that feeds visits*, not the Tracks screen.

## Build-WP decomposition (proposed — §6 rows firm up on Rob's ruling)

| WP | side | scope | depends on |
|---|---|---|---|
| **WP-LOC-B** follow-me + location UX | **app (`ios`)** | follow-me `MLNUserTrackingMode` state machine (+ compass heading, pan-breaks-follow); `scenePhase` battery/backgrounding gating; out-of-coverage located state; startup-camera precedence (coordinate WP-G). **Consumes** the shared permission component (below), does not re-own the manager | codex bare locate-me + permission helper; WP-G (configurable default) |
| **WP-LOC-PERM** permission-flow component | **app (`ios`)** | the reusable authorization component (status observer, request, Settings deep-link, published stream) — **codex is building it on `wp/map-chrome-2`**; this design owns its contract so the locate button **and** onboarding (B10) share one owner | (codex in-flight) |
| **nearby-prompt loop** | **app (`ios`), folds into B8** | foreground "You're near X — seen it?" over the loaded viewport places (§3.4/B8) fed by the located loop; one-tap seen unchanged. The "Fresh snow / My tracks" toggle stays B8's | WP-LOC-B; B4 one-tap (built) |

**Deferred (recorded, not built here):** **B6 Tracks** = derived chronological view over `visits`
timestamps (Rob pre-affirmed) — its own work package later.

## Gate & acceptance

- **Adversarial gate (done): 4 critics (privacy-lifecycle / principle-fidelity / feasibility /
  coherence) → verify. Raised 13, 7 survived, all folded.** The no-passive-trail ruling held — nothing
  smuggled a location trail — but the gate caught real slips:
  - **My own headline privacy invariant still said "never stored beyond the on-device *trail*"** —
    pre-ruling (B) phrasing that reads as blessing a location store. Rewritten: **no coordinate is ever
    stored; the only persisted history is the place-anchored `visits` log** (§Why).
  - **"already debounced" was false** — the map loop has result-coalescing, not call-throttling, so
    continuous follow would fire a full viewport/region/DB refresh per location update. WP-LOC-B **must
    add real throttling** (§2).
  - **Heading architecture was self-contradictory** — native `MLNUserTrackingMode` is MapLibre-driven,
    but §3's accuracy/`distanceFilter`/heading discipline needs an app-owned manager. Resolved by
    **injecting a custom `MLNLocationManager`** the app configures (§2) — one `CLLocationManager`,
    shared with the permission component.
  - **Out-of-coverage rationale mis-read `MapRegion.select`** — the wrong far-region case is the
    hysteresis *current-sticky* branch, not nearest-center; the guard must run **caller-side before
    `select`** (§5).
  - **Startup "last-viewed viewport" was unconfirmed** — #153's serialized state isn't confirmed to
    hold a viewport; softened to verify-first, else WP-G's default is the real top tier (§5).
- PR → `develop`, `sourcery-review` only, report `docs/location-design`. No self-merge; fable reviews;
  `main` is Rob's.
