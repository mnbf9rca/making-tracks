# WP-221 Visit Sheet Layout and Drag Float Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore top-aligned Visit date sheet layout and make the active My tracks row travel with the user's drag without changing reorder results.

**Architecture:** Keep the ruled custom My tracks chrome, compact rows, app-drawn reorder handle, destination calculation, accessibility actions, and edge auto-scroll. Present Visit date as a page within the already full-height My tracks surface instead of creating a nested presentation. Keep the full-height track page in layout while the editor is active, but hide it from accessibility and hit testing. Replace the editor chrome's greedy clear symmetry spacer with a hidden duplicate of the Back label so the title remains centered at standard and accessibility Dynamic Type sizes. During reorder, hide the lazy source card and render a frozen-frame copy in a list-level overlay whose `@GestureState` translation follows the finger. Own each drag recognizer in a stable parent overlay, but limit its hit region to the measured 44-by-44-point handle; retain only the active handle's frozen surface when its lazy row scrolls offscreen. Keep edge-target selection and timing in SwiftUI, while a noninteractive, accessibility-identified UIKit bridge applies bounded content-offset steps to the owning `List` because SwiftUI's two programmatic-scroll APIs ignore requests during the active custom drag.

**Tech Stack:** Swift 6, SwiftUI, XCTest, XCUITest, the designated iOS simulator through `scripts/sim-lock.sh`.

## Global Constraints

- Target iOS 18+ and Swift 6 strict concurrency.
- Preserve the appearance-invariant paper palette and flat custom chrome ratified on issue #221.
- Preserve visit identity, destination calculation, accessibility reorder, and edge auto-scroll behavior.
- Touch the designated simulator only through `scripts/sim-lock.sh`.
- Use one reusable derived-data path: `/private/tmp/dd-codex3-wp221`.
- Introduce zero warnings.

---

### Task 1: Pin and repair the Visit date sheet layout

**Files:**
- Modify: `ios/App/Sources/Map/MapScreen.swift`
- Modify: `ios/App/UITests/MakingTracksCoreLoopUITests.swift`

**Interfaces:**
- Consumes: `AppMenuSheet`, `TrackVisitDateEditorView`, `lists.detail.visit-date.back`, and the existing rendered-pixel oracle fixture.
- Produces: an in-surface editor page and a two-sided geometry assertion aligning the child and owner navigation rows.

- [x] **Step 1: Write the failing UI assertion**

XCUITest does not expose this custom SwiftUI presentation as an `app.sheets` node. In `assertMyTracksRenderedPixelOracle`, capture the owning sheet's Back-button height before opening Visit date, then require the Visit date Back button to remain hittable, inside the device canvas, and within 20 points of that adaptive top:

```swift
XCTAssertEqual(
    visitDateBack.frame.minY,
    expectedVisitDateChromeMinY,
    accuracy: 20
)
```

- [x] **Step 2: Run the focused UI test to verify RED**

Run the `testMyTracksRenderedPixelOraclesAcrossLightAndDarkAppearances` UI test through:

```bash
./scripts/sim-lock.sh xcodebuild test \
  -project ios/App/MakingTracks.xcodeproj \
  -scheme MakingTracks \
  -destination 'platform=iOS Simulator,id=C4A64D49-24A2-4429-B6E2-AD9A14142A99' \
  -derivedDataPath /private/tmp/dd-codex3-wp221 \
  -parallel-testing-enabled NO \
  -maximum-concurrent-test-simulator-destinations 1 \
  -only-testing:MakingTracksUITests/MakingTracksCoreLoopUITests/testMyTracksRenderedPixelOraclesAcrossLightAndDarkAppearances
```

Observed: FAIL at y=254 versus a maximum of 174.8.

- [x] **Step 3: Present Visit date within the owning page bounds**

