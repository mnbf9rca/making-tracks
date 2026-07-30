# Place Card State Morphology Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every place-card state control report ON with a filled pill and filled glyph, OFF with a tonal pill and outline glyph, while keeping momentary verbs quiet and preserving the A6 action grammar.

**Architecture:** Add the ratified opaque `accentContainer` to the Snow semantic token sheet and add a reusable DesignSystem state-toggle button style for opaque semantic state fills. Keep action presence and order in `PlaceCardActionSlots`; the app owns a small presentation mapping from each existing action plus Saved state to title, SF Symbol, and style.

**Tech Stack:** Swift 6, SwiftUI, XCTest, Swift Package Manager, Xcode 26.5, Making Tracks DesignSystem

## Global Constraints

- Build from `origin/ios` exact base `7e92339ceb38c8c91925d656fe2fbd434c741adb` on `wp-526-place-card-state-morphology`.
- A8's frozen `docs/design/design-system/a8-r15-place-card.png` is the visual authority.
- The assigned codex3 seat renders 402×874pt while A8's design canvas is 390×844; grade morphology, tokens, component geometry, and AA at component level, and grade wrapping/reflow behaviorally on the assigned seat.
- `accentContainer` is designed opaque `#D4EDE9`; accent ink `#0A6B5C` over it must clear the 4.5:1 AA gate.
- ON state is a filled pill plus filled glyph; OFF state is tonal plus outline glyph; state is never communicated by colour alone.
- Seen ON uses `accent`; Loved ON uses `love`; Saved ON uses `accentContainer`.
- State toggles are the R16 fourth component category and sit outside the filled-action budget.
- Hide, Unhide, and `place-card.more` remain quiet momentary verbs.
- Do not change action presence or ordering established by `PlaceCardActionSlots`.
- Preserve every existing `place-card.*` accessibility identifier.
- Preserve the accessibility-size HStack-to-VStack reflow and the 44pt minimum control height.
- Do not touch the designated simulator except through `scripts/sim-lock.sh`.

---

### Task 1: Ratified Saved Container Token

**Files:**
- Modify: `ios/Sources/DesignSystem/MaterialTokens.swift`
- Test: `ios/Tests/DesignSystemTests/MaterialTokensTests.swift`
- Modify: `ios/Tests/DesignSystemTests/ControlStylesTests.swift`
- Modify: `ios/Tests/MakingTracksMapStyleTests/PinLayersTests.swift`

**Interfaces:**
- Consumes: `SemanticColorToken`, `MaterialTokenSheet`, and `MaterialTheme.snow`
- Produces: `SemanticColorToken.accentContainer` and `MaterialTokenSheet.accentContainer: MaterialColor`

- [ ] **Step 1: Write the failing token and contrast tests**

Add the exact Snow token to `testSnowMatchesEveryRatifiedSemanticColor`:

```swift
.accentContainer: color(0xD4, 0xED, 0xE9),
```

Add Saved, Seen, and Loved ON-pair assertions to `testEveryMaterialPassesBodyAndLargeUIContrastGates`:

```swift
assertContrast(
    sheet.accent,
    sheet.accentContainer,
    minimum: 4.5,
    label: "accent/accentContainer Saved state"
)
assertContrast(
    sheet.accentContrast,
    sheet.accent,
    minimum: 4.5,
    label: "accentContrast/accent Seen state"
)
assertContrast(
    sheet.accentContrast,
    sheet.love,
    minimum: 4.5,
    label: "accentContrast/love Loved state"
)
```

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```bash
cd ios
swift test --filter MaterialTokensTests
```

Expected: compilation fails because `SemanticColorToken.accentContainer` and `MaterialTokenSheet.accentContainer` do not exist.

- [ ] **Step 3: Add the token to the complete token vocabulary**

In `MaterialTokens.swift`, add `.accentContainer` immediately after `.accent`, add the stored property and exhaustive subscript case, and set Snow to:

