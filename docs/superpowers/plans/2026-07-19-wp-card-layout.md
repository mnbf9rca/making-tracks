# WP-CARD-LAYOUT — place card

## 1. The spec, unchanged

Rob, issue #171:

> "prominent name / type / description / photo / lists; attribution small at bottom + outbound link."

That order is still right. This design keeps all six elements in that order and does not move any of them.

What the research changed is the diagnosis. The commission assumed photos, descriptions, chips and verdicts are now competing for vertical space. Two of those four are not competing today, and the thing that is actually broken is something else.

## 2. Lead finding: the core loop is below the fold

**The description does not render in production.** The card reads `card.blurb` (MapScreen.swift:3948). The publisher emits `{place_id, name, lat, lon, category, tier, score, source_refs}` and no blurb key. The descriptions sidecar is published and contracted but the app does not consume it; WP-BLURB-B is not commissioned. The only blurbs in existence are the two UI-test fixtures at MapScreen.swift:2128 and 2141. So the description block is invisible to every real user. Anything this design does about description length is contingency for work that has not been ordered.

**The real failure is reachability, not competition.** At AXXXL the UI test has to call `scrollToExistence` for Save, Seen and Love. The card already hoists actions above the description at accessibility sizes (MapScreen.swift:3945) and sets the detent to `.large` (line 3980), and the primary actions are *still* off screen. The one thing a tourist opens this card to do needs a scroll.

**The hoist bought a second hierarchy and did not fix the problem.** `actionButtons(card)` is called twice: at position 4 when `dynamicTypeSize.isAccessibilitySize`, at position 9 otherwise (lines 3945 and 3962). There are two element orders shipping today. Rob specified one.

Those two facts set the whole design. Actions are not content, they were never in Rob's list, and they are the only thing on the card that must never require a scroll. So they leave the scroll flow. Everything else keeps Rob's order, at every text size, with no branch.

## 3. Mockups

### Default text size, iPhone SE (375×667), `.medium` detent

```
┌──────────────────────────────────────┐
│           ▁▁▁▁▁▁▁▁                   │  drag indicator (NEW)
│                          ⋯    Close  │  overlay, not a spine row
│                                      │
│  Ghost Sign                          │  1  name  .title2 semibold
│  ⛩  Attraction                       │  2  type
│                                      │
│  A hand-painted sign still visible   │  3  description
│  above the old shopfront.            │     (renders for nobody today)
│                                      │
│  ┌────────────────────────────────┐  │  4  photo
│  │                                │  │
│  │            photo               │  │
├──╫────────────────────────────────╫──┤ ◀── fold
│  └────────────────────────────────┘  │
│                                      │
│  ( Date night )   ( Weekend )        │  5  list chips
│                                      │
│  Photo: J. Bloggs · CC BY-SA 4.0 ↗   │  6  attribution, licence is a Link
│░░░░░░░ scroll-edge fade ░░░░░░░░░░░░░│
├══════════════════════════════════════┤
│   [  Seen  ]  [ Save ]  [  Love  ]   │  PINNED — outside the ScrollView
└──────────────────────────────────────┘
                                          map interactive behind sheet
```

The fold line is where the `.medium` detent clips scroll content. The pinned bar sits below it on screen and is **not** scroll content: it is visible at every scroll offset, always.

`⋯` holds Add to list and Hide/Unhide.

### AXXXL, iPhone SE, `.large` detent

```
┌──────────────────────────────────────┐
│           ▁▁▁▁▁▁▁▁                   │
│                          ⋯    Close  │
│                                      │
│  Ghost                               │  1  name wraps
│  Sign                                │
│                                      │
│  ⛩  Attraction                       │  2  type
│                                      │
│  A hand-painted                      │  3  description, NOT clamped
│  sign still visible                  │     at accessibility sizes
│  above the old                       │
├──────────────────────────────────────┤ ◀── fold
│  shopfront.                          │
│                                      │
│  ┌────────────────────────────────┐  │  4  photo, grows with text,
│  │            photo               │  │     capped as a fraction of
│  └────────────────────────────────┘  │     the content viewport
│                                      │
│  ( Date night )                      │  5  chips, one per row
│  ( Weekend )                         │
│                                      │
│  Photo: J. Bloggs ·                  │  6  attribution wraps
│  CC BY-SA 4.0 ↗                      │
│░░░░░░░ scroll-edge fade ░░░░░░░░░░░░░│
├══════════════════════════════════════┤
│  [           Seen            ]       │  PINNED, FlowLayout wraps
│  [           Save            ]       │  to as many rows as needed
│  [           Love            ]       │  no nested scroll, ever
└──────────────────────────────────────┘
```

