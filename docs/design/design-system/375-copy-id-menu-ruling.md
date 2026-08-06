# #375 Copy ID menu — pre-ruling packet

Status: **REVIEWER VALIDATED / DO NOT IMPLEMENT**. Build agent authored; reviewer validated the proposal at `d0b0379`; Rob's ruling remains required.

Evidence class: **Deterministic fixture.** SHA-256 is the byte-reproduction oracle.

## Request

Add a `Copy ID` action to the existing place-card ellipsis menu so a person reporting a problem can copy the exact `mt1_…` place identifier. Keep the identifier out of the card's visible hierarchy.

## Grounded surface

`PlaceCardSheet.header` already renders a native SwiftUI `Menu` behind the 44×44 `place-card.more` control. Its only row is `Add to list`; no clipboard or copy-confirmation pattern exists in app code. The surrounding card, action bar, detents, and More control stay unchanged.

## Options

1. **Native menu row only — recommended.** Put `Copy ID` after `Add to list`; copy the exact identifier; let the native menu dismiss; post the VoiceOver announcement `Place ID copied.` No visible toast.
2. **Menu row plus visible toast.** Gives sighted confirmation, but introduces timing, overlap, and dismissal behavior for a synchronous, conventional copy action. It expands #375 beyond the requested menu-row change.
3. **Show the ID inline on the card.** Makes the value discoverable without the menu, but exposes internal diagnostic copy in the primary reading order and spends scarce AX space.

The recommendation treats the native menu dismissal as sufficient sighted feedback, while explicitly confirming success for VoiceOver. If Rob wants sighted confirmation, choose option 2 and return it through a separate toast-state render before implementation.

## Proposed contract

- Row label: `Copy ID`, ordered after `Add to list`.
- Payload: the exact `placeID` string, including the `mt1_` prefix; no name, label, newline, or diagnostic wrapper.
- Visible feedback: none beyond native menu dismissal.
- Accessibility: menu item label `Copy ID`; hint `Copies this place's identifier`; success announcement `Place ID copied.`
- Stable identifier: `place-card.copy-id`.
- Scope: no card layout, action bar, detent, data-model, persistence, analytics, or network change.

## Constraint and accessibility record

The two frames are exactly 390×844 CSS pixels. The default render retains the current 44×44 More target and three-button action row. The AX render enlarges the More target to 52×52, menu rows to an illustrative 72pt minimum, card title to 44pt, and actions to 64pt stacked rows. These menu dimensions are **illustrative, not ratified**: SwiftUI owns the live menu geometry, and implementation evidence must verify that each native row remains at least 44pt and fully onscreen through AX5.

The decision carried by the renders is row order, copy, and feedback—not private system-menu pixels. VoiceOver must encounter `Add to list`, then `Copy ID`; activating Copy ID must announce success without reading the long identifier aloud. The raw ID is placed only on the system pasteboard after an explicit user action.

## R16 proof-absence record

The filled `Seen` control in these frames reports an ON state under R16; it is not a filled action. The render preserves A2's shipped R15 morphology—tonal means available, filled means on, and quiet means a momentary verb—so it introduces no filled action beside the state cluster. **this surface does not pair a filled action with a state cluster; the R16 proof obligation travels to the first surface that does.**

| Default | Accessibility size |
|---|---|
| ![Default #375 Copy ID menu](375-copy-id-menu.png) | ![AX #375 Copy ID menu](375-copy-id-menu-ax.png) |

## Reproduction

Run `./scripts/render-375-copy-id.sh`. The deterministic-fixture packet uses Chromium 151.0.7922.34 at device scale factor 1 and captures the HTML source directly at 390×844.
An unchanged second render reproduced both files byte-for-byte.

- `375-copy-id-menu.png`: `868bd85fa2267c24ada1e9da2fa8b30a3c2627e32808b03c98863ebf87a89ff1`
- `375-copy-id-menu-ax.png`: `682d7c353def9e46a14fe0a1cf3ac93b29f05105cd2b2f65feb075f7fa31530d`
