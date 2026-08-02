# UI-Test Condition Waits Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make both UI-test timing boundaries condition-based and fail-explicit before issue #600 resumes concurrency measurement.

**Architecture:** Keep focus and raster policy inside `MakingTracksCoreLoopUITests.swift`. A DEBUG-only app resolver supplies a rendered color-scheme input because Xcode 26's `xcodebuild` appearance delivery is broken; the production material lock remains the higher-precedence value and the Release path contains no injection code.

**Tech Stack:** Swift, XCTest/XCUI, CoreGraphics screenshot rasters, the repository simulator wrapper, and the Release gate.

## Global Constraints

- Issue #602 was originally test-only. On 2026-08-02 the planner authorized one DEBUG-only app-source seam after bounded and independent evidence corroborated Apple thread 812656; Release product behavior must remain unchanged and injection symbols/strings must be absent.
- Use bounded condition observation; no fixed sleep, unbounded retry, or retry-until-lucky behavior.
- Keyboard exhaustion must mention concurrent-gate load and `#600 cap-3 rep1`.
- The raster threshold is strictly greater than 100 pixels; cite the known-good 4,242-pixel minimum beside it.
- Every simulator command runs through `./scripts/sim-lock.sh --seat codex3`.
- The final solo gate is also live cap-1/2 telemetry for #600.

## Fix-forward authorization (supersedes conflicting Task 4 details)

- Add resolver tests before implementation: locked + injected Dark resolves Snow Light; unlocked + injected Dark resolves Dark; unlocked without injection resolves nil.
- Under `#if DEBUG`, parse `--ui-testing-color-scheme light|dark` beside `--ui-testing-disable-material-mode-lock`. The source comment must cite Apple thread 812656, the 40-sample bounded-observer evidence, the 2026-08-02 decision date, and removal when XCTest `xcodebuild` appearance delivery is fixed.
- Feed all four Snow captures an explicit injected input. Fixed Light/Dark retain the production lock; legacy Light/Dark disable it. Record Dark provenance as INJECTED, not system-delivered.
- Preserve the bounded raster observer and retained successful screenshot. Remove reliance on `XCUIDevice.shared.appearance` for this oracle.
- Run the full gate because #602 now bears app code. Build Release and prove the injection type and argument string absent with `nm`/binary inspection, mirroring #595's proof shape.

---

### Task 1: Prove the two condition algorithms RED

**Files:**
- Modify: `ios/App/UITests/MakingTracksCoreLoopUITests.swift:1-460`

**Interfaces:**
- Consumes: closure-supplied focus state/actions and raster-difference samples.
- Produces: tests for `AXFocusAcquirer.acquire(...)` and `RenderedDifferenceWaiter.wait(...)` before those symbols exist.

- [ ] **Step 1: Add deterministic helper tests**

Add tests beside the existing `AXValueWaiter` tests. The focus cases use literal state sequences and assert the real algorithm result plus tap count:

```swift
func testAXFocusAcquirerSkipsRequestWhenAlreadyFocused() {
    var requests = 0
    let result = AXFocusAcquirer.acquire(
        maxAttempts: 3,
        interval: 0,
        isFocused: { true },
        requestFocus: { requests += 1 }
    )
    XCTAssertEqual(result, AXFocusAcquisitionMatch(matched: true, attempts: 0))
    XCTAssertEqual(requests, 0)
}

func testAXFocusAcquirerReacquiresWithinBound() {
    var samples = [false, false, true]
    var requests = 0
    let result = AXFocusAcquirer.acquire(
        maxAttempts: 3,
        interval: 0,
        isFocused: { samples.removeFirst() },
        requestFocus: { requests += 1 }
    )
    XCTAssertEqual(result, AXFocusAcquisitionMatch(matched: true, attempts: 2))
    XCTAssertEqual(requests, 2)
}

func testAXFocusAcquirerReportsExhaustedBound() {
    var samples = [false, false, false, false]
    var requests = 0
    let result = AXFocusAcquirer.acquire(
        maxAttempts: 3,
        interval: 0,
        isFocused: { samples.removeFirst() },
        requestFocus: { requests += 1 }
    )
    XCTAssertEqual(result, AXFocusAcquisitionMatch(matched: false, attempts: 3))
    XCTAssertEqual(requests, 3)
}
```

