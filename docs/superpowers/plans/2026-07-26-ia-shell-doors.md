# IA Shell Doors Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the hamburger and standalone Layers entry with persistent World and Tracks doors, preserve all existing destinations and deep links, and reduce the remaining map chrome to the ruled compass, locate control, doors, and bare attribution.

**Architecture:** `AppShellModel` becomes a door-aware router that owns one presented door and an optional destination. Focused SwiftUI door/chrome views move to `MapDoorShell.swift`; the existing destination views remain in `MapScreen.swift` to avoid a big-bang extraction. `MapScreen` continues to own sheet coordination and dismisses World before presenting the unchanged `LayersSheet`, while `MLNMapViewRepresentable` configures MapLibre's built-in compass.

**Tech Stack:** Swift 6, SwiftUI, Observation, MapLibre Native iOS 6.27+, XCTest/XCUITest, the local `DesignSystem` Swift package, XcodeGen, and the designated simulator through `scripts/sim-lock.sh`.

## Global Constraints

- Target iOS 18+ with Swift 6 strict concurrency and warnings as errors.
- Implement `docs/superpowers/specs/2026-07-25-design-system-and-ia-design.md` §2 and the T1.6 row in `docs/superpowers/phases/phase-1/tasks.md`.
- Treat `docs/design/design-system/ia-doors.png` as certification of the door pattern only; the spec's World and Tracks row lists supersede the render.
- World rows are Scope, Settings, and About. Offline maps remains reachable through Settings and direct deep links, not a World root row.
- Tracks rows are Lists and My tracks. Their current destinations are provisional until T1.8.
- Scope dismisses World and presents the existing `LayersSheet` unchanged; do not merge list filter chips into it.
- Remove `openMenu`, the hamburger, `AppMenuRootView`, and the standalone `map.layers` button.
- Preserve `openListDetailDeepLink`, `openListsDeepLink`, `openTracksDeepLink`, and both `openOfflineMapsDeepLink` callers.
- Use MapLibre's built-in compass, which appears after rotation; do not create a SwiftUI compass.
- Reserve no visible Search control. The shell layout must leave the ruled search slot unobstructed for DS-11.
- Doors use machinery voice, monochrome medium SF Symbols, token surfaces, hairlines, and token shadows.
- Attribution remains `map.openstreetmap-attribution`, becomes bare 11pt muted text, and has no background.
- Locate remains `map.locate-me`, preserves all three current symbols and accessibility labels, and moves from blur to token surface.
- Every interactive target is at least 44×44pt and must survive AX5 Dynamic Type, Reduce Transparency, and dark appearance.
- Re-point affected UI tests; never delete coverage merely to make the suite green.
- Record the ruled Scope transition under `## Taste guesses`, including the rejected stacked-presentation alternative.
- PR targets `ios`, names issue #468 and task T1.6, carries `track-b-ios`, `wp`, `sourcery-review`, and `greptile-review`, and states that Tracks routing is provisional.

---

### Task 1: Door-aware routing state

**Files:**
- Modify: `ios/App/Sources/Map/MapScreen.swift`
- Modify: `ios/App/Tests/AppShellTests.swift`

**Interfaces:**
- Produces: `MapDoor`, `MapShellDestination`, and `AppShellModel.presentedDoor`.
- Produces: `openWorldDoor()`, `openTracksDoor()`, and the retained deep-link methods.
- Consumes: `TracksVisitFilter`.

- [ ] **Step 1: Replace the menu-model tests with failing door-routing tests**

