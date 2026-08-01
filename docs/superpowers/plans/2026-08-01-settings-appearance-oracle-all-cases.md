# Settings Appearance Oracle All-Cases Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Snow appearance-invariance UI oracle classify every rendered Settings group and fail when a future `SettingsGroup` case is added without coverage.

**Architecture:** Give the Settings-group stack a stable accessibility container, then have the existing four-state raster test discover the buttons rendered by `ForEach(SettingsGroup.allCases)` and compare them with its explicit capture classifications. Extend the capture helper to the four previously unproven routes while retaining frozen evidence export and contrast/legacy-regression measurements for Appearance, Map & data, and Location only.

**Tech Stack:** Swift 6, SwiftUI, XCTest/XCUITest, existing `RenderedPixelRaster` helpers, simulator-locked iOS gate.

## Global Constraints

- Branch from fresh `origin/ios`; PR target is `ios`.
- Every simulator command runs through `./scripts/sim-lock.sh --seat codex2`.
- The six committed #590 evidence PNGs and their hashes remain unchanged.
- No source-text assertion may stand in for rendered behavior.
- A future Settings group must fail until its route is explicitly classified.

---

### Task 1: Prove the all-cases classification gap

**Files:**
- Modify: `ios/App/UITests/MakingTracksCoreLoopUITests.swift`

**Interfaces:**
- Consumes: the existing `captureSnowSettingsThemeLock(...) -> SettingsThemeLockCapture?` four-state helper.
- Produces: an expected seven-region contract and runtime Settings-root identifier classification.

- [x] **Step 1: Write the failing assertions**

Change the expected region set from the three frozen evidence names to all seven Settings routes:

```swift
let regionNames = [
    "appearance", "offline-maps", "coverage", "map-data",
    "location", "diagnostics", "replay-welcome",
]
```

Inside `captureSnowSettingsThemeLock`, require the rendered Settings-group container to expose exactly the seven explicitly classified row identifiers before navigating any route.

- [x] **Step 2: Run the focused test to verify RED**

Run through the codex2 simulator wrapper with only `MakingTracksCoreLoopUITests/testSnowSettingsAdaptiveInkIsLegibleAndInvariantAcrossSystemAppearances` selected.

Expected: FAIL because the current capture returns only Appearance, Map & data, and Location (and the Settings group container has no stable identifier yet).

### Task 2: Classify and capture every rendered Settings group

**Files:**
- Modify: `ios/App/Sources/Map/MapScreen.swift`
- Modify: `ios/App/UITests/MakingTracksCoreLoopUITests.swift`

**Interfaces:**
- Consumes: `SettingsGroup.allCases`, existing Settings row identifiers, and existing raster capture helpers.
- Produces: `SettingsThemeLockCapture.regions` entries for all seven Settings groups under each of legacy Light, fixed Light, fixed Dark, and legacy Dark.

- [x] **Step 1: Add the runtime classification boundary**

Add `settings.groups` to the `VStack` rendered directly by `ForEach(SettingsGroup.allCases)` and preserve its children in the accessibility tree.

- [x] **Step 2: Capture the four missing routes**

Use the existing route selectors already exercised by `testSettingsHubRoutesEveryRuledGroupWithoutLosingExistingActions`:

- Offline maps: `settings.storage.manage` and the deterministic forced-offline
  `offline-maps.storage.unavailable` surface
- Coverage: `settings.group.coverage` and the three `settings.coverage.*` information rows
- Diagnostics: `settings.diagnostics.export` and `settings.diagnostics.window-status`
- Replay welcome: `settings.replay-onboarding`, the “Interesting places around you” title, and `onboarding.next`

Capture rasters and comparison frames for all four. Navigate back after destination routes; run Replay welcome last because it exits Settings.

- [x] **Step 3: Preserve the frozen evidence contract**

Only force-export screenshots for `appearance`, `map-data`, and `location`. The four added regions participate in runtime equality checks but do not add or replace committed #590 PNGs.

- [x] **Step 4: Verify GREEN**

Run the same focused UI test. Expected: 1 passed, 0 failed, with fixed Light/Dark difference zero for all seven regions and unchanged measurement/evidence exports for the original three.

### Task 3: Verify, review, and publish

**Files:**
- Modify: `docs/superpowers/phases/pre-phase/tasks.md`
- Update issue #591 body before closing after merge.

**Interfaces:**
- Consumes: focused test results and adversarial review findings.
- Produces: a reviewed PR into `ios` with issue #591 linked and actual gate counts.

- [x] **Step 1: Run host and project checks**

Run `swift test`, `git diff --check`, and confirm the six tracked #590 PNG SHA-256 values are unchanged from `snow-theme-lock-evidence.md`.

- [x] **Step 2: Run adversarial review**

Review spec fidelity, correctness, test teeth, evidence stability, and hostile-input/security posture; fix surviving findings and re-run focused verification.

- [x] **Step 3: Run the full iOS host gate**

Run `MT_RELEASE_GATE_DERIVED_DATA=/private/tmp/dd-codex2 ./scripts/sim-lock.sh --seat codex2 ./scripts/release-gate.sh`; record exact unit/UI counts and warnings.

Gate-tested head `2b9d0c3` passed Release build, Debug build-for-testing,
245 app unit tests, and 97 UI tests (342 total, 0 failed/skipped) without a
retry or flake. Wrapper wall time was 2,809 seconds; the successful result
bundle was removed after count extraction and reusable DerivedData retained.

- [x] **Step 4: Publish**

Fresh-fetch `origin/ios`, verify the two-dot diff contains only #591 work, commit, push, open a draft PR into `ios` with `sourcery-review`, `track-b-ios`, and `wp`, process every review thread, and report to planner/reviewer over AMQ.
