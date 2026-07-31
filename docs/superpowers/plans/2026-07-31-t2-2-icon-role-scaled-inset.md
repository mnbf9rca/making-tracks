# T2.2 Icon Roles and Scaled Quiet-Press Inset Implementation Plan

> **Execution:** Keep this work in `wp-t2-2-impl`. W-1 review findings or a Rob ruling preempt it immediately. Execute inline because the icon-role and button-feedback changes share one DesignSystem contract and one host test gate.

**Goal:** Add the two ratified Explore row icon roles and make the text-only quiet-button press inset scale with the paired button typography role.

**Architecture:** Extend `IconRole` directly so its existing `@ScaledMetric` modifier owns the new sizes and typography anchors. Preserve `ExploreSurfaceIconGeometry` unchanged for the T2.3 and T2.8 consumers. Keep the quiet style's 1-point base inset as its migration input, but scale that input inside `MaterialButtonStyleBody` with `@ScaledMetric` anchored to `TypographyRole.button.specification.textStyle.swiftUI`; feed the resolved value into the existing press-feedback branch.

**Tech Stack:** Swift 6, SwiftUI, XCTest, Swift Package Manager.

---

### Task 1: Prove the five-role icon contract fails before implementation

**Files:**
- Modify: `ios/Tests/DesignSystemTests/IconRoleTests.swift`
- Modify later: `ios/Sources/DesignSystem/Iconography.swift`

- [ ] Rename the closure test to describe five ratified roles.
- [ ] Add literal contracts for `.rowRaised` at 20 points anchored to `.listRowTitle` and `.rowQuiet` at 18 points anchored to `.button`.
- [ ] Add both roles to the real rendered-glyph contract at default and Accessibility 5 Dynamic Type.
- [ ] Run `cd ios && swift test --filter IconRoleTests`; confirm the new cases fail to compile because production does not define them.

### Task 2: Implement the two semantic icon roles

**Files:**
- Modify: `ios/Sources/DesignSystem/Iconography.swift`
- Test: `ios/Tests/DesignSystemTests/IconRoleTests.swift`

- [ ] Add `rowRaised` and `rowQuiet` to `IconRole`.
- [ ] Return 20 and 18 points respectively from `pointSize`.
- [ ] Return `.listRowTitle` and `.button` respectively from `typographyRole`.
- [ ] Leave `ExploreSurfaceIconGeometry.scopeControl` and `.quietDestination` intact.
- [ ] Run `cd ios && swift test --filter IconRoleTests`; confirm the five-case value and rendering contracts pass.

### Task 3: Prove the quiet text inset does not yet scale

**Files:**
- Modify: `ios/Tests/DesignSystemTests/ControlStylesTests.swift`
- Modify later: `ios/Sources/DesignSystem/ControlStyles.swift`

- [ ] Extend the real rendering helper with a `DynamicTypeSize` input and apply it through the environment.
- [ ] Re-point `testQuietTextOnlyBodyAddsRuledInsetToPressScale` so it renders unscaled resting and pressed bodies at `.large` and `.accessibility5`.
- [ ] Preserve the assertions that default-size press moves down by one point, disabled press is inert, and press scale still composes.
- [ ] Add a literal behavioral assertion that the Accessibility 5 pressed/resting displacement is greater than the default one-point displacement.
- [ ] Run `cd ios && swift test --filter ControlStylesTests/testQuietTextOnlyBodyAddsRuledInsetToPressScale`; confirm it fails because both Dynamic Type sizes still render a one-point displacement.

### Task 4: Scale the migrated inset at the consumer

**Files:**
- Modify: `ios/Sources/DesignSystem/ControlStyles.swift`
- Test: `ios/Tests/DesignSystemTests/ControlStylesTests.swift`

- [ ] Keep `.textInset(points: 1)` as the style's base migration input.
- [ ] Change `verticalOffset` to accept the resolved scaled inset and use it only for the enabled, pressed `.textInset` case.
- [ ] Add a body-local `@ScaledMetric` initialized from the feedback's base inset and anchored to `TypographyRole.button.specification.textStyle.swiftUI` (`.subheadline`).
- [ ] Pass the resolved metric into `verticalOffset`; keep scale and symbol-weight behavior unchanged.
- [ ] Update the direct feedback unit assertions for the new resolved-value argument.
- [ ] Run the focused quiet-inset test, then all `ControlStylesTests`; confirm green.

### Task 5: Verify, review, and publish

**Files:**
- Modify: `docs/superpowers/phases/phase-2/tasks.md`
- Modify: `docs/superpowers/plans/2026-07-31-t2-2-icon-role-scaled-inset.md`

- [ ] Run `cd ios && swift test`; require all tests to pass.
- [ ] Confirm `ios/Package.resolved` is unchanged; restore only resolver-generated pin drift if necessary.
- [ ] Inspect the diff for T2.2 scope, warnings-as-errors hazards, and preservation of the T2.3/T2.8 geometry constants.
- [ ] Update the T2.2 ledger row with exact test evidence and head.
- [ ] Commit and push the exact reviewed head.
- [ ] Request the ratified Sourcery plus reviewer review tier over AMQ.
- [ ] Open a draft PR into `ios` and verify `track-b-ios`, `wp`, and `sourcery-review` labels.
