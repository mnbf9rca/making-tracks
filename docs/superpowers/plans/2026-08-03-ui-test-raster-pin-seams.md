# UI-Test Raster and Fixture-Pin Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the two UI-test harness seams that voided issue #600 CAP3 repetition 1 while preserving strict app-pixel equality and intentional negative coordinate probes.

**Architecture:** Keep the change inside `MakingTracksCoreLoopUITests.swift`. A pure frame helper defines the app-owned My Tracks raster region, while positive fixture activation delegates to the existing reset-, identity- and hit-state-driven opener and negative tests use an explicitly named raw coordinate probe.

**Tech Stack:** Swift 6, XCTest/XCUITest, UIKit geometry, the repository release-gate wrapper, AMQ review.

## Global Constraints

- UI-test harness only; do not change app source or product behaviour.
- Preserve exact zero-difference comparison inside app-owned raster bounds; do not add tolerance.
- No sleeps, unbounded retries, app-side sentinels or raw simulator commands.
- Every simulator command runs through `./scripts/sim-lock.sh --seat codex3`.
- Before every simulator launch, require `pmset -g batt` to report `AC Power` and no `discharging`, require `system_profiler SPPowerDataType` to report `Current Power Source: Yes` and `Low Power Mode: No`, and log source, battery percentage/state and low-power-mode state.
- Use one reusable DerivedData directory for codex3 and remove each result bundle after extracting counts.
- Issue #600 CAP3 remains held until #611 merges and planner announces the merge.

---

### Task 1: Pin the app-owned My Tracks comparison frame

**Files:**
- Modify: `ios/App/UITests/MakingTracksCoreLoopUITests.swift:1-340`
- Modify: `ios/App/UITests/MakingTracksCoreLoopUITests.swift:1260-1435`
- Modify: `ios/App/UITests/MakingTracksCoreLoopUITests.swift:2589-2615`

**Interfaces:**
- Consumes: two `CGRect` track-surface frames in app coordinates.
- Produces: `MyTracksRenderedComparisonFrame.appOwnedIntersection(light:dark:) -> CGRect`.

- [ ] **Step 1: Write the failing geometry test**

Add this test beside the existing pure bounded-helper tests. The hand-derived expected rectangle removes 1 point from the top and horizontal edges and 34 points from the bottom:

```swift
func testMyTracksRenderedComparisonFrameExcludesBottomSystemChrome() {
    let trackSurface = CGRect(x: 0, y: 100, width: 402, height: 774)

    XCTAssertEqual(
        MyTracksRenderedComparisonFrame.appOwnedIntersection(
            light: trackSurface,
            dark: trackSurface
        ),
        CGRect(x: 1, y: 101, width: 400, height: 739)
    )
}
```

The named break is reintroducing the full-height surface or a symmetric 1-point bottom inset; either produces a height other than 739.

- [ ] **Step 2: Run the focused test and verify RED**

Put this entry in `/private/tmp/making-tracks-611-frame-red.txt`:

```text
MakingTracksUITests/MakingTracksCoreLoopUITests/testMyTracksRenderedComparisonFrameExcludesBottomSystemChrome
```

After the power precondition passes, run:

```bash
MT_RELEASE_GATE_RUN_DIR=/private/tmp/release-gate-611-frame-red \
MT_RELEASE_GATE_DERIVED_DATA=/private/tmp/dd-codex3 \
MT_RELEASE_GATE_ONLY_TESTING_FILE=/private/tmp/making-tracks-611-frame-red.txt \
./scripts/sim-lock.sh --seat codex3 ./scripts/release-gate.sh
```

Expected: build-for-testing fails because `MyTracksRenderedComparisonFrame` does not exist. The failure must name the missing contract rather than a typo.

- [ ] **Step 3: Add the minimal frame helper**

Add beside the raster support types:

```swift
private enum MyTracksRenderedComparisonFrame {
    static func appOwnedIntersection(light: CGRect, dark: CGRect) -> CGRect {
        light.intersection(dark).inset(
            by: UIEdgeInsets(top: 1, left: 1, bottom: 34, right: 1)
        )
    }
}
```

- [ ] **Step 4: Route the live rendered oracle through the helper**

Replace the symmetric inset with:

```swift
let comparisonFrame = MyTracksRenderedComparisonFrame.appOwnedIntersection(
    light: light.trackSurfaceFrame,
    dark: dark.trackSurfaceFrame
)
```

Keep `differingPixelCount` tolerance at its default zero.

- [ ] **Step 5: Run geometry plus live raster GREEN**

Put these entries in `/private/tmp/making-tracks-611-frame-green.txt`:

```text
MakingTracksUITests/MakingTracksCoreLoopUITests/testMyTracksRenderedComparisonFrameExcludesBottomSystemChrome
MakingTracksUITests/MakingTracksCoreLoopUITests/testMyTracksRenderedPixelOraclesAcrossLightAndDarkAppearances
```

Run the same wrapper command with a unique success run directory and the GREEN list. Expected: 2/2 pass, including exact zero Light/Dark differences within the app-owned frame.

