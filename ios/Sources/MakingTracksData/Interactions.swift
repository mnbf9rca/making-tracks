import Foundation
import GRDB

extension AppDatabase {
    private static let maxListNameScalars = 80

    static func normalizedListName(_ name: String) throws -> String {
        let filtered = String(name.unicodeScalars.filter { !isUnsafeListNameScalar($0) })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !filtered.isEmpty,
              filtered.unicodeScalars.count <= maxListNameScalars
        else {
            throw AppDatabaseError.invalidListName
        }
        return filtered
    }

    private static func isUnsafeListNameScalar(_ scalar: Unicode.Scalar) -> Bool {
        if CharacterSet.controlCharacters.contains(scalar) { return true }
        switch scalar.value {
        case 0x200B...0x200F, 0x202A...0x202E, 0x2060...0x206F, 0xFEFF:
            return true
        default:
            return false
        }
    }

    public func createList(named name: String) throws -> PlaceList {
        let normalized = try Self.normalizedListName(name)
        return try dbQueue.write { db in
            var list = PlaceList(
                id: nil,
                name: normalized,
                isSystem: false,
                createdAt: now()
            )
            try list.insert(db)
            return list
        }
    }

    public func renameList(id: Int64, name: String) throws -> PlaceList {
        let normalized = try Self.normalizedListName(name)
        return try dbQueue.write { db in
            guard let existing = try PlaceList.fetchOne(db, key: id) else {
                throw AppDatabaseError.unreadableDatabase
            }
            guard !existing.isSystem else {
                throw AppDatabaseError.systemListIsProtected
            }
            var renamed = existing
            renamed.name = normalized
            try renamed.update(db)
            return renamed
        }
    }

    public func deleteList(id: Int64) throws {
        try dbQueue.write { db in
            guard let existing = try PlaceList.fetchOne(db, key: id) else {
                throw AppDatabaseError.unreadableDatabase
            }
            guard !existing.isSystem else {
                throw AppDatabaseError.systemListIsProtected
            }
            _ = try existing.delete(db)
        }
    }

    func snapshotIfNeeded(_ place: PlaceRef, _ db: Database) throws {
        let exists = try Bool.fetchOne(
            db,
            sql: "SELECT EXISTS(SELECT 1 FROM place_snapshots WHERE place_id = ?)",
            arguments: [place.placeID]
        ) ?? false
        guard !exists else { return }

        let snapshot = PlaceSnapshot(
            placeID: place.placeID,
            name: place.name,
            lat: place.lat,
            lon: place.lon,
            category: place.category,
            tier: place.tier,
            snapshotJSON: place.rawJSON,
            snapshotSchemaVersion: place.schemaVersion,
            fetchedAt: place.fetchedAt
        )
        try snapshot.insert(db)
    }

    @discardableResult
    public func recordVisit(_ place: PlaceRef, verdict: Verdict? = nil) throws -> Int64 {
        try dbQueue.write { db in
            try snapshotIfNeeded(place, db)
            let timestamp = now()
            var visit = Visit(
                id: nil,
                placeID: place.placeID,
                visitedAt: timestamp,
                verdict: verdict,
                createdAt: timestamp
            )
            try visit.insert(db)
            return visit.id!
        }
    }

    public func deleteVisit(id: Int64) throws {
        try dbQueue.write { db in
            _ = try Visit.deleteOne(db, key: id)
        }
    }

    public func deleteVisits(placeID: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM visits WHERE place_id = ?",
                arguments: [placeID]
            )
        }
    }

    public func addToList(_ place: PlaceRef, listID: Int64) throws {
        try dbQueue.write { db in
            try snapshotIfNeeded(place, db)
            do {
                try db.execute(
                    sql: """
                        INSERT INTO list_items (list_id, place_id, added_at)
                        VALUES (?, ?, ?)
                        """,
                    arguments: [listID, place.placeID, now()]
                )
            } catch let error as DatabaseError
                where error.extendedResultCode == .SQLITE_CONSTRAINT_PRIMARYKEY ||
                    error.extendedResultCode == .SQLITE_CONSTRAINT_UNIQUE {
                // Idempotent save: only an existing (list_id, place_id) row is ignored.
            }
        }
    }

    public func removeFromList(placeID: String, listID: Int64) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM list_items WHERE list_id = ? AND place_id = ?",
                arguments: [listID, placeID]
            )
        }
    }

    public func setLoved(placeID: String, _ loved: Bool) throws {
        try dbQueue.write { db in
            if loved {
                try db.execute(
                    sql: """
                        UPDATE visits
                        SET verdict = ?
                        WHERE id = (
                            SELECT id FROM visits
                            WHERE place_id = ?
                            ORDER BY visited_at DESC, id DESC
                            LIMIT 1
                        )
                        """,
                    arguments: [Verdict.loved.rawValue, placeID]
                )
            } else {
                try db.execute(
                    sql: "UPDATE visits SET verdict = NULL WHERE place_id = ?",
                    arguments: [placeID]
                )
            }
        }
    }

    public func setHidden(_ place: PlaceRef, _ hidden: Bool) throws {
        try dbQueue.write { db in
            if hidden {
                try snapshotIfNeeded(place, db)
                try db.execute(
                    sql: """
                        INSERT INTO hidden_places (place_id, hidden_at)
                        VALUES (?, ?)
                        ON CONFLICT(place_id) DO NOTHING
                        """,
                    arguments: [place.placeID, now()]
                )
            } else {
                try db.execute(
                    sql: "DELETE FROM hidden_places WHERE place_id = ?",
                    arguments: [place.placeID]
                )
            }
        }
    }

    public func unhide(placeID: String) throws {
    // Data-layer helper for tests and non-live maintenance only. Live UI flows must
    // route through CoreLoopController.setHidden so observers receive invalidation.
        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM hidden_places WHERE place_id = ?",
                arguments: [placeID]
            )
        }
    }

    public func wantToGoListID() throws -> Int64 {
        try dbQueue.read { db in
            guard let id = try Int64.fetchOne(
                db,
                sql: "SELECT id FROM lists WHERE is_system = 1 AND name = ? ORDER BY id LIMIT 1",
                arguments: [Self.wantToGoListName]
            ) else {
                throw AppDatabaseError.unreadableDatabase
            }
            return id
        }
    }

    public func snapshot(for placeID: String) throws -> PlaceSnapshot? {
        try dbQueue.read { db in
            try PlaceSnapshot.fetchOne(db, key: placeID)
        }
    }

#if DEBUG
    public func seedUITestingUserList(named name: String, containingPlaceID placeID: String) throws {
        try dbQueue.write { db in
            let timestamp = now()
            let listID: Int64
            if let existingID = try Int64.fetchOne(
                db,
                sql: "SELECT id FROM lists WHERE is_system = 0 AND name = ? ORDER BY id LIMIT 1",
                arguments: [name]
            ) {
                listID = existingID
            } else {
                try db.execute(
                    sql: "INSERT INTO lists (name, is_system, created_at) VALUES (?, ?, ?)",
                    arguments: [name, false, timestamp]
                )
                listID = db.lastInsertedRowID
            }

            try db.execute(
                sql: """
                    INSERT OR IGNORE INTO list_items (list_id, place_id, added_at)
                    VALUES (?, ?, ?)
                    """,
                arguments: [listID, placeID, timestamp]
            )
        }
    }
#endif
}
