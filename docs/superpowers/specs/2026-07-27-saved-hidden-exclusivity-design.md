# Saved–hidden exclusivity enforcement design

**Task:** Amendment wave A6  
**Serves:** #517 and #526  
**Status:** Approved by Rob on 2026-07-27; written-spec review passed

## Context

Saving and hiding are alternative triage dispositions. A place may be saved or
hidden, but never both. This exclusion crosses two otherwise independent axes:

- the visit axis remains `unseen ⇄ seen ⇄ loved`;
- hiding remains presentation, so it is available regardless of visit state;
- saving remains list membership;
- the sole cross-axis rule is `saved ⇒ not hidden`.

#517 and the 2026-07-26 design session already ruled the product behavior:

1. Hide is absent while a place is saved.
2. Hide remains available for unsaved seen and loved places.
3. Hidden rows offer Unhide and Save; Save auto-unhides.
4. Existing saved-and-hidden rows auto-unhide without losing user data.
5. Seen marking remains on the place card, not the Hidden list.

Rob approved the remaining enforcement and affordance mechanics on 2026-07-27:
a typed database rejection, four visible place-card slots where required,
tonal Unhide plus quiet Save, and a list picker that stays open until Done.

The written-spec review passed on 2026-07-27 with these binding rulings:

- **No re-hide after membership removal:** *"The auto-unhide fired on explicit
  save intent and already happened atomically; re-hiding on later edits would
  make hiding a side effect of list editing, and hiding must only ever be an
  explicit act. The user who strips every membership ends unsaved-and-visible,
  one tap from re-hiding if that's what they meant."*
- **Defensive saved-and-hidden rendering:** *"Rendered as saved, the stuck
  hidden flag would have no affordance (Hide is absent while saved) and the
  state could never be escaped; rendered as hidden, Unhide is the escape hatch
  that heals the record to a legal state. Defensive rendering should always
  expose the exit."*
- **Loved keeps disabled Un-see:** *"The grammar table's disabled Un-see while
  loved is right — it teaches the dependency (loved implies seen) instead of
  hiding it."*

## Goals

- Make saved-and-hidden coexistence unrepresentable through the public
  interaction API.
- Repair legacy coexistence before any live model reads hidden state.
- Keep save-driven auto-unhide atomic and immediately reflected in live UI
  state.
- Express every ruled action without hiding it in overflow.
- Prove the migration preserves all stored user intent.

## Non-goals

- Do not clear visits or loved verdicts when hiding.
- Do not remove list memberships when hiding; hiding a saved place is rejected.
- Do not duplicate Seen onto Hidden rows.
- Do not add SQLite triggers. The application interaction API remains the
  invariant boundary.
- Do not implement A2's R15/R16 visual state morphology in this package. A6
  changes which actions are present; A2 owns their later morphology.
- Do not remove legacy defensive count and render exclusions. They remain
  harmless protection for corrupt or externally mutated stores.

## Persistence contract

### Typed rejection

Add `AppDatabaseError.savedPlaceCannotBeHidden`.

`AppDatabase.setHidden(place, true)` checks for any `list_items` row for the
place inside its existing write transaction. If one exists, it throws the typed
error before snapshotting or mutating anything. `setHidden(place, false)`
remains idempotent.

The UI normally prevents this call by omitting Hide from saved cards. The
database error is defense in depth: presentation is not the contract boundary,
and a future caller must fail loudly rather than report success for a silent
no-op.

### Atomic save-driven auto-unhide

`AppDatabase.addToList` keeps its existing list validation, snapshot, insert,
and duplicate-membership idempotence in one write transaction. After the insert
or recognized duplicate, it deletes the place's `hidden_places` row in the same
transaction.

The deletion must run for an idempotent pre-existing membership too. This
repairs a legacy coexistence encountered through the live API and ensures the
transaction exits with `saved ⇒ not hidden`.

SQLite write serialization plus the single transaction gives each public
operation a coherent result:

- hide wins only when the place has no membership at the point of its write;
- save always exits with the place unhidden;
- no observer can see the intermediate saved-and-hidden state.

### Migration v6

Register `v6` after `v5`:

```sql
DELETE FROM hidden_places
WHERE EXISTS (
    SELECT 1
    FROM list_items
    WHERE list_items.place_id = hidden_places.place_id
)
```

The migration runs during `AppDatabase` initialization, before
`MapScreenModel` constructs `HiddenMembershipTracker`. It deletes only the
presentation-suppression row. It preserves:

- every list and list membership;
- every visit and verdict;
- every place snapshot;
- unrelated hidden rows;
- all timestamps outside the removed hidden row.

No down migration is introduced. The known migration set becomes
`v1...v6`, while the existing future-version refusal remains unchanged.

## Live state propagation

`MapScreenModel.addToList` mirrors the database's auto-unhide through
`HiddenMembershipTracker`.

When the target is currently hidden, the model begins an optimistic
`hidden = false` transition before calling `CoreLoopController.addToList`.
On failure it rolls the tracker back; on success it keeps the transition.
When the target is not hidden, no hidden-membership marker is created.

The controller continues emitting the changed place ID only after the database
transaction succeeds. The existing observer path then refreshes map features
and cards against tracker and database state without a hidden flash or a stale
Hidden-row count.

## Place-card action grammar

Action composition derives the visit controls independently, then adds the
presentation control. Save remains present because it opens the list editor
whether or not the place already belongs to a list.