```swift
accent: MaterialColor(red: 0x0A, green: 0x6B, blue: 0x5C),
accentContainer: MaterialColor(red: 0xD4, green: 0xED, blue: 0xE9),
accentContrast: MaterialColor(red: 0xFB, green: 0xFA, blue: 0xF2),
```

Add `accentContainer: MaterialColor` to `MaterialTokenSheet.init` and assign `self.accentContainer = accentContainer`.

- [ ] **Step 4: Keep test-only token-sheet constructors exhaustive**

After each existing `accent: snow.accent` argument in these helpers, add:

```swift
accentContainer: snow.accentContainer,
```

The helpers are `MaterialTokensTests.makeSheet`, `ControlStylesTests.makeInteractionSheet`, and `PinLayersTests.tokenSheet`.

- [ ] **Step 5: Run the focused tests and verify GREEN**

Run:

```bash
cd ios
swift test --filter MaterialTokensTests
```

Expected: all `MaterialTokensTests` pass, including exact token equality and all three ON-state AA pairs.

- [ ] **Step 6: Commit the token slice**

```bash
git add ios/Sources/DesignSystem/MaterialTokens.swift ios/Tests/DesignSystemTests/MaterialTokensTests.swift ios/Tests/DesignSystemTests/ControlStylesTests.swift ios/Tests/MakingTracksMapStyleTests/PinLayersTests.swift
git commit -S -m "Add ratified Saved container token"
```

### Task 2: Reusable Semantic State-Toggle Style

**Files:**
- Modify: `ios/Sources/DesignSystem/ControlStyles.swift`
- Test: `ios/Tests/DesignSystemTests/ControlStylesTests.swift`
- Test: `ios/Tests/DesignSystemTests/PublicControlStylesTests.swift`

**Interfaces:**
- Consumes: `SemanticColorToken`, `MaterialTheme`, `MaterialButtonStyleBody`, and the existing six-point `MaterialControlLabelStyle`
- Produces: `public MaterialStateToggleButtonStyle.init(foreground:background:theme:)`

- [ ] **Step 1: Write failing appearance and public-API tests**

Add a DesignSystem test that asks the new style to resolve Saved's exact opaque palette:

```swift
func testStateToggleStyleResolvesOpaqueSemanticPalette() {
    let style = MaterialStateToggleButtonStyle(
        foreground: .accent,
        background: .accentContainer
    )

    XCTAssertEqual(style.appearance.foreground, MaterialTheme.snow.tokens.accent)
    XCTAssertEqual(style.appearance.background, MaterialTheme.snow.tokens.accentContainer)
    XCTAssertEqual(style.appearance.backgroundOpacity, 1)
    XCTAssertEqual(style.pressFeedback, .scale)
}
```

In `PublicControlStylesTests`, construct the style without `@testable` access:

```swift
_ = Button("Saved", action: {})
    .buttonStyle(
        MaterialStateToggleButtonStyle(
            foreground: .accent,
            background: .accentContainer
        )
    )
```

- [ ] **Step 2: Run focused tests and verify RED**

Run:

```bash
cd ios
swift test --filter ControlStylesTests
swift test --filter PublicControlStylesTests
```

Expected: compilation fails because `MaterialStateToggleButtonStyle` is undefined.

- [ ] **Step 3: Implement the minimal reusable component**

Add this public style beside the existing filled, tonal, and quiet button styles:

```swift
public struct MaterialStateToggleButtonStyle: ButtonStyle {
    private let foreground: SemanticColorToken
    private let background: SemanticColorToken
    private let theme: MaterialTheme

    public init(
        foreground: SemanticColorToken,
        background: SemanticColorToken,
        theme: MaterialTheme = .snow
    ) {
        self.foreground = foreground
        self.background = background
        self.theme = theme
    }

    var appearance: MaterialControlAppearance {
        MaterialControlAppearance(
            foreground: theme.tokens[foreground],
            background: theme.tokens[background],
            backgroundOpacity: 1
        )
    }

    var pressFeedback: MaterialControlPressFeedback { .scale }

    public func makeBody(configuration: Configuration) -> some View {
        MaterialButtonStyleBody(
            label: configuration.label,
            isPressed: configuration.isPressed,
            appearance: appearance,
            tokens: theme.tokens,
            pressFeedback: pressFeedback,
            accessibilityValue: { $0 ? nil : "Unavailable" }
        )
    }
}
```

