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

    public func setVisited(_ place: PlaceRef, _ visited: Bool) throws {
        if visited {
            _ = try database.recordVisit(place)
        } else {
            try database.deleteVisits(placeID: place.placeID)
        }
        emit(place.placeID)
    }

    public func setLoved(placeID: String, _ loved: Bool) throws {
        try database.setLoved(placeID: placeID, loved)
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
