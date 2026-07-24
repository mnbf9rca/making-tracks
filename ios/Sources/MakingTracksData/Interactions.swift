import Foundation
import GRDB

extension AppDatabase {
    private static let maxListNameScalars = 80

    static func normalizedListName(_ name: String) throws -> String {
        let filtered = String(name.unicodeScalars.filter { !isUnsafeListNameScalar($0) })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !filtered.isEmpty else {
            throw AppDatabaseError.emptyListName
        }
        guard filtered.unicodeScalars.count <= maxListNameScalars else {
            throw AppDatabaseError.listNameTooLong
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

    @discardableResult
    public func deleteList(id: Int64) throws -> Set<String> {
        try dbQueue.write { db in
            guard let existing = try PlaceList.fetchOne(db, key: id) else {
                throw AppDatabaseError.unreadableDatabase
            }
            guard !existing.isSystem else {
                throw AppDatabaseError.systemListIsProtected
            }
            let affectedPlaceIDs = Set(
                try String.fetchAll(
                    db,
                    sql: "SELECT place_id FROM list_items WHERE list_id = ?",
                    arguments: [id]
                )
            )
            _ = try existing.delete(db)
            return affectedPlaceIDs
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
        try recordVisit(place, at: now(), verdict: verdict)
    }

    @discardableResult
    public func recordVisit(_ place: PlaceRef, at visitedAt: Date, verdict: Verdict? = nil) throws -> Int64 {
        try dbQueue.write { db in
            try snapshotIfNeeded(place, db)
            let createdAt = now()
            let order = try nextVisitOrder(onDayContaining: visitedAt, calendar: Self.visitEditCalendar, db)
            var visit = Visit(
                id: nil,
                placeID: place.placeID,
                visitedAt: visitedAt,
                verdict: verdict,
                createdAt: createdAt,
                visitOrder: order
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

    // Data-layer helper for tests and maintenance only. Product un-see flows
    // route through deleteLatestVisit so older visit history is preserved.
    func deleteVisits(placeID: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM visits WHERE place_id = ?",
                arguments: [placeID]
            )
        }
    }

    @discardableResult
    public func deleteLatestVisit(placeID: String) throws -> Bool {
        try dbQueue.write { db in
            let visits = try Visit.fetchAll(
                db,
                sql: "SELECT * FROM visits WHERE place_id = ?",
                arguments: [placeID]
            )
            guard let id = visits.sorted(by: Self.visitSortIsBefore).last?.id else {
                return false
            }
            _ = try Visit.deleteOne(db, key: id)
            return true
        }
    }

    public func addToList(_ place: PlaceRef, listID: Int64) throws {
        try dbQueue.write { db in
            guard try !Self.isTrackList(listID: listID, db) else {
                throw AppDatabaseError.systemListIsProtected
            }
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
            guard try !Self.isTrackList(listID: listID, db) else {
                throw AppDatabaseError.systemListIsProtected
            }
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
                    sql: "UPDATE visits SET verdict = ? WHERE place_id = ?",
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

    @discardableResult
    public func setVisitVerdict(id: Int64, _ verdict: Verdict?) throws -> String? {
        try dbQueue.write { db in
            let placeID = try String.fetchOne(
                db,
                sql: "SELECT place_id FROM visits WHERE id = ?",
                arguments: [id]
            )
            guard let placeID else { return nil }
            try db.execute(
                sql: "UPDATE visits SET verdict = ? WHERE place_id = ?",
                arguments: [verdict?.rawValue, placeID]
            )
            return placeID
        }
    }

    public func updateVisitDate(
        id: Int64,
        toDayContaining targetDay: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) throws {
        try dbQueue.write { db in
            guard let existing = try Visit.fetchOne(db, key: id),
                  let movedAt = Self.replacingDay(of: existing.visitedAt, withDayContaining: targetDay, calendar: calendar)
            else {
                throw AppDatabaseError.unreadableDatabase
            }
            let oldDay = calendar.startOfDay(for: existing.visitedAt)
            let newDay = calendar.startOfDay(for: movedAt)
            let nextOrder = oldDay == newDay
                ? existing.visitOrder
                : try nextVisitOrder(onDayContaining: movedAt, calendar: calendar, db)
            try db.execute(
                sql: "UPDATE visits SET visited_at = ?, visit_order = ? WHERE id = ?",
                arguments: [movedAt, nextOrder, id]
            )
        }
    }

    public func reorderVisitsWithinDay(
        _ orderedIDs: [Int64],
        dayContaining day: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) throws {
        try dbQueue.write { db in
            let bounds = Self.dayBounds(containing: day, calendar: calendar)
            let idsInDay = try Set(Int64.fetchAll(
                db,
                sql: "SELECT id FROM visits WHERE visited_at >= ? AND visited_at < ?",
                arguments: [bounds.start, bounds.end]
            ))
            guard idsInDay == Set(orderedIDs), orderedIDs.count == idsInDay.count else {
                throw AppDatabaseError.unreadableDatabase
            }
            for (index, id) in orderedIDs.enumerated() {
                try db.execute(
                    sql: "UPDATE visits SET visit_order = ? WHERE id = ?",
                    arguments: [index, id]
                )
            }
        }
    }

    public func moveVisit(
        id: Int64,
        toDayContaining targetDay: Date,
        targetDayOrderedIDs orderedIDs: [Int64],
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) throws {
        try dbQueue.write { db in
            guard let existing = try Visit.fetchOne(db, key: id),
                  let movedAt = Self.replacingDay(of: existing.visitedAt, withDayContaining: targetDay, calendar: calendar)
            else {
                throw AppDatabaseError.unreadableDatabase
            }
            let bounds = Self.dayBounds(containing: movedAt, calendar: calendar)
            let idsInTargetDay = try Set(Int64.fetchAll(
                db,
                sql: "SELECT id FROM visits WHERE visited_at >= ? AND visited_at < ? AND id != ?",
                arguments: [bounds.start, bounds.end, id]
            ))
            let expectedIDs = idsInTargetDay.union([id])
            guard Set(orderedIDs) == expectedIDs, orderedIDs.count == expectedIDs.count else {
                throw AppDatabaseError.unreadableDatabase
            }

            try db.execute(
                sql: "UPDATE visits SET visited_at = ? WHERE id = ?",
                arguments: [movedAt, id]
            )
            for (index, orderedID) in orderedIDs.enumerated() {
                try db.execute(
                    sql: "UPDATE visits SET visit_order = ? WHERE id = ?",
                    arguments: [index, orderedID]
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

    private static func isTrackList(listID: Int64, _ db: Database) throws -> Bool {
        try Bool.fetchOne(
            db,
            sql: "SELECT EXISTS(SELECT 1 FROM lists WHERE id = ? AND is_system = 1 AND list_kind = ?)",
            arguments: [listID, PlaceList.trackKind]
        ) ?? false
    }

    static var visitEditCalendar: Calendar {
        Calendar(identifier: .gregorian)
    }

    static func dayBounds(containing day: Date, calendar: Calendar) -> (start: Date, end: Date) {
        let start = calendar.startOfDay(for: day)
        return (start, calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(60 * 60 * 24))
    }

    private func nextVisitOrder(onDayContaining day: Date, calendar: Calendar, _ db: Database) throws -> Int {
        let bounds = Self.dayBounds(containing: day, calendar: calendar)
        let maxOrder = try Int.fetchOne(
            db,
            sql: "SELECT MAX(visit_order) FROM visits WHERE visited_at >= ? AND visited_at < ?",
            arguments: [bounds.start, bounds.end]
        )
        return (maxOrder ?? -1) + 1
    }

    private static func replacingDay(of original: Date, withDayContaining targetDay: Date, calendar: Calendar) -> Date? {
        let day = calendar.dateComponents([.era, .year, .month, .day], from: targetDay)
        let time = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: original)
        var moved = DateComponents()
        moved.calendar = calendar
        moved.era = day.era
        moved.year = day.year
        moved.month = day.month
        moved.day = day.day
        moved.hour = time.hour
        moved.minute = time.minute
        moved.second = time.second
        moved.nanosecond = time.nanosecond
        return calendar.date(from: moved)
    }

    private static func visitSortIsBefore(_ lhs: Visit, _ rhs: Visit) -> Bool {
        let calendar = visitEditCalendar
        let leftDay = calendar.startOfDay(for: lhs.visitedAt)
        let rightDay = calendar.startOfDay(for: rhs.visitedAt)
        if leftDay != rightDay { return leftDay < rightDay }
        if lhs.visitOrder != rhs.visitOrder { return lhs.visitOrder < rhs.visitOrder }
        if lhs.visitedAt != rhs.visitedAt { return lhs.visitedAt < rhs.visitedAt }
        return (lhs.id ?? 0) < (rhs.id ?? 0)
    }

    public func snapshot(for placeID: String) throws -> PlaceSnapshot? {
        try dbQueue.read { db in
            try PlaceSnapshot.fetchOne(db, key: placeID)
        }
    }

#if DEBUG
    public func seedUITestingTrackVisits(_ places: [PlaceRef], multiDay: Bool = false) throws {
        try dbQueue.write { db in
            let seedStart = Date(timeIntervalSince1970: 1_000)
            for (index, place) in places.enumerated() {
                try snapshotIfNeeded(place, db)
                let dayOffset: Double = multiDay && index >= 4 ? 24 * 60 * 60 : 0
                let timestamp = seedStart.addingTimeInterval(dayOffset + Double(index % 4) * 60 * 60)
                var visit = Visit(
                    id: nil,
                    placeID: place.placeID,
                    visitedAt: timestamp,
                    verdict: nil,
                    createdAt: timestamp
                )
                try visit.insert(db)
            }
        }
    }

    public func seedUITestingBurstTrackVisits(_ places: [PlaceRef]) throws {
        try dbQueue.write { db in
            let seedStart = Date(timeIntervalSince1970: 1_000)
            for (index, place) in places.enumerated() {
                try snapshotIfNeeded(place, db)
                let timestamp = seedStart.addingTimeInterval(Double(index) * 45)
                var visit = Visit(
                    id: nil,
                    placeID: place.placeID,
                    visitedAt: timestamp,
                    verdict: nil,
                    createdAt: timestamp
                )
                try visit.insert(db)
            }
        }
    }

    public func seedUITestingTrackList(named name: String, places: [PlaceRef]) throws {
        try seedUITestingTrackList(named: name, places: places, spacing: 60 * 60, lovedVisitIndex: nil)
    }

    public func seedUITestingMultiDayTrackList(
        named name: String,
        places: [PlaceRef],
        lovedVisitIndex: Int? = nil
    ) throws {
        try seedUITestingTrackList(
            named: name,
            places: Array(places.prefix(6)),
            seedStart: Self.uiTestingMultiDayTrackSeedStart,
            offsets: Self.uiTestingMultiDayTrackOffsets,
            lovedVisitIndex: lovedVisitIndex
        )
    }

    private static let uiTestingMultiDayTrackOffsets: [TimeInterval] = [
        0,
        (4 * 60 * 60) + (35 * 60),
        (26 * 60 * 60) + (10 * 60),
        (49 * 60 * 60) + (45 * 60),
        (84 * 60 * 60) + (25 * 60),
        (125 * 60 * 60) + (50 * 60),
    ]

    private static var uiTestingMultiDayTrackSeedStart: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026,
            month: 7,
            day: 14,
            hour: 9,
            minute: 20
        ))!
    }

    private func seedUITestingTrackList(
        named name: String,
        places: [PlaceRef],
        spacing: TimeInterval,
        lovedVisitIndex: Int?
    ) throws {
        try seedUITestingTrackList(
            named: name,
            places: places,
            seedStart: Date(timeIntervalSince1970: 1_000),
            offsets: places.indices.map { Double($0) * spacing },
            lovedVisitIndex: lovedVisitIndex
        )
    }

    private func seedUITestingTrackList(
        named name: String,
        places: [PlaceRef],
        seedStart: Date,
        offsets: [TimeInterval],
        lovedVisitIndex: Int?
    ) throws {
        let normalized = try Self.normalizedListName(name)
        try dbQueue.write { db in
            try db.execute(
                sql: "INSERT INTO lists (name, is_system, created_at, list_kind) VALUES (?, ?, ?, ?)",
                arguments: [normalized, false, seedStart, PlaceList.trackKind]
            )
            let listID = db.lastInsertedRowID
            for (index, place) in places.enumerated() {
                try snapshotIfNeeded(place, db)
                let timestamp = seedStart.addingTimeInterval(offsets[index])
                var visit = Visit(
                    id: nil,
                    placeID: place.placeID,
                    visitedAt: timestamp,
                    verdict: lovedVisitIndex == index ? .loved : nil,
                    createdAt: timestamp
                )
                try visit.insert(db)
                try db.execute(
                    sql: """
                        INSERT OR IGNORE INTO list_items (list_id, place_id, added_at)
                        VALUES (?, ?, ?)
                        """,
                    arguments: [listID, place.placeID, timestamp]
                )
            }
        }
    }

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
