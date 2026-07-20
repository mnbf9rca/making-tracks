import Foundation
import GRDB

public struct TrackGeometryContext: Sendable, Equatable {
    public static let empty = TrackGeometryContext(visits: [], sourceIndices: [])

    public let visits: [TrackVisit]
    public let sourceIndices: [Int]
    public let filteredBridgeCount: Int

    public init(visits: [TrackVisit], sourceIndices: [Int]) {
        self.visits = visits
        self.sourceIndices = Array(sourceIndices.prefix(visits.count))
        filteredBridgeCount = Self.bridgeCount(sourceIndices: self.sourceIndices)
    }

    public func clipped(throughEventIndex index: Int?) -> TrackGeometryContext {
        guard let index else { return self }
        guard index >= 0 else { return .empty }
        let count = min(index + 1, visits.count)
        return TrackGeometryContext(
            visits: Array(visits.prefix(count)),
            sourceIndices: Array(sourceIndices.prefix(count))
        )
    }

    private static func bridgeCount(sourceIndices: [Int]) -> Int {
        guard sourceIndices.count >= 2 else { return 0 }
        return zip(sourceIndices, sourceIndices.dropFirst()).reduce(0) { count, pair in
            count + max(pair.1 - pair.0 - 1, 0)
        }
    }
}

extension AppDatabase {
    public func lists() throws -> [PlaceList] {
        try dbQueue.read { db in
            try PlaceList.fetchAll(
                db,
                sql: """
                    SELECT * FROM lists
                    ORDER BY is_system DESC, name COLLATE NOCASE, id
                    """
            )
        }
    }

    public func listItems(listID: Int64) throws -> [ListPlace] {
        try dbQueue.read { db in
            let places = try Self.listSnapshots(listID: listID, db)
            let placeIDs = places.map(\.placeID)
            let states = try Self.viewportState(placeIDs, db)
            return places.map { place in
                return ListPlace(
                    placeID: place.placeID,
                    name: place.name,
                    category: place.category,
                    pinState: states[place.placeID] ?? PinState(saved: false, visit: .none)
                )
            }
        }
    }

    public func listMapFeatures(listID: Int64) throws -> [(MapPlace, PinState)] {
        try dbQueue.read { db in
            let places = try Self.listSnapshots(listID: listID, db)
            let placeIDs = places.map(\.placeID)
            let states = try Self.viewportState(placeIDs, db)
            return places.map { snapshot in
                let place = MapPlace(
                    id: snapshot.placeID,
                    lat: snapshot.lat,
                    lon: snapshot.lon,
                    tier: snapshot.tier,
                    category: snapshot.category
                )
                return (place, states[snapshot.placeID] ?? PinState(saved: false, visit: .none))
            }
        }
    }

    public func listMemberships(containing placeID: String) throws -> [Int64] {
        try dbQueue.read { db in
            try Int64.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT l.id
                    FROM lists l
                    LEFT JOIN list_items li ON li.list_id = l.id AND li.place_id = ?
                    WHERE li.place_id IS NOT NULL
                    OR (
                        l.is_system = 1
                        AND l.list_kind = ?
                        AND EXISTS(SELECT 1 FROM visits v WHERE v.place_id = ?)
                        AND NOT EXISTS(SELECT 1 FROM hidden_places h WHERE h.place_id = ?)
                    )
                    ORDER BY l.is_system DESC, l.name COLLATE NOCASE, li.list_id
                    """,
                arguments: [placeID, PlaceList.trackKind, placeID, placeID]
            )
        }
    }

    public func trackVisits(listID: Int64? = nil) throws -> [TrackVisit] {
        try trackGeometryContext(listID: listID).visits
    }

    public func filteredTrackBridgeCount(listID: Int64) throws -> Int {
        try trackGeometryContext(listID: listID).filteredBridgeCount
    }

    public func trackGeometryContext(listID: Int64? = nil) throws -> TrackGeometryContext {
        try dbQueue.read { db in
            try Self.trackGeometryContext(listID: listID, db)
        }
    }

    private static func trackGeometryContext(listID: Int64?, _ db: Database) throws -> TrackGeometryContext {
        let isTrackList: Bool
        if let listID {
            isTrackList = try Self.isTrackList(listID: listID, db)
        } else {
            isTrackList = true
        }

        let listPlaceIDs: Set<String>
        if let listID, !isTrackList {
            listPlaceIDs = Set(try String.fetchAll(
                db,
                sql: "SELECT place_id FROM list_items WHERE list_id = ?",
                arguments: [listID]
            ))
        } else {
            listPlaceIDs = []
        }
        let hiddenPlaceIDs = Set(try String.fetchAll(db, sql: "SELECT place_id FROM hidden_places"))
        // #257/#265: scoped tracks deliberately connect the rendered visit sequence continuously;
        // callers pair this with `filteredBridgeCount` when list scope or hiding removed visits.
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT v.id, v.place_id, v.visited_at, v.verdict,
                       s.name, s.category, s.tier, s.lat, s.lon
                FROM visits v
                JOIN place_snapshots s ON s.place_id = v.place_id
                ORDER BY v.visited_at ASC, v.id ASC
                """
        )
        let validVisits = rows.compactMap(Self.trackVisitRow)
        let rendered = validVisits.enumerated().compactMap { index, visit -> (TrackVisit, Int)? in
            guard !hiddenPlaceIDs.contains(visit.placeID) else { return nil }
            guard isTrackList || listPlaceIDs.contains(visit.placeID) else { return nil }
            return (visit, index)
        }
        return TrackGeometryContext(
            visits: rendered.map(\.0),
            sourceIndices: rendered.map(\.1)
        )
    }

