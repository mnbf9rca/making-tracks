import XCTest
import GRDB
@testable import MakingTracksData

final class ModelsTests: XCTestCase {
    func testVisitRoundTripsWithSnakeCaseColumns() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 0) })
        try db.dbQueue.write { d in
            var v = Visit(
                id: nil,
                placeID: "mt1_" + String(repeating: "0", count: 26),
                visitedAt: Date(timeIntervalSince1970: 10),
                verdict: .loved,
                createdAt: Date(timeIntervalSince1970: 10)
            )
            try v.insert(d)
        }
        let got = try db.dbQueue.read { try Visit.fetchOne($0) }
        XCTAssertEqual(got?.placeID, "mt1_" + String(repeating: "0", count: 26))
        XCTAssertEqual(got?.verdict, .loved)
        let col = try db.dbQueue.read {
            try Row.fetchOne($0, sql: "SELECT place_id FROM visits")
        }
        XCTAssertNotNil(col)
    }

    func testUnknownVerdictFetchesAsNilRatherThanMakingVisitUnreadable() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 0) })
        try db.dbQueue.write { d in
            try d.execute(
                sql: """
                    INSERT INTO visits (place_id, visited_at, verdict, created_at)
                    VALUES ('p_future', 1, 'future_verdict', 1)
                    """
            )
        }

        let got = try db.dbQueue.read { try Visit.fetchOne($0) }
        XCTAssertEqual(got?.placeID, "p_future")
        XCTAssertNil(got?.verdict)
        XCTAssertTrue(try db.isSeen("p_future"))
    }

    func testPlaceRefCarriesProvenanceAndVerbatimPayload() throws {
        let raw = "{\"place_id\":\"p1\",\"name\":\"Big Ben\",\"lat\":51.5,\"lon\":-0.12,\"category\":\"historic_building\",\"tier\":1,\"score\":0.8,\"source_refs\":[\"wd:Q42\"]}"
        let ref = try PlaceRef(
            placeID: "p1",
            name: "Big Ben",
            lat: 51.5,
            lon: -0.12,
            category: "historic_building",
            tier: 1,
            schemaVersion: 3,
            fetchedAt: Date(timeIntervalSince1970: 7),
            rawJSON: raw
        )
        XCTAssertEqual(ref.schemaVersion, 3)
        XCTAssertEqual(ref.fetchedAt, Date(timeIntervalSince1970: 7))
        XCTAssertEqual(ref.rawJSON, raw)
    }

    func testListAndListItemRoundTripSnakeCaseColumns() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 0) })
        try db.dbQueue.write { d in
            var list = PlaceList(
                id: nil,
                name: "KL trip",
                isSystem: false,
                kind: "track",
                createdAt: Date(timeIntervalSince1970: 1)
            )
            try list.insert(d)
            let item = ListItem(
                listID: list.id!,
                placeID: "p1",
                addedAt: Date(timeIntervalSince1970: 2)
            )
            try item.insert(d)
        }
        let (l, i) = try db.dbQueue.read { d in
            (
                try PlaceList.filter(Column("is_system") == false).fetchOne(d),
                try ListItem.fetchOne(d)
            )
        }
        XCTAssertEqual(l?.name, "KL trip")
        XCTAssertEqual(l?.isSystem, false)
        XCTAssertEqual(l?.kind, "track")
        XCTAssertEqual(i?.placeID, "p1")
        let cols = try db.dbQueue.read { db in
            (
                try Row.fetchOne(db, sql: "SELECT list_kind FROM lists WHERE is_system = 0"),
                try Row.fetchOne(db, sql: "SELECT list_id, added_at FROM list_items")
            )
        }
        XCTAssertEqual(cols.0?["list_kind"] as String?, "track")
        XCTAssertNotNil(cols.1)
    }
}
