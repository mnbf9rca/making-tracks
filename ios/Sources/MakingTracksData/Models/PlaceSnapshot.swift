import Foundation
import GRDB

public struct PlaceSnapshot: Codable, Sendable, FetchableRecord, PersistableRecord {
    public var placeID: String
    public var name: String
    public var lat: Double
    public var lon: Double
    public var category: String
    public var tier: Int
    public var snapshotJSON: String
    public var snapshotSchemaVersion: Int
    public var fetchedAt: Date

    public static let databaseTableName = "place_snapshots"

    enum CodingKeys: String, CodingKey {
        case placeID = "place_id"
        case name
        case lat
        case lon
        case category
        case tier
        case snapshotJSON = "snapshot_json"
        case snapshotSchemaVersion = "snapshot_schema_version"
        case fetchedAt = "fetched_at"
    }

    public init(
        placeID: String,
        name: String,
        lat: Double,
        lon: Double,
        category: String,
        tier: Int,
        snapshotJSON: String,
        snapshotSchemaVersion: Int,
        fetchedAt: Date
    ) {
        self.placeID = placeID
        self.name = name
        self.lat = lat
        self.lon = lon
        self.category = category
        self.tier = tier
        self.snapshotJSON = snapshotJSON
        self.snapshotSchemaVersion = snapshotSchemaVersion
        self.fetchedAt = fetchedAt
    }
}