This deliberately reuses `MaterialButtonStyleBody`, so state controls retain the ratified type role, six-point icon gap, monochrome symbols, 44pt minimum, disabled alpha, and 0.98 press scale.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run:

```bash
cd ios
swift test --filter ControlStylesTests
swift test --filter PublicControlStylesTests
```

Expected: all selected tests pass.

- [ ] **Step 5: Commit the component slice**

```bash
git add ios/Sources/DesignSystem/ControlStyles.swift ios/Tests/DesignSystemTests/ControlStylesTests.swift ios/Tests/DesignSystemTests/PublicControlStylesTests.swift
git commit -S -m "Add semantic state toggle style"
```

### Task 3: Place-Card State Presentation

**Files:**
- Modify: `ios/App/Sources/PlaceCard/PlaceCardSheet.swift`
- Test: `ios/App/Tests/AppShellTests.swift`
- Test: `ios/App/UITests/MakingTracksCoreLoopUITests.swift`

**Interfaces:**
- Consumes: every existing `PlaceCardAction`, `MaterialStateToggleButtonStyle`, `MaterialTonalButtonStyle`, `MaterialQuietButtonStyle`, and `PinState.saved`
- Produces: `PlaceCardActionPresentation`, `PlaceCardActionAppearance.presentation(for:isSaved:)`, and state-bearing SwiftUI `Label` content

- [ ] **Step 1: Replace the old hierarchy test with failing morphology tests**

Define an exhaustive expected table in `AppShellTests`:

```swift
let cases: [(PlaceCardAction, Bool, PlaceCardActionPresentation)] = [
    (.save, false, .init(title: "Save", systemImage: "bookmark", style: .tonal)),
    (.save, true, .init(title: "Saved", systemImage: "bookmark.fill", style: .state(foreground: .accent, background: .accentContainer))),
    (.seen, false, .init(title: "Seen", systemImage: "eye", style: .tonal)),
    (.unsee(isEnabled: true), false, .init(title: "Seen", systemImage: "eye.fill", style: .state(foreground: .accentContrast, background: .accent))),
    (.unsee(isEnabled: false), false, .init(title: "Seen", systemImage: "eye.fill", style: .state(foreground: .accentContrast, background: .accent))),
    (.love, false, .init(title: "Love", systemImage: "heart", style: .state(foreground: .love, background: .loveContainer))),
    (.unlove, false, .init(title: "Loved", systemImage: "heart.fill", style: .state(foreground: .accentContrast, background: .love))),
    (.hide, false, .init(title: "Hide", systemImage: nil, style: .quiet)),
    (.unhide, false, .init(title: "Unhide", systemImage: nil, style: .quiet)),
]
```

For every row, assert `PlaceCardActionAppearance.presentation(for:isSaved:)` equals the expected value. Separately assert ON presentations use `.fill` symbols, OFF presentations use outline symbols, and momentary presentations have no glyph.

- [ ] **Step 2: Run the focused app test and verify RED**

Use the designated simulator and the reusable derived-data path:

```bash
MT_RELEASE_GATE_DESTINATION='platform=iOS Simulator,id=AC60FA71-9449-4F15-A259-5E4A3E832839' \
./scripts/sim-lock.sh xcodebuild test \
  -project ios/App/MakingTracks.xcodeproj \
  -scheme MakingTracks \
  -destination 'platform=iOS Simulator,id=AC60FA71-9449-4F15-A259-5E4A3E832839' \
  -derivedDataPath /private/tmp/dd-codex3 \
  -parallel-testing-enabled NO \
  -disable-concurrent-destination-testing \
  -only-testing:MakingTracksTests/AppShellTests/testPlaceCardActionsUseStateMorphology
```

