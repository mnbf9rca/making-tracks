import Foundation
import XCTest

@MainActor
final class MakingTracksCoreLoopUITests: XCTestCase {
    private let placeID = "mt1_00000000000000000000000000"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCardTogglesPersistAndRestyleMapPin() {
        let app = launch(reset: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))

        tapFixturePin(in: map)
        XCTAssertTrue(app.staticTexts["Ghost Sign"].waitForExistence(timeout: 5))
        attachScreenshot(named: "card-open")

        app.buttons["place-card.save"].tap()
        app.buttons["place-card.visited"].tap()
        XCTAssertTrue(app.buttons["place-card.loved"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["place-card.loved"].label, "Love")
        app.buttons["place-card.loved"].tap()
        XCTAssertTrue(app.buttons["place-card.loved"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["place-card.loved"].label, "Unlove")
        app.buttons["place-card.close"].tap()

        XCTAssertEqual(app.staticTexts["tracks.visit-count.\(placeID)"].label, "Tracks visits: 1")
        XCTAssertTrue(waitForAccessibilityPin(
            in: app,
            placeID: placeID,
            label: "Ghost Sign, Attraction, loved, saved"
        ))
        attachScreenshot(named: "map-after-visited-fade")

        app.terminate()

        let relaunched = launch(reset: false)
        let relaunchedMap = relaunched.otherElements["map.surface"]
        XCTAssertTrue(relaunchedMap.waitForExistence(timeout: 10))
        XCTAssertEqual(relaunched.staticTexts["tracks.visit-count.\(placeID)"].label, "Tracks visits: 1")
        tapFixturePin(in: relaunchedMap)
        XCTAssertTrue(relaunched.staticTexts["Ghost Sign"].waitForExistence(timeout: 5))
        XCTAssertEqual(relaunched.buttons["place-card.save"].label, "Saved")
        XCTAssertTrue(relaunched.buttons["place-card.loved"].waitForExistence(timeout: 5))
        XCTAssertEqual(relaunched.buttons["place-card.loved"].label, "Unlove")
    }

    func testFirstRunOnboardingPersistsRegionAndCompletesBeforeRelaunch() {
        let app = launch(reset: true, resetOnboarding: true)

        XCTAssertTrue(app.staticTexts["Interesting places around you"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["map.surface"].exists)
        XCTAssertFalse(app.otherElements["map.loading"].exists)
        XCTAssertTrue(app.staticTexts["onboarding.progress"].waitForExistence(timeout: 5))
        app.buttons["onboarding.next"].tap()

        XCTAssertTrue(app.staticTexts["Where places come from"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Nothing you save leaves unless you choose to share it."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "no one can see where you look")).firstMatch.exists)
        app.buttons["onboarding.next"].tap()

        XCTAssertTrue(app.staticTexts["Choose your first region"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["onboarding.region.uk"].value as? String, "Not selected")
        XCTAssertFalse(app.buttons["onboarding.next"].isEnabled)
        app.buttons["onboarding.region.uk"].tap()
        app.buttons["onboarding.next"].tap()

        XCTAssertTrue(app.staticTexts["Download UK"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(identifier: "onboarding.download.size", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["onboarding.include-images"].exists)
        app.buttons["onboarding.next"].tap()

        XCTAssertTrue(app.staticTexts["Show your position?"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["onboarding.location-requested"].exists)
        app.buttons["onboarding.location.skip"].tap()

        XCTAssertTrue(app.staticTexts["Fresh snow"].waitForExistence(timeout: 5))
        app.buttons["onboarding.finish"].tap()

        XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["map.startup-region"].label, "Startup region: UK")
        XCTAssertFalse(app.staticTexts["Interesting places around you"].exists)

        app.terminate()

        let relaunched = launch(reset: false)
        XCTAssertTrue(relaunched.otherElements["map.surface"].waitForExistence(timeout: 10))
        XCTAssertEqual(relaunched.staticTexts["map.startup-region"].label, "Startup region: UK")
        XCTAssertFalse(relaunched.staticTexts["Interesting places around you"].exists)
    }

    func testReplayOnboardingPreselectsPersistedRegionFromSettings() {
        let app = launch(reset: true, resetOnboarding: true)
        completeOnboardingSelectingUK(in: app)

        openAppMenu(in: app)
        app.buttons["menu.row.settings"].tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
        let replayOnboardingButton = app.buttons["settings.replay-onboarding"]
        XCTAssertTrue(scrollToExistence(of: replayOnboardingButton, in: app))
        replayOnboardingButton.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()

        XCTAssertTrue(app.staticTexts["Interesting places around you"].waitForExistence(timeout: 5))
        app.buttons["onboarding.next"].tap()
        app.buttons["onboarding.next"].tap()

        XCTAssertTrue(app.staticTexts["Choose your first region"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["onboarding.region.uk"].value as? String, "Selected")
    }

    func testOnboardingRequestsLocationOnlyOnAffirmativeTap() {
        let app = launch(reset: true, locationNotDetermined: true, resetOnboarding: true)

        app.buttons["onboarding.next"].tap()
        app.buttons["onboarding.next"].tap()
        app.buttons["onboarding.region.malaysia"].tap()
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.staticTexts["Download Malaysia"].waitForExistence(timeout: 5))
        app.buttons["onboarding.next"].tap()

        XCTAssertTrue(app.staticTexts["Show your position?"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["onboarding.location-request-count"].label, "Location requests: 0")
        app.buttons["onboarding.location.allow"].tap()

        XCTAssertTrue(app.staticTexts["Fresh snow"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["onboarding.location-request-count"].label, "Location requests: 1")
    }

    func testOnboardingControlsRemainReachableAtAccessibilityTextSize() {
        let app = launch(reset: true, accessibilityTextSize: true, resetOnboarding: true)

        XCTAssertTrue(app.buttons["onboarding.next"].waitForExistence(timeout: 5))
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.buttons["onboarding.next"].waitForExistence(timeout: 5))
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.buttons["onboarding.region.uk"].waitForExistence(timeout: 5))
        app.buttons["onboarding.region.uk"].tap()
        XCTAssertTrue(app.buttons["onboarding.next"].isEnabled)
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.buttons["onboarding.next"].waitForExistence(timeout: 5))
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.buttons["onboarding.location.skip"].waitForExistence(timeout: 5))
    }

    func testTappingAnotherPinSwitchesOpenCard() throws {
        let app = launch(reset: true, pinDiagnostics: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMapToFinishLoading(in: app))

        XCTAssertTrue(activateFixturePin(
            in: map,
            app: app,
            placeID: placeID,
            title: "Ghost Sign",
            expectedLabel: "Ghost Sign, Attraction, not visited"
        ))
        XCTAssertTrue(app.staticTexts["Ghost Sign"].waitForExistence(timeout: 5))
        let sheet = app.scrollViews.matching(identifierPrefix: "place-card.instance.").firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        let sheetInstanceIdentifier = sheet.identifier

        XCTAssertTrue(activateFixturePin(
            in: map,
            app: app,
            placeID: "mt1_00000000000000000000000001",
            title: "Art Deco Cinema",
            expectedLabel: "Art Deco Cinema, Historic Building, not visited"
        ))
        XCTAssertTrue(app.staticTexts["Art Deco Cinema"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.scrollViews[sheetInstanceIdentifier].exists)
        XCTAssertFalse(app.staticTexts["Ghost Sign"].exists)
        XCTAssertFalse(element(identifier: "place-card.description", in: app).exists)
        let sourceArticle = app.buttons["place-card.source-article"]
        XCTAssertTrue(sourceArticle.exists)
        XCTAssertEqual(sourceArticle.label, "OpenStreetMap source article")
        XCTAssertTrue(sourceArticle.isHittable)
        assertDoesNotExposeURL(sourceArticle)
        attachScreenshot(named: "card-switched-to-art-deco-cinema")

        app.buttons["place-card.close"].tap()
        XCTAssertFalse(app.staticTexts["Art Deco Cinema"].waitForExistence(timeout: 2))
    }

    func testPlaceCardOverhaulRendersHierarchyAndHideAction() {
        let app = launch(reset: true, seedUserList: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))

        openFixtureCard(in: map, app: app)

        let title = element(identifier: "place-card.title", in: app)
        let typeLabel = element(identifier: "place-card.type.label", in: app)
        let description = element(identifier: "place-card.description", in: app)
        let sourceArticle = app.buttons["place-card.source-article"]
        let photo = element(identifier: "place-card.photo", in: app)
        let chips = element(identifier: "place-card.list-chips", in: app)
        let attribution = element(identifier: "place-card.attribution", in: app)

        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "Ghost Sign")
        XCTAssertEqual(typeLabel.label, "Attraction")
        XCTAssertEqual(
            description.label,
            "A hand-painted sign still visible above the old shopfront."
        )
        XCTAssertTrue(sourceArticle.waitForExistence(timeout: 5))
        XCTAssertEqual(sourceArticle.label, "Wikipedia source article")
        XCTAssertTrue(sourceArticle.isHittable)
        assertDoesNotExposeURL(sourceArticle)
        XCTAssertTrue(expandPlaceCardSheet(in: app))

        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        XCTAssertEqual(photo.label, "Photo of Ghost Sign")

        let actionBar = app.otherElements["place-card.action-bar"]
        let saveButton = actionBar.buttons["place-card.save"]
        let seenButton = actionBar.buttons["place-card.visited"]
        let hideButton = actionBar.buttons["place-card.hide"]
        XCTAssertTrue(actionBar.waitForExistence(timeout: 5))
        XCTAssertEqual(actionBar.buttons.count, 3)
        XCTAssertTrue(saveButton.exists)
        XCTAssertTrue(seenButton.exists)
        XCTAssertTrue(hideButton.exists)
        XCTAssertFalse(app.buttons["place-card.add-to-list"].exists)
        XCTAssertEqual(seenButton.label, "Seen")
        XCTAssertEqual(hideButton.label, "Hide")
        let saveFrameBeforeAttributionScroll = saveButton.frame
        XCTAssertTrue(chips.waitForExistence(timeout: 5))
        XCTAssertTrue(chips.label.contains("Date night"))

        XCTAssertTrue(scrollToExistence(of: attribution, in: app))
        XCTAssertTrue(attribution.label.contains("Fixture photo"))

        assertVerticallyOrdered([
            ("title", title),
            ("type", typeLabel),
            ("description", description),
            ("sourceArticle", sourceArticle),
            ("photo", photo),
            ("chips", chips),
            ("attribution", attribution),
        ])
        XCTAssertLessThan(abs(saveButton.frame.minY - saveFrameBeforeAttributionScroll.minY), 3)
        XCTAssertTrue(saveButton.isHittable)

        hideButton.tap()
        XCTAssertTrue(app.staticTexts["Hidden — Undo"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Ghost Sign"].waitForExistence(timeout: 2))

        tapFixturePin(in: map)
        XCTAssertFalse(app.staticTexts["Ghost Sign"].waitForExistence(timeout: 2))
    }

    func testCustomListCanBeCreatedBrowsedAndShownOnMap() {
        let app = launch(reset: true, resetTheme: true, pinDiagnostics: true, seedTrackVisits: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMapToFinishLoading(in: app))
        let openFixture = app.buttons["debug.open-fixture"]
        XCTAssertTrue(openFixture.waitForExistence(timeout: 5))
        openFixture.tap()
        XCTAssertTrue(app.staticTexts["Ghost Sign"].waitForExistence(timeout: 5))

        let saveButton = app.otherElements["place-card.action-bar"].buttons["place-card.save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.press(forDuration: 1.0)
        XCTAssertTrue(app.navigationBars["Add to list"].waitForExistence(timeout: 5))
        app.textFields["list-picker.new-name"].tap()
        app.textFields["list-picker.new-name"].typeText("KL walk")
        app.buttons["list-picker.create"].tap()
        XCTAssertTrue(app.buttons.matching(identifierPrefix: "list-picker.row.").firstMatch.waitForExistence(timeout: 5))
        app.buttons["list-picker.done"].tap()

        let savedButton = app.otherElements["place-card.action-bar"].buttons["place-card.save"]
        XCTAssertTrue(savedButton.waitForExistence(timeout: 5))
        XCTAssertEqual(savedButton.label, "Save")
        let listChips = element(identifier: "place-card.list-chips", in: app)
        XCTAssertTrue(listChips.waitForExistence(timeout: 5))
        XCTAssertTrue(listChips.label.contains("KL walk"))
        XCTAssertFalse(listChips.label.contains("Want to go"))
        app.buttons["place-card.close"].tap()

        openAppMenu(in: app)
        app.buttons["menu.row.lists"].tap()
        XCTAssertTrue(app.staticTexts["Lists"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["KL walk"].waitForExistence(timeout: 5))
        app.staticTexts["KL walk"].tap()

        XCTAssertTrue(app.staticTexts["lists.detail.progress"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["lists.detail.progress"].label, "you've been to 1 of these · all seen")
        XCTAssertTrue(app.buttons["lists.detail.show-map"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Ghost Sign"].waitForExistence(timeout: 5))
        app.buttons["lists.detail.show-map"].tap()

        XCTAssertTrue(app.staticTexts["map.list-mode.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["map.list-mode.title"].label, "KL walk")
        XCTAssertTrue(app.buttons["map.list-mode.back"].exists)
        XCTAssertFalse(app.buttons["map.list-mode.close"].exists)
        XCTAssertFalse(app.buttons["map.menu"].exists)
        XCTAssertTrue(waitForSourceFeatureCount(1, in: app))
        XCTAssertTrue(waitForTrackSegmentCount(0, in: app))

        let freshLayerButton = app.buttons["map.list-mode.fresh"]
        let tracksLayerButton = app.buttons["map.list-mode.tracks"]
        XCTAssertTrue(freshLayerButton.waitForExistence(timeout: 5))
        XCTAssertTrue(tracksLayerButton.waitForExistence(timeout: 5))
        XCTAssertEqual(freshLayerButton.label, "Unmarked paper")
        XCTAssertEqual(freshLayerButton.value as? String, "Not selected")
        XCTAssertEqual(tracksLayerButton.label, "My tracks")
        XCTAssertEqual(tracksLayerButton.value as? String, "Selected")
        XCTAssertGreaterThan(freshLayerButton.frame.midY, map.frame.midY)
        XCTAssertGreaterThan(tracksLayerButton.frame.midY, map.frame.midY)
        XCTAssertLessThan(freshLayerButton.frame.midX, tracksLayerButton.frame.midX)
        let locateButton = app.buttons["map.locate-me"]
        let attribution = app.staticTexts["map.openstreetmap-attribution"]
        let listModeControl = app.otherElements["map.list-mode.control"]
        XCTAssertTrue(locateButton.waitForExistence(timeout: 5))
        XCTAssertTrue(attribution.waitForExistence(timeout: 5))
        XCTAssertTrue(listModeControl.waitForExistence(timeout: 5))
        assertNoFrameIntersection(locateButton, listModeControl)
        assertNoFrameIntersection(attribution, listModeControl)
        let layersButton = app.buttons["map.layers"]
        XCTAssertTrue(layersButton.waitForExistence(timeout: 5))
        layersButton.tap()
        XCTAssertTrue(app.navigationBars["Layers"].waitForExistence(timeout: 5))
        app.buttons["map.layers.done"].tap()
        attachScreenshot(named: "list-map-polished-chrome")
        freshLayerButton.tap()
        XCTAssertTrue(waitForSourceFeatureCount(0, in: app))
        XCTAssertTrue(waitForTrackSegmentCount(0, in: app))
        XCTAssertEqual(freshLayerButton.value as? String, "Selected")

        app.buttons["map.list-mode.back"].tap()
        XCTAssertTrue(app.staticTexts["KL walk"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["lists.detail.show-map"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForNonExistence(of: app.staticTexts["map.list-mode.title"], timeout: 5))
    }

    func testTracksMenuShowsVisitedRowsAndLovedFilter() {
        let app = launch(reset: true, pinDiagnostics: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMapToFinishLoading(in: app))
        openFixtureCard(in: map, app: app)

        app.buttons["place-card.visited"].tap()
        XCTAssertTrue(app.buttons["place-card.close"].waitForExistence(timeout: 5))
        app.buttons["place-card.close"].tap()

        openAppMenu(in: app)
        XCTAssertTrue(app.buttons["menu.row.tracks"].waitForExistence(timeout: 5))
        app.buttons["menu.row.tracks"].tap()

        XCTAssertTrue(app.staticTexts["Tracks"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["tracks.filter.loved"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["tracks.summary"].label, "1 visit")
        XCTAssertTrue(app.staticTexts["Ghost Sign"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifierPrefix: "tracks.row.").firstMatch.exists)
    }

    func testTrackGeometryDrawsConnectorFromSeededFixtureVisits() {
        let app = launch(reset: true, pinDiagnostics: true, seedTrackList: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMapToFinishLoading(in: app))
        XCTAssertTrue(waitForTrackSegmentCount(0, in: app))

        openAppMenu(in: app)
        app.buttons["menu.row.lists"].tap()
        XCTAssertTrue(app.staticTexts["Lists"].waitForExistence(timeout: 5))
        app.staticTexts["Track pair"].tap()
        XCTAssertTrue(app.buttons["lists.detail.show-map"].waitForExistence(timeout: 5))
        app.buttons["lists.detail.show-map"].tap()
        XCTAssertTrue(app.staticTexts["map.list-mode.title"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForSourceFeatureCount(2, in: app))
        XCTAssertTrue(waitForTrackSegmentCount(1, in: app))
        attachScreenshot(named: "tracks-static-geometry")
    }

    func testTrackReplaySliderAndAutoplayDriveMapPins() {
        let app = launch(
            reset: true,
            pinDiagnostics: true,
            seedMultiDayTrackList: true,
            densePins: true,
            startupViewport: "kl-street",
            trackReplayBeatDuration: 5
        )

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMapToFinishLoading(in: app))

        openAppMenu(in: app)
        app.buttons["menu.row.lists"].tap()
        XCTAssertTrue(app.staticTexts["Lists"].waitForExistence(timeout: 5))
        app.staticTexts["Replay week"].tap()
        XCTAssertTrue(app.buttons["lists.detail.show-map"].waitForExistence(timeout: 5))
        app.buttons["lists.detail.show-map"].tap()

        XCTAssertTrue(app.staticTexts["map.list-mode.title"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForSourceFeatureCount(6, in: app))
        XCTAssertTrue(waitForTrackSegmentCount(5, in: app))
        XCTAssertTrue(waitForAccessibilityPin(
            in: app,
            placeID: "mt1_D0000000000000000000000001",
            label: "Dense Pin 1, Attraction, visited"
        ))
        XCTAssertTrue(waitForAccessibilityPin(
            in: app,
            placeID: "mt1_D0000000000000000000000002",
            label: "Dense Pin 2, Historic Building, visited"
        ))

        let slider = app.sliders["map.track-replay.slider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        slider.adjust(toNormalizedSliderPosition: 0.0)
        XCTAssertTrue(waitForTrackSegmentCount(0, in: app))
        XCTAssertTrue(waitForAccessibilityPin(
            in: app,
            placeID: "mt1_D0000000000000000000000001",
            label: "Dense Pin 1, Attraction, visited"
        ))
        XCTAssertTrue(waitForAccessibilityPin(
            in: app,
            placeID: "mt1_D0000000000000000000000002",
            label: "Dense Pin 2, Historic Building, not visited"
        ))

        let play = app.buttons["map.track-replay.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        play.tap()
        XCTAssertTrue(waitForTrackSegmentCount(1, in: app))
        XCTAssertTrue(waitForAccessibilityPin(
            in: app,
            placeID: "mt1_D0000000000000000000000002",
            label: "Dense Pin 2, Historic Building, visited"
        ))
        XCTAssertEqual(play.label, "Pause track replay")
        play.tap()
        XCTAssertEqual(play.label, "Play track replay")
        attachScreenshot(named: "track-replay-pin-arrival")
    }

    func testListMapBackReturnsToSeededListDetail() {
        let app = launch(reset: true, pinDiagnostics: true, seedTrackList: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMapToFinishLoading(in: app))

        openAppMenu(in: app)
        app.buttons["menu.row.lists"].tap()
        XCTAssertTrue(app.staticTexts["Lists"].waitForExistence(timeout: 5))
        app.staticTexts["Track pair"].tap()
        XCTAssertTrue(app.buttons["lists.detail.show-map"].waitForExistence(timeout: 5))
        app.buttons["lists.detail.show-map"].tap()
        XCTAssertTrue(app.staticTexts["map.list-mode.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["map.list-mode.title"].label, "Track pair")

        app.buttons["map.list-mode.back"].tap()

        XCTAssertTrue(app.staticTexts["Track pair"].waitForExistence(timeout: 5))
        app.buttons["lists.detail.show-map"].tap()
        XCTAssertTrue(app.staticTexts["map.list-mode.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["map.list-mode.title"].label, "Track pair")
        XCTAssertFalse(app.staticTexts["Lists"].exists)
    }

    func testMyTracksSystemListDrawsWholeLogTrackWithoutStoredListMembership() {
        let app = launch(reset: true, pinDiagnostics: true, seedBurstTrackVisits: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMapToFinishLoading(in: app))
        XCTAssertTrue(waitForTrackSegmentCount(0, in: app))

        openAppMenu(in: app)
        app.buttons["menu.row.lists"].tap()
        XCTAssertTrue(app.staticTexts["Lists"].waitForExistence(timeout: 5))
        app.staticTexts["My tracks"].tap()
        XCTAssertTrue(app.buttons["lists.detail.show-map"].waitForExistence(timeout: 5))
        app.buttons["lists.detail.show-map"].tap()
        XCTAssertTrue(app.staticTexts["map.list-mode.title"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForSourceFeatureCount(2, in: app))
        XCTAssertTrue(waitForTrackSegmentCount(1, in: app))
        XCTAssertFalse(app.staticTexts["map.track-connection-readout"].exists)
        attachScreenshot(named: "my-tracks-continuous-line")
    }

    func testListMapCameraFitsSpreadListMembers() {
        let app = launch(reset: true, pinDiagnostics: true, seedSpreadList: true, startupViewport: "kl-street")

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMapToFinishLoading(in: app))

        openAppMenu(in: app)
        app.buttons["menu.row.lists"].tap()
        XCTAssertTrue(app.staticTexts["Lists"].waitForExistence(timeout: 5))
        app.staticTexts["Spread walk"].tap()
        XCTAssertTrue(app.buttons["lists.detail.show-map"].waitForExistence(timeout: 5))
        app.buttons["lists.detail.show-map"].tap()

        XCTAssertTrue(app.staticTexts["map.list-mode.title"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForSourceFeatureCount(5, in: app))
        XCTAssertTrue(waitForProjectedFixturePinCount(5, in: app))
        for pin in app.staticTexts.matching(identifierPrefix: "map.fixture-pin.").allElementsBoundByIndex {
            XCTAssertEqual(pin.label, "hit")
            guard let value = pin.value as? String else {
                return XCTFail("missing normalized coordinates for \(pin.identifier)")
            }
            let normalized = normalizedPoint(from: value)
            XCTAssertGreaterThan(normalized.x, 0.04, pin.identifier)
            XCTAssertLessThan(normalized.x, 0.96, pin.identifier)
            XCTAssertGreaterThan(normalized.y, 0.08, pin.identifier)
            XCTAssertLessThan(normalized.y, 0.92, pin.identifier)
        }
        attachScreenshot(named: "list-map-spread-fit")
    }

    func testHiddenToastAutoDismissesWithoutUnhidingPlace() {
        let app = launch(reset: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))

        openFixtureCard(in: map, app: app)
        app.buttons["place-card.hide"].tap()
        XCTAssertTrue(app.staticTexts["Hidden — Undo"].waitForExistence(timeout: 5))

        XCTAssertTrue(waitForNonExistence(of: app.staticTexts["Hidden — Undo"], timeout: 7))
        tapFixturePin(in: map)
        XCTAssertFalse(app.staticTexts["Ghost Sign"].waitForExistence(timeout: 2))
    }

    func testHiddenToastUndoRestoresHiddenPlace() {
        let app = launch(reset: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))

        openFixtureCard(in: map, app: app)
        app.buttons["place-card.hide"].tap()
        XCTAssertTrue(app.staticTexts["Hidden — Undo"].waitForExistence(timeout: 5))

        app.buttons["place-card.hide.undo"].tap()
        XCTAssertFalse(app.staticTexts["Hidden — Undo"].waitForExistence(timeout: 2))

        openFixtureCard(in: map, app: app)
    }

    func testHideRemovesFixturePinFromMapSource() {
        let app = launch(reset: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))

        openFixtureCard(in: map, app: app)
        app.buttons["place-card.close"].tap()
        app.buttons["debug.hide-fixture"].tap()
        XCTAssertTrue(waitForFixtureHidden(true, in: app))

        tapFixturePin(in: map)
        XCTAssertFalse(app.staticTexts["Ghost Sign"].waitForExistence(timeout: 2))

        openSecondFixtureCard(in: map, app: app)
    }

    func testUnhideRestoresFixturePinToMapSourceBeforeCardDismissal() {
        let app = launch(reset: true, pinDiagnostics: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMapToFinishLoading(in: app))

        app.buttons["debug.hide-fixture"].tap()
        XCTAssertTrue(waitForFixtureHidden(true, in: app))
        XCTAssertTrue(waitForSourceFeatureCount(1, in: app))
        XCTAssertTrue(waitForNonExistence(of: app.staticTexts["map.fixture-pin.\(placeID)"], timeout: 5))

        app.buttons["debug.unhide-fixture"].tap()
        XCTAssertTrue(waitForFixtureHidden(false, in: app))
        XCTAssertTrue(waitForSourceFeatureCount(2, in: app))
        openFixtureCard(in: map, app: app)
    }

    func testLayersCanHideCategoryPins() {
        let app = launch(reset: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))

        openLayers(in: app)
        let historicBuildings = app.switches["map.layers.category.historic_building"]
        XCTAssertTrue(historicBuildings.waitForExistence(timeout: 5))
        tapSwitch(historicBuildings, expectedValue: "0")
        app.buttons["map.layers.done"].tap()

        XCTAssertTrue(waitForNonExistence(
            of: app.buttons["map.pin.mt1_00000000000000000000000001"],
            timeout: 5
        ))
        tapSecondFixturePin(in: map)
        XCTAssertFalse(app.staticTexts["Art Deco Cinema"].waitForExistence(timeout: 2))

        openLayers(in: app)
        XCTAssertTrue(historicBuildings.waitForExistence(timeout: 5))
        tapSwitch(historicBuildings, expectedValue: "1")
        app.buttons["map.layers.done"].tap()
        XCTAssertTrue(waitForAccessibilityPin(
            in: app,
            placeID: "mt1_00000000000000000000000001",
            label: "Art Deco Cinema, Historic Building, not visited"
        ))

        openSecondFixtureCard(in: map, app: app)
        app.buttons["place-card.close"].tap()

        openFixtureCard(in: map, app: app)
    }

    func testLayersToggleAllCategoriesHidesAndRestoresPins() {
        let app = launch(reset: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))

        openLayers(in: app)
        let toggleAll = app.buttons["map.layers.show-all-categories"]
        XCTAssertTrue(scrollToHittable(toggleAll, in: app))
        XCTAssertEqual(toggleAll.label, "Hide all categories")
        toggleAll.tap()
        XCTAssertEqual(toggleAll.label, "Show all categories")
        app.buttons["map.layers.done"].tap()

        tapFixturePin(in: map)
        XCTAssertFalse(app.staticTexts["Ghost Sign"].waitForExistence(timeout: 2))
        tapSecondFixturePin(in: map)
        XCTAssertFalse(app.staticTexts["Art Deco Cinema"].waitForExistence(timeout: 2))

        openLayers(in: app)
        XCTAssertTrue(scrollToHittable(toggleAll, in: app))
        XCTAssertEqual(toggleAll.label, "Show all categories")
        toggleAll.tap()
        XCTAssertEqual(toggleAll.label, "Hide all categories")
        app.buttons["map.layers.done"].tap()

        openFixtureCard(in: map, app: app)
        app.buttons["place-card.close"].tap()
        openSecondFixtureCard(in: map, app: app)
    }

    func testShowHiddenModeExposesUnhideAffordanceWithoutNormalHideOwnership() {
        let app = launch(reset: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))

        app.buttons["debug.hide-fixture"].tap()
        XCTAssertTrue(waitForFixtureHidden(true, in: app))
        tapFixturePin(in: map)
        XCTAssertFalse(app.staticTexts["Ghost Sign"].waitForExistence(timeout: 2))

        openLayers(in: app)
        let showHidden = app.switches["map.layers.show-hidden"]
        XCTAssertTrue(showHidden.waitForExistence(timeout: 5))
        tapSwitch(showHidden, expectedValue: "1")
        app.buttons["map.layers.done"].tap()

        openFixtureCard(in: map, app: app)
        XCTAssertTrue(app.buttons["place-card.unhide"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["place-card.hide"].exists)

        app.buttons["place-card.unhide"].tap()
        XCTAssertFalse(app.buttons["place-card.unhide"].waitForExistence(timeout: 2))
        app.buttons["place-card.close"].tap()
        openFixtureCard(in: map, app: app)
    }

    func testMenuAboutCarriesCreditsAndMapAttributionIsInert() throws {
        let app = launch(reset: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))

        XCTAssertFalse(app.buttons["map.openstreetmap-attribution"].exists)
        XCTAssertTrue(app.staticTexts["map.openstreetmap-attribution"].waitForExistence(timeout: 5))

        openAppMenu(in: app)
        XCTAssertTrue(app.staticTexts["Menu"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["menu.row.lists"].exists)
        XCTAssertTrue(app.buttons["menu.row.offline-maps"].exists)
        XCTAssertTrue(app.buttons["menu.row.settings"].exists)

        app.buttons["menu.row.about"].tap()
        XCTAssertTrue(app.staticTexts["About"].waitForExistence(timeout: 5))
        let versionLabel = app.staticTexts["about.app-version"]
        XCTAssertTrue(versionLabel.waitForExistence(timeout: 5))
        XCTAssertEqual(versionLabel.label, try expectedAppVersionLabel())
        let expectedBuildLabel = "Build \(try currentGitCommit())"
        XCTAssertTrue(app.staticTexts[expectedBuildLabel].waitForExistence(timeout: 5))
        let privacyPolicy = app.buttons["about.privacy-policy"]
        XCTAssertTrue(privacyPolicy.waitForExistence(timeout: 5))
        XCTAssertEqual(privacyPolicy.label, "Privacy policy")
        XCTAssertEqual(privacyPolicy.value as? String, "https://making-tracks.app/privacy")
        XCTAssertTrue(app.staticTexts["Open source acknowledgements"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["about.openstreetmap-copyright"].waitForExistence(timeout: 5))
        app.buttons["menu.done"].tap()
    }

    func testOfflineProgressChipDeepLinksToOfflineMaps() {
        let activeDownloadApp = launch(reset: true, offlineProgress: 0.42)
        let activeMap = activeDownloadApp.otherElements["map.surface"]
        XCTAssertTrue(activeMap.waitForExistence(timeout: 10))

        let progressChip = activeDownloadApp.buttons["map.download-progress"]
        XCTAssertTrue(progressChip.waitForExistence(timeout: 5))
        XCTAssertTrue(progressChip.label.contains("42%"))
        progressChip.tap()

        XCTAssertTrue(activeDownloadApp.staticTexts["Offline maps"].waitForExistence(timeout: 5))
        activeDownloadApp.buttons["menu.done"].tap()

        XCTAssertTrue(activeMap.waitForExistence(timeout: 5))
        openAppMenu(in: activeDownloadApp)
        XCTAssertTrue(activeDownloadApp.staticTexts["Menu"].waitForExistence(timeout: 5))
        XCTAssertTrue(activeDownloadApp.buttons["menu.row.lists"].exists)
        XCTAssertTrue(activeDownloadApp.buttons["menu.row.settings"].exists)
        activeDownloadApp.buttons["menu.done"].tap()
    }

    func testSettingsThemePickerSelectsRealTheme() {
        let app = launch(reset: true, resetTheme: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))

        openAppMenu(in: app)
        app.buttons["menu.row.settings"].tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["settings.theme.selected"].exists)
        XCTAssertTrue(app.buttons["settings.theme.defined-paper"].exists)
        XCTAssertEqual(app.buttons["settings.theme.defined-paper"].value as? String, "Selected")
        XCTAssertEqual(app.buttons["settings.theme.snow"].value as? String, "Not selected")

        let snowThemeButton = app.buttons["settings.theme.snow"]
        snowThemeButton.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertEqual(snowThemeButton.value as? String, "Selected")
        XCTAssertEqual(app.buttons["settings.theme.defined-paper"].value as? String, "Not selected")
        app.buttons["menu.done"].tap()
    }

    func testSettingsStorageRowNavigatesToOfflineMaps() {
        let app = launch(reset: true)

        XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 10))

        openAppMenu(in: app)
        app.buttons["menu.row.settings"].tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
        let storageRow = app.buttons["settings.storage.manage"]
        XCTAssertTrue(scrollToHittable(storageRow, in: app))
        storageRow.tap()

        XCTAssertTrue(app.staticTexts["Offline maps"].waitForExistence(timeout: 5))
    }

    func testMapHomeChromeHitTargetsAndThemeScreenshots() {
        let app = launch(reset: true, resetTheme: true, forceDarkAppearance: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMapTheme("defined-paper", in: app))

        let menuButton = app.buttons["map.menu"]
        let layersButton = app.buttons["map.layers"]
        XCTAssertTrue(menuButton.waitForExistence(timeout: 5))
        XCTAssertTrue(layersButton.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(menuButton.frame.width, 44)
        XCTAssertGreaterThanOrEqual(menuButton.frame.height, 44)
        XCTAssertGreaterThanOrEqual(layersButton.frame.width, 44)
        XCTAssertGreaterThanOrEqual(layersButton.frame.height, 44)
        XCTAssertGreaterThan(menuButton.frame.minY, 50)
        XCTAssertLessThan(menuButton.frame.minY, 120)
        XCTAssertLessThan(layersButton.frame.minY, 180)
        XCTAssertGreaterThan(layersButton.frame.minY, menuButton.frame.maxY)
        attachScreenshot(named: "map-home-chrome-defined-paper")

        for themeID in ["snow", "street-contrast", "verdant-kl"] {
            selectMapTheme(themeID, in: app)
            attachScreenshot(named: "map-home-chrome-\(themeID)")
        }

        openLayers(in: app)
        let historicBuildings = app.switches["map.layers.category.historic_building"]
        XCTAssertTrue(historicBuildings.waitForExistence(timeout: 5))
        tapSwitch(historicBuildings, expectedValue: "0")
        app.buttons["map.layers.done"].tap()
        XCTAssertEqual(layersButton.value as? String, "Custom")

        selectMapTheme("snow", in: app)

        XCTAssertTrue(map.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForMapTheme("snow", in: app))
        attachScreenshot(named: "map-home-chrome-snow-filtered")
    }

    func testCoverageShadingToggleIsDisplayOnlyLayerState() {
        let app = launch(reset: true, coverageBBoxes: ["101.640,3.090,101.690,3.190"])

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        let layersButton = app.buttons["map.layers"]
        XCTAssertTrue(layersButton.waitForExistence(timeout: 5))
        XCTAssertEqual(layersButton.value as? String, "Default")

        openLayers(in: app)
        let coverageShading = app.switches["map.layers.coverage-shading"]
        XCTAssertTrue(coverageShading.waitForExistence(timeout: 5))
        tapSwitch(coverageShading, expectedValue: "0")
        app.buttons["map.layers.done"].tap()

        XCTAssertEqual(layersButton.value as? String, "Default")

        openLayers(in: app)
        XCTAssertTrue(coverageShading.waitForExistence(timeout: 5))
        tapSwitch(coverageShading, expectedValue: "1")
        app.buttons["map.layers.done"].tap()
        XCTAssertEqual(layersButton.value as? String, "Default")
    }

    func testPinSizeScreenshotsAcrossThemes() {
        let cases: [(theme: String, size: Double, screenshotName: String)] = [
            ("defined-paper", 0.8, "pin-defined-paper-min"),
            ("defined-paper", 1.2, "pin-defined-paper-default"),
            ("defined-paper", 1.6, "pin-defined-paper-max"),
            ("snow", 0.8, "pin-snow-min"),
            ("snow", 1.2, "pin-snow-default"),
            ("snow", 1.6, "pin-snow-max"),
        ]

        for testCase in cases {
            let app = launch(
                reset: true,
                resetTheme: true,
                theme: testCase.theme,
                pinSizeMultiplier: testCase.size,
                pinDiagnostics: true
            )
            XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 10), testCase.screenshotName)
            XCTAssertTrue(waitForMapToFinishLoading(in: app), testCase.screenshotName)
            XCTAssertFalse(app.otherElements["map.unavailable"].exists, testCase.screenshotName)
            XCTAssertTrue(waitForSourceFeatureCount(2, in: app), testCase.screenshotName)
            XCTAssertEqual(app.staticTexts["map.fixture-pin.\(placeID)"].label, "hit", testCase.screenshotName)
            XCTAssertEqual(app.staticTexts["map.debug-theme"].label, "theme:\(testCase.theme)", testCase.screenshotName)
            XCTAssertEqual(app.staticTexts["map.debug-pin-size"].label, "pin-size:\(pinSizeAccessibilityValue(for: testCase.size))", testCase.screenshotName)
            attachScreenshot(named: testCase.screenshotName)
            app.terminate()
        }
    }

    func testPinThinningScreenshotsCompareCityAndStreetZoomDensity() {
        let cityApp = launch(reset: true, pinDiagnostics: true, densePins: true, startupViewport: "kl")
        XCTAssertTrue(cityApp.otherElements["map.surface"].waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMapToFinishLoading(in: cityApp))
        XCTAssertTrue(waitForSourceFeatureCount(10, in: cityApp))
        XCTAssertTrue(waitForProjectedFixturePinCount(10, in: cityApp))
        attachScreenshot(named: "pin-thinning-city")
        cityApp.terminate()

        let streetApp = launch(reset: true, pinDiagnostics: true, densePins: true, startupViewport: "kl-street")
        XCTAssertTrue(streetApp.otherElements["map.surface"].waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMapToFinishLoading(in: streetApp))
        XCTAssertTrue(waitForSourceFeatureCount(24, in: streetApp))
        XCTAssertTrue(waitForProjectedFixturePinCount(24, in: streetApp))
        attachScreenshot(named: "pin-thinning-street")
        streetApp.terminate()
    }

    func testCoverageEdgeScreenshotsAcrossThemes() {
        let coverageBBox = "101.640,3.090,101.690,3.190"
        let diagnosticApp = launch(
            reset: true,
            resetTheme: true,
            theme: "defined-paper",
            pinDiagnostics: true,
            coverageBBoxes: [coverageBBox]
        )
        XCTAssertTrue(diagnosticApp.otherElements["map.surface"].waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMapToFinishLoading(in: diagnosticApp))
        XCTAssertEqual(diagnosticApp.staticTexts["map.debug-coverage"].label, "coverage-bboxes:1")
        diagnosticApp.terminate()

        for themeID in ["defined-paper", "snow", "street-contrast", "verdant-kl"] {
            let app = launch(
                reset: true,
                resetTheme: true,
                theme: themeID,
                coverageBBoxes: [coverageBBox]
            )
            XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 10), themeID)
            XCTAssertTrue(waitForMapTheme(themeID, in: app), themeID)
            attachScreenshot(named: "coverage-edge-\(themeID)")
            app.terminate()
        }
    }

    func testPinSizeSliderUpdatesLiveMapLayers() {
        let app = launch(
            reset: true,
            pinSizeMultiplier: 0.8,
            pinDiagnostics: true
        )
        XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMapToFinishLoading(in: app))
        XCTAssertTrue(waitForSourceFeatureCount(2, in: app))

        XCTAssertEqual(
            app.staticTexts["map.debug-pin-layer-size"].label,
            "pin-layer-size:80% circle:true icon:true bookmark:true heart:true"
        )

        openAppMenu(in: app)
        app.buttons["menu.row.settings"].tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
        let slider = app.sliders["settings.pin-size"]
        XCTAssertTrue(scrollToHittable(slider, in: app))
        slider.adjust(toNormalizedSliderPosition: 1.0)
        app.buttons["menu.done"].tap()

        let liveLayerSize = app.staticTexts["map.debug-pin-layer-size"]
        XCTAssertTrue(liveLayerSize.waitForExistence(timeout: 5))
        XCTAssertEqual(
            liveLayerSize.label,
            "pin-layer-size:160% circle:true icon:true bookmark:true heart:true"
        )
    }

    func testPlaceCardKeepsFixedActionSlotsReachableAtAccessibilityTextSize() {
        let app = launch(reset: true, accessibilityTextSize: true, pinDiagnostics: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMapToFinishLoading(in: app))

        let openFixture = app.buttons["debug.open-fixture"]
        XCTAssertTrue(openFixture.waitForExistence(timeout: 5))
        openFixture.tap()
        XCTAssertTrue(app.staticTexts["Ghost Sign"].waitForExistence(timeout: 5))

        let actionBar = app.otherElements["place-card.action-bar"]
        XCTAssertTrue(actionBar.waitForExistence(timeout: 5))
        let saveButton = actionBar.buttons["place-card.save"]
        let visitedButton = actionBar.buttons["place-card.visited"]
        let hideButton = actionBar.buttons["place-card.hide"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        XCTAssertTrue(visitedButton.waitForExistence(timeout: 5))
        XCTAssertTrue(hideButton.waitForExistence(timeout: 5))
        XCTAssertEqual(actionBar.buttons.count, 3)
        attachScreenshot(named: "place-card-a11y")
        XCTAssertGreaterThan(visitedButton.frame.minY, saveButton.frame.minY)
        XCTAssertGreaterThan(hideButton.frame.minY, visitedButton.frame.minY)

        visitedButton.tap()
        let lovedButton = actionBar.buttons["place-card.loved"]
        let unseeButton = actionBar.buttons["place-card.unsee"]
        XCTAssertTrue(lovedButton.waitForExistence(timeout: 5))
        XCTAssertTrue(unseeButton.waitForExistence(timeout: 5))
        XCTAssertEqual(actionBar.buttons.count, 3)
        XCTAssertEqual(lovedButton.label, "Love")
        XCTAssertEqual(unseeButton.label, "Un-see")
        XCTAssertTrue(unseeButton.isEnabled)

        lovedButton.tap()
        XCTAssertTrue(lovedButton.waitForExistence(timeout: 5))
        XCTAssertTrue(unseeButton.waitForExistence(timeout: 5))
        XCTAssertEqual(actionBar.buttons.count, 3)
        XCTAssertEqual(lovedButton.label, "Unlove")
        XCTAssertFalse(unseeButton.isEnabled)
        XCTAssertFalse(actionBar.buttons["place-card.hide"].exists)
    }

    func testLocateMeChromeExplainsWhenLocationIsDenied() throws {
        let app = launch(reset: true, locationDenied: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))

        XCTAssertEqual(app.buttons["map.locate-me"].label, "Locate me")
        XCTAssertTrue(app.staticTexts["Location is off"].waitForExistence(timeout: 5))
        let locationSettings = app.buttons["map.location-settings"]
        if !locationSettings.waitForExistence(timeout: 5) {
            XCTAssertTrue(app.otherElements["map.location-settings"].waitForExistence(timeout: 5))
        }
        attachScreenshot(named: "map-location-off")
    }

    func testLocateMeShowsNearbyPromptForFixturePlace() {
        let app = launch(
            reset: true,
            simulatedLocationAuthorization: true,
            simulatedLatitude: 3.1402,
            simulatedLongitude: 101.6902
        )

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))

        app.buttons["map.locate-me"].tap()

        let nearbyPrompt = app.otherElements["map.nearby-prompt"]
        XCTAssertTrue(nearbyPrompt.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["You're near Ghost Sign — seen it?"].waitForExistence(timeout: 5))
        attachScreenshot(named: "nearby-prompt")

        let seenButton = app.buttons["map.nearby-prompt.seen"]
        XCTAssertTrue(seenButton.waitForExistence(timeout: 5))
        seenButton.tap()

        XCTAssertFalse(nearbyPrompt.waitForExistence(timeout: 2))
        XCTAssertEqual(app.staticTexts["tracks.visit-count.\(placeID)"].label, "Tracks visits: 1")
    }

    func testCardVisitStateSuppressesNearbyPromptWithoutViewportRefresh() {
        let app = launch(
            reset: true,
            simulatedLocationAuthorization: true,
            simulatedLatitude: 3.1402,
            simulatedLongitude: 101.6902,
            pinDiagnostics: true
        )

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMapToFinishLoading(in: app))

        app.buttons["map.locate-me"].tap()

        let nearbyPrompt = app.otherElements["map.nearby-prompt"]
        XCTAssertTrue(nearbyPrompt.waitForExistence(timeout: 5))

        XCTAssertTrue(activateFixturePin(
            in: map,
            app: app,
            placeID: placeID,
            title: "Ghost Sign",
            expectedLabel: "Ghost Sign, Attraction, not visited"
        ))
        XCTAssertTrue(app.staticTexts["Ghost Sign"].waitForExistence(timeout: 5))
        app.buttons["place-card.visited"].tap()
        app.buttons["place-card.close"].tap()

        XCTAssertFalse(nearbyPrompt.waitForExistence(timeout: 2))
        XCTAssertEqual(app.staticTexts["tracks.visit-count.\(placeID)"].label, "Tracks visits: 1")
    }

    func testLocateMePromptsForNearbyTierHiddenByCityZoomThinning() {
        let app = launch(
            reset: true,
            simulatedLocationAuthorization: true,
            simulatedLatitude: 3.1400,
            simulatedLongitude: 101.6980,
            pinDiagnostics: true,
            densePins: true,
            startupViewport: "kl"
        )

        XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMapToFinishLoading(in: app))
        XCTAssertTrue(waitForSourceFeatureCount(10, in: app))
        XCTAssertFalse(app.staticTexts["map.fixture-pin.mt1_D000000000000000000000000H"].exists)

        app.buttons["map.locate-me"].tap()

        let nearbyPrompt = app.otherElements["map.nearby-prompt"]
        XCTAssertTrue(nearbyPrompt.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["You're near Dense Pin 17 — seen it?"].waitForExistence(timeout: 5))

        let seenButton = app.buttons["map.nearby-prompt.seen"]
        XCTAssertTrue(seenButton.waitForExistence(timeout: 5))
        seenButton.tap()

        XCTAssertFalse(nearbyPrompt.waitForExistence(timeout: 2))
    }

    func testCreditsStayGroupedAtAccessibilityTextSize() throws {
        let app = launch(reset: true, accessibilityTextSize: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))

        openAppMenu(in: app)
        app.buttons["menu.row.about"].tap()
        XCTAssertTrue(app.staticTexts["About"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Build"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Open source acknowledgements"].waitForExistence(timeout: 5))
        XCTAssertEqual(try buildCommitLabel(in: app), "Build \(try currentGitCommit())")
        let grdbCredit = element(identifier: "credits.oss.GRDB.swift|7.11.1", in: app)
        XCTAssertTrue(scrollToExistence(of: grdbCredit, in: app))

        let mapLibreCredit = element(
            identifier: "credits.oss.MapLibre Native iOS / maplibre-gl-native-distribution|6.27.0",
            in: app
        )
        XCTAssertTrue(scrollToExistence(of: mapLibreCredit, in: app))
        let mapLibreLicense = element(
            identifier: "credits.oss.MapLibre Native iOS / maplibre-gl-native-distribution|6.27.0.license",
            in: app
        )
        XCTAssertTrue(scrollToExistence(of: mapLibreLicense, in: app))
        XCTAssertEqual(mapLibreLicense.elementType, .button)
        XCTAssertTrue(mapLibreLicense.isEnabled)
        attachScreenshot(named: "credits-a11y")
    }

    private func launch(
        reset: Bool,
        locationNotDetermined: Bool = false,
        locationDenied: Bool = false,
        simulatedLocationAuthorization: Bool = false,
        simulatedLatitude: Double? = nil,
        simulatedLongitude: Double? = nil,
        accessibilityTextSize: Bool = false,
        seedUserList: Bool = false,
        offlineProgress: Double? = nil,
        resetTheme: Bool = false,
        theme: String? = nil,
        pinSizeMultiplier: Double? = nil,
        pinDiagnostics: Bool = false,
        seedTrackVisits: Bool = false,
        seedBurstTrackVisits: Bool = false,
        seedSpreadList: Bool = false,
        seedTrackList: Bool = false,
        seedMultiDayTrackList: Bool = false,
        coverageBBoxes: [String] = [],
        resetOnboarding: Bool = false,
        forceDarkAppearance: Bool = false,
        densePins: Bool = false,
        startupViewport: String? = nil,
        trackReplayBeatDuration: Double? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-fixture-map"]
        app.launchArguments.append("--ui-testing-reset-pin-size")
        app.launchArguments.append("--ui-testing-reset-coverage-shading")
        if densePins {
            app.launchArguments.append("--ui-testing-dense-pins")
        }
        if let startupViewport {
            app.launchArguments.append("--ui-testing-map-state")
            app.launchArguments.append(startupViewport)
        }
        if let trackReplayBeatDuration {
            app.launchArguments.append("--ui-testing-track-replay-beat-duration")
            app.launchArguments.append(String(trackReplayBeatDuration))
        }
        if pinDiagnostics {
            app.launchArguments.append("--ui-testing-pin-diagnostics")
        }
        if reset {
            app.launchArguments.append("--ui-testing-reset-database")
        }
        if locationNotDetermined {
            app.launchArguments.append("--ui-testing-location-not-determined")
        }
        if locationDenied {
            app.launchArguments.append("--ui-testing-location-denied")
        }
        if simulatedLocationAuthorization {
            app.launchArguments.append("--ui-testing-location-authorized")
        }
        if let simulatedLatitude {
            app.launchArguments.append("--ui-testing-location-latitude")
            app.launchArguments.append(String(simulatedLatitude))
        }
        if let simulatedLongitude {
            app.launchArguments.append("--ui-testing-location-longitude")
            app.launchArguments.append(String(simulatedLongitude))
        }
        if accessibilityTextSize {
            app.launchArguments.append("-UIPreferredContentSizeCategoryName")
            app.launchArguments.append("UICTContentSizeCategoryAccessibilityXXXL")
        }
        if forceDarkAppearance {
            app.launchArguments.append("-AppleInterfaceStyle")
            app.launchArguments.append("Dark")
        }
        if seedUserList {
            app.launchArguments.append("--ui-testing-seed-user-list")
        }
        if seedTrackVisits {
            app.launchArguments.append("--ui-testing-seed-track-visits")
        }
        if seedBurstTrackVisits {
            app.launchArguments.append("--ui-testing-seed-burst-track-visits")
        }
        if seedSpreadList {
            app.launchArguments.append("--ui-testing-seed-spread-list")
        }
        if seedTrackList {
            app.launchArguments.append("--ui-testing-seed-track-list")
        }
        if seedMultiDayTrackList {
            app.launchArguments.append("--ui-testing-seed-multiday-track-list")
        }
        if let offlineProgress {
            app.launchArguments.append("--ui-testing-offline-progress")
            app.launchArguments.append(String(offlineProgress))
        }
        if resetTheme {
            app.launchArguments.append("--ui-testing-reset-theme")
        }
        if let theme {
            app.launchArguments.append("--ui-testing-theme")
            app.launchArguments.append(theme)
        }
        if let pinSizeMultiplier {
            app.launchArguments.append("--ui-testing-pin-size-multiplier")
            app.launchArguments.append(String(pinSizeMultiplier))
        }
        for bbox in coverageBBoxes {
            app.launchArguments.append("--ui-testing-coverage-bbox")
            app.launchArguments.append(bbox)
        }
        if resetOnboarding {
            app.launchArguments.append("--ui-testing-reset-onboarding")
            app.launchArguments.append("-hasCompletedOnboarding")
            app.launchArguments.append("NO")
        } else {
            app.launchArguments.append("--ui-testing-complete-onboarding")
        }
        app.launch()
        return app
    }

    private func selectMapTheme(_ themeID: String, in app: XCUIApplication) {
        openAppMenu(in: app)
        app.buttons["menu.row.settings"].tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
        let themeButton = app.buttons["settings.theme.\(themeID)"]
        XCTAssertTrue(themeButton.waitForExistence(timeout: 5))
        themeButton.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertEqual(themeButton.value as? String, "Selected")
        app.buttons["menu.done"].tap()
        XCTAssertTrue(waitForNonExistence(of: app.staticTexts["Settings"], timeout: 5))
        XCTAssertTrue(waitForMapTheme(themeID, in: app))
    }

    private func waitForMapTheme(_ themeID: String, in app: XCUIApplication) -> Bool {
        let loadedTheme = app.staticTexts["map.loaded-theme"]
        let predicate = NSPredicate(format: "exists == true AND label == %@", "Loaded theme: \(themeID)")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: loadedTheme)
        let result = XCTWaiter.wait(for: [expectation], timeout: 10)
        if result != .completed {
            XCTFail("Expected loaded theme \(themeID), got \(loadedTheme.exists ? loadedTheme.label : "missing loaded theme")")
            return false
        }
        let loading = app.otherElements["map.loading"]
        return !loading.exists || loading.waitForNonExistence(timeout: 10)
    }

    private func completeOnboardingSelectingUK(in app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["Interesting places around you"].waitForExistence(timeout: 5))
        app.buttons["onboarding.next"].tap()
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.buttons["onboarding.region.uk"].waitForExistence(timeout: 5))
        app.buttons["onboarding.region.uk"].tap()
        app.buttons["onboarding.next"].tap()
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.buttons["onboarding.location.skip"].waitForExistence(timeout: 5))
        app.buttons["onboarding.location.skip"].tap()
        XCTAssertTrue(app.buttons["onboarding.finish"].waitForExistence(timeout: 5))
        app.buttons["onboarding.finish"].tap()
        XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 10))
    }

    private func openAppMenu(in app: XCUIApplication) {
        let menuButton = app.buttons["map.menu"]
        XCTAssertTrue(menuButton.waitForExistence(timeout: 5))
        XCTAssertEqual(menuButton.label, "Menu")
        menuButton.tap()
    }

    private func tapFixturePin(in map: XCUIElement) {
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    @discardableResult
    private func activateFixturePin(
        in map: XCUIElement,
        app: XCUIApplication,
        placeID: String,
        title: String,
        expectedLabel: String
    ) -> Bool {
        let marker = app.staticTexts["map.fixture-pin.\(placeID)"]
        guard marker.waitForExistence(timeout: 10),
              waitForFixturePinToBecomeHitTestable(marker)
        else {
            XCTFail("Rendered fixture pin \(placeID) did not become hit-testable")
            return false
        }
        guard waitForAccessibilityPin(in: app, placeID: placeID, label: expectedLabel) else { return false }
        let pin = app.buttons["map.pin.\(placeID)"]
        guard let projectedPoint = projectedScreenPoint(from: marker, through: map, in: app) else {
            XCTFail(
                "Could not resolve projected point for \(placeID); map frame \(map.frame); app frame \(app.frame); marker value \(marker.value ?? "nil")"
            )
            return false
        }
        XCTAssertTrue(
            pin.frame.insetBy(dx: -2, dy: -2).contains(projectedPoint),
            "Accessibility pin \(placeID) frame \(pin.frame) did not contain projected point \(projectedPoint); map frame \(map.frame); marker value \(marker.value ?? "nil")"
        )
        guard tapProjectedFixtureMarker(marker, through: map, in: app) else { return false }
        waitForTapStatusToChange(in: app)
        if app.staticTexts[title].waitForExistence(timeout: 5) {
            return true
        }
        let tapStatus = app.staticTexts["map.debug-tap-status"]
        let tap = tapStatus.exists ? tapStatus.label : "tap-status-missing"
        XCTFail("Activating accessibility pin \(placeID) did not open \(title); \(tap)")
        return false
    }

    @discardableResult
    private func waitForAccessibilityPin(in app: XCUIApplication, placeID: String, label: String) -> Bool {
        let pin = app.buttons["map.pin.\(placeID)"]
        guard pin.waitForExistence(timeout: 10) else {
            XCTFail("Accessibility pin \(placeID) did not appear")
            return false
        }
        let predicate = NSPredicate(format: "label == %@", label)
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: pin)], timeout: 5)
        if result == .completed {
            return true
        }
        XCTFail("Accessibility pin \(placeID) label was \(pin.label), expected \(label)")
        return false
    }

