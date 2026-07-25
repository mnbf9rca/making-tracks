import Foundation

public struct TracksVisitFilter: Sendable, Equatable, Hashable {
    public static let all = TracksVisitFilter()
    public static let loved = TracksVisitFilter(lovedOnly: true)

    public var lovedOnly: Bool
    public var listIDs: Set<Int64>
    /// `nil` means every category; an empty set deliberately means no categories.
    public var categories: Set<String>?

    public var isActive: Bool {
        lovedOnly || !listIDs.isEmpty || categories != nil
    }

    public func includes(category: String) -> Bool {
        PlaceCategoryTaxonomy.isVisible(category, visibleCategories: categories)
    }

    public init(
        lovedOnly: Bool = false,
        listIDs: Set<Int64> = [],
        categories: Set<String>? = nil
    ) {
        self.lovedOnly = lovedOnly
        self.listIDs = listIDs
        self.categories = categories
    }

    public init(
        lovedOnly: Bool = false,
        listIDs: [Int64],
        categories: Set<String>? = nil
    ) {
        self.init(lovedOnly: lovedOnly, listIDs: Set(listIDs), categories: categories)
    }

    public init(
        lovedOnly: Bool = false,
        listIDs: Set<Int64> = [],
        categories: [String]
    ) {
        self.init(lovedOnly: lovedOnly, listIDs: listIDs, categories: Set(categories))
    }

    public init(
        lovedOnly: Bool = false,
        listIDs: [Int64],
        categories: [String]
    ) {
        self.init(lovedOnly: lovedOnly, listIDs: Set(listIDs), categories: Set(categories))
    }
}
