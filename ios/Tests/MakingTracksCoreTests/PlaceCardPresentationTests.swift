import XCTest
@testable import MakingTracksCore

final class PlaceCardPresentationTests: XCTestCase {
    func testShowingAnotherPlaceSwitchesCardWithoutDismissingPresentation() {
        var presentation = PlaceCardPresentation()

        presentation.show(placeID: "p_first")
        let firstPresentationID = presentation.presentationID
        XCTAssertEqual(presentation.activePlaceID, "p_first")
        XCTAssertTrue(presentation.isPresented)
        XCTAssertNotNil(firstPresentationID)

        presentation.show(placeID: "p_second")
        XCTAssertEqual(presentation.activePlaceID, "p_second")
        XCTAssertTrue(presentation.isPresented)
        XCTAssertEqual(presentation.presentationID, firstPresentationID)
    }

    func testItemKeepsStableIdentityWhilePlaceChanges() {
        var presentation = PlaceCardPresentation()

        presentation.show(placeID: "p_first")
        let firstItem = presentation.item
        presentation.show(placeID: "p_second")

        XCTAssertEqual(firstItem?.id, presentation.item?.id)
        XCTAssertEqual(presentation.item?.placeID, "p_second")
    }

    func testDismissClearsActiveCard() {
        var presentation = PlaceCardPresentation()

        presentation.show(placeID: "p_first")
        presentation.dismiss()

        XCTAssertNil(presentation.activePlaceID)
        XCTAssertNil(presentation.presentationID)
        XCTAssertFalse(presentation.isPresented)
    }

    func testNewCardAfterDismissStartsNewPresentation() {
        var presentation = PlaceCardPresentation()

        presentation.show(placeID: "p_first")
        let firstPresentationID = presentation.presentationID
        presentation.dismiss()
        presentation.show(placeID: "p_second")

        XCTAssertEqual(presentation.activePlaceID, "p_second")
        XCTAssertNotEqual(presentation.presentationID, firstPresentationID)
    }
}
