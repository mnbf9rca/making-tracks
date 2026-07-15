import Foundation
import GRDB

public enum Verdict: String, Codable, Sendable {
    case loved
}

public struct Visit: Codable, Sendable, FetchableRecord, MutablePersistableRecord {
    public var id: Int64?
    public var placeID: String
    public var visitedAt: Date
    public var verdict: Verdict?
    public var createdAt: Date

    public static let databaseTableName = "visits"

    enum CodingKeys: String, CodingKey {
        case id
        case placeID = "place_id"
        case visitedAt = "visited_at"
        case verdict
        case createdAt = "created_at"
    }

    public init(
        id: Int64?,
        placeID: String,
        visitedAt: Date,
        verdict: Verdict?,
        createdAt: Date
    ) {
        self.id = id
        self.placeID = placeID
        self.visitedAt = visitedAt
        self.verdict = verdict
        self.createdAt = createdAt
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
