import XCTest
import MakingTracksData
import MakingTracksMapStyle
import MakingTracksTiles
@testable import MakingTracks

final class AppShellTests: XCTestCase {
    func testMapHomeChromeUsesFilterGlyphAndChiplessMenuSpec() {
        XCTAssertEqual(MapHomeChromeSpec.layersSymbolName(isActive: false), "line.3.horizontal.decrease.circle")
        XCTAssertEqual(MapHomeChromeSpec.layersSymbolName(isActive: true), "line.3.horizontal.decrease.circle.fill")
        XCTAssertEqual(MapHomeChromeSpec.menuSymbolName, "line.3.horizontal")
        XCTAssertGreaterThanOrEqual(MapHomeChromeSpec.menuGlyphPointSize, 28)
        XCTAssertGreaterThanOrEqual(MapHomeChromeSpec.hitTargetSide, 44)
        XCTAssertGreaterThan(MapHomeChromeSpec.glyphHaloRadius, 0)
    }

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
        XCTAssertEqual(OfflineDownloadSettings.allowsCellularDownloadsKey, "offline.downloads.allow-cellular")
        XCTAssertFalse(OfflineDownloadSettings.defaultAllowsCellularDownloads)
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

    func testOfflineDownloadProgressSurfacesConnectivityWaitingState() {
        let progress = OfflineDownloadProgress(
            region: "uk_london",
            publishVersion: "20260718T000000Z",
            completedBytes: 0,
            totalBytes: 100,
            fractionComplete: 0,
            isWaitingForConnectivity: true
        )
        let row = OfflineRegionCatalogRow(
            zone: OfflineRegionCatalog.debugFixture.zone(id: "uk_london")!,
            depth: 1,
            state: .downloading(progress)
        )

        XCTAssertEqual(progress.statusText, "Waiting for Wi-Fi")
        XCTAssertEqual(row.statusLabel, "Waiting for Wi-Fi")
    }

    func testOnboardingDownloadStateSurfacesWaitingForWiFi() {
        let plan = OnboardingDownloadPlan(
            region: .malaysia,
            bytesToFetch: 100,
            availableBytes: 10_000_000_000,
            hasHeadroom: true,
            fetchedBytes: 0
        )

        XCTAssertEqual(
            OnboardingDownloadState.downloading(plan, fetchedBytes: 0, isWaitingForConnectivity: true).statusText,
            "Waiting for Wi-Fi"
        )
    }

    func testOfflineDownloadCancelTreatsActiveLeaseAsCancellationSuccess() {
        XCTAssertEqual(
            offlineDownloadCancelMessage {
                throw TileError.downloadAlreadyInProgress
            },
            "Download cancelled"
        )
    }

    @MainActor
    func testDeferredReplaySessionRegistersActiveControlBeforeProgressAppears() {
        let session = OfflineRegionDownloadSession()
        let control = OfflineRegionDownloadControl()
        let downloadID = UUID()
        let progress = OfflineDownloadProgress(region: "uk", publishVersion: "20260717T000000Z", completedBytes: 25, totalBytes: 100, fractionComplete: 0.25)

        XCTAssertTrue(session.beginDeferredReplay(region: "uk", control: control, downloadID: downloadID))

        XCTAssertTrue(session.activeControl === control)
        XCTAssertEqual(session.activeDownloadID, downloadID)
        XCTAssertEqual(session.liveProgress?.region, "uk")
        XCTAssertEqual(session.liveProgress?.completedBytes, 0)
        XCTAssertNil(session.pausedProgress)

        session.updateDeferredReplay(progress: progress, downloadID: downloadID)

        XCTAssertEqual(session.liveProgress?.region, "uk")
        XCTAssertEqual(session.liveProgress?.completedBytes, 25)
        XCTAssertNil(session.pausedProgress)
    }

