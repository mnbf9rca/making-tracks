# A10 Saved-Visibility Filter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the ruled `Show saved places` control to Explore so its default-ON state preserves today's discovery map and switching it OFF removes only saved discovery pins.

**Architecture:** `MapLayerVisibility` owns the positive-polarity default and Explore binding. `MapScreen` propagates changed saved visibility through an applied-value guard into `MapScreenModel`; `PinFeatureFilter.discoveryFeatures` applies the saved and hidden predicates independently to the real `PinState`. The change deliberately stops at discovery map pins: no `Derivations.swift` function or list/track result is altered.

**Tech Stack:** Swift 6, SwiftUI, MakingTracksMapStyle, XCTest/XCUITest, MapLibre-backed iOS simulator gate, checked-in HTML/PNG render evidence.

## Global Constraints

- Work only in `wp-526-saved-visibility-filter`, based on fresh `origin/ios` containing A1 merge `2a91e7b55e37db85614be0dba520c865df96a1fd`; the PR targets `ios`.
- Run simulator operations only through `./scripts/sim-lock.sh` with codex2's explicit simulator destination.
- Use strict test-driven development: observe focused RED before each production change, then run the same test GREEN.
- Label the control exactly `Show saved places`; default ON; identifier `map.layers.show-saved`; bookmark system glyph.
- Render Scope rows in this order: Include hidden OFF, Show saved places ON, Show coverage shading ON.
- Treat `52pt minimum each; 15pt/600 label; 20×20 icon; 10pt gap; 6/2 padding; 44×28 switch with 22pt knob at 3/19pt offsets; 1pt hairlines` as **MEASURED, not ratified** A8 facts.
- Grade implementation renders against frozen A8 Explore frame SHA `0682865dff178ff43ea3e1374685328f565d8cd1`.
- Preserve include-hidden and coverage-shading behavior, category selection, nearby prompts, list maps, tracks, and list derivations.
- Do not modify `ios/Sources/MakingTracksData/Derivations.swift`; the beyond-map reach question is routed to Rob through planner.
- Saved and hidden populations are disjoint after A6 (`d33cea71`), so the two independent predicates need no interaction matrix.
- DS-3 owns later Scope/Layers restructuring; A10 adds one row to A1's current Explore surface only.

## File Structure

- `ios/App/Sources/Map/MapLayerVisibility.swift` — positive saved-state default, `isDefault`, and list-map state preservation.
- `ios/App/Tests/MapLayerVisibilityTests.swift` — catches default-polarity inversion and dropped state while list-map categories are displayed.
- `ios/Sources/MakingTracksMapStyle/PinFeatureFilter.swift` — independent saved-pin predicate for discovery features.
- `ios/Tests/MakingTracksMapStyleTests/PinFeatureFilterTests.swift` — real-filter acceptance for both saved polarities and unchanged hidden/category behavior.
- `ios/App/Sources/Map/MapScreen.swift` — applied saved guard, model setter, and all discovery-filter call sites.
- `ios/App/Sources/Map/MapDoorShell.swift` — ruled presentation, row order, bookmark glyph, and binding.
- `ios/App/Tests/AppShellTests.swift` — invert A1's deliberate saved-row absence assertion into the complete row contract.
- `ios/App/UITests/MakingTracksCoreLoopUITests.swift` — default/AX presence, state, order, hit target, and render capture.
- `docs/design/design-system/a1-journal-explore-doors.html` — update the implementation render source with A10's third Scope row and provenance.
- `docs/design/design-system/a1-explore-door.png` and `docs/design/design-system/a1-explore-door-ax.png` — recaptured 390×844 evidence.
- `docs/design/design-system/README.md` — update the Explore implementation artifact record.
- `docs/superpowers/phases/phase-1/amendment-wave.md` — advance only A10's builder-owned status.

---

### Task 1: Pin positive saved state and real-filter behavior

**Files:**
- Modify: `ios/App/Tests/MapLayerVisibilityTests.swift`
- Modify: `ios/Tests/MakingTracksMapStyleTests/PinFeatureFilterTests.swift`
- Modify after RED: `ios/App/Sources/Map/MapLayerVisibility.swift`
- Modify after RED: `ios/Sources/MakingTracksMapStyle/PinFeatureFilter.swift`

