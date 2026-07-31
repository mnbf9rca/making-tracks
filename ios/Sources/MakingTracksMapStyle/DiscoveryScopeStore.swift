import Foundation

public struct DiscoveryScope: Equatable, Sendable {
    public static let defaults = DiscoveryScope()

    public var visibleCategoryIDs: Set<String>?
    public var includeHidden: Bool
    public var showSaved: Bool
    public var showCoverageShading: Bool

    public var differsFromDefault: Bool {
        self != .defaults
    }

    public init(
        visibleCategoryIDs: Set<String>? = nil,
        includeHidden: Bool = false,
        showSaved: Bool = true,
        showCoverageShading: Bool = true
    ) {
        self.visibleCategoryIDs = visibleCategoryIDs
        self.includeHidden = includeHidden
        self.showSaved = showSaved
        self.showCoverageShading = showCoverageShading
    }
}

public struct DiscoveryScopeStore {
    public static let storageKey = "map.scope.record"

    private static let currentVersion = 1
    // Defensive parsing caps. Tune only with a measured need from the finite category taxonomy.
    private static let maximumRecordBytes = 64 * 1_024
    private static let maximumCategoryCount = 128
    private static let maximumCategoryIDBytes = 128

    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    public func load() -> DiscoveryScope {
        guard let storedObject = userDefaults.object(forKey: Self.storageKey) else {
            return .defaults
        }
        guard let data = storedObject as? Data else {
            return .defaults
        }
        guard data.count <= Self.maximumRecordBytes else {
            return .defaults
        }
        guard let envelope = try? JSONDecoder().decode(
            VersionEnvelope.self,
            from: data
        ) else {
            return .defaults
        }

        switch envelope.version {
        case Self.currentVersion:
            guard let record = try? JSONDecoder().decode(
                RecordV1.self,
                from: data
            ) else {
                return .defaults
            }
            return Self.scope(
                visibleCategoryIDs: record.visibleCategoryIDs,
                includeHidden: record.includeHidden,
                showSaved: record.showSaved,
                showCoverageShading: record.showCoverageShading
            ) ?? .defaults

        default:
            return .defaults
        }
    }

    /// An explicit save intentionally replaces any stored record, including a
    /// newer-version record that `load()` previously degraded to defaults.
    /// The post-downgrade user choice wins over preserving opaque future data.
    @discardableResult
    public func save(_ scope: DiscoveryScope) -> Bool {
        persist(scope)
    }

    public func reset() {
        userDefaults.removeObject(forKey: Self.storageKey)
    }

    @discardableResult
    private func persist(_ scope: DiscoveryScope) -> Bool {
        guard Self.isValid(scope.visibleCategoryIDs) else {
            return false
        }
        let record = RecordV1(
            version: Self.currentVersion,
            visibleCategoryIDs: scope.visibleCategoryIDs?.sorted(),
            includeHidden: scope.includeHidden,
            showSaved: scope.showSaved,
            showCoverageShading: scope.showCoverageShading
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(record) else {
            return false
        }
        guard data.count <= Self.maximumRecordBytes else {
            return false
        }

        userDefaults.set(data, forKey: Self.storageKey)
        return true
    }

    private static func scope(
        visibleCategoryIDs: [String]?,
        includeHidden: Bool,
        showSaved: Bool,
        showCoverageShading: Bool
    ) -> DiscoveryScope? {
        if let visibleCategoryIDs {
            guard visibleCategoryIDs.count <= maximumCategoryCount else {
                return nil
            }
            guard visibleCategoryIDs.allSatisfy(isValidCategoryID) else {
                return nil
            }
        }
        let categoryIDs = visibleCategoryIDs.map(Set.init)
        return DiscoveryScope(
            visibleCategoryIDs: categoryIDs,
            includeHidden: includeHidden,
            showSaved: showSaved,
            showCoverageShading: showCoverageShading
        )
    }

    private static func isValid(_ categoryIDs: Set<String>?) -> Bool {
        guard let categoryIDs else {
            return true
        }
        guard categoryIDs.count <= maximumCategoryCount else {
            return false
        }
        return categoryIDs.allSatisfy(isValidCategoryID)
    }

    private static func isValidCategoryID(_ categoryID: String) -> Bool {
        !categoryID.isEmpty
            && categoryID.utf8.count <= maximumCategoryIDBytes
    }
}

private struct VersionEnvelope: Decodable {
    let version: Int
}

private struct RecordV1: Codable {
    let version: Int
    let visibleCategoryIDs: [String]?
    let includeHidden: Bool
    let showSaved: Bool
    let showCoverageShading: Bool
}
