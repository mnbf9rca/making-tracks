import Foundation
import GRDB

extension AppDatabase {
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

    public func addToList(_ place: PlaceRef, listID: Int64) throws {
        try dbQueue.write { db in
            try snapshotIfNeeded(place, db)
            try db.execute(
                sql: """
                    INSERT OR IGNORE INTO list_items (list_id, place_id, added_at)
                    VALUES (?, ?, ?)
                    """,
                arguments: [listID, place.placeID, now()]
            )
        }
    }
}
