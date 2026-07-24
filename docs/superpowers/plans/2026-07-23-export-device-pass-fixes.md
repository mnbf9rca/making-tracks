# Export Device-Pass Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep the diagnostics exclusion disclosure rendered before Prepare, retain prepared archives until the screen exits, and reduce a device-scale Last-hour snapshot from seconds to well under two seconds without losing selected or malformed log lines.

**Architecture:** `DiagnosticsView` owns presentation lifetime: share-sheet dismissal is inert, explicit Cancel/Delete clean immediately, and view disappearance cleans staging. `DiagnosticLogStore` keeps Everything as a no-filter path and filters bounded windows using the canonical fixed-width UTC timestamp that the store itself writes; malformed timestamps remain included fail-safe.

**Tech Stack:** Swift 6, SwiftUI, XCTest, XCUITest, Foundation.

## Global Constraints

- Target `ios`; iOS 18+ and Swift 6 strict concurrency remain unchanged.
- No server, upload endpoint, telemetry, schema, dependency, or privacy-boundary change.
- Exact location, device name, and raw search wording remain excluded and scrubbed fail-closed.
- Last hour and 15 min export every matching line; Everything exports every line.
- Prepared archives survive share-sheet completion/cancellation, but explicit Cancel/Delete and exiting Diagnostics remove them.
- The designated simulator is touched only through `scripts/sim-lock.sh`.

---

### Task 1: Device-scale bounded snapshot

**Files:**
- Modify: `ios/Sources/MakingTracksTiles/DiagnosticLogExport.swift`
- Test: `ios/Tests/MakingTracksTilesTests/DiagnosticLogExportTests.swift`

**Interfaces:**
- Consumes: canonical timestamps emitted by `DiagnosticLogStore.appendRawLine(_:)`, formatted as `yyyy-MM-dd'T'HH:mm:ssZ`.
- Produces: unchanged `DiagnosticLogStore.snapshot(window:) -> DiagnosticLogSnapshot`.

- [ ] **Step 1: Write the failing 100,000-line regression**

Add a test that writes one file directly, avoiding 100,000 open/seek/close cycles:

```swift
func testLastHourSnapshotFiltersOneHundredThousandLinesWithinTwoSeconds() throws {
    let fixture = try makeFixture()
    try FileManager.default.createDirectory(at: fixture.logs, withIntermediateDirectories: true)
    let oldLine = "2026-07-19T10:58:13Z flow info old event"
    let recentLine = "2026-07-19T12:05:13Z flow info recent event"
    let malformedLine = "not-a-timestamp startup info retain fail-safe"
    let historicalLineCount = 100_000
    let text = Array(repeating: oldLine, count: historicalLineCount).joined(separator: "\n")
        + "\n\(recentLine)\n\(malformedLine)\n"
    try text.write(
        to: fixture.logs.appendingPathComponent("making-tracks.log"),
        atomically: true,
        encoding: .utf8
    )
    let store = DiagnosticLogStore(root: fixture.logs, now: { fixture.now })

    let startedAt = DispatchTime.now().uptimeNanoseconds
    let snapshot = try store.snapshot(window: .lastHour)
    let duration = Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000_000

    XCTAssertEqual(snapshot.totalLineCount, historicalLineCount + 2)
    XCTAssertEqual(snapshot.lines, [recentLine, malformedLine])
    XCTAssertLessThan(duration, 2.0, "snapshot took \(duration)s")
}
```

- [ ] **Step 2: Run it and verify RED**

Run:

```bash
cd ios
swift test --filter DiagnosticLogExportTests/testLastHourSnapshotFiltersOneHundredThousandLinesWithinTwoSeconds
```

Expected: FAIL because the current per-line `ISO8601DateFormatter` construction takes about 11–14 seconds at device scale.

- [ ] **Step 3: Implement canonical bounded-window filtering**

In `DiagnosticLogWindow`, expose a private cutoff date (`nil` for Everything). In `snapshotLocked`, return all lines immediately for Everything. For bounded windows, format the cutoff once and compare it with a validated canonical timestamp token. The token validator checks fixed separators, ASCII digits, leap-year/day bounds, and time bounds; returning `nil` retains malformed lines fail-safe.

```swift
private func snapshotLocked(window: DiagnosticLogWindow, allLines: [String]) -> DiagnosticLogSnapshot {
    guard let cutoff = window.cutoff(relativeTo: now()) else {
        return DiagnosticLogSnapshot(totalLineCount: allLines.count, lines: allLines)
    }
    let cutoffToken = Self.timestampFormatter().string(from: cutoff)
    let windowLines = allLines.filter { line in
        guard let timestamp = Self.canonicalTimestampToken(from: line) else { return true }
        return timestamp >= cutoffToken[...]
    }
    return DiagnosticLogSnapshot(totalLineCount: allLines.count, lines: windowLines)
}
```

- [ ] **Step 4: Verify GREEN and the existing exporter suite**

Run:

```bash
cd ios
swift test --filter DiagnosticLogExportTests
```

Expected: 14 tests pass, including the new 100,000-line regression in under two seconds.

- [ ] **Step 5: Commit**

```bash
git add ios/Sources/MakingTracksTiles/DiagnosticLogExport.swift ios/Tests/MakingTracksTilesTests/DiagnosticLogExportTests.swift
git commit -m "Speed up bounded diagnostic snapshots"
```

