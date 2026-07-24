# WP-221 Visit Sheet Layout and Drag Float Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore top-aligned Visit date sheet layout and make the active My tracks row travel with the user's drag without changing reorder results.

**Architecture:** Keep the ruled custom My tracks chrome, compact rows, app-drawn reorder handle, destination calculation, accessibility actions, and edge auto-scroll. Present Visit date as a page within the already full-height My tracks surface instead of creating a nested presentation. A top-aligned `ZStack` keeps the full-height track list participating in layout while the editor is visible, so both pages share the owning surface's live coordinate origin through rotation and window resizing. During reorder, hide the lazy source card and render a frozen-frame copy in a list-level overlay whose `@GestureState` translation follows the finger even when edge auto-scroll unmounts the source row.

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
- Produces: an owner-bounds page overlay and a two-sided geometry assertion aligning the child and owner navigation rows.

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

Nested-sheet and navigation attempts (`.presentationSizing(.page)`, `.presentationDetents([.large])`, flexible frames, a live owner-height environment value, local navigation destinations, and a measured overlay) retained the same shortened intrinsic-height proposal. Keep the editor inside `ListDetailView`, disable and accessibility-hide the underlying track page while it is active, and make both pages top-aligned siblings while the full-height list remains in layout:

```swift
ZStack(alignment: .top) {
    trackListPage
    trackVisitEditorPage
}
```

- [ ] **Step 4: Run the focused UI test to verify GREEN**

Run the command from Step 2.

Expected: PASS in both Light and Dark appearance, with the existing pixel identity oracle still green.

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
swift test --filter LoggingPrivacyTests.testTrackVisitDateHeadersAreNotStandaloneMovableRows
```

Run the structural overlay regression:

```bash
swift test --package-path ios \
  --filter LoggingPrivacyTests.testTrackVisitCustomDragUsesAnOverlayIndependentOfTheLazySourceRow
```

- [x] **Step 3: Implement an independent drag overlay**

Measure each card in the list coordinate space. At drag start, freeze that card frame in parent state; hide the source card; draw a copy in a list-level overlay positioned from the frozen frame plus `@GestureState` translation. Centralize cleanup so gesture cancellation and disappearance clear identity, frozen geometry, and auto-scroll. Do not change drop destination calculation, row identity, accessibility actions, or auto-scroll.

- [x] **Step 4: Run focused tests to verify GREEN**

Run both commands from Step 2.

Expected: both pass with zero failures.

### Task 3: Verify and deliver

**Files:**
- Modify: `docs/superpowers/plans/2026-07-24-wp-221-sheet-layout-drag-float.md`
- Produce: device screenshots and PR evidence outside the tracked source tree unless the issue gate requires committed artifacts.

**Interfaces:**
- Consumes: the fixes from Tasks 1–2 and issue #221's M1–M6 device-fidelity gate.
- Produces: a pushed iOS-targeting PR with exact test counts, visual evidence, review accounting, and dual-channel status updates.

- [ ] **Step 1: Run host and full simulator gates**

Run:

```bash
swift test
```

Run:

```bash
./scripts/sim-lock.sh ./scripts/release-gate.sh
```

Expected: all host, app/unit, UI, and Release build checks pass with zero warnings.

- [ ] **Step 2: Produce Light and Dark device evidence**

Run the rendered-pixel oracle on the designated simulator in both appearances, export the Visit date screenshots, and compare them against the issue's frozen layout. Confirm the navigation row is at the sheet top and capture a drag-in-progress view showing the active row under the finger.

- [ ] **Step 3: Run adversarial review**

Review spec fidelity, SwiftUI correctness, gesture behavior, accessibility, hostile-content handling under threat-model §2, and test teeth. Neuter each surviving fix and confirm its regression test fails before restoring it.

- [ ] **Step 4: Re-ground, push, and open the PR**

Fetch `origin/ios`, merge it if needed, rerun affected gates, review `git diff --stat origin/ios..HEAD`, push the branch, and open an `ios`-targeting PR linked to issue #221 with `sourcery-review`, `track-b-ios`, and `wp`.

- [ ] **Step 5: Dual-deliver status**

Post each transition (`tests green`, `PR open`, `review clean`, `ready-to-merge`) both to Fable over AMQ and as an issue #221 comment.
