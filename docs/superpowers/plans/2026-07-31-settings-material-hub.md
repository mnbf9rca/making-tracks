# Settings Material Hub Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild Settings as W-2's ruled seven-group DS-1 material hub while preserving every existing setting, route, identifier, contextual Offline maps deep link, and accessibility behavior.

**Architecture:** Keep `MapDoorSheet`'s existing `NavigationStack` and close convention. `SettingsView` becomes a Snow-token `ScrollView` root whose seven `SettingsGroup` rows are composed from `MaterialHairlineRow` inside one raised card; `NavigationLink(value:)` routes focused Appearance, Coverage, Map & data, and Location pages through new `MapShellDestination` cases, while Offline maps and Diagnostics keep their existing destinations and Replay welcome keeps its existing direct action. Small value types own the ruled group order, copy, icons, identifiers, and destinations so app tests can pin the mapping without rendering private SwiftUI views.

**Tech Stack:** Swift 6, SwiftUI, DesignSystem material tokens/rows, XCTest/XCUITest, XcodeGen project, `scripts/sim-lock.sh`.

## Global Constraints

- Target branch is `ios`; T2.9 starts from the ruled W-2 landing and serves #472 / AC2.14, AC2.15, and AC2.19.
- Exact root order: Appearance · Offline maps · Coverage · Map & data · Location · Diagnostics · Replay welcome.
- The root and new focused Settings pages use DS-1 material rows and Snow tokens, never a system `List`.
- Appearance retains all four current themes, their IDs, selection values, and `map.theme.id` behavior; DS-7 owns any later theme migration.
- Offline maps retains `settings.storage.manage`; the progress pill and empty-region action still resolve to `.offlineMaps`.
- Coverage is data-only: published regions, sources, and extents; it contains no coverage-shading switch.
- Map & data retains `settings.downloads.allow-cellular` and `settings.pin-size`, including slider range, step, preview, and spoken value.
- Location retains its dynamic status and `settings.location.open-system`.
- Diagnostics retains `settings.diagnostics.export` and routes to the unchanged Diagnostics screen; DS-9 owns its re-skin.
- Replay welcome retains `settings.replay-onboarding` and invokes the unchanged flow.
- Dynamic Type through AX5 wraps rather than clips; every navigational/action row has at least a 44×44 target and exposes a label, value/summary, and action without relying on colour alone.
- App-target changes require the full host tests, locked Release build, locked simulator test gate, and default/AX render evidence.

---

### Task 1: Pin the ruled group contract

**Files:**
- Modify: `ios/App/Tests/AppShellTests.swift`
- Modify: `ios/App/Sources/Map/MapScreen.swift`

**Interfaces:**
- Produces: `SettingsGroupPresentation: Equatable`
- Produces: `SettingsGroup: CaseIterable`, including `presentation` and `destination`
- Consumes: existing `MapShellDestination`

- [ ] **Step 1: Write the failing contract tests**

Add tests that demand the exact W-2 order, copy, icon, identifier, and routing:

