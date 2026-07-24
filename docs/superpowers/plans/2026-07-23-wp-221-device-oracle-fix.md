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

1. Render the My tracks editor from the menu after explicitly setting and
   verifying the designated simulator's Light and Dark appearances.
2. Sample the rendered paper, sheet, ink, dim, accent, and danger colours with
   Opus's ±5 RGB tolerance.
3. Compute WCAG relative luminance from observed foreground/background token
   samples, exclude control outlines from glyph sampling, require normal text
   contrast of at least 4.5:1 and large text at least 3:1, and reject sampled text
   below 3:1.
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
`./scripts/sim-lock.sh ./scripts/release-gate.sh`. Export Light and Dark
screenshots at the designated simulator's native 402×874 logical canvas—the same
canvas as Rob's reported device—and place them beside the frozen 390×844 design
reference with an M1–M6 checklist. Assert the native canvas dimensions so evidence
cannot silently move to a different device class.

Ask independent agents to review visual fidelity, correctness, tests, security,
and regression risk. Resolve all P1/P2 findings, obtain Opus's visual review, send
the evidence to Rob before merge, and hand the reviewed branch to Fable.

## Amended M6: Compact-row density

The ratified amendment replaces inline date/delete fields in the full My tracks
surface with one-line visit rows grouped under sectional day headers. Each row
keeps only the pin, truncated name, category/time metadata, loved action, and
reorder affordance. Tapping a row opens the existing Visit date home, where date
adjustment and deletion remain available. The DEBUG visual fixture contains the
eight named visits from `visits-editing-dense.png`, and the RED oracle must prove
that at least six rows fit in the 390×844-class viewport with no inline date
accessibility targets. History-list work is explicitly out of scope.
