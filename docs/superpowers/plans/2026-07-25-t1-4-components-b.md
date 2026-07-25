# T1.4 Component Styles B Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the ratified sheet, row, toast/pill, and progress component contracts to `DesignSystem` without migrating any app call site.

**Architecture:** Three focused SwiftUI source files own the public contracts: sheet/row containers, the adaptive toast family, and progress. Each view consumes `MaterialTheme` tokens and uses an internal semantic presentation resolver that is also exercised by host tests, so tests pin the values and branches the rendered view actually consumes rather than duplicating them.

**Tech Stack:** Swift 6, SwiftUI, XCTest, static HTML/CSS rendered with headless Chrome.

## Global Constraints

- Target the existing package floors: iOS 18+ and macOS 14+.
- Consume `MaterialTheme.snow.tokens`; do not add a colour literal outside `DesignSystem`.
- Expose one sheet pattern, exactly two row containers, one toast/pill family, and one progress component.
- The sheet owns its grabber, 22pt top radius, medium/large detents, solid `surface` background, and one close affordance.
- The toast family uses one normal blur recipe and switches to solid `surface` when Reduce Transparency is enabled.
- Determinate progress always renders count text; only indeterminate progress may be a bare hairline.
- Do not modify the four existing toast/pill call sites; adoption is T1.7.
- Do not modify `ios/App/project.yml`; this task remains host-only.
- Ship 390×844 default and AX renders with their HTML sources.

---

### Task 1: Sheet and row contracts

**Files:**
- Create: `ios/Tests/DesignSystemTests/MaterialSheetRowsTests.swift`
- Create: `ios/Sources/DesignSystem/MaterialSheetRows.swift`

**Interfaces:**
- Consumes: `MaterialTheme`, `MaterialTokenSheet`, and `MaterialColor`.
- Produces: `MaterialSheet<Content>`, `MaterialRaisedCardRow<Content>`, and `MaterialHairlineRow<Content>`.

- [ ] **Step 1: Write failing sheet tests**

Write tests against the wished-for public views and their internal resolved appearances:

```swift
@MainActor
func testSheetOwnsTheSingleRatifiedPresentation() {
    let appearance = MaterialSheet { EmptyView() }.appearance

    XCTAssertEqual(appearance.background, .solid(color(0xFB, 0xFA, 0xF2)))
    XCTAssertEqual(appearance.topCornerRadius, 22)
    XCTAssertEqual(appearance.detents, [.medium, .large])
    XCTAssertEqual(appearance.closeAccessibilityLabel, "Close")
}
```

The production breaks caught are a sheet returning to mixed materials, the wrong token, a drifting radius/detent set, or divergent close affordances.

- [ ] **Step 2: Write failing row tests**

Assert that `MaterialRaisedCardRow` resolves `surfaceRaised` plus a 14pt radius and no divider, while `MaterialHairlineRow` resolves no raised background and a `hairline` divider. The view bodies must read the same appearance properties.

- [ ] **Step 3: Verify RED**

Run:

```bash
cd ios && swift test --filter MaterialSheetRowsTests
```

Expected: compilation fails because the three public component symbols do not exist.

- [ ] **Step 4: Implement the minimal sheet and rows**

Create:

```swift
public struct MaterialSheet<Content: View>: View
public struct MaterialRaisedCardRow<Content: View>: View
public struct MaterialHairlineRow<Content: View>: View
```

Each initializer accepts `theme: MaterialTheme = .snow` and a `@ViewBuilder` content closure. `MaterialSheet` uses `@Environment(\.dismiss)`, always renders the same xmark close button with accessibility label `Close`, hides the system drag indicator in favour of its own grabber, applies `[.medium, .large]`, and uses the token-backed solid background. Rows remain generic so T1.2 typography can be applied by consumers without creating a dependency here.

- [ ] **Step 5: Verify GREEN**

Run:

```bash
cd ios && swift test --filter MaterialSheetRowsTests
```

Expected: all focused tests pass with zero failures.

### Task 2: Adaptive toast/pill family

**Files:**
- Create: `ios/Tests/DesignSystemTests/MaterialToastTests.swift`
- Create: `ios/Sources/DesignSystem/MaterialToast.swift`

