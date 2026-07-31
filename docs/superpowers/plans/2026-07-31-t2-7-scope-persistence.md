# T2.7 Scope Persistence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist all four discovery-scope choices as one bounded, versioned record, migrate shipped coverage-shading state, expose an accurate default-scope predicate, and prove discovery scope never filters Journal derivations.

**Architecture:** `MakingTracksMapStyle` owns a host-testable `DiscoveryScope` value and `DiscoveryScopeStore` because both the map app and its existing host tests already consume that package. The store reads and writes one deterministic JSON record in `UserDefaults`, understands versions 0 and 1, rejects newer or malformed records to defaults, and migrates the shipped `map.coverageShading.visible` key. The app-only `MapLayerVisibility` adapts between UI categories and `DiscoveryScope`; `MapScreen` loads once and saves from its existing single `layerVisibility` change seam.

**Tech Stack:** Swift 6, Foundation `Codable` and `UserDefaults`, SwiftUI state, XCTest, Swift Package Manager, the existing simulator release gate.

## Global Constraints

- iOS 18+ and Swift 6 strict concurrency remain unchanged.
- Defaults are hidden OFF, saved ON, coverage ON, and all categories visible.
- The current reader version is 1; version 0 migrates deterministically; versions above 1, malformed records, and invalid bounded content degrade to defaults.
- The shipped `map.coverageShading.visible` key migrates for both `true` and `false` and is removed only after the new record is written.
- An explicitly empty category set is valid user intent; a parse or validation failure must never become an empty set.
- Category identifiers are stored sorted so repeated saves are deterministic.
- No picker UI, identifier rename, render, or change to `Derivations.swift` belongs to T2.7.
- Tests name the behavior they protect and exercise real storage and real derivations without mocks.

---

### Task 1: Versioned discovery-scope store

**Files:**
- Create: `ios/Sources/MakingTracksMapStyle/DiscoveryScopeStore.swift`
- Create: `ios/Tests/MakingTracksMapStyleTests/DiscoveryScopeStoreTests.swift`

**Interfaces:**
- Produces: `public struct DiscoveryScope: Equatable, Sendable`
- Produces: `public static let DiscoveryScope.defaults`
- Produces: `public var DiscoveryScope.differsFromDefault: Bool`
- Produces: `public struct DiscoveryScopeStore`
- Produces: `DiscoveryScopeStore.init(userDefaults: UserDefaults)`
- Produces: `DiscoveryScopeStore.load() -> DiscoveryScope`
- Produces: `DiscoveryScopeStore.save(_ scope: DiscoveryScope)`
- Produces: `DiscoveryScopeStore.reset()`
- Produces: `DiscoveryScopeStore.storageKey == "map.scope.record"` and `DiscoveryScopeStore.legacyCoverageShadingKey == "map.coverageShading.visible"`

- [ ] **Step 1: Write failing real-`UserDefaults` tests**

Add a unique suite per test and remove its persistent domain in `tearDown`. Cover these literal outcomes:

```swift
XCTAssertEqual(DiscoveryScope.defaults, DiscoveryScope(
    visibleCategoryIDs: nil,
    includeHidden: false,
    showSaved: true,
    showCoverageShading: true
))
XCTAssertFalse(DiscoveryScope.defaults.differsFromDefault)
XCTAssertTrue(DiscoveryScope(showCoverageShading: false).differsFromDefault)
```

Save and reload a scope with `visibleCategoryIDs: ["museum", "history"]`, hidden ON, saved OFF, and coverage OFF; assert exact equality and assert the persisted JSON carries `"version":1` with categories ordered `["history","museum"]`.

Feed literal JSON records for:

```json
{"version":2,"visibleCategoryIDs":[],"includeHidden":true,"showSaved":false,"showCoverageShading":false}
{"version":0,"categories":["museum"],"showHiddenPlaces":true,"showSavedPlaces":false,"showCoverageShading":false}
{"version":1,"visibleCategoryIDs":
```

