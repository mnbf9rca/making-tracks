import XCTest
import MakingTracksData
@testable import MakingTracksMapStyle

final class PinFeatureFilterTests: XCTestCase {
    func testHiddenPinsAreExcludedUnlessShowHiddenIsEnabled() {
        let visible = MapPlace(id: "visible", lat: 51.5, lon: -0.12, tier: 1)
        let hidden = MapPlace(id: "hidden", lat: 51.6, lon: -0.11, tier: 2)
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
}
