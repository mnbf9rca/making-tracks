import XCTest
import GRDB
@testable import MakingTracksData

final class InteractionsTests: XCTestCase {
    private func ref(
        _ id: String,
        name: String = "Big Ben",
        schemaVersion: Int = 1,
        fetchedAt: Date = Date(timeIntervalSince1970: 50)
    ) throws -> PlaceRef {
        let raw = "{\"place_id\":\"\(id)\",\"name\":\"\(name)\",\"lat\":51.5,\"lon\":-0.12," +
            "\"category\":\"historic_building\",\"tier\":1,\"score\":0.82,\"source_refs\":[\"wd:Q42\"]}"
        return try PlaceRef(
            placeID: id,
            name: name,
            lat: 51.5,
            lon: -0.12,
            category: "historic_building",
            tier: 1,
            schemaVersion: schemaVersion,
            fetchedAt: fetchedAt,
            rawJSON: raw
        )
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

    func testWantToGoListIDReturnsSeededSystemList() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })

        let listID = try db.wantToGoListID()

        let row = try db.dbQueue.read {
            try Row.fetchOne($0, sql: "SELECT name, is_system FROM lists WHERE id = ?", arguments: [listID])
        }
        XCTAssertEqual(row?["name"] as String?, "Want to go")
        XCTAssertEqual(row?["is_system"] as Bool?, true)
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

    func testHiddenIsOrthogonalToSavedAndVisitState() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })
        let place = try ref("p_hidden_loved")
        try db.addToList(place, listID: try db.wantToGoListID())
        _ = try db.recordVisit(place, verdict: .loved)
        try db.setHidden(place, true)

        XCTAssertEqual(
            try db.viewportState([place.placeID])[place.placeID],
            PinState(saved: true, visit: .loved, hidden: true)
        )

        try db.setHidden(place, false)

        XCTAssertEqual(
            try db.viewportState([place.placeID])[place.placeID],
            PinState(saved: true, visit: .loved, hidden: false)
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
