# Fixture-Pin Hittability Acquisition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Repair issue #617's latent AX5 UI-test timing seam so the reposition regression acquires the named fixture pin only after it is simultaneously present, hittable, and outside the captured map centre.

**Architecture:** Keep the change inside `MakingTracksCoreLoopUITests.swift`. A pure `FixturePinRepositionObservation` classifier maps the three live conditions to the existing `AXScrollObservation` vocabulary. The live test supplies that observation to `AXBoundedScroller.acquire(maxScrolls: 3)`, preserving the existing edge drag, intentional negative centre probe, and positive named-pin opener.

**Tech Stack:** Swift 6, XCTest/XCUITest, UIKit geometry, the repository release-gate wrapper, AMQ review.

## Global constraints

- UI-test harness only; do not change app source or product behaviour.
- The planner-approved success condition is exact: `.hittable` only for `exists && isHittable && !frameContainsMapCenter`.
- Missing maps to `.missing`; every present non-match maps to `.presentNotHittable`.
- At most three condition-driven edge drags; no sleeps or unbounded retry.
- Preserve the raw centre-tap negative probe and the named-pin positive opener assertions.
- Every simulator command runs through `./scripts/sim-lock.sh --seat codex3`.
- Before simulator work, verify AC power and an allowed power mode using the inherited iOS gate precondition.
- Use unique run directories so the preserved #612 failure bundle at `/tmp/release-gate-AC60FA71-9449-4F15-A259-5E4A3E832839/MakingTracksTests.xcresult` remains untouched.
- Keep #616 scripts/docs-only. This repair is one signed commit on its stacked branch and one separate PR targeting `ios`.
- Run exactly one fresh full codex3 gate on the reviewed combined head; focused TDD runs are scoped verification, not replacement full gates.

---

### Task 1: Pin the combined observation contract

**Files:**
- Modify: `ios/App/UITests/MakingTracksCoreLoopUITests.swift:1-40`
- Modify: `ios/App/UITests/MakingTracksCoreLoopUITests.swift:1320-1395`

**Interface:**
- Consumes: `exists`, `isHittable`, `frameContainsMapCenter`.
- Produces: `AXScrollObservation`.

- [x] **Step 1: Add the pure failing regression**

Add beside the existing pure bounded-scroller tests:

```swift
func testFixturePinRepositionObservationRejectsOffCentreNonHittablePin() {
    XCTAssertEqual(
        FixturePinRepositionObservation.classify(
            exists: true,
            isHittable: false,
            frameContainsMapCenter: false
        ),
        .presentNotHittable
    )
}
```

The named break is classifying a present, off-centre element as acquired before `isHittable` becomes true.

- [x] **Step 2: Run the focused test and verify RED**

Create `/private/tmp/making-tracks-617-pure.txt` with:

```text
MakingTracksUITests/MakingTracksCoreLoopUITests/testFixturePinRepositionObservationRejectsOffCentreNonHittablePin
```

After the power precondition passes, run:

```bash
MT_RELEASE_GATE_RUN_DIR=/private/tmp/release-gate-617-red \
MT_RELEASE_GATE_ONLY_TESTING_FILE=/private/tmp/making-tracks-617-pure.txt \
./scripts/sim-lock.sh --seat codex3 ./scripts/release-gate.sh
```

Expected: build-for-testing fails because `FixturePinRepositionObservation` does not exist. The compiler error must name that missing contract.

- [x] **Step 3: Add the minimal pure classifier**

Add beside `AXScrollObservation`:

```swift
private enum FixturePinRepositionObservation {
    static func classify(
        exists: Bool,
        isHittable: Bool,
        frameContainsMapCenter: Bool
    ) -> AXScrollObservation {
        guard exists else { return .missing }
        guard isHittable, !frameContainsMapCenter else {
            return .presentNotHittable
        }
        return .hittable
    }
}
```

---

### Task 2: Route the live AX5 regression through bounded acquisition

**Files:**
- Modify: `ios/App/UITests/MakingTracksCoreLoopUITests.swift:1524-1550`

- [x] **Step 1: Replace the local frame-only loop**

Capture `mapCenter` once, then call `AXBoundedScroller.acquire(maxScrolls: 3)`. Its observation closure must sample the named pin and delegate all state classification to `FixturePinRepositionObservation.classify(...)`. Its scroll closure keeps the existing `0.08/0.58 → 0.08/0.25` edge drag.

- [x] **Step 2: Fail with terminal live diagnostics**

Require `match.matched`. On failure report `match.scrolls`, `match.observation`, `pin.exists`, `pin.isHittable`, `pin.frame`, `mapCenter`, and `map.frame`. Do not rely on a second immediate assertion as the acquisition mechanism.

- [x] **Step 3: Preserve both activation probes**

Keep, in order:

1. `tapFixtureCoordinate(in: map)` and the negative `Ghost Sign` assertion.
2. `tapFixturePin(in: map, app: app)` and the positive `Ghost Sign` assertion.

- [x] **Step 4: Run focused GREEN**

Create `/private/tmp/making-tracks-617-green.txt` with the pure regression and `testFixturePinTapUsesNamedPinAfterMapRepositionAtAX5`. Run the wrapper with unique run directory `/private/tmp/release-gate-617-green`.

Expected: 2/2 pass, no retry.

- [x] **Step 5: Prove mutation teeth**

Temporarily classify `exists && !frameContainsMapCenter` as `.hittable`, ignoring `isHittable`. Run the pure focused test and require RED with expected `.presentNotHittable` versus observed `.hittable`. Restore the production condition with `apply_patch`, rerun both focused tests, and require 2/2 GREEN.

---

### Task 3: Review, publish, and gate the combined head

**Files:**
- Modify: `docs/superpowers/phases/pre-phase/tasks.md`
- Verify: all files changed from `5e9a9496e60e50ed862770762b6be89de5599f68`

- [x] **Step 1: Run static and host checks**

Run `git diff --check`, the agent-law lint, and `swift test --package-path ios`. Record exact counts.

- [ ] **Step 2: Commit and push one signed seam repair commit**

Stage only the plan, UI-test source, and #617 ledger lines. Review the staged diff, sign the commit, verify the signature, push the branch, then verify the remote head.

- [ ] **Step 3: Obtain scoped independent review**

Review the exact commit against #617 and the planner ruling. The clearance must name its scope, exact head, and Critical/Important/Minor counts. Resolve surviving findings before the full gate.

- [ ] **Step 4: Run one fresh full combined gate**

Notify planner immediately before starting. Use a unique run directory, the production default concurrency cap, and:

```bash
MT_RELEASE_GATE_RUN_DIR=/private/tmp/release-gate-617-full \
./scripts/sim-lock.sh --seat codex3 ./scripts/release-gate.sh
```

Expected: Release and Debug build-for-testing pass; 372/372 tests pass with 0 failed/skipped (251 app + 121 UI, including the new pure regression). Extract counts before deleting only the task-created successful result bundle. Recheck `--status` reports `FREE`.

- [ ] **Step 5: Open and hand off the separate draft PR**

Open a draft PR from `fix-617-fixture-pin-hittability` to `ios`, label it `sourcery-review`, `track-b-ios`, and `wp`, and state that it is stacked on #616 until planner merges #616 first. Update issue bodies with final evidence, append ledger transitions, verify live checks and exact heads, and hand both #616 and #617 heads to planner. Do not merge.