Same content order as default size. Nothing is hoisted, because nothing needs to be. All three primary actions are hittable at scroll offset zero.

### Before Seen is tapped

```
│   [  Seen  ]  [ Save ]  [░░░░░░░░]   │  Love's slot is reserved and
                             ▲           empty. Tapping Seen fills the
                             │           gap. The row never re-flows
                    reserved, not drawn  under the thumb.
```

Every action awaits a DB write and a refetch with no optimistic update. Without a reserved slot, the button under the finger can become a different button between finger-down and write-return.

## 4. What is recommended

**Winner: content-first.** Rob's order was right. The execution failed. Fix the execution.

1. **Pin the primary actions.** `.safeAreaInset(edge: .bottom)` on the card's ScrollView. This deletes both `isAccessibilitySize` call sites of `actionButtons` and the two-hierarchy problem with them. It also yields the bottom content inset for free, so attribution can still scroll clear of the bar. Actions become unreachable-by-scroll by construction, not by budget.
2. **Three fixed slots: Seen, Save, Love.** Love's slot is reserved from first render. Seen keeps `.borderedProminent`. Seen is never demoted anywhere, at any size.
3. **Add to list and Hide move to a `⋯` overflow beside Close.** Five text buttons across 375pt is roughly 65pt per cell; "Add to list" does not fit. Hide is destructive-ish and does not belong under the thumb next to Seen. This costs one extra tap for both actions and is a real Principle 3 regression — see Open choice B.
4. **The bar uses `FlowLayout`** (already in the codebase at MapScreen.swift:4022, used for chips). It wraps to as many rows as it needs at any text size. Three slots means the AXXXL worst case is three stacked rows. There is no height cap, no demotion rule, and no scroll region inside the bar.
5. **Close moves to a top-trailing overlay** with a drag indicator. It currently owns a whole row at the top of the reading order (MapScreen.swift:3931-3938) for chrome.
6. **Attribution's licence becomes a Link.** See §6.
7. **Photo height stops being a hard-coded 180pt.** See §5.
8. **Description is not clamped.** The block renders for nobody. Clamping is a contingency to specify when WP-BLURB-B is commissioned, not a shipped affordance sitting on an empty block.

### Grafted from the runners-up

| Graft | From | Why |
|---|---|---|
| Fixed slot count, Love's cell reserved from first render | pinned-actions | Connects "no optimistic update" to "the button under the thumb must not move". Real mis-tap class, cheapest possible fix. |
| Add to list and Hide out of the primary bar | pinned-actions | Resolves the 65pt-cell problem the winner filed as an open parameter. |
| Seen is never demoted, at any size | adaptive | Principle 3 and 4 invariant, stated as a rule rather than a preference. |
| Scroll-edge fade above the bar | pinned-actions | A pinned bar makes a truncated card look complete. The fade says there is more. |
| `FlowLayout` for the action bar instead of a grid or `ViewThatFits` | two-detent | Deletes the AX layout branch instead of rewriting it. No truncation, no cap parameter, no nested scroll. |
| Photo height as a scaled metric capped by viewport fraction | adaptive | The fixed 180pt is proportionally tiny at AXXXL. |
| A test guarding the no-prefetch law | adaptive | Standing law on #171 with nothing enforcing it. |

## 5. Photo

**Correction to the brief.** `PlaceCardPhotoSlot` (MapScreen.swift:4254) already draws a fixed 180pt box with a `ProgressView` while bytes load. Late-arriving *bytes* cause no jump. The live jump is presence-driven: `observeImageChanges()` → `refreshCard()` (lines 4157-4171) replaces `card` and `card.photo` flips nil → non-nil, at which point the whole 180pt block is **inserted** into an open card and everything below it moves.

Two ways to fix that, and they are Rob's call (Open choice D):