    private static func listSnapshotRow(_ row: Row) -> ListSnapshotRow? {
        let placeID: String = row["place_id"]
        let name: String = row["name"]
        let lat: Double = row["lat"]
        let lon: Double = row["lon"]
        let category: String = row["category"]
        let tier: Int = row["tier"]
        guard placeID.count <= PlaceRef.maxPlaceIDLength,
              lat.isFinite,
              lon.isFinite,
              (-90.0...90.0).contains(lat),
              (-180.0...180.0).contains(lon),
              (1...4).contains(tier)
        else { return nil }

        return ListSnapshotRow(
            placeID: placeID,
            name: safeListSnapshotText(name, max: PlaceRef.maxNameLength) ?? "Unnamed place",
            lat: lat,
            lon: lon,
            category: safeListSnapshotText(category, max: PlaceRef.maxCategoryLength) ?? "place",
            tier: tier
        )
    }

    private static func trackVisitRow(_ row: Row) -> TrackVisit? {
        let id: Int64 = row["id"]
        let placeID: String = row["place_id"]
        let visitedAt: Date = row["visited_at"]
        let rawVerdict: String? = row["verdict"]
        let name: String = row["name"]
        let category: String = row["category"]
        let tier: Int = row["tier"]
        let lat: Double = row["lat"]
        let lon: Double = row["lon"]
        guard placeID.count <= PlaceRef.maxPlaceIDLength,
              lat.isFinite,
              lon.isFinite,
              (-90.0...90.0).contains(lat),
              (-180.0...180.0).contains(lon),
              (1...4).contains(tier)
        else { return nil }

        return TrackVisit(
            id: id,
            placeID: placeID,
            visitedAt: visitedAt,
            verdict: rawVerdict.flatMap(Verdict.init(rawValue:)),
            name: safeListSnapshotText(name, max: PlaceRef.maxNameLength) ?? "Unnamed place",
            category: safeListSnapshotText(category, max: PlaceRef.maxCategoryLength) ?? "place",
            tier: tier,
            lat: lat,
            lon: lon
        )
    }

    private static func safeListSnapshotText(_ text: String, max: Int) -> String? {
        guard (1...max).contains(text.unicodeScalars.count),
              text.unicodeScalars.allSatisfy({ scalar in
                  switch scalar.value {
                  case 0x0000...0x001f, 0x007f...0x009f,
                       0x200b...0x200d, 0x2028...0x2029, 0x202a...0x202e,
                       0x2060, 0x2066...0x2069, 0xfeff:
                      return false
                  default:
                      return true
                  }
              })
        else { return nil }
        return text
    }

    public func isSeen(_ placeID: String) throws -> Bool {
        try dbQueue.read { db in
            try Bool.fetchOne(
                db,
                sql: "SELECT EXISTS(SELECT 1 FROM visits WHERE place_id = ?)",
                arguments: [placeID]
            ) ?? false
        }
    }

    public func seen(among placeIDs: [String]) throws -> Set<String> {
        guard !placeIDs.isEmpty else { return [] }
        return try dbQueue.read { db in
            let sql = """
                SELECT DISTINCT place_id FROM visits
                WHERE place_id IN (\(databaseQuestionMarks(count: placeIDs.count)))
                """
            return try Set(
                String.fetchAll(db, sql: sql, arguments: StatementArguments(placeIDs))
            )
        }
    }

    public func hiddenPlaceIDs() throws -> Set<String> {
        try dbQueue.read { db in
            try Set(String.fetchAll(db, sql: "SELECT place_id FROM hidden_places"))
        }
    }

