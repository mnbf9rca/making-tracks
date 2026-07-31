# T2.8 Explore Scope Picker Implementation Plan

> **For Codex:** Execute test-first against `origin/ios` at `2105250`; keep the identifier contract rename isolated in one commit.

**Goal:** Rebuild Explore as the ruled single Scope picker, composing persisted discovery scope with contextual active-list visit filters without conflating their state or reach.

**Architecture:** Keep `DiscoveryScope`/`MapLayerVisibility` as the persisted discovery domain and `TracksVisitFilter` as the active-list domain. Add small pure policy types for effective-scope indication, Clear behavior, eligible list ordering/summary, and category symbol pairs. `MapScreen` owns async model refresh and bindings; `MapDoorSheet` receives a focused optional list-scope context and renders it inside `ExploreDoorRootView`. Remove the floating list chips and grouped-edit filter sheet after their behavior is live in Explore.

**Tech Stack:** Swift 6, SwiftUI, XCTest, DesignSystem `MaterialChip`, XCUITest, the locked iOS release gate.

---

### Task 1: Correct the pre-release persistence contract

**Files:**
- Modify: `ios/Tests/MakingTracksMapStyleTests/DiscoveryScopeStoreTests.swift`
- Modify: `ios/Sources/MakingTracksMapStyle/DiscoveryScopeStore.swift`
- Modify: `ios/App/Sources/Map/MapScreen.swift`
- Verify: `ios/App/Sources/MakingTracksApp.swift`

1. Delete the version-zero and legacy coverage-key migration tests; add a test that version zero degrades to defaults and is not rewritten.
2. Change `save` to return a checked result and test invalid input returns failure without replacing the last valid record.
3. Run the focused store tests and observe the new expectations fail.
4. Delete `RecordV0`, `legacyCoverageShadingKey`, legacy load/reset handling, and the app-only legacy key alias.
5. Preserve current-version decoding, unknown-version degradation, malformed/oversize defaults, version field, and bounds. Document that an explicit later save may overwrite a newer record after degradation.
6. Run focused tests green.

### Task 2: Pin the compositional Scope policy

**Files:**
- Modify: `ios/App/Tests/AppShellTests.swift`
- Modify: `ios/App/Tests/MapLayerVisibilityTests.swift`
- Modify: `ios/App/Sources/Map/MapDoorShell.swift`
- Modify: `ios/App/Sources/Map/MapLayerVisibility.swift`

1. Add red tests for the indicator matrix: default/non-default discovery, Tracks/Fresh with a retained list filter, and coverage/category differences.
2. Add red tests for Clear: discovery resets always; an effective Tracks filter resets; a dormant Fresh filter survives.
3. Add red tests for eligible Other Lists choices: exclude system and active lists, case-insensitive title order, stable-id tie break, and summary copy.
4. Add red tests that every category has an explicit filled/outline SF Symbol pair.
5. Implement pure policy/data types until focused host tests pass.

### Task 3: Wire the ruled picker into the door

**Files:**
- Modify: `ios/App/Sources/Map/MapDoorShell.swift`
- Modify: `ios/App/Sources/Map/MapScreen.swift`
- Modify: `ios/App/Tests/AppShellTests.swift`

1. Extend `MapDoorSheet` with discovery scope and optional active-list scope context.
2. Render W-1's default and list-context section ordering, live Loved chip, shared categories, Other Lists drill-in, discovery-default explanation, and conditional Clear row.
3. Load eligible saved lists when Explore opens in active-list context.
4. Make Loved/category/membership edits live and promote Fresh to Tracks; keep discovery saved/hidden choices from thinning list-story rows.
5. Reset both effective domains from Clear while preserving a dormant Fresh filter.
6. Remove the floating chip overlay, grouped-edit sheet state, draft/apply machinery, and retired Apply/Close/sheet contracts.
7. Run focused app tests.

### Task 4: Carry metrics and accessibility contracts

**Files:**
- Modify: `ios/Sources/DesignSystem/Iconography.swift`
- Modify: `ios/App/Sources/Map/MapDoorShell.swift`
- Modify: `ios/App/Tests/AppShellTests.swift`
- Modify: `ios/App/UITests/MakingTracksCoreLoopUITests.swift`

1. Add tests pinning the distinct Scope-control metric at 20 default and its `.button` scaling contract to 30 at AX.
2. Re-home the metric under a separately named Scope-control API, anchor the live scaled metric to `.button`, then retire `ExploreSurfaceIconGeometry.scopeControl`.
3. Give every state control a VoiceOver value, keep switch morphology, keep clear/navigation targets at least 44pt, and preserve AX5 reflow.
4. Add/extend real hit tests for two adjacent distinct chips at a sub-22pt gap so a midpoint-near tap reaches exactly the nearer chip.

### Task 5: Perform the one-commit identifier rename

**Files:**
- Modify: `ios/App/Sources/Map/MapDoorShell.swift`
- Modify: `ios/App/Sources/Map/MapScreen.swift`
- Modify: `ios/App/Tests/*.swift`
- Modify: `ios/App/UITests/MakingTracksCoreLoopUITests.swift`

1. Rename every contract exactly from W-1's annex, including the prefix helper and bare retired launcher assertion.
2. Rename `layersSheetVisibility` plumbing to Explore-scope language in the same commit.
3. Verify `rg -n 'map\.layers|track-filter-picker|map\.list-mode\.filter' ios/App/Sources ios/App/Tests ios/App/UITests` returns zero surviving retired contracts.
4. Mutate the AX Scope-row threshold to 85, run the focused UI test and capture red, then restore 86 and capture green.
5. Commit only the identifier/plumbing rename as its own commit.

### Task 6: Full evidence and review gate

**Files:**
- Add: implementation renders and reproducible capture record under `docs/design/design-system/` if the existing capture tooling requires new artifacts.
- Modify: `docs/superpowers/phases/phase-2/tasks.md`

1. Run `cd ios && swift test` and retain exact counts.
2. Export the assigned seat from `docs/ios-gate-ledger.md`, then run `./scripts/sim-lock.sh ./scripts/release-gate.sh` with one reusable derived-data path.
3. Capture default/AX picker and default/adjusted door states with measurements; verify no result bundles remain.
4. Run adversarial review with distinct spec, correctness, security/untrusted-data, accessibility, and test-teeth lenses; refute each finding, fix survivors, and prove teeth.
5. Fetch `origin/ios`, re-ground, review the two-dot diff, push, open the PR into `ios`, and apply `sourcery-review`, `track-b-ios`, and `wp` labels.
6. State in the PR body: “The prior shipped-state framing was a planner/reviewer decomposition error; the app is pre-release, so this PR deletes the legacy coverage-key migration.”
