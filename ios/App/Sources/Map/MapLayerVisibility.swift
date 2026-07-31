import Foundation
import MakingTracksData
import MakingTracksMapStyle

struct MapLayerCategory: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let iconName: String
}

struct MapLayerVisibility: Equatable, Sendable {
    let categories: [MapLayerCategory]
    var showHiddenPlaces: Bool
    var showSavedPlaces: Bool
    var showCoverageShading: Bool
    private(set) var visibleCategories: Set<String>?

    var isDefault: Bool {
        !discoveryScope.differsFromDefault
    }

    var discoveryScope: DiscoveryScope {
        DiscoveryScope(
            visibleCategoryIDs: visibleCategories,
            includeHidden: showHiddenPlaces,
            showSaved: showSavedPlaces,
            showCoverageShading: showCoverageShading
        )
    }

    var toggleAllCategoriesTitle: String {
        areAllCategoriesVisible ? "Hide all categories" : "Show all categories"
    }

    private var areAllCategoriesVisible: Bool {
        guard let visibleCategories else { return true }
        return visibleCategories == Set(categories.map(\.id))
    }

    init(
        categories: [MapLayerCategory] = MapLayerVisibility.defaultCategories,
        showHiddenPlaces: Bool = false,
        showSavedPlaces: Bool = true,
        showCoverageShading: Bool = true,
        visibleCategories: Set<String>? = nil
    ) {
        self.categories = categories
        self.showHiddenPlaces = showHiddenPlaces
        self.showSavedPlaces = showSavedPlaces
        self.showCoverageShading = showCoverageShading
        self.visibleCategories = visibleCategories
    }

    init(
        categories: [MapLayerCategory] = MapLayerVisibility.defaultCategories,
        scope: DiscoveryScope
    ) {
        let liveCategoryIDs = Set(categories.map(\.id))
        let visibleCategories: Set<String>?
        if let storedCategoryIDs = scope.visibleCategoryIDs {
            if storedCategoryIDs.isEmpty {
                visibleCategories = []
            } else {
                let survivingCategoryIDs = storedCategoryIDs.intersection(
                    liveCategoryIDs
                )
                visibleCategories = survivingCategoryIDs.isEmpty
                    || survivingCategoryIDs == liveCategoryIDs
                    ? nil
                    : survivingCategoryIDs
            }
        } else {
            visibleCategories = nil
        }

        self.init(
            categories: categories,
            showHiddenPlaces: scope.includeHidden,
            showSavedPlaces: scope.showSaved,
            showCoverageShading: scope.showCoverageShading,
            visibleCategories: visibleCategories
        )
    }

    func isCategoryVisible(_ categoryID: String) -> Bool {
        visibleCategories?.contains(categoryID) ?? true
    }

    func requiresDiscoveryFeatureRefresh(
        appliedShowHiddenPlaces: Bool,
        appliedShowSavedPlaces: Bool
    ) -> Bool {
        showHiddenPlaces != appliedShowHiddenPlaces
            || showSavedPlaces != appliedShowSavedPlaces
    }

    mutating func setCategory(_ categoryID: String, visible: Bool) {
        let filterableCategoryIDs = Set(categories.map(\.id))
        guard filterableCategoryIDs.contains(categoryID) else { return }

        var next = visibleCategories ?? filterableCategoryIDs
        if visible {
            next.insert(categoryID)
        } else {
            next.remove(categoryID)
        }
        visibleCategories = next == filterableCategoryIDs ? nil : next
    }

    mutating func showAllCategories() {
        visibleCategories = nil
    }

    mutating func toggleAllCategories() {
        visibleCategories = areAllCategoriesVisible ? [] : nil
    }

    private static let defaultCategories: [MapLayerCategory] = PinLayers.categoryIconNames.keys.sorted().map { categoryID in
        MapLayerCategory(
            id: categoryID,
            title: title(for: categoryID),
            iconName: PinLayers.categoryIconNames[categoryID] ?? PinLayers.fallbackCategoryIconName
        )
    } + [
        MapLayerCategory(
            id: PinLayers.fallbackCategoryID,
            title: "Other",
            iconName: PinLayers.fallbackCategoryIconName
        ),
    ]

    private static func title(for categoryID: String) -> String {
        categoryID
            .split(separator: "_")
            .map { word in
                guard let first = word.first else { return "" }
                return String(first).uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }
}

enum ListMapLayerVisibility {
    static func displayed(
        discoveryVisibility: MapLayerVisibility,
        visitFilter: TracksVisitFilter?
    ) -> MapLayerVisibility {
        guard let visitFilter else { return discoveryVisibility }
        return MapLayerVisibility(
            categories: discoveryVisibility.categories,
            showHiddenPlaces: discoveryVisibility.showHiddenPlaces,
            showSavedPlaces: discoveryVisibility.showSavedPlaces,
            showCoverageShading: discoveryVisibility.showCoverageShading,
            visibleCategories: visitFilter.categories
        )
    }

    static func updating(
        visitFilter: TracksVisitFilter,
        from visibility: MapLayerVisibility
    ) -> TracksVisitFilter {
        var next = visitFilter
        next.categories = visibility.visibleCategories
        return next
    }
}
