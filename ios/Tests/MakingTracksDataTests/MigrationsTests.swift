import XCTest
import GRDB
@testable import MakingTracksData

final class MigrationsTests: XCTestCase {
    func testSchemaMatchesSection54Exactly() throws {
        let db = try AppDatabase.inMemory()
        try db.dbQueue.read { d in
            func cols(_ t: String) throws -> Set<String> {
                Set(try d.columns(in: t).map(\.name))
            }

            XCTAssertEqual(try cols("visits"), ["id", "place_id", "visited_at", "verdict", "created_at"])
            XCTAssertEqual(try cols("lists"), ["id", "name", "is_system", "created_at"])
            XCTAssertEqual(try cols("list_items"), ["list_id", "place_id", "added_at"])
            XCTAssertEqual(
                try cols("place_snapshots"),
                [
                    "place_id",
                    "name",
                    "lat",
                    "lon",
                    "category",
                    "tier",
                    "snapshot_json",
                    "snapshot_schema_version",
                    "fetched_at",
                ]
            )
            XCTAssertEqual(try d.primaryKey("list_items").columns, ["list_id", "place_id"])
            let vIdx = try d.indexes(on: "visits").first { $0.name == "idx_visits_place" }
            let liIdx = try d.indexes(on: "list_items").first { $0.name == "idx_list_items_place" }
            XCTAssertEqual(vIdx?.columns, ["place_id"])
            XCTAssertEqual(liIdx?.columns, ["place_id"])
        }
    }

    func testNoSpatialRTreeTableExists() throws {
        let db = try AppDatabase.inMemory()
        let rtree = try db.dbQueue.read {
            try Int.fetchOne(
                $0,
                sql: "SELECT COUNT(*) FROM sqlite_master WHERE lower(sql) LIKE '%rtree%'"
            )
        } ?? 0
        XCTAssertEqual(rtree, 0)
    }

    func testSystemListNotDoubleSeededAcrossReopen() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("mt-\(UUID().uuidString).sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }

        for _ in 0..<2 {
            let db = try AppDatabase(
                try DatabaseQueue(path: path),
                now: { Date(timeIntervalSince1970: 0) }
            )
            _ = db
        }
        let db = try AppDatabase(
            try DatabaseQueue(path: path),
            now: { Date(timeIntervalSince1970: 0) }
        )
        let n = try db.dbQueue.read {
            try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM lists WHERE is_system = 1")
        }
        XCTAssertEqual(n, 1)
    }

    func testSeedsWantToGoSystemListExactlyOnce() throws {
        let db = try AppDatabase.inMemory()
        let rows = try db.dbQueue.read {
            try Row.fetchAll($0, sql: "SELECT name, is_system FROM lists")
        }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0]["name"], "Want to go")
        XCTAssertEqual(rows[0]["is_system"], true)
    }

    func testRefusesDatabaseFromNewerAppVersion() throws {
        let queue = try DatabaseQueue()
        try queue.write { d in
            try d.execute(sql: "CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY)")
            try d.execute(sql: "INSERT INTO grdb_migrations (identifier) VALUES ('v1'), ('v2_future')")
        }
        XCTAssertThrowsError(try AppDatabase(queue, now: { Date() })) { err in
            guard case AppDatabaseError.databaseFromNewerAppVersion(let unknown) = err else {
                return XCTFail("expected databaseFromNewerAppVersion, got \(err)")
            }
            XCTAssertTrue(unknown.contains("v2_future"))
        }
    }
}
