import XCTest
import MakingTracksData
import MakingTracksMapStyle
@testable import MakingTracks

final class MapLayerVisibilityTests: XCTestCase {
    func testCategoryToggleNormalizesAllVisibleToNoFilter() {
        let categories = [
            MapLayerCategory(id: "attraction", title: "Attraction", iconName: "pin-category-attraction"),
            MapLayerCategory(id: "museum", title: "Museum", iconName: "pin-category-museum"),
            MapLayerCategory(id: PinLayers.fallbackCategoryID, title: "Other", iconName: PinLayers.fallbackCategoryIconName),
        ]
        var visibility = MapLayerVisibility(categories: categories)

        XCTAssertNil(visibility.visibleCategories)
        XCTAssertTrue(visibility.isCategoryVisible("attraction"))
        XCTAssertTrue(visibility.isCategoryVisible("museum"))

        visibility.setCategory("museum", visible: false)

        XCTAssertEqual(visibility.visibleCategories, [PinLayers.fallbackCategoryID, "attraction"])
        XCTAssertTrue(visibility.isCategoryVisible("attraction"))
        XCTAssertFalse(visibility.isCategoryVisible("museum"))
        XCTAssertTrue(visibility.isCategoryVisible(PinLayers.fallbackCategoryID))

        visibility.setCategory("museum", visible: true)

        XCTAssertNil(visibility.visibleCategories)
        XCTAssertTrue(visibility.isCategoryVisible("attraction"))
        XCTAssertTrue(visibility.isCategoryVisible("museum"))
    }

    func testShowHiddenModeIsIndependentOfCategoryVisibility() {
        let categories = [
            MapLayerCategory(id: "attraction", title: "Attraction", iconName: "pin-category-attraction"),
            MapLayerCategory(id: "museum", title: "Museum", iconName: "pin-category-museum"),
            MapLayerCategory(id: PinLayers.fallbackCategoryID, title: "Other", iconName: PinLayers.fallbackCategoryIconName),
        ]
        var visibility = MapLayerVisibility(categories: categories)

        visibility.setCategory("museum", visible: false)
        visibility.showHiddenPlaces = true

        XCTAssertEqual(visibility.visibleCategories, [PinLayers.fallbackCategoryID, "attraction"])
        XCTAssertTrue(visibility.showHiddenPlaces)
    }

    func testCoverageShadingDefaultsOnButDoesNotAffectDefaultFilterState() {
        var visibility = MapLayerVisibility()

        XCTAssertTrue(visibility.showCoverageShading)
        XCTAssertTrue(visibility.isDefault)

        visibility.showCoverageShading = false

        XCTAssertFalse(visibility.showCoverageShading)
        XCTAssertTrue(visibility.isDefault)
    }

    func testSavedPlacesDefaultOnAndParticipateInDefaultFilterStateAndDiscoveryFiltering() {
        let unsaved = MapPlace(
            id: "unsaved-attraction",
            lat: 51.5,
            lon: -0.12,
            tier: 1,
            category: "attraction"
        )
        let saved = MapPlace(
            id: "saved-museum",
            lat: 51.6,
            lon: -0.11,
            tier: 2,
            category: "museum"
        )
        let features = [
            (unsaved, PinState(saved: false, visit: .none, hidden: false)),
            (saved, PinState(saved: true, visit: .none, hidden: false)),
        ]
        var visibility = MapLayerVisibility()

        XCTAssertTrue(visibility.showSavedPlaces)
        XCTAssertTrue(visibility.isDefault)
        XCTAssertEqual(
            PinFeatureFilter.discoveryFeatures(
                features,
                showHidden: visibility.showHiddenPlaces,
                showSaved: visibility.showSavedPlaces
            ).map(\.0.id),
            ["unsaved-attraction", "saved-museum"]
        )

        visibility.showSavedPlaces = false

        XCTAssertFalse(visibility.isDefault)
        XCTAssertEqual(
            PinFeatureFilter.discoveryFeatures(
                features,
                showHidden: visibility.showHiddenPlaces,
                showSaved: visibility.showSavedPlaces
            ).map(\.0.id),
            ["unsaved-attraction"]
        )

        visibility.showSavedPlaces = true

        XCTAssertTrue(visibility.isDefault)
    }

