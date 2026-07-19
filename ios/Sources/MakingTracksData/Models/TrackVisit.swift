import Foundation

public struct TrackVisit: Sendable, Equatable, Identifiable {
    public let id: Int64
    public let placeID: String
    public let visitedAt: Date
    public let verdict: Verdict?
    public let name: String
    public let category: String
    public let tier: Int
    public let lat: Double
    public let lon: Double

    public init(
        id: Int64,
        placeID: String,
        visitedAt: Date,
        verdict: Verdict?,
        name: String,
        category: String,
        tier: Int,
        lat: Double,
        lon: Double
    ) {
        self.id = id
        self.placeID = placeID
        self.visitedAt = visitedAt
        self.verdict = verdict
        self.name = name
        self.category = category
        self.tier = tier
        self.lat = lat
        self.lon = lon
    }
}
