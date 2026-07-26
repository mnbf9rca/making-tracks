# T1.9 Loved and Hidden Surfaces Implementation Plan

> **For Codex:** Use the executing-plans skill to implement this plan task by
> task. Preserve RED/GREEN order and stop if implementation requires schema or
> migration work.

**Goal:** Add snapshot-backed Loved and Hidden virtual collections to the
Tracks door, with place-level management, accessible Snow/Newsreader UI, and
committed default/AX evidence.

**Architecture:** `AppDatabase` derives two `[ListPlace]` collections from
existing visits, hidden membership, and place snapshots. `MapScreenModel`
provides detached async wrappers and live mutations. The Tracks root adds two
counted hairline rows and routes to one mode-driven managed-place destination
extracted into its own Swift file.

**Tech stack:** Swift 6, GRDB, SwiftUI, XCTest/XCUITest, DesignSystem,
XcodeGen, self-contained HTML evidence.

**Approved design:**
`docs/superpowers/plans/2026-07-26-loved-hidden-surfaces-design.md`

---

## Task 1: Build the two database reads query-first

**Files:**

- Modify: `ios/Tests/MakingTracksDataTests/DerivationsTests.swift`
- Modify: `ios/Sources/MakingTracksData/Derivations.swift`

**Interfaces produced:**

```swift
public func lovedPlaces() throws -> [ListPlace]
public func hiddenPlaces() throws -> [ListPlace]
```

### Step 1: Add the Loved query RED test

Add a comprehensive `testLovedPlacesAreSnapshotBackedDeduplicatedAndIncludeHiddenOverlap`.
Seed:

- one place with repeated visits and more than one loved verdict;
- one loved place that is also hidden;
- one ordinary visited place;
- one loved visit without a snapshot;
- deterministic timestamps and names.

Assert:

- one row per loved place;
- latest-loved-visit descending order, then case-insensitive name and place ID;
- snapshot name/category projection;
- `.loved` pin state;
- hidden+loved overlap has `pinState.hidden == true`;
- ordinary and snapshotless places are absent.

Run:

```bash
cd ios
swift test --filter DerivationsTests.testLovedPlacesAreSnapshotBackedDeduplicatedAndIncludeHiddenOverlap
```

Expected RED: compilation fails because `AppDatabase.lovedPlaces()` does not
exist. Confirm the failure names that missing API.

### Step 2: Add the Hidden query RED test

Add `testHiddenPlacesJoinSnapshotsValidateRowsAndSortNewestFirst`. Seed:

- two valid hidden snapshot rows with distinct `hidden_at`;
- a hidden+loved overlap;
- a hidden ID without a snapshot;
- an invalid snapshot row;
- a visible snapshot.

Assert newest-hidden-first deterministic ordering, names/categories, current
hidden and loved pin states, and omission of snapshotless/invalid/visible rows.

Run:

```bash
cd ios
swift test --filter DerivationsTests.testHiddenPlacesJoinSnapshotsValidateRowsAndSortNewestFirst
```

Expected RED: compilation fails because `AppDatabase.hiddenPlaces()` does not
exist.

### Step 3: Implement the minimal queries

In `Derivations.swift`:

- select loved rows by joining `visits` to `place_snapshots`, filtering
  `verdict = 'loved'`, grouping by place, and ordering by
  `MAX(visited_at) DESC`, name, and ID;
- select hidden rows by joining `hidden_places` to `place_snapshots`, ordering
  by `hidden_at DESC`, name, and ID;
- reuse `listSnapshotRow(_:)` to enforce existing snapshot validation;
- derive `PinState` for the validated IDs inside the same `dbQueue.read`;
- map into existing `ListPlace`;
- do not introduce a record for `hidden_places`, schema, or migration.

Do not exclude hidden IDs from Loved.

### Step 4: Prove GREEN and run the complete host suite

Run:

```bash
cd ios
swift test --filter DerivationsTests
swift test
```

Expected GREEN: both new query tests and the full host suite pass with zero
failures.

### Step 5: Commit the data contract

```bash
git add ios/Tests/MakingTracksDataTests/DerivationsTests.swift
git add ios/Sources/MakingTracksData/Derivations.swift
git diff --cached --check
git commit -m "Add loved and hidden place reads"
```

---

## Task 2: Pin the door and destination contracts before UI

**Files:**

