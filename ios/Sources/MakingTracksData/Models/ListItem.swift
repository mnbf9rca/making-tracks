import Foundation
import GRDB

public struct ListItem: Codable, Sendable, FetchableRecord, PersistableRecord {
    public var listID: Int64
    public var placeID: String
    public var addedAt: Date

    public static let databaseTableName = "list_items"

    enum CodingKeys: String, CodingKey {
        case listID = "list_id"
        case placeID = "place_id"
        case addedAt = "added_at"
    }

    public init(listID: Int64, placeID: String, addedAt: Date) {
        self.listID = listID
        self.placeID = placeID
        self.addedAt = addedAt
    }
}
