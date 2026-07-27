# A6 Saved–Hidden Exclusivity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enforce saved-and-hidden mutual exclusivity from migration and database interactions through the place card and Hidden list, while preserving visits, snapshots, list intent, and multi-list editing.

**Architecture:** `AppDatabase` is the invariant boundary: v6 repairs legacy stores, `setHidden(true)` rejects saved places, and `addToList` auto-unhides in the membership transaction. `MapScreenModel` mirrors the committed auto-unhide through `HiddenMembershipTracker`; pure place-card composition and Hidden-list UI then expose only legal actions plus a defensive Unhide escape for corrupt saved-and-hidden input.

**Tech Stack:** Swift 6, GRDB, SwiftUI, XCTest/XCUITest, MapLibre-backed iOS simulator gate.

## Global Constraints

- App work stays on `wp-517-saved-hidden-exclusivity`, based on current `origin/ios`, and the PR targets `ios`.
- Run all simulator operations through `./scripts/sim-lock.sh`; never call `simctl` directly.
- Use test-driven development: observe each focused test fail before writing its implementation.
- `saved ⇒ not hidden`; visits and loved verdicts remain orthogonal to hidden state.
- `savedPlaceCannotBeHidden` is a typed error; a saved hide attempt is never a silent no-op.
- Saving a hidden place auto-unhides atomically; later membership removal never re-hides it.
- Hidden corrupt input renders Unhide as its escape; loved retains disabled Un-see.
- Unsaved Seen/Loved cards show four slots; Hide is the rightmost quiet verb.
- Hidden rows use tonal Unhide and quiet Save; the list picker remains open until Done.
- No SQLite triggers, no membership ejection, no visit clearing, and no duplicate Seen action in the Hidden list.
- Keep all existing `place-card.*` identifiers; add `tracks.hidden.save.<placeID>`.
- Release builds treat warnings as errors.
- Required review/evidence: full host tests, full host simulator gate, default and AX Hidden renders, exact-head Opus, Greptile, Sourcery accounting per #535, and adversarial correctness/security/test-teeth review.

## File Structure

- `ios/Sources/MakingTracksData/Errors.swift` — owns the new typed invariant error.
- `ios/Sources/MakingTracksData/Interactions.swift` — owns transaction-level rejection and save-driven auto-unhide.
- `ios/Sources/MakingTracksData/Migrations.swift` — owns v6 legacy repair.
- `ios/Tests/MakingTracksDataTests/InteractionsTests.swift` — proves the public interaction contract.
- `ios/Tests/MakingTracksDataTests/MigrationsTests.swift` — proves v6 preservation and migration bookkeeping.
- `ios/Sources/MakingTracksCore/PlaceCardActionSlots.swift` — derives the legal card grammar.
- `ios/Tests/MakingTracksCoreTests/PlaceCardActionSlotsTests.swift` — exhaustively pins the grammar table.
- `ios/App/Sources/Map/MapScreen.swift` — mirrors auto-unhide and reports list-picker membership direction.
- `ios/App/Sources/Map/HiddenMembershipTracker.swift` — retains the existing optimistic rollback primitive; no new persistence responsibility.
- `ios/App/Sources/Map/ManagedPlacesView.swift` — adds Hidden-row action hierarchy and picker presentation.
- `ios/App/Sources/PlaceCard/PlaceCardSheet.swift` — adopts the directional list-picker callback without changing card identifiers.
- `ios/App/Sources/MakingTracksApp.swift` — replaces the forbidden managed-places fixture.
- `ios/App/Tests/AppShellTests.swift` — proves live-state rollback and Hidden-row state behavior.
- `ios/App/UITests/MakingTracksCoreLoopUITests.swift` — proves the user flows, AX geometry, and screenshot exports.
- `docs/design/design-system/a6-hidden-actions.png` and `docs/design/design-system/a6-hidden-actions-ax.png` — checked-in implementation renders.
- `docs/superpowers/phases/phase-1/amendment-wave.md` — advances only A6's builder-owned status.

---

### Task 1: Enforce the interaction invariant

**Files:**
- Modify: `ios/Sources/MakingTracksData/Errors.swift:3`
- Modify: `ios/Sources/MakingTracksData/Interactions.swift:159-184`
- Modify: `ios/Sources/MakingTracksData/Interactions.swift:309-326`
- Test: `ios/Tests/MakingTracksDataTests/InteractionsTests.swift:545-584`

**Interfaces:**
- Consumes: `AppDatabase.dbQueue`, `PlaceRef.placeID`, `AppDatabase.wantToGoListID()`.
- Produces: `AppDatabaseError.savedPlaceCannotBeHidden`; `addToList(_:listID:)` exits with the place unhidden; `setHidden(_:true)` throws for any saved place.

- [ ] **Step 1: Replace the superseded orthogonality test with failing contract tests**

