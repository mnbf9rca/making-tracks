# Visit-Date Future Validation Design

Issue: #454

Status: proposed; awaiting planner ruling before implementation

## Purpose

The visit-date editor must accept today and earlier calendar days, but never a
later day. The editor should prevent an invalid choice, and the data boundary
must reject a future day even if a caller bypasses the SwiftUI picker.

This is a behavior-only correction to the ratified #221 Visit date surface.
It adds no control, copy, layout, color, or navigation state, so the existing
frozen renders remain authoritative and no new mockup is required.

## Current state

`TrackVisitDateEditorView` uses a compact, date-only `DatePicker` with no
selection range. Saving forwards the selected `Date` through `MapScreenModel`
and `CoreLoopController` to `AppDatabase.updateVisitDate`, which replaces the
stored visit's calendar-day components while preserving its time-of-day.

`AppDatabase` already owns an injected `now` clock for deterministic tests.
The visit-editing functions consistently use a Gregorian calendar whose time
zone follows the user's current environment.

## Options considered

### 1. Constrain the picker only

Add an upper bound to the compact picker and make no data-layer change.

This gives the right interaction, but leaves `updateVisitDate` able to persist
a future day through any other caller or a later UI regression. It does not
make the invariant belong to the data it protects.

### 2. Validate only when saving

Allow the picker to navigate into the future, then reject the save.

This protects storage, but presents an impossible choice and turns an obvious
constraint into a generic error after the user acts. It is needlessly hostile
for a date-only control.

### 3. Constrain the picker and validate storage

The picker exposes only today and earlier, while `AppDatabase` independently
rejects a target whose calendar day is after the injected clock's calendar
day.

This is the recommended design. Each layer owns a distinct responsibility:
the view prevents invalid input and the database preserves the invariant.

## Proposed ruling

Adopt option 3.

### Calendar-day semantics

"Future" is evaluated by Gregorian calendar day in the active local time
zone, not by comparing raw timestamps. Any time on today's date is valid;
tomorrow is invalid. This matters because date editing preserves the original
visit's time-of-day: choosing today at 09:00 for a visit whose preserved time
is 22:00 must still be allowed.

The picker therefore ends at the end of the current calendar day, not at the
current instant. The data guard compares `startOfDay(target)` with
`startOfDay(now())` using the same calendar supplied to the date-edit
operation.

### View behavior

`TrackVisitDateEditorView` supplies the compact `DatePicker` a closed range
ending at the current day's end. Past dates and today remain selectable;
future days are unavailable.

If an already-invalid future-dated visit reaches this editor from data written
by the old build, its initial picker selection is clamped to today. This keeps
the control inside its declared range and gives the user a direct recovery
path. Nothing is written until Save day is tapped.

The view's visible hierarchy, wording, identifiers, and styling remain
unchanged.

### Data behavior

`AppDatabase.updateVisitDate` checks the requested calendar day before opening
the write transaction. A future target throws a dedicated
`AppDatabaseError.futureVisitDate`. The visit timestamp and `visit_order`
remain unchanged, and the controller emits no change event because the write
failed.

Today and earlier retain the existing behavior: replace the day, preserve the
time-of-day, and assign the next order only when moving across days.

The rule applies only to visit-date editing. It does not change fixture
seeding, imported legacy data, visit creation, reorder, or move semantics.

## Test design

The behavioral RED lives in `MakingTracksDataTests` against a real in-memory
database and its injected clock. With a literal local calendar fixture it
will prove:

1. a target later today is accepted as today's calendar day and preserves the
   visit time-of-day;
2. tomorrow throws `futureVisitDate`; and
3. the rejected write leaves both `visited_at` and `visit_order` unchanged.

Removing the database guard must make the tomorrow case write successfully
and fail the regression. Expectations are literal fixture dates and stored
row values; no source-text assertion or mock is used.

The picker bound is a direct SwiftUI framework contract rather than a second
date-validation implementation. The full simulator gate exercises the mounted
editor and its existing accessibility identity; the durable regression oracle
remains the caller-independent database behavior instead of a brittle test of
system calendar-cell accessibility.

## Verification

After implementation:

1. run the focused data regression red, then green;
2. run the full Swift package suite;
3. prove the missing-guard mutation turns the intended regression red and
   restore the production source;
4. run `git diff --check` and the repository law lint;
5. obtain independent adversarial review of the exact signed code head; and
6. run one fresh codex1 host release gate with
   `MT_GATE_MAX_CONCURRENT=3`, recording Release/build-for-testing status,
   exact app/unit and UI counts, artifact lifecycle, and final seat status.

