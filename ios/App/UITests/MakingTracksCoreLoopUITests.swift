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

    func testPlaceCardOverhaulRendersHierarchyAndHideAction() {
        let app = launch(reset: true, seedUserList: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))

        openFixtureCard(in: map, app: app)

        let title = element(identifier: "place-card.title", in: app)
        let typeLabel = element(identifier: "place-card.type.label", in: app)
        let description = element(identifier: "place-card.description", in: app)
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

        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        XCTAssertEqual(photo.label, "Photo of Ghost Sign")

        let saveButton = app.buttons["place-card.save"]
        let seenButton = app.buttons["place-card.visited"]
        let hideButton = app.buttons["place-card.hide"]
        XCTAssertTrue(saveButton.exists)
        XCTAssertTrue(seenButton.exists)
        XCTAssertTrue(hideButton.exists)
        XCTAssertTrue(chips.waitForExistence(timeout: 5))
        XCTAssertTrue(chips.label.contains("Date night"))

        XCTAssertTrue(scrollToExistence(of: attribution, in: app))
        XCTAssertTrue(attribution.label.contains("Fixture photo"))

        assertVerticallyOrdered([
            ("title", title),
            ("type", typeLabel),
            ("description", description),
            ("photo", photo),
            ("chips", chips),
            ("actions", saveButton),
            ("attribution", attribution),
        ])

        hideButton.tap()
        XCTAssertTrue(app.staticTexts["Hidden — Undo"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Ghost Sign"].waitForExistence(timeout: 2))

        tapFixturePin(in: map)
        XCTAssertFalse(app.staticTexts["Ghost Sign"].waitForExistence(timeout: 2))
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
        let app = launch(reset: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))

        app.buttons["debug.hide-fixture"].tap()
        XCTAssertTrue(waitForFixtureHidden(true, in: app))
        tapFixturePin(in: map)
        XCTAssertFalse(app.staticTexts["Ghost Sign"].waitForExistence(timeout: 2))

        app.buttons["debug.unhide-fixture"].tap()
        XCTAssertTrue(waitForFixtureHidden(false, in: app))
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
        let expectedBuildLabel = "Build \(try currentGitCommit())"
        XCTAssertTrue(app.staticTexts[expectedBuildLabel].waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.staticTexts["settings.theme.selected"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["settings.theme.selected"].label, "Defined Paper")

        app.buttons["settings.theme.snow"].tap()
        XCTAssertEqual(app.staticTexts["settings.theme.selected"].label, "Snow")
        app.buttons["menu.done"].tap()
    }

    func testPlaceCardStacksActionsAtAccessibilityTextSize() {
        let app = launch(reset: true, accessibilityTextSize: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))

        tapFixturePin(in: map)
        XCTAssertTrue(app.staticTexts["Ghost Sign"].waitForExistence(timeout: 5))

        let saveButton = app.buttons["place-card.save"]
        let visitedButton = app.buttons["place-card.visited"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        XCTAssertTrue(visitedButton.waitForExistence(timeout: 5))
        attachScreenshot(named: "place-card-a11y")
        XCTAssertGreaterThan(visitedButton.frame.minY, saveButton.frame.minY)

        visitedButton.tap()
        let lovedButton = app.buttons["place-card.loved"]
        XCTAssertTrue(lovedButton.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(lovedButton.frame.minY, visitedButton.frame.minY)
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

    func testCreditsStayGroupedAtAccessibilityTextSize() throws {
        let app = launch(reset: true, accessibilityTextSize: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))

        openAppMenu(in: app)
        app.buttons["menu.row.about"].tap()
        XCTAssertTrue(app.staticTexts["About"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Build"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Open source acknowledgements"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Build \(try currentGitCommit())"].waitForExistence(timeout: 5))
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
        locationDenied: Bool = false,
        simulatedLocationAuthorization: Bool = false,
        simulatedLatitude: Double? = nil,
        simulatedLongitude: Double? = nil,
        accessibilityTextSize: Bool = false,
        seedUserList: Bool = false,
        offlineProgress: Double? = nil,
        resetTheme: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-fixture-map"]
        if reset {
            app.launchArguments.append("--ui-testing-reset-database")
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
        if seedUserList {
            app.launchArguments.append("--ui-testing-seed-user-list")
        }
        if let offlineProgress {
            app.launchArguments.append("--ui-testing-offline-progress")
            app.launchArguments.append(String(offlineProgress))
        }
        if resetTheme {
            app.launchArguments.append("--ui-testing-reset-theme")
        }
        app.launch()
        return app
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

    private func tapEmptyMap(in map: XCUIElement) {
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.20, dy: 0.30)).tap()
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
        guard let exportName = screenshotExportNames[name] else { return }
        let directory = URL(fileURLWithPath: "/private/tmp/making-tracks-artifacts", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent(exportName).appendingPathExtension("png")
        try? screenshot.pngRepresentation.write(to: fileURL)
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

    private func scrollTarget(in app: XCUIApplication) -> XCUIElement {
        let scrollView = app.scrollViews.firstMatch
        if scrollView.exists {
            return scrollView
        }
        return app
    }

    private func element(identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", identifier))
            .firstMatch
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

    private let screenshotExportNames: [String: String] = [
        "card-open": "attribution-card-sheet",
        "nearby-prompt": "nearby-prompt",
        "locate-me-chrome": "locate-me-chrome",
        "map-location-off": "denied-settings",
        "place-card-a11y": "place-card-a11y",
        "credits-a11y": "credits-a11y",
    ]
}

private extension XCUIElementQuery {
    func matching(identifierPrefix prefix: String) -> XCUIElementQuery {
        matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
    }
}
