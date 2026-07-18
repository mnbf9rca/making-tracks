import Foundation
import GRDB

extension AppDatabase {
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
            let total = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM list_items WHERE list_id = ?",
                arguments: [listID]
            ) ?? 0
            let visited = try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM list_items li
                    WHERE li.list_id = ?
                    AND EXISTS(SELECT 1 FROM visits v WHERE v.place_id = li.place_id)
                    """,
                arguments: [listID]
            ) ?? 0
            return (visited, total)
        }
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
}

private func databaseQuestionMarks(count: Int) -> String {
    Array(repeating: "?", count: count).joined(separator: ",")
}