    @discardableResult
    private func tapProjectedFixturePin(
        in map: XCUIElement,
        app: XCUIApplication,
        placeID: String,
        title: String,
    ) -> Bool {
        let marker = app.staticTexts["map.fixture-pin.\(placeID)"]
        guard marker.waitForExistence(timeout: 10),
              waitForFixturePinToBecomeHitTestable(marker),
              tapProjectedFixtureMarker(marker, through: map, in: app)
        else { return false }
        waitForTapStatusToChange(in: app)
        if app.staticTexts[title].waitForExistence(timeout: 2) {
            return true
        }
        let tapStatus = app.staticTexts["map.debug-tap-status"]
        let tap = tapStatus.exists ? tapStatus.label : "tap-status-missing"
        XCTFail("Projected tap did not open \(title); \(tap)")
        return false
    }

    private func openFixtureCard(in map: XCUIElement, app: XCUIApplication) {
        openCard(named: "Ghost Sign", in: map, app: app, tap: tapFixturePin)
    }

    private func openSecondFixtureCard(in map: XCUIElement, app: XCUIApplication) {
        openCard(named: "Art Deco Cinema", in: map, app: app, tap: tapSecondFixturePin)
    }

    private func openCard(
        named name: String,
        in map: XCUIElement,
        app: XCUIApplication,
        tap: (XCUIElement) -> Void
    ) {
        let title = app.staticTexts[name]
        for _ in 0..<5 {
            tap(map)
            if title.waitForExistence(timeout: 1) {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTAssertTrue(title.waitForExistence(timeout: 1))
    }

    private func tapSecondFixturePin(in map: XCUIElement) {
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.67, dy: 0.37)).tap()
    }

