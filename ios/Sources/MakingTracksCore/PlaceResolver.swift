import Foundation
import MakingTracksData
import MakingTracksTiles

public protocol TileResolving: Sendable {
    func placeRef(for placeID: String) async -> PlaceRef?
}

public protocol SnapshotReading: Sendable {
    func snapshot(for placeID: String) throws -> PlaceSnapshot?
}

extension TileClient: TileResolving {}
extension AppDatabase: SnapshotReading {}

public enum CardSource: Sendable, Equatable {
    case tile(PlaceRef)
    case snapshot(PlaceRef, PlaceSnapshot)
    case unavailable
}

public struct PlaceResolver<Tile: TileResolving, Snapshots: SnapshotReading>: Sendable {
    private let tile: Tile
    private let snapshots: Snapshots

    public init(tile: Tile, snapshots: Snapshots) {
        self.tile = tile
        self.snapshots = snapshots
    }

    public func source(for placeID: String) async -> CardSource {
        if let placeRef = await tile.placeRef(for: placeID) {
            return .tile(placeRef)
        }
        guard let snapshot = try? snapshots.snapshot(for: placeID),
              let placeRef = try? PlaceRef(
                placeID: snapshot.placeID,
                name: snapshot.name,
                lat: snapshot.lat,
                lon: snapshot.lon,
                category: snapshot.category,
                tier: snapshot.tier,
                schemaVersion: snapshot.snapshotSchemaVersion,
                fetchedAt: snapshot.fetchedAt,
                rawJSON: snapshot.snapshotJSON
              )
        else { return .unavailable }
        return .snapshot(placeRef, snapshot)
    }
}
