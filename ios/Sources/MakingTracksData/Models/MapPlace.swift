import Foundation

/// A map-renderable place value supplied by the tile client to B2.
public struct MapPlace: Sendable, Equatable {
    public let id: String
    public let lat: Double
    public let lon: Double
    public let tier: Int

    public init(id: String, lat: Double, lon: Double, tier: Int) {
        self.id = id
        self.lat = lat
        self.lon = lon
        self.tier = tier
    }
}
