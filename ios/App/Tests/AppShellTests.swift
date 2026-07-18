import XCTest
import MakingTracksMapStyle
@testable import MakingTracks

final class AppShellTests: XCTestCase {
    func testAppShellModelSeparatesMenuPresentationFromDeepLinkRouting() {
        let shell = AppShellModel()

        XCTAssertFalse(shell.isMenuPresented)
        XCTAssertNil(shell.deepLinkPath)

        shell.isMenuPresented = true
        XCTAssertTrue(shell.isMenuPresented)
        XCTAssertNil(shell.deepLinkPath)

        shell.deepLinkPath = .offlineMaps
        XCTAssertTrue(shell.isMenuPresented)
        XCTAssertEqual(shell.deepLinkPath, .offlineMaps)
    }

    func testThemeStorageUsesStableKeyAndDefinedPaperDefault() {
        XCTAssertEqual(MapScreen.themeStorageKey, "map.theme.id")
        XCTAssertEqual(MapTheme.named(nil).id, MapTheme.definedPaper.id)
        XCTAssertEqual(MapTheme.named("defined-paper").displayName, "Defined Paper")
    }

    func testOfflineDownloadProgressBoundsInvalidFractions() {
        XCTAssertEqual(OfflineDownloadProgress(fractionComplete: .nan).percentComplete, 0)
        XCTAssertEqual(OfflineDownloadProgress(fractionComplete: .infinity).percentComplete, 0)
        XCTAssertEqual(OfflineDownloadProgress(fractionComplete: -.infinity).percentComplete, 0)
        XCTAssertEqual(OfflineDownloadProgress(fractionComplete: -0.25).percentComplete, 0)
        XCTAssertEqual(OfflineDownloadProgress(fractionComplete: 1.25).percentComplete, 100)
    }

    @MainActor
    func testCoordinatorGeneratesThemeSpecificStyleJSON() throws {
        let coordinator = MLNMapViewRepresentable.Coordinator(
            onCameraIdle: { _, _ in },
            onUserPanned: {},
            onTapPlace: { _ in },
            onTapEmpty: {}
        )

        let definedPaperURL = try XCTUnwrap(coordinator.styleURL(
            worldPMTilesURL: "pmtiles://world.pmtiles",
            regionPMTilesURL: nil,
            theme: .definedPaper
        ))
        let snowURL = try XCTUnwrap(coordinator.styleURL(
            worldPMTilesURL: "pmtiles://world.pmtiles",
            regionPMTilesURL: nil,
            theme: .snow
        ))

        let definedPaperJSON = try String(contentsOf: definedPaperURL, encoding: .utf8)
        let snowJSON = try String(contentsOf: snowURL, encoding: .utf8)
        XCTAssertNotEqual(definedPaperJSON, snowJSON)
        XCTAssertTrue(definedPaperJSON.contains(MapTheme.definedPaper.background))
        XCTAssertTrue(snowJSON.contains(MapTheme.snow.background))
    }

    @MainActor
    func testCoordinatorReloadPlanIncludesThemeAndCommitsOnlyAfterURLExists() throws {
        let coordinator = MLNMapViewRepresentable.Coordinator(
            onCameraIdle: { _, _ in },
            onUserPanned: {},
            onTapPlace: { _ in },
            onTapEmpty: {}
        )
        coordinator.currentWorldPMTilesURL = "pmtiles://world.pmtiles"
        coordinator.currentRegionPMTilesURL = nil
        coordinator.currentThemeID = MapTheme.definedPaper.id

        let failedReload = coordinator.prepareStyleReload(
            worldPMTilesURL: "pmtiles://world.pmtiles",
            regionPMTilesURL: nil,
            theme: .snow,
            makeStyleURL: { _, _, _ in nil }
        )
        XCTAssertNil(failedReload)
        XCTAssertEqual(coordinator.currentThemeID, MapTheme.definedPaper.id)

        let url = URL(fileURLWithPath: "/tmp/making-tracks-style-test.json")
        let reload = try XCTUnwrap(coordinator.prepareStyleReload(
            worldPMTilesURL: "pmtiles://world.pmtiles",
            regionPMTilesURL: nil,
            theme: .snow,
            makeStyleURL: { _, _, _ in url }
        ))
        XCTAssertEqual(reload.themeID, MapTheme.snow.id)
        coordinator.commitStyleReload(reload)
        XCTAssertEqual(coordinator.currentThemeID, MapTheme.snow.id)
        XCTAssertNil(coordinator.prepareStyleReload(
            worldPMTilesURL: "pmtiles://world.pmtiles",
            regionPMTilesURL: nil,
            theme: .snow,
            makeStyleURL: { _, _, _ in url }
        ))
    }
}