```swift
func testSettingsGroupsMatchRuledW2OrderAndRoutes() {
    XCTAssertEqual(SettingsGroup.allCases, [
        .appearance, .offlineMaps, .coverage, .mapAndData,
        .location, .diagnostics, .replayWelcome,
    ])
    XCTAssertEqual(SettingsGroup.allCases.map(\.presentation), [
        .init(title: "Appearance", subtitle: "Four existing presets", systemImage: "circle.lefthalf.filled", accessibilityIdentifier: "settings.group.appearance"),
        .init(title: "Offline maps", subtitle: "Packs · downloads · per-pack storage", systemImage: "externaldrive.badge.arrow.down", accessibilityIdentifier: "settings.storage.manage"),
        .init(title: "Coverage", subtitle: "Published regions · sources · extents", systemImage: "map", accessibilityIdentifier: "settings.group.coverage"),
        .init(title: "Map & data", subtitle: "Cellular downloads · pin size", systemImage: "map.circle", accessibilityIdentifier: "settings.group.map-data"),
        .init(title: "Location", subtitle: "Permission and system settings", systemImage: "location", accessibilityIdentifier: "settings.group.location"),
        .init(title: "Diagnostics", subtitle: "Review or export local logs", systemImage: "arrow.up.doc", accessibilityIdentifier: "settings.diagnostics.export"),
        .init(title: "Replay welcome", subtitle: "Return to the existing welcome flow", systemImage: "arrow.counterclockwise.circle", accessibilityIdentifier: "settings.replay-onboarding"),
    ])
    XCTAssertEqual(SettingsGroup.appearance.destination, .settingsAppearance)
    XCTAssertEqual(SettingsGroup.offlineMaps.destination, .offlineMaps)
    XCTAssertEqual(SettingsGroup.coverage.destination, .settingsCoverage)
    XCTAssertEqual(SettingsGroup.mapAndData.destination, .settingsMapAndData)
    XCTAssertEqual(SettingsGroup.location.destination, .settingsLocation)
    XCTAssertEqual(SettingsGroup.diagnostics.destination, .diagnostics)
    XCTAssertNil(SettingsGroup.replayWelcome.destination)
}

func testSettingsCoverageContractIsDataOnly() {
    let coverage = SettingsGroup.coverage.presentation
    XCTAssertEqual(coverage.subtitle, "Published regions · sources · extents")
    XCTAssertFalse(coverage.subtitle.localizedCaseInsensitiveContains("shading"))
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run under the codex2 simulator seat:

```bash
MT_RELEASE_GATE_DESTINATION='platform=iOS Simulator,id=BACC2CF8-C1F8-4C92-B058-47B0AC0B128D' \
  ./scripts/sim-lock.sh xcodebuild \
  -project ios/App/MakingTracks.xcodeproj \
  -scheme MakingTracks \
  -destination 'platform=iOS Simulator,id=BACC2CF8-C1F8-4C92-B058-47B0AC0B128D' \
  -parallel-testing-enabled NO \
  -disable-concurrent-destination-testing \
  -only-testing:MakingTracksTests/AppShellTests/testSettingsGroupsMatchRuledW2OrderAndRoutes \
  -only-testing:MakingTracksTests/AppShellTests/testSettingsCoverageContractIsDataOnly \
  test
