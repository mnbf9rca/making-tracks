import XCTest
@testable import MakingTracksData
@testable import MakingTracksCore

final class NearbyPromptSelectorTests: XCTestCase {
    func testHiddenPlacesAreSkippedEvenWhenPresentInFeatureSource() {
        let visible = MapPlace(id: "visible", lat: 3.1401, lon: 101.6901, tier: 1)
        let hidden = MapPlace(id: "hidden", lat: 3.1400, lon: 101.6900, tier: 1)
        let features = [
            (hidden, PinState(saved: false, visit: .none, hidden: true)),
            (visible, PinState(saved: false, visit: .none, hidden: false)),
        ]

        let candidate = NearbyPromptSelector.candidate(
            features: features,
            names: ["hidden": "Hidden Place", "visible": "Visible Place"],
            userLatitude: 3.1400,
            userLongitude: 101.6900,
            maxDistanceMeters: 125,
            suppressedPlaceIDs: [],
            hiddenPlaceIDs: ["hidden"]
        )

        XCTAssertEqual(candidate?.placeID, "visible")
    }
}
