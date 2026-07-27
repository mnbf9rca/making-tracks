# A9 Quiet Text Press Inset Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give enabled text-only quiet Hide and Unhide controls perceptible pressed geometry while preserving disabled controls and the icon-bearing Settings gear.

**Architecture:** Extend the shared `MaterialControlPressFeedback` vocabulary with a text-inset strategy and let `MaterialQuietButtonStyle.textOnly(theme:)` select it. The default quiet style remains the A5 symbol-weight pulse. `PlaceCardActionAppearance` owns the narrow Hide/Unhide routing decision, while `MaterialButtonStyleBody` applies the inset only when the control is both enabled and pressed.

**Tech Stack:** Swift 6, SwiftUI, XCTest, AppKit `ImageRenderer` host render tests, XCUITest evidence capture.

## Global Constraints

- Branch from exact `origin/ios` commit `4c580c4f7d4a592626db71ad7f590349fa85c1c8` and target `ios`.
- Geometry only; never change enabled opacity or semantic colours.
- Hide and Unhide gain the inset; disabled Un-see and Seen remain unchanged.
- The location-off Settings gear keeps A5's symbol-weight pulse.
- The proposed literal is a 1pt downward pressed displacement, cited to `amendment-wave.md` A9.
- Record the alternative reading—content/bezel shrink rather than vertical displacement—in the PR body's `## Taste guesses`.
- Evidence must use A5's press-holding capture method and report dark-pixel counts plus bounding boxes beside default-size and AX rest/pressed images.

---

### Task 1: Pin the quiet text-only feedback contract

**Files:**
- Modify: `ios/Tests/DesignSystemTests/ControlStylesTests.swift`
- Modify: `ios/App/Tests/AppShellTests.swift`

**Interfaces:**
- Consumes: `MaterialQuietButtonStyle.pressFeedback`, `MaterialButtonStyleBody`, `PlaceCardAction`
- Produces: regression coverage for the 1pt enabled press displacement and the exact Hide/Unhide routing set

- [ ] **Step 1: Invert the existing do-nothing test**

Rename `testQuietTextOnlyBodyRetainsPressScaleWithoutWeightPulse` to
`testQuietTextOnlyBodyAddsRuledInsetToPressScale`. Keep the existing
`pressScale` assertion, but replace the unscaled rest/pressed identity
assertion with literal bounds assertions:

```swift
XCTAssertEqual(pressedBounds.minX, restingBounds.minX)
XCTAssertEqual(pressedBounds.minY, restingBounds.minY + 1)
XCTAssertEqual(pressedBounds.size, restingBounds.size)
```

Add a disabled render pair and assert that its pixels remain identical. Add
strategy assertions that the default quiet style remains
`.symbolWeightPulse`, while `MaterialQuietButtonStyle.textOnly()` resolves to
`.textInset(points: 1)`.

- [ ] **Step 2: Pin the mounted action routing**

Extend `testPlaceCardActionsUseRuledDesignSystemStylesWithoutDestructiveHide`
with hand-written expectations:

```swift
XCTAssertTrue(PlaceCardActionAppearance.usesQuietTextPressInset(for: .hide))
XCTAssertTrue(PlaceCardActionAppearance.usesQuietTextPressInset(for: .unhide))
XCTAssertFalse(
    PlaceCardActionAppearance.usesQuietTextPressInset(
        for: .unsee(isEnabled: false)
    )
)
XCTAssertFalse(
    PlaceCardActionAppearance.usesQuietTextPressInset(for: .seenDisabled)
)
```

- [ ] **Step 3: Run the focused tests and verify RED**

Run:

```bash
swift test --package-path ios --filter ControlStylesTests
```

Expected: compile failure because `.textInset(points:)`,
`MaterialQuietButtonStyle.textOnly(theme:)`, and the enabled-only offset do
not exist.

The app routing test is simulator-backed and runs in the full gate after the
host-tested seam is green.

- [ ] **Step 4: Commit the red tests**

```bash
git add ios/Tests/DesignSystemTests/ControlStylesTests.swift ios/App/Tests/AppShellTests.swift
git commit -S -m "test(ios): pin quiet text press inset"
```

---

### Task 2: Implement the scoped 1pt inset

**Files:**
- Modify: `ios/Sources/DesignSystem/ControlStyles.swift`
- Modify: `ios/App/Sources/PlaceCard/PlaceCardSheet.swift`

**Interfaces:**
- Consumes: the existing `MaterialControlPressFeedback.scale(isPressed:tokens:)` and A5 symbol-weight environment
- Produces: `MaterialControlPressFeedback.textInset(points:)`, `MaterialQuietButtonStyle.textOnly(theme:)`, and `PlaceCardActionAppearance.usesQuietTextPressInset(for:)`

- [ ] **Step 1: Add the minimal shared feedback strategy**

Add the strategy case and its enabled-only geometry:

