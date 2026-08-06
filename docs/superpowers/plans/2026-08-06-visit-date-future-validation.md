# Visit-Date Future Validation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the visit-date editor accept today and earlier local calendar days while preventing and atomically rejecting tomorrow and later.

**Architecture:** A small `MakingTracksData` policy derives today's start, today's final selectable instant, membership, and legacy-selection clamping from an injected date and calendar. Both the SwiftUI picker and `AppDatabase.updateVisitDate` consume that policy, so the UI prevents invalid input while the database owns the invariant.

**Tech Stack:** Swift 6, Foundation `Calendar`, SwiftUI `DatePicker`, GRDB, XCTest, Swift Package Manager, Xcode iOS test gate.

## Global Constraints

- “Future” means a Gregorian calendar day after the injected clock's day in the supplied local time zone, not a raw timestamp comparison and not UTC.
- Every time on today's date is valid; the picker range ends at 23:59:59 on that calendar day.
- An existing future selection is displayed as today but is not written until the user taps Save day.
- A rejected database update changes neither `visited_at` nor `visit_order` and emits no controller change event.
- Do not change Visit date copy, hierarchy, styling, accessibility identifiers, fixture seeding, reorder, or move behavior.
- Add no mock, source-text assertion, schema, migration, or new dependency.
- All simulator access uses `./scripts/sim-lock.sh --seat codex1`; the final gate uses `MT_GATE_MAX_CONCURRENT=3`.

---

### Task 1: Shared Local-Day Policy and Database Invariant

**Files:**
- Create: `ios/Sources/MakingTracksData/VisitDateEditPolicy.swift`
- Create: `ios/Tests/MakingTracksDataTests/VisitDateEditPolicyTests.swift`
- Modify: `ios/Sources/MakingTracksData/Errors.swift:3-11`
- Modify: `ios/Sources/MakingTracksData/Interactions.swift:230-250`
- Modify: `ios/Tests/MakingTracksDataTests/InteractionsTests.swift:447-467`

**Interfaces:**
- Consumes: `AppDatabase.now: @Sendable () -> Date` and the `Calendar` already supplied to `updateVisitDate`.
- Produces: `public struct VisitDateEditPolicy`, `public init(now:calendar:)`, `public let today: Date`, `public let latestSelectableDate: Date`, `public func contains(_:) -> Bool`, `public func clamped(_:) -> Date`, and `AppDatabaseError.futureVisitDate`.

- [ ] **Step 1: Add failing policy tests with literal local-day expectations**

Create `VisitDateEditPolicyTests.swift`. Build dates from literal components using an explicitly time-zoned Gregorian calendar, then assert:

```swift
final class VisitDateEditPolicyTests: XCTestCase {
    func testTodayEndsAtLastSecondAndClampsTomorrowBackToToday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Kuala_Lumpur"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 6, hour: 9
        )))
        let laterToday = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 6, hour: 22
        )))
        let tomorrow = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 7, hour: 9
        )))

        let policy = VisitDateEditPolicy(now: now, calendar: calendar)

        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: policy.latestSelectableDate),
            DateComponents(year: 2026, month: 8, day: 6, hour: 23, minute: 59, second: 59)
        )
        XCTAssertTrue(policy.contains(laterToday))
        XCTAssertFalse(policy.contains(tomorrow))
        XCTAssertEqual(policy.clamped(tomorrow), policy.today)
    }

    func testCalendarDayFollowsSuppliedTimeZoneWhenUTCDateDiffers() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Pacific/Kiritimati"))
        let now = Date(timeIntervalSince1970: 1_775_565_000) // 2026-04-07 12:30 UTC, Apr 8 locally
        let laterLocalToday = Date(timeIntervalSince1970: 1_775_608_200) // 2026-04-08 00:30 UTC, Apr 8 locally

        let policy = VisitDateEditPolicy(now: now, calendar: calendar)

        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day], from: policy.today),
            DateComponents(year: 2026, month: 4, day: 8)
        )
        XCTAssertTrue(policy.contains(laterLocalToday))
    }
}
```

These epoch literals were independently checked with Foundation against both
UTC and `Pacific/Kiritimati`; expected values are not derived through
`VisitDateEditPolicy`.

- [ ] **Step 2: Add the failing database rejection test**

Extend `InteractionsTests` with a real in-memory database whose `now` is fixed. Record a visit with a nonzero `visitOrder`, request tomorrow in the same explicit calendar, and assert the dedicated error plus byte-for-byte stored state:

```swift
func testUpdateVisitDateRejectsTomorrowWithoutMutatingTheVisit() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Kuala_Lumpur"))
    let now = try XCTUnwrap(calendar.date(from: DateComponents(
        year: 2026, month: 8, day: 6, hour: 9
    )))
    let original = try XCTUnwrap(calendar.date(from: DateComponents(
        year: 2026, month: 8, day: 5, hour: 22, minute: 15
    )))
    let tomorrow = try XCTUnwrap(calendar.date(from: DateComponents(
        year: 2026, month: 8, day: 7, hour: 8
    )))
    let db = try AppDatabase.inMemory(now: { now })
    let id = try db.recordVisit(ref("p_future_date"), at: original)
    try db.dbQueue.write { database in
        try database.execute(sql: "UPDATE visits SET visit_order = 7 WHERE id = ?", arguments: [id])
    }

    XCTAssertThrowsError(
        try db.updateVisitDate(id: id, toDayContaining: tomorrow, calendar: calendar)
    ) { error in
        XCTAssertEqual(error as? AppDatabaseError, .futureVisitDate)
    }

    let stored = try XCTUnwrap(db.visit(id: id))
    XCTAssertEqual(stored.visitedAt, original)
    XCTAssertEqual(stored.visitOrder, 7)
}
```

- [ ] **Step 3: Run the focused host tests and verify RED**

Run:

```bash
swift test --package-path ios --filter VisitDateEditPolicyTests
swift test --package-path ios --filter InteractionsTests.testUpdateVisitDateRejectsTomorrowWithoutMutatingTheVisit
```

Expected: the policy target fails to compile because `VisitDateEditPolicy` does not exist; after temporarily limiting the run to the database test if necessary, that test fails because `futureVisitDate` does not exist or the future write succeeds.

- [ ] **Step 4: Add the minimal shared policy**

Create `VisitDateEditPolicy.swift`:

```swift
import Foundation

public struct VisitDateEditPolicy: Sendable {
    public let today: Date
    public let latestSelectableDate: Date

    private let calendar: Calendar

    public init(
        now: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) {
        self.calendar = calendar
        today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        latestSelectableDate = calendar.date(byAdding: .second, value: -1, to: tomorrow) ?? now
    }

    public func contains(_ date: Date) -> Bool {
        calendar.startOfDay(for: date) <= today
    }

    public func clamped(_ date: Date) -> Date {
        contains(date) ? date : today
    }
}
```

- [ ] **Step 5: Enforce the database invariant before the write**

Add `case futureVisitDate` to `AppDatabaseError`. At the start of `updateVisitDate`, before `dbQueue.write`, construct the policy from `now()` and the supplied calendar and fail closed:

```swift
let policy = VisitDateEditPolicy(now: now(), calendar: calendar)
guard policy.contains(targetDay) else {
    throw AppDatabaseError.futureVisitDate
}
```

Leave the existing transaction body and time-of-day/order logic unchanged.

- [ ] **Step 6: Run focused and full host tests and verify GREEN**

Run:

```bash
swift test --package-path ios --filter VisitDateEditPolicyTests
swift test --package-path ios --filter InteractionsTests
swift test --package-path ios
```

Expected: all new focused tests pass and the complete host suite reports zero failures.

- [ ] **Step 7: Commit the independently testable data invariant**

```bash
git add ios/Sources/MakingTracksData/VisitDateEditPolicy.swift \
  ios/Sources/MakingTracksData/Errors.swift \
  ios/Sources/MakingTracksData/Interactions.swift \
  ios/Tests/MakingTracksDataTests/VisitDateEditPolicyTests.swift \
  ios/Tests/MakingTracksDataTests/InteractionsTests.swift
git commit -S -m "fix: reject future visit dates"
```

---

### Task 2: Wire the Ruled Policy Into the Visit-Date Picker

**Files:**
- Modify: `ios/App/Sources/Map/MapScreen.swift:5996-6087`

**Interfaces:**
- Consumes: `VisitDateEditPolicy(now:calendar:)`, `latestSelectableDate`, and `clamped(_:)` from Task 1.
- Produces: a compact `DatePicker` whose selectable range ends at today's last local second and whose initial selection is valid even for a legacy future row.

- [ ] **Step 1: Capture one policy for the editor session**

Add a stored `private let datePolicy: VisitDateEditPolicy`. Extend the private view initializer with defaulted `now` and `calendar` parameters, construct one policy, store it, and initialize state through it:

```swift
init(
    model: MapScreenModel?,
    visit: TrackVisit,
    now: Date = Date(),
    calendar: Calendar = Calendar(identifier: .gregorian),
    onChanged: @escaping @MainActor () async -> Void,
    onDismiss: @escaping @MainActor () -> Void
) {
    let datePolicy = VisitDateEditPolicy(now: now, calendar: calendar)
    self.model = model
    self.onChanged = onChanged
    self.onDismiss = onDismiss
    self.datePolicy = datePolicy
    _visit = State(initialValue: visit)
    _selectedDate = State(initialValue: datePolicy.clamped(visit.visitedAt))
}
```

Keep all current call sites source-compatible through the defaulted parameters.

- [ ] **Step 2: Bound the existing picker without changing its presentation**

Add the range argument to the existing `DatePicker`:

```swift
DatePicker(
    "Visit date",
    selection: Binding(
        get: { selectedDate },
        set: { date in selectedDate = date }
    ),
    in: ...datePolicy.latestSelectableDate,
    displayedComponents: .date
)
```

Do not alter modifiers, accessibility identifiers, overlay text, button copy, or layout.

- [ ] **Step 3: Compile through the full host suite**

Run:

```bash
swift test --package-path ios
git diff --check
```

Expected: the package suite remains green and the diff check emits no output. The app-target compile is verified by the final locked gate because `MapScreen.swift` is not a Swift package target.

- [ ] **Step 4: Commit the picker integration**

```bash
git add ios/App/Sources/Map/MapScreen.swift
git commit -S -m "fix: bound visit picker to today"
```

---

### Task 3: Mutation Proof, Review, and Host Gate

**Files:**
- Modify: `docs/superpowers/phases/pre-phase/tasks.md`
- Modify: GitHub issue #454 body through `gh issue edit`

**Interfaces:**
- Consumes: the exact signed code head from Tasks 1 and 2.
- Produces: regression teeth, review verdict, cap-3 host-gate evidence, and a coherent issue/ledger record ready for PR handoff.

- [ ] **Step 1: Prove the database guard has teeth**

Temporarily remove only the `VisitDateEditPolicy.contains` guard from `AppDatabase.updateVisitDate`, run:

```bash
swift test --package-path ios --filter InteractionsTests.testUpdateVisitDateRejectsTomorrowWithoutMutatingTheVisit
```

Expected: exactly the future-date regression fails because the write succeeds or the expected error is absent. Restore the production source and rerun the focused test green. Confirm `git diff` contains no mutation residue.

- [ ] **Step 2: Run repository checks**

Run the complete Swift package suite, `git diff --check`, the repository agent-law lint named by `AGENTS.md`, and verify the branch still descends from current `origin/ios`. Record exact counts and zero-failure status.

- [ ] **Step 3: Obtain independent adversarial review**

Review the exact signed code head across correctness, time-zone/calendar boundaries, test teeth, Swift concurrency/API scope, UI fidelity, security/privacy, and scope containment. Fix every surviving Critical or Important finding with a fresh RED/GREEN cycle, then re-review the changed head.

- [ ] **Step 4: Run the mandatory fresh host gate**

After confirming codex1 is free with the wrapper status command, run exactly:

```bash
MT_GATE_MAX_CONCURRENT=3 ./scripts/sim-lock.sh --seat codex1 ./scripts/release-gate.sh
```

Record the exact gate-tested code head, Release and Debug build-for-testing results, app/unit and UI counts, failed/skipped counts, artifact lifecycle, and final two-way `FREE` status. Do not touch a simulator outside `sim-lock.sh`.

- [ ] **Step 5: Update durable records and commit**

Append the task transition/evidence line to `docs/superpowers/phases/pre-phase/tasks.md`. Update issue #454's body first with the approved behavior, implementation, acceptance status, and exact verification evidence; do not post running-status comments. Commit the ledger-only change separately so the code-tree hash remains tied to its review and gate evidence.

- [ ] **Step 6: Push and open the draft PR**

Push the signed branch, open a draft PR targeting `ios`, and apply `sourcery-review`, `track-b-ios`, and `wp`. Include the design record, exact reviewed/gate-tested code head, test counts, mutation result, no-mockup ruling, and a `## Taste guesses` section stating there are none.

- [ ] **Step 7: Complete review handoff**

Disposition every Sourcery item and inline thread, verify all required CI checks and labels against the live PR head, append `PR open → review clean → ready-to-merge` transitions to both AMQ and the ledger, and hand the exact final head to planner. Do not self-merge.