### Task 2: Disclosure rendering and prepared-artifact lifetime

**Files:**
- Modify: `ios/App/Sources/Map/MapScreen.swift`
- Test: `ios/Tests/MakingTracksTilesTests/LoggingPrivacyTests.swift`
- Test: `ios/App/UITests/MakingTracksCoreLoopUITests.swift`

**Interfaces:**
- Consumes: `DiagnosticsView.artifact`, `shareItem`, and `cleanupPreparedArtifact()`.
- Produces: unchanged accessibility identifiers and a persistent visible exclusion sentence before Prepare.

- [ ] **Step 1: Write the failing lifecycle source regression**

Add:

```swift
func testDiagnosticsKeepsPreparedArtifactUntilCancelDeleteOrScreenExit() throws {
    let source = try String(
        contentsOf: packageRoot().appendingPathComponent("App/Sources/Map/MapScreen.swift"),
        encoding: .utf8
    )

    XCTAssertFalse(source.contains(".sheet(item: $shareItem, onDismiss: cleanupPreparedArtifact)"))
    XCTAssertTrue(source.contains(".sheet(item: $shareItem) { item in"))
    XCTAssertTrue(source.contains(".onDisappear(perform: cleanupPreparedArtifact)"))
    XCTAssertTrue(source.contains("Button(\"Cancel\") {\n                    cleanupPreparedArtifact()"))
}
```

- [ ] **Step 2: Write the failing dark-appearance render regression**

Add an XCUITest that opens Settings → Diagnostics before Prepare:

```swift
func testDiagnosticsShowsScopedExclusionBeforePrepareInDarkAppearance() {
    let app = launch(reset: true, forceDarkAppearance: true)
    XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 10))
    openAppMenu(in: app)
    app.buttons["menu.row.settings"].tap()
    let diagnostics = app.buttons["settings.diagnostics.export"]
    XCTAssertTrue(scrollToHittable(diagnostics, in: app))
    diagnostics.tap()

    let exclusion = app.staticTexts[
        "Your device name, exact location, and searches are not included in the export."
    ]
    XCTAssertTrue(scrollToExistence(of: exclusion, in: app))
    XCTAssertTrue(exclusion.isHittable)
    attachScreenshot(named: "diagnostics-prepared-exclusions-dark")
}
```

- [ ] **Step 3: Run the host lifecycle regression and verify RED**

Run:

```bash
cd ios
swift test --filter LoggingPrivacyTests/testDiagnosticsKeepsPreparedArtifactUntilCancelDeleteOrScreenExit
```

Expected: FAIL because share-sheet dismissal currently invokes cleanup and screen exit does not.

- [ ] **Step 4: Run the rendered regression and verify RED**

Run under `scripts/sim-lock.sh` with the designated UDID, `-parallel-testing-enabled NO`, `-maximum-concurrent-test-simulator-destinations 1`, and reusable derived data `/private/tmp/dd-codex2`.

Expected: FAIL because the exclusion row does not exist before Prepare.

- [ ] **Step 5: Implement the minimal SwiftUI lifetime change**

Keep Preview and ready copy inside `if let artifact`, then render one always-present `Section("Before sharing")`. Show the chooser/no-endpoint bullets only when `artifact != nil`, and always show the exclusion sentence. Remove the sheet `onDismiss` cleanup and attach `.onDisappear(perform: cleanupPreparedArtifact)` to the Diagnostics view.

- [ ] **Step 6: Verify GREEN**

Run the focused host tests and the focused XCUITest again. Expected: all pass, and the dark screenshot contains the exclusion row.

- [ ] **Step 7: Commit**

```bash
git add ios/App/Sources/Map/MapScreen.swift ios/Tests/MakingTracksTilesTests/LoggingPrivacyTests.swift ios/App/UITests/MakingTracksCoreLoopUITests.swift
git commit -m "Keep diagnostic exports until screen exit"
```

### Task 3: Required gates and handoff

**Files:**
- Verify only.

**Interfaces:**
- Consumes: Tasks 1–2.
- Produces: test counts, Release gate evidence, adversarial review accounting, pushed branch, and a PR into `ios`.

- [ ] **Step 1: Run the full host suite**

```bash
cd ios
swift test
```

Expected: 382 host-package tests pass, 0 failures; the new XCUITest is counted separately in the simulator gate.

- [ ] **Step 2: Run adversarial review**

Dispatch independent critics for spec fidelity/internal coherence, correctness/performance, threat-model/privacy, and test teeth. Cross-examine findings, fix those that survive, and prove test teeth for each fix.

- [ ] **Step 3: Re-ground and run the host simulator/Release gate**

Fetch `origin/ios`, verify ancestry, then run:

```bash
./scripts/sim-lock.sh ./scripts/release-gate.sh
```

Expected: Release build and simulator suites pass with zero warnings. Capture exact counts and remove result bundles per the runbook.

- [ ] **Step 4: Review stale-base diff and push**

Verify `git diff --stat origin/ios..HEAD` contains only this plan and the export fixes. Push the branch.

- [ ] **Step 5: Open the PR and request review**

Open a draft PR into `ios`, name #324 and #351 in the body, include exact test/gate counts and adversarial accounting, and apply `sourcery-review`, `track-b-ios`, and `wp`. Request Fable/Opus review through AMQ and process every review thread.