Add raster cases whose expected values are hand-derived from `[nil, 100, 101]` and `[nil, 0, 100]`:

```swift
func testRenderedDifferenceWaiterWaitsForValueAboveThreshold() {
    var samples: [Int?] = [nil, 100, 101]
    let result = RenderedDifferenceWaiter.wait(
        exceeding: 100,
        attempts: 3,
        interval: 0,
        sample: { samples.removeFirst() }
    )
    XCTAssertEqual(result, RenderedDifferenceMatch(matched: true, observed: 101, attempts: 3))
}

func testRenderedDifferenceWaiterReportsExhaustedBound() {
    var samples: [Int?] = [nil, 0, 100]
    let result = RenderedDifferenceWaiter.wait(
        exceeding: 100,
        attempts: 3,
        interval: 0,
        sample: { samples.removeFirst() }
    )
    XCTAssertEqual(result, RenderedDifferenceMatch(matched: false, observed: 100, attempts: 3))
}
```

- [ ] **Step 2: Run the five focused tests and verify RED**

Create `/private/tmp/making-tracks-602-helper-tests.txt` containing the five fully qualified test names, then run a focused gate through seat `codex3`:

```bash
MT_RELEASE_GATE_RUN_DIR=/private/tmp/release-gate-602-red \
MT_RELEASE_GATE_ONLY_TESTING_FILE=/private/tmp/making-tracks-602-helper-tests.txt \
./scripts/sim-lock.sh --seat codex3 ./scripts/release-gate.sh
```

Expected: build-for-testing fails because `AXFocusAcquirer`, `AXFocusAcquisitionMatch`, `RenderedDifferenceWaiter`, and `RenderedDifferenceMatch` do not exist. The failure must come from those missing contracts, not a typo in the tests.

---

### Task 2: Implement the minimal condition algorithms GREEN

**Files:**
- Modify: `ios/App/UITests/MakingTracksCoreLoopUITests.swift:1-460`

**Interfaces:**
- Consumes: the Task 1 tests.
- Produces: `AXFocusAcquisitionMatch`, `AXFocusAcquirer`, `RenderedDifferenceMatch`, and `RenderedDifferenceWaiter`.

- [ ] **Step 1: Add the focus result and bounded acquirer**

```swift
private struct AXFocusAcquisitionMatch: Equatable {
    let matched: Bool
    let attempts: Int
}

private enum AXFocusAcquirer {
    static func acquire(
        maxAttempts: Int,
        interval: TimeInterval = 0,
        isFocused: () -> Bool,
        requestFocus: () -> Void
    ) -> AXFocusAcquisitionMatch {
        precondition(maxAttempts > 0, "AX focus acquisition must make at least one attempt")
        var attempts = 0
        var focused = isFocused()
        while !focused, attempts < maxAttempts {
            requestFocus()
            attempts += 1
            focused = isFocused()
            if !focused, interval > 0, attempts < maxAttempts {
                RunLoop.current.run(until: Date().addingTimeInterval(interval))
            }
        }
        return AXFocusAcquisitionMatch(matched: focused, attempts: attempts)
    }
}
```

- [ ] **Step 2: Add the raster result and bounded waiter**

```swift
private struct RenderedDifferenceMatch: Equatable {
    let matched: Bool
    let observed: Int?
    let attempts: Int
}

private enum RenderedDifferenceWaiter {
    static func wait(
        exceeding threshold: Int,
        attempts: Int,
        interval: TimeInterval = 0,
        sample: () -> Int?
    ) -> RenderedDifferenceMatch {
        precondition(attempts > 0, "rendered difference wait must make at least one sample")
        var observed: Int?
        for attempt in 1...attempts {
            observed = sample()
            if let observed, observed > threshold {
                return RenderedDifferenceMatch(matched: true, observed: observed, attempts: attempt)
            }
            if interval > 0, attempt < attempts {
                RunLoop.current.run(until: Date().addingTimeInterval(interval))
            }
        }
        return RenderedDifferenceMatch(matched: false, observed: observed, attempts: attempts)
    }
}
```

- [ ] **Step 3: Re-run the five focused tests and verify GREEN**

Run the Task 1 focused command with `MT_RELEASE_GATE_RUN_DIR=/private/tmp/release-gate-602-helper-green`.

Expected: all five helper tests pass with zero warnings.