    @MainActor
    func testDeferredReplaySessionRefusesToStealActiveUserDownload() {
        let session = OfflineRegionDownloadSession()
        let userControl = OfflineRegionDownloadControl()
        let userDownloadID = UUID()
        session.begin(region: "uk", control: userControl, downloadID: userDownloadID)

        let replayControl = OfflineRegionDownloadControl()

        XCTAssertFalse(session.beginDeferredReplay(region: "uk", control: replayControl, downloadID: UUID()))
        XCTAssertTrue(session.activeControl === userControl)
        XCTAssertEqual(session.activeDownloadID, userDownloadID)
    }

    @MainActor
    func testDeferredReplayPausePreservesResumableProgress() {
        let session = OfflineRegionDownloadSession()
        let control = OfflineRegionDownloadControl()
        let downloadID = UUID()
        let progress = OfflineDownloadProgress(region: "uk", publishVersion: "20260717T000000Z", completedBytes: 25, totalBytes: 100, fractionComplete: 0.25)

        XCTAssertTrue(session.beginDeferredReplay(region: "uk", control: control, downloadID: downloadID))
        session.updateDeferredReplay(progress: progress, downloadID: downloadID)
        session.pauseDeferredReplay(region: "uk", downloadID: downloadID)

        XCTAssertNil(session.liveProgress)
        XCTAssertNil(session.chromeProgress)
        XCTAssertEqual(session.pausedProgress, progress)
        XCTAssertEqual(session.rowProgress, progress)
        XCTAssertNil(session.activeControl)
        XCTAssertNil(session.activeTask)
    }

    @MainActor
    func testDeferredReplayPauseIgnoresStaleReplayID() {
        let session = OfflineRegionDownloadSession()
        let userControl = OfflineRegionDownloadControl()
        let userDownloadID = UUID()
        let progress = OfflineDownloadProgress(region: "uk", fractionComplete: 0.42)
        session.begin(region: "uk", control: userControl, downloadID: userDownloadID)
        session.update(progress)

        session.pauseDeferredReplay(region: "uk", downloadID: UUID())

        XCTAssertEqual(session.liveProgress, progress)
        XCTAssertNil(session.pausedProgress)
        XCTAssertTrue(session.activeControl === userControl)
        XCTAssertEqual(session.activeDownloadID, userDownloadID)
    }

    @MainActor
    func testPausedDeferredReplayBlocksAnotherDeferredReplayRegion() {
        let session = OfflineRegionDownloadSession()
        let downloadID = UUID()
        XCTAssertTrue(session.beginDeferredReplay(region: "uk", control: OfflineRegionDownloadControl(), downloadID: downloadID))
        session.updateDeferredReplay(
            progress: OfflineDownloadProgress(region: "uk", fractionComplete: 0.42),
            downloadID: downloadID
        )
        session.pauseDeferredReplay(region: "uk", downloadID: downloadID)

        XCTAssertFalse(session.canBegin(region: "malaysia"))
    }

    func testStartupAndEarlyCameraIdleSuppressManifestRefreshUntilPostFirstRenderRefreshCompletes() {
        XCTAssertFalse(MapManifestRefreshPolicy.startupAllowsManifestRefresh)
        XCTAssertFalse(MapManifestRefreshPolicy.cameraIdleAllowsManifestRefresh(afterPostFirstRenderRefreshCompleted: false))
        XCTAssertTrue(MapManifestRefreshPolicy.cameraIdleAllowsManifestRefresh(afterPostFirstRenderRefreshCompleted: true))
        XCTAssertTrue(MapManifestRefreshPolicy.mapLoadFailureAllowsManifestRefresh(afterPostFirstRenderRefreshCompleted: false))
        XCTAssertFalse(MapManifestRefreshPolicy.mapLoadFailureAllowsManifestRefresh(afterPostFirstRenderRefreshCompleted: true))
    }

