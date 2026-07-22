import XCTest
@testable import MakingTracksCore
@testable import MakingTracksData

final class PlaceCardActionSlotsTests: XCTestCase {
    func testVisiblePlaceSlotsFollowRuledSeenLoveStateMachine() {
        XCTAssertEqual(
            PlaceCardActionSlots(pinState: PinState(saved: false, visit: .none)).actions,
            [.save, .seen, .hide]
        )
        XCTAssertEqual(
            PlaceCardActionSlots(pinState: PinState(saved: false, visit: .visited)).actions,
            [.save, .love, .unsee(isEnabled: true)]
        )
        XCTAssertEqual(
            PlaceCardActionSlots(pinState: PinState(saved: false, visit: .loved)).actions,
            [.save, .unlove, .unsee(isEnabled: false)]
        )
    }

    func testDisabledLovedUnseeKeepsTheDeliberatelyOmittedLovedToUnseenEdgeOutOfTheUI() {
        let slots = PlaceCardActionSlots(pinState: PinState(saved: true, visit: .loved))

        XCTAssertEqual(slots.actions.count, 3)
        XCTAssertEqual(slots.actions[2].title, "Un-see")
        XCTAssertFalse(slots.actions[2].isEnabled)
    }

    func testSaveActionHintsSecondaryListPickerGesture() {
        XCTAssertEqual(
            PlaceCardAction.save.accessibilityHint(isSaved: false),
            "Double-tap to choose list."
        )
        XCTAssertEqual(
            PlaceCardAction.save.accessibilityHint(isSaved: true),
            "Double-tap to unsave, double-tap and hold to choose list."
        )
    }

    func testActionsThatLeaveAPlacePromptIneligibleSuppressNearbyPromptImmediately() {
        XCTAssertTrue(NearbyPromptSuppressionPolicy.suppressesPromptImmediately(for: .seen))
        XCTAssertTrue(NearbyPromptSuppressionPolicy.suppressesPromptImmediately(for: .love))
        XCTAssertTrue(NearbyPromptSuppressionPolicy.suppressesPromptImmediately(for: .unlove))
        XCTAssertTrue(NearbyPromptSuppressionPolicy.suppressesPromptImmediately(for: .hide))

        XCTAssertFalse(NearbyPromptSuppressionPolicy.suppressesPromptImmediately(for: .save))
        XCTAssertFalse(NearbyPromptSuppressionPolicy.suppressesPromptImmediately(for: .unsee(isEnabled: true)))
        XCTAssertFalse(NearbyPromptSuppressionPolicy.suppressesPromptImmediately(for: .seenDisabled))
        XCTAssertFalse(NearbyPromptSuppressionPolicy.suppressesPromptImmediately(for: .unhide))
    }

    func testHiddenPlaceOffersOnlyUnhideBackTowardUnseen() {
        XCTAssertEqual(
            PlaceCardActionSlots(pinState: PinState(saved: false, visit: .none, hidden: true)).actions,
            [.save, .seenDisabled, .unhide]
        )
    }

    func testHiddenFallbackStillKeepsThreeSlots() {
        let slots = PlaceCardActionSlots(pinState: PinState(saved: false, visit: .none, hidden: true))

        XCTAssertEqual(slots.actions, [.save, .seenDisabled, .unhide])
    }

    func testPlaceCardContentBottomPaddingClearsFadeAndActionBar() {
        XCTAssertEqual(
            PlaceCardOverlayMetrics.contentBottomPadding(actionBarHeight: 100),
            124
        )
    }
}