- [ ] **Step 4: Commit the helper cycle**

```bash
git add ios/App/UITests/MakingTracksCoreLoopUITests.swift
git commit -S -m "Add bounded UI test condition helpers"
git push origin HEAD
```

---

### Task 3: Acquire focus at every text-entry sibling

**Files:**
- Modify: `ios/App/UITests/MakingTracksCoreLoopUITests.swift:1788-1840`
- Modify: `ios/App/UITests/MakingTracksCoreLoopUITests.swift:6200-6460`

**Interfaces:**
- Consumes: `AXFocusAcquirer.acquire(...)`.
- Produces: `acquireKeyboardFocus(_:in:maxAttempts:) -> Bool`, used by both text fields before `typeText()`.

- [ ] **Step 1: Add the runtime-proxy XCUI adapter**

```swift
private func acquireKeyboardFocus(
    _ element: XCUIElement,
    in app: XCUIApplication,
    maxAttempts: Int = 3,
    file: StaticString = #filePath,
    line: UInt = #line
) -> Bool {
    func observeFocus() -> KeyboardFocusObservation {
        KeyboardFocusProxySelector.observe(
            softwareKeyboardPresent: app.keyboards.firstMatch.exists,
            elementFocused: element.hasFocus
        )
    }

    var lastObservation = observeFocus()
    guard !lastObservation.focused else {
        XCTFail("keyboard focus proxy was already true on the fresh pre-tap field")
        return false
    }

    let result = AXFocusAcquirer.acquire(
        maxAttempts: maxAttempts,
        interval: 0.1,
        isFocused: {
            let predicate = NSPredicate { _, _ in
                lastObservation = observeFocus()
                return lastObservation.focused
            }
            return XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(predicate: predicate, object: element)],
                timeout: 1
            ) == .completed
        },
        requestFocus: { element.tap() }
    )
    guard result.matched else {
        XCTFail(
            "keyboard focus not acquired within \(maxAttempts) attempts using \(lastObservation.proxy.rawValue) — known to amplify under concurrent-gate load, see #600 cap-3 rep1",
            file: file,
            line: line
        )
        return false
    }
    return true
}
```

- [ ] **Step 2: Replace both immediate tap/type pairs**

```swift
let listPickerName = app.textFields["list-picker.new-name"]
guard acquireKeyboardFocus(listPickerName, in: app) else { return }
listPickerName.typeText("KL walk")

let rootListField = app.textFields["lists.create.name"]
guard acquireKeyboardFocus(rootListField, in: app) else { return }
rootListField.typeText(rootListName)
```

- [ ] **Step 3: Run the focused custom-list integration test**

Run a focused Release gate for:

```text
MakingTracksUITests/MakingTracksCoreLoopUITests/testCustomListCanBeCreatedBrowsedAndShownOnMap
```

Expected: 1 test passes. `rg 'typeText\('` still finds exactly two calls, and both are immediately guarded by `acquireKeyboardFocus`.

---

### Task 4: Inject and observe legacy appearance before Snow diffs

**Files:**
- Modify: `ios/App/Sources/MakingTracksApp.swift`
- Modify: `ios/App/Tests/AppShellTests.swift`
- Modify: `ios/App/UITests/MakingTracksCoreLoopUITests.swift:1521-1710`
- Modify: `ios/App/UITests/MakingTracksCoreLoopUITests.swift:5000-5260`
- Modify: `ios/App/UITests/MakingTracksCoreLoopUITests.swift:6740-6780`

**Interfaces:**
- Consumes: the DEBUG `UITestingColorSchemeInjection`, fixed Light/Dark Appearance captures, and `RenderedDifferenceWaiter.wait(...)`.
- Produces: explicit injected Light/Dark inputs, a legacy-Light raster matching fixed Light, and a legacy-Dark raster exceeding the 100-pixel difference threshold from fixed Dark.

- [ ] **Step 1: Add the DEBUG-only color-scheme resolver RED/GREEN cycle**

Add tests proving that the production material lock wins over injected Dark, that disabling the lock exposes injected Dark, and that disabling the lock without injection remains unpinned. Implement `--ui-testing-color-scheme light|dark` parsing only under `#if DEBUG`, with an explicit unchanged Release path. Record Apple thread 812656, bounded evidence, decision date, and removal condition in the source comment.

