# Explore destination-row press pulse design

**Issue:** #595  
**Designer ruling:** Settings and About are enabled glyphed quiet controls, so they join A5's ratified symbol-weight pulse family.  
**Scope:** pressed interaction only; resting row geometry, colour, typography, routing, and accessibility remain unchanged.

## Grounded defect

`ExploreQuietDestinationIconGlyph` adopts `.iconRole(.rowQuiet)` but then pins
`.fontWeight(.medium)`, so an emphasized `materialControlSymbolWeight` environment cannot reach the
glyph. The row also mounts `.buttonStyle(.plain)`, so merely deleting the override would leave no
production `ButtonStyle.Configuration.isPressed` path to set that environment. Both blockers must
move together.

## Considered approaches

1. **Delete the weight override only — rejected.** The glyph becomes environment-capable but the
   production row remains on `PlainButtonStyle`; the visible press stays dead.
2. **Mount `MaterialQuietButtonStyle` directly — rejected.** It would reuse A5, but also introduces
   capsule padding, minimum frame, foreground, and content-shape chrome around the ratified
   hairline row. That changes the resting surface and exceeds the ruling.
3. **Mount a label-preserving row adapter over A5's existing feedback implementation — chosen.**
   Extract the already-shipped environment/scale/offset application from `MaterialButtonStyleBody`
   into one shared modifier. The existing filled/tonal/quiet styles and the new row adapter both
   delegate to it. The adapter adds no new feedback case, weight, colour, opacity, or geometry.

The planner explicitly ruled approach 3 conformant on 2026-08-01: the adapter is plumbing in the
same class as `IconRoleModifier`; reimplementing the pulse is forbidden, and resting-state equality
is part of acceptance.

## Production shape

- Add `MaterialQuietRowButtonStyle`, whose only feedback strategy is the existing
  `MaterialControlPressFeedback.symbolWeightPulse`.
- Extract the current environment weight, token-backed press scale, and optional offset into a
  shared internal modifier. `MaterialButtonStyleBody` and `MaterialQuietRowButtonStyle` call the
  same modifier, so divergence breaks tests rather than silently forking A5.
- Extract the existing row label into `ExploreQuietDestinationRowContent`; both the production
  button and DEBUG evidence fixture render that exact content.
- Replace `.buttonStyle(.plain)` with `MaterialQuietRowButtonStyle()` and delete the explicit
  `.fontWeight(.medium)` plus its expired preserve comment.

At rest the shared modifier resolves standard/medium weight, scale `1`, and offset `0`; the row must
render identically to the pre-enrollment state. While pressed it resolves emphasized/semibold
weight and the already-ratified token press scale. No opacity change is permitted.

## Behavioral tests

Invert `testExploreQuietDestinationWiresRowQuietWithFixedMediumWeight` rather than deleting it:

- assert the real row mounts exactly one `MaterialQuietRowButtonStyle` using
  `.symbolWeightPulse`;
- assert the default/standard glyph remains byte-identical to the former fixed-medium reference at
  default and AX5;
- flip the old emphasized-equality assertion: emphasized rendering must differ from rest and carry
  more glyph ink, proving medium → semibold;
- render the complete row content with and without the shared modifier at rest and require byte
  equality, pinning pressed-only enrollment.

Mutation checks must kill the tests when the row style returns to plain, when the adapter selects
`.scale`, when emphasized maps back to medium, and when the resting adapter changes geometry.

## Live evidence

A DEBUG-only Explore-row fixture uses the exact production row content and wraps the exact
production row style only to overlay an out-of-crop cyan/rest or magenta/pressed state marker.
Unique launch arguments select Settings or About. UI tests export the live button frame and issue
repeated real taps while a lock-owned capture loop records lossless simulator screenshots; the
marker, not a method name, proves `ButtonStyle.Configuration.isPressed` was live.

A fail-closed analyzer selects one rest and one pressed candidate for each row at default and AX,
measures glyph-region ink count and bounds beside the frames, and refuses identical crops. The
packet therefore contains eight frames: Settings and About × rest and pressed × default and AX,
plus paired measurements, digests, exact head, toolchain, destination, and regeneration command.
`XCUIElement.press(forDuration:)` is not used because A5 proved it does not hold the configuration's
pressed state.

The fixture is self-contained and uses #595-specific flags/helpers. It does not import or depend on
#575's unpublished place-card fixture; any overlap after #575 lands is resolved manually during
rebase, not by coupling the branches.

## Out of scope

- no new feedback mechanism, weight, metric, opacity, animation, or exception list;
- no change to Scope-control glyphs, raised door rows, destination copy, routing, or accessibility;
- no shared-fixture cleanup with #575;
- no change to committed T2.3 historical evidence. The new packet records the later ruling.