    func testDeferredOfflineMaintenanceCanRunAfterMapLoadFailureWhenProtectedDataIsAvailable() {
        XCTAssertTrue(MapDeferredOfflineMaintenancePolicy.allowsDeferredMaintenance(
            isMapReady: false,
            didMapLoadFail: true,
            didScheduleMaintenance: false,
            isProtectedDataAvailable: true,
            hasPausedDownload: false,
            hasActiveDownload: false
        ))
        XCTAssertTrue(MapDeferredOfflineMaintenancePolicy.allowsDeferredMaintenance(
            isMapReady: true,
            didMapLoadFail: false,
            didScheduleMaintenance: false,
            isProtectedDataAvailable: true,
            hasPausedDownload: false,
            hasActiveDownload: false
        ))
        XCTAssertFalse(MapDeferredOfflineMaintenancePolicy.allowsDeferredMaintenance(
            isMapReady: false,
            didMapLoadFail: false,
            didScheduleMaintenance: false,
            isProtectedDataAvailable: true,
            hasPausedDownload: false,
            hasActiveDownload: false
        ))
        XCTAssertFalse(MapDeferredOfflineMaintenancePolicy.allowsDeferredMaintenance(
            isMapReady: false,
            didMapLoadFail: true,
            didScheduleMaintenance: true,
            isProtectedDataAvailable: true,
            hasPausedDownload: false,
            hasActiveDownload: false
        ))
        XCTAssertFalse(MapDeferredOfflineMaintenancePolicy.allowsDeferredMaintenance(
            isMapReady: false,
            didMapLoadFail: true,
            didScheduleMaintenance: false,
            isProtectedDataAvailable: false,
            hasPausedDownload: false,
            hasActiveDownload: false
        ))
        XCTAssertFalse(MapDeferredOfflineMaintenancePolicy.allowsDeferredMaintenance(
            isMapReady: true,
            didMapLoadFail: false,
            didScheduleMaintenance: false,
            isProtectedDataAvailable: true,
            hasPausedDownload: true,
            hasActiveDownload: false
        ))
        XCTAssertFalse(MapDeferredOfflineMaintenancePolicy.allowsDeferredMaintenance(
            isMapReady: true,
            didMapLoadFail: false,
            didScheduleMaintenance: false,
            isProtectedDataAvailable: true,
            hasPausedDownload: false,
            hasActiveDownload: true
        ))
    }