- [ ] **Step 2: Capture explicit injected inputs in ruled order**

Capture fixed Light first, then legacy Light with `.matches(fixedLightAppearance)`, fixed Dark, and legacy Dark with `.differs(fixedDarkAppearance)`. Fixed captures retain the production Snow lock; legacy captures disable it. Pass `forceDarkAppearance: false` so this oracle has no dependency on the broken `XCUIDevice.shared.appearance` path. Attach kept evidence stating that Dark provenance is INJECTED and the invariant is production pin precedence.

- [ ] **Step 3: Resample and retain the observed legacy rasters**

Inside the nested Appearance `capture`, use 40 samples at 0.25-second intervals. Legacy Light waits for exactly zero differing pixels from fixed Light; legacy Dark waits for more than 100 differing pixels from fixed Dark. Store the screenshot and raster produced by the successful sample. The threshold comment must read:

```swift
// The smallest known-good legacy-Dark delta is 4,242 pixels; 100 stays
// comfortably below a real transition while excluding raster noise.
```

On legacy-Dark exhaustion, fail with injected provenance, the threshold, and the last observation. Use an `attachScreenshot(_:named:forceExport:)` overload so the successful screenshot becomes the attached/exported frozen evidence; do not take a replacement screenshot after the condition succeeds.

- [ ] **Step 4: Run resolver, helper, focus, and Snow integration tests**

Run a focused gate for the three resolver tests, focus helper/proxy tests, rendered-difference helper tests, and both complete integrations:

```text
MakingTracksUITests/MakingTracksCoreLoopUITests/testCustomListCanBeCreatedBrowsedAndShownOnMap
MakingTracksUITests/MakingTracksCoreLoopUITests/testSnowSettingsAdaptiveInkIsLegibleAndInvariantAcrossSystemAppearances
```

Expected: 3 app tests and 11 UI tests pass. Snow fixed Light/Dark remains zero-diff, legacy Light matches fixed Light, and the injected legacy-Dark Appearance transition is greater than 100 before the final oracle loop.

- [ ] **Step 5: Commit and push the integrations**

```bash
git add ios/App/Sources/MakingTracksApp.swift ios/App/Tests/AppShellTests.swift ios/App/UITests/MakingTracksCoreLoopUITests.swift
git commit -S -m "Harden UI test focus and appearance waits"
git push origin HEAD
```

---

### Task 5: Validate, record telemetry, and publish

**Files:**
- Modify: `docs/superpowers/phases/pre-phase/tasks.md`
- Modify: issue #602 body outcome after final evidence exists.

**Interfaces:**
- Consumes: the final branch head and seat `codex3`.
- Produces: host evidence, one solo full-gate record, #600 cap-1/2 telemetry, independent review, and a draft PR into `ios`.

- [x] **Step 1: Run the host suite**

Run `swift test` with the working directory set to `ios/`.

Expected baseline: 516 tests, 0 failures, zero new warnings.

- [x] **Step 2: Run one solo full gate**

```bash
./scripts/sim-lock.sh --seat codex3 ./scripts/release-gate.sh
```

Capture Release and Debug build results, exact unit/UI counts, wall time, retry/flake count, and host pressure samples. Clean the task `.xcresult` through the documented wrapper-safe gate cleanup path and verify `--status` reports `FREE`.

- [x] **Step 3: Record #602 and #600 evidence durably**

Add a `tests green` row for #602 to `docs/superpowers/phases/pre-phase/tasks.md`. Add the solo gate as live cap-1/2 telemetry in the #600 branch record and relay the exact evidence to the planner over AMQ.

- [x] **Step 4: Run self-review and independent review**

Review spec fidelity, bounded-wait correctness, failure semantics, test teeth, and threat-model scope. Because subagent delegation is unavailable in this session, request an independent AMQ review and resolve every surviving finding before PR creation.

- [x] **Step 5: Re-ground and verify the branch**

Fetch `origin/ios`, prove `origin/ios` is an ancestor of `HEAD`, run `git diff --check`, review `git diff --stat origin/ios..HEAD`, verify signed commits and a clean worktree, then push.

- [x] **Step 6: Open the draft PR**

Open a draft PR into `ios` that names #602 and #600, includes exact test counts and review accounting, and applies `sourcery-review`, `track-b-ios`, and `wp`. Process Sourcery and independent-review findings; do not merge.
