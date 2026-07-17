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

    func testListProgressCountsVisitedOfTotal() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 0) })
        try db.dbQueue.write { d in
            for p in ["a", "b", "c"] {
                try d.execute(
                    sql: "INSERT INTO list_items (list_id, place_id, added_at) VALUES (1, ?, 0)",
                    arguments: [p]
                )
            }
            try d.execute(sql: "INSERT INTO visits (place_id, visited_at, created_at) VALUES ('a', 1, 1)")
        }
        let p = try db.listProgress(listID: 1)
        XCTAssertEqual(p.total, 3)
        XCTAssertEqual(p.visited, 1)
    }

    func testEmptyViewportReturnsEmpty() throws {
        XCTAssertEqual(try AppDatabase.inMemory().viewportState([]), [:])
    }
}
