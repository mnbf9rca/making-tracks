import XCTest
import MakingTracksData
import MakingTracksMapStyle
import MakingTracksTiles
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

    func testAppShellModelCanRouteOfflineMapsDeepLink() {
        let shell = AppShellModel()

        shell.openOfflineMapsDeepLink()

        XCTAssertTrue(shell.isMenuPresented)
        XCTAssertEqual(shell.deepLinkPath, .offlineMaps)
    }

    func testUpdateRequiredSurfaceBlocksOnlyFreshTooOldReaderState() throws {
        let surface = try XCTUnwrap(MapBlockingSurface.resolve(loadState: .updateRequired))

        XCTAssertEqual(surface.title, "Update required")
        XCTAssertTrue(surface.message.contains("too old to read the latest map"))
        XCTAssertEqual(surface.primaryActionTitle, "Open App Store")
        XCTAssertEqual(surface.appStoreURL.scheme, "https")
        XCTAssertEqual(surface.appStoreURL.host, "apps.apple.com")

        let nonBlockingStates: [TileLoadState] = [.ok, .stale, .updateAvailable, .offline, .manifestInvalid, .unavailable]
        for loadState in nonBlockingStates {
            XCTAssertNil(MapBlockingSurface.resolve(loadState: loadState), "\(loadState) must not block the app")
        }
    }

    func testEmptyRegionSurfaceDistinguishesUnsupportedUnavailableAndGenuineEmpty() {
        let ocean = ViewportSeed.ocean
        let london = ViewportSeed(
            bbox: BBox(minLon: -0.13, minLat: 51.48, maxLon: -0.11, maxLat: 51.50),
            zoom: 12
        )
        let wideSupported = ViewportSeed(
            bbox: BBox(minLon: -8.65, minLat: 0.85, maxLon: 119.27, maxLat: 60.86),
            zoom: 1
        )
        let place = MapPlace(id: "mt1_test", lat: 51.49, lon: -0.12, tier: 1, category: "history")

        XCTAssertEqual(
            MapEmptyRegionSurface.resolve(features: [], loadState: .ok, viewport: ocean, isFixtureMap: false),
            .unsupportedRegion
        )
        XCTAssertEqual(
            MapEmptyRegionSurface.resolve(features: [], loadState: .unavailable, viewport: ocean, isFixtureMap: false),
            .unsupportedRegion
        )
        XCTAssertEqual(
            MapEmptyRegionSurface.resolve(features: [], loadState: .unavailable, viewport: london, isFixtureMap: false),
            .mapDataUnavailable
        )
        XCTAssertEqual(
            MapEmptyRegionSurface.resolve(features: [], loadState: .ok, viewport: london, isFixtureMap: false),
            .noPlaces
        )
        XCTAssertEqual(
            MapEmptyRegionSurface.resolve(features: [], loadState: .ok, viewport: wideSupported, isFixtureMap: false),
            .noPlaces
        )
        XCTAssertNil(MapEmptyRegionSurface.resolve(
            features: [],
            loadState: .ok,
            viewport: london,
            isFixtureMap: false,
            isViewportLoading: true
        ))
        XCTAssertNil(MapEmptyRegionSurface.resolve(
            features: [],
            loadState: .manifestInvalid,
            viewport: london,
            isFixtureMap: false
        ))
        XCTAssertNil(MapEmptyRegionSurface.resolve(
            features: [(place, PinState(saved: false, visit: .none))],
            loadState: .unavailable,
            viewport: london,
            isFixtureMap: false
        ))
        XCTAssertNil(MapEmptyRegionSurface.resolve(features: [], loadState: .ok, viewport: london, isFixtureMap: true))
    }

    func testMapDataUnavailableSurfaceUsesNeutralCopyAndOfflineMapsAffordance() throws {
        let surface = MapEmptyRegionSurface.mapDataUnavailable

        XCTAssertEqual(surface.title, "Map data unavailable")
        XCTAssertTrue(surface.message.contains("Check your connection"))
        XCTAssertEqual(surface.primaryActionTitle, "Offline maps")
        XCTAssertNil(MapEmptyRegionSurface.unsupportedRegion.primaryActionTitle)
        XCTAssertNil(MapEmptyRegionSurface.noPlaces.primaryActionTitle)
    }

    func testViewportRefreshTrackerSuppressesEmptySurfaceUntilLatestRefreshCompletes() {
        var tracker = ViewportRefreshTracker()
        let london = ViewportSeed(
            bbox: BBox(minLon: -0.13, minLat: 51.48, maxLon: -0.11, maxLat: 51.50),
            zoom: 12
        )

        let firstRequestID = tracker.nextRequestID()
        let secondRequestID = tracker.nextRequestID()

        XCTAssertTrue(tracker.isLoading)
        XCTAssertNil(MapEmptyRegionSurface.resolve(
            features: [],
            loadState: .ok,
            viewport: london,
            isFixtureMap: false,
            isViewportLoading: tracker.isLoading
        ))

        tracker.complete(requestID: firstRequestID)
        XCTAssertTrue(tracker.isLoading)

        tracker.complete(requestID: secondRequestID)
        XCTAssertFalse(tracker.isLoading)
        XCTAssertEqual(MapEmptyRegionSurface.resolve(
            features: [],
            loadState: .ok,
            viewport: london,
            isFixtureMap: false,
            isViewportLoading: tracker.isLoading
        ), .noPlaces)
    }

    @MainActor
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

    func testOnboardingStorageUsesFoldedDesignKeys() {
        XCTAssertEqual(OnboardingStorage.hasCompletedOnboardingKey, "hasCompletedOnboarding")
        XCTAssertEqual(OnboardingStorage.chosenRegionKey, "chosenRegion")
    }

    func testChosenRegionDrivesStartupSeedUnlessUITestArgumentOverrides() {
        XCTAssertEqual(OnboardingRegionChoice.uk.startupViewport, .uk)
        XCTAssertEqual(OnboardingRegionChoice.malaysia.startupViewport, .kl)
        XCTAssertEqual(
            OnboardingStorage.startupViewport(argumentSeed: nil, chosenRegionRawValue: "uk"),
            .uk
        )
        XCTAssertEqual(
            OnboardingStorage.startupViewport(argumentSeed: nil, chosenRegionRawValue: "malaysia"),
            .kl
        )
        XCTAssertEqual(
            OnboardingStorage.startupViewport(argumentSeed: "ocean", chosenRegionRawValue: "uk"),
            .ocean
        )
    }

    func testOnboardingCopyMatchesPrivacyPolicyQualifierAndDoesNotExposeImageToggle() {
        XCTAssertEqual(
            OnboardingCopy.savedActivityPrivacy,
            "Nothing you save leaves unless you choose to share it."
        )
        XCTAssertFalse(OnboardingCopy.offlinePackOffer.contains("no one can see where you look"))
        XCTAssertFalse(OnboardingCopy.offlinePackOffer.localizedCaseInsensitiveContains("images"))
    }

    func testReplayPreselectsExistingRegionButTrueFirstRunDoesNot() {
        XCTAssertNil(OnboardingFlowState.initialSelectedRegion(isReplay: false, chosenRegionRawValue: "uk"))
        XCTAssertEqual(OnboardingFlowState.initialSelectedRegion(isReplay: true, chosenRegionRawValue: "uk"), .uk)
        XCTAssertEqual(OnboardingFlowState.initialSelectedRegion(isReplay: true, chosenRegionRawValue: "malaysia"), .malaysia)
        XCTAssertNil(OnboardingFlowState.initialSelectedRegion(isReplay: true, chosenRegionRawValue: "not-a-region"))
    }

    @MainActor
    func testLocationPermissionRequestIsOneShotAndExplicit() {
        let manager = AppLocationManager(simulatedAuthorizationStatus: .notDetermined)
        let permission = LocationPermission(manager: manager)

        XCTAssertEqual(manager.whenInUseAuthorizationRequestCount, 0)
        XCTAssertEqual(permission.authorizationRequestCount, 0)

        permission.requestWhenInUseIfNeeded()
        permission.requestWhenInUseIfNeeded()

        XCTAssertEqual(manager.whenInUseAuthorizationRequestCount, 1)
        XCTAssertEqual(permission.authorizationRequestCount, 1)
    }

    @MainActor
    func testMapCameraRequestIsConsumedOnce() {
        let coordinator = makeCoordinator()

        XCTAssertTrue(coordinator.consumeCameraRequest(1))
        XCTAssertFalse(coordinator.consumeCameraRequest(1))
        XCTAssertTrue(coordinator.consumeCameraRequest(2))
    }

    func testOfflineDownloadProgressCarriesDownloaderBytes() {
        let progress = OfflineDownloadProgress(OfflineRegionDownloadProgress(
            region: "uk",
            publishVersion: "20260717T000000Z",
            completedBytes: 25,
            totalBytes: 100,
            completedObjectCount: 1,
            totalObjectCount: 4
        ))

        XCTAssertEqual(progress.region, "uk")
        XCTAssertEqual(progress.completedBytes, 25)
        XCTAssertEqual(progress.totalBytes, 100)
        XCTAssertEqual(progress.percentComplete, 25)
    }

    func testStorageMenuStatusUsesStableRowsAndByteFormatting() {
        let status = StorageMenuStatus.ready(
            totalBytes: 2_097_152,
            regions: [
                StorageMenuRegion(region: "uk_london", publishVersion: "20260716T155409Z", bytes: 1_572_864, tileCount: 12),
                StorageMenuRegion(region: "uk", publishVersion: "20260716T155409Z", bytes: 524_288, tileCount: 4),
            ]
        )

        XCTAssertEqual(status.totalBytesText, "2.1 MB")
        XCTAssertEqual(status.regions.map(\.region), ["uk", "uk_london"])
        XCTAssertEqual(status.regions.map(\.title), ["uk", "uk_london"])
        XCTAssertEqual(status.regions.map(\.detail), [
            "20260716T155409Z · 4 tiles",
            "20260716T155409Z · 12 tiles",
        ])
        XCTAssertEqual(status.regions.map(\.bytesText), ["524 KB", "1.6 MB"])
        XCTAssertEqual(status.failedRegions, [])
    }

    func testStorageMenuStatusTreatsEmptyStoreAsReady() {
        let status = StorageMenuStatus.ready(from: OfflinePackStorageSummary(packs: [], failedRegions: [], totalBytes: 0))

        XCTAssertEqual(status.kind, .ready)
        XCTAssertEqual(status.totalBytesText, "Zero KB")
        XCTAssertEqual(status.regions, [])
        XCTAssertEqual(status.failedRegions, [])
    }

    @MainActor
    func testCoordinatorGeneratesThemeSpecificStyleJSON() throws {
        let coordinator = makeCoordinator()

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
        let coordinator = makeCoordinator()
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

    @MainActor
    private func makeCoordinator() -> MLNMapViewRepresentable.Coordinator {
        MLNMapViewRepresentable.Coordinator(
            onCameraIdle: { _, _ in },
            onUserPanned: {},
            onTapPlace: { _ in },
            onTapEmpty: {},
            onMapReady: {},
            onFeaturesApplied: {},
            onStyleWillReload: {},
            onMapLoadFailed: {}
        )
    }
}