Expected: compilation fails because `PlaceCardActionPresentation` and `presentation(for:isSaved:)` do not exist.

- [ ] **Step 3: Implement the presentation table without touching slot grammar**

Replace the old warning/action-hierarchy mapping with:

```swift
struct PlaceCardActionPresentation: Equatable {
    let title: String
    let systemImage: String?
    let style: PlaceCardActionStyle
}

enum PlaceCardActionStyle: Equatable {
    case tonal
    case quiet
    case state(
        foreground: SemanticColorToken,
        background: SemanticColorToken
    )
}
```

Implement the exact test table in `PlaceCardActionAppearance.presentation(for:isSaved:)`. Keep `usesQuietTextPressInset` true only for Hide and Unhide. Do not edit `PlaceCardActionSlots.swift`.

- [ ] **Step 4: Mount the presentation in the existing buttons**

Pass `card.pinState.saved` to every style modifier. Render state controls as:

```swift
Label(
    presentation.title,
    systemImage: presentation.systemImage
)
.frame(maxWidth: .infinity)
```

Render quiet verbs as the existing text-only label. Route `.state` through `MaterialStateToggleButtonStyle`, `.tonal` through `MaterialTonalButtonStyle`, and `.quiet` through `MaterialQuietButtonStyle.textOnly`.

Keep every existing action closure, enabled/disabled rule, accessibility value, hint, identifier, long-press behavior, and action order unchanged. Keep `place-card.more` as the existing plain, background-free, icon-only Menu control with its explicit More accessibility label.

- [ ] **Step 5: Match frozen cluster spacing**

Change the default action-row spacing from `10` to the frozen component metric `8`; keep accessibility layout as a leading-aligned vertical stack with `8` points between controls.

- [ ] **Step 6: Add the default-size and AX render matrix**

Add `testPlaceCardStateMorphologyRenderMatrix` to `MakingTracksCoreLoopUITests`. For each tuple
`(saved: false/true, accessibilityTextSize: false/true)`, launch a reset fixture app, open and expand
the primary fixture card, then capture these three reachable visit states:

```swift
let states = [
    (name: "unseen", action: nil),
    (name: "seen", action: "place-card.visited"),
    (name: "loved", action: "place-card.loved"),
]
```

Before each capture, assert the action identifiers and exact state labels for the current state.
For unseen, assert outline-bearing labels `Save`/`Saved`, `Seen`, and no Loved ON label. For seen,
assert `Seen` and `Love`; for loved, assert `Seen` and `Loved`. At AX size, call
`assertVerticalActionStack`; at default size, assert horizontal ordering and no frame intersections.
Name and force-export the twelve captures so the matrix produces artifacts even when xcodebuild
does not propagate the shell environment into the UI runner:

```swift
attachScreenshot(named: name, forceExport: true)
```

Use these names:

```text
place-card-r15-{default|ax}-{unsaved|saved}-{unseen|seen|loved}
```

Add all twelve names to `screenshotExportNames`. These are the evidence set for grading every
reachable Saved × visit-state combination against A8; hidden is not a reachable card state under
the A4/A6 grammar.

- [ ] **Step 7: Run the focused app test and verify GREEN**

Repeat the Step 2 command.

Expected: the selected `testPlaceCardActionsUseStateMorphology` passes.

- [ ] **Step 8: Run the focused render matrix**

Run through the designated simulator:

```bash
MT_RELEASE_GATE_DESTINATION='platform=iOS Simulator,id=AC60FA71-9449-4F15-A259-5E4A3E832839' \
./scripts/sim-lock.sh xcodebuild test \
  -project ios/App/MakingTracks.xcodeproj \
  -scheme MakingTracks \
  -destination 'platform=iOS Simulator,id=AC60FA71-9449-4F15-A259-5E4A3E832839' \
  -derivedDataPath /private/tmp/dd-codex3 \
  -parallel-testing-enabled NO \
  -disable-concurrent-destination-testing \
  -only-testing:MakingTracksUITests/MakingTracksCoreLoopUITests/testPlaceCardStateMorphologyRenderMatrix
```