Nested-sheet and navigation attempts (`.presentationSizing(.page)`, `.presentationDetents([.large])`, flexible frames, a live owner-height environment value, local navigation destinations, and measured overlays) retained the same apparent y=246 result. A diagnostic accessibility probe established that the editor root was already at y=62 with zero safe-area inset. The actual cause was the trailing `Color.clear` having only minimum dimensions: it greedily expanded the navigation HStack to consume the VStack's surplus height, centering the Back control at y=246. Keep the editor in the owning `ZStack`, but give the symmetry spacer fixed dimensions and give the chrome its standard minimum height:

```swift
ZStack(alignment: .top) {
    trackListPage
    trackVisitEditorPage
}

Text("‹ My tracks")
    .font(.body.weight(.semibold))
    .frame(minWidth: 88, minHeight: 44, alignment: .trailing)
    .hidden()
    .accessibilityHidden(true)

navigationChrome
    .frame(maxWidth: .infinity, minHeight: TrackVisitEditorVisualSpec.chromeMinimumHeight)
```

- [x] **Step 4: Run the focused UI test to verify GREEN**

Run the command from Step 2.

Observed: PASS in both Light and Dark appearance. The strict sheet-top geometry assertions pass, and the opaque editor interior remains pixel-identical; the comparison excludes only the system-owned rounded corners that expose the appearance-dependent map beneath the sheet.

### Task 2: Pin and repair active-row drag travel

**Files:**
- Modify: `ios/App/Sources/Map/MapScreen.swift`
- Modify: `ios/App/Tests/AppShellTests.swift`
- Modify: `ios/Tests/MakingTracksTilesTests/LoggingPrivacyTests.swift`

**Interfaces:**
- Consumes: `TrackVisitDragVisualSpec`, `trackVisitReorderGesture(for:)`, and the existing `TrackVisitDragTrigger` destination logic.
- Produces: `TrackVisitDragVisualSpec.overlayFrame(startFrame:translationY:)`, a list-level drag overlay, and gesture-owned translation.

- [x] **Step 1: Write failing unit and structural tests**

Pin translation-aware overlay geometry:

```swift
XCTAssertEqual(
    TrackVisitDragVisualSpec.overlayFrame(
        startFrame: CGRect(x: 16, y: 120, width: 370, height: 64),
        translationY: 90
    ),
    CGRect(x: 16, y: 207, width: 370, height: 64)
)
```

Replace the stale `.onMove` source assertion with checks that the lazy source card is hidden, the parent overlay is rendered, and `@GestureState` supplies live translation.

- [x] **Step 2: Run focused tests to verify RED**

Run:

```bash
./scripts/sim-lock.sh xcodebuild test \
  -project ios/App/MakingTracks.xcodeproj \
  -scheme MakingTracks \
  -destination 'platform=iOS Simulator,id=C4A64D49-24A2-4429-B6E2-AD9A14142A99' \
  -derivedDataPath /private/tmp/dd-codex3-wp221 \
  -parallel-testing-enabled NO \
  -maximum-concurrent-test-simulator-destinations 1 \
  -only-testing:MakingTracksTests/AppShellTests/testTrackVisitDragVisualSpecLiftsOnlyTheActiveRow
```

Run:

```bash
swift test --package-path ios \
  --filter LoggingPrivacyTests.testTrackVisitDateHeadersAreNotStandaloneMovableRows
```

Run the structural overlay regression:

```bash
swift test --package-path ios \
  --filter LoggingPrivacyTests.testTrackVisitCustomDragUsesAnOverlayIndependentOfTheLazySourceRow
```

- [x] **Step 3: Implement an independent drag overlay**

