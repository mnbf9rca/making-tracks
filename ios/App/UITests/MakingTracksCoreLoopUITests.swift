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
        app.buttons["place-card.loved"].tap()
        app.buttons["place-card.close"].tap()

        XCTAssertEqual(app.staticTexts["tracks.visit-count.\(placeID)"].label, "Tracks visits: 1")
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
        XCTAssertEqual(relaunched.buttons["place-card.loved"].label, "Loved")
    }

    func testTappingAnotherPinSwitchesOpenCard() {
        let app = launch(reset: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))

        tapFixturePin(in: map)
        XCTAssertTrue(app.staticTexts["Ghost Sign"].waitForExistence(timeout: 5))
        let sheet = app.scrollViews.matching(identifierPrefix: "place-card.instance.").firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        let sheetInstanceIdentifier = sheet.identifier

        tapSecondFixturePin(in: map)
        XCTAssertTrue(app.staticTexts["Art Deco Cinema"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.scrollViews[sheetInstanceIdentifier].exists)
        XCTAssertFalse(app.staticTexts["Ghost Sign"].exists)
        attachScreenshot(named: "card-switched-to-art-deco-cinema")

        tapEmptyMap(in: map)
        XCTAssertFalse(app.staticTexts["Art Deco Cinema"].waitForExistence(timeout: 2))
    }

    func testCreditsShowBuildCommitHash() throws {
        let app = launch(reset: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))

        let osmAttribution = app.buttons["map.openstreetmap-attribution"]
        XCTAssertTrue(osmAttribution.waitForExistence(timeout: 5))
        osmAttribution.tap()
        let expectedBuildLabel = "Build \(try currentGitCommit())"
        XCTAssertTrue(app.staticTexts[expectedBuildLabel].waitForExistence(timeout: 5))
    }

    func testMapShowsOpenStreetMapAttribution() {
        let app = launch(reset: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))

        let osmAttribution = app.buttons["map.openstreetmap-attribution"]
        XCTAssertTrue(osmAttribution.waitForExistence(timeout: 5))
        osmAttribution.tap()

        XCTAssertTrue(app.staticTexts["Credits"].waitForExistence(timeout: 5))
        attachScreenshot(named: "map-openstreetmap-attribution")
    }

    func testLocateMeChromeExplainsWhenLocationIsDenied() throws {
        let app = launch(reset: true, locationDenied: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))

        XCTAssertTrue(app.staticTexts["Location is off"].waitForExistence(timeout: 5))
        let locationSettings = app.buttons["map.location-settings"]
        if !locationSettings.waitForExistence(timeout: 5) {
            XCTAssertTrue(app.otherElements["map.location-settings"].waitForExistence(timeout: 5))
        }
        attachScreenshot(named: "map-location-off")
    }

    func testCreditsShowOpenSourceAcknowledgements() throws {
        let app = launch(reset: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))

        let osmAttribution = app.buttons["map.openstreetmap-attribution"]
        XCTAssertTrue(osmAttribution.waitForExistence(timeout: 5))
        osmAttribution.tap()
        XCTAssertTrue(app.staticTexts["GRDB.swift"].waitForExistence(timeout: 5))

        let mapLibreCredit = app.staticTexts["MapLibre Native iOS / maplibre-gl-native-distribution"]
        XCTAssertTrue(scrollToExistence(of: mapLibreCredit, in: app))
        attachScreenshot(named: "credits-open-source-acknowledgements")
    }

    private func launch(reset: Bool, locationDenied: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-fixture-map"]
        if reset {
            app.launchArguments.append("--ui-testing-reset-database")
        }
        if locationDenied {
            app.launchArguments.append("--ui-testing-location-denied")
        }
        app.launch()
        return app
    }

    private func tapFixturePin(in map: XCUIElement) {
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func tapSecondFixturePin(in map: XCUIElement) {
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.67, dy: 0.37)).tap()
    }

    private func tapEmptyMap(in map: XCUIElement) {
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.20, dy: 0.30)).tap()
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @discardableResult
    private func scrollToExistence(of element: XCUIElement, in app: XCUIApplication) -> Bool {
        if element.waitForExistence(timeout: 2) {
            return true
        }

        for _ in 0..<5 {
            app.swipeUp()
            if element.waitForExistence(timeout: 1) {
                return true
            }
        }

        return element.exists
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

}

private extension XCUIElementQuery {
    func matching(identifierPrefix prefix: String) -> XCUIElementQuery {
        matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
    }
}
