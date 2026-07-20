import XCTest
import MakingTracksData
@testable import MakingTracksMapStyle

final class PinFeatureFilterTests: XCTestCase {
    func testTierZoomGateShowsOnlyLandmarksAndHighlightsAtCityZoom() {
        let features = [
            (MapPlace(id: "t1", lat: 51.5, lon: -0.12, tier: 1, category: "attraction"), PinState(saved: false, visit: .none)),
            (MapPlace(id: "t2", lat: 51.6, lon: -0.11, tier: 2, category: "museum"), PinState(saved: false, visit: .none)),
            (MapPlace(id: "t3", lat: 51.7, lon: -0.10, tier: 3, category: "artwork"), PinState(saved: false, visit: .none)),
            (MapPlace(id: "t4", lat: 51.8, lon: -0.09, tier: 4, category: "memorial"), PinState(saved: false, visit: .none)),
        ]

        XCTAssertEqual(
            PinFeatureFilter.discoveryFeatures(features, showHidden: false, zoom: 11).map(\.0.id),
            ["t1", "t2"]
        )
        XCTAssertEqual(
            PinFeatureFilter.discoveryFeatures(features, showHidden: false, zoom: 14).map(\.0.id),
            ["t1", "t2", "t3", "t4"]
        )
    }

    func testSparseTierFallbackKeepsOverviewFromGoingBlank() {
        let visibleOddity = MapPlace(id: "visible-t4", lat: 3.14, lon: 101.69, tier: 4, category: "attraction")
        let hiddenOddity = MapPlace(id: "hidden-t4", lat: 3.15, lon: 101.70, tier: 4, category: "museum")
        let features = [
            (visibleOddity, PinState(saved: false, visit: .none, hidden: false)),
            (hiddenOddity, PinState(saved: false, visit: .none, hidden: true)),
        ]

        XCTAssertEqual(
            PinFeatureFilter.discoveryFeatures(features, showHidden: false, zoom: 11).map(\.0.id),
            []
        )
        XCTAssertEqual(
            PinFeatureFilter.discoveryFeatures(features, showHidden: false, zoom: 11, allowSparseTierFallback: true).map(\.0.id),
            ["visible-t4"]
        )
        XCTAssertEqual(
            PinFeatureFilter.discoveryFeatures(features, showHidden: false, zoom: 9, allowSparseTierFallback: true).map(\.0.id),
            []
        )
    }

    func testTierZoomGateStillAppliesWhenShowHiddenIsEnabled() {
        let hiddenHighlight = MapPlace(id: "hidden-t2", lat: 51.6, lon: -0.11, tier: 2, category: "attraction")
        let hiddenOddity = MapPlace(id: "hidden-t4", lat: 51.7, lon: -0.10, tier: 4, category: "attraction")
        let visibleOddity = MapPlace(id: "visible-t4", lat: 51.7, lon: -0.10, tier: 4, category: "attraction")
        let features = [
            (hiddenHighlight, PinState(saved: true, visit: .visited, hidden: true)),
            (hiddenOddity, PinState(saved: true, visit: .visited, hidden: true)),
            (visibleOddity, PinState(saved: false, visit: .none, hidden: false)),
        ]

        XCTAssertEqual(
            PinFeatureFilter.discoveryFeatures(features, showHidden: true, zoom: 11).map(\.0.id),
            ["hidden-t2"]
        )
    }

    func testNearbyPromptFeaturesAreHiddenFilteredButNotTierThinned() {
        let hiddenHighlight = MapPlace(id: "hidden-t2", lat: 51.6, lon: -0.11, tier: 2, category: "attraction")
        let visibleOddity = MapPlace(id: "visible-t4", lat: 51.7, lon: -0.10, tier: 4, category: "attraction")
        let features = [
            (hiddenHighlight, PinState(saved: true, visit: .visited, hidden: true)),
            (visibleOddity, PinState(saved: false, visit: .none, hidden: false)),
        ]

        XCTAssertEqual(
            PinFeatureFilter.nearbyPromptFeatures(features).map(\.0.id),
            ["visible-t4"]
        )
    }

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
