import Foundation
import MakingTracksData

public final class CoreLoopController: Sendable {
    private let database: AppDatabase
    private let continuation: AsyncStream<Set<String>>.Continuation
    public let changes: AsyncStream<Set<String>>

    public init(database: AppDatabase) {
        self.database = database
        var captured: AsyncStream<Set<String>>.Continuation?
        changes = AsyncStream<Set<String>> { continuation in
            captured = continuation
        }
        continuation = captured!
    }

    public func setSaved(_ place: PlaceRef, _ saved: Bool) throws {
        if saved {
            try database.addToList(place, listID: database.wantToGoListID())
        } else {
            try database.removeFromList(placeID: place.placeID, listID: database.wantToGoListID())
        }
        emit(place.placeID)
    }

    public func addToList(_ place: PlaceRef, listID: Int64) throws {
        try database.addToList(place, listID: listID)
        emit(place.placeID)
    }

    public func removeFromList(placeID: String, listID: Int64) throws {
        try database.removeFromList(placeID: placeID, listID: listID)
        emit(placeID)
    }

    public func setVisited(_ place: PlaceRef, _ visited: Bool) throws {
        if visited {
            _ = try database.recordVisit(place)
        } else {
            // Interim per #217: delete latest only. Multi-visit and stale
            // disambiguation routes to the #221 edit screen when it exists.
            try database.deleteLatestVisit(placeID: place.placeID)
        }
        emit(place.placeID)
    }

    public func setLoved(placeID: String, _ loved: Bool) throws {
        try database.setLoved(placeID: placeID, loved)
        emit(placeID)
    }

    public func setVisitVerdict(id: Int64, _ verdict: Verdict?) throws {
        guard let placeID = try database.setVisitVerdict(id: id, verdict) else { return }
        emit(placeID)
    }

    public func setHidden(_ place: PlaceRef, _ hidden: Bool) throws {
        try database.setHidden(place, hidden)
        emit(place.placeID)
    }

    private func emit(_ placeID: String) {
        continuation.yield([placeID])
    }
}
