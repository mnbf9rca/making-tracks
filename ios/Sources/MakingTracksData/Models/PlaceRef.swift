import Foundation

/// A tile-derived place, validated at the storage boundary before it can seed a
/// snapshot. It is intentionally not Codable; B3 must decode and validate tiles
/// before handing B1 this value.
public struct PlaceRef: Sendable, Equatable {
    public let placeID: String
    public let name: String
    public let lat: Double
    public let lon: Double
    public let category: String
    public let tier: Int
    public let schemaVersion: Int
    public let fetchedAt: Date
    public let rawJSON: String

    public enum ValidationError: Error, Equatable {
        case coordinateOutOfRange
        case tierOutOfRange
        case fieldTooLong
        case payloadTooLarge
    }

    public static let maxNameLength = 200
    public static let maxCategoryLength = 64
    public static let maxPlaceIDLength = 64
    public static let maxRawJSONBytes = 65_536

    public init(
        placeID: String,
        name: String,
        lat: Double,
        lon: Double,
        category: String,
        tier: Int,
        schemaVersion: Int,
        fetchedAt: Date,
        rawJSON: String
    ) throws {
        guard lat.isFinite,
              lon.isFinite,
              (-90.0...90.0).contains(lat),
              (-180.0...180.0).contains(lon)
        else { throw ValidationError.coordinateOutOfRange }
        guard (1...4).contains(tier) else { throw ValidationError.tierOutOfRange }
        guard placeID.count <= Self.maxPlaceIDLength,
              name.count <= Self.maxNameLength,
              category.count <= Self.maxCategoryLength
        else { throw ValidationError.fieldTooLong }
        guard rawJSON.utf8.count <= Self.maxRawJSONBytes else {
            throw ValidationError.payloadTooLarge
        }

        self.placeID = placeID
        self.name = name
        self.lat = lat
        self.lon = lon
        self.category = category
        self.tier = tier
        self.schemaVersion = schemaVersion
        self.fetchedAt = fetchedAt
        self.rawJSON = rawJSON
    }
}
