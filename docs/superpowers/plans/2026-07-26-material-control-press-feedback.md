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

- [x] **Step 1: Write the failing package policy tests**

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

- [x] **Step 2: Extend AC29 before changing production code**

In `testMaterialChipExtendsHitTargetBeyondVisualCapsule`, use an
`XCUICoordinate` at the top 11pt outset edge and call:

```swift
coordinate(at: topOutsideVisualCapsule).press(forDuration: 0.2)
XCTAssertTrue(waitForActivationCount("1"))
```

Keep the bottom-edge tap and its second activation assertion. This preserves
the existing edge check while exercising the pressed lifecycle.

- [x] **Step 3: Run the focused package tests to verify RED**

Run:

```bash
swift test --filter ControlStylesTests
```

Expected: compilation fails because
`MaterialControlInteractionFeedback` does not exist. The UI assertion covers
the pressed lifecycle and edge activation only. Modifier order is protected
by code structure and adversarial review, not by AC29.

- [x] **Step 4: Implement the minimal shared policy**

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

Expose both `MaterialChipStyleBody` and `MaterialButtonStyleBody` as narrow
internal generic views accepting an explicit `label` and `isPressed`. Each
production `ButtonStyle.makeBody` forwards `configuration.label` and
`configuration.isPressed`. In both bodies, replace the private
pressed-opacity branch with:

```swift
.opacity(
    MaterialControlInteractionFeedback.semanticControlOpacity(
        isEnabled: isEnabled
    )
)
.scaleEffect(
    MaterialControlInteractionFeedback.semanticControlScale(
        isPressed: isPressed
    )
)
```

Do not move `MaterialChip`'s outer
`.contentShape(.interaction, MaterialChipHitTargetShape())`.
In `MaterialButtonStyleBody`, apply `.scaleEffect` before
`.contentShape(Capsule())` so the content shape is established around the
scaled visual result.

- [x] **Step 5: Run the focused package tests to verify GREEN**

Run:

```bash
swift test --filter ControlStylesTests
```

Expected: all `ControlStylesTests` pass with no warnings.

- [x] **Step 6: Perform mutation checks**

Temporarily restore enabled opacity to `0.78`; rerun the focused test and
confirm the opacity assertion fails. Restore `1`, temporarily return scale
`1` while pressed, rerun, and confirm the scale assertion fails. The final
review fix repeats both mutations locally in each style body against rendered
pixels and geometry. Restore the approved implementation and rerun to green.

- [x] **Step 7: Commit the behavior and tests**

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

- [x] **Step 1: Run the host package gate**

Run:

```bash
swift test
```

Expected: the full package suite passes with zero failures.

- [x] **Step 2: Run the locked release gate**

Run:

```bash
./scripts/sim-lock.sh ./scripts/release-gate.sh
```

Expected: Release build, unit tests, and required simulator checks pass under
the designated lock, including AC29.

- [x] **Step 3: Run adversarial reviews**

Review the exact committed diff independently for:

- R9 contract and contrast arithmetic.
- Swift implementation coherence and modifier order.
- Test rigor, hit-target preservation, security, privacy, and untrusted-data handling.

Resolve every Critical and Important finding before continuing, then rerun
the affected gates.

- [x] **Step 4: Push and request Opus review**

Push the exact verified head, send its SHA to Fable through AMQ, and request
the promised Opus review. Hold merge.

- [x] **Step 5: Update PR #505**

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

The former published head was verified at `81999ff7`. Monitoring and
exact-head verification remain open because the controller, not this fix
task, will push the final-review commit and update the live PR.
