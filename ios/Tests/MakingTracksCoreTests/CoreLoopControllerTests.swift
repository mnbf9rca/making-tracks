import Foundation
import XCTest
import MakingTracksData
@testable import MakingTracksCore

final class CoreLoopControllerTests: XCTestCase {
    func testResolverUsesTileThenSnapshotThenUnavailable() async throws {
        let place = try makePlace("p_resolve")
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })
        _ = try db.recordVisit(place)
        let resolver = PlaceResolver(tile: StubTileResolver(refs: ["p_tile": place]), snapshots: db)

        let tileSource = await resolver.source(for: "p_tile")
        XCTAssertEqual(tileSource, .tile(place))
        guard case .snapshot(let snapshotRef, let snapshot) = await resolver.source(for: "p_resolve") else {
            return XCTFail("expected snapshot fallback")
        }
        XCTAssertEqual(snapshotRef.placeID, "p_resolve")
        XCTAssertEqual(snapshot, try db.snapshot(for: "p_resolve"))
        let missingSource = await resolver.source(for: "missing")
        XCTAssertEqual(missingSource, .unavailable)
    }

    func testCoreLoopTogglesAreReversibleAndEmitChangedPlaceIDs() async throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })
        let controller = CoreLoopController(database: db)
        var changes = controller.changes.makeAsyncIterator()
        let place = try makePlace("p_loop")

        try controller.setSaved(place, true)
        let savedChange = await changes.next()
        XCTAssertEqual(savedChange, ["p_loop"])
        XCTAssertEqual(try db.viewportState(["p_loop"])["p_loop"], PinState(saved: true, visit: .none))

        try controller.setVisited(place, true)
        let visitedChange = await changes.next()
        XCTAssertEqual(visitedChange, ["p_loop"])
        XCTAssertEqual(try db.viewportState(["p_loop"])["p_loop"], PinState(saved: true, visit: .visited))

        try controller.setLoved(placeID: "p_loop", true)
        let lovedChange = await changes.next()
        XCTAssertEqual(lovedChange, ["p_loop"])
        XCTAssertEqual(try db.viewportState(["p_loop"])["p_loop"], PinState(saved: true, visit: .loved))

        try controller.setLoved(placeID: "p_loop", false)
        let unlovedChange = await changes.next()
        XCTAssertEqual(unlovedChange, ["p_loop"])
        XCTAssertEqual(try db.viewportState(["p_loop"])["p_loop"], PinState(saved: true, visit: .visited))

        try controller.setVisited(place, false)
        let unvisitedChange = await changes.next()
        XCTAssertEqual(unvisitedChange, ["p_loop"])
        XCTAssertEqual(try db.viewportState(["p_loop"])["p_loop"], PinState(saved: true, visit: .none))

        try controller.setSaved(place, false)
        let unsavedChange = await changes.next()
        XCTAssertEqual(unsavedChange, ["p_loop"])
        XCTAssertEqual(try db.viewportState(["p_loop"])["p_loop"], PinState(saved: false, visit: .none))
    }

    func testCoreLoopCanProduceEverySavedVisitStateCell() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })
        let controller = CoreLoopController(database: db)
        let cases: [(String, Bool, VisitState)] = [
            ("p_none", false, .none),
            ("p_saved", true, .none),
            ("p_visited", false, .visited),
            ("p_saved_visited", true, .visited),
            ("p_loved", false, .loved),
            ("p_saved_loved", true, .loved),
        ]

        for (placeID, saved, visit) in cases {
            let place = try makePlace(placeID)
            if saved {
                try controller.setSaved(place, true)
            }
            switch visit {
            case .none:
                break
            case .visited:
                try controller.setVisited(place, true)
            case .loved:
                try controller.setVisited(place, true)
                try controller.setLoved(placeID: placeID, true)
            }
        }

        let state = try db.viewportState(cases.map(\.0))
        for (placeID, saved, visit) in cases {
            XCTAssertEqual(state[placeID], PinState(saved: saved, visit: visit), placeID)
        }
    }
}

private struct StubTileResolver: TileResolving {
    var refs: [String: PlaceRef]

    func placeRef(for placeID: String) async -> PlaceRef? {
        refs[placeID]
    }
}

private func makePlace(_ id: String) throws -> PlaceRef {
    let raw = jsonString([
        "place_id": id,
        "name": "Clock",
        "lat": 51.5,
        "lon": -0.12,
        "category": "architecture",
        "tier": 1,
        "score": 0.9,
        "source_refs": ["wd:Q42"],
    ])
    return try PlaceRef(
        placeID: id,
        name: "Clock",
        lat: 51.5,
        lon: -0.12,
        category: "architecture",
        tier: 1,
        schemaVersion: 1,
        fetchedAt: Date(timeIntervalSince1970: 0),
        rawJSON: raw
    )
}

private func jsonString(_ object: [String: Any]) -> String {
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return String(decoding: data, as: UTF8.self)
}