**Interfaces:**
- Consumes: `MaterialTheme.tokens.surface`, `.ink`, `.accent`, and `.hairline`.
- Produces: `MaterialToastAction`, `MaterialToastSurfaceAction`, and `MaterialToast`.

- [ ] **Step 1: Write failing content-shape tests**

Instantiate the family in all required forms and assert its internal content mode:

```swift
XCTAssertEqual(MaterialToast(message: "Location is off").contentMode, .messageOnly)
XCTAssertEqual(
    MaterialToast(
        message: "Download 42%",
        primaryAction: MaterialToastAction("Open") {}
    ).contentMode,
    .messageAndAction
)
XCTAssertEqual(
    MaterialToast(
        message: "You're near a place",
        primaryAction: MaterialToastAction("Seen it") {},
        dismissAction: {}
    ).contentMode,
    .messageActionAndDismiss
)
```

The production break caught is a family that cannot express one of the four existing call-site shapes without a bespoke wrapper.

- [ ] **Step 2: Write failing transparency and action tests**

Assert the independently derived Snow foreground/action tokens. Assert `appearance(reduceTransparency: false)` uses the single regular-material recipe and `appearance(reduceTransparency: true)` uses solid Snow `surface`. Invoke `MaterialToastAction.perform()` and assert the real closure fires once. Assert built-in and dismiss controls retain identifiers and a component-owned 44×44pt minimum target. Caller-built styled or representable controls retain their own interaction semantics and identifier, and their adopting task owns proof of their 44×44pt target. Assert the default dismiss accessibility label is `Dismiss` and a caller can make it context-specific. Pin the closed whole-surface action's label, hint, identifier, progress accessibility value, single invocation, and component-owned minimum height.

- [ ] **Step 3: Verify RED**

Run:

```bash
cd ios && swift test --filter MaterialToastTests
```

Expected: compilation fails because `MaterialToastAction` and `MaterialToast` do not exist.

- [ ] **Step 4: Implement the minimal toast family**

Create:

```swift
public struct MaterialToastAction
public struct MaterialToastSurfaceAction
public struct MaterialToast: View
```

`MaterialToast` accepts a verbatim message, optional primary action, optional dismiss action, a dismiss accessibility label defaulting to `Dismiss`, and `theme: MaterialTheme = .snow`. Built-in controls own a tested 44pt target. Control-based initializers also accept caller-built styled/representable action content; because an opaque child owns its action, that child must own its 44pt hit region and the adopting task must prove it. A separate closed whole-surface initializer accepts only `MaterialToastSurfaceAction`, an optional leading SF Symbol name, and optional `MaterialProgressState`; it renders a real outer `Button`, owns its minimum target, and cannot represent nested controls. Use `ViewThatFits(in: .horizontal)` to select an HStack at normal sizes and a VStack fallback at AX sizes. Use one rounded family shape, the same padding and stroke in every mode, and `@Environment(\.accessibilityReduceTransparency)` to select the tested backdrop. Do not depend on T1.3's button-style symbols; T1.7 injects them through the caller-built control path.

- [ ] **Step 5: Verify GREEN**

Run:

```bash
cd ios && swift test --filter MaterialToastTests
```

Expected: all focused tests pass with zero failures.

### Task 3: Count-carrying progress

**Files:**
- Create: `ios/Tests/DesignSystemTests/MaterialProgressTests.swift`
- Create: `ios/Sources/DesignSystem/MaterialProgress.swift`

**Interfaces:**
- Consumes: `MaterialTheme.tokens.accent`, `.hairline`, and `.muted`.
- Produces: `MaterialProgressState` and `MaterialProgress`.

- [ ] **Step 1: Write failing state tests**

Pin all three consumer shapes:

```swift
XCTAssertEqual(
    MaterialProgressState.count(completed: 3, total: 8).presentation,
    .init(fraction: 0.375, visibleCount: "3 of 8", accessibilityValue: "3 of 8")
)
XCTAssertEqual(
    MaterialProgressState.percentage(42).presentation,
    .init(fraction: 0.42, visibleCount: "42%", accessibilityValue: "42%")
)
XCTAssertEqual(
    MaterialProgressState.indeterminate.presentation,
    .init(fraction: nil, visibleCount: nil, accessibilityValue: "In progress")
)
```

