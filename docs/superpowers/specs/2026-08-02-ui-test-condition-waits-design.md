# UI-Test Condition Waits Design

**Issue:** #602
**Prerequisite for:** #600
**Scope:** UI-test hardening plus one DEBUG-only app launch-argument seam; no Release product-behaviour change

## Problem

Issue #600's first three-gate run exposed two harness races that obscured the host-capacity result.

All three seats failed list creation after `tap()` waited 21–34 seconds for app idleness. The target text field still existed with the same frame and value when `typeText()` ran, but it no longer held keyboard focus. The suite has exactly two text-entry paths, and both use the same immediate `tap()` then `typeText()` shape without observing focus.

Two seats also failed the Snow oracle only in its deliberately unpinned legacy-Dark control. Every fixed Light/Dark region remained byte-identical, so the #590 production pin held. The failing legacy control had zero changed pixels because the system-Dark transition had not reached it before capture. The successful control changed by 26,066 / 36,157 / 4,242 pixels across the three frozen regions.

## Chosen Design

### Keyboard focus acquisition

Add a test-only `AXFocusAcquirer` with a closure-driven interface:

```swift
static func acquire(
    maxAttempts: Int,
    interval: TimeInterval = 0,
    isFocused: () -> Bool,
    requestFocus: () -> Void
) -> AXFocusAcquisitionMatch
```

The helper checks the real condition before every focus request, taps only while focus is absent, and stops after `maxAttempts`. A thin `MakingTracksCoreLoopUITests` wrapper supplies the runtime focus observation as the condition and the element's `tap()` as the request. Both `list-picker.new-name` and `lists.create.name` use the wrapper before `typeText()`.

**Fix-forward amendment — Xcode 26.6 / iOS 26.5 integration evidence.** The originally proposed `hasKeyboardFocus == true` predicate remained false before and after all three taps for both fields in a clean solo codex3 run, yet a diagnostic continuation immediately typed into both fields, created both lists, and passed the complete custom-list test. Shipping that predicate would therefore manufacture solo failures. The wrapper instead self-selects software-keyboard presence when the keyboard is visible and the public `XCUIElement.hasFocus` focused-element query when it is not (including hardware-keyboard mode). The integration test asserts the proxy is false on each fresh pre-tap field, and successful bounded acquisition followed by successful `typeText()` proves the true polarity. An exhausted failure names the last proxy used. The closure-driven selector tests cover software-keyboard presence, hardware-keyboard focused-element success, and an unfocused fresh field.

A second runtime finding supersedes the original test-only appearance design. A clean solo run and an independent codex1 full gate both held legacy Dark at zero changed pixels through the observer's full 40-sample bound, while `XCUIDevice.shared.appearance` reported Dark. An independent codex4 full gate then reproduced the same zero-delta assertion as its only failure: 344 of 345 tests passed, including 98 of 99 UI tests and all 246 non-UI tests; both Release and Debug build-for-testing passed. Apple Developer Forums thread 812656 documents the same XCTest regression: appearance changes are ignored when UI tests run through `xcodebuild` on newer Xcode/iOS runtimes. A subsequent run also exposed the inverse stale-state failure, with legacy Light still rendering Dark by the known 26,066-pixel Appearance delta. System-delivered appearance is therefore untestable under this Release-gate runtime, not merely slow.

**Fix-forward scope authorization — 2026-08-02.** The planner authorized a DEBUG-only `--ui-testing-color-scheme light|dark` launch-argument injection alongside the existing `--ui-testing-disable-material-mode-lock` precedent. The resolver returns the production Snow lock while the lock is enabled, regardless of the injected scheme; only the deliberately unpinned legacy controls receive the injected Light or Dark value. This proves #590's actual invariant — the production pin beats the color scheme — without claiming the runtime delivered system appearance. Release builds contain neither the resolver nor the argument string, proven by a Release build plus symbol/string absence check. The source comment links Apple thread 812656, records the bounded-observer evidence, and states the removal condition: restore system-delivered appearance when XCTest under `xcodebuild` is fixed.

Fixed Light is captured first as the rendered target. Legacy Light retains the first raster that matches it exactly; legacy Dark retains the first raster that differs from the fixed-Dark target by more than 100 pixels. The fixed Light/Dark captures receive different injected inputs while retaining the production lock and still participate in the exact equality oracle, so a weak production pin cannot be hidden by the injection. The test result carries an explicit attachment stating that Dark provenance is **INJECTED**, not system-delivered, on this runtime.

The exhausted-bound assertion says: `keyboard focus not acquired within N attempts using <proxy> — known to amplify under concurrent-gate load, see #600 cap-3 rep1`. This distinguishes harness synchronization from a product assertion and identifies the runtime observable.

### Legacy-Dark transition observation

Add a test-only `RenderedDifferenceWaiter` with closure-driven sampling:

```swift
static func wait(
    exceeding threshold: Int,
    attempts: Int,
    interval: TimeInterval = 0,
    sample: () -> Int?
) -> RenderedDifferenceMatch
```

When capturing the first injected legacy-Dark Appearance region, repeatedly take a fresh screenshot and compare its current raster with the already-captured fixed-Dark Appearance raster. The capture proceeds only after the comparison reports more than 100 differing pixels, and it retains that successful raster instead of taking a new unobserved screenshot. If the bound expires, the test fails with the threshold, last observed count, and injected provenance before the product-invariant diff loop begins.

The 100-pixel figure is derived from measured evidence: 4,242 pixels was the smallest known-good legacy-Dark transition, so 100 is comfortably below a real transition and above incidental raster noise. The remaining Settings regions capture normally after the first adaptive control proves that system Dark has propagated.

## Tests and Failure Semantics

Closure-driven tests exercise the real helper algorithms without launching the app:

- focus already present performs no tap;
- focus arriving after reacquisition succeeds within the bound;
- focus never arriving reports the exact exhausted attempt count;
- missing and sub-threshold raster samples are retried until a value above 100 arrives;
- a transition that never exceeds 100 reports the last observation and fails at the bound.
- the DEBUG resolver keeps the Snow material lock under an injected Dark input, supplies injected Dark only when that lock is disabled, and remains unpinned without an injection.

The two focused app tests then prove integration with the real accessibility predicate and screenshot raster. Removing the focus request makes the focus-helper regression test fail; accepting a sub-threshold raster makes the difference-helper regression test fail.

Validation is the host Swift package suite followed by the app-code-bearing full gate through `scripts/sim-lock.sh --seat codex3`. A Release build is inspected with `nm` and binary strings for the injection type and argument, both of which must be absent. The gate's exact wall-time, pass/fail counts, and pressure evidence are also recorded as cap-1/2 telemetry for #600.

## Rejected Alternatives

- Inline loops at each call site duplicate synchronization policy and allow the two text-entry siblings to drift.
- A runtime trait sentinel would couple the harness to app state and could report Dark without proving rendered Dark. The authorized launch-argument resolver instead drives the real SwiftUI color-scheme input and is compiled out of Release.
- Host-level release-gate restructuring around simulator-wide appearance would be disproportionate and would still depend on the broken XCTest/system-delivery path.
- Fixed sleeps and unbounded retries do not observe the required condition and can turn a real failure into an indefinite or load-dependent pass.

## Review and Delivery

The change ships in its own branch and PR into `ios`, independently of #600's provisional ceiling branch. It requires deterministic RED/GREEN evidence, a clean host suite, one solo full gate, independent adversarial review, and Sourcery review before merge. Concurrency measurements resume only after this prerequisite merges and the planner opens a new window.
