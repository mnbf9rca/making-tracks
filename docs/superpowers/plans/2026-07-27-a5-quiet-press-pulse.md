# A5 Quiet-Control Symbol-Weight Pulse Implementation Plan

> **For Codex:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Give enabled quiet buttons perceptible press feedback by changing their SF Symbol from medium to semibold while pressed, without fading semantic colours or changing the filled and tonal scale treatment. Quiet controls retain their existing token-backed press scale so text-only quiet actions keep feedback.

**Architecture:** Keep `MaterialControlAppearance` palette-only and add an explicit press-feedback strategy to the shared button body. Filled and tonal styles select the existing token-backed scale strategy; quiet selects a symbol-weight pulse that retains that geometry while adding symbol weight. A private SwiftUI environment value carries only the current symbol weight into both supported symbol paths: `iconRole(_:)` and SwiftUI `Label` icons. This corrects the earlier scale-`1` draft after adversarial review identified text-only quiet controls that would otherwise lose all feedback.

**Tech Stack:** Swift 6, SwiftUI, XCTest, AppKit `ImageRenderer` host render tests.

---

### Task 1: Route quiet presses through a symbol-weight strategy

**Files:**
- Modify: `ios/Tests/DesignSystemTests/ControlStylesTests.swift`
- Modify: `ios/Sources/DesignSystem/ControlStyles.swift`
- Modify: `ios/Sources/DesignSystem/Iconography.swift`
- Verify mounted consumer: `ios/App/Sources/Map/MapContextualChrome.swift:27`
- Verify mounted contract: `ios/App/Tests/AppShellTests.swift:697`

**Step 1: Write the failing tests**

Add a strategy test that proves the three button styles choose the ruled feedback:

```swift
func testButtonStylesResolveTheirRatifiedPressFeedback() {
    XCTAssertEqual(MaterialFilledButtonStyle().pressFeedback, .scale)
    XCTAssertEqual(MaterialTonalButtonStyle().pressFeedback, .scale)
    XCTAssertEqual(
        MaterialQuietButtonStyle().pressFeedback,
        .symbolWeightPulse
    )
}
```

Add a quiet-body host render test using the first mounted glyph, `gearshape.fill`, with `.iconRole(.inline)`. Render resting and pressed bodies over transparency with a supplied `pressScale` of `0.87`, then assert:

- the image dimensions are identical;
- the quiet style's scale strategy resolves to `0.87` when pressed, preserving text-only quiet feedback;
- a separate supplied `pressScale` of `1` isolates the semibold pulse, whose pressed rendering has materially more muted glyph coverage than resting;
- every sufficiently opaque glyph pixel remains the literal Snow `muted` RGB and full alpha, with a non-vacuous opaque-pixel minimum in both states;
- the direct glyph bounds stay glyph-sized in both states, rejecting a restored translucent background.

Add an equivalent empty-title `Label` coverage assertion so the shared style cannot fix only the explicit `iconRole(_:)` path. Render a title-only quiet body at scale `1` and assert resting/pressed pixels are identical, proving button text does not change weight.

**Step 2: Run the focused tests and verify RED**

Run:

```bash
swift test --package-path ios --filter ControlStylesTests
```

Expected: compile/test failure because `pressFeedback` and the symbol-weight pulse do not exist.

**Step 3: Implement the minimal strategy**

In `ControlStyles.swift`, add:

```swift
enum MaterialControlPressFeedback: Equatable, Sendable {
    case scale
    case symbolWeightPulse

    func scale(isPressed: Bool, tokens: MaterialTokenSheet) -> CGFloat {
        switch self {
        case .scale:
            MaterialControlInteractionFeedback.semanticControlScale(
                isPressed: isPressed,
                tokens: tokens
            )
        case .symbolWeightPulse:
            MaterialControlInteractionFeedback.semanticControlScale(
                isPressed: isPressed,
                tokens: tokens
            )
        }
    }

    func symbolWeight(isPressed: Bool) -> MaterialControlSymbolWeight {
        switch self {
        case .scale:
            .standard
        case .symbolWeightPulse:
            isPressed ? .emphasized : .standard
        }
    }
}
```

Give filled and tonal styles `pressFeedback == .scale`, quiet
`pressFeedback == .symbolWeightPulse`, and pass that value into
`MaterialButtonStyleBody`. Replace the body's unconditional scale lookup with
`pressFeedback.scale(isPressed:tokens:)`, and place
`pressFeedback.symbolWeight(isPressed:)` into the label environment.

In `Iconography.swift`, add the module-internal vocabulary and environment key:

```swift
enum MaterialControlSymbolWeight: Equatable, Sendable {
    case standard
    case emphasized

    var swiftUI: Font.Weight {
        switch self {
        case .standard: .medium
        case .emphasized: .semibold
        }
    }
}
```

Make `IconRoleModifier` read this environment value and replace its hard-coded
`.medium`. Make `MaterialControlLabelStyle` read the same value and apply it to
the icon only. Resting symbols therefore remain exactly medium; pressed quiet
symbols become semibold; button text does not change.

Do not change `MapLocationOffToast`: its existing
`.iconRole(.inline)` + `.buttonStyle(MaterialQuietButtonStyle())` mount must
inherit the behavior.

**Step 4: Run the focused tests and verify GREEN**

Run:

```bash
swift test --package-path ios --filter ControlStylesTests
```

Expected: all focused tests pass.

**Step 5: Prove the tests have teeth**

Temporarily change quiet's strategy back to `.scale` and run the new quiet
tests. Expected: strategy and render tests fail. Restore the implementation.

Temporarily map `.emphasized` to `.medium` and run the new render tests.
Expected: glyph-coverage tests fail. Restore `.semibold`.

Temporarily fade the resting button body and run the new render tests.
Expected: the opaque-pixel minimum and title-only identity tests fail. Restore semantic enabled opacity.

**Step 6: Run package and mounted-contract verification**

Run:

```bash
swift test --package-path ios
```

The canonical simulator release gate changes what the app displays, but it remains controller-owned for centralized simulator coordination:

```bash
./scripts/sim-lock.sh ./scripts/release-gate.sh
```

Expected: package tests, Release build, app/unit tests, and UI shards all pass.

**Step 7: Commit**

```bash
git add docs/superpowers/plans/2026-07-27-a5-quiet-press-pulse.md ios/Sources/DesignSystem/ControlStyles.swift ios/Sources/DesignSystem/Iconography.swift ios/Tests/DesignSystemTests/ControlStylesTests.swift
git commit -S -m "feat(ios): pulse quiet symbols on press"
```
