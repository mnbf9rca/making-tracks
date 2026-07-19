import Foundation
import GRDB

public struct PlaceList: Codable, Sendable, Identifiable, FetchableRecord, MutablePersistableRecord {
    public static let defaultKind = "collection"
    public static let trackKind = "track"

    public var id: Int64?
    public var name: String
    public var isSystem: Bool
    public var kind: String
    public var createdAt: Date

    public static let databaseTableName = "lists"

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case isSystem = "is_system"
        case kind = "list_kind"
        case createdAt = "created_at"
    }

    public init(id: Int64?, name: String, isSystem: Bool, kind: String = Self.defaultKind, createdAt: Date) {
        self.id = id
        self.name = name
        self.isSystem = isSystem
        self.kind = kind
        self.createdAt = createdAt
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public struct ListProgress: Sendable, Equatable {
    public var visited: Int
    public var total: Int

    public init(visited: Int, total: Int) {
        self.visited = visited
        self.total = total
    }
}

public struct ListPlace: Sendable, Equatable, Identifiable {
    public var placeID: String
    public var name: String
    public var category: String
    public var pinState: PinState

    public var id: String { placeID }

    public init(placeID: String, name: String, category: String, pinState: PinState) {
        self.placeID = placeID
        self.name = name
        self.category = category
        self.pinState = pinState
    }
}
