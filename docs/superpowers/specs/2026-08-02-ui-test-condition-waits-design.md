# UI-Test Condition Waits Design

**Issue:** #602  
**Prerequisite for:** #600  
**Scope:** UI-test target only; no app-source or product-behaviour changes

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

The helper checks the real condition before every focus request, taps only while focus is absent, and stops after `maxAttempts`. A thin `MakingTracksCoreLoopUITests` wrapper supplies an `XCTNSPredicateExpectation` for `hasKeyboardFocus == true` as the condition and the element's `tap()` as the request. Both `list-picker.new-name` and `lists.new-name` use the wrapper before `typeText()`.

The exhausted-bound assertion says: `keyboard focus not acquired within N attempts — known to amplify under concurrent-gate load, see #600 cap-3 rep1`. This distinguishes harness synchronization from a product assertion.

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

When capturing the first legacy-Dark Appearance region, repeatedly take a fresh screenshot and compare its current raster with the already-captured fixed-Dark Appearance raster. The capture proceeds only after the comparison reports more than 100 differing pixels, and it retains that successful raster instead of taking a new unobserved screenshot. If the bound expires, the test fails with the threshold and last observed count before the product-invariant diff loop begins.

The 100-pixel figure is derived from measured evidence: 4,242 pixels was the smallest known-good legacy-Dark transition, so 100 is comfortably below a real transition and above incidental raster noise. The remaining Settings regions capture normally after the first adaptive control proves that system Dark has propagated.

## Tests and Failure Semantics

Closure-driven tests exercise the real helper algorithms without launching the app:

- focus already present performs no tap;
- focus arriving after reacquisition succeeds within the bound;
- focus never arriving reports the exact exhausted attempt count;
- missing and sub-threshold raster samples are retried until a value above 100 arrives;
- a transition that never exceeds 100 reports the last observation and fails at the bound.

The two focused app tests then prove integration with the real accessibility predicate and screenshot raster. Removing the focus request makes the focus-helper regression test fail; accepting a sub-threshold raster makes the difference-helper regression test fail.

Validation is the host Swift package suite followed by one solo full gate through `scripts/sim-lock.sh --seat codex3`. The solo gate's exact wall-time, pass/fail counts, and pressure evidence are also recorded as cap-1/2 telemetry for #600.

## Rejected Alternatives

- Inline loops at each call site duplicate synchronization policy and allow the two text-entry siblings to drift.
- An app-side trait sentinel would make observation simpler but violates the test-only scope and couples product code to the harness.
- Fixed sleeps and unbounded retries do not observe the required condition and can turn a real failure into an indefinite or load-dependent pass.

## Review and Delivery

The change ships in its own branch and PR into `ios`, independently of #600's provisional ceiling branch. It requires deterministic RED/GREEN evidence, a clean host suite, one solo full gate, independent adversarial review, and Sourcery review before merge. Concurrency measurements resume only after this prerequisite merges and the planner opens a new window.
