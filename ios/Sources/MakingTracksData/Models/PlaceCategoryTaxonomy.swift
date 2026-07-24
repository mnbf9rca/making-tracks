public enum PlaceCategoryTaxonomy {
    public static let fallbackCategoryID = "uncategorized"
    public static let knownCategoryIDs: Set<String> = [
        "religious",
        "memorial",
        "archaeological",
        "historic_building",
        "museum",
        "attraction",
        "artwork",
    ]

    public static func isVisible(
        _ category: String,
        visibleCategories: Set<String>?
    ) -> Bool {
        guard let visibleCategories else { return true }
        if visibleCategories.contains(category) { return true }
        if knownCategoryIDs.contains(category) { return false }
        return visibleCategories.contains(fallbackCategoryID)
    }
}
