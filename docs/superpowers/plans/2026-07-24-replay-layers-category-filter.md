# Replay Layers Category Filter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make category switches in the Layers sheet scope list-map pins, the replay timeline, and autoplay to the same active visit set.

**Architecture:** Keep discovery category visibility and active list/replay category scope as separate state. While a list map is active, derive the Layers sheet visibility from `ActiveListMap.visitFilter`, and write category changes back to that filter before refreshing the replay context. Represent category scope as `nil` for all categories and a non-optional set inside `some`, including an empty set for no categories.

**Tech Stack:** Swift 6, SwiftUI, GRDB-backed `MakingTracksData`, XCTest/XCUITest, MapLibre.

## Global Constraints

- Work only on `wp-257-replay-filter-regression`, branched from `ios`; the PR targets `ios`.
- All simulator access goes through `./scripts/sim-lock.sh`.
- Preserve discovery Layers category state when entering and leaving list/replay mode.
- Category scope is tri-state: `nil` means all, a non-empty set means only those categories, and an empty set means none.
- Unknown and future category IDs follow the same `uncategorized` (“Other”) fallback in replay filtering and map-style filtering.
- The dedicated Filter tracks sheet exposes an explicit “All types” row so all and none never render identically.
- Filtered-out visits have no pins, timeline beats, autoplay dwell, or arcs.
- Do not persist a new track object or category setting.

---

### Task 1: Reproduce the Layers control-path failure

**Files:**
- Modify: `ios/App/UITests/MakingTracksCoreLoopUITests.swift`

**Interfaces:**
- Consumes: the `seedVisitsEditorVisual` fixture, `openLayers(in:)`, `tapSwitch(in:identifier:expectedValue:)`, and replay accessibility identifiers.
- Produces: `testLayersCategoryFilterScopesReplayTimelineAndAutoplay()`.

- [ ] **Step 1: Write the failing UI test**

Add a test that opens `My tracks`, shows it on the map, opens Layers, taps `map.layers.show-all-categories`, enables only `map.layers.category.attraction`, closes the sheet, and expects:

```swift
XCTAssertTrue(waitForTrackReplayCounter("Visit 2 of 2", in: app))
XCTAssertTrue(waitForTrackReplayArrival(
    prefix: "Visit 2 of 2, Petronas Twin Towers Observation Deck",
    in: app
))
app.buttons["map.track-replay.play"].tap()
XCTAssertTrue(waitForTrackReplayCounter("Visit 1 of 2", in: app))
XCTAssertTrue(waitForTrackReplayArrival(
    prefix: "Visit 1 of 2, Ghost Sign",
    in: app
))
```

- [ ] **Step 2: Run the test to verify the root-cause failure**

Run:

```bash
./scripts/sim-lock.sh xcodebuild test \
  -project ios/App/MakingTracks.xcodeproj \
  -scheme MakingTracks \
  -destination 'platform=iOS Simulator,id=C4A64D49-24A2-4429-B6E2-AD9A14142A99' \
  -derivedDataPath /private/tmp/dd-codex2 \
  -parallel-testing-enabled NO \
  -disable-concurrent-destination-testing \
  -maximum-concurrent-test-simulator-destinations 1 \
  -only-testing:MakingTracksUITests/MakingTracksCoreLoopUITests/testLayersCategoryFilterScopesReplayTimelineAndAutoplay
```

Expected: FAIL because the replay counter remains `Visit 8 of 8`.

### Task 2: Give track filters explicit category-scope semantics

**Files:**
- Modify: `ios/Sources/MakingTracksData/Models/TracksVisitFilter.swift`
- Add: `ios/Sources/MakingTracksData/Models/PlaceCategoryTaxonomy.swift`
- Modify: `ios/Sources/MakingTracksData/Derivations.swift`
- Modify: `ios/Sources/MakingTracksMapStyle/PinLayers.swift`
- Modify: `ios/Tests/MakingTracksDataTests/DerivationsTests.swift`
- Modify: `ios/Tests/MakingTracksMapStyleTests/TaxonomyContractTests.swift`
- Modify: `ios/App/Sources/Map/MapScreen.swift`
- Modify: `ios/App/Tests/AppShellTests.swift`

**Interfaces:**
- Consumes: existing `TracksVisitFilter` callers and category chips.
- Produces: `TracksVisitFilter.categories: Set<String>?`, where `nil` is all and `.some([])` is none.

- [ ] **Step 1: Add data-layer tests for all, some, and no categories**

Extend the existing combined track-filter test with:

```swift
XCTAssertEqual(try db.trackVisits(filter: TracksVisitFilter(categories: nil)).count, allVisitCount)
XCTAssertEqual(
    try db.trackVisits(filter: TracksVisitFilter(categories: Set<String>())).count,
    0
)
```

- [ ] **Step 2: Run the data test and verify the empty-set assertion fails**

Run:

```bash
cd ios && swift test --filter DerivationsTests
```

Expected: FAIL because the current empty set means all categories.

- [ ] **Step 3: Implement the tri-state category scope**

Change the model to:

```swift
public var categories: Set<String>?

public var isActive: Bool {
    lovedOnly || !listIDs.isEmpty || categories != nil
}

public init(
    lovedOnly: Bool = false,
    listIDs: Set<Int64> = [],
    categories: Set<String>? = nil
) {
    self.lovedOnly = lovedOnly
    self.listIDs = listIDs
    self.categories = categories
}
```

Change the derivation predicate to use the shared place-category taxonomy:

```swift
guard filter.includes(category: visit.category) else { return false }
```

Update chips and the picker draft to unwrap the optional set. `toggleCategory(_:)` must change `nil` to a one-category set, insert into an existing set, and change the last selected category back to `nil`. Preserve exact matching for explicitly selected legacy/unknown raw category IDs, while the `uncategorized` selection matches every unknown ID.

Add an explicit “All types” row to the picker for the `.some([])` state, and share the known-category IDs plus `uncategorized` fallback between `TracksVisitFilter` and `PinLayers`.

- [ ] **Step 4: Run the data and app unit tests**

Run:

```bash
cd ios && swift test --filter DerivationsTests
./scripts/sim-lock.sh xcodebuild test \
  -project ios/App/MakingTracks.xcodeproj \
  -scheme MakingTracks \
  -destination 'platform=iOS Simulator,id=C4A64D49-24A2-4429-B6E2-AD9A14142A99' \
  -derivedDataPath /private/tmp/dd-codex2 \
  -parallel-testing-enabled NO \
  -disable-concurrent-destination-testing \
  -maximum-concurrent-test-simulator-destinations 1 \
  -only-testing:MakingTracksTests/AppShellTests
```

Expected: the category-scope and filter-chip tests pass.

### Task 3: Bind Layers categories to the active replay filter

**Files:**
- Modify: `ios/App/Sources/Map/MapLayerVisibility.swift`
- Modify: `ios/App/Sources/Map/MapScreen.swift`
- Modify: `ios/App/Tests/MapLayerVisibilityTests.swift`
- Test: `ios/App/UITests/MakingTracksCoreLoopUITests.swift`

**Interfaces:**
- Consumes: `MapLayerVisibility.visibleCategories`, `ActiveListMap.visitFilter`, and `refreshActiveListMap(updateCamera:)`.
- Produces: a list-aware Layers binding that preserves discovery category visibility.

- [ ] **Step 1: Add pure binding-policy tests**

Add tests that prove:

```swift
let displayed = ListMapLayerVisibility.displayed(
    discovery: discoveryVisibility,
    visitFilter: TracksVisitFilter(categories: ["attraction"])
)
XCTAssertEqual(displayed.visibleCategories, ["attraction"])
XCTAssertEqual(discoveryVisibility.visibleCategories, ["museum"])

let hiddenAll = ListMapLayerVisibility.updating(
    visitFilter: .all,
    from: MapLayerVisibility(visibleCategories: [])
)
XCTAssertEqual(hiddenAll.categories, [])
XCTAssertTrue(hiddenAll.isActive)
```

- [ ] **Step 2: Run the policy tests and verify they fail because the helper is absent**

Run:

```bash
./scripts/sim-lock.sh xcodebuild test \
  -project ios/App/MakingTracks.xcodeproj \
  -scheme MakingTracks \
  -destination 'platform=iOS Simulator,id=C4A64D49-24A2-4429-B6E2-AD9A14142A99' \
  -derivedDataPath /private/tmp/dd-codex2 \
  -parallel-testing-enabled NO \
  -disable-concurrent-destination-testing \
  -maximum-concurrent-test-simulator-destinations 1 \
  -only-testing:MakingTracksTests/MapLayerVisibilityTests
```

Expected: FAIL with `cannot find 'ListMapLayerVisibility' in scope`.

- [ ] **Step 3: Implement the list-aware binding**

Add a pure `ListMapLayerVisibility` helper and use it in a computed `Binding<MapLayerVisibility>`:

```swift
private var layersVisibilityBinding: Binding<MapLayerVisibility> {
    Binding(
        get: {
            ListMapLayerVisibility.displayed(
                discovery: layerVisibility,
                visitFilter: activeListMap?.visitFilter
            )
        },
        set: { visibility in
            applyLayersSheetVisibility(visibility)
        }
    )
}
```

When an active list exists, copy hidden/coverage settings back to discovery state, update `activeListMap.visitFilter.categories` from `visibility.visibleCategories`, stop autoplay, and call `refreshActiveListMap(updateCamera: true)`. When no list is active, assign the visibility directly. Use the derived visibility for the Layers button’s active styling and accessibility value.

- [ ] **Step 4: Run the Layers UI regression and existing dedicated-filter regression**

Run:

```bash
./scripts/sim-lock.sh xcodebuild test \
  -project ios/App/MakingTracks.xcodeproj \
  -scheme MakingTracks \
  -destination 'platform=iOS Simulator,id=C4A64D49-24A2-4429-B6E2-AD9A14142A99' \
  -derivedDataPath /private/tmp/dd-codex2 \
  -parallel-testing-enabled NO \
  -disable-concurrent-destination-testing \
  -maximum-concurrent-test-simulator-destinations 1 \
  -only-testing:MakingTracksUITests/MakingTracksCoreLoopUITests/testLayersCategoryFilterScopesReplayTimelineAndAutoplay \
  -only-testing:MakingTracksUITests/MakingTracksCoreLoopUITests/testTrackCategoryFilterScopesReplayTimelineAndAutoplay
```

Expected: both tests pass with two attraction events and the correct autoplay arrival names.

- [ ] **Step 5: Run the repository gate and commit**

Run:

```bash
./scripts/sim-lock.sh ./scripts/release-gate.sh
```

Expected: release build and required tests pass with no warnings. Then stage the exact files, create a signed imperative commit, push `wp-257-replay-filter-regression`, update issue #257, and open a PR into `ios`.
