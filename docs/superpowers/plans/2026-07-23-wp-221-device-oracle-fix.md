# WP-221 My Tracks device-oracle fix

> Issue #221 and the ratified visits-editing mockups are the design authority. Opus's
> 2026-07-23 ruling selects an appearance-invariant light-paper surface with explicit
> colour tokens; this plan does not revisit that decision.

## Goal

Make the My tracks visits editor render the ratified light-paper design on a real
device in both Light and Dark system appearances, and prevent a structural UI test
from passing while the rendered content is illegible.

## Task 1: Add the RED rendered-pixel oracle

**Files**

- Modify: `ios/App/UITests/MakingTracksCoreLoopUITests.swift`

Add shared screenshot sampling helpers that:

1. Render the My tracks editor from the menu in forced Light and forced Dark.
2. Sample the rendered paper, sheet, ink, dim, accent, and danger colours with
   Opus's ±5 RGB tolerance.
3. Compute WCAG relative luminance from sampled foreground/background pixels and
   require normal text contrast of at least 4.5:1, large text at least 3:1, and no
   sampled text below 3:1.
4. Verify opaque/low-variance paper and sheet fills, flat paper-backed navigation
   controls, and absence of system-blue pixels.
5. Verify representative row control order and compact heart/delete controls.

Run both new tests against unchanged production code and retain the failing Dark
screenshot as the RED evidence.

## Task 2: Give the track surface explicit visual semantics

**Files**

- Modify: `ios/App/Sources/Map/MapScreen.swift`

Extend `TrackVisitEditorVisualSpec` with the ruled `ink` and `dim` tokens. Apply the
track-only tokens explicitly to every title, summary, day header, place label,
metadata label, date label/value, and row action. Replace inherited bordered
styles with explicit paper/accent/danger shapes so the surface cannot inherit
system blue or Dark-mode semantic text.

Do not add `.preferredColorScheme`, a colour-scheme environment override, or a
parallel Dark palette.

## Task 3: Replace inherited navigation chrome for My tracks

**Files**

- Modify: `ios/App/Sources/Map/MapScreen.swift`

Hide the system navigation bar only for the My tracks visit editor and render a
paper-backed, flat Back/title/Done header whose actions preserve both entry paths:
Menu → My tracks and Menu → Lists → My tracks. Keep collection-list navigation
unchanged.

## Task 4: Prove the fix and prepare device evidence

Run the focused Light and Dark pixel tests, `swift test --package-path ios`, and
`./scripts/sim-lock.sh ./scripts/release-gate.sh`. Export 390×844 Light and Dark
device-frame screenshots and place them beside the frozen mockup with an M1–M6
checklist.

Ask independent agents to review visual fidelity, correctness, tests, security,
and regression risk. Resolve all P1/P2 findings, obtain Opus's visual review, send
the evidence to Rob before merge, and hand the reviewed branch to Fable.
