import XCTest
@testable import MakingTracks

final class HiddenMembershipTrackerTests: XCTestCase {
    func testSuccessfulHiddenMembershipChangeIsConsumedOnceForOverlappingIDs() {
        var tracker = HiddenMembershipTracker(hiddenPlaceIDs: [])

        _ = tracker.beginSetHidden(placeID: "A", hidden: true)

        XCTAssertEqual(tracker.hiddenIDs, ["A"])
        XCTAssertTrue(tracker.consumeHiddenMembershipChange(overlapping: ["A"]))
        XCTAssertFalse(tracker.consumeHiddenMembershipChange(overlapping: ["A"]))
    }

    func testConsumingOnePendingHiddenMembershipChangePreservesOthers() {
        var tracker = HiddenMembershipTracker(hiddenPlaceIDs: [])

        _ = tracker.beginSetHidden(placeID: "A", hidden: true)
        _ = tracker.beginSetHidden(placeID: "B", hidden: true)

        XCTAssertTrue(tracker.consumeHiddenMembershipChange(overlapping: ["A"]))
        XCTAssertFalse(tracker.consumeHiddenMembershipChange(overlapping: ["A"]))
        XCTAssertTrue(tracker.consumeHiddenMembershipChange(overlapping: ["B"]))
        XCTAssertFalse(tracker.consumeHiddenMembershipChange(overlapping: ["B"]))
    }

    func testRollbackRestoresPriorPendingMarkerForSamePlace() {
        var tracker = HiddenMembershipTracker(hiddenPlaceIDs: [])
        _ = tracker.beginSetHidden(placeID: "A", hidden: true)

        let rollback = tracker.beginSetHidden(placeID: "A", hidden: false)
        tracker.rollback(rollback)

        XCTAssertEqual(tracker.hiddenIDs, ["A"])
        XCTAssertTrue(tracker.consumeHiddenMembershipChange(overlapping: ["A"]))
        XCTAssertFalse(tracker.consumeHiddenMembershipChange(overlapping: ["A"]))
    }

    func testRollbackRemovesMarkerCreatedByFailedOperationWhenNoPriorMarker() {
        var tracker = HiddenMembershipTracker(hiddenPlaceIDs: [])

        let rollback = tracker.beginSetHidden(placeID: "A", hidden: true)
        tracker.rollback(rollback)

        XCTAssertEqual(tracker.hiddenIDs, [])
        XCTAssertFalse(tracker.consumeHiddenMembershipChange(overlapping: ["A"]))
    }
}
