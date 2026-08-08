import XCTest
import GRDB
@testable import MakingTracksData

final class InteractionsTests: XCTestCase {
    private func ref(
        _ id: String,
        name: String = "Big Ben",
        lat: Double = 51.5,
        lon: Double = -0.12,
        schemaVersion: Int = 1,
        fetchedAt: Date = Date(timeIntervalSince1970: 50)
    ) throws -> PlaceRef {
        let raw = "{\"place_id\":\"\(id)\",\"name\":\"\(name)\",\"lat\":\(lat),\"lon\":\(lon)," +
            "\"category\":\"historic_building\",\"tier\":1,\"score\":0.82,\"source_refs\":[\"wd:Q42\"]}"
        return try PlaceRef(
            placeID: id,
            name: name,
            lat: lat,
            lon: lon,
            category: "historic_building",
            tier: 1,
            schemaVersion: schemaVersion,
            fetchedAt: fetchedAt,
            rawJSON: raw
        )
    }

    private func rejectFixtureMemberships(in database: AppDatabase) throws {
        try database.dbQueue.write { db in
            try db.execute(sql: """
                CREATE TRIGGER reject_fixture_memberships
                BEFORE INSERT ON list_items
                BEGIN
                    SELECT RAISE(ABORT, 'fixture membership rejected');
                END
                """)
        }
    }

