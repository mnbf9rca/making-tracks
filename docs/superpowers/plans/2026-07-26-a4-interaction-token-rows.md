# A4 Interaction Token Rows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the ratified `disabledAlpha` and `pressScale` values real `MaterialTokenSheet` rows and migrate every in-scope interaction consumer away from hardcoded copies.

**Architecture:** `MaterialTokenSheet` owns the two non-colour scalar rows for each material. `MaterialControlInteractionFeedback` receives the selected sheet explicitly, and both DesignSystem style bodies pass their theme’s sheet through that seam. App-local semantic-tone and pending-action controls read the same sheet rows without expanding the public interaction-policy API.

**Tech Stack:** Swift 6, SwiftUI, Swift Package Manager, XCTest

## Global Constraints

- `disabledAlpha` is exactly `0.46`; `pressScale` is exactly `0.98`.
- The existing enabled/resting values remain exactly `1`.
- `MaterialControlInteractionFeedback` must read the supplied sheet; a custom sheet with mutated interaction rows must change its returned disabled opacity and pressed scale.
- Keep the existing independent rendered-pixel and geometry tests green; they are the behavioral teeth for the ratified values.
- Migrate the duplicate interaction literals in `PlaceCardActionAppearance` and the pending-disabled action in `ManagedPlacesView`.
- Do not change the unrelated `coverageMaskFillOpacity = 0.46` in `MakingTracksMapStyle/PaperStyle.swift`.
- Do not change the unrelated XCUITest normalized coordinate `0.98`.
- Preserve enabled, disabled, pressed, accessibility, and hit-target behavior exactly; this task changes ownership of values, not appearance.
- No `project.yml` change, no new dependency, and no render packet because the resulting pixels and geometry are unchanged.
- Serve issue #526 and amendment task A4; target `ios`.

---

### Task 1: Ratify interaction rows and migrate their consumers

**Files:**
- Modify: `ios/Sources/DesignSystem/MaterialTokens.swift:117-246`
- Modify: `ios/Sources/DesignSystem/ControlStyles.swift:33-451`
- Modify: `ios/Tests/DesignSystemTests/MaterialTokensTests.swift:8-221`
- Modify: `ios/Tests/DesignSystemTests/ControlStylesTests.swift:10-36,573-604`
- Modify: `ios/App/Sources/PlaceCard/PlaceCardSheet.swift:38-78,93-100,155-179`
- Modify: `ios/App/Tests/AppShellTests.swift:60-96`
- Modify: `ios/App/Sources/Map/ManagedPlacesView.swift:287-306`

**Interfaces:**
- Produces: `MaterialTokenSheet.disabledAlpha: Double`
- Produces: `MaterialTokenSheet.pressScale: CGFloat`
- Changes: `MaterialControlInteractionFeedback.semanticControlOpacity(isEnabled:tokens:) -> Double`
- Changes: `MaterialControlInteractionFeedback.semanticControlScale(isPressed:tokens:) -> CGFloat`
- Consumes: the existing `MaterialTheme.tokens` selection at every style body and app call site

- [ ] **Step 1: Write the failing sheet and seam tests**

In `MaterialTokensTests`, add a ratified-row assertion:

```swift
func testSnowMatchesRatifiedInteractionRows() {
    let sheet = MaterialTheme.snow.tokens

    XCTAssertEqual(sheet.disabledAlpha, 0.46)
    XCTAssertEqual(sheet.pressScale, 0.98)
}
```

In `ControlStylesTests`, change the existing feedback calls to pass
`tokens: MaterialTheme.snow.tokens`, then add:

```swift
func testMaterialControlInteractionFeedbackReadsTheProvidedSheetRows() {
    let sheet = makeInteractionSheet(
        disabledAlpha: 0.23,
        pressScale: 0.87
    )

    XCTAssertEqual(
        MaterialControlInteractionFeedback.semanticControlOpacity(
            isEnabled: false,
            tokens: sheet
        ),
        0.23
    )
    XCTAssertEqual(
        MaterialControlInteractionFeedback.semanticControlScale(
            isPressed: true,
            tokens: sheet
        ),
        0.87
    )
}
```