- [ ] **Step 1: Add the failing visibility contracts**

Extend the default-state test so the default requires `showSavedPlaces == true`, switching it false makes `isDefault == false`, and restoring it true returns to default even when coverage shading changes. Extend the list-map display test so it preserves the discovery saved polarity while replacing only visible categories.

- [ ] **Step 2: Add the failing real-filter acceptance test**

Use three literal fixtures: an unsaved visible attraction, a saved visible museum, and an unsaved hidden museum. Assert:

```swift
XCTAssertEqual(
    PinFeatureFilter.discoveryFeatures(
        features,
        showHidden: false,
        showSaved: MapLayerVisibility().showSavedPlaces
    ).map(\.0.id),
    ["unsaved-attraction", "saved-museum"]
)
XCTAssertEqual(
    PinFeatureFilter.discoveryFeatures(
        features,
        showHidden: false,
        showSaved: false
    ).map(\.0.id),
    ["unsaved-attraction"]
)
```

The saved fixture's museum category remains present in the input and category filtering stays downstream; the hidden fixture remains excluded in both assertions. This fails if the saved member is absent, its default flips, or the filter ignores the argument.

- [ ] **Step 3: Run focused tests and verify RED**

Run the MapStyle package filter and the app `MapLayerVisibilityTests` build/test through the assigned simulator. Record the compiler/assertion failures before implementation.

- [ ] **Step 4: Implement the minimum state and predicate**

Add `showSavedPlaces: Bool = true`, require its positive value in `isDefault`, preserve it through `ListMapLayerVisibility.displayed`, and filter discovery features with:

```swift
(showHidden || !state.hidden) && (showSaved || !state.saved)
```

Update existing MapStyle call sites/tests to pass `showSaved: true` where they are not testing saved visibility.

- [ ] **Step 5: Re-run focused tests and verify GREEN**

Run exactly the RED commands again. Confirm the filter test catches both wrong default and ignored-argument mutations.

### Task 2: Propagate saved visibility through MapScreen exactly on change

**Files:**
- Modify: `ios/App/Sources/Map/MapScreen.swift`
- Modify: `ios/App/Tests/MapLayerVisibilityTests.swift` if an additional pure guard seam is needed

- [ ] **Step 1: Add/extend a failing guard contract**

Pin that a saved-only visibility change is considered an applied filter change while an identical visibility value does not trigger another refresh. Prefer a small pure change predicate if the view's async method cannot be exercised without a simulator integration harness.

- [ ] **Step 2: Verify RED**

Run the focused app test and retain the failure showing saved changes are currently ignored.

- [ ] **Step 3: Implement model state and plumbing**

Add `showSavedPlaces = true` and `setShowSaved(_:)` to `MapScreenModel`; pass it at every `discoveryFeatures` call. Add `appliedShowSavedPlaces = true`, initialise both applied values at startup, preserve the saved value in list-map visibility reconstruction, and make `applyLayerVisibility` refresh only when hidden or saved changed.

- [ ] **Step 4: Verify GREEN**

Re-run the focused test and all `MapLayerVisibilityTests`; then run the MapStyle suite to catch a missed call site.

### Task 3: Invert A1's absence law and mount the ruled row

**Files:**
- Modify: `ios/App/Tests/AppShellTests.swift`
- Modify after RED: `ios/App/Sources/Map/MapDoorShell.swift`

- [ ] **Step 1: Invert, do not delete, A1's saved-row assertion**

Rename the A1 test to describe the complete Scope contract. Change `allCases` to the literal order `[.includeHidden, .showSaved, .coverageShading]`; replace `XCTAssertFalse(...contains("Show saved places"))` with equality for:

```swift
ExploreScopeControlPresentation(
    title: "Show saved places",
    icon: .system("bookmark"),
    accessibilityIdentifier: "map.layers.show-saved"
)
```

- [ ] **Step 2: Run the focused AppShell test and verify RED**

The test must fail because `.showSaved` and its presentation do not exist.

- [ ] **Step 3: Add the minimum Explore implementation**

