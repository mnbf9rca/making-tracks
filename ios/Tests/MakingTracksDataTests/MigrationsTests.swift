import XCTest
import GRDB
@testable import MakingTracksData

final class MigrationsTests: XCTestCase {
    func testSchemaIncludesCurrentLocalStateTables() throws {
        let db = try AppDatabase.inMemory()
        try db.dbQueue.read { d in
            func cols(_ t: String) throws -> Set<String> {
                Set(try d.columns(in: t).map(\.name))
            }

            XCTAssertEqual(try cols("visits"), ["id", "place_id", "visited_at", "verdict", "created_at"])
            XCTAssertEqual(try cols("lists"), ["id", "name", "is_system", "created_at"])
            XCTAssertEqual(try cols("list_items"), ["list_id", "place_id", "added_at"])
            XCTAssertEqual(try cols("hidden_places"), ["place_id", "hidden_at"])
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
            XCTAssertEqual(try d.primaryKey("hidden_places").columns, ["place_id"])
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

    func testV1DatabaseMigratesToV2WithoutLosingUserRows() throws {
        let queue = try DatabaseQueue()
        let timestamp = Date(timeIntervalSince1970: 12)
        try queue.write { db in
            try db.execute(sql: "CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY)")
            try db.execute(sql: "INSERT INTO grdb_migrations (identifier) VALUES ('v1')")
            try db.create(table: "visits") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("place_id", .text).notNull()
                t.column("visited_at", .datetime).notNull()
                t.column("verdict", .text)
                t.column("created_at", .datetime).notNull()
            }
            try db.create(index: "idx_visits_place", on: "visits", columns: ["place_id"])
            try db.create(table: "lists") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("is_system", .boolean).notNull().defaults(to: false)
                t.column("created_at", .datetime).notNull()
            }
            try db.create(table: "list_items") { t in
                t.column("list_id", .integer).notNull().references("lists", onDelete: .cascade)
                t.column("place_id", .text).notNull()
                t.column("added_at", .datetime).notNull()
                t.primaryKey(["list_id", "place_id"])
            }
            try db.create(index: "idx_list_items_place", on: "list_items", columns: ["place_id"])
            try db.create(table: "place_snapshots") { t in
                t.column("place_id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("lat", .double).notNull()
                t.column("lon", .double).notNull()
                t.column("category", .text).notNull()
                t.column("tier", .integer).notNull()
                t.column("snapshot_json", .text).notNull()
                t.column("snapshot_schema_version", .integer).notNull()
                t.column("fetched_at", .datetime).notNull()
            }
            try db.execute(sql: "INSERT INTO lists (id, name, is_system, created_at) VALUES (1, 'Want to go', 1, ?)", arguments: [timestamp])
            try db.execute(sql: "INSERT INTO visits (place_id, visited_at, verdict, created_at) VALUES ('p1', ?, 'loved', ?)", arguments: [timestamp, timestamp])
            try db.execute(sql: "INSERT INTO list_items (list_id, place_id, added_at) VALUES (1, 'p1', ?)", arguments: [timestamp])
            try db.execute(sql: """
                INSERT INTO place_snapshots
                (place_id, name, lat, lon, category, tier, snapshot_json, snapshot_schema_version, fetched_at)
                VALUES ('p1', 'Ghost Sign', 3.14, 101.69, 'artwork', 2, '{}', 1, ?)
                """, arguments: [timestamp])
        }

        let db = try AppDatabase(queue, now: { Date(timeIntervalSince1970: 100) })

        XCTAssertEqual(try db.appliedMigrations, ["v1", "v2"])
        XCTAssertEqual(try db.viewportState(["p1"])["p1"], PinState(saved: true, visit: .loved, hidden: false))
        XCTAssertEqual(try db.hiddenPlaceIDs(), [])
        XCTAssertEqual(try db.snapshot(for: "p1")?.name, "Ghost Sign")
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