```swift
func testHiddenRemainsOrthogonalToVisitState() throws {
    let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })
    let place = try ref("p_hidden_loved")
    _ = try db.recordVisit(place, verdict: .loved)

    try db.setHidden(place, true)
    XCTAssertEqual(
        try db.viewportState([place.placeID])[place.placeID],
        PinState(saved: false, visit: .loved, hidden: true)
    )

    try db.setHidden(place, false)
    XCTAssertEqual(
        try db.viewportState([place.placeID])[place.placeID],
        PinState(saved: false, visit: .loved, hidden: false)
    )
}

func testSavedPlaceCannotBeHiddenAndRejectedWriteDoesNotSnapshot() throws {
    let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })
    let place = try ref("p_saved_hide_rejected")
    let listID = try db.wantToGoListID()
    try db.dbQueue.write {
        try $0.execute(
            sql: "INSERT INTO list_items (list_id, place_id, added_at) VALUES (?, ?, ?)",
            arguments: [listID, place.placeID, Date(timeIntervalSince1970: 50)]
        )
    }

    XCTAssertThrowsError(try db.setHidden(place, true)) { error in
        guard let databaseError = error as? AppDatabaseError else {
            return XCTFail("Expected AppDatabaseError, got \(error)")
        }
        XCTAssertEqual(String(describing: databaseError), "savedPlaceCannotBeHidden")
    }
    XCTAssertEqual(try db.hiddenPlaceIDs(), [])
    XCTAssertNil(try db.snapshot(for: place.placeID))
}

func testSavingHiddenPlaceAutoUnhidesAndPreservesLovedVisit() throws {
    let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })
    let place = try ref("p_hidden_then_saved")
    _ = try db.recordVisit(place, verdict: .loved)
    try db.setHidden(place, true)

    try db.addToList(place, listID: try db.wantToGoListID())

    XCTAssertEqual(
        try db.viewportState([place.placeID])[place.placeID],
        PinState(saved: true, visit: .loved, hidden: false)
    )
}

func testIdempotentSaveRepairsLegacySavedAndHiddenCoexistence() throws {
    let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })
    let place = try ref("p_legacy_coexistence")
    let listID = try db.wantToGoListID()
    try db.addToList(place, listID: listID)
    try db.dbQueue.write {
        try $0.execute(
            sql: "INSERT INTO hidden_places (place_id, hidden_at) VALUES (?, ?)",
            arguments: [place.placeID, Date(timeIntervalSince1970: 75)]
        )
    }

    try db.addToList(place, listID: listID)

    XCTAssertEqual(try db.listMemberships(containing: place.placeID), [listID])
    XCTAssertFalse(try db.hiddenPlaceIDs().contains(place.placeID))
}

func testRemovingLastMembershipAfterSaveDoesNotRehidePlace() throws {
    let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })
    let place = try ref("p_hidden_save_then_remove")
    let listID = try db.wantToGoListID()
    try db.setHidden(place, true)
    try db.addToList(place, listID: listID)

    try db.removeFromList(placeID: place.placeID, listID: listID)

    XCTAssertEqual(
        try db.viewportState([place.placeID])[place.placeID],
        PinState(saved: false, visit: .none, hidden: false)
    )
}
```

- [ ] **Step 2: Run the five interaction tests and verify RED**

Run:

```bash
cd ios
swift test --filter 'InteractionsTests/(testHiddenRemainsOrthogonalToVisitState|testSavedPlaceCannotBeHiddenAndRejectedWriteDoesNotSnapshot|testSavingHiddenPlaceAutoUnhidesAndPreservesLovedVisit|testIdempotentSaveRepairsLegacySavedAndHiddenCoexistence|testRemovingLastMembershipAfterSaveDoesNotRehidePlace)'
```

Expected: the visit-only test passes; the typed-error test fails because no
error is thrown; both auto-unhide tests and the later-removal test fail with
`hidden == true`.

- [ ] **Step 3: Add the typed error and minimal transaction enforcement**

```swift
public enum AppDatabaseError: Error, Equatable {
    case databaseFromNewerAppVersion(unknown: Set<String>)
    case unreadableDatabase
    case invalidListName
    case emptyListName
    case listNameTooLong
    case systemListIsProtected
    case savedPlaceCannotBeHidden
}
```

In `addToList`, execute this after the insert or recognized duplicate, still inside the existing write transaction:

```swift
try db.execute(
    sql: "DELETE FROM hidden_places WHERE place_id = ?",
    arguments: [place.placeID]
)
```

At the start of the `hidden == true` branch in `setHidden`:

```swift
let isSaved = try Bool.fetchOne(
    db,
    sql: "SELECT EXISTS(SELECT 1 FROM list_items WHERE place_id = ?)",
    arguments: [place.placeID]
) ?? false
guard !isSaved else {
    throw AppDatabaseError.savedPlaceCannotBeHidden
}
```

- [ ] **Step 4: Rerun the focused interaction tests and verify GREEN**

Run the Step 2 command.

Expected: 5 selected tests pass with no warnings.

- [ ] **Step 5: Run the whole data interaction suite**

Run:

```bash
cd ios
swift test --filter InteractionsTests
```

Expected: every `InteractionsTests` case passes.

- [ ] **Step 6: Commit the interaction boundary**

```bash
git add ios/Sources/MakingTracksData/Errors.swift ios/Sources/MakingTracksData/Interactions.swift ios/Tests/MakingTracksDataTests/InteractionsTests.swift
git commit -m "feat(data): enforce saved-hidden exclusivity"
```

---

### Task 2: Repair legacy stores with migration v6

**Files:**
- Modify: `ios/Sources/MakingTracksData/Migrations.swift:91-96`
- Modify: `ios/Tests/MakingTracksDataTests/MigrationsTests.swift:1-222`

**Interfaces:**
- Consumes: v5 tables `list_items`, `hidden_places`, `visits`, and `place_snapshots`.
- Produces: migration identifier `v6`; every migrated store satisfies `saved ⇒ not hidden`.

- [ ] **Step 1: Add a failing v5 preservation fixture**

Add this complete helper inside `MigrationsTests`:

```swift
private func makeV5Queue() throws -> DatabaseQueue {
    let queue = try DatabaseQueue()
    let timestamp = Date(timeIntervalSince1970: 12)
    try queue.write { db in
        try db.execute(
            sql: "CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY)"
        )
        try db.execute(
            sql: """
                INSERT INTO grdb_migrations (identifier)
                VALUES ('v1'), ('v2'), ('v3'), ('v4'), ('v5')
                """
        )
        try db.create(table: "visits") { table in
            table.autoIncrementedPrimaryKey("id")
            table.column("place_id", .text).notNull()
            table.column("visited_at", .datetime).notNull()
            table.column("verdict", .text)
            table.column("created_at", .datetime).notNull()
            table.column("visit_order", .integer).notNull().defaults(to: 0)
        }
        try db.create(index: "idx_visits_place", on: "visits", columns: ["place_id"])
        try db.create(table: "lists") { table in
            table.autoIncrementedPrimaryKey("id")
            table.column("name", .text).notNull()
            table.column("is_system", .boolean).notNull().defaults(to: false)
            table.column("created_at", .datetime).notNull()
            table.column("list_kind", .text).notNull().defaults(to: "collection")
        }
        try db.create(table: "list_items") { table in
            table.column("list_id", .integer).notNull()
                .references("lists", onDelete: .cascade)
            table.column("place_id", .text).notNull()
            table.column("added_at", .datetime).notNull()
            table.primaryKey(["list_id", "place_id"])
        }
        try db.create(index: "idx_list_items_place", on: "list_items", columns: ["place_id"])
        try db.create(table: "place_snapshots") { table in
            table.column("place_id", .text).primaryKey()
            table.column("name", .text).notNull()
            table.column("lat", .double).notNull()
            table.column("lon", .double).notNull()
            table.column("category", .text).notNull()
            table.column("tier", .integer).notNull()
            table.column("snapshot_json", .text).notNull()
            table.column("snapshot_schema_version", .integer).notNull()
            table.column("fetched_at", .datetime).notNull()
        }
        try db.create(table: "hidden_places") { table in
            table.column("place_id", .text).primaryKey()
            table.column("hidden_at", .datetime).notNull()
        }
        try db.execute(
            sql: """
                INSERT INTO lists (id, name, is_system, created_at, list_kind)
                VALUES
                    (1, 'Want to go', 1, ?, 'collection'),
                    (2, 'Weekend', 0, ?, 'collection'),
                    (3, 'My tracks', 1, ?, 'track')
                """,
            arguments: [timestamp, timestamp, timestamp]
        )
        try db.execute(
            sql: """
                INSERT INTO list_items (list_id, place_id, added_at)
                VALUES (2, 'coexisting', ?), (2, 'saved-only', ?)
                """,
            arguments: [timestamp, timestamp]
        )
        try db.execute(
            sql: """
                INSERT INTO hidden_places (place_id, hidden_at)
                VALUES ('coexisting', ?), ('hidden-only', ?)
                """,
            arguments: [timestamp, timestamp]
        )
        try db.execute(
            sql: """
                INSERT INTO visits
                    (id, place_id, visited_at, verdict, created_at, visit_order)
                VALUES (10, 'coexisting', ?, 'loved', ?, 4)
                """,
            arguments: [timestamp, timestamp]
        )
        for (placeID, name) in [
            ("coexisting", "Coexisting"),
            ("saved-only", "Saved only"),
            ("hidden-only", "Hidden only"),
        ] {
            try db.execute(
                sql: """
                    INSERT INTO place_snapshots
                        (place_id, name, lat, lon, category, tier, snapshot_json,
                         snapshot_schema_version, fetched_at)
                    VALUES (?, ?, 51.5, -0.1, 'memorial', 2, '{}', 1, ?)
                    """,
                arguments: [placeID, name, timestamp]
            )
        }
    }
    return queue
}
```

Then add the preservation test:

```swift
func testV5MigrationAutoUnhidesSavedRowsWithoutDestroyingUserData() throws {
    let timestamp = Date(timeIntervalSince1970: 12)
    let queue = try makeV5Queue()
    let db = try AppDatabase(queue, now: { Date(timeIntervalSince1970: 100) })

    XCTAssertEqual(try db.appliedMigrations, ["v1", "v2", "v3", "v4", "v5", "v6"])
    XCTAssertEqual(try db.hiddenPlaceIDs(), ["hidden-only"])
    XCTAssertEqual(try db.listMemberships(containing: "coexisting"), [2])
    XCTAssertEqual(try db.listMemberships(containing: "saved-only"), [2])
    XCTAssertEqual(
        try db.viewportState(["coexisting"])["coexisting"],
        PinState(saved: true, visit: .loved, hidden: false)
    )
    XCTAssertEqual(try db.snapshot(for: "coexisting")?.name, "Coexisting")
    XCTAssertEqual(try db.snapshot(for: "saved-only")?.name, "Saved only")
    XCTAssertEqual(try db.snapshot(for: "hidden-only")?.name, "Hidden only")

    let visit = try XCTUnwrap(try db.visit(id: 10))
    XCTAssertEqual(visit.visitedAt, timestamp)
    XCTAssertEqual(visit.createdAt, timestamp)
    XCTAssertEqual(visit.visitOrder, 4)
    let preserved = try db.dbQueue.read { database in
        (
            lists: try String.fetchAll(
                database,
                sql: "SELECT name FROM lists ORDER BY id"
            ),
            weekendCreatedAt: try Date.fetchOne(
                database,
                sql: "SELECT created_at FROM lists WHERE id = 2"
            ),
            coexistingAddedAt: try Date.fetchOne(
                database,
                sql: """
                    SELECT added_at FROM list_items
                    WHERE list_id = 2 AND place_id = 'coexisting'
                    """
            ),
            hiddenOnlyHiddenAt: try Date.fetchOne(
                database,
                sql: "SELECT hidden_at FROM hidden_places WHERE place_id = 'hidden-only'"
            )
        )
    }
    XCTAssertEqual(preserved.lists, ["Want to go", "Weekend", "My tracks"])
    XCTAssertEqual(preserved.weekendCreatedAt, timestamp)
    XCTAssertEqual(preserved.coexistingAddedAt, timestamp)
    XCTAssertEqual(preserved.hiddenOnlyHiddenAt, timestamp)
    XCTAssertEqual(try db.snapshot(for: "coexisting")?.fetchedAt, timestamp)

    let reopened = try AppDatabase(queue, now: { Date(timeIntervalSince1970: 200) })
    XCTAssertEqual(try reopened.hiddenPlaceIDs(), ["hidden-only"])
    XCTAssertEqual(try reopened.appliedMigrations, ["v1", "v2", "v3", "v4", "v5", "v6"])
}
```