```

Expected: compile failure because `SettingsGroup`, its destination cases, and `SettingsGroupPresentation` do not exist.

- [ ] **Step 3: Add the minimal contract**

Add these `MapShellDestination` cases:

```swift
case settingsAppearance
case settingsCoverage
case settingsMapAndData
case settingsLocation
```

Add `SettingsGroupPresentation` and `SettingsGroup` beside the existing Settings navigation contract. The presentation switch must return exactly the tested values; the destination switch returns `nil` only for `.replayWelcome`.

- [ ] **Step 4: Run the focused contract tests and verify GREEN**

Repeat the Step 2 command. Expected: 2 tests passed, 0 failures, no new warnings.

- [ ] **Step 5: Commit**

```bash
git add ios/App/Tests/AppShellTests.swift ios/App/Sources/Map/MapScreen.swift
git commit -m "Define the ruled Settings group contract"
```

---

### Task 2: Build the DS-1 root and focused subareas

**Files:**
- Modify: `ios/App/Tests/AppShellTests.swift`
- Modify: `ios/App/Sources/Map/MapScreen.swift`

**Interfaces:**
- Consumes: `SettingsGroup`, `SettingsGroupPresentation`, `MapShellDestination`
- Produces: `SettingsView` root hub
- Produces: private `SettingsMaterialPage`, `SettingsGroupRow`, `SettingsAppearanceView`, `SettingsCoverageView`, `SettingsMapAndDataView`, and `SettingsLocationView`

- [ ] **Step 1: Write the failing architecture test**

Read `MapScreen.swift`, slice from `private struct SettingsView` up to `private struct DiagnosticsView`, and assert:

```swift
XCTAssertFalse(settingsSource.contains("List {"))
XCTAssertTrue(settingsSource.contains("MaterialHairlineRow"))
XCTAssertTrue(settingsSource.contains("SettingsGroup.allCases"))
XCTAssertFalse(settingsSource.contains("map.layers.coverage-shading"))
```

Name the test `testSettingsHubUsesMaterialRowsWithoutSystemListChrome`.

- [ ] **Step 2: Run the architecture test and verify RED**

Use the locked focused `xcodebuild test` command from Task 1 with:

```text
-only-testing:MakingTracksTests/AppShellTests/testSettingsHubUsesMaterialRowsWithoutSystemListChrome
```

Expected: assertion failure because the current `SettingsView` contains `List {` and no material rows.

- [ ] **Step 3: Replace the root List with the ruled material hub**

Implement:

```swift
private struct SettingsView: View {
    var body: some View {
        SettingsMaterialPage(
            title: "Settings",
            subtitle: "Things you set once, grouped into material subareas."
        ) {
            Text("Settings groups")
                .font(Typography.font(for: .label))
                .textCase(.uppercase)

            VStack(spacing: 0) {
                ForEach(SettingsGroup.allCases, id: \.self) { group in
                    settingsGroupRow(group)
                }
            }
            .background(
                MaterialTheme.snow.tokens.surfaceRaised.swiftUIColor,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}
```

`SettingsMaterialPage` is a `GeometryReader` + `ScrollView` + leading `VStack`, uses `.sheetTitle`, `.evocativeSubline`, `.body`, `.metadata`, and Snow token colours, and never creates a `List`. `SettingsGroupRow` wraps its label in `MaterialHairlineRow`, uses the W-2 75pt default / 120pt AX minimum, a 20pt icon scaled from `.body`, Newsreader `.listRowTitle`, metadata summary, and a trailing chevron. Apply explicit `.accessibilityLabel`, `.accessibilityValue`, and identifiers.

Appearance's root summary names the current selected theme and draws four accessibility-hidden colour dots; selection is also named in the accessibility value.

- [ ] **Step 4: Move current controls into focused pages without changing behavior**

- `SettingsAppearanceView`: move the existing four `MapTheme.allCandidates` buttons unchanged, retaining every `settings.theme.\(theme.id)` identifier, selected value, and selected trait.
- `SettingsCoverageView`: render three material hairline information rows — Published regions, Sources, Extents — and explanatory text pointing region management to Offline maps and licensing to About. Do not add a toggle or reference `map.layers.coverage-shading`.
- `SettingsMapAndDataView`: move the cellular-download toggle and pin preview/slider unchanged, retaining both existing identifiers and slider math.
- `SettingsLocationView`: move the existing dynamic location status/action unchanged and retain `settings.location.open-system`.
- Root `.offlineMaps` and `.diagnostics` rows remain `NavigationLink(value:)` routes to the existing destinations.
- Root `.replayWelcome` remains a direct `Button` invoking `replayOnboarding`.

Add the four new cases to `MapDoorContent.destinationView`, passing the same bindings/status/actions as the old inline controls.

- [ ] **Step 5: Run contract and architecture tests and verify GREEN**

Run all three focused `AppShellTests`. Expected: 3 tests passed, 0 failures, no new warnings.

- [ ] **Step 6: Run the host package suite**

```bash
swift test --package-path ios
```

Restore the incidental `ios/Package.resolved` rewrite immediately after reading the counts. Expected: all host tests pass.

- [ ] **Step 7: Commit**

```bash
git add ios/App/Tests/AppShellTests.swift ios/App/Sources/Map/MapScreen.swift
git commit -m "Rebuild Settings as a material hub"
```

---

### Task 3: Prove routes, accessibility, and default/AX rendering

**Files:**
- Modify: `ios/App/Tests/AppShellTests.swift`
- Modify: `ios/App/UITests/MakingTracksCoreLoopUITests.swift`
- Modify if a real defect is found: `ios/App/Sources/Map/MapScreen.swift`

**Interfaces:**
- Consumes: existing `openExploreDoor`, `scrollToHittable`, screenshot helpers, and retained accessibility identifiers
- Produces: regression coverage for W-2 root order, focused pages, Offline maps callers, Diagnostics, Replay welcome, and AX wrapping

- [ ] **Step 1: Write failing UI expectations before changing UI behavior**

Update `testSettingsThemePickerSelectsRealTheme` to require `settings.group.appearance` before any theme button exists, tap it, then perform the existing selection assertions unchanged.

Add `testSettingsHubRoutesEveryRuledGroupWithoutLosingExistingActions`:

- assert the seven root identifiers exist in W-2 order while scrolling;
- assert every row is hittable and at least 44pt in both dimensions;
- open Appearance and verify all four theme IDs;
- open Offline maps through `settings.storage.manage`;
- open Coverage and verify `settings.coverage.published-regions`, `.sources`, and `.extents`, plus absence of `map.layers.coverage-shading`;
- open Map & data and verify `settings.downloads.allow-cellular` and `settings.pin-size`;
- open Location and verify the dynamic location copy/action;
- open Diagnostics through `settings.diagnostics.export`;
- invoke Replay welcome through `settings.replay-onboarding`.

Add `testOfflineMapContextualCallersKeepTheirDeepLinkAtPointOfUse`, a source-contract test that independently requires both current `appShell.openOfflineMapsDeepLink()` call sites: the empty-region card action and the progress-pill `onOpenOfflineMaps` closure. This complements the existing live progress-pill navigation test and prevents either caller from being dropped during the regrouping.

Add a default/AX render test that captures the Settings root and all seven destinations/actions under both ordinary and accessibility text sizes: Appearance, Offline maps, Coverage, Map & data, Location, Diagnostics, and Replay welcome. Use stable attachment names such as `settings-root-default`, `settings-appearance-ax`, and `settings-map-data-ax`.

- [ ] **Step 2: Run the changed theme-picker UI test and verify RED**

Use the codex2 destination through `sim-lock.sh` with:

```text
-only-testing:MakingTracksUITests/MakingTracksCoreLoopUITests/testSettingsThemePickerSelectsRealTheme
```

Expected: failure because `settings.group.appearance` does not exist in the pre-change UI.

- [ ] **Step 3: Complete only the code needed by the failing UI evidence**

Fix identifier placement, row hit regions, navigation, accessibility values, wrapping, or back navigation only where the failing test demonstrates a defect. Do not re-skin Diagnostics or Replay welcome.

- [ ] **Step 4: Run focused UI tests and verify GREEN**

Run the theme, hub-route, both independent Offline maps caller checks, Diagnostics route test, pin-size test, and the default/AX render test under the codex2 simulator lock. Expected: all selected tests pass with no app assertion or harness failures.

- [ ] **Step 5: Export render evidence**

Read screenshot attachments from the focused `.xcresult`, record their exact names and dimensions, copy the default/AX Settings evidence into `.mt-data/screenshots/`, and remove the result bundle after counts and attachments are extracted.

- [ ] **Step 6: Commit**

```bash
git add ios/App/UITests/MakingTracksCoreLoopUITests.swift ios/App/Sources/Map/MapScreen.swift
git commit -m "Prove Settings routes and AX layout"
```

---

### Task 4: Full gates, adversarial review, and handoff

**Files:**
- Modify: `docs/superpowers/phases/phase-2/tasks.md`
- Modify only for verified findings: files from Tasks 1–3

**Interfaces:**
- Produces: exact host/unit/UI/Release counts, warning count, render inventory, adversarial accounting, and PR status

- [ ] **Step 1: Re-ground on current `origin/ios`**

Fetch `ios`, inspect the file-level base delta, and rebase. If any reviewed source or test file changed, rerun every affected focused gate; a docs-only advance carries prior evidence forward.

- [ ] **Step 2: Run the full host suite**

```bash
swift test --package-path ios
```

Record exact counts and restore `ios/Package.resolved`.

- [ ] **Step 3: Run the locked Release build and full simulator gate**

```bash
export MT_RELEASE_GATE_DESTINATION='platform=iOS Simulator,id=BACC2CF8-C1F8-4C92-B058-47B0AC0B128D'
./scripts/sim-lock.sh ./scripts/release-gate.sh
```

Record build/unit/UI counts, duration, and warnings. Classify any red only under `docs/ios-gate-ledger.md`.

- [ ] **Step 4: Perform adversarial self-review**

Attack at least ten plausible failures: stock `List` surviving, theme IDs/selection changing, Offline maps route drift, contextual deep-link drift, Coverage shading duplication, cellular/pin controls lost, Location action lost, Diagnostics re-skinned, Replay action lost, AX clipping, colour-only state, undersized rows, and concurrent T2.10 overlap. Fix surviving findings with a new failing test first and report raised/survived/fixed/refuted counts.

- [ ] **Step 5: Update the durable ledger and publish**

Open a ready PR into `ios`, capture the returned PR number, set T2.9 to `PR open — #` followed by that exact number, commit, and push. Apply `sourcery-review`, `track-b-ios`, and `wp`; the body names #472, exact gate counts, render evidence, threat-model result, taste guesses (expected: none), and adversarial accounting.

- [ ] **Step 6: Process every automated and human review thread**

Use the repository review workflows, verify fixes on the exact new head, update the ledger to the correct review state, and announce the exact handoff SHA to planner over AMQ. Do not self-merge.