    func testMarkingSeenSnapshotsOnFirstInteractionWithProvenance() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })
        _ = try db.recordVisit(ref("p1", fetchedAt: Date(timeIntervalSince1970: 77)))
        let snap = try db.dbQueue.read { try PlaceSnapshot.fetchOne($0) }
        XCTAssertEqual(snap?.placeID, "p1")
        XCTAssertEqual(snap?.snapshotSchemaVersion, 1)
        XCTAssertEqual(snap?.fetchedAt, Date(timeIntervalSince1970: 77))
        XCTAssertTrue(try db.isSeen("p1"))
    }

    func testSnapshotSchemaVersionIsDataDerivedNotAConstant() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })
        _ = try db.recordVisit(ref("p2", schemaVersion: 2))
        let snap = try db.dbQueue.read { try PlaceSnapshot.fetchOne($0) }
        XCTAssertEqual(snap?.snapshotSchemaVersion, 2)
    }

    func testSnapshotJSONIsTheVerbatimPayload() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })
        let r = try ref("p1")
        _ = try db.recordVisit(r)
        let snap = try db.dbQueue.read { try PlaceSnapshot.fetchOne($0) }
        XCTAssertEqual(snap?.snapshotJSON, r.rawJSON)
    }

    func testSnapshotIsWrittenOnceAndNotOverwrittenBySecondInteraction() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })
        _ = try db.recordVisit(ref("p1", name: "First Name"))
        try db.addToList(ref("p1", name: "Later Name"), listID: 1)
        let snaps = try db.dbQueue.read { try PlaceSnapshot.fetchAll($0) }
        XCTAssertEqual(snaps.count, 1)
        XCTAssertEqual(snaps[0].name, "First Name")
    }

    func testVerdictLovedIsRecordedAndReversible() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })
        let vid = try db.recordVisit(ref("p1"), verdict: .loved)
        XCTAssertEqual(try db.viewportState(["p1"])["p1"], PinState(saved: false, visit: .loved))
        try db.deleteVisit(id: vid)
        XCTAssertFalse(try db.isSeen("p1"))
    }

    func testSaveIsIdempotentAndDoesNotMarkSeen() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })
        try db.addToList(ref("p1"), listID: 1)
        try db.addToList(ref("p1"), listID: 1)
        let count = try db.dbQueue.read {
            try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM list_items")
        }
        XCTAssertEqual(count, 1)
        XCTAssertFalse(try db.isSeen("p1"))
    }

    func testSaveToMissingListThrowsInsteadOfDroppingUserIntent() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })
        XCTAssertThrowsError(try db.addToList(ref("p_missing"), listID: 404))
    }

    func testFailedSaveRollsBackMembershipAndPreservesHiddenUserIntent() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })
        let place = try ref("p_save_rollback", name: "Rollback place")
        let visitID = try db.recordVisit(place, verdict: .loved)
        try db.setHidden(place, true)
        let snapshotBefore = try XCTUnwrap(try db.snapshot(for: place.placeID))
        let visitBefore = try XCTUnwrap(try db.visit(id: visitID))
        try db.dbQueue.write { database in
            try database.execute(sql: """
                CREATE TRIGGER reject_hidden_delete
                BEFORE DELETE ON hidden_places
                WHEN OLD.place_id = 'p_save_rollback'
                BEGIN
                    SELECT RAISE(ABORT, 'hidden delete rejected');
                END
                """)
        }

        XCTAssertThrowsError(try db.addToList(place, listID: 1))

        XCTAssertEqual(try db.listMemberships(containing: place.placeID), [])
        XCTAssertTrue(try db.hiddenPlaceIDs().contains(place.placeID))
        XCTAssertEqual(try db.snapshot(for: place.placeID), snapshotBefore)
        let visitAfter = try XCTUnwrap(try db.visit(id: visitID))
        XCTAssertEqual(visitAfter.id, visitBefore.id)
        XCTAssertEqual(visitAfter.placeID, visitBefore.placeID)
        XCTAssertEqual(visitAfter.visitedAt, visitBefore.visitedAt)
        XCTAssertEqual(visitAfter.verdict, visitBefore.verdict)
        XCTAssertEqual(visitAfter.createdAt, visitBefore.createdAt)
        XCTAssertEqual(visitAfter.visitOrder, visitBefore.visitOrder)
    }

    func testWantToGoListIDReturnsSeededSystemList() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })

        let listID = try db.wantToGoListID()

        let row = try db.dbQueue.read {
            try Row.fetchOne($0, sql: "SELECT name, is_system FROM lists WHERE id = ?", arguments: [listID])
        }
        XCTAssertEqual(row?["name"] as String?, "Want to go")
        XCTAssertEqual(row?["is_system"] as Bool?, true)
    }

    func testMyTracksSystemListIsProtectedAndUsesTrackKind() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })
        let myTracks = try XCTUnwrap(try db.lists().first { $0.kind == PlaceList.trackKind })
        let myTracksID = try XCTUnwrap(myTracks.id)

        XCTAssertEqual(myTracks.name, "My tracks")
        XCTAssertTrue(myTracks.isSystem)
        XCTAssertThrowsError(try db.renameList(id: myTracksID, name: "Routes")) { error in
            XCTAssertEqual(error as? AppDatabaseError, .systemListIsProtected)
        }
        XCTAssertThrowsError(try db.deleteList(id: myTracksID)) { error in
            XCTAssertEqual(error as? AppDatabaseError, .systemListIsProtected)
        }
    }

    func testMyTracksSystemListRejectsStoredMembershipWrites() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })
        let myTracks = try XCTUnwrap(try db.lists().first { $0.kind == PlaceList.trackKind })
        let myTracksID = try XCTUnwrap(myTracks.id)
        let place = try ref("p_track_membership")

        XCTAssertThrowsError(try db.addToList(place, listID: myTracksID)) { error in
            XCTAssertEqual(error as? AppDatabaseError, .systemListIsProtected)
        }
        XCTAssertThrowsError(try db.removeFromList(placeID: place.placeID, listID: myTracksID)) { error in
            XCTAssertEqual(error as? AppDatabaseError, .systemListIsProtected)
        }
        let visitID = try db.recordVisit(place)
        try db.setVisitVerdict(id: visitID, .loved)
        XCTAssertEqual(try db.trackVisits().first?.verdict, .loved)

        let rows = try db.dbQueue.read {
            try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM list_items WHERE list_id = ?", arguments: [myTracksID])
        }
        XCTAssertEqual(rows, 0)
    }

    func testNonSystemTrackKindListStillAllowsStoredMembershipWrites() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })
        try db.dbQueue.write { d in
            try d.execute(
                sql: "INSERT INTO lists (id, name, is_system, created_at, list_kind) VALUES (42, 'Imported', 0, 0, ?)",
                arguments: [PlaceList.trackKind]
            )
        }
        let place = try ref("p_imported_track_kind")

        try db.addToList(place, listID: 42)

        XCTAssertEqual(try db.listItems(listID: 42).map(\.placeID), [place.placeID])
    }

    func testUITestingTrackListSeedUsesTrackKind() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })

        try db.seedUITestingMultiDayTrackList(
            named: "Replay week",
            places: [
                ref("p_replay_1", name: "First"),
                ref("p_replay_2", name: "Second"),
            ]
        )

        let list = try XCTUnwrap(try db.lists().first { $0.name == "Replay week" })
        XCTAssertFalse(list.isSystem)
        XCTAssertEqual(list.kind, PlaceList.trackKind)
        XCTAssertEqual(try db.listItems(listID: XCTUnwrap(list.id)).map(\.placeID), ["p_replay_2", "p_replay_1"])
    }

    func testUITestingMultiDayTrackListSeedUsesVisibleModernVariedTimestamps() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })
        let places = try (1...6).map { try ref("p_replay_\($0)", name: "Replay \($0)") }

        try db.seedUITestingMultiDayTrackList(named: "Replay week", places: places)

        let visits = try db.dbQueue.read {
            try Visit.fetchAll($0, sql: "SELECT * FROM visits ORDER BY visited_at")
        }
        let calendar = Calendar(identifier: .gregorian)
        let years = visits.map { calendar.component(.year, from: $0.visitedAt) }
        let days = Set(visits.map { calendar.startOfDay(for: $0.visitedAt) })
        let timesOfDay = Set(visits.map {
            calendar.component(.hour, from: $0.visitedAt) * 60 + calendar.component(.minute, from: $0.visitedAt)
        })

        XCTAssertEqual(visits.count, 6)
        XCTAssertEqual(years, Array(repeating: 2026, count: 6))
        XCTAssertGreaterThanOrEqual(days.count, 4)
        XCTAssertGreaterThanOrEqual(timesOfDay.count, 4)
    }

    func testUITestingMultiDayTrackListSeedAllowsRepeatedPlacesForReplayLanes() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })
        let first = try ref("p_replay_1", name: "Replay 1", lat: 3.135, lon: 101.62)
        let second = try ref("p_replay_2", name: "Replay 2", lat: 3.245, lon: 101.81)
        let third = try ref("p_replay_3", name: "Replay 3", lat: 3.065, lon: 101.75)
        let fourth = try ref("p_replay_4", name: "Replay 4", lat: 3.218, lon: 101.67)
        let fifth = try ref("p_replay_5", name: "Replay 5", lat: 3.105, lon: 101.86)

        try db.seedUITestingMultiDayTrackList(
            named: "Replay week",
            places: [first, second, first, third, fourth, fifth]
        )

        let list = try XCTUnwrap(try db.lists().first { $0.name == "Replay week" })
        let visits = try db.trackVisits(listID: XCTUnwrap(list.id))
        XCTAssertEqual(visits.map(\.placeID), [
            "p_replay_1",
            "p_replay_2",
            "p_replay_1",
            "p_replay_3",
            "p_replay_4",
            "p_replay_5",
        ])
        XCTAssertEqual(Set(try db.listItems(listID: XCTUnwrap(list.id)).map(\.placeID)), [
            "p_replay_1",
            "p_replay_2",
            "p_replay_3",
            "p_replay_4",
            "p_replay_5",
        ])
    }

    func testSnapshotLookupReturnsEquatableSnapshot() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })
        let place = try ref("p_snapshot", fetchedAt: Date(timeIntervalSince1970: 77))
        _ = try db.recordVisit(place)

        let snapshot = try db.snapshot(for: "p_snapshot")

        XCTAssertEqual(
            snapshot,
            PlaceSnapshot(
                placeID: "p_snapshot",
                name: "Big Ben",
                lat: 51.5,
                lon: -0.12,
                category: "historic_building",
                tier: 1,
                snapshotJSON: place.rawJSON,
                snapshotSchemaVersion: 1,
                fetchedAt: Date(timeIntervalSince1970: 77)
            )
        )
        XCTAssertNil(try db.snapshot(for: "missing"))
    }

    func testCustomListCRUDTrimsBoundsAndProtectsSystemList() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })

        let created = try db.createList(named: "  Date night  ")
        XCTAssertEqual(created.name, "Date night")
        XCTAssertFalse(created.isSystem)
        XCTAssertEqual(created.createdAt, Date(timeIntervalSince1970: 100))

        let renamed = try db.renameList(id: created.id!, name: "Architecture\u{0007}")
        XCTAssertEqual(renamed.name, "Architecture")

        XCTAssertThrowsError(try db.createList(named: "   ")) { error in
            XCTAssertEqual(error as? AppDatabaseError, .emptyListName)
        }
        XCTAssertThrowsError(try db.createList(named: "\u{0007}\u{200B}")) { error in
            XCTAssertEqual(error as? AppDatabaseError, .emptyListName)
        }
        XCTAssertThrowsError(try db.createList(named: String(repeating: "x", count: 81))) { error in
            XCTAssertEqual(error as? AppDatabaseError, .listNameTooLong)
        }
        XCTAssertThrowsError(try db.renameList(id: try db.wantToGoListID(), name: "Trips")) { error in
            XCTAssertEqual(error as? AppDatabaseError, .systemListIsProtected)
        }
        XCTAssertThrowsError(try db.deleteList(id: try db.wantToGoListID())) { error in
            XCTAssertEqual(error as? AppDatabaseError, .systemListIsProtected)
        }

        try db.deleteList(id: created.id!)
        XCTAssertFalse(try db.lists().contains { $0.id == created.id })
    }

    func testListMembershipRowsAndSnapshotBackedMapFeaturesStayListExclusive() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })
        let custom = try db.createList(named: "KL trip")
        let customPlace = try ref("p_custom", name: "Custom Place")
        let wantPlace = try ref("p_want", name: "Want Place")

        try db.addToList(customPlace, listID: custom.id!)
        try db.addToList(wantPlace, listID: try db.wantToGoListID())
        _ = try db.recordVisit(customPlace)

        let rows = try db.listItems(listID: custom.id!)
        XCTAssertEqual(rows.map(\.placeID), ["p_custom"])
        XCTAssertEqual(rows[0].name, "Custom Place")
        XCTAssertEqual(rows[0].pinState, PinState(saved: true, visit: .visited, hidden: false))

        let features = try db.listMapFeatures(listID: custom.id!)
        XCTAssertEqual(features.map(\.0.id), ["p_custom"])
        XCTAssertEqual(features[0].0.lat, customPlace.lat)
        XCTAssertEqual(features[0].1, PinState(saved: true, visit: .visited, hidden: false))
    }

    func testListMembershipLookupUsesExactRowsNotDisplayFeed() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })
        let custom = try db.createList(named: "KL trip")
        let futureSnapshotPlace = try ref("p_future_snapshot", schemaVersion: 99)

        try db.addToList(futureSnapshotPlace, listID: custom.id!)
        try db.dbQueue.write { d in
            try d.execute(
                sql: "INSERT INTO list_items (list_id, place_id, added_at) VALUES (?, ?, ?)",
                arguments: [custom.id!, "p_missing_snapshot", Date(timeIntervalSince1970: 99)]
            )
        }

        XCTAssertEqual(try db.listMemberships(containing: "p_future_snapshot"), [custom.id!])
        XCTAssertEqual(try db.listMemberships(containing: "p_missing_snapshot"), [custom.id!])
        XCTAssertEqual(try db.listItems(listID: custom.id!).map(\.placeID), ["p_future_snapshot"])
    }

    func testListRowsSanitizeSnapshotFallbackTextWithoutDroppingHistory() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })
        let custom = try db.createList(named: "KL trip")
        try db.dbQueue.write { d in
            try d.execute(
                sql: """
                    INSERT INTO place_snapshots
                    (place_id, name, lat, lon, category, tier, snapshot_json, snapshot_schema_version, fetched_at)
                    VALUES (?, ?, 51.5, -0.12, ?, 2, '{}', 99, ?)
                    """,
                arguments: ["p_unsafe_snapshot", "Safe\u{202E}evil", "category\u{202E}", Date(timeIntervalSince1970: 50)]
            )
            try d.execute(
                sql: "INSERT INTO list_items (list_id, place_id, added_at) VALUES (?, ?, ?)",
                arguments: [custom.id!, "p_unsafe_snapshot", Date(timeIntervalSince1970: 100)]
            )
        }

        let rows = try db.listItems(listID: custom.id!)
        let features = try db.listMapFeatures(listID: custom.id!)

        XCTAssertEqual(rows.map(\.placeID), ["p_unsafe_snapshot"])
        XCTAssertEqual(rows[0].name, "Unnamed place")
        XCTAssertEqual(rows[0].category, "place")
        XCTAssertEqual(features.map(\.0.id), ["p_unsafe_snapshot"])
        XCTAssertEqual(features[0].0.category, "place")
    }

    func testRemoveFromListClearsSavedWithoutDeletingSnapshotOrVisits() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })
        let place = try ref("p_unsave")
        let listID = try db.wantToGoListID()
        try db.addToList(place, listID: listID)
        _ = try db.recordVisit(place)

        try db.removeFromList(placeID: "p_unsave", listID: listID)

        XCTAssertEqual(try db.viewportState(["p_unsave"])["p_unsave"], PinState(saved: false, visit: .visited))
        XCTAssertNotNil(try db.snapshot(for: "p_unsave"))
    }

    func testSetLovedTrueMarksLatestVisitAndFalseClearsEveryLovedVisitForPlace() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })
        let place = try ref("p_loved")
        _ = try db.recordVisit(place, verdict: .loved)
        _ = try db.recordVisit(place)

        try db.setLoved(placeID: "p_loved", true)

        let visitsAfterLove = try db.dbQueue.read {
            try Visit.fetchAll($0, sql: "SELECT * FROM visits WHERE place_id = ? ORDER BY id", arguments: ["p_loved"])
        }
        XCTAssertEqual(visitsAfterLove.map(\.verdict), [.loved, .loved])
        XCTAssertEqual(try db.viewportState(["p_loved"])["p_loved"], PinState(saved: false, visit: .loved))

        try db.setLoved(placeID: "p_loved", false)

        let visitsAfterUnlove = try db.dbQueue.read {
            try Visit.fetchAll($0, sql: "SELECT * FROM visits WHERE place_id = ? ORDER BY id", arguments: ["p_loved"])
        }
        XCTAssertEqual(visitsAfterUnlove.map(\.verdict), [nil, nil])
        XCTAssertEqual(try db.viewportState(["p_loved"])["p_loved"], PinState(saved: false, visit: .visited))
    }

    func testSetVisitVerdictUsesVisitIDToFindPlaceAndThenUpdatesEveryRowForThatPlace() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })
        let place = try ref("p_row_loved")
        let older = try db.recordVisit(place)
        let newer = try db.recordVisit(place)

        try db.setVisitVerdict(id: older, .loved)

        var visits = try db.dbQueue.read {
            try Visit.fetchAll($0, sql: "SELECT * FROM visits WHERE place_id = ? ORDER BY id", arguments: ["p_row_loved"])
        }
        XCTAssertEqual(visits.map(\.verdict), [.loved, .loved])
        XCTAssertEqual(try db.viewportState(["p_row_loved"])["p_row_loved"], PinState(saved: false, visit: .loved))

        try db.setVisitVerdict(id: older, nil)
        try db.setVisitVerdict(id: newer, .loved)

        visits = try db.dbQueue.read {
            try Visit.fetchAll($0, sql: "SELECT * FROM visits WHERE place_id = ? ORDER BY id", arguments: ["p_row_loved"])
        }
        XCTAssertEqual(visits.map(\.verdict), [.loved, .loved])
    }

    func testUpdateVisitDateTargetsOneVisitRowAndPreservesTimeOfDay() throws {
        let calendar = Calendar(identifier: .gregorian)
        let targetDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 14)))
        let recordedAt = Date(timeIntervalSince1970: 100)
        let db = try AppDatabase.inMemory(now: { targetDay.addingTimeInterval(60 * 60 * 24) })
        let place = try ref("p_date_edit")
        let first = try db.recordVisit(place, at: recordedAt)
        let second = try db.recordVisit(place, at: recordedAt)

        try db.updateVisitDate(id: first, toDayContaining: targetDay, calendar: calendar)

        let visits = try db.dbQueue.read {
            try Visit.fetchAll($0, sql: "SELECT * FROM visits WHERE place_id = ? ORDER BY id", arguments: ["p_date_edit"])
        }
        XCTAssertEqual(visits.map(\.id), [first, second])
        XCTAssertEqual(calendar.component(.year, from: visits[0].visitedAt), 2026)
        XCTAssertEqual(calendar.component(.month, from: visits[0].visitedAt), 7)
        XCTAssertEqual(calendar.component(.day, from: visits[0].visitedAt), 14)
        XCTAssertEqual(calendar.component(.hour, from: visits[0].visitedAt), calendar.component(.hour, from: recordedAt))
        XCTAssertEqual(calendar.component(.minute, from: visits[0].visitedAt), calendar.component(.minute, from: recordedAt))
        XCTAssertEqual(visits[1].visitedAt, recordedAt)
    }

    func testUpdateVisitDateRejectsTomorrowWithoutMutatingTheVisit() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Kuala_Lumpur"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 6,
            hour: 9
        )))
        let original = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 5,
            hour: 22,
            minute: 15
        )))
        let tomorrow = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 7,
            hour: 8
        )))
        let db = try AppDatabase.inMemory(now: { now })
        let id = try db.recordVisit(ref("p_future_date"), at: original)
        try db.dbQueue.write { database in
            try database.execute(
                sql: "UPDATE visits SET visit_order = 7 WHERE id = ?",
                arguments: [id]
            )
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

    func testUpdateVisitDateAcceptsLaterInstantOnSameSuppliedLocalDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Pacific/Kiritimati"))
        let now = Date(timeIntervalSince1970: 1_775_565_000)
        let laterLocalToday = Date(timeIntervalSince1970: 1_775_608_200)
        let original = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 4,
            day: 7,
            hour: 21,
            minute: 15
        )))
        let db = try AppDatabase.inMemory(now: { now })
        let id = try db.recordVisit(ref("p_local_today"), at: original)

        try db.updateVisitDate(
            id: id,
            toDayContaining: laterLocalToday,
            calendar: calendar
        )

        let stored = try XCTUnwrap(db.visit(id: id))
        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day, .hour, .minute], from: stored.visitedAt),
            DateComponents(year: 2026, month: 4, day: 8, hour: 21, minute: 15)
        )
    }

    func testReorderVisitsWithinDayUsesVisitIDsNotPlaceIDs() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })
        let day = Date(timeIntervalSince1970: 60 * 60 * 24 * 10)
        let first = try db.recordVisit(ref("p_repeat", name: "Repeat"), at: day.addingTimeInterval(60))
        let other = try db.recordVisit(ref("p_other", name: "Other"), at: day.addingTimeInterval(120))
        let repeatAgain = try db.recordVisit(ref("p_repeat", name: "Repeat"), at: day.addingTimeInterval(180))

        try db.reorderVisitsWithinDay([repeatAgain, first, other], dayContaining: day)

        XCTAssertEqual(try db.trackVisits().map(\.id), [repeatAgain, first, other])
        let rows = try db.dbQueue.read {
            try Row.fetchAll($0, sql: "SELECT id, visit_order FROM visits ORDER BY visit_order, id")
        }
        XCTAssertEqual(rows.map { $0["id"] as Int64 }, [repeatAgain, first, other])
        XCTAssertEqual(rows.map { $0["visit_order"] as Int }, [0, 1, 2])
    }

    func testMoveVisitToDaySlotsAtTargetOrderAndPreservesTimeOfDay() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })
        let calendar = Calendar(identifier: .gregorian)
        let sourceDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 13)))
        let targetDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 14)))
        let moved = try db.recordVisit(ref("p_moved", name: "Moved"), at: sourceDay.addingTimeInterval(9 * 60 * 60 + 15 * 60))
        let firstTarget = try db.recordVisit(ref("p_first", name: "First"), at: targetDay.addingTimeInterval(10 * 60 * 60))
        let secondTarget = try db.recordVisit(ref("p_second", name: "Second"), at: targetDay.addingTimeInterval(11 * 60 * 60))

        try db.moveVisit(
            id: moved,
            toDayContaining: targetDay,
            targetDayOrderedIDs: [firstTarget, moved, secondTarget],
            calendar: calendar
        )

        let visits = try db.trackVisits()
        XCTAssertEqual(visits.map(\.id), [firstTarget, moved, secondTarget])
        XCTAssertEqual(visits.map(\.visitOrder), [0, 1, 2])
        XCTAssertEqual(calendar.component(.year, from: visits[1].visitedAt), 2026)
        XCTAssertEqual(calendar.component(.month, from: visits[1].visitedAt), 7)
        XCTAssertEqual(calendar.component(.day, from: visits[1].visitedAt), 14)
        XCTAssertEqual(calendar.component(.hour, from: visits[1].visitedAt), 9)
        XCTAssertEqual(calendar.component(.minute, from: visits[1].visitedAt), 15)
    }

    func testDeleteLatestVisitRemovesOnlyNewestVisitForPlace() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })
        let place = try ref("p_unsee_latest")
        let older = try db.recordVisit(place, verdict: .loved)
        let newer = try db.recordVisit(place)

        let deleted = try db.deleteLatestVisit(placeID: "p_unsee_latest")

        XCTAssertEqual(deleted, true)
        let visits = try db.dbQueue.read {
            try Visit.fetchAll($0, sql: "SELECT * FROM visits WHERE place_id = ? ORDER BY id", arguments: ["p_unsee_latest"])
        }
        XCTAssertEqual(visits.map(\.id), [older])
        XCTAssertEqual(visits.map(\.verdict), [.loved])
        XCTAssertEqual(try db.viewportState(["p_unsee_latest"])["p_unsee_latest"], PinState(saved: false, visit: .loved))
        XCTAssertEqual(try db.trackVisits().map(\.id), [older])

        try db.deleteLatestVisit(placeID: "p_unsee_latest")
        XCTAssertFalse(try db.isSeen("p_unsee_latest"))
        XCTAssertEqual(try db.deleteLatestVisit(placeID: "p_unsee_latest"), false)
        XCTAssertEqual(newer, older + 1)
    }

    func testDeleteVisitsClearsAllVisitStateForPlaceButKeepsSavedAxis() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })
        let place = try ref("p_unvisit")
        let listID = try db.wantToGoListID()
        try db.addToList(place, listID: listID)
        _ = try db.recordVisit(place, verdict: .loved)
        _ = try db.recordVisit(place)

        try db.deleteVisits(placeID: "p_unvisit")

        XCTAssertFalse(try db.isSeen("p_unvisit"))
        XCTAssertEqual(try db.viewportState(["p_unvisit"])["p_unvisit"], PinState(saved: true, visit: .none))
        XCTAssertNotNil(try db.snapshot(for: "p_unvisit"))
    }

    func testDeleteLatestVisitPrefersNewestVisitedAtTwoYearsAfterOlderRowID() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })
        let olderVisitedAt = Date(timeIntervalSince1970: 100)
        let newerVisitedAt = olderVisitedAt.addingTimeInterval(60 * 60 * 24 * 365 * 2)
        let newerLowerID = try db.dbQueue.write { db in
            var visit = Visit(
                id: nil,
                placeID: "p_unsee_order",
                visitedAt: newerVisitedAt,
                verdict: .loved,
                createdAt: newerVisitedAt
            )
            try visit.insert(db)
            return visit.id!
        }
        let olderHigherID = try db.dbQueue.write { db in
            var visit = Visit(
                id: nil,
                placeID: "p_unsee_order",
                visitedAt: olderVisitedAt,
                verdict: nil,
                createdAt: olderVisitedAt
            )
            try visit.insert(db)
            return visit.id!
        }
        XCTAssertLessThan(newerLowerID, olderHigherID)

        let deleted = try db.deleteLatestVisit(placeID: "p_unsee_order")

        XCTAssertEqual(deleted, true)
        let visits = try db.dbQueue.read {
            try Visit.fetchAll($0, sql: "SELECT * FROM visits WHERE place_id = ? ORDER BY id", arguments: ["p_unsee_order"])
        }
        XCTAssertEqual(visits.map(\.id), [olderHigherID])
        XCTAssertEqual(visits.map(\.visitedAt), [olderVisitedAt])
    }

    func testSetHiddenIsIdempotentReversibleAndSnapshotsOnFirstInteraction() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })
        let place = try ref("p_hidden")

        try db.setHidden(place, true)
        try db.setHidden(place, true)

        XCTAssertEqual(try db.hiddenPlaceIDs(), ["p_hidden"])
        XCTAssertEqual(try db.viewportState(["p_hidden"])["p_hidden"], PinState(saved: false, visit: .none, hidden: true))
        XCTAssertEqual(try db.snapshot(for: "p_hidden")?.name, "Big Ben")

        try db.setHidden(place, false)
        try db.unhide(placeID: "p_hidden")

        XCTAssertEqual(try db.hiddenPlaceIDs(), [])
        XCTAssertEqual(try db.viewportState(["p_hidden"])["p_hidden"], PinState(saved: false, visit: .none, hidden: false))
    }

    func testHiddenRemainsOrthogonalToVisitState() throws {
        // Mutation caught: treating any visit as a saved membership would reject this hide.
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
        // Mutation caught: mutating saved, hidden, or snapshot state before rejecting a saved place.
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
            XCTAssertEqual(databaseError, .savedPlaceCannotBeHidden)
        }
        XCTAssertEqual(try db.listMemberships(containing: place.placeID), [listID])
        XCTAssertEqual(try db.hiddenPlaceIDs(), [])
        XCTAssertNil(try db.snapshot(for: place.placeID))
    }

    func testSavingHiddenPlaceAutoUnhidesAndPreservesLovedVisit() throws {
        // Mutation caught: adding a membership without removing the place's hidden state.
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
        // Mutation caught: skipping the unhide repair when the membership insert is a duplicate.
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

    func testSeedUITestingTrackListRepairsHiddenMembership() throws {
        // Mutation caught: UI track fixtures inserting a saved membership without repairing hidden state.
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })
        let first = try ref("p_seeded_track_hidden_1")
        let second = try ref("p_seeded_track_hidden_2")
        try db.setHidden(first, true)
        try db.setHidden(second, true)

        try db.seedUITestingTrackList(named: "Fixture track", places: [first, second])

        XCTAssertEqual(
            try db.viewportState([first.placeID])[first.placeID],
            PinState(saved: true, visit: .visited, hidden: false)
        )
        XCTAssertEqual(
            try db.viewportState([second.placeID])[second.placeID],
            PinState(saved: true, visit: .visited, hidden: false)
        )
        XCTAssertFalse(try db.hiddenPlaceIDs().contains(first.placeID))
        XCTAssertFalse(try db.hiddenPlaceIDs().contains(second.placeID))
    }

    func testSeedUITestingUserListRepairsHiddenMembership() throws {
        // Mutation caught: UI user-list fixtures inserting a saved membership without repairing hidden state.
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })
        let place = try ref("p_seeded_user_hidden")
        try db.setHidden(place, true)

        try db.seedUITestingUserList(named: "Fixture list", containingPlaceID: place.placeID)

        XCTAssertEqual(
            try db.viewportState([place.placeID])[place.placeID],
            PinState(saved: true, visit: .none, hidden: false)
        )
        XCTAssertFalse(try db.hiddenPlaceIDs().contains(place.placeID))
    }

    func testSeedUITestingTrackListRollsBackHiddenRepairWhenMembershipFails() throws {
        // Mutation caught: committing an unhide before a later fixture membership write fails.
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })
        let place = try ref("p_seeded_track_rollback")
        try db.setHidden(place, true)
        try rejectFixtureMemberships(in: db)

        XCTAssertThrowsError(try db.seedUITestingTrackList(named: "Fixture track", places: [place]))

        XCTAssertTrue(try db.hiddenPlaceIDs().contains(place.placeID))
    }

    func testSeedUITestingUserListRollsBackHiddenRepairWhenMembershipFails() throws {
        // Mutation caught: committing an unhide before a later fixture membership write fails.
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })
        let place = try ref("p_seeded_user_rollback")
        try db.setHidden(place, true)
        try rejectFixtureMemberships(in: db)

        XCTAssertThrowsError(try db.seedUITestingUserList(named: "Fixture list", containingPlaceID: place.placeID))

        XCTAssertTrue(try db.hiddenPlaceIDs().contains(place.placeID))
    }

    func testRemovingLastMembershipAfterSaveDoesNotRehidePlace() throws {
        // Mutation caught: deriving hidden state from membership removal instead of preserving its repaired state.
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

    func testValidatingInitRejectsOutOfRangeAndOversize() throws {
        XCTAssertThrowsError(try PlaceRef(
            placeID: "p",
            name: "n",
            lat: 91,
            lon: 0,
            category: "c",
            tier: 1,
            schemaVersion: 1,
            fetchedAt: Date(),
            rawJSON: "{}"
        ))
        XCTAssertThrowsError(try PlaceRef(
            placeID: "p",
            name: "n",
            lat: 0,
            lon: 0,
            category: "c",
            tier: 9,
            schemaVersion: 1,
            fetchedAt: Date(),
            rawJSON: "{}"
        ))
        XCTAssertThrowsError(try PlaceRef(
            placeID: "p",
            name: "n",
            lat: 0,
            lon: 0,
            category: "c",
            tier: 1,
            schemaVersion: 1,
            fetchedAt: Date(),
            rawJSON: String(repeating: "x", count: PlaceRef.maxRawJSONBytes + 1)
        ))
    }
}
