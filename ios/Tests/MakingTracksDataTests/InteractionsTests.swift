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
            "\"category\":\"architecture\",\"tier\":1,\"score\":0.82,\"source_refs\":[\"wd:Q42\"]}"
        return try PlaceRef(
            placeID: id,
            name: name,
            lat: 51.5,
            lon: -0.12,
            category: "architecture",
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