```swift
func testAppShellModelOpensEachDoorAtItsRoot() {
    let shell = AppShellModel()

    shell.openWorldDoor()
    XCTAssertEqual(shell.presentedDoor, .world)
    XCTAssertNil(shell.deepLinkDestination)

    shell.openTracksDoor()
    XCTAssertEqual(shell.presentedDoor, .tracks)
    XCTAssertNil(shell.deepLinkDestination)
}

func testDeepLinksChooseTheirOwningDoor() {
    let shell = AppShellModel()

    shell.openOfflineMapsDeepLink()
    XCTAssertEqual(shell.presentedDoor, .world)
    XCTAssertEqual(shell.deepLinkDestination, .offlineMaps)

    shell.openListsDeepLink()
    XCTAssertEqual(shell.presentedDoor, .tracks)
    XCTAssertEqual(shell.deepLinkDestination, .lists)

    shell.openListDetailDeepLink(listID: 42)
    XCTAssertEqual(shell.presentedDoor, .tracks)
    XCTAssertEqual(shell.deepLinkDestination, .listDetail(42))
}
```

- [ ] **Step 2: Run the focused tests and verify the new API fails to compile**

Run:

```bash
./scripts/sim-lock.sh xcodebuild test -project ios/App/MakingTracks.xcodeproj -scheme MakingTracks -destination 'platform=iOS Simulator,id=C4A64D49-24A2-4429-B6E2-AD9A14142A99' -only-testing:MakingTracksTests/AppShellTests
```

Expected: FAIL because `MapDoor`, `presentedDoor`, and `deepLinkDestination` do not exist.

- [ ] **Step 3: Implement the minimal door-aware router**

```swift
enum MapDoor: Hashable, Identifiable {
    case world
    case tracks

    var id: Self { self }
}

enum MapShellDestination: Hashable {
    case lists
    case listDetail(Int64)
    case tracks
    case offlineMaps
    case settings
    case diagnostics
    case about
}

@Observable
final class AppShellModel {
    var presentedDoor: MapDoor?
    var deepLinkDestination: MapShellDestination?
    var tracksFocusPlaceID: String?
    var listDetailVisitFilter = TracksVisitFilter.all

    func openWorldDoor() {
        prepareRoot(door: .world)
    }

    func openTracksDoor() {
        prepareRoot(door: .tracks)
    }

    private func prepareRoot(door: MapDoor) {
        tracksFocusPlaceID = nil
        listDetailVisitFilter = .all
        deepLinkDestination = nil
        presentedDoor = door
    }
}
```

Update every retained deep-link method so World owns `.offlineMaps`, `.settings`, `.diagnostics`, and `.about`, while Tracks owns `.lists`, `.listDetail`, and `.tracks`.

- [ ] **Step 4: Run the focused tests and verify they pass**

Run the Step 2 command.

Expected: all `AppShellTests` pass with zero failures.

- [ ] **Step 5: Commit the routing slice**

```bash
git add ios/App/Sources/Map/MapScreen.swift ios/App/Tests/AppShellTests.swift
git commit -m "Route app destinations through map doors"
```

---

### Task 2: Token-backed persistent door chrome

**Files:**
- Create: `ios/App/Sources/Map/MapDoorShell.swift`
- Regenerate: `ios/App/MakingTracks.xcodeproj/project.pbxproj`
- Modify: `ios/App/Tests/AppShellTests.swift`

**Interfaces:**
- Consumes: `MapDoor`, `MaterialTheme.snow.tokens`, and `Typography`.
- Produces: `MapDoorChromeSpec`, `MapDoorButton`, and `MapDoorBar`.
- Produces accessibility identifiers `map.door.world` and `map.door.tracks`.

- [ ] **Step 1: Add failing exact-value tests for the ruled door contract**

```swift
func testMapDoorChromeMatchesRuledMaterialContract() {
    XCTAssertEqual(MapDoorChromeSpec.worldTitle, "World")
    XCTAssertEqual(MapDoorChromeSpec.tracksTitle, "Tracks")
    XCTAssertEqual(MapDoorChromeSpec.worldSymbol, "globe.europe.africa")
    XCTAssertEqual(MapDoorChromeSpec.tracksSymbol, "shoeprints.fill")
    XCTAssertGreaterThanOrEqual(MapDoorChromeSpec.minimumHitTarget, 44)
    XCTAssertEqual(MapDoorChromeSpec.doorTypographyRole, .button)
    XCTAssertEqual(MapDoorChromeSpec.attributionTypographyRole, .label)
    XCTAssertEqual(MapDoorChromeSpec.rowTitleTypographyRole, .listRowTitle)
    XCTAssertEqual(MapDoorChromeSpec.sheetTitleTypographyRole, .sheetTitle)
}
```

