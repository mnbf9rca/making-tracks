import XCTest
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

    func testDefaultCategoriesExposeFallbackBucket() {
        let visibility = MapLayerVisibility()

        XCTAssertTrue(visibility.categories.contains { category in
            category.id == PinLayers.fallbackCategoryID && category.title == "Other"
        })
    }
}
