import XCTest
import GRDB
@testable import MakingTracksData

final class DerivationsTests: XCTestCase {
    private func seededDB() throws -> AppDatabase {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 0) })
        try db.dbQueue.write { d in
            try d.execute(
                sql: "INSERT INTO visits (place_id, visited_at, created_at) VALUES ('p_seen', 1, 1)"
            )
        }
        return db
    }

    func testIsSeenIsDerivedFromVisitEvents() throws {
        let db = try seededDB()
        XCTAssertTrue(try db.isSeen("p_seen"))
        XCTAssertFalse(try db.isSeen("p_unseen"))
    }

    func testUnmarkingDeletesTheEventAndSeenBecomesFalse() throws {
        let db = try seededDB()
        try db.dbQueue.write {
            try $0.execute(sql: "DELETE FROM visits WHERE place_id='p_seen'")
        }
        XCTAssertFalse(try db.isSeen("p_seen"))
    }

    func testRevisitsAreRepresentableAndDeletingOneKeepsSeen() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 0) })
        try db.dbQueue.write { d in
            try d.execute(sql: "INSERT INTO visits (place_id, visited_at, created_at) VALUES ('p', 1, 1)")
            try d.execute(sql: "INSERT INTO visits (place_id, visited_at, created_at) VALUES ('p', 2, 2)")
        }
        let n = try db.dbQueue.read {
            try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM visits WHERE place_id='p'")
        }
        XCTAssertEqual(n, 2)
        try db.dbQueue.write {
            try $0.execute(sql: "DELETE FROM visits WHERE id = (SELECT MIN(id) FROM visits)")
        }
        XCTAssertTrue(try db.isSeen("p"))
    }

    func testSeenAmongIsBatched() throws {
        let db = try seededDB()
        XCTAssertEqual(try db.seen(among: ["p_seen", "p_unseen"]), ["p_seen"])
    }

    func testListProgressCountsSnapshotBackedRowsShownByTheList() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 0) })
        try db.dbQueue.write { d in
            for p in ["a", "b", "c"] {
                try d.execute(
                    sql: "INSERT INTO list_items (list_id, place_id, added_at) VALUES (1, ?, 0)",
                    arguments: [p]
                )
            }
            for p in ["a", "b"] {
                try d.execute(
                    sql: """
                        INSERT INTO place_snapshots
                        (place_id, name, lat, lon, category, tier, snapshot_json, snapshot_schema_version, fetched_at)
                        VALUES (?, ?, 51.5, -0.12, 'history', 1, '{}', 1, 0)
                        """,
                    arguments: [p, p.uppercased()]
                )
            }
            try d.execute(sql: "INSERT INTO visits (place_id, visited_at, created_at) VALUES ('a', 1, 1)")
            try d.execute(sql: "INSERT INTO visits (place_id, visited_at, created_at) VALUES ('c', 1, 1)")
        }
        let p = try db.listProgress(listID: 1)
        XCTAssertEqual(p.total, 2)
        XCTAssertEqual(p.visited, 1)
    }

    func testEmptyViewportReturnsEmpty() throws {
        XCTAssertEqual(try AppDatabase.inMemory().viewportState([]), [:])
    }

    func testTrackVisitsAreChronologicalSnapshotBackedAndExcludeHiddenPlaces() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 0) })
        try db.dbQueue.write { d in
            try insertSnapshot(d, placeID: "old", name: "Old Plaque", category: "history", lat: 51.50, lon: -0.12, tier: 2)
            try insertSnapshot(d, placeID: "hidden", name: "Hidden Marker", category: "oddity", lat: 51.51, lon: -0.13, tier: 3)
            try insertSnapshot(d, placeID: "new", name: "New Arcade", category: "architecture", lat: 51.52, lon: -0.14, tier: 1)
            try d.execute(sql: "INSERT INTO visits (place_id, visited_at, created_at) VALUES ('new', 30, 30)")
            try d.execute(sql: "INSERT INTO visits (place_id, visited_at, created_at) VALUES ('hidden', 20, 20)")
            try d.execute(sql: "INSERT INTO visits (place_id, visited_at, created_at) VALUES ('old', 10, 10)")
            try d.execute(sql: "INSERT INTO hidden_places (place_id, hidden_at) VALUES ('hidden', 40)")
        }

        let visits = try db.trackVisits()

        XCTAssertEqual(visits.map(\.placeID), ["old", "new"])
        XCTAssertEqual(visits.map(\.name), ["Old Plaque", "New Arcade"])
        XCTAssertEqual(visits.map(\.category), ["history", "architecture"])
        XCTAssertEqual(visits.map(\.tier), [2, 1])
    }

    func testTrackVisitsDocumentVisitIDTieBreakOrder() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 0) })
        let timestamp = Date(timeIntervalSince1970: 10)
        try db.dbQueue.write { d in
            try insertSnapshot(d, placeID: "first", name: "First", category: "history", lat: 51.50, lon: -0.12, tier: 2)
            try insertSnapshot(d, placeID: "second", name: "Second", category: "architecture", lat: 51.51, lon: -0.13, tier: 2)
            try insertVisit(d, placeID: "first", timestamp: timestamp)
            try insertVisit(d, placeID: "second", timestamp: timestamp)
        }

        let visits = try db.trackVisits()

        XCTAssertEqual(visits.map(\.placeID), ["first", "second"])
        XCTAssertEqual(visits.map(\.id), visits.map(\.id).sorted())
    }

    private func insertSnapshot(
        _ db: Database,
        placeID: String,
        name: String,
        category: String,
        lat: Double,
        lon: Double,
        tier: Int
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO place_snapshots
                (place_id, name, lat, lon, category, tier, snapshot_json, snapshot_schema_version, fetched_at)
                VALUES (?, ?, ?, ?, ?, ?, '{}', 1, 0)
                """,
            arguments: [placeID, name, lat, lon, category, tier]
        )
    }

    private func insertVisit(_ db: Database, placeID: String, timestamp: Date, verdict: Verdict? = nil) throws {
        try db.execute(
            sql: "INSERT INTO visits (place_id, visited_at, verdict, created_at) VALUES (?, ?, ?, ?)",
            arguments: [placeID, timestamp, verdict?.rawValue, timestamp]
        )
    }
}