- [ ] **Step 2: Update existing migration expectations to the new current schema**

Change every exact migration-set assertion from:

```swift
["v1", "v2", "v3", "v4", "v5"]
```

to:

```swift
["v1", "v2", "v3", "v4", "v5", "v6"]
```

In `testV2DatabaseMigratesToCurrentSchemaWithoutLosingHiddenOrCustomListRows`, rename the test to `testV2DatabaseMigratesToCurrentSchemaAndRepairsSavedHiddenOverlap`, assert `hiddenPlaceIDs()` is empty, and keep the custom-list membership assertion `[2]`.

- [ ] **Step 3: Run migration tests and verify RED**

Run:

```bash
cd ios
swift test --filter MigrationsTests
```

Expected: failures report missing `v6` and the legacy `coexisting` hidden row still present.

- [ ] **Step 4: Register the minimal repair migration**

Add after v5:

```swift
register("v6") { db in
    try db.execute(
        sql: """
            DELETE FROM hidden_places
            WHERE EXISTS (
                SELECT 1
                FROM list_items
                WHERE list_items.place_id = hidden_places.place_id
            )
            """
    )
}
```

- [ ] **Step 5: Rerun migration tests and verify GREEN**

Run the Step 3 command.

Expected: all `MigrationsTests` pass, including reopen idempotence.

- [ ] **Step 6: Commit the migration**

```bash
git add ios/Sources/MakingTracksData/Migrations.swift ios/Tests/MakingTracksDataTests/MigrationsTests.swift
git commit -m "feat(data): migrate saved-hidden overlap"
```

---

### Task 3: Derive the complete place-card grammar

**Files:**
- Modify: `ios/Sources/MakingTracksCore/PlaceCardActionSlots.swift:65-83`
- Modify: `ios/Tests/MakingTracksCoreTests/PlaceCardActionSlotsTests.swift:5-76`

**Interfaces:**
- Consumes: `PinState(saved:visit:hidden:)`.
- Produces: `PlaceCardActionSlots.actions` with visit controls independent of Hide/Unhide and saved gating.

- [ ] **Step 1: Replace the partial slot tests with a failing exhaustive table**

```swift
func testActionSlotsCoverSavedHiddenAndVisitAxes() {
    let cases: [(PinState, [PlaceCardAction])] = [
        (PinState(saved: false, visit: .none, hidden: false), [.save, .seen, .hide]),
        (PinState(saved: false, visit: .visited, hidden: false), [.save, .love, .unsee(isEnabled: true), .hide]),
        (PinState(saved: false, visit: .loved, hidden: false), [.save, .unlove, .unsee(isEnabled: false), .hide]),
        (PinState(saved: true, visit: .none, hidden: false), [.save, .seen]),
        (PinState(saved: true, visit: .visited, hidden: false), [.save, .love, .unsee(isEnabled: true)]),
        (PinState(saved: true, visit: .loved, hidden: false), [.save, .unlove, .unsee(isEnabled: false)]),
        (PinState(saved: false, visit: .none, hidden: true), [.save, .seen, .unhide]),
        (PinState(saved: false, visit: .visited, hidden: true), [.save, .love, .unsee(isEnabled: true), .unhide]),
        (PinState(saved: false, visit: .loved, hidden: true), [.save, .unlove, .unsee(isEnabled: false), .unhide]),
        (PinState(saved: true, visit: .none, hidden: true), [.save, .seen, .unhide]),
        (PinState(saved: true, visit: .visited, hidden: true), [.save, .love, .unsee(isEnabled: true), .unhide]),
        (PinState(saved: true, visit: .loved, hidden: true), [.save, .unlove, .unsee(isEnabled: false), .unhide]),
    ]

    for (state, expected) in cases {
        XCTAssertEqual(PlaceCardActionSlots(pinState: state).actions, expected, "\(state)")
    }
}
```

Keep the focused assertion that loved exposes disabled Un-see.

- [ ] **Step 2: Run the slot tests and verify RED**

Run:

```bash
cd ios
swift test --filter PlaceCardActionSlotsTests
```

Expected: unsaved visited/loved lack Hide; saved unseen still exposes Hide; hidden uses disabled Seen instead of the visit action.

- [ ] **Step 3: Implement independent visit and presentation composition**

```swift
public init(pinState: PinState) {
    var next: [PlaceCardAction] = [.save]
    switch pinState.visit {
    case .none:
        next.append(.seen)
    case .visited:
        next.append(contentsOf: [.love, .unsee(isEnabled: true)])
    case .loved:
        next.append(contentsOf: [.unlove, .unsee(isEnabled: false)])
    }

    if pinState.hidden {
        next.append(.unhide)
    } else if !pinState.saved {
        next.append(.hide)
    }
    actions = next
}
```

Retain `seenDisabled` in `PlaceCardAction`; A2 still owns the vocabulary.

- [ ] **Step 4: Rerun core tests and verify GREEN**

Run:

```bash
cd ios
swift test --filter PlaceCardActionSlotsTests
swift test --filter MakingTracksCoreTests
```

Expected: both commands pass.

- [ ] **Step 5: Commit the action grammar**