Expected: the render matrix passes and exports twelve non-empty PNGs. Inspect all twelve at original
detail: ON pills have opaque semantic fills and filled glyphs, OFF pills are tonal with outline
glyphs, momentary controls are quiet, default rows do not collide, AX rows form a leading-aligned
vertical stack, and the saved+seen+loved frame matches A8's fully-lit cluster. Record one evidence
sentence that the assigned seat is 402×874pt versus A8's 390×844 design canvas, and grade the
component figures beside the renders: 44pt default minimum pill height, 17pt glyph, 15pt/600 label,
6pt icon gap, 8pt cluster gap, plus Saved/Seen/Loved ON contrast 5.23:1/6.13:1/5.25:1.

- [ ] **Step 9: Commit the app slice**

```bash
git add ios/App/Sources/PlaceCard/PlaceCardSheet.swift ios/App/Tests/AppShellTests.swift ios/App/UITests/MakingTracksCoreLoopUITests.swift
git commit -S -m "Adopt place card state morphology"
```

### Task 4: Verification, Review, and Handoff

**Files:**
- Modify: `docs/superpowers/phases/phase-1/amendment-wave.md`

**Interfaces:**
- Consumes: Tasks 1–3, project review gates, A2 acceptance evidence
- Produces: green host/app gates, adversarial review accounting, pushed review head, and A2 row status `review`

- [ ] **Step 1: Run the complete host package suite**

Run:

```bash
cd ios
swift test
```

Expected: 491 or more tests pass with zero failures.

- [ ] **Step 2: Run adversarial review**

Request independent review lenses for spec fidelity, concurrency/correctness, test quality, and threat-model-calibrated security. Cross-examine every finding, fix findings that survive, and prove each fix has test teeth by observing the relevant test fail when the fix is locally neutered and pass when restored.

- [ ] **Step 3: Re-ground on the fresh target**

Run each mutation as its own command:

```bash
git fetch origin ios
git merge-base --is-ancestor origin/ios HEAD
```

If the ancestry check fails, merge `origin/ios` in a signed commit, resolve only A2-owned files, and rerun all affected tests.

- [ ] **Step 4: Run the complete simulator Release gate once**

Run:

```bash
MT_RELEASE_GATE_DESTINATION='platform=iOS Simulator,id=AC60FA71-9449-4F15-A259-5E4A3E832839' \
./scripts/sim-lock.sh ./scripts/release-gate.sh
```

Expected: Release build and complete simulator test suite pass with zero warnings; record exact counts.

- [ ] **Step 5: Verify scope and update the ledger row**

Verify:

```bash
git diff --stat origin/ios..HEAD
git diff origin/ios..HEAD -- ios/Sources/DesignSystem/MaterialTokens.swift ios/Sources/DesignSystem/ControlStyles.swift ios/App/Sources/PlaceCard/PlaceCardSheet.swift ios/Tests ios/App/Tests docs/superpowers/phases/phase-1/amendment-wave.md
python3 scripts/lint_agent_law.py
```

Change only A2's status from `branch` to `review`; keep owner and branch exact.

- [ ] **Step 6: Commit, push, and verify the remote head**

```bash
git add docs/superpowers/phases/phase-1/amendment-wave.md
git commit -S -m "Mark A2 place card morphology for review"
git push origin wp-526-place-card-state-morphology
git rev-parse HEAD
git rev-parse origin/wp-526-place-card-state-morphology
git log -1 --show-signature
```

Expected: local and remote SHAs match and the final commit has a good signature.

- [ ] **Step 7: Route the review request**

Send AMQ `review_request` messages containing the exact pushed SHA, branch, A2 row, frozen A8 artifact path, review accounting, host-test count, Release-gate count, and a statement that action presence/order and all `place-card.*` identifiers are unchanged.
