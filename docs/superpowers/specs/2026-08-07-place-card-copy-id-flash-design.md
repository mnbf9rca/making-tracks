# Place-card Copy ID confirmation design

## Status and decision

Issue #375 adds diagnostic copying to the existing place-card More menu. Rob ruled on 2026-08-06 that `Copy ID` must briefly become an in-row copied-confirmation state before the native menu dismisses. The feasibility condition has passed using public UIKit APIs. The rendered default and AX delta now requires reviewer validation; if it passes, no further Rob roundtrip is required before implementation.

The implementation must copy the exact raw `mt1_…` identifier, preserve the existing `Add to list` behavior, announce `Place ID copied.` to VoiceOver, show disabled `Copied` plus a checkmark for one second, and then dismiss. It must not add a toast or expose the identifier inline.

## Grounded context

The place-card header currently uses a SwiftUI `Menu` with a 44×44 `place-card.more` target and one action, `Add to list`. `PlaceCardMoreIconGlyph` owns the visible ellipsis styling and Dynamic Type behavior. The app targets iOS 18.

Public SDK support establishes the implementation boundary:

- SwiftUI `menuActionDismissBehavior(.disabled)` can keep a menu presented but offers no public delayed-dismiss handle.
- UIKit `UIMenuElement.Attributes.keepsMenuPresented` keeps a selected `UIAction` menu visible.
- A menu-owning `UIButton` exposes its public `contextMenuInteraction`; `UIContextMenuInteraction` can update the visible menu and dismiss it.

## Approaches

### Selected: UIKit-backed native menu beneath the existing SwiftUI glyph

Replace only the interaction owner. A transparent `UIViewRepresentable`-backed `UIButton` supplies a `UIMenu`, while the existing SwiftUI `PlaceCardMoreIconGlyph` remains the visible label. This preserves the ruled appearance and native menu behavior. The Copy action uses `keepsMenuPresented`; its coordinator updates the open menu to the confirmation state and dismisses it after the injected delay.

### Rejected: SwiftUI Menu only

SwiftUI can disable automatic action dismissal, but cannot publicly dismiss the live menu after a delay. Removing or swapping the anchor to force lifecycle dismissal would be fragile and outside the public contract.

### Rejected: custom SwiftUI popover

A custom popover could own timing directly, but would replace a native platform menu and enlarge the layout, focus, keyboard, VoiceOver, and dismissal surface. The issue does not justify that scope.

## Component design

### `PlaceCardMoreMenuButton`

A small SwiftUI wrapper composes the unchanged glyph over a transparent UIKit interaction view and retains the current target size, accessibility label, hint, and `place-card.more` identifier. It accepts the place ID and existing Add-to-list callback.

### UIKit interaction view and coordinator

The representable creates one transparent `UIButton`, sets `showsMenuAsPrimaryAction`, uses fixed menu ordering, and builds these idle actions:

1. `Add to list`, preserving existing behavior and identifier `place-card.add-to-list`.
2. `Copy ID`, with identifier `place-card.copy-id`, the hint-equivalent accessibility description, and `keepsMenuPresented`.

The coordinator is the state owner. Its observable states are `idle` and `confirming`. It cancels any prior confirmation task before starting another and cancels on teardown.

When Copy ID activates, the coordinator performs this sequence:

1. Write the exact supplied place ID to the pasteboard immediately.
2. Post the VoiceOver announcement `Place ID copied.`.
3. Enter `confirming` and update the visible native menu. `Add to list` remains first; the second row becomes disabled `Copied` with a trailing checkmark.
4. Await the injected one-second delay.
5. If the task is still current, ask the public context-menu interaction to dismiss the menu and return to `idle` so the next opening shows `Copy ID`.

If the system or user dismisses the menu first, the later dismissal is a harmless no-op and the coordinator still returns to idle. Updating SwiftUI inputs while confirmation is active must not replace the captured payload or start a second task.

### Injected effects

The coordinator receives narrow closures or protocol values for:

- writing the pasteboard payload;
- posting the accessibility announcement;
- awaiting the confirmation interval;
- updating the visible menu; and
- dismissing it.

Production adapters use `UIPasteboard`, `UIAccessibility`, `ContinuousClock` (or an equivalent cancellable public clock), and the button's public context-menu interaction. Tests supply deterministic fakes. No production or test path sleeps to observe state.

## Behavior contract

- Copy exactly the original place ID, including the `mt1_` prefix, with no formatting or newline.
- Keep `Add to list` first and preserve its current dismissal and navigation behavior.
- Keep the native menu visible while `Copied` is shown.
- Show text and checkmark together; color is not the only confirmation signal.
- Hold the confirmation for one second, then dismiss and reset.
- A subsequent menu opening always begins with `Copy ID`.
- Do not add persistence, analytics, networking, card layout, detent, action-bar, model, toast, or inline-ID changes.

## Accessibility, privacy, and layout

The transparent interaction owner must remain at least 44×44pt at default size and retain the existing AX enlargement. VoiceOver order is `Add to list`, then `Copy ID`; activation announces success without speaking the long identifier. The confirmation action exposes `Copied` as text and is disabled to prevent a duplicate copy. The state replacement has no animation and therefore respects Reduce Motion without a separate branch.

The place ID is a public diagnostic reference, but the app still places it on the system pasteboard only after an explicit user action. It is not logged, persisted, transmitted, or inserted into the card's reading hierarchy.

The native menu must remain fully onscreen through AX5. UIKit owns exact row geometry; implementation evidence gates the app-owned More target at least 44×44pt by default and its 52×52pt AX enlargement, fixed `Add to list` then `Copy ID` order, on-screen containment, accessibility exposure/activation, and the success announcement. On 2026-08-07, iOS 26.5 rendered each native row at 250×42pt by default and 370×126pt at AX5; these are dated platform observations, not thresholds. The deterministic renders specify state, order, and feedback rather than private system pixels.

## Testing and evidence

Unit tests exercise the coordinator before production code is written:

- exact payload and announcement occur once and immediately;
- visible state changes from `Copy ID` to disabled `Copied` plus checkmark;
- the menu does not dismiss before the injected delay completes;
- completing the fake delay dismisses once and restores idle state;
- cancellation/teardown prevents a stale task from dismissing a later menu;
- Add to list preserves its callback and never writes the pasteboard;
- long IDs remain byte-for-byte unchanged.

Host/component tests verify fixed row order and both action identifiers. UIKit `UIAction.Identifier` values will use `place-card.add-to-list` and `place-card.copy-id`; the live UI test must verify those stable routes are exposed to XCTest before the implementation gate can pass. If UIKit does not surface the identifiers as expected, the builder must add a tested public accessibility route or return the finding to the reviewer/planner rather than silently weakening the contract.

Locked simulator UI evidence verifies the menu stays visible after activation, shows `Copied` and a checkmark, dismisses after the controlled interval, resets on reopen, copies the exact payload, preserves Add to list, keeps the app-owned More target at least 44×44pt by default and at least 52×52pt at AX5, preserves row order and accessibility activation, and keeps the native menu fully onscreen. It records the dated default and AX5 native-row observations without turning them into thresholds. The default and AX deterministic confirmation renders are the visual comparison packet; live system-menu pixels are implementation evidence, not a requirement to match illustrative geometry exactly.

## Rendered decision record

The ruled packet and reproduction oracle live in `docs/design/design-system/375-copy-id-menu-ruling.md`. Its original default/AX images are unchanged, and its new default/AX `Copied` frames record the confirmation delta selected by Rob.