Add a private `makeInteractionSheet(disabledAlpha:pressScale:)` test fixture
that copies every colour row from `MaterialTheme.snow.tokens` into the
internal `MaterialTokenSheet` initializer and overrides only these two scalar
rows. The break this test catches is replacing either seam lookup with a
literal; the hand-written `0.23` and `0.87` expectations are independent of
production values.

- [ ] **Step 2: Run the tests and verify RED**

Run:

```bash
swift test --package-path ios --filter 'MaterialTokensTests|ControlStylesTests'
```

Expected: compilation fails because `MaterialTokenSheet` has no
`disabledAlpha`/`pressScale` rows and the feedback methods do not accept
`tokens:`.

- [ ] **Step 3: Add the two scalar rows to the material sheet**

In `MaterialTokens.swift`:

```swift
public let disabledAlpha: Double
public let pressScale: CGFloat
```

Add matching initializer parameters and assignments. Set the Snow sheet to:

```swift
disabledAlpha: 0.46,
pressScale: 0.98
```

Update every test-only `MaterialTokenSheet` construction with the two new
arguments.

- [ ] **Step 4: Make DesignSystem feedback token-explicit**

Change the seam to:

```swift
enum MaterialControlInteractionFeedback {
    static func semanticControlOpacity(
        isEnabled: Bool,
        tokens: MaterialTokenSheet
    ) -> Double {
        isEnabled ? 1 : tokens.disabledAlpha
    }

    static func semanticControlScale(
        isPressed: Bool,
        tokens: MaterialTokenSheet
    ) -> CGFloat {
        isPressed ? tokens.pressScale : 1
    }
}
```

Pass the selected `theme.tokens` into `MaterialButtonStyleBody` and
`MaterialChipStyleBody`, including the test render helpers, and supply that
sheet to both seam calls. Do not move hit-target or `contentShape` modifiers.

- [ ] **Step 5: Migrate app-local interaction consumers**

Keep `PlaceCardActionAppearance`’s existing tested helpers, but add a
`tokens: MaterialTokenSheet` parameter and replace their literals:

```swift
static func semanticControlOpacity(
    isEnabled: Bool,
    tokens: MaterialTokenSheet
) -> Double {
    isEnabled ? 1 : tokens.disabledAlpha
}

static func semanticControlScale(
    isPressed: Bool,
    tokens: MaterialTokenSheet
) -> CGFloat {
    isPressed ? tokens.pressScale : 1
}
```

Give `PlaceCardSemanticToneButtonStyle` the selected token sheet and pass it
to those helpers. Update `AppShellTests` to pass
`MaterialTheme.snow.tokens`.

In `ManagedPlacesView`, keep the pending-state branch and replace only its
literal:

```swift
.opacity(
    state.isPending(placeID: place.placeID)
        ? tokens.disabledAlpha
        : 1
)
```

- [ ] **Step 6: Run focused tests and verify GREEN**

Run:

```bash
swift test --package-path ios --filter 'MaterialTokensTests|ControlStylesTests'
```

Expected: all selected tests pass, including the custom-sheet wiring test and
the existing independent pixel/geometry tests.

- [ ] **Step 7: Run the complete host suite**

Run:

```bash
swift test --package-path ios
```

Expected: all host tests pass with zero failures. Restore generated
`ios/Package.resolved` noise before committing.

- [ ] **Step 8: Prove test teeth**

Temporarily replace `tokens.disabledAlpha` with `0.46` and
`tokens.pressScale` with `0.98` inside
`MaterialControlInteractionFeedback`. Re-run:

```bash
swift test --package-path ios --filter ControlStylesTests.testMaterialControlInteractionFeedbackReadsTheProvidedSheetRows
```

Expected: the custom-sheet wiring test fails for both independent mutated
values. Restore the token lookups and rerun the same test to green.

- [ ] **Step 9: Commit the implementation**

Stage only the files named by this task, inspect the staged diff, then create
a signed commit:

```bash
git commit -S -m "Ratify material interaction token rows"
```

Record exact focused/full test counts, the RED failure, and the teeth
failure/restored-green evidence in the task report.
