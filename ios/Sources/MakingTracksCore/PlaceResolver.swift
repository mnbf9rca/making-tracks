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

    public static func actionSafeSnapshot(_ snapshot: PlaceSnapshot) -> Self {
        guard let rawJSON = actionRawJSON(for: snapshot),
              let placeRef = try? PlaceRef(
                placeID: snapshot.placeID,
                name: snapshot.name,
                lat: snapshot.lat,
                lon: snapshot.lon,
                category: snapshot.category,
                tier: snapshot.tier,
                schemaVersion: snapshot.snapshotSchemaVersion,
                fetchedAt: snapshot.fetchedAt,
                rawJSON: rawJSON
              )
        else { return .unavailable }
        return .snapshot(placeRef, snapshot)
    }

    private static func actionRawJSON(for snapshot: PlaceSnapshot) -> String? {
        let object: [String: Any] = [
            "place_id": snapshot.placeID,
            "name": snapshot.name,
            "lat": snapshot.lat,
            "lon": snapshot.lon,
            "category": snapshot.category,
            "tier": snapshot.tier,
            "source_refs": [],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }
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
        guard let snapshot = try? snapshots.snapshot(for: placeID) else {
            return .unavailable
        }
        return .actionSafeSnapshot(snapshot)
    }
}