Measure each card in the list coordinate space. Create exact 44-by-44-point gesture surfaces over the visible reorder handles in a stable parent overlay, retaining the active surface at its frozen frame if the corresponding lazy row unmounts. Convert named-space geometry into the outer overlay's local coordinates before positioning both the gesture surface and floating copy. At drag start, freeze that card frame in parent state; hide the source card; draw a copy in a list-level overlay positioned from the frozen frame plus `@GestureState` translation. Track gesture activity separately from translation so crossing zero does not look like cancellation, and centralize cleanup so genuine cancellation and disappearance clear identity, frozen geometry, and auto-scroll. Preserve the existing SwiftUI edge-target calculation and timer; use a main-actor `UIViewRepresentable` probe to select only the effectively visible `UICollectionView` identified as `lists.detail.surface.track`, require positive overlap, and apply adjusted-inset-clamped offset steps. Do not change drop destination calculation, row identity, or accessibility actions. A real trailing-gutter swipe test proves that no full-height hit area steals ordinary List scrolling.

- [x] **Step 4: Run focused tests to verify GREEN**

Run all three commands from Step 2.

Observed: all three focused tests pass with zero failures. Real XCUITests additionally pass for a direct handle reorder, an initially offscreen visit becoming visible through edge auto-scroll before persistence is checked, and ordinary scrolling from the trailing gutter outside a handle.

### Task 3: Verify and deliver

**Files:**
- Modify: `docs/superpowers/plans/2026-07-24-wp-221-sheet-layout-drag-float.md`
- Produce: device screenshots and PR evidence outside the tracked source tree unless the issue gate requires committed artifacts.

**Interfaces:**
- Consumes: the fixes from Tasks 1–2 and issue #221's M1–M6 device-fidelity gate.
- Produces: a pushed iOS-targeting PR with exact test counts, visual evidence, review accounting, and dual-channel status updates.

- [x] **Step 1: Run host and full simulator gates**

Run:

```bash
swift test --package-path ios
```

Run:

```bash
./scripts/sim-lock.sh ./scripts/release-gate.sh
```

Expected: all host, app/unit, UI, and Release build checks pass with zero warnings.

Observed after the final signed merge of `origin/ios` at `fbf215f2`: host Swift
tests pass 389/389. The mandatory simulator gate passes its Release
warnings-as-errors build, 185/185 app/unit tests, and 70/70 UI tests.

- [x] **Step 2: Produce Light and Dark device evidence**

Run the rendered-pixel oracle on the designated simulator in both appearances, export the Visit date screenshots, and compare them against the issue's frozen layout. Confirm the navigation row is at the sheet top and capture a drag-in-progress view showing the active row under the finger.

Observed: the strict rendered-pixel oracle passes in both appearances and exports
`/private/tmp/making-tracks-artifacts/my-tracks-rendered-oracle-light.png`,
`my-tracks-rendered-oracle-dark.png`,
`my-tracks-visit-date-oracle-light.png`, and
`my-tracks-visit-date-oracle-dark.png`. The geometry assertions prove the editor
chrome remains at the sheet top. Real handle-drag UI tests prove direct travel,
edge auto-scroll to an initially offscreen visit, persisted order, and ordinary
gutter scrolling.

- [x] **Step 3: Run adversarial review**

Review spec fidelity, SwiftUI correctness, gesture behavior, accessibility, hostile-content handling under threat-model §2, and test teeth. Neuter each surviving fix and confirm its regression test fails before restoring it.

Observed: three independent adversarial reviews approved the drag/test behavior,
SwiftUI/layout correctness, and spec/security/privacy scope. The focused tests
were written against the regressions and observed RED before the fixes; all
focused, structural, pixel-oracle, accessibility, and full-gate tests are GREEN
after restoring the implementation.

- [ ] **Step 4: Re-ground, push, and open the PR**

Fetch `origin/ios`, merge it if needed, rerun affected gates, review `git diff --stat origin/ios..HEAD`, push the branch, and open an `ios`-targeting PR linked to issue #221 with `sourcery-review`, `track-b-ios`, and `wp`.

- [ ] **Step 5: Dual-deliver status**

Post each transition (`tests green`, `PR open`, `review clean`, `ready-to-merge`) both to Fable over AMQ and as an issue #221 comment.
