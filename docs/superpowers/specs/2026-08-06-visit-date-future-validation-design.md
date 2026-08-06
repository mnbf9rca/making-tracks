# Visit-Date Future Validation Design

Issue: #454

Status: approved by planner on 2026-08-06; scoped visual exception granted by Rob and recorded in issue #454

## Purpose

The visit-date editor must accept today and earlier calendar days, but never a
later day. The editor should prevent an invalid choice, and the data boundary
must reject a future day even if a caller bypasses the SwiftUI picker.

This is a behavior-only correction to the ratified #221 Visit date surface.
Rob granted the scoped issue-only mockup exception recorded in issue #454:
the only visible change is system-controlled disabled availability in the
stock `DatePicker`; resting pixels, copy, and hierarchy remain unchanged. Any
drawn-pixel, copy, or hierarchy change re-enters the full mockup workflow.

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

## Ruling

Adopt option 3.

### Calendar-day semantics

"Future" is evaluated by Gregorian calendar day in the active local time
zone, not by comparing raw timestamps. Any time on today's date is valid;
tomorrow is invalid. This matters because date editing preserves the original
visit's time-of-day: choosing today at 09:00 for a visit whose preserved time
is 22:00 must still be allowed.

The picker therefore ends at the greatest representable `Date` before the
next local calendar day, not at the current instant or a whole-second
approximation. The data guard compares `startOfDay(target)` with
`startOfDay(now())` using the same calendar supplied to the date-edit
operation.

### View behavior

`TrackVisitDateEditorView` supplies the compact `DatePicker` a closed range
ending immediately before the next local day. Past dates and every instant
of today remain selectable; future days are unavailable.

If an already-invalid future-dated visit reaches this editor from data written
by the old build, its initial picker selection is clamped to today. This keeps
the control inside its declared range and gives the user a direct recovery
path. Nothing is written until Save day is tapped.

The view's visible hierarchy, wording, identifiers, and styling remain
unchanged.

### Data behavior

`AppDatabase.updateVisitDate` checks the requested calendar day before opening
the write transaction. Non-finite dates fail closed, and a future target
throws a dedicated `AppDatabaseError.futureVisitDate`. The visit timestamp and `visit_order`
remain unchanged, and the controller emits no change event because the write
failed.

Today and earlier retain the existing behavior: replace the day, preserve the
time-of-day, and assign the next order only when moving across days.

The rule applies only to visit-date editing. It does not change fixture
seeding, imported legacy data, visit creation, reorder, or move semantics.

## Test design

The policy regressions use literal, explicitly time-zoned fixtures to prove
same-day membership, UTC/local-day divergence, non-finite rejection, the
fractional final instant before tomorrow, and calendar-day arithmetic across
the 23-hour New York DST-start day.

The data-boundary RED lives in `MakingTracksDataTests` against a real in-memory
database and its injected clock. It proves:

1. a target later today is accepted as today's calendar day and preserves the
   visit time-of-day;
2. tomorrow throws `futureVisitDate`; and
3. the rejected write leaves both `visited_at` and `visit_order` unchanged.

A separate Kiritimati boundary fixture uses a target timestamp later than
`now` but on the same supplied local day. It proves the database compares
calendar days rather than raw timestamps or UTC dates.

Removing the database guard must make the tomorrow case write successfully
and fail the regression. Expectations are literal fixture dates and stored
row values; no source-text assertion or mock is used.

The controller regression proves a rejected update emits no change by
performing a succeeding mutation and asserting that its place is the first
stream event. The picker regression mounts the real editor in a
`UIHostingController`, finds the stock `UIDatePicker`, and asserts both its
clamped date and exact maximum. It does not inspect private calendar cells or
source text.

## Verification

After implementation:

1. run the focused data regression red, then green;
2. run the full Swift package suite;
3. prove mutations of the database guard, non-finite guard, fractional-day
   bound, DST arithmetic, post-write event ordering, initial clamp, and picker
   maximum each turn their intended regression red, then restore production;
4. run `git diff --check` and the repository law lint;
5. obtain independent adversarial review of the exact signed code head; and
6. run one fresh codex1 host release gate with
   `MT_GATE_MAX_CONCURRENT=3`, recording Release/build-for-testing status,
   exact app/unit and UI counts, artifact lifecycle, and final seat status.