Also assert counts and percentages clamp safely: `count(completed: 12, total: 8)` becomes `8 of 8`; negative values become zero; percentage values clamp to `0...100`; a non-positive total becomes `0 of 0`.

The production breaks caught are a determinate bar with no visible count, overflow/underflow geometry, or a bare indicator with no spoken state.

- [ ] **Step 2: Write failing token test**

Assert the view's appearance uses Snow `accent` for fill, Snow `hairline` for track, Snow `muted` for count, and a 3pt bar height. These are hand-derived from the ratified spec and token table.

- [ ] **Step 3: Verify RED**

Run:

```bash
cd ios && swift test --filter MaterialProgressTests
```

Expected: compilation fails because `MaterialProgressState` and `MaterialProgress` do not exist.

- [ ] **Step 4: Implement the minimal progress component**

Create:

```swift
public enum MaterialProgressState: Hashable, Sendable {
    case count(completed: Int, total: Int, suffix: String? = nil)
    case percentage(Int)
    case indeterminate
}

public struct MaterialProgress<LeadingHeader: View>: View
```

`MaterialProgress` accepts its state, an accessibility label, and `theme: MaterialTheme = .snow`; the `EmptyView` convenience retains the `Progress` default. Count states alone can own a semantic suffix such as `seen`, applied after clamping to both visible and spoken values. A typed leading-header initializer lets T1.8 supply its later typography-styled title while the component still owns the trailing count. Its `ViewThatFits` header keeps the count intrinsic in the normal HStack and falls back to a VStack at AX sizes. Render a 3pt accent fill on the hairline track. Count and percentage states always render their derived visible text. The indeterminate state renders a bare static accent segment and speaks `In progress`; introducing animation is out of scope and therefore introduces no new Reduced Motion obligation.

- [ ] **Step 5: Verify GREEN**

Run:

```bash
cd ios && swift test --filter MaterialProgressTests
```

Expected: all focused tests pass with zero failures.

### Task 4: Visual evidence and full verification

**Files:**
- Create: `docs/design/design-system/t1.4-components-b.html`
- Create: `docs/design/design-system/t1.4-components-b.png`
- Create: `docs/design/design-system/t1.4-components-b-ax.html`
- Create: `docs/design/design-system/t1.4-components-b-ax.png`

**Interfaces:**
- Consumes: Tasks 1–3's exact component states and the frozen Snow material.
- Produces: reviewable evidence at the ruled 390×844 canvas and its AX variant.

- [ ] **Step 1: Author the default render**

Show one sheet with grabber and close affordance, both row types, all three toast shapes, counted list progress, percentage download progress, and the bare map-fetch hairline. Use the exact Snow token values and component radii from production.

- [ ] **Step 2: Author the AX render**

Use accessibility-sized text, deliberately long content, stacked toast actions, multiline rows, and unchanged 390×844 width to prove the components grow vertically without fixed-height clipping.

- [ ] **Step 3: Render both PNGs**

Use headless Chrome with `--force-device-scale-factor=1`, `--hide-scrollbars`, dedicated `/private/tmp/chrome-t1-4-*` profiles, `--window-size=390,844`, and `file://` URLs rooted at the worktree.

- [ ] **Step 4: Inspect both PNGs**

View the images at original resolution. Confirm dimensions are exactly 390×844, every required state is visible, the fold is marked, and AX content neither clips nor escapes the canvas.

- [ ] **Step 5: Run focused and full host tests**

Run:

```bash
cd ios && swift test --filter 'Material(SheetRows|Toast|Progress)Tests'
cd ios && swift test
```

Expected: all new focused tests and the 397-test baseline plus new tests pass with zero failures.

- [ ] **Step 6: Prove test teeth**

One mutation at a time: change the sheet background away from `surface`; bypass the Reduce Transparency toast branch; remove progress count text. Confirm the corresponding focused test fails for each mutation, restore immediately, and rerun green.

- [ ] **Step 7: Commit the implementation**

Stage only the T1.4 source, tests, plan, renders, and ledger. Commit with an imperative plain message and push the verified branch.