    public func visitCount(placeID: String) throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM visits WHERE place_id = ?",
                arguments: [placeID]
            ) ?? 0
        }
    }

    public func listProgress(listID: Int64) throws -> (visited: Int, total: Int) {
        try dbQueue.read { db in
            if try Self.isTrackList(listID: listID, db) {
                let total = try Int.fetchOne(
                    db,
                    sql: """
                        SELECT COUNT(DISTINCT v.place_id)
                        FROM visits v
                        JOIN place_snapshots ps ON ps.place_id = v.place_id
                        WHERE v.place_id NOT IN (SELECT place_id FROM hidden_places)
                        """
                ) ?? 0
                return (total, total)
            }
            let total = try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*)
                    FROM list_items li
                    JOIN place_snapshots ps ON ps.place_id = li.place_id
                    WHERE li.list_id = ?
                    """,
                arguments: [listID]
            ) ?? 0
            let visited = try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*)
                    FROM list_items li
                    JOIN place_snapshots ps ON ps.place_id = li.place_id
                    WHERE li.list_id = ?
                    AND EXISTS(SELECT 1 FROM visits v WHERE v.place_id = li.place_id)
                    """,
                arguments: [listID]
            ) ?? 0
            return (visited, total)
        }
    }

    private static func isTrackList(listID: Int64, _ db: Database) throws -> Bool {
        try Bool.fetchOne(
            db,
            sql: "SELECT EXISTS(SELECT 1 FROM lists WHERE id = ? AND is_system = 1 AND list_kind = ?)",
            arguments: [listID, PlaceList.trackKind]
        ) ?? false
    }

    private static func listSnapshots(listID: Int64, _ db: Database) throws -> [ListSnapshotRow] {
        if try isTrackList(listID: listID, db) {
            return try trackListSnapshots(db)
        }
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT ps.place_id, ps.name, ps.lat, ps.lon, ps.category, ps.tier
                FROM list_items li
                JOIN place_snapshots ps ON ps.place_id = li.place_id
                WHERE li.list_id = ?
                ORDER BY li.added_at DESC, ps.name COLLATE NOCASE, ps.place_id
                """,
            arguments: [listID]
        )
        return rows.compactMap(Self.listSnapshotRow)
    }

    private static func trackListSnapshots(_ db: Database) throws -> [ListSnapshotRow] {
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT ps.place_id, ps.name, ps.lat, ps.lon, ps.category, ps.tier
                FROM visits v
                JOIN place_snapshots ps ON ps.place_id = v.place_id
                WHERE v.id = (
                    SELECT v2.id
                    FROM visits v2
                    WHERE v2.place_id = v.place_id
                    ORDER BY v2.visited_at DESC, v2.id DESC
                    LIMIT 1
                )
                AND v.place_id NOT IN (SELECT place_id FROM hidden_places)
                ORDER BY v.visited_at DESC, v.id DESC, ps.name COLLATE NOCASE, ps.place_id
                """
        )
        return rows.compactMap(Self.listSnapshotRow)
    }

    public func userListNames(containing placeID: String) throws -> [String] {
        try dbQueue.read { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT l.name
                    FROM lists l
                    JOIN list_items li ON li.list_id = l.id
                    WHERE li.place_id = ?
                    AND l.is_system = 0
                    ORDER BY l.name COLLATE NOCASE
                    LIMIT 8
                    """,
                arguments: [placeID]
            )
        }
    }

    public func viewportState(_ placeIDs: [String]) throws -> [String: PinState] {
        guard !placeIDs.isEmpty else { return [:] }
        return try dbQueue.read { db in
            try Self.viewportState(placeIDs, db)
        }
    }

    private static func viewportState(_ placeIDs: [String], _ db: Database) throws -> [String: PinState] {
        guard !placeIDs.isEmpty else { return [:] }
        let qmarks = databaseQuestionMarks(count: placeIDs.count)
        let saved = try Set(
            String.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT li.place_id
                    FROM list_items li
                    JOIN lists l ON l.id = li.list_id
                    WHERE li.place_id IN (\(qmarks))
                    AND l.is_system = 1
                    AND l.name = ?
                    """,
                arguments: StatementArguments(placeIDs + [Self.wantToGoListName])
            )
        )
        let hidden = try Set(
            String.fetchAll(
                db,
                sql: "SELECT place_id FROM hidden_places WHERE place_id IN (\(qmarks))",
                arguments: StatementArguments(placeIDs)
            )
        )
        let visitRows = try Row.fetchAll(
            db,
            sql: """
                SELECT place_id,
                       MAX(CASE WHEN verdict = 'loved' THEN 1 ELSE 0 END) AS loved
                FROM visits
                WHERE place_id IN (\(qmarks))
                GROUP BY place_id
                """,
            arguments: StatementArguments(placeIDs)
        )
        var visit: [String: VisitState] = [:]
        for row in visitRows {
            let placeID: String = row["place_id"]
            let loved: Int = row["loved"]
            visit[placeID] = loved == 1 ? .loved : .visited
        }

        var out: [String: PinState] = [:]
        for placeID in placeIDs {
            out[placeID] = PinState(
                saved: saved.contains(placeID),
                visit: visit[placeID] ?? .none,
                hidden: hidden.contains(placeID)
            )
        }
        return out
    }
}

private struct ListSnapshotRow {
    let placeID: String
    let name: String
    let lat: Double
    let lon: Double
    let category: String
    let tier: Int
}

private func databaseQuestionMarks(count: Int) -> String {
    Array(repeating: "?", count: count).joined(separator: ",")
}
