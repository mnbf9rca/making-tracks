import Foundation
import GRDB

public struct PlaceList: Codable, Sendable, FetchableRecord, MutablePersistableRecord {
    public var id: Int64?
    public var name: String
    public var isSystem: Bool
    public var createdAt: Date

    public static let databaseTableName = "lists"

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case isSystem = "is_system"
        case createdAt = "created_at"
    }

    public init(id: Int64?, name: String, isSystem: Bool, createdAt: Date) {
        self.id = id
        self.name = name
        self.isSystem = isSystem
        self.createdAt = createdAt
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