- Reserve the slot at first render whenever the place is known to have a photo record, before bytes exist. Nothing below moves.
- Animate the insertion and accept a bounded, visible growth.

Note `PlaceCardPhoto.width` and `.height` are `Int?` and nil on the no-image init, so an aspect-derived height needs a default path anyway, and per-place variable height fights the viewport cap. Recommend a single computed height, not per-place aspect.

**Sizing.** Replace the hard 180pt with a height expressed as a scaled metric so it grows with Dynamic Type, clamped to a maximum fraction of the content viewport. Text wins the tie. Values open.

**No photo record.** No slot, no empty box, no apology. Chips move up. That is the offline case today, since photos are not in packs (WP-IMG-B2 not started).

**Standing law.** Fetching stays strictly viewport/card-driven. No launch prefetch, no cache warming. Reserving a slot is layout, not fetching, and must not be allowed to grow into speculative decoding. There is no test guarding this today; this design adds one (§7).

## 6. Attribution

Stays last, stays `.caption2`, stays below the fold at `.medium` on SE. Attribution is a presence obligation. It is satisfied by being present and reachable.

Today `attributionParts` (MapScreen.swift:4241) appends `photo.attribution`, which is `PlaceImageAttribution.displayText`, which ends with `licenseURL.absoluteString` (MakingTracksTiles.swift:1750-1759). A full raw CC URL renders as inert plain text. It is the longest thing on the line, it is unreadable, and tapping it does nothing. VoiceOver reads the URL out character by character.

Proposed: `Photo: J. Bloggs · CC BY-SA 4.0 ↗` where the licence name is a `Link` carrying `licenseURL`. Separator changes from `" / "` to `·` because a slash next to a URL reads as a path. The full string stays in the `accessibilityLabel`. Give the row a real hit area with padding.

**This is not free.** `PlaceCardPhoto` flattens attribution into one `String` (PlaceCardModel.swift:168). Carrying `licenseName` and `licenseURL` through to the card is a Core model change plus a rewrite of `attributionParts`. It is still no new *data*: `licenseURL` is already decoded, already host-allowlisted to creativecommons.org, and already checked against the licence code (MakingTracksTiles.swift:1867-1868).

**Flag for Rob, not a decision this design makes.** `docs/privacy.md:84` says source data is shown as plain text. Making a data-supplied URL tappable is a change to that commitment, even with the existing allowlist. The OSS credits screen already applies an `https` scheme guard to link targets; the same guard applies here. If Rob reads privacy.md:84 as binding, the link does not ship and §6 reduces to shortening the line.

Source names carry no URLs, so Rob's outbound link lands for the photo licence only.

## 7. Test delta

### What the order-teeth test forbids today

`testPlaceCardOverhaulRendersHierarchyAndHideAction` (UITests/MakingTracksCoreLoopUITests.swift:181) ends with:

```swift
assertVerticallyOrdered([
    ("title", title), ("type", typeLabel), ("description", description),
    ("photo", photo), ("chips", chips), ("actions", saveButton),
    ("attribution", attribution),
])
```

Strict `minY` ordering across seven elements, adjacent pairs. No two elements may share a baseline. No photo beside the title, no chips inline with the type row.

### What breaks, and needs ratification

**RATIFICATION ITEM 1 — actions leave the ordering assertions.** Pinning puts the bar below attribution in screen coordinates, so `chips < actions < attribution` inverts. This is a change to a hierarchy Rob specified and signed off. It is not an implementation detail.

The case to put: Rob's list has six elements and actions is not one of them. All six keep their exact relative order. The shipped card invented a position for actions, then invented a second one when the first turned out to be unreachable. Removing them from the spine removes the need for both.

Replaced by a **stronger** assertion, not a weaker one: with the card just opened and no scrolling, Save, Seen and (after tapping Seen) Love are hittable, asserted at default size **and** at AXXXL. `scrollToExistence` must not appear. Today's test passes while the core loop is unreachable at AXXXL. The replacement cannot.

**RATIFICATION ITEM 2 — `hideButton.exists` and `hideButton.tap()` break** (test lines 209, 228). Hide is behind the `⋯` overflow. The test must open the menu first. The hidden/undo assertions that follow are unaffected. This is a product change, not just a test change: Hide goes from one tap to two.