- Modify: `ios/App/Tests/AppShellTests.swift`
- Modify: `ios/App/Sources/Map/MapDoorShell.swift`
- Modify: `ios/App/Sources/Map/MapScreen.swift`

**Interfaces produced:**

- `MapShellDestination.lovedPlaces`
- `MapShellDestination.hiddenPlaces`
- `TracksDoorRow.lovedPlaces`
- `TracksDoorRow.hiddenPlaces`
- Loved/Hidden counts on `TracksDoorContent`
- `MapScreenModel.lovedPlaces()` / `hiddenPlaces()`

### Step 1: Write failing door-order and content tests

Replace the T1.8 assertion that Loved/Hidden do not render. Assert:

```swift
TracksDoorRow.allCases == [
    .myTracks,
    .newList,
    .lovedPlaces,
    .hiddenPlaces,
]
```

Pin each virtual row's exact title, SF Symbol, and accessibility identifier:

- `tracks.row.loved`
- `tracks.row.hidden`

Extend `TracksDoorContent.make` tests to pass explicit Loved/Hidden result
arrays and assert deduplicated projected counts, including zero counts.

### Step 2: Run the focused app tests RED

Regenerate the project only if its committed project is stale:

```bash
cd ios/App
xcodegen generate
cd ../..
./scripts/sim-lock.sh xcodebuild test \
  -project ios/App/MakingTracks.xcodeproj \
  -scheme MakingTracks \
  -destination 'platform=iOS Simulator,id=C4A64D49-24A2-4429-B6E2-AD9A14142A99' \
  -only-testing:MakingTracksTests/AppShellTests
```

Expected RED: missing Loved/Hidden enum cases and count inputs.

### Step 3: Implement the minimal navigation/content contract

In `MapDoorShell.swift`:

- add the two `TracksDoorRow` cases and presentations;
- add Loved/Hidden counts to `TracksDoorContent`;
- render the two rows after New list;
- use hairline geometry, leading heart/eye-slash symbols, trailing numeric
  counts, and muted styling across the Hidden row;
- append the matching `MapShellDestination` on tap;
- always render both rows, including at zero.

In `MapScreen.swift`:

- add the two destination cases;
- add async database wrappers for `lovedPlaces()` and `hiddenPlaces()`;
- extend the destination switch without changing existing routes;
- load both collections in the Tracks-root reload and project their counts.

### Step 4: Prove the contract GREEN

Run the same focused `AppShellTests` command. Confirm existing My tracks, list,
and New list assertions stay green and the new exact-order/count assertions
pass.

### Step 5: Commit the door contract

```bash
git add ios/App/Tests/AppShellTests.swift
git add ios/App/Sources/Map/MapDoorShell.swift
git add ios/App/Sources/Map/MapScreen.swift
git add ios/App/MakingTracks.xcodeproj/project.pbxproj
git diff --cached --check
git commit -m "Add Loved and Hidden door routes"
```

---

## Task 3: Build the shared managed-place surface test-first

**Files:**

- Create: `ios/App/Sources/Map/ManagedPlacesView.swift`
- Modify: `ios/App/MakingTracks.xcodeproj/project.pbxproj`
- Modify: `ios/App/Tests/AppShellTests.swift`
- Modify: `ios/App/Sources/Map/MapScreen.swift`

**Interfaces produced:**

- `ManagedPlacesMode`
- `ManagedPlacesPresentation`
- `ManagedPlacesView`

### Step 1: Add failing presentation/action-state tests

In `AppShellTests`, pin both mode presentations:

- Newsreader surface title (`Loved places` / `Hidden places`);
- leading symbol;
- empty-state title and guidance;
- row action accessibility text;
- row, action, surface, and error identifier prefixes;
- failure copy.

Add a pure helper/state test proving:

- a successful membership removal removes only the matching place;
- a failed action retains it;
- only the pending row is disabled.

Keep asynchronous database/controller behavior in integration tests; this host
test pins deterministic presentation/state transformations.

### Step 2: Run focused app tests RED

Run the focused `AppShellTests` command from Task 2.

Expected RED: missing `ManagedPlacesMode` and state/presentation contracts.

### Step 3: Implement the extracted surface

Create `ManagedPlacesView.swift` with:

- a mode-driven presentation contract;
- a Snow-token `List`;
- `.sheetTitle` surface title;
- `.listRowTitle` place names and `.metadata` category/state copy;
- `MaterialHairlineRow` place rows;
- accessibility-hidden decorative icon;
- a 44-point trailing action;
- Loved action via `MapScreenModel.setLoved(placeID:loved: false)`;
- Hidden action via `MapScreenModel.setHidden(placeID:hidden: false)`;
- per-row pending state;
- immediate removal only after success;
- inline token-styled failure while retaining the row;
- ruled empty-state copy;
- `.task` and `.refreshable` reads.

Loved must surface a hidden overlap as metadata rather than filtering it.
Hidden styling is quiet, but its Unhide control remains legible and
non-colour-dependent.

Wire both cases in `MapDoorSheetIntegration.destinationView`.

Regenerate the committed Xcode project:

```bash
cd ios/App
xcodegen generate
cd ../..
```

Review the generated `project.pbxproj` diff and verify it only adds the new
source file/reference.

### Step 4: Prove GREEN and renderability

Run focused `AppShellTests`. Add ImageRenderer smoke coverage for populated and
AX5 instances if the existing render harness permits direct construction;
assert non-nil images and no fixed-height contract.

### Step 5: Commit the surface

```bash
git add ios/App/Sources/Map/ManagedPlacesView.swift
git add ios/App/Sources/Map/MapScreen.swift
git add ios/App/Tests/AppShellTests.swift
git add ios/App/MakingTracks.xcodeproj/project.pbxproj
git diff --cached --check
git commit -m "Build manageable Loved and Hidden surfaces"
```

---

## Task 4: Prove live behavior and the include-hidden asymmetry

**Files:**

- Modify: `ios/App/Sources/MakingTracksApp.swift`
- Modify: `ios/App/UITests/MakingTracksCoreLoopUITests.swift`

### Step 1: Add a deterministic T1.9 fixture

Add one launch flag that seeds:

- at least two loved snapshot-backed places;
- at least two hidden snapshot-backed places;
- one place in both sets;
- a visible ordinary place;
- a stored list or track visit that witnesses hidden-count exclusion.

Extend the UITest `launch` helper with one boolean for the flag. Reuse existing
fixture places and public mutations where possible; do not add schema-only
fixture hooks.

### Step 2: Add focused UI tests RED

Add tests that:

1. Open Tracks and find My tracks, existing lists, New list, Loved, and Hidden
   without losing any T1.8 destination.
2. Assert the virtual row counts and minimum hit targets.
3. Open Loved, verify the Newsreader-title surface and hidden-overlap metadata,
   remove one loved membership, and verify only that place disappears.
4. Open Hidden, unhide one row, verify it disappears, and verify reopening
   Tracks refreshes the count.
5. Prove the ruled asymmetry: hidden membership is excluded from track/list
   progress before unhide; Scope's include-hidden changes discovery rendering
   only; live unhide restores ordinary discovery without changing the toggle's
   data-count semantics.
6. Run a focused AX5 flow and assert multiline rows/actions do not overlap or
   clip.

Add screenshot export names for the default door, Loved, Hidden, and AX
captures.

### Step 3: Run the focused UI tests and observe RED

Use only the simulator lock:

```bash
./scripts/sim-lock.sh xcodebuild test \
  -project ios/App/MakingTracks.xcodeproj \
  -scheme MakingTracks \
  -destination 'platform=iOS Simulator,id=C4A64D49-24A2-4429-B6E2-AD9A14142A99' \
  -only-testing:MakingTracksUITests/MakingTracksCoreLoopUITests/testLovedAndHiddenSurfacesManagePlaceMembership \
  -only-testing:MakingTracksUITests/MakingTracksCoreLoopUITests/testHiddenSurfaceRoundTripsWithScopeWithoutChangingTrackCounts \
  -only-testing:MakingTracksUITests/MakingTracksCoreLoopUITests/testLovedAndHiddenSurfacesRemainUsableAtAX5
```

Expected RED must be behavioral (missing row/action/refresh), not simulator
setup failure.

### Step 4: Make the focused flows GREEN

Implement only the fixture/wiring fixes required by the failing integration
tests. Confirm live Hidden mutation reaches `CoreLoopController.setHidden`;
never call `AppDatabase.unhide(placeID:)`.

Run the same focused UI command until all new tests pass.

### Step 5: Commit integration proof

```bash
git add ios/App/Sources/MakingTracksApp.swift
git add ios/App/UITests/MakingTracksCoreLoopUITests.swift
git diff --cached --check
git commit -m "Prove Loved and Hidden live management"
```

---