| Saved | Hidden | Visit | Actions, in order |
|---|---|---|---|
| no | no | unseen | Save, Seen, Hide |
| no | no | seen | Save, Love, Un-see, Hide |
| no | no | loved | Save, Unlove, disabled Un-see, Hide |
| yes | no | unseen | Save, Seen |
| yes | no | seen | Save, Love, Un-see |
| yes | no | loved | Save, Unlove, disabled Un-see |
| no | yes | unseen | Save, Seen, Unhide |
| no | yes | seen | Save, Love, Un-see, Unhide |
| no | yes | loved | Save, Unlove, disabled Un-see, Unhide |

A saved-and-hidden input is unreachable after migration and public API
enforcement. Defensive rendering treats it as hidden: Unhide remains available
as the escape action, Hide remains absent, and visit facts remain editable.

Unsaved seen and loved cards therefore grow from three to four visible slots.
Hide or Unhide is the single momentary verb and stays rightmost; it is not
buried in More. Under the D-taxonomy this reads as three state controls plus one
verb rather than four peer calls to action. The existing accessibility-size
horizontal-to-vertical reflow stacks all slots.

Existing `place-card.*` accessibility identifiers remain stable.

## Hidden-list actions

Each Hidden hairline row gains two explicit actions:

1. **Unhide** — first and visually stronger, using
   `MaterialTonalButtonStyle`.
2. **Save** — second and quieter, using `MaterialQuietButtonStyle`.

Both are momentary actions, so R16 does not exempt them from the one-filled
action budget. Repeating a filled Unhide button on every row would violate that
budget. The hierarchy instead reflects expected intent: direct unhide is the
common action; save-from-hidden is the deliberate secondary path.

At default text sizes the actions sit horizontally. At accessibility sizes they
stack without overlap or truncation. Both retain at least 44×44-point targets
and use stable identifiers:

- `tracks.hidden.unhide.<placeID>`
- `tracks.hidden.save.<placeID>`

Unhide keeps the existing optimistic pending/error behavior. Save presents the
existing `ListPickerView` for that row's place.

## List-picker behavior

The list picker remains a multi-assignment editing surface and stays open until
the explicit Done action. It must not dismiss after the first membership
selection.

Extend its change callback to report whether the completed operation added or
removed membership. The place-card caller continues refreshing after either
change. The Hidden-list caller removes the row after the first successful
addition, because the database has atomically auto-unhidden it. Later edits in
the still-open picker do not rehide the place, even if the user removes every
membership before tapping Done.

Picker-local errors remain in the picker. A failed add neither removes the
Hidden row nor changes the model's hidden tracker.

## Fixture changes

The managed-places UI fixture currently constructs saved-and-hidden
coexistence. Replace it with representable states:

- a visible saved/loved place for list-progress coverage;
- a hidden loved place with no membership to prove visit orthogonality;
- a hidden ordinary place with no membership for the Save flow.

The fixture must use the same public interactions as production. It must not
insert forbidden rows directly merely to keep superseded UI assertions alive.

## Test strategy

Implementation proceeds test-first.

### Data and migration tests

- Split `testHiddenIsOrthogonalToSavedAndVisitState`:
  - hidden remains orthogonal to visit state;
  - saved membership excludes hiding.
- Prove `setHidden(true)` throws
  `savedPlaceCannotBeHidden` and makes no snapshot or hidden-row mutation.
- Prove saving a hidden place atomically preserves the membership and visit
  state while removing hidden state.
- Prove an idempotent save to an existing membership also repairs hidden state.
- Build a v5 database containing:
  - saved-and-hidden with visits and snapshot;
  - hidden-only;
  - saved-only;
  - unrelated lists and rows.
  Then migrate and assert only the forbidden hidden row is removed.
- Reopen the migrated database and prove v6 is idempotent.

### Core and model tests

- Exhaustively pin the place-card table above, including defensive
  saved-and-hidden input.
- Preserve the loved-to-unseen disabled edge.
- Prove add-to-list optimistic unhide is consumed once on success.
- Prove tracker state and pending markers roll back on failure.
- Preserve changed-place-ID emission after successful transactions.

### App and UI tests

- Prove unsaved unseen, seen, and loved cards expose Hide.
- Prove every saved card omits Hide.
- Prove Hidden cards retain the visit action appropriate to their fact state.
- Prove Hidden rows expose both stable action identifiers and minimum targets.
- Prove Unhide removes the row.
- Prove Save opens the list picker, the first successful add removes the row,
  the picker stays open, and Done closes it.
- Prove default and AX layouts contain every control without intersection.
- Update list-progress and Loved/Hidden assertions to use the representable
  fixture.

## Evidence and review

The PR must include:

- the full host `swift test` result;
- the host simulator gate via
  `./scripts/sim-lock.sh ./scripts/release-gate.sh`;
- default and accessibility renders of the Hidden surface with both actions;
- issue-body acceptance mapping for #517 and #526;
- Sourcery cap-skip evidence per #535 if the weekly cap remains exhausted;
- exact-head Opus review;
- Greptile review because v6 changes stored user data;
- adversarial correctness, security, and test-teeth review evidence.

The PR opens ready with `sourcery-review`, `track-b-ios`, `wp`, and
`greptile-review`. Opus reviews the exact head as a separate handoff. Fable
owns merge.
