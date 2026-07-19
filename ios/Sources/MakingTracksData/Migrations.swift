import Foundation
import GRDB

extension AppDatabase {
    private func makeMigrator() -> (migrator: DatabaseMigrator, identifiers: [String]) {
        var migrator = DatabaseMigrator()
        var identifiers: [String] = []

        func register(_ id: String, _ body: @escaping @Sendable (Database) throws -> Void) {
            identifiers.append(id)
            migrator.registerMigration(id, migrate: body)
        }

        register("v1") { [now] db in
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
                t.column("list_id", .integer).notNull()
                    .references("lists", onDelete: .cascade)
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

            try db.execute(
                sql: "INSERT INTO lists (name, is_system, created_at) VALUES (?, ?, ?)",
                arguments: [AppDatabase.wantToGoListName, true, now()]
            )
        }

        register("v2") { db in
            try db.create(table: "hidden_places") { t in
                t.column("place_id", .text).primaryKey()
                t.column("hidden_at", .datetime).notNull()
            }
        }

        register("v3") { db in
            try db.alter(table: "lists") { t in
                t.add(column: "list_kind", .text).notNull().defaults(to: "collection")
            }
        }

        register("v4") { [now] db in
            try db.execute(
                sql: """
                    INSERT INTO lists (name, is_system, created_at, list_kind)
                    SELECT ?, ?, ?, ?
                    WHERE NOT EXISTS (
                        SELECT 1 FROM lists
                        WHERE is_system = 1 AND list_kind = ?
                    )
                    """,
                arguments: [
                    AppDatabase.myTracksListName,
                    true,
                    now(),
                    PlaceList.trackKind,
                    PlaceList.trackKind,
                ]
            )
        }

        return (migrator, identifiers)
    }

    var appliedMigrations: Set<String> {
        get throws {
            try dbQueue.read { db in
                guard try db.tableExists("grdb_migrations") else { return [] }
                do {
                    return try Set(
                        String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations")
                    )
                } catch {
                    throw AppDatabaseError.unreadableDatabase
                }
            }
        }
    }

    func migrate() throws {
        let (migrator, identifiers) = makeMigrator()
        let unknown = try appliedMigrations.subtracting(identifiers)
        if !unknown.isEmpty {
            throw AppDatabaseError.databaseFromNewerAppVersion(unknown: unknown)
        }
        try migrator.migrate(dbQueue)
    }
}