```bash
git add ios/Sources/MakingTracksCore/PlaceCardActionSlots.swift ios/Tests/MakingTracksCoreTests/PlaceCardActionSlotsTests.swift
git commit -m "feat(core): gate hide by saved state"
```

---

### Task 4: Mirror auto-unhide in live map state

**Files:**
- Modify: `ios/App/Sources/Map/MapScreen.swift:9061-9068`
- Test: `ios/App/Tests/AppShellTests.swift`

**Interfaces:**
- Consumes: `HiddenMembershipTracker.hiddenIDs`, `beginSetHidden(placeID:hidden:)`, and `rollback(_:)`.
- Produces: `MapScreenModel.addToList(placeID:listID:)` optimistically removes hidden membership only when needed and restores it on failure.

- [ ] **Step 1: Add failing model-level success and rollback tests**

```swift
@MainActor
func testAddingHiddenPlaceToListMirrorsAutoUnhideAndMarksOneRefresh() async throws {
    let database = try AppDatabase.inMemory()
    let place = try PlaceRef(
        placeID: "hidden-save",
        name: "Hidden save",
        lat: 51.5,
        lon: -0.1,
        category: "memorial",
        tier: 2,
        schemaVersion: 1,
        fetchedAt: Date(timeIntervalSince1970: 1),
        rawJSON: "{}"
    )
    try database.setHidden(place, true)
    let model = try MapScreenModel(database: database, fixturePlaces: [place])

    try await model.addToList(placeID: place.placeID, listID: database.wantToGoListID())

    XCTAssertFalse(model.hiddenIDs.contains(place.placeID))
    XCTAssertTrue(model.consumeHiddenMembershipChange(overlapping: [place.placeID]))
    XCTAssertFalse(model.consumeHiddenMembershipChange(overlapping: [place.placeID]))
}

@MainActor
func testFailedSaveRollsBackOptimisticAutoUnhide() async throws {
    let database = try AppDatabase.inMemory()
    let place = try PlaceRef(
        placeID: "hidden-save-failure",
        name: "Hidden save failure",
        lat: 51.5,
        lon: -0.1,
        category: "memorial",
        tier: 2,
        schemaVersion: 1,
        fetchedAt: Date(timeIntervalSince1970: 1),
        rawJSON: "{}"
    )
    try database.setHidden(place, true)
    let model = try MapScreenModel(database: database, fixturePlaces: [place])
    let lists = await model.lists()
    let trackListID = try XCTUnwrap(
        lists.first { $0.isSystem && $0.kind == PlaceList.trackKind }?.id
    )

    do {
        try await model.addToList(placeID: place.placeID, listID: trackListID)
        XCTFail("Expected protected track-list write to fail")
    } catch {
        XCTAssertEqual(error as? AppDatabaseError, .systemListIsProtected)
    }

    XCTAssertTrue(model.hiddenIDs.contains(place.placeID))
    XCTAssertFalse(model.consumeHiddenMembershipChange(overlapping: [place.placeID]))
}
```

- [ ] **Step 2: Run the two app tests and verify RED**

Run:

```bash
./scripts/sim-lock.sh xcodebuild test \
  -project ios/App/MakingTracks.xcodeproj \
  -scheme MakingTracks \
  -destination 'platform=iOS Simulator,id=C4A64D49-24A2-4429-B6E2-AD9A14142A99' \
  -parallel-testing-enabled NO \
  -disable-concurrent-destination-testing \
  -only-testing:MakingTracksTests/AppShellTests
```

Expected: the success case finds stale `model.hiddenIDs`; the failure case may pass before optimistic state is introduced.

- [ ] **Step 3: Add rollback-protected tracker mirroring**

Replace `MapScreenModel.addToList` with:

```swift
func addToList(placeID: String, listID: Int64) async throws {
    guard let placeRef = await actionPlaceRef(for: placeID) else {
        throw MapScreenActionError.placeUnavailable
    }
    let rollback = hiddenTracker.hiddenIDs.contains(placeID)
        ? hiddenTracker.beginSetHidden(placeID: placeID, hidden: false)
        : nil
    do {
        try coreLoop.addToList(placeRef, listID: listID)
    } catch {
        if let rollback {
            hiddenTracker.rollback(rollback)
        }
        throw error
    }
    MakingTracksLog.flowEvent("verdict changed", fields: placeFields(placeRef) + [
        .public("action", "add-to-list"),
        .public("listID", String(listID)),
    ])
}
```

- [ ] **Step 4: Rerun the app tests and verify GREEN**

Run the Step 2 command.

Expected: all `AppShellTests` pass.

- [ ] **Step 5: Commit live-state propagation**

```bash
git add ios/App/Sources/Map/MapScreen.swift ios/App/Tests/AppShellTests.swift
git commit -m "feat(app): mirror save-driven auto-unhide"
```

---

### Task 5: Add directional list-picker changes and Hidden-row actions

**Files:**
- Modify: `ios/App/Sources/Map/MapScreen.swift:7714-7800`
- Modify: `ios/App/Sources/Map/ManagedPlacesView.swift:153-355`
- Modify: `ios/App/Sources/PlaceCard/PlaceCardSheet.swift:260-271`
- Modify: `ios/App/Tests/AppShellTests.swift`

**Interfaces:**
- Produces: `enum ListPickerMembershipChange { case added(listID: Int64); case removed(listID: Int64) }`.
- Produces: `ListPickerView.onChanged: @MainActor (ListPickerMembershipChange) -> Void`.
- Produces: `ManagedPlacesState.removePlace(placeID:)`.
- Consumes: `MaterialTonalButtonStyle`, `MaterialQuietButtonStyle`, and `ListPlace.id`.

- [ ] **Step 1: Add failing unit tests for directional row state**

