# Place Card Design-System Adoption Plan

> **For Codex:** Execute this plan test-first and keep the four love/warning
> values behind the explicit ruling seam until Rob ratifies their token rows.

**Goal:** Move the place-card surface out of `MapScreen.swift` and onto the
ratified DesignSystem token, typography, and button-style contracts while
preserving card behaviour and adopting the #376 adaptive-photo ruling.

**Architecture:** Extract the complete place-card view and its private helpers
into `ios/App/Sources/PlaceCard/PlaceCardSheet.swift`. Keep data loading and
mutation in the existing `MapScreenModel`; the extracted view receives that
model and the same callbacks, so this is a surface extraction rather than a
behavioural rewrite. Replace `PlaceCardVisualSpec` with a small token-backed
appearance/layout contract and a pure photo-height calculation that is directly
testable.

**Tech stack:** Swift 6, SwiftUI, UIKit/ImageIO, `DesignSystem`, XCTest,
XCUITest, XcodeGen project generation, simulator release gate.

## Taste guesses

- Replace the fixed 132pt photo slot with a 112–260pt clamp. At the card's
  usual ~354pt content width, 112pt keeps a 3.16:1 panorama legible rather than
  a sliver, while 260pt keeps portrait/square media below most of the first
  medium detent and leaves the pinned action bar visible. The unclamped height
  is `availableWidth × imageHeight / imageWidth`.
- Use metadata dimensions before decode and decoded-image dimensions as the
  authoritative fallback. Invalid or absent dimensions use a neutral 4:3
  loading/error ratio rather than bringing back a fixed production-photo
  height.
- Preserve aspect ratio with `scaledToFit`, never `scaledToFill`. The frame
  follows the intrinsic ratio in the admitted clamp range. (Extremes at the
  clamp are the unavoidable boundary of the ruled min/max policy; render
  evidence will include representative landscape and portrait cases.)

## Task 1: Pin the token, style, typography, dead-code, and photo-layout contracts

**Files:**
- Modify: `ios/App/Tests/AppShellTests.swift`
- Modify: `ios/Tests/DesignSystemTests/MaterialTokensTests.swift`

1. Rewrite `testPlaceCardVisualSpecMatchesApprovedCardLayout` so it expects
   Snow's `surface`, `surfaceRaised`, `ink`, `muted`, `accent`, and
   `accentContrast` token resolutions rather than 13 literal colours.
2. Repoint the action mapping test to filled/tonal/quiet semantic styles and
   assert at most one filled slot in every pin state.
3. Add pure photo-layout tests covering 4:3, landscape, portrait, min clamp,
   max clamp, invalid metadata, and decoded-size fallback.
4. Add a source-structure assertion that the card is absent from
   `MapScreen.swift`, has no forced light scheme, no fixed 132pt slot,
   no `scaledToFill`, and no missing-photo branch/type.
5. Run the focused app test target and record the expected RED result.

## Task 2: Extract the place-card surface

**Files:**
- Add: `ios/App/Sources/PlaceCard/PlaceCardSheet.swift`
- Modify: `ios/App/Sources/Map/MapScreen.swift`
- Modify: `ios/App/project.yml`
- Regenerate: `ios/App/MakingTracks.xcodeproj/project.pbxproj`

1. Move `PlaceCardSheet`, its preference key, photo slot, layout/appearance
   contract, and place-card-only helpers to the new source file.
2. Remove `PlaceCardVisualSpec`, the dead missing-photo slot flag/branch/type,
   and the moved declarations from `MapScreen.swift`.
3. Preserve the existing initializer/callback boundary and action behaviour.
4. Add the new source to the app target through `project.yml`, then regenerate
   the project.
5. Run the focused structural and behavioural tests.

## Task 3: Adopt tokens, typography roles, and component styles

**Files:**
- Modify: `ios/App/Sources/PlaceCard/PlaceCardSheet.swift`

1. Resolve the card, fade, action-bar, text, link, swatch, and fallback-media
   colours from `MaterialTheme.snow.tokens`; both fade stops use `surface`.
2. Remove `.preferredColorScheme(.light)`.
3. Apply `Typography.font(for: .placeName)` to the place name and machinery
   roles to body, labels, metadata, and controls.
4. Replace manual action styling with `MaterialTonalButtonStyle` for Save,
   `MaterialFilledButtonStyle` for Seen, and `MaterialQuietButtonStyle` for
   Hide/unhide. Disabled uses the style's standard opacity and the existing
   muted vocabulary.
5. Keep love/unlove and warning/unsee behind a clearly marked
   `TODO(ruling)` appearance seam using their pre-existing four literals only;
   do not derive or invent replacements.
6. Verify VoiceOver labels/values/hints and AX5 vertical reflow remain intact.

## Task 4: Implement adaptive photo layout

**Files:**
- Modify: `ios/App/Sources/PlaceCard/PlaceCardSheet.swift`
- Modify: `ios/App/Tests/AppShellTests.swift`

1. Implement the pure 112–260pt height calculation from available width and
   safe intrinsic dimensions.
2. Size the slot with a geometry-provided available width and render decoded
   media with aspect-fit semantics.
3. Keep loading/failure UI token-backed and Reduce Transparency-safe (solid
   `surfaceRaised`, no material blur).
4. Run the focused tests until GREEN.

## Task 5: Land Rob's love/warning ruling

**Files:**
- Modify: `docs/superpowers/specs/2026-07-25-design-system-and-ia-design.md`
- Modify: `ios/Sources/DesignSystem/MaterialTokens.swift`
- Modify: `ios/Tests/DesignSystemTests/MaterialTokensTests.swift`
- Modify: `ios/App/Sources/PlaceCard/PlaceCardSheet.swift`
- Modify: `ios/App/Tests/AppShellTests.swift`

1. Record exactly the ratified semantic rows and Snow values in the spec.
2. Add those rows to the material sheet and its exhaustive token accessor.
3. Extend token contrast tests for every newly ratified text/background pair.
4. Replace the four TODO-ruling literals with the new token resolutions.
5. Prove the new contrast/token-resolution test fails under a deliberate
   mutation, revert the mutation, and rerun GREEN.

## Task 6: Render and verify

**Files:**
- Add: `docs/design/design-system/t1.10-place-card.html`
- Add: `docs/design/design-system/t1.10-place-card.png`
- Add: `docs/design/design-system/t1.10-place-card-ax.html`
- Add: `docs/design/design-system/t1.10-place-card-ax.png`

1. Produce committed 390×844 Snow/default and AX render evidence, including
   adaptive landscape/portrait photo states and dark system appearance.
2. Run `cd ios && swift test`.
3. Run the focused app unit/UI tests through `scripts/sim-lock.sh`.
4. Run the full host gate:
   `./scripts/sim-lock.sh ./scripts/release-gate.sh`.
5. Run the required independent critics, cross-examination/fix loop, mutation
   proof, Sourcery, and exact-head Opus review.
6. Update the task ledger and AMQ status, commit intentionally, push, open the
   PR to `ios`, and hand merge authority to fable.
