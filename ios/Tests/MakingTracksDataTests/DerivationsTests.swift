import XCTest
import GRDB
@testable import MakingTracksData
import MakingTracksMapStyle

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

    func testListProgressCountsSnapshotBackedRowsShownByTheList() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 0) })
        try db.dbQueue.write { d in
            for p in ["a", "b", "c"] {
                try d.execute(
                    sql: "INSERT INTO list_items (list_id, place_id, added_at) VALUES (1, ?, 0)",
                    arguments: [p]
                )
            }
            for p in ["a", "b"] {
                try d.execute(
                    sql: """
                        INSERT INTO place_snapshots
                        (place_id, name, lat, lon, category, tier, snapshot_json, snapshot_schema_version, fetched_at)
                        VALUES (?, ?, 51.5, -0.12, 'history', 1, '{}', 1, 0)
                        """,
                    arguments: [p, p.uppercased()]
                )
            }
            try d.execute(sql: "INSERT INTO visits (place_id, visited_at, created_at) VALUES ('a', 1, 1)")
            try d.execute(sql: "INSERT INTO visits (place_id, visited_at, created_at) VALUES ('c', 1, 1)")
        }
        let p = try db.listProgress(listID: 1)
        XCTAssertEqual(p.total, 2)
        XCTAssertEqual(p.visited, 1)
    }

    func testEmptyViewportReturnsEmpty() throws {
        XCTAssertEqual(try AppDatabase.inMemory().viewportState([]), [:])
    }

    func testTrackVisitsAreChronologicalSnapshotBackedAndExcludeHiddenPlaces() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 0) })
        try db.dbQueue.write { d in
            try insertSnapshot(d, placeID: "old", name: "Old Plaque", category: "history", lat: 51.50, lon: -0.12, tier: 2)
            try insertSnapshot(d, placeID: "hidden", name: "Hidden Marker", category: "oddity", lat: 51.51, lon: -0.13, tier: 3)
            try insertSnapshot(d, placeID: "new", name: "New Arcade", category: "architecture", lat: 51.52, lon: -0.14, tier: 1)
            try d.execute(sql: "INSERT INTO visits (place_id, visited_at, created_at) VALUES ('new', 30, 30)")
            try d.execute(sql: "INSERT INTO visits (place_id, visited_at, created_at) VALUES ('hidden', 20, 20)")
            try d.execute(sql: "INSERT INTO visits (place_id, visited_at, created_at) VALUES ('old', 10, 10)")
            try d.execute(sql: "INSERT INTO hidden_places (place_id, hidden_at) VALUES ('hidden', 40)")
        }

        let visits = try db.trackVisits()

        XCTAssertEqual(visits.map(\.placeID), ["old", "new"])
        XCTAssertEqual(visits.map(\.name), ["Old Plaque", "New Arcade"])
        XCTAssertEqual(visits.map(\.category), ["history", "architecture"])
        XCTAssertEqual(visits.map(\.tier), [2, 1])
        XCTAssertEqual(visits.map(\.lat), [51.50, 51.52])
        XCTAssertEqual(visits.map(\.lon), [-0.12, -0.14])
    }

    func testTrackVisitsDocumentVisitIDTieBreakOrder() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 0) })
        let timestamp = Date(timeIntervalSince1970: 10)
        try db.dbQueue.write { d in
            try insertSnapshot(d, placeID: "first", name: "First", category: "history", lat: 51.50, lon: -0.12, tier: 2)
            try insertSnapshot(d, placeID: "second", name: "Second", category: "architecture", lat: 51.51, lon: -0.13, tier: 2)
            try insertVisit(d, placeID: "first", timestamp: timestamp)
            try insertVisit(d, placeID: "second", timestamp: timestamp)
        }

        let visits = try db.trackVisits()

        XCTAssertEqual(visits.map(\.placeID), ["first", "second"])
        XCTAssertEqual(visits.map(\.id), visits.map(\.id).sorted())
    }

    func testTrackVisitsCanBeScopedToAListWithoutLeakingOtherVisitedPlaces() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 0) })
        try db.dbQueue.write { d in
            try d.execute(sql: "INSERT INTO lists (id, name, is_system, created_at) VALUES (42, 'Penang', 0, 0)")
            try insertSnapshot(d, placeID: "in_list_a", name: "A", category: "history", lat: 51.50, lon: -0.12, tier: 2)
            try insertSnapshot(d, placeID: "outside", name: "Outside", category: "oddity", lat: 51.51, lon: -0.13, tier: 2)
            try insertSnapshot(d, placeID: "in_list_b", name: "B", category: "architecture", lat: 51.52, lon: -0.14, tier: 2)
            try d.execute(sql: "INSERT INTO list_items (list_id, place_id, added_at) VALUES (42, 'in_list_a', 0)")
            try d.execute(sql: "INSERT INTO list_items (list_id, place_id, added_at) VALUES (42, 'in_list_b', 0)")
            try insertVisit(d, placeID: "in_list_a", timestamp: Date(timeIntervalSince1970: 10))
            try insertVisit(d, placeID: "outside", timestamp: Date(timeIntervalSince1970: 20))
            try insertVisit(d, placeID: "in_list_b", timestamp: Date(timeIntervalSince1970: 30))
        }

        let visits = try db.trackVisits(listID: 42)

        XCTAssertEqual(visits.map(\.placeID), ["in_list_a", "in_list_b"])
    }

    func testMyTracksListDerivesDistinctVisitedPlacesWithoutStoredMembership() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 0) })
        let myTracks = try XCTUnwrap(try db.lists().first { $0.kind == PlaceList.trackKind })
        let myTracksID = try XCTUnwrap(myTracks.id)
        let older = Date(timeIntervalSince1970: 10)
        let afterOlder = Date(timeIntervalSince1970: 15)
        let middle = Date(timeIntervalSince1970: 20)
        let newer = Date(timeIntervalSince1970: 30)
        try db.dbQueue.write { d in
            try insertSnapshot(d, placeID: "p_a", name: "A", category: "history", lat: 51.50, lon: -0.12, tier: 2)
            try insertSnapshot(d, placeID: "p_b", name: "B", category: "architecture", lat: 51.52, lon: -0.14, tier: 1)
            try insertSnapshot(d, placeID: "p_hidden", name: "Hidden", category: "oddity", lat: 51.51, lon: -0.13, tier: 3)
            try insertVisit(d, placeID: "p_b", timestamp: afterOlder)
            try insertVisit(d, placeID: "p_hidden", timestamp: middle)
            try insertVisit(d, placeID: "p_a", timestamp: older)
            try insertVisit(d, placeID: "p_a", timestamp: newer)
            try d.execute(sql: "INSERT INTO hidden_places (place_id, hidden_at) VALUES ('p_hidden', 40)")
        }

        XCTAssertEqual(try db.listItems(listID: myTracksID).map(\.placeID), ["p_a", "p_b"])
        XCTAssertEqual(try db.listMapFeatures(listID: myTracksID).map(\.0.id), ["p_a", "p_b"])
        let progress = try db.listProgress(listID: myTracksID)
        XCTAssertEqual(progress.visited, 2)
        XCTAssertEqual(progress.total, 2)
        let storedMemberships = try db.dbQueue.read {
            try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM list_items WHERE list_id = ?", arguments: [myTracksID])
        }
        XCTAssertEqual(storedMemberships, 0)

        XCTAssertTrue(try db.deleteLatestVisit(placeID: "p_a"))
        XCTAssertEqual(try db.listItems(listID: myTracksID).map(\.placeID), ["p_b", "p_a"])
        XCTAssertTrue(try db.deleteLatestVisit(placeID: "p_a"))
        XCTAssertEqual(try db.listItems(listID: myTracksID).map(\.placeID), ["p_b"])
    }

    func testMyTracksListTrackVisitsDrawOneConnectorThroughVirtualMembership() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 0) })
        let myTracks = try XCTUnwrap(try db.lists().first { $0.kind == PlaceList.trackKind })
        let myTracksID = try XCTUnwrap(myTracks.id)
        try db.dbQueue.write { d in
            try insertSnapshot(d, placeID: "first", name: "First", category: "history", lat: 51.50, lon: -0.12, tier: 2)
            try insertSnapshot(d, placeID: "second", name: "Second", category: "architecture", lat: 51.52, lon: -0.14, tier: 1)
            try insertVisit(d, placeID: "first", timestamp: Date(timeIntervalSince1970: 10))
            try insertVisit(d, placeID: "second", timestamp: Date(timeIntervalSince1970: 10 + TrackLayers.defaultBurstWindow + 60))
        }

        let storedMemberships = try db.dbQueue.read {
            try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM list_items WHERE list_id = ?", arguments: [myTracksID])
        }
        XCTAssertEqual(storedMemberships, 0)

        let summary = FeatureEncoding.trackSegmentSummary(try db.trackVisits(listID: myTracksID))

        XCTAssertEqual(summary.features.count, 1)
        XCTAssertEqual(summary.suppressedBurstConnectorCount, 0)
        XCTAssertEqual(summary.connectableVisitCount, 2)
        guard case let .object(feature) = summary.features.first,
              case let .object(geometry) = feature["geometry"]
        else { return XCTFail("track segment feature") }
        XCTAssertEqual(geometry["type"], .string("LineString"))
    }

    func testFilteredTrackBridgeCountIncludesListScopeAndHiddenOmissions() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 0) })
        try db.dbQueue.write { d in
            try d.execute(sql: "INSERT INTO lists (id, name, is_system, created_at) VALUES (42, 'Weekend', 0, 0)")
            for index in 0..<5 {
                let placeID = "p_\(index)"
                try insertSnapshot(
                    d,
                    placeID: placeID,
                    name: placeID,
                    category: "history",
                    lat: 51.50 + Double(index) * 0.01,
                    lon: -0.12,
                    tier: 2
                )
                try insertVisit(d, placeID: placeID, timestamp: Date(timeIntervalSince1970: Double(index + 1)))
            }
            try d.execute(sql: "INSERT INTO list_items (list_id, place_id, added_at) VALUES (42, 'p_0', 0)")
            try d.execute(sql: "INSERT INTO list_items (list_id, place_id, added_at) VALUES (42, 'p_2', 0)")
            try d.execute(sql: "INSERT INTO list_items (list_id, place_id, added_at) VALUES (42, 'p_4', 0)")
            try d.execute(sql: "INSERT INTO hidden_places (place_id, hidden_at) VALUES ('p_2', 0)")
        }

        let context = try db.trackGeometryContext(listID: 42)

        XCTAssertEqual(context.visits.map(\.placeID), ["p_0", "p_4"])
        XCTAssertEqual(context.sourceIndices, [0, 4])
        XCTAssertEqual(context.filteredBridgeCount, 3)
        XCTAssertEqual(try db.filteredTrackBridgeCount(listID: 42), 3)
    }

    func testNonSystemTrackKindRowsUseStoredMembershipNotVirtualTracks() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 0) })
        try db.dbQueue.write { d in
            try d.execute(
                sql: "INSERT INTO lists (id, name, is_system, created_at, list_kind) VALUES (42, 'Imported', 0, 0, ?)",
                arguments: [PlaceList.trackKind]
            )
            try insertSnapshot(d, placeID: "stored", name: "Stored", category: "history", lat: 51.50, lon: -0.12, tier: 2)
            try insertSnapshot(d, placeID: "visited_only", name: "Visited Only", category: "architecture", lat: 51.52, lon: -0.14, tier: 1)
            try d.execute(sql: "INSERT INTO list_items (list_id, place_id, added_at) VALUES (42, 'stored', 0)")
            try insertVisit(d, placeID: "visited_only", timestamp: Date(timeIntervalSince1970: 30))
        }

        XCTAssertEqual(try db.listItems(listID: 42).map(\.placeID), ["stored"])
        XCTAssertEqual(try db.listProgress(listID: 42).total, 1)
    }

    private func insertSnapshot(
        _ db: Database,
        placeID: String,
        name: String,
        category: String,
        lat: Double,
        lon: Double,
        tier: Int
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO place_snapshots
                (place_id, name, lat, lon, category, tier, snapshot_json, snapshot_schema_version, fetched_at)
                VALUES (?, ?, ?, ?, ?, ?, '{}', 1, 0)
                """,
            arguments: [placeID, name, lat, lon, category, tier]
        )
    }

    private func insertVisit(_ db: Database, placeID: String, timestamp: Date, verdict: Verdict? = nil) throws {
        try db.execute(
            sql: "INSERT INTO visits (place_id, visited_at, verdict, created_at) VALUES (?, ?, ?, ?)",
            arguments: [placeID, timestamp, verdict?.rawValue, timestamp]
        )
    }
}