```swift
case textInset(points: CGFloat)

func verticalOffset(isPressed: Bool, isEnabled: Bool) -> CGFloat {
    guard isPressed, isEnabled else { return 0 }
    switch self {
    case let .textInset(points):
        return points
    case .scale, .symbolWeightPulse:
        return 0
    }
}
```

Map `.textInset` to `.standard` symbol weight and retain the existing
token-backed `pressScale` for every strategy. Apply the returned offset before
the button's outer content shape: `offset` preserves the original layout
dimensions, while the outer shape stays rooted in the stable 44pt hit target.

- [ ] **Step 2: Add the cited text-only quiet factory**

Keep `MaterialQuietButtonStyle.init(theme:)` on `.symbolWeightPulse`. Add:

```swift
public static func textOnly(
    theme: MaterialTheme = .snow
) -> MaterialQuietButtonStyle {
    MaterialQuietButtonStyle(
        theme: theme,
        pressFeedback: .textInset(points: 1)
    )
}
```

The `1` literal cites `amendment-wave.md` A9 in a nearby comment; it is the
builder-proposed figure awaiting metrics-table ratification.

- [ ] **Step 3: Route only Hide and Unhide**

Implement `PlaceCardActionAppearance.usesQuietTextPressInset(for:)` with
literal `.hide` and `.unhide` cases. In `PlaceCardActionStyleModifier`, select
`MaterialQuietButtonStyle.textOnly(theme:)` only when that helper returns
true; all other quiet controls keep `MaterialQuietButtonStyle(theme:)`.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run:

```bash
swift test --package-path ios --filter ControlStylesTests
```

Expected: all focused tests pass.

- [ ] **Step 5: Prove teeth**

Temporarily return `0` for `.textInset` and rerun the inverted host test;
expected: the literal `minY + 1` assertion fails. Restore the implementation
and rerun green.

Temporarily remove `.unhide` from the mounted routing helper during the
simulator unit gate; expected: the AppShell routing assertion fails. Restore
the implementation before the final gate.

- [ ] **Step 6: Commit the implementation**

```bash
git add ios/Sources/DesignSystem/ControlStyles.swift ios/App/Sources/PlaceCard/PlaceCardSheet.swift
git commit -S -m "feat(ios): inset quiet text on press"
```

---

### Task 3: Verify and evidence the mounted behavior

**Files:**
- Create: `docs/design/design-system/a9-place-card-hide-rest.png`
- Create: `docs/design/design-system/a9-place-card-hide-pressed.png`
- Create: `docs/design/design-system/a9-place-card-hide-ax-rest.png`
- Create: `docs/design/design-system/a9-place-card-hide-ax-pressed.png`
- Modify: the smallest existing UI-test capture seam that can hold Hide pressed without navigating

**Interfaces:**
- Consumes: the A5 repeated-real-tap press-holding method and the designated simulator lock
- Produces: exact-head default/AX rest/pressed artifacts with dark-pixel counts and bounding boxes

- [ ] **Step 1: Run the complete host suite**

Run:

```bash
swift test --package-path ios
```

Expected: 0 failures.

- [ ] **Step 2: Capture default and AX held-press evidence**

Use only `scripts/sim-lock.sh` for the designated simulator. Reuse A5's
repeated-real-tap capture method; do not use
`XCUIElement.press(forDuration:)` as evidence. If a temporary no-navigation
seam is needed to hold Hide visibly pressed, keep it out of the final source
diff.

- [ ] **Step 3: Measure every image pair**

For the isolated Hide text region, record the count of dark pixels and the
`x,y,width,height` bounding box for rest and pressed at default and AX sizes.
Reject and recapture any pair whose measured region is identical.

- [ ] **Step 4: Run the full host release gate**

Run:

```bash
./scripts/sim-lock.sh ./scripts/release-gate.sh
```

Expected: Release build, app unit tests, and UI shards pass with 0 warnings.
Reuse `/private/tmp/dd-codex1`; delete result bundles after extracting counts.

- [ ] **Step 5: Run exact-head adversarial and Opus review**

Review spec fidelity, internal coherence, correctness, untrusted-data posture,
and test quality. Request Opus review of the exact pushed SHA with the four
images and measurements, explicitly asking it to judge vertical displacement
against the alternative content/bezel-shrink reading.

- [ ] **Step 6: Commit final evidence**

```bash
git add docs/design/design-system/a9-place-card-hide-*.png
git commit -S -m "docs(ios): add quiet text press evidence"
```

- [ ] **Step 7: Re-ground, push, and open the PR**

Fetch `origin/ios`, prove it is an ancestor of `HEAD`, inspect
`git diff --stat origin/ios..HEAD`, push, and open a ready PR into `ios`.
Apply `sourcery-review`, `track-b-ios`, and `wp` immediately. The PR body cites
#526/A9, includes actual test counts, adversarial accounting, embedded renders
with their measurements, the inverted assertion, and `## Taste guesses`.