**RATIFICATION ITEM 3 — the attribution assertion changes.** `attribution.label.contains("Fixture photo")` (line 218) breaks once the line is a composed element with a Link inside it.

### Remaining teeth, tightened

Six content elements, asserted at **both** text sizes as the same sequence:

```
title < type < description < photo < chips < attribution
```

Today the suite cannot assert one order because there is not one. This is a tightening.

### New tests owed

1. **Reachability.** All three primary actions hittable with zero scrolling, at default and AXXXL. Neuter: remove the `safeAreaInset` so actions return to the ScrollView, the AXXXL assertion goes red.
2. **Bar geometry stability.** Capture the bar frame, tap Seen, wait for the refetch to settle, assert the frame is unchanged. Neuter: restore the conditional Love slot, goes red. Must wait on settled state, not a timeout, or it will flake against the un-optimistic write.
3. **Close the gap in the teeth.** `place-card.add-to-list` is absent from the current test entirely. That is how it drifted. Add it to the existence assertions in its new home.
4. **Attribution Link exists and carries the expected URL** (if Open choice E lands).
5. **Photo slot stability** — frames below the photo do not move between the no-photo and photo-present states (if Open choice D lands as reserve-early).
6. **No-prefetch guard** — no image fetch is issued before a card is opened. This needs network instrumentation that does not exist in the UITest target. Sizeable, unbudgeted, and the standing law has nothing enforcing it today. Recommend it lands as its own work package rather than riding on this one.

### Not a delta

Close moving to an overlay (not in the teeth). Drag indicator. Attribution shortening. Chip tap-target height. Photo height changes.

## 8. Open choices for Rob

All thresholds and point values stay open. This design does not pick numbers.

**A. Detent set.** Keep `[.medium]` (and `[.large]` at AX), or adopt `[.medium, .large]` with a visible drag indicator.
*Recommendation: adopt both.* The card is not resizable today, so a user who wants the attribution has no gesture that reveals it and no affordance suggesting the sheet scrolls. Pinning makes the fold permanent unless the user can resize.
*Tradeoff:* `.presentationBackgroundInteraction` can only stay enabled up through `.medium`, so expanding makes the map inert until the user drags back down. It also reopens a decision already made.

**B. Add to list and Hide behind `⋯`.**
*Recommendation: yes, as designed.* It is the only way three legible slots fit on a 375pt screen.
*Tradeoff:* two shipped one-tap actions become two-tap. That is a direct Principle 3 cost. If the answer is "Hide is never buried", the alternatives are dropping Save from the bar instead, or a four-slot bar with icon-plus-text labels — both worse.

**C. Photo height metric and cap.** The base scaled metric and the maximum fraction of content viewport.
*Recommendation: cap it low enough that name, type and the first lines of description always clear the fold at default size.*
*Tradeoff:* a smaller photo at default size than today's 180pt. The photo is the tourist's main decide-input.

**D. Late-photo jump.** Reserve the slot before bytes exist, or animate the insertion.
*Recommendation: reserve.* It is the only option where nothing below the photo moves.
*Tradeoff:* on a card whose place has no photo record decided later, a reserved box that never fills is worse than no box. Needs a rule for when reservation is triggered.

**E. Attribution Link.** Ship it, or keep plain text per privacy.md:84.
*Recommendation: ship it, with the existing `https` and host allowlist guards.* It is the one line of #171 that never landed, and it shortens the longest element on the card.
*Tradeoff:* it is a change to a written privacy commitment and needs a §9-style decision, not a layout sign-off. It is also the card's first coloured text and therefore the first place the committed WCAG AA 4.5:1 is visibly on the line, with no contrast test and no colour tokens behind it.

**F. Chip tap target.** Chips are `Button`s, not labels (MapScreen.swift:4022-4041), roughly 26-28pt tall, all eight invoking the same `showListPicker = true`.
*Recommendation: give them a 44pt hit area without visually inflating the capsule, and label them so VoiceOver says what activation does.*
*Tradeoff:* there is no minimum-tap-target rule anywhere in this codebase. Adopting 44pt means writing the rule down and testing it, which is scope. Doing nothing ships eight sub-minimum controls that all do the same thing.

