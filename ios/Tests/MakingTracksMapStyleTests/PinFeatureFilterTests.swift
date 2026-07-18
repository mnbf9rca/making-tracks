import XCTest
import MakingTracksData
@testable import MakingTracksMapStyle

final class PinFeatureFilterTests: XCTestCase {
    func testHiddenPinsAreExcludedUnlessShowHiddenIsEnabled() {
        let visible = MapPlace(id: "visible", lat: 51.5, lon: -0.12, tier: 1, category: "attraction")
        let hidden = MapPlace(id: "hidden", lat: 51.6, lon: -0.11, tier: 2, category: "attraction")
        let features = [
            (visible, PinState(saved: false, visit: .none, hidden: false)),
            (hidden, PinState(saved: true, visit: .visited, hidden: true)),
        ]

        XCTAssertEqual(
            PinFeatureFilter.discoveryFeatures(features, showHidden: false).map(\.0.id),
            ["visible"]
        )
        XCTAssertEqual(
            PinFeatureFilter.discoveryFeatures(features, showHidden: true).map(\.0.id),
            ["visible", "hidden"]
        )
    }

    func testCategoryTogglesDoNotAffectSourceFeatures() {
        let attraction = MapPlace(id: "attraction", lat: 51.5, lon: -0.12, tier: 1, category: "attraction")
        let hiddenMuseum = MapPlace(id: "hidden-museum", lat: 51.6, lon: -0.11, tier: 2, category: "museum")
        let museum = MapPlace(id: "museum", lat: 51.7, lon: -0.10, tier: 2, category: "museum")
        let future = MapPlace(id: "future", lat: 51.8, lon: -0.09, tier: 2, category: "future_category")
        let features = [
            (attraction, PinState(saved: false, visit: .none, hidden: false)),
            (hiddenMuseum, PinState(saved: false, visit: .none, hidden: true)),
            (museum, PinState(saved: false, visit: .none, hidden: false)),
            (future, PinState(saved: false, visit: .none, hidden: false)),
        ]

        XCTAssertEqual(
            PinFeatureFilter.discoveryFeatures(features, showHidden: false).map(\.0.id),
            ["attraction", "museum", "future"]
        )
        XCTAssertEqual(
            PinFeatureFilter.discoveryFeatures(features, showHidden: true).map(\.0.id),
            ["attraction", "hidden-museum", "museum", "future"]
        )
    }
}