```swift
func testManagedPlacesStateRemovesHiddenRowAfterSaveAddition() {
    let hidden = ListPlace(
        placeID: "hidden",
        name: "Hidden",
        category: "memorial",
        pinState: PinState(saved: false, visit: .none, hidden: true)
    )
    var state = ManagedPlacesState(places: [hidden])

    state.removePlace(placeID: hidden.placeID)

    XCTAssertTrue(state.places.isEmpty)
}

func testListPickerMembershipChangeMapsPriorMembershipToCompletedDirection() {
    XCTAssertEqual(
        ListPickerMembershipChange.completed(wasMember: false, listID: 7),
        .added(listID: 7)
    )
    XCTAssertEqual(
        ListPickerMembershipChange.completed(wasMember: true, listID: 7),
        .removed(listID: 7)
    )
}
```

- [ ] **Step 2: Run `AppShellTests` and verify RED**

Run the focused xcodebuild command from Task 4, Step 2.

Expected: `removePlace` and `ListPickerMembershipChange` are undefined.

- [ ] **Step 3: Implement the directional callback**

Add:

```swift
enum ListPickerMembershipChange: Equatable {
    case added(listID: Int64)
    case removed(listID: Int64)

    static func completed(wasMember: Bool, listID: Int64) -> Self {
        wasMember ? .removed(listID: listID) : .added(listID: listID)
    }
}
```

Change the callback to:

```swift
let onChanged: @MainActor (ListPickerMembershipChange) -> Void
```

In `toggle(_:)`, capture the prior membership and report after successful reload:

```swift
let wasMember = memberships.contains(id)
if wasMember {
    try await model.removeFromList(placeID: placeID, listID: id)
} else {
    try await model.addToList(placeID: placeID, listID: id)
}
actionError = nil
await reload()
onChanged(.completed(wasMember: wasMember, listID: id))
```

In `createAndAdd()`, report:

```swift
onChanged(.added(listID: id))
```

Update `PlaceCardSheet` to ignore the payload while refreshing:

```swift
onChanged: { _ in
    Task { await refreshCard() }
}
```

- [ ] **Step 4: Implement the Hidden-row action hierarchy**

Add:

```swift
mutating func removePlace(placeID: String) {
    places.removeAll { $0.placeID == placeID }
    pendingPlaceIDs.remove(placeID)
    errorMessage = nil
}
```

Add `@Environment(\.dynamicTypeSize) private var dynamicTypeSize` and
`@State private var saveTarget: ListPlace?` to `ManagedPlacesView`.

For `.hidden`, render:

```swift
let layout = dynamicTypeSize.isAccessibilitySize
    ? AnyLayout(VStackLayout(alignment: .trailing, spacing: 6))
    : AnyLayout(HStackLayout(spacing: 8))

layout {
    Button("Unhide") {
        Task { await performAction(for: place) }
    }
    .buttonStyle(MaterialTonalButtonStyle())
    .accessibilityLabel("Unhide \(place.name)")
    .accessibilityIdentifier("tracks.hidden.unhide.\(place.placeID)")

    Button("Save") {
        saveTarget = place
    }
    .buttonStyle(MaterialQuietButtonStyle())
    .accessibilityLabel("Save \(place.name)")
    .accessibilityIdentifier("tracks.hidden.save.\(place.placeID)")
}
```

Keep the Loved action unchanged. Disable both Hidden actions while that place is pending.

Attach the picker:

```swift
.sheet(item: $saveTarget) { place in
    ListPickerView(
        placeID: place.placeID,
        model: model,
        onChanged: { change in
            if case .added = change {
                state.removePlace(placeID: place.placeID)
            }
        }
    )
}
```

Do not dismiss `saveTarget` from `onChanged`; Done remains the only close action.

- [ ] **Step 5: Rerun `AppShellTests` and verify GREEN**

Run the focused xcodebuild command from Task 4, Step 2.

Expected: all `AppShellTests` pass without changing Loved-row behavior.

- [ ] **Step 6: Commit picker and Hidden-row mechanics**

```bash
git add ios/App/Sources/Map/MapScreen.swift ios/App/Sources/Map/ManagedPlacesView.swift ios/App/Sources/PlaceCard/PlaceCardSheet.swift ios/App/Tests/AppShellTests.swift
git commit -m "feat(app): add save action to hidden rows"
```

---

### Task 6: Replace forbidden fixtures and prove user flows

**Files:**
- Modify: `ios/App/Sources/MakingTracksApp.swift:119-151`
- Modify: `ios/App/UITests/MakingTracksCoreLoopUITests.swift:951-1035`
- Modify: `ios/App/UITests/MakingTracksCoreLoopUITests.swift:1832-2040`
- Modify: `ios/App/UITests/MakingTracksCoreLoopUITests.swift:3239-3280`
- Modify: `ios/App/UITests/MakingTracksCoreLoopUITests.swift:4856-4890`

**Interfaces:**
- Consumes: public `recordVisit`, `setHidden`, and `seedUITestingUserList` interactions.
- Produces: representable managed-place fixtures; exported screenshots `a6-hidden-actions` and `a6-hidden-actions-ax`.

- [ ] **Step 1: Write failing UI assertions for the new card grammar**

In the accessibility card test, after tapping Seen:

```swift
XCTAssertTrue(actionBar.buttons["place-card.hide"].waitForExistence(timeout: 5))
XCTAssertEqual(actionBar.buttons.count, 4)
```

After tapping Love:

```swift
XCTAssertTrue(actionBar.buttons["place-card.hide"].exists)
XCTAssertEqual(actionBar.buttons.count, 4)
XCTAssertTrue(waitForButtonEnabled(false, identifier: "place-card.unsee", in: app))
```