- [ ] **Step 6: Commit the completed frame RED/GREEN cycle**

```bash
git add ios/App/UITests/MakingTracksCoreLoopUITests.swift
git commit -m "Exclude system chrome from track raster oracle"
```

---

### Task 2: Separate positive fixture activation from negative coordinate probes

**Files:**
- Modify: `ios/App/UITests/MakingTracksCoreLoopUITests.swift:1493-1535`
- Modify: `ios/App/UITests/MakingTracksCoreLoopUITests.swift:3918-4080`
- Modify: `ios/App/UITests/MakingTracksCoreLoopUITests.swift:6700-6860`

**Interfaces:**
- Consumes: the active `XCUIApplication`, `map.surface`, and existing `openFixtureCard(in:app:expectedHidden:)` readiness contract.
- Produces: readiness-aware `tapFixturePin(in:app:)` for positive activation and `tapFixtureCoordinate(in:)` for intentional negative probes.

- [ ] **Step 1: Write the failing AX fixture-opening test**

Add beside the card persistence test:

```swift
func testFixturePinTapWaitsForNamedHittablePinAtAX5() {
    let app = launch(reset: true, accessibilityTextSize: true)
    let map = app.otherElements["map.surface"]
    XCTAssertTrue(map.waitForExistence(timeout: 10))

    tapFixturePin(in: map, app: app)

    XCTAssertTrue(app.staticTexts["Ghost Sign"].waitForExistence(timeout: 5))
}
```

The named break is replacing named-pin readiness with the old map-centre coordinate tap while AX fixture chrome can obstruct the centre.

- [ ] **Step 2: Run the AX test and verify RED**

Put this entry in `/private/tmp/making-tracks-611-pin-red.txt`:

```text
MakingTracksUITests/MakingTracksCoreLoopUITests/testFixturePinTapWaitsForNamedHittablePinAtAX5
```

Run the focused release gate after the power precondition passes. Expected: build-for-testing fails because the existing `tapFixturePin` has no `app` argument. The missing desired API, not a test typo, must cause RED.

- [ ] **Step 3: Implement the positive and negative helpers**

Replace the raw helper with:

```swift
private func tapFixturePin(in map: XCUIElement, app: XCUIApplication) {
    openFixtureCard(in: map, app: app)
}

private func tapFixtureCoordinate(in map: XCUIElement) {
    map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
}
```

- [ ] **Step 4: Classify every call site**

Pass the active app to the two positive calls in `testCardTogglesPersistAndRestyleMapPin`. Rename only the four intentional non-activation calls to `tapFixtureCoordinate` in:

- `testHiddenToastAutoDismissesWithoutUnhidingPlace`
- `testHideRemovesFixturePinFromMapSource`
- `testExploreScopeToggleAllCategoriesHidesAndRestoresPins`
- `testShowHiddenModeExposesUnhideAffordanceWithoutNormalHideOwnership`

No positive fixture opening may call the raw coordinate helper.

- [ ] **Step 5: Run the positive and negative focused suite GREEN**

Put these entries in `/private/tmp/making-tracks-611-pin-green.txt`:

```text
MakingTracksUITests/MakingTracksCoreLoopUITests/testFixturePinTapWaitsForNamedHittablePinAtAX5
MakingTracksUITests/MakingTracksCoreLoopUITests/testCardTogglesPersistAndRestyleMapPin
MakingTracksUITests/MakingTracksCoreLoopUITests/testHiddenToastAutoDismissesWithoutUnhidingPlace
MakingTracksUITests/MakingTracksCoreLoopUITests/testHideRemovesFixturePinFromMapSource
MakingTracksUITests/MakingTracksCoreLoopUITests/testExploreScopeToggleAllCategoriesHidesAndRestoresPins
MakingTracksUITests/MakingTracksCoreLoopUITests/testShowHiddenModeExposesUnhideAffordanceWithoutNormalHideOwnership
```

Run the focused release gate with a unique success run directory. Expected: 6/6 pass with no retry.

- [ ] **Step 6: Commit the completed fixture RED/GREEN cycle**

```bash
git add ios/App/UITests/MakingTracksCoreLoopUITests.swift
git commit -m "Wait for fixture pin readiness before tapping"
```

---

### Task 3: Prove mutation teeth and sibling completeness

**Files:**
- Verify: `ios/App/UITests/MakingTracksCoreLoopUITests.swift`
- Update: `docs/superpowers/specs/2026-08-03-ui-test-raster-pin-seams-design.md` only if implementation discovers a real design mismatch.

**Interfaces:**
- Consumes: the Task 1 geometry test and Task 2 AX integration test.
- Produces: recorded evidence that each test catches its named regression.

- [ ] **Step 1: Neuter the bottom exclusion and prove RED**

Temporarily change `bottom: 34` to `bottom: 1`, run only `testMyTracksRenderedComparisonFrameExcludesBottomSystemChrome`, and require the literal expected rectangle to fail. Restore `bottom: 34` with `apply_patch`, rerun, and require PASS.

- [ ] **Step 2: Neuter readiness delegation and prove RED**

