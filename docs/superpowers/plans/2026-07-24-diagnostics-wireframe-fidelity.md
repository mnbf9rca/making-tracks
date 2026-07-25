# Diagnostics Wireframe Fidelity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore the shipped Diagnostics pre-Prepare screen to the hierarchy and disclosure guardrails ratified in PR #355 while retaining later approved behavior from PRs #397, #429, and #439.

**Architecture:** Keep the change inside the existing `DiagnosticsView` in `MapScreen.swift`. Reintroduce the ruled review content as explicit SwiftUI sections backed by fixed local disclosure models, add a visible selected-window status without reintroducing the obsolete session-covering export heuristic, and make the fixed action label fill the Making Tracks action bar. Pin rendering through both source-level contract tests and a real simulator UI test.

**Tech Stack:** Swift 6, SwiftUI, XCTest, XCUITest, iOS 18+

## Global Constraints

- Branch from fresh `origin/ios` and PR back to `ios`.
- Preserve the exporter privacy boundary and exact frozen class tokens.
- Preserve PR #397's plain user-facing class labels.
- Restore the Included/Excluded grids only in the pre-Prepare state. Preserve PR #429's box-free
  prepared state with Preview first, followed by ready copy.
- Preserve PR #439's scoped exclusion sentence in both states and its prepared-artifact lifetime.
- Match the frozen AXXXL variant's stated accessibility outcome: retain every class label and omit
  supporting blurbs. Collapse the runtime disclosure grid to one column at accessibility sizes. The
  frozen HTML's two-column geometry fragmented real AXXXL labels into single letters on the designated
  simulator; the one-column adaptation is required to preserve the ruled readable-label guardrail.
- Fold the small #447 privacy fix found during review: redact absolute tile X/Y from diagnostic object paths.
- Do not force a color scheme or absorb #350's app-wide theming scope.
- App-target verification runs only through `./scripts/sim-lock.sh`.
- Baseline host suite has the separately tracked #446 failure: 385 tests, 1 failure in `testTrackVisitDateHeadersAreNotStandaloneMovableRows`.

---

### Task 1: Restore the ruled Diagnostics review screen

**Files:**
- Modify: `ios/Tests/MakingTracksTilesTests/LoggingPrivacyTests.swift`
- Modify: `ios/App/UITests/MakingTracksCoreLoopUITests.swift`
- Modify: `ios/App/Sources/Map/MapScreen.swift`
- Modify: `ios/Sources/MakingTracksTiles/MakingTracksLog.swift`

**Interfaces:**
- Consumes: `DiagnosticLogWindow.settingsOptions`, `DiagnosticLogWindow.label`, the existing selected-window binding, and existing `DiagnosticsView` state.
- Produces: `settings.diagnostics.window-status`, `settings.diagnostics.included`, `settings.diagnostics.excluded`, and the full-width `settings.diagnostics.prepare` action.

- [ ] **Step 1: Replace the source contract that requires disclosure boxes to be absent**

Change `testDiagnosticsConsentCopyKeepsExportClassesWithoutDisclosureBoxes` into a contract that requires:

```swift
for expected in [
    "Nothing is sent automatically. The app prepares a file on this phone",
    "App details", "Device type", "Steps in the app", "Downloaded maps",
    "Map file links", "Problems", "Load times", "Places and taps",
    "Device name", "Precise location", "Search text",
    "Your device name, exact location, and searches are not included in the export.",
] {
    XCTAssertTrue(source.contains(expected), expected)
}
XCTAssertTrue(source.contains("diagnosticsClassGrid("))
XCTAssertTrue(source.contains("Section(\"Included\")"))
XCTAssertTrue(source.contains("Section(\"Excluded\")"))
```

Also require the ruled review order and action copy:

```swift
XCTAssertTrue(source.contains("\"Prepare file\""))
XCTAssertTrue(source.contains("settings.diagnostics.window-status"))
```

- [ ] **Step 2: Add a simulator regression for visible pre-Prepare guardrails**

Extend the existing dark-appearance Diagnostics test to assert the following elements exist before tapping Prepare:

```swift
XCTAssertTrue(app.staticTexts["settings.diagnostics.window-status"].waitForExistence(timeout: 3))
XCTAssertTrue(app.otherElements["settings.diagnostics.included"].exists)
XCTAssertTrue(app.otherElements["settings.diagnostics.excluded"].exists)
XCTAssertTrue(app.buttons["Prepare file"].exists)
```

Keep the existing assertion for the scoped exclusion sentence.

Add an AXXXL simulator regression that proves class labels remain present while supporting blurbs are
absent. Assert that every disclosure label shares the same leading edge, pinning the one-column runtime
adaptation required by device evidence.

