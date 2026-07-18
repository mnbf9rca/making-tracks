import MakingTracksData

public enum PinFeatureFilter {
    public static func discoveryFeatures(
        _ features: [(MapPlace, PinState)],
        showHidden: Bool,
        visibleCategories: Set<String>?
    ) -> [(MapPlace, PinState)] {
        features.filter { place, state in
            (showHidden || !state.hidden) && isCategoryVisible(place.category, visibleCategories: visibleCategories)
        }
    }

    private static func isCategoryVisible(_ category: String, visibleCategories: Set<String>?) -> Bool {
        guard let visibleCategories else { return true }
        if PinLayers.categoryIconNames.keys.contains(category) {
            return visibleCategories.contains(category)
        }
        return visibleCategories.contains(PinLayers.fallbackCategoryID)
    }
}
