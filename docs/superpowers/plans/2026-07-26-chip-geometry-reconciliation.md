# Chip Geometry Reconciliation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore the ratified 22pt chip capsule with 9pt horizontal padding and 4pt icon gap while retaining a real 44pt touch target outside its visual frame.

**Architecture:** Give `MaterialChip` a dedicated chip style so it no longer inherits button geometry. Keep its visual capsule and layout bounds at the ratified size, then expand only SwiftUI's interaction `contentShape`; prove that separation with host rendering tests and an XCUITest that taps outside the rendered capsule.

**Tech Stack:** Swift 6, SwiftUI, XCTest, XCUITest, self-contained HTML/CSS render evidence

## Global Constraints

- The visual capsule is 22pt high at the default content size, with 9pt horizontal padding and a 4pt icon/title gap.
- The interaction target is at least 44pt and must be proved by hit-testing, not a frame assertion.
- Chip title remains 12pt/600 and the SF Symbol remains 11pt.
- General filled, tonal, and quiet button geometry must remain unchanged.
- Before/after renders use a 390×844 canvas; an accessibility-size variant and committed HTML are required.
- Build/test/simulator access goes only through the repository's documented gates and `scripts/sim-lock.sh`.

---

### Task 1: Pin Visual Geometry with a Failing Host Test

**Files:**
- Modify: `ios/Tests/DesignSystemTests/ControlStylesTests.swift`
- Modify: `ios/Sources/DesignSystem/ControlStyles.swift`

**Interfaces:**
- Consumes: `MaterialChip.init(_:systemImage:state:theme:action:)`
- Produces: `MaterialChipGeometry` with `visualHeight`, `horizontalPadding`, `labelSpacing`, `minimumHitTarget`, and `hitOutset`

- [ ] **Step 1: Write host tests that expose the inherited button geometry**

Add a default-size render test that hand-checks a text-only chip at 22pt high and checks that adding an icon widens it by the rendered icon width plus a literal 4pt gap. Add a regression assertion that a normal filled button remains 44pt high.

```swift
func testMaterialChipUsesRatifiedVisualGeometry() throws {
    XCTAssertEqual(
        try renderedHeight(MaterialChip("Saved", state: .active, action: {})),
        22
    )
}

func testMaterialChipUsesRatifiedIconGap() throws {
    let textWidth = try renderedWidth(MaterialChip("Map", state: .active, action: {}))
    let iconWidth = try renderedWidth(
        Image(systemName: "map")
            .font(Typography.font(for: .label).weight(.medium))
    )
    let combinedWidth = try renderedWidth(
        MaterialChip("Map", systemImage: "map", state: .active, action: {})
    )
    XCTAssertEqual(combinedWidth - textWidth, iconWidth + 4, accuracy: 1)
}
```

- [ ] **Step 2: Run the focused host tests and verify RED**

Run:

```bash
cd ios
swift test --filter ControlStylesTests
```

Expected: the chip height reports 44 instead of 22 and the icon delta reports the old 5pt gap.

- [ ] **Step 3: Implement a dedicated chip style**

Add internal geometry values and a private `MaterialChipButtonStyle` that applies:

```swift
configuration.label
    .padding(.horizontal, MaterialChipGeometry.horizontalPadding)
    .frame(minHeight: MaterialChipGeometry.visualHeight)
    .foregroundStyle(appearance.foreground.swiftUIColor)
    .background(
        appearance.background.map { color in
            color.swiftUIColor.opacity(appearance.backgroundOpacity)
        },
        in: Capsule()
    )
    .contentShape(
        .interaction,
        Capsule().inset(by: -MaterialChipGeometry.hitOutset)
    )
```

Change the chip label to `HStack(spacing: MaterialChipGeometry.labelSpacing)`, select filled/tonal appearance in the chip style, and leave all shared button styles untouched.

- [ ] **Step 4: Run focused and full host tests and verify GREEN**

Run:

```bash
cd ios
swift test --filter ControlStylesTests
swift test
```

Expected: all control-style tests pass and the full count is at least the 452-test baseline with zero failures.

- [ ] **Step 5: Commit the visual-geometry cycle**

```bash
git add ios/Sources/DesignSystem/ControlStyles.swift ios/Tests/DesignSystemTests/ControlStylesTests.swift
git commit -m "fix(ios): restore ratified chip geometry"
```

### Task 2: Prove the Extended Target by Actual Hit Testing

**Files:**
- Modify: `ios/App/UITests/MakingTracksCoreLoopUITests.swift`

**Interfaces:**
- Consumes: the chip interaction shape from Task 1 and the seeded `Date night` place-card chip
- Produces: an AC29 UI-test oracle against the chip's real accessibility button

- [ ] **Step 1: Write an XCUITest that taps outside the capsule**

Seed the user list, open the fixture card, find its existing `Date night` button by label, and calculate a screen coordinate 8pt above the chip's reported visual frame:

```swift
let chip = app.buttons["Date night"]
XCTAssertTrue(chip.waitForExistence(timeout: 5))
let outsideVisualCapsule = app.coordinate(
    withNormalizedOffset: CGVector(
        dx: chip.frame.midX / app.frame.width,
        dy: (chip.frame.minY - 8) / app.frame.height
    )
)
outsideVisualCapsule.tap()
XCTAssertTrue(app.navigationBars["Add to list"].waitForExistence(timeout: 5))
```

The production mutation this catches is removal or shrinking of the negative-inset interaction shape; a center tap or frame-height assertion would not catch that break.

- [ ] **Step 2: Run the single UI test against the pre-hit-area implementation and verify RED**

Run the named UI test through the simulator lock:

```bash
./scripts/sim-lock.sh xcodebuild \
  -project ios/App/MakingTracks.xcodeproj \
  -scheme MakingTracks \
  -destination 'platform=iOS Simulator,id=C4A64D49-24A2-4429-B6E2-AD9A14142A99' \
  -only-testing:MakingTracksUITests/MakingTracksCoreLoopUITests/testMaterialChipExtendsHitTargetBeyondVisualCapsule \
  test
```

Expected: failure because the coordinate is outside the current content shape and does not open the picker.

- [ ] **Step 3: Run the single UI test after Task 1 and verify GREEN**

Repeat the locked `xcodebuild` command. Expected: the coordinate outside the 22pt frame opens `Add to list`.

- [ ] **Step 4: Commit the actual hit-testing proof**

```bash
git add ios/App/UITests/MakingTracksCoreLoopUITests.swift
git commit -m "test(ios): prove chip extended hit target"
```

### Task 3: Commit Before/After and Accessibility Render Evidence

**Files:**
- Create: `docs/design/design-system/t1.12-chip-geometry-evidence.html`
- Create: `docs/design/design-system/t1.12-chip-geometry-before.png`
- Create: `docs/design/design-system/t1.12-chip-geometry-after.png`
- Create: `docs/design/design-system/t1.12-chip-geometry-ax.png`
- Modify: `docs/design/design-system/README.md`

**Interfaces:**
- Consumes: the frozen `ia-doors.html` chip geometry and the shipped Snow material tokens
- Produces: query-selectable `before`, `after`, and `ax` 390×844 evidence frames

- [ ] **Step 1: Author one self-contained evidence HTML**

Use `?variant=before|after|ax`; render the same place-card chip row with explicit annotations. The before variant uses `min-height:44px; padding:10px 16px; gap:5px`, the after variant uses `height:22px; padding:0 9px; gap:4px`, and AX uses the after capsule rules with accessibility-scale text and wrapping.

- [ ] **Step 2: Capture exact 390×844 PNGs**

Use the locally available browser screenshot mechanism against each variant, set its viewport to 390×844, and write the three PNGs listed above.

- [ ] **Step 3: Inspect all PNGs**

Open each PNG at original detail. Verify the before/after capsule change is visible, the after geometry matches its ruler annotation, and the AX variant remains legible without clipping.

- [ ] **Step 4: Document the evidence**

Add the T1.12 asset family to the README implementation-evidence table, including the interaction-target caveat: the PNG proves visible geometry while the XCUITest proves the invisible 44pt target.

- [ ] **Step 5: Commit the render evidence**

```bash
git add docs/design/design-system/t1.12-chip-geometry-*
git add docs/design/design-system/README.md
git commit -m "docs(ios): record chip geometry evidence"
```

### Task 4: Gate, Review, and Handoff

**Files:**
- Modify: `docs/superpowers/phases/phase-1/tasks.md`

**Interfaces:**
- Consumes: Tasks 1–3 and the repository review/gate law
- Produces: green gates, clean adversarial reviews, PR #467 linkage, and a ready-to-merge ledger state

- [ ] **Step 1: Run all required verification**

Run:

```bash
cd ios
swift test
cd ..
./scripts/sim-lock.sh ./scripts/release-gate.sh
```

Expected: host tests and the complete locked Release/simulator gate pass with zero warnings or failures.

- [ ] **Step 2: Request mandated independent reviews**

Request the task's Sourcery review and an Opus design review. Also dispatch the repository-required adversarial code/test/security reviews; resolve every actionable finding and rerun the affected gates.

- [ ] **Step 3: Record the final ledger transition**

Update T1.12 through `tests green`, `PR open`, `review clean`, and finally `ready-to-merge`, mirroring each transition over AMQ with exact test counts, review accounting, render paths, and commit hashes.

- [ ] **Step 4: Push and open the PR into `ios`**

Push `wp-467-chip-geometry`, open a PR targeting `ios`, link issue #467, report task/acceptance-criteria coverage, add `sourcery-review`, `track-b-ios`, and `wp`, then verify the PR body and labels.

- [ ] **Step 5: Run the finishing checklist**

Verify the branch is pushed, the worktree is clean, no `.xcresult` bundles remain, all review threads are resolved, and the handoff message includes the PR URL plus the exact gate/review evidence.