Add the enum case/presentation, insert its `ExploreScopeToggleRow` between hidden and coverage, and add a binding that copies `visibility`, changes only `showSavedPlaces`, and writes it back. Reuse A1's row component and MEASURED-not-ratified geometry; do not restructure Explore.

- [ ] **Step 4: Re-run the focused test and verify GREEN**

Then run complete `AppShellTests` to catch ordering, case exhaustiveness, and shell regressions.

### Task 4: Prove the mounted control and capture render evidence

**Files:**
- Modify: `ios/App/UITests/MakingTracksCoreLoopUITests.swift`
- Modify: `docs/design/design-system/a1-journal-explore-doors.html`
- Recapture: `docs/design/design-system/a1-explore-door.png`
- Recapture: `docs/design/design-system/a1-explore-door-ax.png`
- Modify: `docs/design/design-system/README.md`

- [ ] **Step 1: Add failing default and AX UI assertions**

Require `map.layers.show-saved` between the existing hidden and coverage rows, value `1` at launch, a 52pt minimum default frame, and a hittable 44pt minimum AX frame. Toggle it OFF and assert value `0`; close/reopen Explore and assert the value remains `0` in the live session. Add the identifier to A1's AX control loop.

- [ ] **Step 2: Run focused UI tests and verify RED**

Use codex2's assigned simulator through `sim-lock.sh`. The saved switch existence assertion must fail before production UI is added.

- [ ] **Step 3: Verify GREEN and capture both renders**

Re-run the focused default and AX tests after implementation. Export the named default and AX screenshots, recapture the checked-in 390×844 implementation images, and inspect them at original detail.

- [ ] **Step 4: Measure all three rows**

Record exact hidden/saved/coverage row heights from XCUI frames in default and AX captures. Confirm default states OFF/ON/ON and ruled order. Update the HTML/README provenance using A1's wording:

> Grading authority: the implementation renders were graded against `a8-explore-surface.png` at exact frozen remote head `0682865dff178ff43ea3e1374685328f565d8cd1`. The geometry figures applied here come from the spec's **Measured A8 Explore frozen-render facts — not system law** table, whose rows cite artifact SHA `f492296e932d8f3225362875f466f6d40504fe54`; they are **MEASURED, not ratified**, pending Phase 1 next-session Open Flag 5.

### Task 5: Complete gates, review, and handoff

**Files:**
- Modify: `docs/superpowers/phases/phase-1/amendment-wave.md`
- Modify only for surviving findings: files above

- [ ] **Step 1: Run complete host gates**

Run `cd ios && swift test`, repository law/docs checks, complete `AppShellTests`, and any changed-path checks. Delete generated `.xcresult` bundles after extracting test counts.

- [ ] **Step 2: Run the complete host simulator gate**

Run:

```bash
MT_RELEASE_GATE_DESTINATION='platform=iOS Simulator,id=BACC2CF8-C1F8-4C92-B058-47B0AC0B128D' \
MT_RELEASE_GATE_RUN_DIR=/private/tmp/release-gate-codex2 \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
./scripts/sim-lock.sh ./scripts/release-gate.sh
```

Record Release build, app/unit, and serial UI counts; remove the run's `.xcresult` bundles after extracting them.

- [ ] **Step 3: Run adversarial and automated review**

Perform correctness, data-boundary/security, and test-teeth review against the exact pushed SHA. Request the row's `sourcery` + `reviewer` tier over AMQ/GitHub, cross-examine every finding, fix only findings that survive, and report raised/survived/fixed counts.

- [ ] **Step 4: Record the explicit non-decision**

In the PR body state: the merged behavior filters discovery map pins only; `Derivations.swift` is untouched; beyond-map derivation reach was routed to Rob through planner; saved/hidden populations are disjoint under A6 so no combination matrix is required.

- [ ] **Step 5: Open and hand off the PR**

Advance A10 to `pr`, commit signed, push and verify exact remote SHA, open a ready PR into `ios` serving #526, apply `sourcery-review`, `track-b-ios`, and `wp`, process review threads, and hand the exact PR/SHA and gate evidence to planner. Do not self-merge.