Temporarily replace the body of `tapFixturePin(in:app:)` with the old normalized centre tap. Run only `testFixturePinTapWaitsForNamedHittablePinAtAX5` and require FAIL because Ghost Sign does not open. Restore delegation to `openFixtureCard`, rerun, and require PASS.

- [ ] **Step 3: Verify the exhaustive tap classification**

```bash
rg -n "tapFixturePin|tapFixtureCoordinate" ios/App/UITests/MakingTracksCoreLoopUITests.swift
```

Expected: readiness-aware calls occur only in the new AX test and the two positive persistence paths; raw coordinate calls occur only in the four named negative tests plus the helper definition.

- [ ] **Step 4: Verify the raster sibling sweep against the current tree**

```bash
rg -n -C 8 "differingPixelCount\(" ios/App/UITests/MakingTracksCoreLoopUITests.swift
```

Expected: Snow Settings and transition samples use element-bounded regions, Visit Date ends 34 points above the app bottom, and My Tracks uses `MyTracksRenderedComparisonFrame`.

- [ ] **Step 5: Run the combined focused suite**

Run all eight distinct geometry, raster, positive and negative tests from Tasks 1 and 2 in one focused release gate. Expected: 8/8 pass with no retry, zero warnings, and a successful result bundle removed after count extraction.

---

### Task 4: Run host and solo-gate verification

**Files:**
- Modify: `docs/superpowers/phases/pre-phase/tasks.md`

**Interfaces:**
- Consumes: the final code-bearing head after Tasks 1-3.
- Produces: exact host/full-gate evidence and durable task status.

- [ ] **Step 1: Run host verification**

```bash
cd ios
swift test
```

Expected baseline family: 518 tests, 0 failures. Restore any mechanical `Package.resolved` rewrite and verify it is byte-identical to `origin/ios` unless the target branch intentionally changed it.

- [ ] **Step 2: Verify launch power and seat state**

Record `pmset -g batt`, `system_profiler SPPowerDataType`, `pmset -g custom`, `memory_pressure`, `vm_stat`, `uptime`, and `df -h /private/tmp`. Require AC, no discharging, `Low Power Mode: No`, and `./scripts/sim-lock.sh --seat codex3 --status` reporting FREE.

- [ ] **Step 3: Run one solo full gate**

```bash
MT_GATE_MAX_CONCURRENT=1 \
MT_RELEASE_GATE_RUN_DIR=/private/tmp/release-gate-611-full \
MT_RELEASE_GATE_DERIVED_DATA=/private/tmp/dd-codex3 \
./scripts/sim-lock.sh --seat codex3 ./scripts/release-gate.sh
```

Expected: Release build, Debug build-for-testing, all app tests and all UI tests pass once with no retry, no skipped or expected failures, and no warnings. Extract exact counts/timings before deleting the successful xcresult; preserve only the reusable DerivedData directory.

- [ ] **Step 4: Record post-run telemetry and durable status**

Repeat the power, memory, load and disk samples. Append a `tests green` row to `docs/superpowers/phases/pre-phase/tasks.md` with the exact signed head, host count, app/UI counts, full-gate timing, warning state, power state, retry count and final FREE seat.

- [ ] **Step 5: Commit the evidence ledger**

```bash
git add docs/superpowers/phases/pre-phase/tasks.md
git commit -m "Record UI test hardening evidence"
```

---

### Task 5: Review and publish

**Files:**
- Update: issue #611 body with final implementation and verification evidence.
- Update: draft PR body with exact counts and review accounting.

**Interfaces:**
- Consumes: the exact signed, gate-tested code head and its `ios/` subtree hash.
- Produces: independently reviewed draft PR into `ios`; planner-owned merge handoff.

- [ ] **Step 1: Run final local checks**

Run `git diff --check`, `python3 scripts/lint_agent_law.py`, `git status --short`, the stale-base two-dot diff against freshly fetched `origin/ios`, signature verification, and ancestry verification. The diff must contain only #611 files.

- [ ] **Step 2: Request independent AMQ review**

Send planner or reviewer the exact head, spec path, issue URL, diff, RED/GREEN evidence, mutation results and gate counts. Require a severity-accounted verdict anchored to the reviewed `ios/` subtree hash; address every surviving finding and re-run affected tests.

- [ ] **Step 3: Update the issue body as one coherent record**

Rewrite issue #611 to preserve Request, Evidence, Why #607 Missed This Sibling, Outcome and exact verification. Do not add running-status comments.

- [ ] **Step 4: Push and open the draft PR**

Push the final signed branch, verify the remote head, open a draft PR into `ios`, and apply `sourcery-review`, `track-b-ios`, and `wp`. The body names #611 and #600, exact test counts, power precondition evidence, review accounting and planner merge ownership.

- [ ] **Step 5: Process automated review and hand off**

Wait for Sourcery to post, rigorously disposition and resolve every thread, verify live checks and labels, append `PR open`, `review clean`, and `ready-to-merge` ledger transitions as they become true, then send planner the exact final head and subtree hash. Do not merge. CAP3 remains held until planner announces the merge SHA.