**G. VoiceOver order of the pinned bar.** A `safeAreaInset` bar reads **last** in the accessibility tree by default. A VoiceOver user would swipe past description, photo, chips and attribution before reaching Seen.
*Recommendation: set `accessibilitySortPriority` so traversal is name, type, actions, then content.* Without this the design's central claim is untrue for the users it most affects.
*Tradeoff:* traversal order then differs from visual order. That is the correct trade here, but it is a choice.

**H. Action completion feedback.** Every tap awaits a DB write and a refetch. Nothing announces. A VoiceOver user taps Seen and hears nothing, then a Love button appears in the tree unannounced.
*Recommendation: add an announcement on completion.* Small, and pinning makes the latency more conspicuous because the bar is permanently on screen.
*Tradeoff:* the real fix is optimistic update, which is out of scope here and which this design raises the value of.

**I. Description clamp.** Specify one now, or wait for WP-BLURB-B.
*Recommendation: wait.* Clamping a block that renders for nobody, validated against two fixtures, is speculative. Specify the clamp when a real 500-char excerpt exists to test it against.
*Tradeoff:* whoever lands WP-BLURB-B inherits the fold problem.

**J. altNames.** Decoded, capped at 8, never rendered (PlaceCardModel.swift:12).
*Recommendation: delete it from the model, or render one truncated line under the name.* Either is fine. Dead decoded data is not.
*Tradeoff:* rendering it adds a tooth between title and type and pushes everything down. Deleting it is a Core change for no user-visible gain.

## 9. Alternatives considered

Four layouts were designed and judged against four lenses (core loop, accessibility, engineering, fidelity to #171), 10 points each.

| Layout | Score | Why it lost |
|---|---|---|
| **content-first** (recommended) | 29 | Won. Its own weak points — the 5-cell bar geometry and the description clamp — are the two things this document changed. |
| pinned-actions | 27.5 | Same pinned bar, but it spent design effort on a photo loader and an attribution model that do not exist in the app layer, and it proposed making Love imply Seen to keep the row geometry stable. That is a layout constraint rewriting a product rule. Its AXXXL fallback was a scroll region inside the pinned bar, which reintroduces the exact failure the bar exists to remove. |
| adaptive (density tiers) | 25.5 | A density tier derived from measured content height, inside a sheet whose height is animated by a detent drag, with the pinned bar's own height inside the measurement. That cycle has no fixed point. It also demoted actions to an overflow at AXXXL only, which is a capability cut aimed at large-text users. |
| two-detent (progressive disclosure) | 18 | Its discovery affordance was a clipped first line of description. There is no description in production, so the compact detent ends at a clean edge that reads as "that is all there is", with the photo hidden behind a mode nobody knows exists. Its accessibility argument also rested on chips being labels; they are Buttons. |

Ideas taken from the losers are listed in §4.

## 10. Pre-existing defects

| Defect | Fixed here? |
|---|---|
| No outbound attribution link (#171 spec item that never shipped) | **Yes**, subject to Open choice E. Needs a Core model change; no new data. |
| Chips below 44pt tap target, and all eight fire the same action | **Open choice F.** There is no tap-target rule in this codebase to point at. |
| altNames decoded and never rendered | **Open choice J.** Not fixed by default. |
| Raw placeID rendered on the failure state (MapScreen.swift:3969-3972) | **No.** Out of scope. It is a debug affordance in a user-facing string and should be its own ticket. |
| No WCAG AA 4.5:1 contrast test, no colour tokens | **No.** This design adds the card's first coloured text and therefore makes the gap worse. Flagged, not solved. |
| Late-photo layout jump | **Yes**, subject to Open choice D. Note the brief's diagnosis was wrong — the jump is block insertion, not byte arrival. |
| Order test missing the Add-to-list button | **Yes.** Added to the existence assertions in §7. |
| No test guarding the no-prefetch law | **Recommended, not committed.** It needs network instrumentation the UITest target does not have. Should be its own work package. |
| Two element orders shipping at once | **Yes.** Both `isAccessibilitySize` branches around `actionButtons` are deleted. |
| Primary actions below the fold at AXXXL | **Yes.** This is the point of the design. |