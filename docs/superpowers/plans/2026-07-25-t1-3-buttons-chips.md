# T1.3 Buttons and Chips Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the three ratified token-backed button styles and one accessible active/available chip family to `DesignSystem`.

**Architecture:** Three public `ButtonStyle` types expose the only supported button tones. A shared internal appearance resolver maps those types and `MaterialChipState` onto `MaterialTheme` tokens, so tests exercise the same values the SwiftUI bodies consume. `MaterialChip` owns its capsule rendering and accessibility state while accepting only SF Symbol names for optional icons.

**Tech Stack:** Swift 6, SwiftUI, XCTest, static HTML/CSS rendered with headless Chrome.

## Global Constraints

- Target iOS 18+ and macOS 14+ through the existing Swift package.
- Consume `MaterialTheme.snow.tokens`; add no colour or font literal outside `DesignSystem`.
- Buttons are exactly filled, tonal, and quiet; tonal uses 12% accent.
- Chips expose exactly `active` and `available`; active is filled and available is tonal.
- SF Symbols are monochrome at `.medium` weight.
- Disabled controls expose `Unavailable` as an accessibility value; chips expose `Selected` or `Not selected` while enabled.
- Dynamic Type may expand vertically; no fixed height may clip at AX5.
- Do not modify app surfaces or `ios/App/project.yml`.

---

### Task 1: Pin the component contract with failing host tests

**Files:**
- Create: `ios/Tests/DesignSystemTests/ControlStylesTests.swift`
- Create: `ios/Sources/DesignSystem/ControlStyles.swift`

**Interfaces:**
- Consumes: `MaterialTheme`, `MaterialTokenSheet`, and `MaterialColor` from T1.1.
- Produces: `MaterialFilledButtonStyle`, `MaterialTonalButtonStyle`, `MaterialQuietButtonStyle`, `MaterialChipState`, and `MaterialChip`.

- [ ] **Step 1: Write failing semantic-palette tests**

Add tests that instantiate the wished-for styles and assert that their shared appearances resolve independently derived Snow values:

```swift
XCTAssertEqual(MaterialFilledButtonStyle().appearance.foreground, color(0xFB, 0xFA, 0xF2))
XCTAssertEqual(MaterialFilledButtonStyle().appearance.background, color(0x0A, 0x6B, 0x5C))
XCTAssertEqual(MaterialTonalButtonStyle().appearance.backgroundOpacity, 0.12)
XCTAssertEqual(MaterialQuietButtonStyle().appearance.foreground, color(0x6B, 0x67, 0x5F))
```

The production break caught is a button tone reading the wrong semantic token or tonal opacity.

- [ ] **Step 2: Write failing chip-state and accessibility tests**

Assert `.active` resolves to the filled palette, `.available` resolves to the tonal palette, enabled states return `Selected` / `Not selected`, and disabled controls return `Unavailable`.

The production break caught is an inverted chip state or a visually disabled control with no spoken state.

- [ ] **Step 3: Run focused tests and verify RED**

Run:

```bash
cd ios && swift test --filter ControlStylesTests
```

Expected: compilation fails because the five public API symbols do not exist.

- [ ] **Step 4: Add the minimal public declarations and shared appearance resolver**

Create the five public API symbols with exact names and signatures:

```swift
public struct MaterialFilledButtonStyle: ButtonStyle
public struct MaterialTonalButtonStyle: ButtonStyle
public struct MaterialQuietButtonStyle: ButtonStyle
public enum MaterialChipState: Sendable { case active, available }
public struct MaterialChip: View
```

Each style takes `theme: MaterialTheme = .snow`. `MaterialChip` takes a verbatim title, optional `systemImage`, state, and action.

- [ ] **Step 5: Run focused tests and verify GREEN**

Run:

```bash
cd ios && swift test --filter ControlStylesTests
```

Expected: all `ControlStylesTests` pass with zero failures.

### Task 2: Finish SwiftUI rendering and visual evidence

**Files:**
- Modify: `ios/Sources/DesignSystem/ControlStyles.swift`
- Modify: `ios/Tests/DesignSystemTests/ControlStylesTests.swift`
- Create: `docs/design/design-system/t1.3-buttons-chips.html`
- Create: `docs/design/design-system/t1.3-buttons-chips.png`
- Create: `docs/design/design-system/t1.3-buttons-chips-ax.html`
- Create: `docs/design/design-system/t1.3-buttons-chips-ax.png`

**Interfaces:**
- Consumes: Task 1's exact public names and state cases.
- Produces: the stable API consumed by T1.6, T1.7, T1.8, T1.9, and T1.10.

- [ ] **Step 1: Implement the minimal control bodies**

Apply token foreground/background values, capsule shapes, unfixed vertical padding, monochrome SF Symbols, `.medium` symbol weight, press feedback without animation, and conditional accessibility values.

- [ ] **Step 2: Run focused tests**

Run:

```bash
cd ios && swift test --filter ControlStylesTests
```

Expected: all focused tests pass with zero warnings and zero failures.

- [ ] **Step 3: Author the two required HTML renders**

The 390×844 render shows filled, tonal, quiet, disabled, active-chip, and available-chip states. The AX render uses accessibility-size typography and demonstrates multiline buttons/chips expanding rather than clipping.

- [ ] **Step 4: Render PNGs and inspect them**

Use headless Chrome with a dedicated `/private/tmp/chrome-t1-3-*` profile and `--window-size=390,844`, then inspect both PNGs at original resolution.

- [ ] **Step 5: Run the full host gate**

Run:

```bash
cd ios && swift test
```

Expected: 397 baseline tests plus the new T1.3 tests, all passing with zero failures.

- [ ] **Step 6: Prove test teeth**

Temporarily invert one chip mapping and remove the disabled accessibility value, confirm the focused suite fails for both mutations, restore the implementation, and re-run green.

- [ ] **Step 7: Commit**

Stage only the T1.3 source, tests, plan, renders, and ledger, then commit with an imperative plain message.
