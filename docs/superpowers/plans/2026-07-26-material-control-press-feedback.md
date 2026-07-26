# Material Control Press Feedback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve semantic token contrast during enabled press feedback by replacing whole-control opacity with a 0.98 geometry scale in material buttons and chips.

**Architecture:** One internal `MaterialControlInteractionFeedback` policy supplies disabled-only opacity and pressed-only scale to both material style bodies. The scale remains inside each style body, while `MaterialChip` keeps its expanded interaction shape outside, preserving the 44pt target.

**Tech Stack:** Swift 6, SwiftUI, XCTest, XCUITest, Swift Package Manager

## Global Constraints

- Enabled opacity is always `1`; disabled opacity remains `0.46`.
- Pressed scale is `0.98`; resting scale is `1`.
- Both `MaterialChipStyleBody` and `MaterialButtonStyleBody` consume the same policy.
- `MaterialChipHitTargetShape` remains outside the scaled style body.
- The snow filled pair must preserve its opaque `6.1330:1` contrast instead of the former composited `3.8801:1`.
- Production changes follow strict RED-GREEN-REFACTOR.

---

### Task 1: Shared material interaction feedback

**Files:**
- Modify: `ios/Tests/DesignSystemTests/ControlStylesTests.swift`
- Modify: `ios/App/UITests/MakingTracksCoreLoopUITests.swift`
- Modify: `ios/Sources/DesignSystem/ControlStyles.swift`

**Interfaces:**
- Consumes: SwiftUI `isEnabled` and `ButtonStyle.Configuration.isPressed`
- Produces: `MaterialControlInteractionFeedback.semanticControlOpacity(isEnabled:) -> Double`
- Produces: `MaterialControlInteractionFeedback.semanticControlScale(isPressed:) -> CGFloat`

- [ ] **Step 1: Write the failing package policy tests**

Add independently derived branch assertions:

```swift
func testMaterialControlInteractionFeedbackPreservesEnabledOpacity() {
    XCTAssertEqual(
        MaterialControlInteractionFeedback.semanticControlOpacity(
            isEnabled: true
        ),
        1
    )
    XCTAssertEqual(
        MaterialControlInteractionFeedback.semanticControlOpacity(
            isEnabled: false
        ),
        0.46
    )
}

func testMaterialControlInteractionFeedbackUsesScaleForPresses() {
    XCTAssertEqual(
        MaterialControlInteractionFeedback.semanticControlScale(
            isPressed: false
        ),
        1
    )
    XCTAssertEqual(
        MaterialControlInteractionFeedback.semanticControlScale(
            isPressed: true
        ),
        0.98
    )
}
```

- [ ] **Step 2: Extend AC29 before changing production code**

In `testMaterialChipExtendsHitTargetBeyondVisualCapsule`, use an
`XCUICoordinate` at the top 11pt outset edge and call:

```swift
coordinate(at: topOutsideVisualCapsule).press(forDuration: 0.2)
XCTAssertTrue(waitForActivationCount("1"))
```

Keep the bottom-edge tap and its second activation assertion. This preserves
the existing edge check while exercising the pressed lifecycle.

- [ ] **Step 3: Run the focused package tests to verify RED**

Run:

```bash
swift test --filter ControlStylesTests
```

Expected: compilation fails because
`MaterialControlInteractionFeedback` does not exist. The UI preservation
assertion is not expected to fail before the new scale exists; its purpose is
to reject a modifier-order regression introduced by this task.

- [ ] **Step 4: Implement the minimal shared policy**

Add:

```swift
enum MaterialControlInteractionFeedback {
    static func semanticControlOpacity(isEnabled: Bool) -> Double {
        isEnabled ? 1 : 0.46
    }

    static func semanticControlScale(isPressed: Bool) -> CGFloat {
        isPressed ? 0.98 : 1
    }
}
```

In both `MaterialChipStyleBody` and `MaterialButtonStyleBody`, replace the
private pressed-opacity branch with:

```swift
.opacity(
    MaterialControlInteractionFeedback.semanticControlOpacity(
        isEnabled: isEnabled
    )
)
.scaleEffect(
    MaterialControlInteractionFeedback.semanticControlScale(
        isPressed: configuration.isPressed
    )
)
```

Do not move `MaterialChip`'s outer
`.contentShape(.interaction, MaterialChipHitTargetShape())`.

- [ ] **Step 5: Run the focused package tests to verify GREEN**

Run:

```bash
swift test --filter ControlStylesTests
```

Expected: all `ControlStylesTests` pass with no warnings.

- [ ] **Step 6: Perform mutation checks**

Temporarily restore enabled opacity to `0.78`; rerun the focused test and
confirm the opacity assertion fails. Restore `1`, temporarily return scale
`1` while pressed, rerun, and confirm the scale assertion fails. Restore the
approved implementation and rerun to green.

- [ ] **Step 7: Commit the behavior and tests**

```bash
git add ios/Sources/DesignSystem/ControlStyles.swift \
  ios/Tests/DesignSystemTests/ControlStylesTests.swift \
  ios/App/UITests/MakingTracksCoreLoopUITests.swift
git commit -m "Preserve material control contrast while pressed"
```

### Task 2: Verify, review, and update PR #505

**Files:**
- Modify: PR #505 body through GitHub
- Verify: all branch changes

**Interfaces:**
- Consumes: committed Task 1 behavior
- Produces: exact-head host and simulator evidence, adversarial review accounting, Opus handoff

- [ ] **Step 1: Run the host package gate**

Run:

```bash
swift test
```

Expected: the full package suite passes with zero failures.

- [ ] **Step 2: Run the locked release gate**

Run:

```bash
./scripts/sim-lock.sh ./scripts/release-gate.sh
```

Expected: Release build, unit tests, and required simulator checks pass under
the designated lock, including AC29.

- [ ] **Step 3: Run adversarial reviews**

Review the exact committed diff independently for:

- R9 contract and contrast arithmetic.
- Swift implementation coherence and modifier order.
- Test rigor, hit-target preservation, security, privacy, and untrusted-data handling.

Resolve every Critical and Important finding before continuing, then rerun
the affected gates.

- [ ] **Step 4: Push and request Opus review**

Push the exact verified head, send its SHA to Fable through AMQ, and request
the promised Opus review. Hold merge.

- [ ] **Step 5: Update PR #505**

Replace the former comment-only/trivial-exception accounting with:

- R9 provenance and the shared policy design.
- Before/after contrast arithmetic (`3.8801:1` to `6.1330:1`).
- Explicit note that no existing test asserted the deleted `0.78`.
- Exact host, release-gate, adversarial, Opus, and automated review evidence.
- Required labels `sourcery-review`, `track-b-ios`, and `wp`.

- [ ] **Step 6: Verify the published head**

Fetch `origin/ios`, confirm the PR head SHA equals the verified local SHA,
confirm only intended files changed, confirm the worktree is clean, and
monitor required checks. Do not merge.
