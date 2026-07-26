# Loved and Hidden Browsable Surfaces Design

Date: 2026-07-26
Task: T1.9
Issue: #470
Branch: `wp-470-loved-hidden-surfaces`

## Outcome

The Tracks door gains two always-visible virtual rows after the list-creation
row:

- **Loved places**, with an exhaustive count of snapshot-backed places whose
  place-level visit verdict is loved.
- **Hidden places**, styled quietly, with an exhaustive count of
  snapshot-backed hidden places.

Each row opens a dedicated place-level collection. The collections share one
visual component but expose mode-specific management:

- Loved rows remove the loved verdict.
- Hidden rows unhide the place through the live
  `MapScreenModel.setHidden(placeID:hidden:)` path, which delegates to
  `CoreLoopController.setHidden`.

These are virtual collections, not stored lists and not filtered track-event
editors.

## Constraints and ruled behavior

- Add no schema and no migration.
- Loved remains derived from `visits.verdict`.
- Hidden remains derived from the raw-SQL `hidden_places` table joined to
  `place_snapshots`.
- Both query results are place-level, snapshot-backed, validated, and
  deduplicated.
- Loved is exhaustive: a loved place remains in Loved even when it is also
  hidden. Its row identifies the hidden state in metadata.
- Hidden places remain excluded from track geometry, track lists, and list
  progress.
- Unhiding restores ordinary discovery visibility in the same way that Scope's
  include-hidden toggle can reveal a hidden pin. The Scope toggle continues to
  affect map-pin rendering only; it does not change track or list counts.
- The maintenance-only `AppDatabase.unhide(placeID:)` API is not used by live
  UI.
- The existing `PlaceCardSheet.showHiddenMode` seam remains intact. These
  collections own their explicit row actions and do not need to present a
  place card to make hiding reversible.

## Data contracts

Reuse the existing `ListPlace` projection because it already expresses the
place-level data both collections need: stable place ID, validated snapshot
name and category, and current `PinState`.

Add these public `AppDatabase` reads:

```swift
public func lovedPlaces() throws -> [ListPlace]
public func hiddenPlaces() throws -> [ListPlace]
```

`lovedPlaces()` selects snapshot-backed places for which at least one visit has
`verdict = 'loved'`, groups by place, and sorts by the most recent loved visit
date descending, then name and place ID for deterministic ties. It deliberately
does not exclude hidden places.

`hiddenPlaces()` joins `hidden_places` to `place_snapshots` and sorts by
`hidden_at` descending, then name and place ID for deterministic ties.

Both reads build rows through the existing snapshot validation path and obtain
`PinState` in the same database read transaction. Snapshotless or invalid rows
are omitted consistently with stored-list and track-list browsing.

`MapScreenModel` exposes asynchronous wrappers for both reads. The Tracks root
loads the two collections alongside lists and visits, so row counts and
destination payloads come from one reload generation.

## Navigation and component structure

Extend `MapShellDestination` with `.lovedPlaces` and `.hiddenPlaces`. Extend
`TracksDoorRow` with `.lovedPlaces` and `.hiddenPlaces`; the full ruled order is
My tracks, dynamic stored lists, New list, Loved places, Hidden places.

The new destination implementation lives outside the already-large map screen
and door shell in a focused file. A small mode value supplies:

- surface title and icon;
- empty-state title and guidance;
- row/action accessibility identifiers and labels;
- the action to perform.

The shared surface uses:

- Snow material tokens for surface, ink, muted text, accent, and hairlines;
- `Typography.font(for: .sheetTitle)` for the surface title;
- `Typography.font(for: .listRowTitle)` for place names;
- `Typography.font(for: .metadata)` for category and state metadata;
- `MaterialHairlineRow` for every place row;
- a minimum 44-point action target;
- a large navigation detent, already enforced whenever the door has a
  destination.

The Loved action is a filled-heart quiet control labelled
“Remove loved from _Place_”. The Hidden action is a quiet “Unhide” control
labelled “Unhide _Place_”. Decorative leading symbols are accessibility-hidden.
The row remains a container, not a nested navigation button: browsing is the
scrollable place collection and management is the explicit trailing action.

The door rows use the frozen Tracks-door geometry: hairline rows, leading
heart/eye-slash symbols, Newsreader list-row titles, trailing counts, and muted
styling across the whole Hidden row. Both rows render when their count is zero.

## State, actions, and errors

Each destination loads on appearance and supports pull-to-refresh.

On a successful action, remove the row immediately and update the visible
count. Returning to the Tracks root triggers its normal task reload and shows
the same count. On failure, keep the row in place and show a token-styled inline
error:

- “Could not update that loved place.”
- “Could not unhide that place.”

Actions are disabled only for the row currently mutating, preventing duplicate
taps without blocking the rest of the collection.

Empty states:

- Loved: **No loved places yet** — “Love a place you’ve seen and it’ll wait
  here.”
- Hidden: **No hidden places** — “Places you hide will wait here until you
  bring them back.”

## Taste guesses

### Remove rows immediately after success

The built interaction removes a row as soon as its loved/hidden membership is
successfully cleared. This keeps the screen truthful and makes the action's
effect legible. The alternative was to dim or retain the row until dismissal,
which can feel less destructive but leaves a virtual-membership list showing a
place that no longer belongs to it. Failure never removes a row.

### Empty-state voice

The short empty-state copy above uses the product's calm, personal voice while
explaining how a place enters each collection. The alternative was purely
mechanical copy (“No results”), which is terser but does not teach the
relationship to love/hide actions.

The include-hidden/count asymmetry is not a taste guess. T1.9's task row already
rules that unhide restores discovery while hidden places remain excluded from
track and list progress.

## Verification and evidence

Implementation follows query-first TDD:

1. Add failing host tests for both reads before production query code.
2. Prove loved deduplication, hidden/loved overlap, snapshot backing, invalid
   row omission, deterministic ordering, and current pin state.
3. Add app unit tests for door order, counts, destination configuration,
   accessibility copy, and row-removal/error state transitions.
4. Add focused UI coverage that opens both destinations, manages a loved and a
   hidden place, verifies successful row removal, and verifies the Hidden
   round-trip against Scope's include-hidden behavior without changing track or
   list counts.
5. Run `cd ios && swift test` before UI work, then the locked full release gate.

Commit implementation-evidence HTML and PNGs for:

- the Tracks door with both virtual rows at 390×844 and AX5;
- the populated Loved surface at 390×844 and AX5;
- the populated Hidden surface at 390×844 and AX5.

The evidence copies existing T1.8 door geometry and DesignSystem row/token
patterns; it does not amend the frozen design-session renders.