    private func waitForFixturePinToBecomeHitTestable(_ marker: XCUIElement) -> Bool {
        let predicate = NSPredicate(format: "label == %@", "hit")
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: marker)], timeout: 10) == .completed
    }

    @discardableResult
    private func waitForTapStatusToChange(in app: XCUIApplication) -> Bool {
        let tapStatus = app.staticTexts["map.debug-tap-status"]
        guard tapStatus.waitForExistence(timeout: 2) else { return false }
        let predicate = NSPredicate(format: "label != %@", "not-tapped")
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: tapStatus)], timeout: 3) == .completed
    }

    private func expandPlaceCardSheet(in app: XCUIApplication) -> Bool {
        let sheet = app.scrollViews.matching(identifierPrefix: "place-card.instance.").firstMatch
        guard sheet.waitForExistence(timeout: 5) else { return false }
        let initialHeight = sheet.frame.height
        let appHeight = app.frame.height
        guard appHeight > 0, initialHeight < appHeight * 0.85 else { return false }

        sheet.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08))
            .press(
                forDuration: 0.1,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
            )

        let targetHeight = min(initialHeight + 80, appHeight * 0.85)
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if sheet.frame.height > targetHeight {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return false
    }

    private func tapProjectedFixtureMarker(_ marker: XCUIElement, through map: XCUIElement, in app: XCUIApplication) -> Bool {
        guard let point = projectedScreenPoint(from: marker, through: map, in: app) else { return false }
        let appFrame = app.frame
        guard appFrame.width > 0, appFrame.height > 0 else { return false }
        app.coordinate(withNormalizedOffset: CGVector(
            dx: (point.x - appFrame.minX) / appFrame.width,
            dy: (point.y - appFrame.minY) / appFrame.height
        )).tap()
        return true
    }

    private func projectedScreenPoint(from marker: XCUIElement, through map: XCUIElement, in app: XCUIApplication) -> CGPoint? {
        guard let offset = projectedOffset(from: marker) else { return nil }
        let mapFrame = map.frame
        let appFrame = app.frame
        guard appFrame.width > 0, appFrame.height > 0 else { return nil }
        let referenceFrame = mapFrame.width.isFinite && mapFrame.height.isFinite && mapFrame.width > 0 && mapFrame.height > 0
            ? mapFrame
            : appFrame
        let point = CGPoint(
            x: referenceFrame.minX + (offset.dx * referenceFrame.width),
            y: referenceFrame.minY + (offset.dy * referenceFrame.height)
        )
        guard appFrame.contains(point) else { return nil }
        return point
    }

    private func projectedOffset(from marker: XCUIElement) -> CGVector? {
        guard let value = marker.value as? String else { return nil }
        let parts = value.split(separator: " ")
        guard parts.count == 2,
              let xPart = parts.first,
              let yPart = parts.last,
              xPart.hasPrefix("x:"),
              yPart.hasPrefix("y:"),
              let dx = Double(xPart.dropFirst(2)),
              let dy = Double(yPart.dropFirst(2)),
              (0...1).contains(dx),
              (0...1).contains(dy)
        else { return nil }
        return CGVector(dx: dx, dy: dy)
    }

    private func tapEmptyMap(in map: XCUIElement) {
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.20, dy: 0.30)).tap()
    }

    private func openLayers(in app: XCUIApplication) {
        let layers = app.buttons["map.layers"]
        XCTAssertTrue(layers.waitForExistence(timeout: 5))
        layers.tap()
        XCTAssertTrue(app.navigationBars["Layers"].waitForExistence(timeout: 5))
    }

    private func tapSwitch(_ switchElement: XCUIElement, expectedValue: String) {
        switchElement.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        expectation(for: NSPredicate(format: "value == %@", expectedValue), evaluatedWith: switchElement)
        waitForExpectations(timeout: 5)
    }

    @discardableResult
    private func waitForMapToFinishLoading(in app: XCUIApplication) -> Bool {
        let loading = app.otherElements["map.loading"]
        let readiness = app.staticTexts["map.debug-readiness"]
        let sourceStatus = app.staticTexts["map.debug-source-status"]
        let featuresApplied = app.staticTexts["map.features-applied"]
        guard readiness.waitForExistence(timeout: 10) else {
            XCTFail("map.debug-readiness did not appear")
            return false
        }
        guard featuresApplied.waitForExistence(timeout: 10) else {
            let source = sourceStatus.exists ? sourceStatus.label : "source-status-missing"
            XCTFail("map.features-applied did not appear; \(readiness.label); \(source)")
            return false
        }
        return !loading.exists || loading.waitForNonExistence(timeout: 10)
    }

    private func waitForSourceFeatureCount(_ count: Int, in app: XCUIApplication) -> Bool {
        let sourceStatus = app.staticTexts["map.debug-source-status"]
        let predicate = NSPredicate(format: "label == %@", "source applied features:\(count)")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: sourceStatus)
        let result = XCTWaiter.wait(for: [expectation], timeout: 10)
        if result != .completed {
            XCTFail("Expected source applied features:\(count), got \(sourceStatus.exists ? sourceStatus.label : "missing source status")")
            return false
        }
        return true
    }

    private func waitForTrackSegmentCount(_ count: Int, in app: XCUIApplication) -> Bool {
        let sourceStatus = app.staticTexts["map.debug-track-source-status"]
        let predicate = NSPredicate(format: "label == %@", "track source applied segments:\(count) layer:true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: sourceStatus)
        let result = XCTWaiter.wait(for: [expectation], timeout: 10)
        if result != .completed {
            XCTFail("Expected track source applied segments:\(count) layer:true, got \(sourceStatus.exists ? sourceStatus.label : "missing track source status")")
            return false
        }
        return true
    }

    private func assertNoFrameIntersection(
        _ first: XCUIElement,
        _ second: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(
            first.frame.intersects(second.frame),
            "\(first.identifier) frame \(first.frame) intersects \(second.identifier) frame \(second.frame)",
            file: file,
            line: line
        )
    }

    private func waitForProjectedFixturePinCount(_ count: Int, in app: XCUIApplication) -> Bool {
        let deadline = Date().addingTimeInterval(10)
        let pins = app.staticTexts.matching(identifierPrefix: "map.fixture-pin.")
        while Date() < deadline {
            if pins.count == count {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTFail("Expected \(count) projected fixture pins, got \(pins.count)")
        return false
    }

    private func normalizedPoint(from value: String) -> (x: Double, y: Double) {
        let parts = value.split(separator: " ")
        let values = Dictionary(uniqueKeysWithValues: parts.compactMap { part -> (String, Double)? in
            let pair = part.split(separator: ":")
            guard pair.count == 2, let value = Double(pair[1]) else { return nil }
            return (String(pair[0]), value)
        })
        return (values["x"] ?? -1, values["y"] ?? -1)
    }

    private func attachScreenshot(named name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        exportScreenshot(screenshot, named: name)
    }

    private func exportScreenshot(_ screenshot: XCUIScreenshot, named name: String) {
        guard ProcessInfo.processInfo.environment["MAKING_TRACKS_EXPORT_UI_TEST_SCREENSHOTS"] == "1" else { return }
        guard let exportName = screenshotExportNames[name] else {
            XCTFail("No screenshot export name configured for \(name)")
            return
        }
        let directory = URL(fileURLWithPath: "/private/tmp/making-tracks-artifacts", isDirectory: true)
        let fileURL = directory.appendingPathComponent(exportName).appendingPathExtension("png")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try screenshot.pngRepresentation.write(to: fileURL)
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let byteCount = attributes[.size] as? UInt64 ?? 0
            XCTAssertGreaterThan(byteCount, 0, "Exported screenshot should not be empty: \(fileURL.path)")
        } catch {
            XCTFail("Failed to export screenshot \(name): \(error)")
        }
    }

    @discardableResult
    private func scrollToExistence(of element: XCUIElement, in app: XCUIApplication) -> Bool {
        if element.waitForExistence(timeout: 2) {
            return true
        }

        for _ in 0..<5 {
            scrollTarget(in: app).swipeUp()
            if element.waitForExistence(timeout: 1) {
                return true
            }
        }

        return element.exists
    }

    @discardableResult
    private func scrollToHittable(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        if element.waitForExistence(timeout: 2), element.isHittable {
            return true
        }

        for _ in 0..<5 {
            scrollTarget(in: app).swipeUp()
            if element.waitForExistence(timeout: 1), element.isHittable {
                return true
            }
        }

        return element.exists && element.isHittable
    }

    private func scrollTarget(in app: XCUIApplication) -> XCUIElement {
        let scrollView = app.scrollViews.firstMatch
        if scrollView.exists {
            return scrollView
        }
        return app
    }

    private func pinSizeAccessibilityValue(for multiplier: Double) -> String {
        "\(Int((multiplier * 100).rounded()))%"
    }

    private func element(identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", identifier))
            .firstMatch
    }

    private func assertDoesNotExposeURL(
        _ element: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let value = element.value as? String ?? ""
        XCTAssertFalse(element.label.localizedCaseInsensitiveContains("http"), file: file, line: line)
        XCTAssertFalse(value.localizedCaseInsensitiveContains("http"), file: file, line: line)
    }

    private func waitForNonExistence(of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForFixtureHidden(_ hidden: Bool, in app: XCUIApplication) -> Bool {
        let element = app.staticTexts["debug.fixture-hidden-state"]
        let predicate = NSPredicate(format: "exists == true AND label == %@", "Fixture hidden: \(hidden)")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }

    private func assertVerticallyOrdered(
        _ orderedElements: [(name: String, element: XCUIElement)],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for (previous, current) in zip(orderedElements, orderedElements.dropFirst()) {
            XCTAssertLessThan(
                previous.element.frame.minY,
                current.element.frame.minY,
                "\(previous.name) should appear above \(current.name)",
                file: file,
                line: line
            )
        }
    }

    private func buildCommitLabel(in app: XCUIApplication) throws -> String {
        let element = app.staticTexts["credits.build-commit"]
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        return element.label
    }

    private func currentGitCommit() throws -> String {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: "BuildInfo", withExtension: "plist"))
        let data = try Data(contentsOf: url)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
        )
        let commit = try XCTUnwrap(plist["GitCommit"])
        XCTAssertFalse(commit.isEmpty)
        return commit
    }

    private func expectedAppVersionLabel() throws -> String {
        let plistURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Info.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        let version = (plist["CFBundleShortVersionString"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let build = (plist["CFBundleVersion"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        switch (version, build) {
        case let (.some(version), .some(build)):
            return "Version \(version) (\(build))"
        case let (.some(version), nil):
            return "Version \(version)"
        case let (nil, .some(build)):
            return "Version \(build)"
        case (nil, nil):
            return "Version unknown"
        }
    }

    private let screenshotExportNames: [String: String] = [
        "card-open": "attribution-card-sheet",
        "nearby-prompt": "nearby-prompt",
        "locate-me-chrome": "locate-me-chrome",
        "map-home-chrome-defined-paper": "map-home-chrome-defined-paper",
        "map-home-chrome-snow": "map-home-chrome-snow",
        "map-home-chrome-street-contrast": "map-home-chrome-street-contrast",
        "map-home-chrome-verdant-kl": "map-home-chrome-verdant-kl",
        "map-home-chrome-snow-filtered": "map-home-chrome-snow-filtered",
        "map-location-off": "denied-settings",
        "place-card-a11y": "place-card-a11y",
        "credits-a11y": "credits-a11y",
        "tracks-static-geometry": "tracks-static-geometry",
        "list-map-polished-chrome": "list-map-polished-chrome",
        "list-map-spread-fit": "list-map-spread-fit",
        "my-tracks-burst-readout": "my-tracks-burst-readout",
        "track-replay-pin-arrival": "track-replay-pin-arrival",
        "pin-defined-paper-min": "pin-defined-paper-min",
        "pin-defined-paper-default": "pin-defined-paper-default",
        "pin-defined-paper-max": "pin-defined-paper-max",
        "pin-snow-min": "pin-snow-min",
        "pin-snow-default": "pin-snow-default",
        "pin-snow-max": "pin-snow-max",
        "pin-thinning-city": "pin-thinning-city",
        "pin-thinning-street": "pin-thinning-street",
        "coverage-edge-defined-paper": "coverage-edge-defined-paper",
        "coverage-edge-snow": "coverage-edge-snow",
        "coverage-edge-street-contrast": "coverage-edge-street-contrast",
        "coverage-edge-verdant-kl": "coverage-edge-verdant-kl",
    ]
}

private extension XCUIElementQuery {
    func matching(identifierPrefix prefix: String) -> XCUIElementQuery {
        matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
    }
}