Assert respectively: defaults for the newer record, the exact migrated v1 scope plus rewritten `"version":1`, and defaults rather than an empty category set for malformed JSON.

Set the shipped legacy key to `true` and `false` in separate cases. Assert both values migrate into otherwise-default scopes, the new record exists, and the legacy key is removed.

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
cd ios
swift test --filter DiscoveryScopeStoreTests
```

Expected: compilation fails because `DiscoveryScope` and `DiscoveryScopeStore` do not exist.

- [ ] **Step 3: Implement the bounded versioned store**

Implement `DiscoveryScope` with the four public choices and defaulted initializer arguments. Implement private `VersionEnvelope`, `RecordV0`, and `RecordV1` Codable shapes in the store file.

`load()` must:

1. Prefer `map.scope.record` when present.
2. Reject data above 65,536 bytes.
3. Decode only the version envelope first.
4. Decode v1 exactly; decode v0 and immediately rewrite it as v1.
5. Reject versions outside `0...1` to `.defaults`.
6. Validate at most 128 category identifiers, each non-empty and at most 128 UTF-8 bytes.
7. Preserve an empty category array as an empty set.
8. Use the shipped coverage key only when no new record exists, then save v1 before removing the old key.

`save()` must encode sorted category identifiers with `JSONEncoder.OutputFormatting.sortedKeys`. `reset()` removes both keys.

- [ ] **Step 4: Run focused and package tests and verify GREEN**

Run:

```bash
cd ios
swift test --filter DiscoveryScopeStoreTests
swift test
```

Expected: all new tests pass and the package total increases from the 499-test baseline with zero failures.

- [ ] **Step 5: Commit the store**

```bash
git add ios/Sources/MakingTracksMapStyle/DiscoveryScopeStore.swift ios/Tests/MakingTracksMapStyleTests/DiscoveryScopeStoreTests.swift
git commit -m "Persist versioned discovery scope"
```

### Task 2: Map visibility adapter and accurate default predicate

**Files:**
- Modify: `ios/App/Sources/Map/MapLayerVisibility.swift`
- Modify: `ios/App/Tests/MapLayerVisibilityTests.swift`

**Interfaces:**
- Consumes: `DiscoveryScope`
- Produces: `MapLayerVisibility.init(categories:scope:)`
- Produces: `MapLayerVisibility.discoveryScope: DiscoveryScope`
- Preserves: `MapLayerVisibility.isDefault`, now including coverage shading

- [ ] **Step 1: Change the predicate test and add adapter tests**

Replace `testCoverageShadingDefaultsOnButDoesNotAffectDefaultFilterState` with a test that asserts coverage OFF makes `isDefault` false and restoring coverage ON makes it true.

Add a round-trip test using two explicit categories and this literal scope:

```swift
let scope = DiscoveryScope(
    visibleCategoryIDs: ["museum"],
    includeHidden: true,
    showSaved: false,
    showCoverageShading: false
)
```

Assert the initialized visibility exposes only `"museum"`, all three booleans, and the same `discoveryScope`. Add a case where stored identifiers contain only `"removed-category"` and assert the category axis degrades to all live categories while the other valid scope choices survive, never to an empty scope.

- [ ] **Step 2: Run the focused app test and verify RED**

Run through the simulator wrapper with the assigned seat destination:

```bash
export MT_RELEASE_GATE_DESTINATION='platform=iOS Simulator,id=42D1482C-DE04-49AA-990D-1884ED9B855D'
./scripts/sim-lock.sh xcodebuild -project ios/App/MakingTracks.xcodeproj -scheme MakingTracks -destination "$MT_RELEASE_GATE_DESTINATION" -only-testing:MakingTracksTests/MapLayerVisibilityTests test
```

Expected: the coverage predicate assertion fails and the adapter API is absent.

- [ ] **Step 3: Implement the adapter**

Make `isDefault` delegate to `!discoveryScope.differsFromDefault`. Build `discoveryScope` from the current booleans and `visibleCategories`.

In `init(categories:scope:)`, intersect stored category identifiers with the live category set. If the stored set was non-empty but the intersection is empty, normalize the category axis to `nil` while preserving the other valid scope choices; if the stored set contains every live category, also normalize it to `nil`; preserve a deliberately empty stored set.

- [ ] **Step 4: Run the focused app test and verify GREEN**

Re-run the Step 2 command. Expected: `MapLayerVisibilityTests` passes with zero failures.

- [ ] **Step 5: Commit the adapter**

```bash
git add ios/App/Sources/Map/MapLayerVisibility.swift ios/App/Tests/MapLayerVisibilityTests.swift
git commit -m "Include coverage in effective scope"
```

### Task 3: Wire persistence and reset into the app

**Files:**
- Modify: `ios/App/Sources/Map/MapScreen.swift`
- Modify: `ios/App/Sources/MakingTracksApp.swift`
- Modify: `ios/App/Tests/AppShellTests.swift`

**Interfaces:**
- Consumes: `DiscoveryScopeStore.load()`, `save(_:)`, and `reset()`
- Produces: `MapScreen.scopeStorageKey == "map.scope.record"`
- Preserves: `MapScreen.coverageShadingStorageKey == "map.coverageShading.visible"` as the shipped migration key

- [ ] **Step 1: Write the failing app storage contract assertion**

Extend `testThemeStorageUsesStableKeyAndDefinedPaperDefault`:

```swift
XCTAssertEqual(MapScreen.scopeStorageKey, "map.scope.record")
XCTAssertEqual(MapScreen.coverageShadingStorageKey, "map.coverageShading.visible")
```

- [ ] **Step 2: Run the focused app test and verify RED**

Use the Task 2 simulator command with `-only-testing:MakingTracksTests/AppShellTests/testThemeStorageUsesStableKeyAndDefinedPaperDefault`.

Expected: compilation fails because `MapScreen.scopeStorageKey` does not exist.

- [ ] **Step 3: Replace the one-off coverage state with the scope store**

In `MapScreen`:

- Add `static let scopeStorageKey = DiscoveryScopeStore.storageKey`.
- Keep `coverageShadingStorageKey` as the legacy key alias.
- Remove the coverage `@AppStorage`.
- Initialize `layerVisibility` from `DiscoveryScopeStore(userDefaults: .standard).load()`.
- In the existing `onChange(of: layerVisibility)` hook, save `visibility.discoveryScope` before applying the visibility.

In `MakingTracksApp.resetUITestingCoverageShadingIfNeeded()`, call the scope store's `reset()` so UI-test resets clear both the current and legacy keys.

- [ ] **Step 4: Run focused app tests and host tests**

Run:

```bash
cd ios
swift test --filter DiscoveryScopeStoreTests
```

Then run the focused `AppShellTests` and `MapLayerVisibilityTests` through `sim-lock`. Expected: all pass with zero failures.

- [ ] **Step 5: Commit app wiring**

```bash
git add ios/App/Sources/Map/MapScreen.swift ios/App/Sources/MakingTracksApp.swift ios/App/Tests/AppShellTests.swift
git commit -m "Restore discovery scope on launch"
```

### Task 4: Give the derivation-reach law teeth

**Files:**
- Modify: `ios/Tests/MakingTracksDataTests/DerivationsTests.swift`
- Do not modify: `ios/Sources/MakingTracksData/Derivations.swift`

**Interfaces:**
- Consumes: the real `DiscoveryScopeStore`, `PinFeatureFilter.discoveryFeatures`, and the real `AppDatabase` derivations
- Protects: `trackVisits`, `listItems`, `lovedPlaces`, and `hiddenPlaces` from discovery-scope reach

- [ ] **Step 1: Write the integration test**

Create a real database with:

- two snapshot-backed visited places;
- one custom list containing both;
- one loved visit;
- one hidden place.

Capture the exact default story outputs. Save this restrictive scope to a unique real `UserDefaults` suite:

```swift
DiscoveryScope(
    visibleCategoryIDs: [],
    includeHidden: false,
    showSaved: false,
    showCoverageShading: false
)
```

Use its hidden/saved choices with real `PinFeatureFilter.discoveryFeatures` and assert the discovery result is empty. Then assert exact hand-derived story outputs remain:

- `trackVisits()` returns the non-hidden visit according to its own domain rule;
- `listItems(listID:)` returns both stored members;
- `lovedPlaces()` returns the loved place even where it overlaps hidden state;
- `hiddenPlaces()` returns the hidden place.

The break this catches is reusing discovery scope in any Journal derivation.

- [ ] **Step 2: Prove the test has teeth**

Temporarily filter one derivation assertion through the restrictive discovery result and run:

```bash
cd ios
swift test --filter DerivationsTests/testRestrictiveDiscoveryScopeDoesNotFilterStoryDerivations
```

Expected: RED because the story output is incorrectly emptied. Restore the real assertion.

- [ ] **Step 3: Run the real test and full host suite**

Run:

```bash
cd ios
swift test --filter DerivationsTests/testRestrictiveDiscoveryScopeDoesNotFilterStoryDerivations
swift test
```

Expected: the focused test and full suite pass with zero failures; `Derivations.swift` remains unchanged.

- [ ] **Step 4: Commit the reach-law test**

```bash
git add ios/Tests/MakingTracksDataTests/DerivationsTests.swift
git commit -m "Pin discovery scope outside story derivations"
```

### Task 5: Status, adversarial review, and release gate

**Files:**
- Modify: `docs/superpowers/phases/phase-2/tasks.md`

**Interfaces:**
- Produces: exact gate counts and durable status transitions for planner

- [ ] **Step 1: Update the row to `tests green`**

Record the exact host and simulator counts in T2.7's status line and announce the same transition to planner on `p2p/planner__codex4`.

- [ ] **Step 2: Run the adversarial self-review**

Review `origin/ios..HEAD` for:

- future-version records accidentally decoded;
- malformed data becoming an empty category scope;
- legacy `false` being lost;
- legacy deletion before v1 write;
- nondeterministic category ordering;
- category IDs no longer present in the live taxonomy;
- reset clearing only one of the two storage keys;
- any scope reach into `Derivations.swift`;
- hostile local record size or identifier bounds.

For each finding, either fix it test-first or record why it does not survive.

- [ ] **Step 3: Run the full host and simulator gate**

Export codex4's ledger seat and run:

```bash
cd ios
swift test
cd ..
export MT_RELEASE_GATE_DESTINATION='platform=iOS Simulator,id=42D1482C-DE04-49AA-990D-1884ED9B855D'
./scripts/sim-lock.sh ./scripts/release-gate.sh
```

Capture exact build, unit-test, and UI-test pass/fail counts. Confirm zero warnings and remove any `.xcresult` artifacts per the repository disk-hygiene law.

- [ ] **Step 4: Re-ground and inspect the stale-base diff**

Run a fresh `git fetch origin ios`, verify `origin/ios` is an ancestor or merge it and re-gate, then confirm `git diff --stat origin/ios..HEAD` contains only T2.7 work.

- [ ] **Step 5: Push, open the PR, and apply review labels**

Push the exact tested head. Open a PR into `ios` serving #469, name the produced contracts, include exact test counts, adversarial accounting, and a `## Taste guesses` section stating `None`. Apply `track-b-ios`, `wp`, `sourcery-review`, and the allocated `greptile-review` label.

- [ ] **Step 6: Process review and hand off**

Process every Sourcery, Greptile, and reviewer thread. When clean, update the row through `PR open`, `review clean`, and `ready-to-merge` in both the branch ledger and AMQ, always naming the exact head SHA. Planner executes the merge.
