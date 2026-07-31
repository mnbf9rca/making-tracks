# T2.2 Icon Roles and Scaled Quiet-Press Inset Implementation Plan

> **Execution:** Keep this work in `wp-t2-2-impl`. W-1 review findings or a Rob ruling preempt it immediately. Execute inline because the icon-role and button-feedback changes share one DesignSystem contract and one host test gate.

**Goal:** Add the two ratified Explore row icon roles and make the text-only quiet-button press inset scale with the paired button typography role.

**Architecture:** Extend `IconRole` directly so its existing `@ScaledMetric` modifier owns the new sizes and typography anchors. Preserve `ExploreSurfaceIconGeometry` unchanged for the T2.3 and T2.8 consumers. Keep the quiet style's 1-point base inset as its migration input, but scale that input inside `MaterialButtonStyleBody` with `@ScaledMetric` anchored to `TypographyRole.button.specification.textStyle.swiftUI`; feed the resolved value into the existing press-feedback branch. Apple documents that macOS ignores Dynamic Type changes, so the host test injects a simulated iOS-resolved metric through the actual body path and names that limitation; T2.3's mandatory default/AX simulator renders own the device-real `@ScaledMetric` proof.

**Tech Stack:** Swift 6, SwiftUI, XCTest, Swift Package Manager.

---

### Task 1: Prove the five-role icon contract fails before implementation

**Files:**
- Modify: `ios/Tests/DesignSystemTests/IconRoleTests.swift`
- Modify later: `ios/Sources/DesignSystem/Iconography.swift`

- [x] Rename the closure test to describe five ratified roles.
- [x] Add literal contracts for `.rowRaised` at 20 points anchored to `.listRowTitle` and `.rowQuiet` at 18 points anchored to `.button`.
- [x] Add both roles to the real rendered-glyph contract at default and Accessibility 5 Dynamic Type.
- [x] Run `cd ios && swift test --filter IconRoleTests`; confirm the new cases fail to compile because production does not define them.

### Task 2: Implement the two semantic icon roles

**Files:**
- Modify: `ios/Sources/DesignSystem/Iconography.swift`
- Test: `ios/Tests/DesignSystemTests/IconRoleTests.swift`

- [x] Add `rowRaised` and `rowQuiet` to `IconRole`.
- [x] Return 20 and 18 points respectively from `pointSize`.
- [x] Return `.listRowTitle` and `.button` respectively from `typographyRole`.
- [x] Leave `ExploreSurfaceIconGeometry.scopeControl` and `.quietDestination` intact.
- [x] Run `cd ios && swift test --filter IconRoleTests`; confirm the five-case value and rendering contracts pass.

### Task 3: Prove the quiet text inset does not yet scale

**Files:**
- Modify: `ios/Tests/DesignSystemTests/ControlStylesTests.swift`
- Modify later: `ios/Sources/DesignSystem/ControlStyles.swift`

- [x] Reproduce and isolate the macOS limitation: `@ScaledMetric` values remain fixed under both `dynamicTypeSize` and legacy `sizeCategory`, matching Apple's platform documentation.
- [x] Obtain the planner's Route A ruling: inject the resolved metric through the actual body path, name the limitation, and assign device-real proof to T2.3.
- [x] Extend the real rendering helper with `DynamicTypeSize` and optional resolved-metric inputs.
- [x] Preserve the assertions that default-size press moves down by one point, disabled press is inert, and press scale still composes.
- [x] Assert that the actual body renders a simulated AX resolved inset at three points, greater than the default one-point displacement.
- [x] Run the focused test first; confirm RED because `MaterialButtonStyleBody` does not yet accept the resolved metric.

### Task 4: Scale the migrated inset at the consumer

**Files:**
- Modify: `ios/Sources/DesignSystem/ControlStyles.swift`
- Test: `ios/Tests/DesignSystemTests/ControlStylesTests.swift`

- [x] Keep `.textInset(points: 1)` as the style's base migration input.
- [x] Change `verticalOffset` to accept the resolved scaled inset and use it only for the enabled, pressed `.textInset` case.
- [x] Add a body-local `@ScaledMetric` initialized from the feedback's base inset and anchored to `TypographyRole.button.specification.textStyle.swiftUI` (`.subheadline`).
- [x] Pass the resolved metric into `verticalOffset`; keep scale and symbol-weight behavior unchanged.
- [x] Add the optional host-test seam while production callers continue to use the body-local metric.
- [x] Update the direct feedback unit assertions for the new resolved-value argument.
- [x] Run the focused quiet-inset test, then all `ControlStylesTests`; confirm green.

### Task 5: Verify, review, and publish

**Files:**
- Modify: `docs/superpowers/phases/phase-2/tasks.md`
- Modify: `docs/superpowers/plans/2026-07-31-t2-2-icon-role-scaled-inset.md`

- [x] Run `cd ios && swift test`; require all tests to pass.
- [x] Confirm `ios/Package.resolved` is unchanged; restore only resolver-generated pin drift if necessary.
- [x] Inspect the diff for T2.2 scope, warnings-as-errors hazards, and preservation of the T2.3/T2.8 geometry constants.
- [ ] Update the T2.2 ledger row with exact test evidence and head.
- [ ] Commit and push the exact reviewed head.
- [ ] Request the ratified Sourcery plus reviewer review tier over AMQ.
- [ ] Open a draft PR into `ios` and verify `track-b-ios`, `wp`, and `sourcery-review` labels.