Add a saved gating test:

```swift
func testSavedPlaceCardOmitsHideAcrossVisitStates() {
    let app = launch(reset: true, seedUserList: true)
    let map = app.otherElements["map.surface"]
    XCTAssertTrue(map.waitForExistence(timeout: 10))
    openFixtureCard(in: map, app: app)

    let actionBar = app.otherElements["place-card.action-bar"]
    XCTAssertTrue(actionBar.waitForExistence(timeout: 5))
    XCTAssertFalse(actionBar.buttons["place-card.hide"].exists)
    actionBar.buttons["place-card.visited"].tap()
    XCTAssertFalse(actionBar.buttons["place-card.hide"].exists)
    actionBar.buttons["place-card.loved"].tap()
    XCTAssertFalse(actionBar.buttons["place-card.hide"].exists)
}
```

- [ ] **Step 2: Write the failing Hidden Save flow**

Add:

```swift
func testHiddenSurfaceSaveAutoUnhidesAndKeepsPickerOpen() {
    let app = launch(reset: true, seedManagedPlaces: true)
    XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 10))
    openTracksDoor(in: app)
    let hidden = app.buttons["tracks.row.hidden"]
    XCTAssertTrue(scrollToHittable(hidden, in: app))
    hidden.tap()

    let placeID = "mt1_S0000000000000000000000001"
    let row = element(identifier: "tracks.hidden.row.\(placeID)", in: app)
    let save = app.buttons["tracks.hidden.save.\(placeID)"]
    XCTAssertTrue(scrollToHittable(save, in: app))
    assertMinimumInteractiveTarget(save)
    save.tap()

    XCTAssertTrue(app.navigationBars["Add to list"].waitForExistence(timeout: 5))
    let wantToGo = app.buttons["list-picker.row.1"]
    XCTAssertTrue(wantToGo.waitForExistence(timeout: 5))
    wantToGo.tap()
    XCTAssertTrue(waitForNonExistence(of: row, timeout: 5))
    XCTAssertTrue(app.navigationBars["Add to list"].exists)
    wantToGo.tap()
    XCTAssertTrue(waitForNonExistence(of: row, timeout: 2))
    XCTAssertTrue(app.navigationBars["Add to list"].exists)
    app.buttons["list-picker.done"].tap()
    XCTAssertFalse(app.navigationBars["Add to list"].waitForExistence(timeout: 2))
}
```

- [ ] **Step 3: Add failing default and AX action geometry assertions**

For each Hidden row, assert both `tracks.hidden.unhide.<id>` and `tracks.hidden.save.<id>` exist, are hittable after scrolling, meet the minimum target, and remain inside the app frame. At AX size also assert the two action frames do not intersect.

Before mutating rows, add:

```swift
attachScreenshot(named: "a6-hidden-actions")
```

and in the AX Hidden surface:

```swift
attachScreenshot(named: "a6-hidden-actions-ax")
```

Add both names to `screenshotExportNames`.

- [ ] **Step 4: Run the three focused UI tests and verify RED**

Run:

```bash
./scripts/sim-lock.sh xcodebuild test \
  -project ios/App/MakingTracks.xcodeproj \
  -scheme MakingTracks \
  -destination 'platform=iOS Simulator,id=C4A64D49-24A2-4429-B6E2-AD9A14142A99' \
  -parallel-testing-enabled NO \
  -disable-concurrent-destination-testing \
  -only-testing:MakingTracksUITests/MakingTracksCoreLoopUITests/testPlaceCardKeepsFixedActionSlotsReachableAtAccessibilityTextSize \
  -only-testing:MakingTracksUITests/MakingTracksCoreLoopUITests/testSavedPlaceCardOmitsHideAcrossVisitStates \
  -only-testing:MakingTracksUITests/MakingTracksCoreLoopUITests/testHiddenSurfaceSaveAutoUnhidesAndKeepsPickerOpen
```

Expected: old card slot assertions fail, saved cards still expose Hide, and `tracks.hidden.save.*` is absent.

- [ ] **Step 5: Replace the managed-place fixture with legal states**

Keep the primary fixture loved and saved in Date night. Keep `fixturePlaces[1]`
loved and hidden, but do not add it to any list. Keep `spreadFixturePlaces[0]`
hidden without list membership. The mutation order is:

```swift
try database.recordVisit(fixturePlaces[0], at: seedStart, verdict: .loved)
try database.recordVisit(
    fixturePlaces[1],
    at: seedStart.addingTimeInterval(60),
    verdict: .loved
)
try database.recordVisit(
    hiddenOnly,
    at: seedStart.addingTimeInterval(120)
)
try database.recordVisit(
    visibleOrdinary,
    at: seedStart.addingTimeInterval(180)
)
try database.setHidden(fixturePlaces[1], true)
try database.setHidden(hiddenOnly, true)
try database.seedUITestingUserList(
    named: "Date night",
    containingPlaceID: Self.primaryFixturePlaceID
)
```

Do not call `seedUITestingUserList` with `fixturePlaces[1].placeID`.

- [ ] **Step 6: Re-point the existing Loved/Hidden assertions**

Keep Loved-and-Hidden overlap assertions for `fixturePlaces[1]`; that overlap is
visit orthogonality, not saved overlap. Change Date night progress expectations
to remain `1 of 1 seen` before and after Unhide. Remove assertions that Unhide
restores stored membership. Keep track-count changes tied only to visit
visibility.

In the saved card overhaul test, assert Hide is absent instead of tapping it.
Leave hide/undo behavior in the unsaved hide-specific tests.

- [ ] **Step 7: Rerun focused UI tests and verify GREEN**

Run the Step 4 command, then run:

```bash
./scripts/sim-lock.sh xcodebuild test \
  -project ios/App/MakingTracks.xcodeproj \
  -scheme MakingTracks \
  -destination 'platform=iOS Simulator,id=C4A64D49-24A2-4429-B6E2-AD9A14142A99' \
  -parallel-testing-enabled NO \
  -disable-concurrent-destination-testing \
  -only-testing:MakingTracksUITests/MakingTracksCoreLoopUITests/testLovedAndHiddenSurfacesManagePlaceMembership \
  -only-testing:MakingTracksUITests/MakingTracksCoreLoopUITests/testHiddenSurfaceRoundTripsWithScopeWithoutChangingTrackCounts \
  -only-testing:MakingTracksUITests/MakingTracksCoreLoopUITests/testLovedAndHiddenSurfacesRemainUsableAtAX5
```

Expected: all six selected UI tests pass.

- [ ] **Step 8: Commit fixtures and UI coverage**

```bash
git add ios/App/Sources/MakingTracksApp.swift ios/App/UITests/MakingTracksCoreLoopUITests.swift
git commit -m "test(ui): prove saved-hidden exclusivity flows"
```

---

### Task 7: Run full gates, capture renders, and hand off exact-head review

**Files:**
- Create: `docs/design/design-system/a6-hidden-actions.png`
- Create: `docs/design/design-system/a6-hidden-actions-ax.png`
- Modify: `docs/superpowers/phases/phase-1/amendment-wave.md`

**Interfaces:**
- Consumes: the complete A6 implementation and screenshot export names.
- Produces: green host/gate evidence, checked-in renders, ledger status, and a stable exact head for reviewers.

- [ ] **Step 1: Run the complete host package suite**

Run:

```bash
cd ios
swift test
```

Expected: all host tests pass with zero failures. Restore `ios/Package.resolved`
if SwiftPM removes the app-only MapLibre pin; do not commit that host-suite
rewrite.

- [ ] **Step 2: Run the complete release and simulator gate**

Run:

```bash
./scripts/sim-lock.sh ./scripts/release-gate.sh
```

Expected: Release build, debug build-for-testing, unit tests, and UI tests all
pass with zero warnings-as-errors.

- [ ] **Step 3: Export the default and AX implementation renders**

Run the two render-producing tests with export enabled:

```bash
MAKING_TRACKS_EXPORT_UI_TEST_SCREENSHOTS=1 \
./scripts/sim-lock.sh xcodebuild test \
  -project ios/App/MakingTracks.xcodeproj \
  -scheme MakingTracks \
  -destination 'platform=iOS Simulator,id=C4A64D49-24A2-4429-B6E2-AD9A14142A99' \
  -parallel-testing-enabled NO \
  -disable-concurrent-destination-testing \
  -only-testing:MakingTracksUITests/MakingTracksCoreLoopUITests/testLovedAndHiddenSurfacesManagePlaceMembership \
  -only-testing:MakingTracksUITests/MakingTracksCoreLoopUITests/testLovedAndHiddenSurfacesRemainUsableAtAX5
```

Copy:

```bash
cp /private/tmp/making-tracks-artifacts/a6-hidden-actions.png docs/design/design-system/a6-hidden-actions.png
cp /private/tmp/making-tracks-artifacts/a6-hidden-actions-ax.png docs/design/design-system/a6-hidden-actions-ax.png
```

Inspect both images at original resolution. Verify default horizontal actions,
AX stacked actions, legible tonal/quiet hierarchy, no clipping, and no stale
saved-and-hidden row.

- [ ] **Step 4: Advance the builder-owned ledger status**

Change only A6:

```markdown
- **Status:** tests green
```

- [ ] **Step 5: Commit final evidence**

```bash
git add docs/design/design-system/a6-hidden-actions.png docs/design/design-system/a6-hidden-actions-ax.png docs/superpowers/phases/phase-1/amendment-wave.md
git commit -m "docs(a6): add saved-hidden implementation evidence"
```

- [ ] **Step 6: Re-ground and rerun affected checks if `origin/ios` advanced**

Run:

```bash
git fetch origin ios
git merge origin/ios --no-edit
cd ios
swift test
cd ..
./scripts/sim-lock.sh ./scripts/release-gate.sh
```

Expected: merge succeeds without changing A6 semantics; both suites pass at the
post-merge head.

- [ ] **Step 7: Run adversarial review at the exact head**

Copy the full SHA from:

```bash
git rev-parse HEAD
```

Request separate correctness, security/data-migration, and test-teeth reviews.
Require reviewers to inspect the exact SHA, the v6 deletion predicate, rollback
behavior, defensive saved-and-hidden rendering, and whether any test can pass
without the production behavior.

- [ ] **Step 8: Push and open the ready PR**

Run:

```bash
git push origin HEAD
```

Open a ready PR into `ios`; immediately apply:

```text
sourcery-review
track-b-ios
wp
greptile-review
```

The body must cite #517 and #526, map every ruled behavior to evidence, embed
immutable render links, record the full host and simulator commands/results,
record Sourcery's result or #535 cap-skip run ID/timestamp, and state why
Greptile is required: v6 changes stored user data.

- [ ] **Step 9: Obtain exact-head Opus and automated-review clearance**

Send Opus the copied full SHA and PR URL. Address all actionable findings
test-first, rerun affected tests and full gates after any production change,
push the new exact head, and repeat review until Opus, Greptile, and the
accounted Sourcery path are clean.

- [ ] **Step 10: Hand ready-to-merge ownership to Fable**

Update A6 status to `ready-to-merge`, commit and push that exact head, then send
Fable the PR URL, full SHA copied from `git rev-parse HEAD`, gate results,
review clearances, render paths, and remaining taste guesses. Do not merge.
