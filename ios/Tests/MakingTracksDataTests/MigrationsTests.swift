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

            XCTAssertEqual(try cols("visits"), ["id", "place_id", "visited_at", "verdict", "created_at", "visit_order"])
            XCTAssertEqual(try cols("lists"), ["id", "name", "is_system", "created_at", "list_kind"])
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
        XCTAssertEqual(n, 2)
    }

    func testV1DatabaseMigratesToCurrentSchemaWithoutLosingUserRows() throws {
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

        XCTAssertEqual(try db.appliedMigrations, ["v1", "v2", "v3", "v4", "v5", "v6"])
        XCTAssertEqual(try db.viewportState(["p1"])["p1"], PinState(saved: true, visit: .loved, hidden: false))
        XCTAssertEqual(try db.hiddenPlaceIDs(), [])
        XCTAssertEqual(try db.snapshot(for: "p1")?.name, "Ghost Sign")
        let visitOrder = try db.dbQueue.read {
            try Int.fetchOne($0, sql: "SELECT visit_order FROM visits WHERE place_id = 'p1'")
        }
        XCTAssertEqual(visitOrder, 0)
        let listKind = try db.dbQueue.read {
            try String.fetchOne($0, sql: "SELECT list_kind FROM lists WHERE id = 1")
        }
        XCTAssertEqual(listKind, PlaceList.defaultKind)
    }

    func testV2DatabaseMigratesToCurrentSchemaAndRepairsSavedHiddenOverlap() throws {
        let queue = try DatabaseQueue()
        let timestamp = Date(timeIntervalSince1970: 12)
        try queue.write { db in
            try db.execute(sql: "CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY)")
            try db.execute(sql: "INSERT INTO grdb_migrations (identifier) VALUES ('v1'), ('v2')")
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
            try db.create(table: "hidden_places") { t in
                t.column("place_id", .text).primaryKey()
                t.column("hidden_at", .datetime).notNull()
            }
            try db.execute(sql: "INSERT INTO lists (id, name, is_system, created_at) VALUES (1, 'Want to go', 1, ?), (2, 'KL trip', 0, ?)", arguments: [timestamp, timestamp])
            try db.execute(sql: "INSERT INTO hidden_places (place_id, hidden_at) VALUES ('p1', ?)", arguments: [timestamp])
            try db.execute(sql: "INSERT INTO list_items (list_id, place_id, added_at) VALUES (2, 'p1', ?)", arguments: [timestamp])
        }

        let db = try AppDatabase(queue, now: { Date(timeIntervalSince1970: 100) })

        XCTAssertEqual(try db.appliedMigrations, ["v1", "v2", "v3", "v4", "v5", "v6"])
        XCTAssertEqual(try db.hiddenPlaceIDs(), [])
        let rows = try db.dbQueue.read {
            try Row.fetchAll($0, sql: "SELECT id, name, is_system, list_kind FROM lists ORDER BY id")
        }
        XCTAssertEqual(rows.map { $0["name"] as String }, ["Want to go", "KL trip", "My tracks"])
        XCTAssertEqual(rows.map { $0["list_kind"] as String }, [PlaceList.defaultKind, PlaceList.defaultKind, PlaceList.trackKind])
        XCTAssertEqual(try db.listMemberships(containing: "p1"), [2])
    }

    func testSeedsSystemListsExactlyOnce() throws {
        let db = try AppDatabase.inMemory()
        let rows = try db.dbQueue.read {
            try Row.fetchAll($0, sql: "SELECT name, is_system, list_kind FROM lists ORDER BY name")
        }
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.map { $0["name"] as String }, ["My tracks", "Want to go"])
        XCTAssertEqual(rows.map { $0["is_system"] as Bool }, [true, true])
        XCTAssertEqual(rows.map { $0["list_kind"] as String }, [PlaceList.trackKind, PlaceList.defaultKind])
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

    func testV5MigrationAutoUnhidesSavedRowsWithoutDestroyingUserData() throws {
        let timestamp = Date(timeIntervalSince1970: 12)
        let queue = try makeV5Queue()
        let db = try AppDatabase(queue, now: { Date(timeIntervalSince1970: 100) })

        XCTAssertEqual(try db.appliedMigrations, ["v1", "v2", "v3", "v4", "v5", "v6"])
        XCTAssertEqual(try db.hiddenPlaceIDs(), ["hidden-only"])
        XCTAssertEqual(try db.listMemberships(containing: "system-coexisting"), [1])
        XCTAssertEqual(try db.listMemberships(containing: "coexisting"), [3, 2])
        XCTAssertEqual(try db.listMemberships(containing: "saved-only"), [2])
        XCTAssertEqual(
            try db.viewportState(["system-coexisting"])["system-coexisting"],
            PinState(saved: true, visit: .none, hidden: false)
        )
        XCTAssertEqual(
            try db.viewportState(["coexisting"])["coexisting"],
            PinState(saved: true, visit: .loved, hidden: false)
        )
        XCTAssertEqual(try db.snapshot(for: "system-coexisting")?.name, "System coexisting")
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
                    VALUES
                        (1, 'system-coexisting', ?),
                        (2, 'coexisting', ?),
                        (2, 'saved-only', ?)
                    """,
                arguments: [timestamp, timestamp, timestamp]
            )
            try db.execute(
                sql: """
                    INSERT INTO hidden_places (place_id, hidden_at)
                    VALUES
                        ('system-coexisting', ?),
                        ('coexisting', ?),
                        ('hidden-only', ?)
                    """,
                arguments: [timestamp, timestamp, timestamp]
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
                ("system-coexisting", "System coexisting"),
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
}
