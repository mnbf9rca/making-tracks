import XCTest
import MakingTracksData
@testable import MakingTracksMapStyle

final class PinMatrixTests: XCTestCase {
    func testPinAppearanceCoversAllSixCells() {
        let cases: [(PinState, PinAppearance)] = [
            (PinState(saved: false, visit: .none), PinAppearance(opacity: 1.0, showBookmarkBadge: false, showHeartBadge: false)),
            (PinState(saved: true, visit: .none), PinAppearance(opacity: 1.0, showBookmarkBadge: true, showHeartBadge: false)),
            (PinState(saved: false, visit: .visited), PinAppearance(opacity: 0.35, showBookmarkBadge: false, showHeartBadge: false)),
            (PinState(saved: true, visit: .visited), PinAppearance(opacity: 0.35, showBookmarkBadge: true, showHeartBadge: false)),
            (PinState(saved: false, visit: .loved), PinAppearance(opacity: 0.35, showBookmarkBadge: false, showHeartBadge: true)),
            (PinState(saved: true, visit: .loved), PinAppearance(opacity: 0.35, showBookmarkBadge: true, showHeartBadge: true)),
        ]

        for (state, expected) in cases {
            XCTAssertEqual(pinAppearance(state), expected, "cell saved=\(state.saved) visit=\(state.visit)")
        }
    }
}
