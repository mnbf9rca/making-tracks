# Material control press feedback design

## Decision

R9 requires enabled interaction feedback to preserve the contrast of semantic
foreground/background token pairs. `MaterialChipStyleBody` and
`MaterialButtonStyleBody` will therefore stop applying `0.78` opacity while
pressed. They will mirror the established `PlaceCardActionAppearance` split:

- `semanticControlOpacity(isEnabled:)` returns `1` when enabled and `0.46`
  when disabled.
- `semanticControlScale(isPressed:)` returns `0.98` when pressed and `1`
  otherwise.

Both policies will live on one internal
`MaterialControlInteractionFeedback` seam used by both style bodies. This
keeps the two control families coherent. Each style body also exposes a
narrow internal boundary accepting an explicit label and pressed state;
production `ButtonStyle.Configuration` forwards its real values into that
boundary, and rendered package tests exercise the point of use without
growing public API.

## Modifier order

Each style body will apply its disabled-only opacity and then its pressed
scale. The scale stays inside the button style body. `MaterialChip` continues
to apply `MaterialChipHitTargetShape` outside the style body, so scaling the
rendered capsule cannot shrink the derived 44pt interaction shape.

## Contrast evidence

The snow filled pair is accent contrast `#FBFAF2` on accent `#0A6B5C`, with
an opaque contrast ratio of `6.1330:1`. Compositing the entire control at
`0.78` over snow surface `#FBFAF2` changes the effective background to
approximately `(63.02, 138.46, 125)` and reduces the pair to `3.8801:1`.
Keeping enabled opacity at `1` preserves `6.1330:1`; scale changes geometry,
not color.

## Verification

Package tests pin the enabled and disabled opacity branches and the pressed
and resting scale branches through the shared policy seam. Rendered
point-of-use tests additionally verify that each pressed style body preserves
the opaque semantic accent pixels and renders at 0.98 geometry. Body-local
mutations restoring `0.78` opacity or removing the pressed scale must fail.

The existing AC29 UI test adds a press-duration activation at the 11pt outset
edge. It proves the pressed lifecycle and edge activation only. Modifier order
is protected by code structure and adversarial review, not by AC29; no
modifier-order mutation is claimed.

No error path is introduced: the policy is deterministic from SwiftUI's
`isEnabled` and `isPressed` state. Existing disabled opacity remains `0.46`.
