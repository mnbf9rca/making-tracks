import XCTest
@testable import MakingTracksCore
@testable import MakingTracksData

final class PlaceCardActionSlotsTests: XCTestCase {
    func testActionSlotsCoverSavedHiddenAndVisitAxes() {
        let cases: [(PinState, [PlaceCardAction])] = [
            (PinState(saved: false, visit: .none, hidden: false), [.save, .seen, .hide]),
            (PinState(saved: false, visit: .visited, hidden: false), [.save, .love, .unsee(isEnabled: true), .hide]),
            (PinState(saved: false, visit: .loved, hidden: false), [.save, .unlove, .unsee(isEnabled: false), .hide]),
            (PinState(saved: true, visit: .none, hidden: false), [.save, .seen]),
            (PinState(saved: true, visit: .visited, hidden: false), [.save, .love, .unsee(isEnabled: true)]),
            (PinState(saved: true, visit: .loved, hidden: false), [.save, .unlove, .unsee(isEnabled: false)]),
            (PinState(saved: false, visit: .none, hidden: true), [.save, .seen, .unhide]),
            (PinState(saved: false, visit: .visited, hidden: true), [.save, .love, .unsee(isEnabled: true), .unhide]),
            (PinState(saved: false, visit: .loved, hidden: true), [.save, .unlove, .unsee(isEnabled: false), .unhide]),
            (PinState(saved: true, visit: .none, hidden: true), [.save, .seen, .unhide]),
            (PinState(saved: true, visit: .visited, hidden: true), [.save, .love, .unsee(isEnabled: true), .unhide]),
            (PinState(saved: true, visit: .loved, hidden: true), [.save, .unlove, .unsee(isEnabled: false), .unhide]),
        ]

        for (state, expected) in cases {
            XCTAssertEqual(PlaceCardActionSlots(pinState: state).actions, expected, "\(state)")
        }
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
            "Double-tap to choose lists."
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

    func testInverseActionsThatRestorePromptEligibilityClearPromptSuppressionOnSuccess() {
        XCTAssertTrue(NearbyPromptSuppressionPolicy.clearsPromptSuppressionOnSuccess(for: .unsee(isEnabled: true)))
        XCTAssertTrue(NearbyPromptSuppressionPolicy.clearsPromptSuppressionOnSuccess(for: .unhide))

        XCTAssertFalse(NearbyPromptSuppressionPolicy.clearsPromptSuppressionOnSuccess(for: .unlove))
        XCTAssertFalse(NearbyPromptSuppressionPolicy.clearsPromptSuppressionOnSuccess(for: .seen))
        XCTAssertFalse(NearbyPromptSuppressionPolicy.clearsPromptSuppressionOnSuccess(for: .love))
        XCTAssertFalse(NearbyPromptSuppressionPolicy.clearsPromptSuppressionOnSuccess(for: .hide))
        XCTAssertFalse(NearbyPromptSuppressionPolicy.clearsPromptSuppressionOnSuccess(for: .save))
        XCTAssertFalse(NearbyPromptSuppressionPolicy.clearsPromptSuppressionOnSuccess(for: .seenDisabled))
    }

    func testPlaceCardContentBottomPaddingClearsFadeAndActionBar() {
        XCTAssertEqual(
            PlaceCardOverlayMetrics.contentBottomPadding(actionBarHeight: 100),
            124
        )
    }
}