- [ ] **Step 2: Run `AppShellTests` and verify failure**

Run the Task 1 Step 2 command.

Expected: FAIL because `MapDoorChromeSpec` does not exist.

- [ ] **Step 3: Add the focused door views**

`MapDoorShell.swift` must define:

```swift
import DesignSystem
import SwiftUI

enum MapDoorChromeSpec {
    static let worldTitle = "World"
    static let tracksTitle = "Tracks"
    static let worldSymbol = "globe.europe.africa"
    static let tracksSymbol = "shoeprints.fill"
    static let minimumHitTarget: CGFloat = 44
    static let doorTypographyRole = TypographyRole.button
    static let attributionTypographyRole = TypographyRole.label
    static let rowTitleTypographyRole = TypographyRole.listRowTitle
    static let sheetTitleTypographyRole = TypographyRole.sheetTitle
}

struct MapDoorBar: View {
    let openWorld: () -> Void
    let openTracks: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            MapDoorButton(door: .world, action: openWorld)
            MapDoorButton(door: .tracks, action: openTracks)
        }
        .accessibilityElement(children: .contain)
    }
}
```

`MapDoorButton` uses a `Label`, `Typography.font(for: .button)`, `surface`, `hairline`, and `shadow` tokens, a capsule shape, a 44pt minimum target, and the door-specific identifier. It must contain no blur/material background.

- [ ] **Step 4: Regenerate the checked-in project and run the focused tests**

Run:

```bash
xcodegen generate --spec ios/App/project.yml
```

Then run the Task 1 Step 2 command.

Expected: project generation succeeds and all `AppShellTests` pass.

- [ ] **Step 5: Commit the chrome slice**

```bash
git add ios/App/Sources/Map/MapDoorShell.swift ios/App/MakingTracks.xcodeproj/project.pbxproj ios/App/Tests/AppShellTests.swift
git commit -m "Add persistent map door chrome"
```

---

### Task 3: Door sheets and preserved destinations

**Files:**
- Modify: `ios/App/Sources/Map/MapDoorShell.swift`
- Modify: `ios/App/Sources/Map/MapScreen.swift`
- Modify: `ios/App/Tests/AppShellTests.swift`

**Interfaces:**
- Produces: `MapDoorSheet`, `WorldDoorRootView`, and `TracksDoorRootView`.
- Consumes: `MaterialSheet`, `MaterialRaisedCardRow`, `MaterialHairlineRow`.
- Consumes destination builder `(MapShellDestination) -> Content`.
- Produces row identifiers `world.row.scope`, `world.row.settings`, `world.row.about`, `tracks.row.lists`, and `tracks.row.my-tracks`.

- [ ] **Step 1: Add failing root-row contract tests**

```swift
func testDoorRootsExposeOnlyRuledRows() {
    XCTAssertEqual(WorldDoorRow.allCases, [.scope, .settings, .about])
    XCTAssertEqual(TracksDoorRow.allCases, [.lists, .myTracks])
    XCTAssertFalse(WorldDoorRow.allCases.map(\.title).contains("Offline maps"))
    XCTAssertFalse(WorldDoorRow.allCases.map(\.title).contains("Coverage"))
}
```

- [ ] **Step 2: Run the focused tests and verify failure**

Run the Task 1 Step 2 command.

Expected: FAIL because the row enums do not exist.

- [ ] **Step 3: Implement the row models and sheet roots**

Define `CaseIterable` row enums with titles, SF Symbols, subtitles, and identifiers. Implement each row as a plain `Button` whose content is wrapped by `MaterialRaisedCardRow` for the first/high-priority row and `MaterialHairlineRow` for quiet rows. Use `Typography.font(for: .sheetTitle)` for World/Tracks sheet titles, `.listRowTitle` for row titles, and `.metadata` for subtitles. Keep the close control supplied by `MaterialSheet`.