## Task 5: Commit default and AX render evidence

**Files:**

- Create: `docs/design/design-system/t1.9-loved-hidden-surfaces.html`
- Create: `docs/design/design-system/t1.9-loved-hidden-surfaces.png`
- Create: `docs/design/design-system/t1.9-loved-hidden-surfaces-ax.html`
- Create: `docs/design/design-system/t1.9-loved-hidden-surfaces-ax.png`
- Modify: `docs/design/design-system/README.md`

### Step 1: Author self-contained evidence HTML

The default source contains three exact 390×844 frames:

- Tracks door with both counted rows;
- populated Loved collection;
- populated Hidden collection.

The AX source contains the same three frames at AX5 sizing. Copy geometry and
tokens from T1.8 evidence and DesignSystem; do not alter frozen
`coherence.*`/`ia-doors.*`. Mark the fold and identify implementation evidence,
not a new ruling.

### Step 2: Capture the PNGs

Use the locally available headless Chrome command with:

- `--hide-scrollbars`;
- device scale factor 1;
- isolated `/private/tmp` user-data directories;
- width 390 and height 2532 for three stacked 390×844 frames;
- background networking disabled.

Write only the two tracked PNG paths above.

### Step 3: Inspect at original detail

Open both PNGs and verify:

- ruled door order/counts/icons and quiet Hidden treatment;
- Newsreader titles and DS hairline rows;
- explicit Loved/Unhide controls with non-colour meaning;
- no overlap, clipping, or accidental dark-system material at AX5;
- each frame boundary is exactly 390×844.

### Step 4: Document and commit evidence

Add the T1.9 packet to the README implementation-evidence table.

```bash
git add docs/design/design-system/t1.9-loved-hidden-surfaces.html
git add docs/design/design-system/t1.9-loved-hidden-surfaces.png
git add docs/design/design-system/t1.9-loved-hidden-surfaces-ax.html
git add docs/design/design-system/t1.9-loved-hidden-surfaces-ax.png
git add docs/design/design-system/README.md
git diff --cached --check
git commit -m "Record Loved and Hidden surface evidence"
```

---

## Task 6: Gate, review, and exact-SHA handoff

**Files:**

- Modify: `docs/superpowers/phases/phase-1/tasks.md`
- Modify: PR body only after opening the PR

### Step 1: Re-ground against fresh `origin/ios`

```bash
git fetch origin ios
git merge-base --is-ancestor origin/ios HEAD
```

If stale, inspect the exact incoming diff. Merge fresh `origin/ios` as a bare
mutation. A code or scripts advance requires rerunning all gates; only a
proved docs-only advance may use the repository's carry rule.

### Step 2: Run required verification

Run:

```bash
cd ios
swift test
cd ..
./scripts/sim-lock.sh ./scripts/release-gate.sh
```

Record exact build/test counts, zero failed/skipped, and warnings-as-errors
evidence. Check:

```bash
git diff --check
git status --short
```

### Step 3: Update the dual-channel checkpoint

Update only T1.9's ledger row to `tests green` with the exact full SHA and test
counts, commit it, and send the same facts through AMQ. Never describe it as
ready-to-merge before the PR and required reviews are clean.

### Step 4: Open the PR with complete evidence

Target `ios`. The PR body must include:

- issue #470 and T1.9;
- exact query signatures;
- explicit no-schema/no-migration statement;
- host and release-gate counts;
- default and AX render links;
- accessibility and adversarial accounting;
- controller-routed unhide evidence;
- `## Taste guesses` with immediate-removal and empty-copy alternatives;
- explicit ruled include-hidden interpretation and rejected count-changing
  alternative;
- exact full head SHA under the body-evidence rule.

### Step 5: Run the required review tier

Request Sourcery unless the weekly cap-skip clause applies; record cap evidence
if skipped. Request Opus at the exact PR head. A Greptile slot is Fable's call.
Address feedback using receiving-code-review rigor, rerun proportionate gates,
and obtain exact-head clearance.

### Step 6: Mark ready-to-merge and hand off

After reviews are clean, update T1.9 to `ready-to-merge` with:

- PR number;
- exact full head SHA;
- exact host/full-gate results;
- review dispositions;
- render paths;
- no-schema and Taste-guess accounting.

Commit the ledger update, verify a clean worktree, push the exact head, and send
the matching AMQ handoff. Do not self-merge; Fable owns merge and final
`merged` ledger state.