    func testMapLoadingPlaceholderUsesOpaqueDefinedPaperBackground() {
        let color = MapThemeColor.uiColor(hex: MapTheme.definedPaper.background)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        XCTAssertEqual(Int(round(red * 255)), 0xF3)
        XCTAssertEqual(Int(round(green * 255)), 0xEF)
        XCTAssertEqual(Int(round(blue * 255)), 0xE5)
        XCTAssertEqual(alpha, 1)

        let fallback = MapThemeColor.uiColor(hex: "not-a-color")
        XCTAssertTrue(fallback.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        XCTAssertEqual(Int(round(red * 255)), 0xF3)
        XCTAssertEqual(Int(round(green * 255)), 0xEF)
        XCTAssertEqual(Int(round(blue * 255)), 0xE5)
        XCTAssertEqual(alpha, 1)
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

    func testOfflineRegionCatalogFixtureIsHierarchicalAndShowsBoundedSizes() {
        let catalog = OfflineRegionCatalog.debugFixture

        XCTAssertEqual(catalog.rootZones.map(\.id), ["malaysia", "uk"])
        XCTAssertEqual(catalog.children(of: "uk").map(\.id), ["uk_london", "uk_south_east"])
        XCTAssertEqual(catalog.children(of: "malaysia").map(\.id), ["malaysia_kl", "malaysia_penang"])
        XCTAssertEqual(catalog.zone(id: "uk_london")?.sizeLabel(includeThumbnails: false), "842 MB")
        XCTAssertEqual(catalog.zone(id: "malaysia_kl")?.sizeLabel(includeThumbnails: true), "915 MB")
        XCTAssertNil(catalog.zone(id: "not-a-zone"))
    }

    func testOfflineRegionRowsSurfaceProgressUpdatesAndQuarantines() {
        let catalog = OfflineRegionCatalog.debugFixture
        let progress = OfflineDownloadProgress(
            region: "uk_london",
            publishVersion: "20260718T000000Z",
            completedBytes: 50,
            totalBytes: 100,
            fractionComplete: 0.5
        )
        let quarantine = OfflinePackQuarantine(
            region: "malaysia_kl",
            publishVersion: "20260717T000000Z",
            coordinates: [TileCoordinate(z: 10, x: 806, y: 503)]
        )

        let rows = catalog.rows(
            installed: [
                "uk": "20260718T000000Z",
                "uk_london": "20260717T000000Z",
                "uk_south_east": "20260717T000000Z",
                "malaysia_kl": "20260717T000000Z",
            ],
            activeProgress: progress,
            quarantines: [quarantine]
        )
        let uk = rows.first { $0.zone.id == "uk" }
        let london = rows.first { $0.zone.id == "uk_london" }
        let southEast = rows.first { $0.zone.id == "uk_south_east" }
        let kl = rows.first { $0.zone.id == "malaysia_kl" }

        XCTAssertEqual(uk?.state, .installed(publishVersion: "20260718T000000Z"))
        XCTAssertEqual(london?.state, .downloading(progress))
        XCTAssertEqual(
            southEast?.state,
            .updateAvailable(
                installedPublishVersion: "20260717T000000Z",
                availablePublishVersion: "20260718T000000Z"
            )
        )
        XCTAssertEqual(kl?.state, .quarantined(quarantine))
        XCTAssertEqual(london?.depth, 1)
        XCTAssertEqual(southEast?.statusLabel, "Update available")
        XCTAssertEqual(kl?.statusLabel, "Quarantined pack")
    }

    func testOfflineRegionRowsSurfacePausedProgressSeparatelyFromActiveProgress() {
        let catalog = OfflineRegionCatalog.debugFixture
        let paused = OfflineDownloadProgress(
            region: "uk_london",
            publishVersion: "20260718T000000Z",
            completedBytes: 50,
            totalBytes: 100,
            fractionComplete: 0.5
        )

        let rows = catalog.rows(
            installed: [
                "uk": "20260718T000000Z",
                "uk_london": "20260717T000000Z",
            ],
            activeProgress: nil,
            pausedProgress: paused,
            quarantines: []
        )
        let london = rows.first { $0.zone.id == "uk_london" }

        XCTAssertEqual(london?.state, .paused(paused))
        XCTAssertEqual(london?.statusLabel, "Paused at 50%")
    }

    @MainActor
    func testOfflineDownloadSessionDeletePreservesUnrelatedActiveDownload() {
        let session = OfflineRegionDownloadSession()
        let progress = OfflineDownloadProgress(region: "uk", fractionComplete: 0.42)
        let downloadID = UUID()
        let task = Task<Void, Never> {}
        defer { task.cancel() }

        session.begin(region: "uk", control: OfflineRegionDownloadControl(), downloadID: downloadID)
        session.attach(task: task)
        session.update(progress)
        session.noteDeleted(region: "malaysia")

        XCTAssertEqual(session.liveProgress, progress)
        XCTAssertNil(session.pausedProgress)
        XCTAssertNotNil(session.activeControl)
        XCTAssertNotNil(session.activeTask)
        XCTAssertEqual(session.activeDownloadID, downloadID)
    }

    @MainActor
    func testOfflineDownloadSessionPauseClearsChipProgressButKeepsResumableProgress() {
        let session = OfflineRegionDownloadSession()
        let progress = OfflineDownloadProgress(region: "uk", fractionComplete: 0.42)

        session.begin(region: "uk", control: OfflineRegionDownloadControl(), downloadID: UUID())
        session.update(progress)
        session.pause(region: "uk")

        XCTAssertNil(session.liveProgress)
        XCTAssertNil(session.chromeProgress)
        XCTAssertEqual(session.pausedProgress, progress)
        XCTAssertEqual(session.rowProgress, progress)
        XCTAssertNil(session.activeControl)
        XCTAssertNil(session.activeTask)
    }

    @MainActor
    func testOfflineDownloadSessionRequiresPausedRegionToResumeOrCancelBeforeStartingAnotherRegion() {
        let session = OfflineRegionDownloadSession()

        session.begin(region: "uk", control: OfflineRegionDownloadControl(), downloadID: UUID())
        session.update(OfflineDownloadProgress(region: "uk", fractionComplete: 0.42))
        session.pause(region: "uk")

        XCTAssertTrue(session.canBegin(region: "uk"))
        XCTAssertFalse(session.canBegin(region: "malaysia"))
    }

    @MainActor
    func testOfflineDownloadSessionUsesPersistedPausedRowRegionForCancelAfterRelaunch() {
        let session = OfflineRegionDownloadSession()

        XCTAssertEqual(session.regionForCancel(fallbackRegion: "uk_london"), "uk_london")
    }

    @MainActor
    func testOfflineDownloadSessionUsesTappedPausedRowRegionBeforeLiveSessionForCancel() {
        let session = OfflineRegionDownloadSession()
        session.begin(region: "uk", control: OfflineRegionDownloadControl(), downloadID: UUID())
        session.update(OfflineDownloadProgress(region: "uk", fractionComplete: 0.42))

        XCTAssertFalse(session.canBegin(region: "uk_london"))
        XCTAssertEqual(session.regionForCancel(fallbackRegion: "uk_london"), "uk_london")
        XCTAssertFalse(session.shouldClearSessionForCancel(fallbackRegion: "uk_london"))
        XCTAssertTrue(session.shouldClearSessionForCancel(fallbackRegion: "uk"))
        XCTAssertFalse(session.isSessionRegion("uk_london"))
        XCTAssertTrue(session.isSessionRegion("uk"))
    }

    func testDeferredOfflineMaintenanceRouteCarriesCellularPolicyIntoReplayFetchers() {
        let route = DeferredOfflineMaintenanceDownloadRoute(
            region: "uk",
            allowsCellularDownloads: true
        )
        defer {
            OfflineDownloadSession.invalidateBackgroundSessionForTesting(identifier: route.backgroundIdentifier)
        }

        XCTAssertEqual(route.backgroundIdentifier, OfflineDownloadSession.backgroundIdentifier(region: "uk"))
        XCTAssertTrue(route.metadataAllowsCellularDownloadsForTesting)
        XCTAssertTrue(route.objectAllowsCellularDownloadsForTesting)
    }

    func testPausedOfflineRegionCatalogRowCarriesRowRegionForCancelAction() {
        let zone = OfflineRegionCatalogZone(
            id: "uk_london",
            displayName: "London",
            parentID: "uk",
            publishVersion: "20260718T000000Z",
            bytesWithoutThumbnails: 842_000_000,
            bytesWithThumbnails: 1_160_000_000
        )

        XCTAssertEqual(
            OfflineRegionCatalogRow(
                zone: zone,
                depth: 1,
                state: .paused(OfflineDownloadProgress(region: "uk_london", fractionComplete: 0))
            ).cancelRegion,
            "uk_london"
        )
        XCTAssertNil(OfflineRegionCatalogRow(
            zone: zone,
            depth: 1,
            state: .downloading(OfflineDownloadProgress(region: "uk_london", fractionComplete: 0.42))
        ).cancelRegion)
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
            onMapReady: { _ in },
            onFeaturesApplied: {},
            onStyleWillReload: {},
            onMapLoadFailed: {}
        )
    }
}