`MapDoorSheet` owns:

```swift
@State private var path: [MapShellDestination] = []
let door: MapDoor
let deepLinkDestination: MapShellDestination?
let openScope: () -> Void
let destination: (MapShellDestination) -> Destination
```

On appearance and deep-link change:

```swift
if let deepLinkDestination {
    path = deepLinkDestination.listDetailPath
}
```

where `listDetailPath` returns `[.lists, .listDetail(id)]` for a list detail and `[self]` otherwise. The root view switches on `door`; no combined app-menu root survives.

- [ ] **Step 4: Rename destination routing without changing destination implementations**

Rename `MenuDestination` to `MapShellDestination`, `AppMenuSheet` to the door-aware sheet integration, and `path` bindings in `SettingsView`. Keep `ListsView`, `ListDetailDeepLinkView`, `TrackListDetailDeepLinkView`, `OfflineMapsView`, `SettingsView`, `DiagnosticsView`, and `AboutView` behavior unchanged.

- [ ] **Step 5: Run focused tests and a Release build**

Run the Task 1 Step 2 command, then:

```bash
MT_RELEASE_GATE_MODE=build ./scripts/sim-lock.sh ./scripts/release-gate.sh
```

Expected: all focused tests pass and Release build completes with zero warnings.

- [ ] **Step 6: Commit the sheet slice**

```bash
git add ios/App/Sources/Map/MapDoorShell.swift ios/App/Sources/Map/MapScreen.swift ios/App/Tests/AppShellTests.swift
git commit -m "Replace the app menu with door sheets"
```

---

### Task 4: Built-in compass and quiet chrome

**Files:**
- Modify: `ios/App/Sources/Map/MLNMapViewRepresentable.swift`
- Modify: `ios/App/Sources/Map/MapScreen.swift`
- Modify: `ios/App/Tests/AppShellTests.swift`

**Interfaces:**
- Configures: `MLNMapView.showsCompassView`, `compassViewPosition`, `compassViewMargins`, and `compassView.compassVisibility`.
- Preserves: `map.openstreetmap-attribution`, `map.locate-me`, the three locate symbols, and their current labels.

- [ ] **Step 1: Add failing quiet-chrome contract tests**

```swift
func testQuietChromeUsesTokenSurfacesAndBareAttribution() {
    XCTAssertEqual(MapDoorChromeSpec.attributionTypographyRole, .label)
    XCTAssertFalse(MapDoorChromeSpec.attributionHasBackground)
    XCTAssertEqual(MapDoorChromeSpec.locateMinimumHitTarget, 44)
    XCTAssertTrue(MapDoorChromeSpec.usesBuiltInCompass)
}
```

- [ ] **Step 2: Run the focused tests and verify failure**

Run the Task 1 Step 2 command.

Expected: FAIL for the new constants.

- [ ] **Step 3: Configure MapLibre's compass**

In `makeUIView`, configure the SDK-owned compass:

```swift
map.showsCompassView = true
map.compassViewPosition = .topRight
map.compassViewMargins = CGPoint(x: 16, y: 12)
map.compassView.compassVisibility = .adaptive
map.compassView.tintColor = UIColor(MaterialTheme.snow.tokens.muted.swiftUIColor)
```

Do not add a SwiftUI compass or call `resetNorth` from a new control.

- [ ] **Step 4: Restyle attribution and locate**

Render attribution as bare machinery text:

```swift
Text(verbatim: "© OpenStreetMap")
    .font(Typography.font(for: MapDoorChromeSpec.attributionTypographyRole))
    .foregroundStyle(MaterialTheme.snow.tokens.muted.swiftUIColor)
```

Remove its padding, capsule, and material. Change only the locate button's background from `.ultraThinMaterial` to the token `surface` with token hairline/shadow; retain existing icon state and accessibility behavior.

- [ ] **Step 5: Run focused tests and the Release build**

Run the Task 1 Step 2 command and the Task 3 Release-build command.

Expected: tests pass and Release build completes with zero warnings.

- [ ] **Step 6: Commit the quiet-chrome slice**