    func testDiscoveryFeatureRefreshDetectsSavedOrHiddenChangesOnly() {
        let applied = MapLayerVisibility()
        var savedChanged = applied
        savedChanged.showSavedPlaces = false
        var hiddenChanged = applied
        hiddenChanged.showHiddenPlaces = true
        var coverageChanged = applied
        coverageChanged.showCoverageShading = false
        var categoriesChanged = applied
        categoriesChanged.setCategory("museum", visible: false)

        XCTAssertFalse(applied.requiresDiscoveryFeatureRefresh(
            appliedShowHiddenPlaces: applied.showHiddenPlaces,
            appliedShowSavedPlaces: applied.showSavedPlaces
        ))
        XCTAssertTrue(savedChanged.requiresDiscoveryFeatureRefresh(
            appliedShowHiddenPlaces: applied.showHiddenPlaces,
            appliedShowSavedPlaces: applied.showSavedPlaces
        ))
        XCTAssertTrue(hiddenChanged.requiresDiscoveryFeatureRefresh(
            appliedShowHiddenPlaces: applied.showHiddenPlaces,
            appliedShowSavedPlaces: applied.showSavedPlaces
        ))
        XCTAssertFalse(coverageChanged.requiresDiscoveryFeatureRefresh(
            appliedShowHiddenPlaces: applied.showHiddenPlaces,
            appliedShowSavedPlaces: applied.showSavedPlaces
        ))
        XCTAssertFalse(categoriesChanged.requiresDiscoveryFeatureRefresh(
            appliedShowHiddenPlaces: applied.showHiddenPlaces,
            appliedShowSavedPlaces: applied.showSavedPlaces
        ))
    }

    func testDefaultCategoriesExposeFallbackBucket() {
        let visibility = MapLayerVisibility()

        XCTAssertTrue(visibility.categories.contains { category in
            category.id == PinLayers.fallbackCategoryID && category.title == "Other"
        })
    }

    func testToggleAllCategoriesHidesEverythingWhenEverythingIsVisible() {
        let categories = [
            MapLayerCategory(id: "attraction", title: "Attraction", iconName: "pin-category-attraction"),
            MapLayerCategory(id: "museum", title: "Museum", iconName: "pin-category-museum"),
            MapLayerCategory(id: PinLayers.fallbackCategoryID, title: "Other", iconName: PinLayers.fallbackCategoryIconName),
        ]
        var visibility = MapLayerVisibility(categories: categories)

        visibility.toggleAllCategories()

        XCTAssertEqual(visibility.visibleCategories, [])
        XCTAssertFalse(visibility.isCategoryVisible("attraction"))
        XCTAssertFalse(visibility.isCategoryVisible("museum"))
        XCTAssertFalse(visibility.isCategoryVisible(PinLayers.fallbackCategoryID))

        visibility.toggleAllCategories()

        XCTAssertNil(visibility.visibleCategories)
        XCTAssertTrue(visibility.isCategoryVisible("attraction"))
        XCTAssertTrue(visibility.isCategoryVisible("museum"))
        XCTAssertTrue(visibility.isCategoryVisible(PinLayers.fallbackCategoryID))
    }

    func testToggleAllCategoriesTitleReflectsCurrentState() {
        let categories = [
            MapLayerCategory(id: "attraction", title: "Attraction", iconName: "pin-category-attraction"),
            MapLayerCategory(id: "museum", title: "Museum", iconName: "pin-category-museum"),
        ]
        var visibility = MapLayerVisibility(categories: categories)

        XCTAssertEqual(visibility.toggleAllCategoriesTitle, "Hide all categories")

        visibility.setCategory("museum", visible: false)
        XCTAssertEqual(visibility.toggleAllCategoriesTitle, "Show all categories")
    }

    func testListMapDisplaysVisitFilterCategoriesWithoutChangingDiscoveryVisibility() {
        let discovery = MapLayerVisibility(
            showSavedPlaces: false,
            visibleCategories: ["museum"]
        )
        let displayed = ListMapLayerVisibility.displayed(
            discoveryVisibility: discovery,
            visitFilter: TracksVisitFilter(categories: ["attraction"])
        )

        XCTAssertEqual(displayed.visibleCategories, ["attraction"])
        XCTAssertFalse(displayed.showSavedPlaces)
        XCTAssertEqual(discovery.visibleCategories, ["museum"])
    }

    func testListMapLayersCanWriteAnExplicitlyEmptyCategoryScope() {
        var visibility = MapLayerVisibility()
        visibility.toggleAllCategories()

        let updated = ListMapLayerVisibility.updating(
            visitFilter: .all,
            from: visibility
        )

        XCTAssertNotNil(updated.categories)
        XCTAssertEqual(updated.categories, [])
        XCTAssertTrue(updated.isActive)
    }
}
