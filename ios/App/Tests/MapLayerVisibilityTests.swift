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
        let discovery = MapLayerVisibility(visibleCategories: ["museum"])
        let displayed = ListMapLayerVisibility.displayed(
            discoveryVisibility: discovery,
            visitFilter: TracksVisitFilter(categories: ["attraction"])
        )

        XCTAssertEqual(displayed.visibleCategories, ["attraction"])
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