- [ ] **Step 3: Run focused tests to verify RED**

Run:

```bash
cd ios
swift test --filter LoggingPrivacyTests/testDiagnostics
```

Expected: the updated source contract fails because the current screen has no status row or disclosure grids and still labels the action `Prepare`.

Run the focused UI test through the simulator lock. Expected: FAIL because the new accessibility identifiers and `Prepare file` action do not exist.

- [ ] **Step 4: Implement the review hierarchy and disclosures**

In `DiagnosticsView`, render one hero section in this order:

```swift
Text("Send a diagnostic log")
Text("Nothing is sent automatically. The app prepares a file on this phone; when you share, you pick who gets it.")
Picker(...)
diagnosticsWindowStatus
```

`diagnosticsWindowStatus` must name the selected explicit window and say archive size is shown after preparation; it must not claim the removed session-covering promotion:

```swift
Label {
    VStack(alignment: .leading, spacing: 2) {
        Text("Showing \(selectedWindow.statusLabel)")
            .font(.callout.weight(.semibold))
        Text("Archive size is shown after Prepare.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
} icon: {
    Image(systemName: "arrow.up.doc")
        .foregroundStyle(DiagnosticsVisualSpec.accent)
}
.accessibilityElement(children: .combine)
.accessibilityIdentifier("settings.diagnostics.window-status")
```

Add the exact status wording beside the existing picker label:

```swift
var statusLabel: String {
    switch self {
    case .fifteenMinutes:
        return "the last 15 minutes"
    case .lastHour:
        return "the last hour"
    case .everything:
        return "everything"
    }
}
```

Restore `Included` and `Excluded` class grids using PR #397's labels only while `artifact == nil`.
Keep the PR #439 scoped exclusion sentence below the excluded grid before Prepare and repeat it in the
prepared `Before sharing` section. This keeps the prepared state box-free and Preview-first per #429.
Give each pre-Prepare section a stable accessibility identifier. Disable the window picker while preparing
and while an artifact exists so the visible window cannot diverge from the prepared file.

At accessibility Dynamic Type sizes, omit `DiagnosticsDisclosureClass.detail`, retain every title and
icon, and collapse the disclosure grid to one column. The frozen render's accessibility requirement is
readable class names; its two-column HTML geometry does not survive real AXXXL rendering, so the
device-proven one-column layout implements that requirement without authoring a new wireframe mid-build.

Redact coordinate-bearing CDN object paths through `MakingTracksLog.objectPath`: retain region, publish
version, object kind, and tile Z, but replace absolute X/Y components with placeholders. Preserve readable
non-coordinate paths such as `current.json`.

- [ ] **Step 5: Implement the ruled fixed action**

Change the pre-Prepare action to `Prepare file`, place the max-width frame inside the button label, and tint primary diagnostics actions with the ruled `#0a6b5c` accent:

```swift
Button(action: beginPreparation) {
    Text(isPreparing ? "Preparing" : "Prepare file")
        .fontWeight(.semibold)
        .frame(maxWidth: .infinity, minHeight: 44)
}
.buttonStyle(.borderedProminent)
.tint(DiagnosticsVisualSpec.accent)
```

Do not change navigation chrome or force light appearance.

- [ ] **Step 6: Run focused tests to verify GREEN**

Run the focused host Diagnostics tests. Expected: all focused tests pass.

Run the focused simulator UI test through `sim-lock.sh`. Expected: the window status, Included, Excluded, scoped exclusion sentence, and Prepare file action are present before preparation.

- [ ] **Step 7: Verify teeth**

Temporarily remove the Included section and run the focused source and UI tests. Expected: both turn red. Restore the section and rerun to green.

Temporarily change `Prepare file` back to `Prepare` and run the focused tests. Expected: red. Restore and rerun to green.

- [ ] **Step 8: Run the full gates**

Run `swift test` and confirm only the already tracked #446 baseline failure remains until that upstream issue lands. Then run:

```bash
./scripts/sim-lock.sh ./scripts/release-gate.sh
```

Capture actual Release, app-unit, and UI-test counts and confirm zero new warnings.

- [ ] **Step 9: Commit and push**

Commit with:

```bash
git add docs/superpowers/plans/2026-07-24-diagnostics-wireframe-fidelity.md ios/App/Sources/Map/MapScreen.swift ios/App/UITests/MakingTracksCoreLoopUITests.swift ios/Sources/MakingTracksTiles/MakingTracksLog.swift ios/Tests/MakingTracksTilesTests/LoggingPrivacyTests.swift
git commit -m "Restore diagnostics wireframe hierarchy"
```

Push `wp-324-device-wireframe-fix`, then open a PR to `ios` referencing #324 with `track-b-ios`, `wp`, and `sourcery-review`.
