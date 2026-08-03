# UI-Test Raster and Fixture-Pin Seams Design

**Issue:** #611

**Prerequisite for:** #600

**Scope:** UI-test harness only; no app source or product-behaviour change

## Problem

Issue #600 CAP3 repetition 1 completed with qualifying three-way overlap but is void as capacity evidence because two independent UI-test harness seams made one runner red while the other two passed 369/369. The repetition counts as neither a qualifying pass nor a qualifying failure, so the cap-3 failure counter remains zero.

The rendered-pixel test reported 6,452 Light/Dark differences. Byte-exact analysis of the preserved images localized every asserted difference to the system home indicator at pixel bounds x=387...818 and y=2583...2597. The Light capture contained the indicator and the Dark capture did not. Every app-owned editor pixel was identical. A separate 1,089-pixel status-clock change was outside the asserted frame. The Visit Date sibling already ends its comparison surface 34 points above the app frame bottom; the My Tracks surface extends through system chrome.

The card-persistence test failed before opening Ghost Sign. Its activity tree records `map.surface` becoming observable at 13:22:10.795Z and a blind centre-coordinate tap beginning 29 milliseconds later. `tapFixturePin` observes neither fixture reset nor the named accessibility pin. Existing `openFixtureCard` and `activateFixturePin` helpers already wait for reset state, pin identity and hittability.

## Chosen Design

### App-owned rendered comparison frame

Introduce one pure frame helper for the My Tracks Light/Dark comparison. It intersects the two track-surface frames, removes one point from the top and horizontal edges as today, and removes 34 points from the bottom. The 34-point exclusion is the same system-owned bottom region already encoded by `visitDateSurfaceFrame`; it excludes the home indicator while retaining the complete app-owned editor chrome and content.

A deterministic geometry test pins all four resulting bounds. The live rendered oracle continues to require zero differing pixels inside that frame. No tolerance is added, and no app-rendered difference is waived.

### Positive fixture activation versus negative coordinate probes

`tapFixturePin` becomes a positive-opening helper that accepts the active `XCUIApplication` and delegates to the existing reset-, identity- and hit-state-driven `openFixtureCard`. Both positive calls in `testCardTogglesPersistAndRestyleMapPin` use that contract, including the relaunch path.

The four intentional negative checks currently sharing `tapFixturePin` are renamed to a raw coordinate helper whose name states that it probes the fixture coordinate without claiming pin readiness. Those tests deliberately tap where a hidden or filtered fixture would have been and assert that no card opens. Separating the names makes a future positive use of a blind coordinate tap visible in review.

A focused AX-XXXL test exercises `tapFixturePin` while fixture chrome can cover the map centre. It must open Ghost Sign through the named, hittable accessibility pin. Replacing the readiness path with the old centre tap must make this test red.

## Sibling Sweep

Every `differingPixelCount` caller in `MakingTracksCoreLoopUITests.swift` is classified:

- Snow Settings comparisons union accessibility frames belonging to specific rendered cards and controls, then intersect that region with the app frame. They never assert the full screen or a surface extending behind the home indicator.
- Snow appearance-transition sampling reuses those same element-bounded frames.
- Visit Date already constructs a surface ending 34 points above `appFrame.maxY` before applying its horizontal sheet-corner inset.
- My Tracks is the only comparison whose asserted surface reaches the app-frame bottom, so it is the only frame changed.

The direct fixture-tap sibling sweep is also exhaustive. Positive opening uses the readiness helper. Raw centre-coordinate probes survive only in tests whose asserted outcome is non-activation after hiding or filtering the fixture.

## Why Issue #607 Missed This Sibling

Issue #607 did inspect the direct `tapFixturePin` call sites, but grouped the card-persistence test with intentional negative and persistence behaviour and left those calls unchanged because they were not then-current blockers. That sweep classified call-site intent from the visible failures; it did not mutate delayed pin readiness or exercise the positive path with map-centre obstruction.

The learned sweep rule is stricter: a positive action must name and observe the state it needs. A raw coordinate helper is permitted only where the test is explicitly proving non-activation, and its name must say that it is a coordinate probe rather than a fixture-pin activation.

## Tests and Failure Semantics

RED/GREEN evidence consists of:

- a pure frame test that fails while the My Tracks comparison includes the bottom 34-point system region;
- an AX-XXXL fixture-opening test that fails when the positive helper is the raw centre tap;
- the existing card-persistence test, which exercises both initial and relaunched positive openings;
- the existing My Tracks rendered oracle, which still requires exact Light/Dark equality for all app-owned pixels.

Teeth are proven by separately neutering the bottom exclusion and the readiness delegation and observing their focused tests fail. No fixed sleep, unbounded retry, pixel tolerance, app-side sentinel or product-code change is permitted.

## Rejected Alternatives

- Changing only the two positive call sites would leave the ambiguously named blind helper available for the same mistake elsewhere.
- Waiting a fixed interval before tapping would hide readiness rather than observe it and would remain load-dependent.
- Ignoring the observed 6,452 pixels or adding a raster tolerance would weaken a strict app-render oracle even though the exact system-owned region is known.
- Generalizing every rendered oracle behind a new region abstraction would add machinery without another defective full-surface caller.

## Delivery

The change ships from an isolated branch based on fresh `origin/ios` and a draft PR into `ios`. It requires focused RED/GREEN and mutation evidence, the host Swift suite, one verified-AC solo codex3 full gate with exact counts and no retry, independent review of the exact tested head, and Sourcery review. Planner retains merge ownership. Issue #600 restarts CAP3 at repetition 1 only after #611 merges; the new measurement power precondition requires an AC source and no discharging state, logs battery percentage and low-power-mode state per sample, and fails only when low-power mode is active rather than merely configured as automatic.