```bash
git add ios/App/Sources/Map/MLNMapViewRepresentable.swift ios/App/Sources/Map/MapScreen.swift ios/App/Tests/AppShellTests.swift
git commit -m "Adopt built-in compass and quiet map chrome"
```

---

### Task 5: Integrate persistent doors and migrate UI coverage

**Files:**
- Modify: `ios/App/Sources/Map/MapScreen.swift`
- Modify: `ios/App/UITests/MakingTracksCoreLoopUITests.swift`
- Modify: `ios/App/Tests/AppShellTests.swift`

**Interfaces:**
- Consumes: `MapDoorBar`, `AppShellModel.presentedDoor`, and `MapDoorSheet`.
- Produces: one-sheet-at-a-time Scope transition.
- Retires: `MapHomeChromeSpec.menuSymbolName`, `layersButton`, `map.menu`, `map.layers`, `menu.row.*`, and `menu.done`.

- [ ] **Step 1: Add failing UI tests for both doors and Scope**

Add one compact home test:

```swift
func testMapHomeExposesBothDoorsAndScopeOpensLayers() {
    let app = launchFixtureMap()

    XCTAssertTrue(app.buttons["map.door.world"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["map.door.tracks"].exists)
    XCTAssertFalse(app.buttons["map.menu"].exists)
    XCTAssertFalse(app.buttons["map.layers"].exists)

    app.buttons["map.door.world"].tap()
    app.buttons["world.row.scope"].tap()
    XCTAssertTrue(app.navigationBars["Layers"].waitForExistence(timeout: 5))
}
```

- [ ] **Step 2: Run only the new UI test and verify failure**

Run:

```bash
./scripts/sim-lock.sh xcodebuild test -project ios/App/MakingTracks.xcodeproj -scheme MakingTracks -destination 'platform=iOS Simulator,id=C4A64D49-24A2-4429-B6E2-AD9A14142A99' -only-testing:MakingTracksUITests/MakingTracksCoreLoopUITests/testMapHomeExposesBothDoorsAndScopeOpensLayers
```

Expected: FAIL because the door identifiers do not yet render on `MapScreen`.

- [ ] **Step 3: Integrate the bottom door bar and sheet presentation**

Replace the hamburger/layers `shellChrome` with only list navigation/filter/download state that still belongs at top-leading. Add a bottom overlay containing `MapDoorBar` and the bare attribution. Raise list-mode controls, nearby prompt, hidden toast, and locate chrome by a shared door-bar clearance so they never overlap at standard or AX5 sizes.

Bind the sheet with an optional-item presentation:

```swift
.sheet(item: $appShell.presentedDoor) { door in
    MapDoorSheet(
        door: door,
        deepLinkDestination: appShell.deepLinkDestination,
        openScope: openScopeFromWorld,
        destination: destinationView
    )
}
```

Implement `openScopeFromWorld` by clearing `presentedDoor` and scheduling `showLayers = true` on the next main-actor turn. This prevents simultaneous sheets and leaves `LayersSheet` unchanged.

- [ ] **Step 4: Re-point every affected UI test**

Create focused helpers:

```swift
private func openWorldDoor(in app: XCUIApplication) {
    let door = app.buttons["map.door.world"]
    XCTAssertTrue(door.waitForExistence(timeout: 5))
    door.tap()
}

private func openTracksDoor(in app: XCUIApplication) {
    let door = app.buttons["map.door.tracks"]
    XCTAssertTrue(door.waitForExistence(timeout: 5))
    door.tap()
}

private func openScope(in app: XCUIApplication) {
    openWorldDoor(in: app)
    app.buttons["world.row.scope"].tap()
}
```

Re-point list/track navigation to Tracks, settings/about to World, and every old Layers entry to `openScope`. Replace `menu.done` assertions with the MaterialSheet close button label `Close`. Rewrite menu-inventory assertions to the exact per-door row inventories; do not delete destination or deep-link tests.

- [ ] **Step 5: Verify no retired production/test identifiers remain**

Run:

