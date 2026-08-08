import Foundation
import XCTest
@testable import MakingTracksData
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

    func testResolverReturnsSnapshotEvenWhenSnapshotJSONIsOverCap() async throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })
        let oversized = PlaceSnapshot(
            placeID: "p_oversize",
            name: "Snapshot name",
            lat: 51.5,
            lon: -0.12,
            category: "attraction",
            tier: 2,
            snapshotJSON: String(repeating: "x", count: PlaceCardModel.maxSnapshotJSONBytes + 1),
            snapshotSchemaVersion: 1,
            fetchedAt: Date(timeIntervalSince1970: 0)
        )
        try await db.dbQueue.write { try oversized.insert($0) }
        let resolver = PlaceResolver(tile: StubTileResolver(refs: [:]), snapshots: db)

        guard case .snapshot(let actionRef, let snapshot) = await resolver.source(for: "p_oversize") else {
            return XCTFail("expected snapshot fallback despite over-cap raw JSON")
        }

        XCTAssertLessThanOrEqual(actionRef.rawJSON.utf8.count, PlaceRef.maxRawJSONBytes)
        XCTAssertEqual(actionRef.placeID, "p_oversize")
        XCTAssertEqual(snapshot, oversized)
        XCTAssertEqual(PlaceCardModel.from(snapshot: snapshot, pinState: PinState(saved: false, visit: .none))?.name, "Snapshot name")
    }

    func testCoreLoopTogglesAreReversibleAndEmitChangedPlaceIDs() async throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })
        let controller = CoreLoopController(database: db)
        var changes = controller.changes.makeAsyncIterator()
        let place = try makePlace("p_loop")
        let wantToGoListID = try db.wantToGoListID()

        try controller.addToList(place, listID: wantToGoListID)
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

        try controller.removeFromList(placeID: place.placeID, listID: wantToGoListID)
        let unsavedChange = await changes.next()
        XCTAssertEqual(unsavedChange, ["p_loop"])
        XCTAssertEqual(try db.viewportState(["p_loop"])["p_loop"], PinState(saved: false, visit: .none))

        try controller.setHidden(place, true)
        let hiddenChange = await changes.next()
        XCTAssertEqual(hiddenChange, ["p_loop"])
        XCTAssertEqual(try db.viewportState(["p_loop"])["p_loop"], PinState(saved: false, visit: .none, hidden: true))

        try controller.setHidden(place, false)
        let unhiddenChange = await changes.next()
        XCTAssertEqual(unhiddenChange, ["p_loop"])
        XCTAssertEqual(try db.viewportState(["p_loop"])["p_loop"], PinState(saved: false, visit: .none, hidden: false))
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
                try controller.addToList(place, listID: db.wantToGoListID())
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

    func testCoreLoopTransitionsPreserveOrthogonalAxes() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })
        let controller = CoreLoopController(database: db)
        let savedLoved = try makePlace("p_saved_loved_transition")
        let wantToGoListID = try db.wantToGoListID()
        try controller.addToList(savedLoved, listID: wantToGoListID)
        try controller.setVisited(savedLoved, true)
        try controller.setLoved(placeID: savedLoved.placeID, true)

        try controller.removeFromList(placeID: savedLoved.placeID, listID: wantToGoListID)
        XCTAssertEqual(
            try db.viewportState([savedLoved.placeID])[savedLoved.placeID],
            PinState(saved: false, visit: .loved)
        )

        try controller.addToList(savedLoved, listID: wantToGoListID)
        try controller.setLoved(placeID: savedLoved.placeID, false)
        XCTAssertEqual(
            try db.viewportState([savedLoved.placeID])[savedLoved.placeID],
            PinState(saved: true, visit: .visited)
        )

        try controller.setVisited(savedLoved, false)
        XCTAssertEqual(
            try db.viewportState([savedLoved.placeID])[savedLoved.placeID],
            PinState(saved: true, visit: .none)
        )
    }

    func testSetVisitedFalseDeletesOnlyLatestVisitForRevisitedPlace() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })
        let controller = CoreLoopController(database: db)
        let place = try makePlace("p_revisited")
        try controller.setVisited(place, true)
        try controller.setVisited(place, true)

        try controller.setVisited(place, false)

        let visits = try db.dbQueue.read {
            try Visit.fetchAll($0, sql: "SELECT * FROM visits WHERE place_id = ? ORDER BY id", arguments: ["p_revisited"])
        }
        XCTAssertEqual(visits.count, 1)
        XCTAssertEqual(try db.viewportState(["p_revisited"])["p_revisited"], PinState(saved: false, visit: .visited))

        try controller.setVisited(place, false)
        XCTAssertEqual(try db.viewportState(["p_revisited"])["p_revisited"], PinState(saved: false, visit: .none))
    }

    func testCustomListMembershipChangesEmitChangedPlaceIDs() async throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })
        let controller = CoreLoopController(database: db)
        var changes = controller.changes.makeAsyncIterator()
        let list = try db.createList(named: "KL trip")
        let place = try makePlace("p_custom_membership")

        try controller.addToList(place, listID: list.id!)

        let addedChange = await changes.next()
        XCTAssertEqual(addedChange, ["p_custom_membership"])
        XCTAssertEqual(try db.listItems(listID: list.id!).map(\.placeID), ["p_custom_membership"])

        try controller.removeFromList(placeID: "p_custom_membership", listID: list.id!)

        let removedChange = await changes.next()
        XCTAssertEqual(removedChange, ["p_custom_membership"])
        XCTAssertEqual(try db.listItems(listID: list.id!).map(\.placeID), [])
    }

    func testDeletingCustomListEmitsAffectedPlaceIDsAndClearsSavedState() async throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })
        let controller = CoreLoopController(database: db)
        var changes = controller.changes.makeAsyncIterator()
        let list = try db.createList(named: "Date night")
        let place = try makePlace("p_deleted_list")
        try controller.addToList(place, listID: list.id!)
        _ = await changes.next()
        XCTAssertEqual(
            try db.viewportState([place.placeID])[place.placeID],
            PinState(saved: true, visit: .none)
        )

        try controller.deleteList(id: list.id!)

        let deletedChange = await changes.next()
        XCTAssertEqual(deletedChange, [place.placeID])
        XCTAssertEqual(
            try db.viewportState([place.placeID])[place.placeID],
            PinState(saved: false, visit: .none)
        )
    }

    func testVisitVerdictUsesVisitIDToFindPlaceAndEmitsChangedPlaceID() async throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })
        let controller = CoreLoopController(database: db)
        var changes = controller.changes.makeAsyncIterator()
        let place = try makePlace("p_row_emit")
        let first = try db.recordVisit(place)
        let second = try db.recordVisit(place)

        try controller.setVisitVerdict(id: first, .loved)

        let lovedChange = await changes.next()
        XCTAssertEqual(lovedChange, ["p_row_emit"])
        let visits = try await db.dbQueue.read {
            try Visit.fetchAll($0, sql: "SELECT * FROM visits WHERE place_id = ? ORDER BY id", arguments: ["p_row_emit"])
        }
        XCTAssertEqual(visits.map(\.verdict), [.loved, .loved])

        try controller.setVisitVerdict(id: second, .loved)

        let secondLovedChange = await changes.next()
        XCTAssertEqual(secondLovedChange, ["p_row_emit"])
    }

    func testVisitEditingOperationsEmitChangedPlaceIDsByVisitIdentity() async throws {
        let day = Date(timeIntervalSince1970: 60 * 60 * 24 * 10)
        let db = try AppDatabase.inMemory(now: { day.addingTimeInterval(60 * 60 * 24 * 2) })
        let controller = CoreLoopController(database: db)
        var changes = controller.changes.makeAsyncIterator()
        let firstPlace = try makePlace("p_edit_first")
        let secondPlace = try makePlace("p_edit_second")
        let first = try db.recordVisit(firstPlace, at: day.addingTimeInterval(60))
        let second = try db.recordVisit(secondPlace, at: day.addingTimeInterval(120))

        try controller.reorderVisitsWithinDay([second, first], dayContaining: day)

        let reorderChange = await changes.next()
        XCTAssertEqual(reorderChange, ["p_edit_first", "p_edit_second"])

        try controller.updateVisitDate(id: first, toDayContaining: day.addingTimeInterval(60 * 60 * 24))

        let dateChange = await changes.next()
        XCTAssertEqual(dateChange, ["p_edit_first"])

        let nextDayFirst = try db.recordVisit(makePlace("p_next_first"), at: day.addingTimeInterval(60 * 60 * 24 + 60))
        try controller.moveVisit(
            id: first,
            toDayContaining: day.addingTimeInterval(60 * 60 * 24),
            targetDayOrderedIDs: [nextDayFirst, first]
        )

        let moveChange = await changes.next()
        XCTAssertEqual(moveChange, ["p_edit_first", "p_next_first"])

        try controller.deleteVisit(id: second)

        let deleteChange = await changes.next()
        XCTAssertEqual(deleteChange, ["p_edit_second"])
        XCTAssertEqual(try db.trackVisits().map(\.id), [nextDayFirst, first])
    }

    func testRejectedFutureVisitDateEmitsNoChangeBeforeNextSuccessfulAction() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Kuala_Lumpur"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 6,
            hour: 9
        )))
        let yesterday = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 5,
            hour: 12
        )))
        let tomorrow = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 7,
            hour: 12
        )))
        let db = try AppDatabase.inMemory(now: { now })
        let controller = CoreLoopController(database: db)
        var changes = controller.changes.makeAsyncIterator()
        let rejectedID = try db.recordVisit(makePlace("p_rejected_future"), at: yesterday)
        let successfulID = try db.recordVisit(makePlace("p_success_after_rejection"), at: yesterday)

        XCTAssertThrowsError(
            try controller.updateVisitDate(id: rejectedID, toDayContaining: tomorrow)
        ) { error in
            XCTAssertEqual(error as? AppDatabaseError, .futureVisitDate)
        }
        try controller.setVisitVerdict(id: successfulID, .loved)

        let firstChange = await changes.next()
        XCTAssertEqual(firstChange, ["p_success_after_rejection"])
    }

    func testUnseeingFromPlaceCardDeletesOnlyLatestVisitEvent() async throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 100) })
        let controller = CoreLoopController(database: db)
        var changes = controller.changes.makeAsyncIterator()
        let place = try makePlace("p_unsee_latest")
        let older = try db.recordVisit(place, verdict: .loved)
        let newer = try db.recordVisit(place)

        try controller.setVisited(place, false)

        let unvisitedChange = await changes.next()
        XCTAssertEqual(unvisitedChange, ["p_unsee_latest"])
        let visits = try await db.dbQueue.read {
            try Visit.fetchAll($0, sql: "SELECT * FROM visits WHERE place_id = ? ORDER BY id", arguments: ["p_unsee_latest"])
        }
        XCTAssertEqual(visits.map(\.id), [older])
        XCTAssertFalse(visits.contains { $0.id == newer })
        XCTAssertEqual(try db.viewportState(["p_unsee_latest"])["p_unsee_latest"], PinState(saved: false, visit: .loved))
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
        "category": "historic_building",
        "tier": 1,
        "score": 0.9,
        "source_refs": ["wd:Q42"],
    ])
    return try PlaceRef(
        placeID: id,
        name: "Clock",
        lat: 51.5,
        lon: -0.12,
        category: "historic_building",
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