```bash
rg -n 'map\.menu|map\.layers"|menu\.row\.|menu\.done|openAppMenu|AppMenuRootView|openMenu\(' ios/App
```

Expected: no matches, except `map.layers.*` identifiers belonging to controls inside the unchanged `LayersSheet`.

- [ ] **Step 6: Run focused app tests and the full host package suite**

Run the Task 1 Step 2 command, then:

```bash
cd ios && swift test
```

Expected: all app-shell tests and all host tests pass with zero failures.

- [ ] **Step 7: Commit the integration slice**

```bash
git add ios/App/Sources/Map/MapScreen.swift ios/App/UITests/MakingTracksCoreLoopUITests.swift ios/App/Tests/AppShellTests.swift
git commit -m "Integrate World and Tracks door navigation"
```

---

### Task 6: Accessibility, renders, full gate, and review handoff

**Files:**
- Modify: `docs/superpowers/phases/phase-1/tasks.md`
- Create: `docs/design/design-system/t1.6-ia-shell.html`
- Create: `docs/design/design-system/t1.6-ia-shell.png`
- Create: `docs/design/design-system/t1.6-ia-shell-ax.html`
- Create: `docs/design/design-system/t1.6-ia-shell-ax.png`
- Modify: issue #468 body and PR body through `gh`.

**Interfaces:**
- Produces: home, World-open, and Tracks-open evidence at 390×844 plus an AX5 accessibility variant.
- Produces: gate counts, adversarial-review accounting, provisional Tracks note, and Taste guesses.

- [ ] **Step 1: Run focused simulator scenarios**

Through `./scripts/sim-lock.sh`, verify:

- Home shows World and Tracks with no hamburger or standalone Layers button.
- World opens Scope, Settings, and About only.
- Scope transitions to the unchanged Layers sheet in discovery and list modes.
- Tracks opens Lists and My tracks, and direct list-detail/tracks deep links preserve their current destination behavior.
- Offline maps remains reachable from Settings and both direct callers.
- Compass is hidden north-up and appears after rotation.
- Locate retains all three states.
- AX5 keeps every door/row tappable without clipping.
- Reduce Transparency and dark appearance keep solid token surfaces legible.

- [ ] **Step 2: Render the required implementation evidence**

Create a fidelity packet that shows 390×844 home, World-open, and Tracks-open frames, plus a separate AX5 home/door-sheet stress frame. Base it only on the already-frozen IA pattern and the ratified §2 row list; do not introduce or rule a new layout. Commit the HTML sources and PNG renders beside the established design-system assets.

- [ ] **Step 3: Run the complete host and simulator gates**

Run:

```bash
cd ios && swift test
```

Then:

```bash
./scripts/sim-lock.sh ./scripts/release-gate.sh
```

Expected: host suite, Release build, app tests, and UI tests all pass with exact counts recorded from output.

- [ ] **Step 4: Perform adversarial self-review with teeth**

Review five lenses: spec fidelity, routing/internal coherence, Swift/MapLibre correctness, privacy/untrusted-data posture, and test quality. For each fixed defect, temporarily neuter the behavior and run the narrow test to prove it turns red, then restore and rerun green. Record raised/survived/fixed counts.

- [ ] **Step 5: Push and open the PR**

Push `wp-468-ia-shell-doors`, open a PR into `ios`, and apply `track-b-ios`, `wp`, `sourcery-review`, and `greptile-review` immediately. The body must include:

- `#468` and `T1.6`.
- Exact host/full-gate test counts.
- Render links.
- Adversarial-review accounting.
- `## Taste guesses`: Scope dismisses World then opens the existing Layers sheet; the rejected alternative was pushing/stacking Layers inside World.
- An explicit note that Tracks-door routing is provisional until T1.8.

- [ ] **Step 6: Record and announce checkpoint transitions**

Update T1.6 in `docs/superpowers/phases/phase-1/tasks.md` and send the matching AMQ status at each allowed transition: `tests green`, `PR open`, `review clean`, and `ready-to-merge`. Do not self-merge.
