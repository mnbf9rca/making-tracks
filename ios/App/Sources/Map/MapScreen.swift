import CoreLocation
import Observation
import SwiftUI
import UIKit
@preconcurrency import MapLibre
import MakingTracksCore
import MakingTracksData
import MakingTracksMapStyle
import MakingTracksTiles

struct MapHomeChromeSpec {
    static let menuSymbolName = "line.3.horizontal"
    static let menuGlyphPointSize: CGFloat = 30
    static let hitTargetSide: CGFloat = 44
    static let glyphHaloRadius: CGFloat = 1.2
    static let glyphHaloYOffset: CGFloat = 1

    static func layersSymbolName(isActive: Bool) -> String {
        isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
    }
}

struct OfflineRegionCatalogZone: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let parentID: String?
    let publishVersion: String
    let bytesWithoutThumbnails: Int
    let bytesWithThumbnails: Int

    func sizeLabel(includeThumbnails: Bool) -> String {
        let bytes = includeThumbnails ? bytesWithThumbnails : bytesWithoutThumbnails
        if bytes >= 1_000_000_000 {
            return String(format: "%.1f GB", Double(bytes) / 1_000_000_000.0)
        }
        return "\(Int((Double(bytes) / 1_000_000.0).rounded())) MB"
    }
}

struct OfflineRegionCatalog: Sendable, Equatable {
    let zones: [OfflineRegionCatalogZone]

    static let debugFixture = OfflineRegionCatalog(zones: [
        OfflineRegionCatalogZone(
            id: "uk",
            displayName: "United Kingdom",
            parentID: nil,
            publishVersion: "20260718T000000Z",
            bytesWithoutThumbnails: 2_640_000_000,
            bytesWithThumbnails: 3_180_000_000
        ),
        OfflineRegionCatalogZone(
            id: "uk_london",
            displayName: "London",
            parentID: "uk",
            publishVersion: "20260718T000000Z",
            bytesWithoutThumbnails: 842_000_000,
            bytesWithThumbnails: 1_160_000_000
        ),
        OfflineRegionCatalogZone(
            id: "uk_south_east",
            displayName: "South East England",
            parentID: "uk",
            publishVersion: "20260718T000000Z",
            bytesWithoutThumbnails: 1_120_000_000,
            bytesWithThumbnails: 1_410_000_000
        ),
        OfflineRegionCatalogZone(
            id: "malaysia",
            displayName: "Malaysia",
            parentID: nil,
            publishVersion: "20260718T000000Z",
            bytesWithoutThumbnails: 1_420_000_000,
            bytesWithThumbnails: 1_980_000_000
        ),
        OfflineRegionCatalogZone(
            id: "malaysia_kl",
            displayName: "Kuala Lumpur",
            parentID: "malaysia",
            publishVersion: "20260718T000000Z",
            bytesWithoutThumbnails: 610_000_000,
            bytesWithThumbnails: 915_000_000
        ),
        OfflineRegionCatalogZone(
            id: "malaysia_penang",
            displayName: "Penang",
            parentID: "malaysia",
            publishVersion: "20260718T000000Z",
            bytesWithoutThumbnails: 520_000_000,
            bytesWithThumbnails: 760_000_000
        ),
    ])

    var rootZones: [OfflineRegionCatalogZone] {
        zones.filter { $0.parentID == nil }.sorted(by: zoneSort)
    }

    func zone(id: String) -> OfflineRegionCatalogZone? {
        zones.first { $0.id == id }
    }

    func children(of parentID: String) -> [OfflineRegionCatalogZone] {
        zones.filter { $0.parentID == parentID }.sorted(by: zoneSort)
    }

    func rows(
        installed: [String: String],
        availablePublishVersions: [String: String] = [:],
        activeProgress: OfflineDownloadProgress?,
        pausedProgress: OfflineDownloadProgress? = nil,
        pausedRegions: Set<String> = [],
        quarantines: [OfflinePackQuarantine]
    ) -> [OfflineRegionCatalogRow] {
        let quarantineByRegion = quarantines.reduce(into: [String: OfflinePackQuarantine]()) { byRegion, quarantine in
            byRegion[quarantine.region] = quarantine
        }
        return rootZones.flatMap {
            rows(
                for: $0,
                depth: 0,
                installed: installed,
                availablePublishVersions: availablePublishVersions,
                activeProgress: activeProgress,
                pausedProgress: pausedProgress,
                pausedRegions: pausedRegions,
                quarantines: quarantineByRegion
            )
        }
    }

    private func rows(
        for zone: OfflineRegionCatalogZone,
        depth: Int,
        installed: [String: String],
        availablePublishVersions: [String: String],
        activeProgress: OfflineDownloadProgress?,
        pausedProgress: OfflineDownloadProgress?,
        pausedRegions: Set<String>,
        quarantines: [String: OfflinePackQuarantine]
    ) -> [OfflineRegionCatalogRow] {
        let state: OfflineRegionCatalogRow.State
        let isSupportedRegion = MapRegion(rawValue: zone.id) != nil
        let hasUnavailableLocalData = !isSupportedRegion && (installed[zone.id] != nil || quarantines[zone.id] != nil)
        let hasUnavailablePausedDownload = !isSupportedRegion
            && (activeProgress?.region == zone.id || pausedProgress?.region == zone.id || pausedRegions.contains(zone.id))
        if !isSupportedRegion {
            state = .unavailable
        } else if let quarantine = quarantines[zone.id] {
            state = .quarantined(quarantine)
        } else if activeProgress?.region == zone.id {
            state = .downloading(activeProgress!)
        } else if pausedProgress?.region == zone.id {
            state = .paused(pausedProgress!)
        } else if pausedRegions.contains(zone.id) {
            state = .paused(OfflineDownloadProgress(region: zone.id, fractionComplete: 0))
        } else if let installedVersion = installed[zone.id] {
            if let availablePublishVersion = availablePublishVersions[zone.id],
               installedVersion != availablePublishVersion
            {
                state = .updateAvailable(
                    installedPublishVersion: installedVersion,
                    availablePublishVersion: availablePublishVersion
                )
            } else {
                state = .installed(publishVersion: installedVersion)
            }
        } else {
            state = .notInstalled
        }
        let current = OfflineRegionCatalogRow(
            zone: zone,
            depth: depth,
            state: state,
            hasUnavailableLocalData: hasUnavailableLocalData,
            hasUnavailablePausedDownload: hasUnavailablePausedDownload
        )
        return [current] + children(of: zone.id).flatMap {
            rows(
                for: $0,
                depth: depth + 1,
                installed: installed,
                availablePublishVersions: availablePublishVersions,
                activeProgress: activeProgress,
                pausedProgress: pausedProgress,
                pausedRegions: pausedRegions,
                quarantines: quarantines
            )
        }
    }

    private func zoneSort(_ lhs: OfflineRegionCatalogZone, _ rhs: OfflineRegionCatalogZone) -> Bool {
        if lhs.displayName != rhs.displayName {
            return lhs.displayName < rhs.displayName
        }
        return lhs.id < rhs.id
    }
}

struct OfflineRegionCatalogRow: Identifiable, Sendable, Equatable {
    enum State: Sendable, Equatable {
        case notInstalled
        case unavailable
        case installed(publishVersion: String)
        case updateAvailable(installedPublishVersion: String, availablePublishVersion: String)
        case downloading(OfflineDownloadProgress)
        case paused(OfflineDownloadProgress)
        case quarantined(OfflinePackQuarantine)
    }

    let zone: OfflineRegionCatalogZone
    let depth: Int
    let state: State
    let hasUnavailableLocalData: Bool
    let hasUnavailablePausedDownload: Bool

    init(
        zone: OfflineRegionCatalogZone,
        depth: Int,
        state: State,
        hasUnavailableLocalData: Bool = false,
        hasUnavailablePausedDownload: Bool = false
    ) {
        self.zone = zone
        self.depth = depth
        self.state = state
        self.hasUnavailableLocalData = hasUnavailableLocalData
        self.hasUnavailablePausedDownload = hasUnavailablePausedDownload
    }

    var id: String { zone.id }

    var statusLabel: String {
        switch state {
        case .notInstalled:
            "Not downloaded"
        case .unavailable:
            "Not available"
        case .installed:
            "Downloaded"
        case .updateAvailable:
            "Update available"
        case let .downloading(progress):
            progress.isWaitingForConnectivity ? progress.statusText : "Downloading \(progress.percentComplete)%"
        case let .paused(progress):
            "Paused at \(progress.percentComplete)%"
        case .quarantined:
            "Quarantined pack"
        }
    }

    var cancelRegion: String? {
        guard case .paused = state else {
            return hasUnavailablePausedDownload ? zone.id : nil
        }
        return zone.id
    }

    var allowsDelete: Bool {
        switch state {
        case .installed, .updateAvailable:
            true
        case .unavailable:
            hasUnavailableLocalData
        case .notInstalled, .downloading, .paused, .quarantined:
            false
        }
    }
}

struct ViewportSeed: Sendable, Equatable {
    let bbox: BBox
    let zoom: Int

    var center: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: bbox.center.lat, longitude: bbox.center.lon)
    }

    static let kl = ViewportSeed(
        bbox: BBox(minLon: 101.64, minLat: 3.09, maxLon: 101.74, maxLat: 3.19),
        zoom: 12
    )

    static let penang = ViewportSeed(
        bbox: BBox(minLon: 100.282, minLat: 5.440, maxLon: 100.306, maxLat: 5.464),
        zoom: 14
    )

    static let penangMid = ViewportSeed(
        bbox: BBox(minLon: 100.276, minLat: 5.434, maxLon: 100.312, maxLat: 5.470),
        zoom: 13
    )

    static let penangWide = ViewportSeed(
        bbox: BBox(minLon: 100.264, minLat: 5.422, maxLon: 100.324, maxLat: 5.482),
        zoom: 12
    )

    static let ocean = ViewportSeed(
        bbox: BBox(minLon: -170, minLat: -10, maxLon: -150, maxLat: 10),
        zoom: 4
    )

    static let uk = ViewportSeed(
        bbox: BBox(minLon: -8.5, minLat: 49.5, maxLon: 2.5, maxLat: 59.5),
        zoom: 6
    )

    static func selected(_ value: String?) -> ViewportSeed {
        switch value {
        case "ocean":
            return .ocean
        case "penang":
            return .penang
        case "penang-mid":
            return .penangMid
        case "penang-wide":
            return .penangWide
        case "uk":
            return .uk
        default:
            return .kl
        }
    }

#if DEBUG
    var fixtureRegionLabel: String {
        if self == .uk {
            return "UK"
        }
        if self == .kl {
            return "Malaysia"
        }
        if self == .penang {
            return "Penang"
        }
        if self == .ocean {
            return "Ocean"
        }
        return "Custom"
    }
#endif
}

struct ViewportCameraRequest: Sendable, Equatable {
    let id: Int
    let viewport: ViewportSeed
}

enum MenuDestination: Hashable {
    case lists
    case offlineMaps
    case settings
    case about
}

enum OfflineDownloadSettings {
    static let allowsCellularDownloadsKey = "offline.downloads.allow-cellular"
    static let defaultAllowsCellularDownloads = false
}

struct DeferredOfflineMaintenanceDownloadRoute {
    let backgroundIdentifier: String
    private let allowsCellularDownloads: Bool
#if DEBUG
    var metadataAllowsCellularDownloadsForTesting: Bool {
        metadataFetcher().allowsCellularDownloadsForTesting
    }

    var objectAllowsCellularDownloadsForTesting: Bool {
        objectFetcher().allowsCellularDownloadsForTesting
    }
#endif

    init(region: String, allowsCellularDownloads: Bool) {
        backgroundIdentifier = OfflineDownloadSession.backgroundIdentifier(region: region)
        self.allowsCellularDownloads = allowsCellularDownloads
    }

    func metadataFetcher() -> HTTPTileFetcher {
        HTTPTileFetcher.offlineForeground(
            allowsCellularDownloads: allowsCellularDownloads
        )
    }

    func objectFetcher() -> HTTPTileFetcher {
        HTTPTileFetcher.offlineBackground(
            identifier: backgroundIdentifier,
            allowsCellularDownloads: allowsCellularDownloads
        )
    }
}

@Observable
final class AppShellModel {
    var isMenuPresented = false
    var deepLinkPath: MenuDestination?
}

struct ListsCopy {
    static func progress(visited: Int, total: Int) -> String {
        guard total > 0 else { return "No places yet" }
        let remaining = max(total - visited, 0)
        if remaining == 0 {
            return "you've been to \(visited) of these · all seen"
        }
        return "you've been to \(visited) of these · \(remaining) to go"
    }
}

struct OfflineDownloadProgress: Sendable, Equatable {
    let region: String?
    let publishVersion: String?
    let completedBytes: Int?
    let totalBytes: Int?
    let fractionComplete: Double
    let isWaitingForConnectivity: Bool

    init(
        region: String? = nil,
        publishVersion: String? = nil,
        completedBytes: Int? = nil,
        totalBytes: Int? = nil,
        fractionComplete: Double,
        isWaitingForConnectivity: Bool = false
    ) {
        self.region = region
        self.publishVersion = publishVersion
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
        self.fractionComplete = fractionComplete
        self.isWaitingForConnectivity = isWaitingForConnectivity
    }

    init(_ progress: OfflineRegionDownloadProgress) {
        region = progress.region
        publishVersion = progress.publishVersion
        completedBytes = progress.completedBytes
        totalBytes = progress.totalBytes
        fractionComplete = progress.fractionComplete
        isWaitingForConnectivity = progress.isWaitingForConnectivity
    }

    var percentComplete: Int {
        Int((boundedFraction * 100).rounded())
    }

    private var boundedFraction: Double {
        guard fractionComplete.isFinite else { return 0 }
        return min(max(fractionComplete, 0), 1)
    }

    var statusText: String {
        if isWaitingForConnectivity {
            return "Waiting for Wi-Fi"
        }
        if let completedBytes, let totalBytes {
            let completed = ByteCountFormatter.string(fromByteCount: Int64(completedBytes), countStyle: .file)
            let total = ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file)
            return "\(completed) of \(total)"
        }
        return "\(percentComplete)%"
    }
}

struct MapBlockingSurface: Equatable {
    let title: String
    let message: String
    let primaryActionTitle: String
    let appStoreURL: URL

    static func resolve(loadState: TileLoadState) -> MapBlockingSurface? {
        guard loadState == .updateRequired else { return nil }
        return MapBlockingSurface(
            title: "Update required",
            message: "This version is too old to read the latest map. Please update Making Tracks in the App Store.",
            primaryActionTitle: "Open App Store",
            appStoreURL: URL(string: "https://apps.apple.com/search?term=Making%20Tracks")!
        )
    }
}

enum MapEmptyRegionSurface: Equatable {
    case unsupportedRegion
    case mapDataUnavailable
    case noPlaces

    static func resolve(
        features: [(MapPlace, PinState)],
        loadState: TileLoadState,
        viewport: ViewportSeed,
        isFixtureMap: Bool,
        isViewportLoading: Bool = false
    ) -> MapEmptyRegionSurface? {
        guard !isFixtureMap, !isViewportLoading, features.isEmpty else { return nil }
        if MapRegion.supportedRegion(for: viewport.bbox) == nil {
            return .unsupportedRegion
        }
        switch loadState {
        case .unavailable:
            return .mapDataUnavailable
        case .ok, .stale, .updateAvailable, .offline:
            return .noPlaces
        case .updateRequired, .manifestInvalid:
            return nil
        }
    }

    var title: String {
        switch self {
        case .unsupportedRegion:
            return "No map for your area yet"
        case .mapDataUnavailable:
            return "Map data unavailable"
        case .noPlaces:
            return "No places here yet"
        }
    }

    var message: String {
        switch self {
        case .unsupportedRegion:
            return "Making Tracks v1 covers the UK and Malaysia."
        case .mapDataUnavailable:
            return "The world map is still available. Check your connection or download a region for offline browsing."
        case .noPlaces:
            return "Try another part of the UK or Malaysia."
        }
    }

    var primaryActionTitle: String? {
        switch self {
        case .mapDataUnavailable:
            return "Offline maps"
        case .unsupportedRegion, .noPlaces:
            return nil
        }
    }
}

extension AppShellModel {
    func openListsDeepLink() {
        deepLinkPath = .lists
        isMenuPresented = true
    }

    func openOfflineMapsDeepLink() {
        deepLinkPath = .offlineMaps
        isMenuPresented = true
    }
}

struct ViewportRefreshTracker: Equatable {
    private(set) var latestRequestID = 0
    private(set) var inFlightRequestID: Int?

    var isLoading: Bool {
        inFlightRequestID != nil
    }

    mutating func nextRequestID() -> Int {
        latestRequestID += 1
        inFlightRequestID = latestRequestID
        return latestRequestID
    }

    mutating func complete(requestID: Int) {
        guard requestID == latestRequestID else { return }
        inFlightRequestID = nil
    }
}

@Observable
@MainActor
final class OfflineRegionDownloadSession {
    var liveProgress: OfflineDownloadProgress?
    var pausedProgress: OfflineDownloadProgress?
    @ObservationIgnored var activeControl: OfflineRegionDownloadControl?
    @ObservationIgnored var activeTask: Task<Void, Never>?
    @ObservationIgnored var activeDownloadID: UUID?

    var rowProgress: OfflineDownloadProgress? {
        liveProgress ?? pausedProgress
    }

    var chromeProgress: OfflineDownloadProgress? {
        liveProgress
    }

    var pausedRegion: String? {
        pausedProgress?.region
    }

    var hasActiveDownload: Bool {
        activeControl != nil || activeTask != nil || liveProgress != nil
    }

    func regionForCancel(fallbackRegion: String? = nil) -> String? {
        fallbackRegion ?? pausedProgress?.region ?? liveProgress?.region
    }

    func isSessionRegion(_ region: String) -> Bool {
        pausedProgress?.region == region || liveProgress?.region == region
    }

    func shouldClearSessionForCancel(fallbackRegion: String? = nil) -> Bool {
        guard let region = regionForCancel(fallbackRegion: fallbackRegion) else { return true }
        return isSessionRegion(region)
    }

    func canBegin(region: String) -> Bool {
        if let pausedRegion {
            let allowed = pausedRegion == region
            MakingTracksLog.downloads.info("ui begin checked region=\(region, privacy: .private(mask: .hash)) pausedRegion=\(pausedRegion, privacy: .private(mask: .hash)) allowed=\(allowed, privacy: .public)")
            return allowed
        }
        let allowed = !hasActiveDownload
        MakingTracksLog.downloads.info("ui begin checked region=\(region, privacy: .private(mask: .hash)) activeDownload=\(!allowed, privacy: .public) allowed=\(allowed, privacy: .public)")
        return allowed
    }

    func begin(region: String, control: OfflineRegionDownloadControl, downloadID: UUID) {
        activeControl?.cancel()
        activeTask?.cancel()
        activeControl = control
        activeTask = nil
        activeDownloadID = downloadID
        pausedProgress = nil
        liveProgress = OfflineDownloadProgress(region: region, publishVersion: nil, completedBytes: 0, totalBytes: nil, fractionComplete: 0)
        MakingTracksLog.downloads.info("ui session began region=\(region, privacy: .private(mask: .hash))")
    }

    func attach(task: Task<Void, Never>) {
        activeTask = task
        MakingTracksLog.downloads.debug("ui session task attached")
    }

    func update(_ progress: OfflineDownloadProgress) {
        liveProgress = progress
        MakingTracksLog.downloads.debug("ui progress updated region=\(progress.region ?? "unknown", privacy: .private(mask: .hash)) version=\(progress.publishVersion ?? "unknown", privacy: .public) percent=\(progress.percentComplete, privacy: .public) bytes=\(progress.completedBytes ?? -1, privacy: .public) total=\(progress.totalBytes ?? -1, privacy: .public)")
    }

    func beginDeferredReplay(
        region: String,
        control: OfflineRegionDownloadControl,
        downloadID: UUID
    ) -> Bool {
        guard activeDownloadID == nil || activeDownloadID == downloadID else { return false }
        if activeDownloadID == nil {
            begin(region: region, control: control, downloadID: downloadID)
        }
        return true
    }

    func updateDeferredReplay(progress: OfflineDownloadProgress, downloadID: UUID) {
        guard activeDownloadID == downloadID else { return }
        update(progress)
    }

    func pauseDeferredReplay(region: String, downloadID: UUID) {
        guard activeDownloadID == downloadID else { return }
        pause(region: region)
    }

    func pause(region: String) {
        pausedProgress = liveProgress ?? pausedProgress ?? OfflineDownloadProgress(region: region, fractionComplete: 0)
        liveProgress = nil
        activeControl = nil
        activeTask = nil
        activeDownloadID = nil
        MakingTracksLog.downloads.info("ui session paused region=\(region, privacy: .private(mask: .hash))")
    }

    func clear() {
        let region = liveProgress?.region ?? pausedProgress?.region ?? "unknown"
        liveProgress = nil
        pausedProgress = nil
        activeControl = nil
        activeTask = nil
        activeDownloadID = nil
        MakingTracksLog.downloads.info("ui session cleared region=\(region, privacy: .private(mask: .hash))")
    }

    func noteDeleted(region: String) {
        guard liveProgress?.region == region || pausedProgress?.region == region else { return }
        activeControl?.cancel()
        activeTask?.cancel()
        clear()
        MakingTracksLog.downloads.info("ui session deleted region=\(region, privacy: .private(mask: .hash))")
    }
}

struct MapScreen: View {
    static let themeStorageKey = "map.theme.id"
    static let pinSizeMultiplierStorageKey = "map.pinSize.multiplier"

    let database: AppDatabase
    let startupViewport: ViewportSeed
    var isFixtureMap = false
    var debugInstallOfflineRegion: String?
    var debugForceTileNetworkOffline = false
    var offlineDownloadProgress: OfflineDownloadProgress?
    var debugCoverageBBoxes: [CoverageBBox] = []
    var debugExposeFixturePinDiagnostics = false
    var onReplayOnboarding: @MainActor () -> Void = {}
    var cameraRequest: ViewportCameraRequest?

    @State private var model: MapScreenModel?
    @StateObject private var locationPermission: LocationPermission
    @AppStorage(Self.themeStorageKey) private var selectedThemeID = MapTheme.definedPaper.id
    @AppStorage(OfflineDownloadSettings.allowsCellularDownloadsKey) private var allowsCellularDownloads = OfflineDownloadSettings.defaultAllowsCellularDownloads
    @AppStorage(Self.pinSizeMultiplierStorageKey) private var pinSizeMultiplier = PinSize.defaultMultiplier
    @Environment(\.scenePhase) private var scenePhase
    @State private var worldPMTilesURL: String? = WorldBasemap.pmtilesURL()
    @State private var features: [(MapPlace, PinState)] = []
    @State private var regionPMTilesURL: String?
    @State private var installedCoverageBBoxes: [CoverageBBox] = []
    @State private var attribution: [Attribution] = []
    @State private var debugOfflineStatus: String?
    @State private var offlineDownloadSession = OfflineRegionDownloadSession()
    @State private var liveOfflineDownloadProgressID: UUID?
    @State private var appShell = AppShellModel()
    @State private var storageMenuStatus = StorageMenuStatus.loading
    @State private var cardPresentation = PlaceCardPresentation()
    @State private var showLayers = false
    @State private var layerVisibility = MapLayerVisibility()
    @State private var appliedShowHiddenPlaces = false
    @State private var loadState: TileLoadState = .unavailable
    @State private var isMapReady = false
    @State private var didMapLoadFail = false
    @State private var mapLoadAttemptID = 0
    @State private var loadedThemeID: String?
    @State private var didSchedulePostFirstRenderManifestRefresh = false
    @State private var didCompletePostFirstRenderManifestRefresh = false
    @State private var didScheduleDeferredOfflineMaintenance = false
    @State private var hasLoadedFixtureFeatures = false
    @State private var viewportRefreshTracker = ViewportRefreshTracker()
    @State private var stateEpoch = 0
    @State private var currentViewport: ViewportSeed?
    @State private var fixtureVisitCount = 0
    @State private var userTrackingMode: MLNUserTrackingMode = .none
    @State private var pendingLocateMeActivation = false
    @State private var hiddenToast: HiddenToast?
    @State private var hiddenToastDismissTask: Task<Void, Never>?
    @State private var nextHiddenToastID = 0
    @State private var activeListMap: ActiveListMap?
    @State private var listCameraRequest: ViewportCameraRequest?
    @State private var nextListCameraRequestID = 10_000
    private let viewportRefreshDebouncer = ViewportRefreshDebouncer()
    @State private var suppressedNearbyPromptPlaceIDs: Set<String> = []
    @State private var nearbyPromptNames: [String: String] = [:]
    @State private var debugProjectedFixturePins: [ProjectedFeatureDiagnostic] = []
    @State private var debugMapUpdateStatus = "not-updated"
    @State private var debugTapStatus = "not-tapped"
    @State private var debugPinLayerSizeStatus = "pin-layer-size:unreported"
    private let locationManager: AppLocationManager
    private static let primaryFixturePlaceID = fixturePlaces[0].placeID
    private static let nearbyPromptDistanceMeters: CLLocationDistance = 125

    init(
        database: AppDatabase,
        startupViewport: ViewportSeed,
        isFixtureMap: Bool = false,
        debugInstallOfflineRegion: String? = nil,
        debugForceTileNetworkOffline: Bool = false,
        offlineDownloadProgress: OfflineDownloadProgress? = nil,
        debugCoverageBBoxes: [CoverageBBox] = [],
        debugExposeFixturePinDiagnostics: Bool = false,
        locationManager: AppLocationManager = AppLocationManager(),
        locationPermission: LocationPermission? = nil,
        cameraRequest: ViewportCameraRequest? = nil,
        onReplayOnboarding: @escaping @MainActor () -> Void = {}
    ) {
        self.database = database
        self.startupViewport = startupViewport
        self.isFixtureMap = isFixtureMap
        self.debugInstallOfflineRegion = debugInstallOfflineRegion
        self.debugForceTileNetworkOffline = debugForceTileNetworkOffline
        self.offlineDownloadProgress = offlineDownloadProgress
        self.debugCoverageBBoxes = debugCoverageBBoxes
        self.debugExposeFixturePinDiagnostics = debugExposeFixturePinDiagnostics
        self.onReplayOnboarding = onReplayOnboarding
        self.cameraRequest = cameraRequest
        self.locationManager = locationManager
        _features = State(initialValue: isFixtureMap ? Self.initialFixtureFeatures() : [])
        _installedCoverageBBoxes = State(initialValue: debugCoverageBBoxes)
        _locationPermission = StateObject(wrappedValue: locationPermission ?? LocationPermission(manager: locationManager))
    }

    var body: some View {
        ZStack {
            MLNMapViewRepresentable(
                worldPMTilesURL: worldPMTilesURL,
                regionPMTilesURL: regionPMTilesURL,
                coverageBBoxes: installedCoverageBBoxes,
                theme: selectedTheme,
                startupViewport: startupViewport,
                features: features,
                visibleCategories: ListMapCategoryVisibility.visibleCategories(
                    discoveryVisibleCategories: layerVisibility.visibleCategories,
                    isListMapActive: activeListMap != nil
                ),
                pinSizeMultiplier: pinSizeMultiplier,
                locationManager: locationManager,
                showsUserLocation: showsUserLocation,
                userTrackingMode: userTrackingMode,
                debugExposeFixturePinDiagnostics: debugExposeFixturePinDiagnostics,
                cameraRequest: listCameraRequest ?? cameraRequest,
                onCameraIdle: { bbox, zoom in
                    Task { @MainActor in
                        currentViewport = ViewportSeed(bbox: bbox, zoom: zoom)
                        if activeListMap == nil {
                            scheduleViewportRefresh(
                                bbox: bbox,
                                zoom: zoom,
                                requestID: nextViewportRequestID(),
                                stateEpoch: currentStateEpoch(),
                                allowManifestRefresh: MapManifestRefreshPolicy.cameraIdleAllowsManifestRefresh(
                                    afterPostFirstRenderRefreshCompleted: didCompletePostFirstRenderManifestRefresh
                                )
                            )
                        }
                    }
                },
                onUserPanned: {
                    Task { @MainActor in
                        userTrackingMode = .none
                    }
                },
                onTapPlace: { placeID in
                    Task { @MainActor in
                        cardPresentation.show(placeID: placeID)
                    }
                },
                onTapEmpty: {
                    Task { @MainActor in
                        cardPresentation.dismiss()
                    }
                },
                onMapReady: { loadedThemeID in
                    Task { @MainActor in
                        guard !isMapReady || didMapLoadFail else { return }
                        isMapReady = true
                        self.loadedThemeID = loadedThemeID
                        didMapLoadFail = false
                        MakingTracksLog.startup.info("overlay transition surface=map state=ready")
                        schedulePostFirstRenderManifestRefresh()
                        scheduleDeferredOfflineMaintenanceIfReady()
                    }
                },
                onFeaturesApplied: {
                    Task { @MainActor in
                        guard !hasLoadedFixtureFeatures else { return }
                        hasLoadedFixtureFeatures = true
                    }
                },
                onStyleWillReload: {
                    Task { @MainActor in
                        isMapReady = false
                        didMapLoadFail = false
                        hasLoadedFixtureFeatures = false
                        loadedThemeID = nil
                        debugProjectedFixturePins = []
                        mapLoadAttemptID += 1
                        let attempt = mapLoadAttemptID
                        MakingTracksLog.startup.info("overlay transition surface=map state=styleReload attempt=\(attempt, privacy: .public)")
                    }
                },
                onMapLoadFailed: {
                    Task { @MainActor in
                        didMapLoadFail = true
                        MakingTracksLog.startup.error("overlay transition surface=map state=failed")
                        if MapManifestRefreshPolicy.mapLoadFailureAllowsManifestRefresh(
                            afterPostFirstRenderRefreshCompleted: didCompletePostFirstRenderManifestRefresh
                        ) {
                            schedulePostFirstRenderManifestRefresh()
                        }
                        scheduleDeferredOfflineMaintenanceIfReady()
                    }
                },
                debugReportProjectedFeatureDiagnostics: { diagnostics in
                    guard debugExposeFixturePinDiagnostics else { return }
                    Task { @MainActor in
                        guard debugProjectedFixturePins != diagnostics else { return }
                        debugProjectedFixturePins = diagnostics
                    }
                },
                debugReportMapUpdateStatus: { status in
                    guard debugExposeFixturePinDiagnostics else { return }
                    Task { @MainActor in
                        guard debugMapUpdateStatus != status else { return }
                        debugMapUpdateStatus = status
                    }
                },
                debugReportTapStatus: { status in
                    guard debugExposeFixturePinDiagnostics else { return }
                    Task { @MainActor in
                        guard debugTapStatus != status else { return }
                        debugTapStatus = status
                    }
                },
                debugReportPinLayerSize: { status in
                    guard debugExposeFixturePinDiagnostics else { return }
                    Task { @MainActor in
                        guard debugPinLayerSizeStatus != status else { return }
                        debugPinLayerSizeStatus = status
                    }
                }
            )
            .ignoresSafeArea()
            .overlay(alignment: .topLeading) {
                shellChrome
                    .padding(.top, 72)
                    .padding(.leading, 16)
            }
            .overlay {
                if didMapLoadFail {
                    ZStack {
                        MapThemeColor.color(hex: selectedTheme.background)
                            .ignoresSafeArea()
                        VStack(spacing: 8) {
                            Image(systemName: "map")
                                .font(.title3)
                            Text("Map unavailable")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        .padding(14)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("map.unavailable")
                    .transition(.opacity)
                } else if isMapLoading {
                    ZStack {
                        MapThemeColor.color(hex: selectedTheme.background)
                            .ignoresSafeArea()
                        ProgressView()
                            .padding(14)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("map.loading")
                    .transition(.opacity)
                }
            }
            .overlay {
                if let surface = emptyRegionSurface, isMapReady, !didMapLoadFail, !isMapLoading, !isViewportLoading {
                    MapEmptyRegionSurfaceView(surface: surface) {
                        appShell.openOfflineMapsDeepLink()
                    }
                    .allowsHitTesting(surface.primaryActionTitle != nil)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 32)
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isMapLoading)
            .animation(.easeInOut(duration: 0.2), value: didMapLoadFail)
#if DEBUG
            .overlay(alignment: .topLeading) {
                if isFixtureMap && debugExposeFixturePinDiagnostics {
                    VStack(alignment: .leading, spacing: 2) {
                        if hasLoadedFixtureFeatures {
                            Text(verbatim: "applied")
                                .font(.system(size: 8))
                                .foregroundStyle(.red)
                                .frame(width: 44, height: 18)
                                .accessibilityIdentifier("map.features-applied")
                                .allowsHitTesting(false)
                        }

                        ForEach(debugProjectedFixturePins) { pin in
                            Text(verbatim: pin.isHitTestable ? "hit" : "miss")
                                .font(.system(size: 8))
                                .foregroundStyle(.red)
                                .frame(width: 96, height: 18, alignment: .leading)
                                .accessibilityIdentifier("map.fixture-pin.\(pin.placeID)")
                                .accessibilityValue(
                                    "x:\(pin.normalizedX.formatted(.number.precision(.fractionLength(6)))) y:\(pin.normalizedY.formatted(.number.precision(.fractionLength(6))))"
                                )
                                .allowsHitTesting(false)
                            }
                    }
                    .allowsHitTesting(false)
                }
            }
#endif
            .overlay(alignment: .topTrailing) {
                statusChrome
                    .padding(.top, 72)
                    .padding(.trailing, 16)
            }
            .overlay(alignment: .bottomLeading) {
                attributionText
                    .padding(.leading, 16)
                    .padding(.bottom, 16)
            }
            .overlay(alignment: .bottomTrailing) {
                locationChrome
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
            }
            .overlay(alignment: .bottom) {
                if let prompt = nearbyPromptCandidate {
                    nearbyPromptView(for: prompt)
                        .padding(.bottom, 88)
                        .padding(.horizontal, 16)
                }
            }
            .overlay(alignment: .bottom) {
                if let hiddenToast {
                    hiddenToastView(for: hiddenToast)
                        .padding(.bottom, 24)
                        .padding(.horizontal, 16)
                }
            }
        }
        .sheet(isPresented: $appShell.isMenuPresented) {
            AppMenuSheet(
                shell: appShell,
                model: model,
                attribution: attribution,
                selectedThemeID: $selectedThemeID,
                pinSizeMultiplier: $pinSizeMultiplier,
                seededOfflineDownloadProgress: offlineDownloadProgress,
                offlineDownloadSession: offlineDownloadSession,
                locationStatus: locationMenuStatus,
                storageStatus: storageMenuStatus,
                openLocationSettings: openLocationSettings,
                replayOnboarding: onReplayOnboarding,
                onOfflineMapsChanged: refreshAfterOfflineMapsChanged,
                onShowListOnMap: { list in
                    Task { @MainActor in
                        appShell.isMenuPresented = false
                        await showListOnMap(list)
                    }
                },
                onListRenamed: { list in
                    reconcileActiveListMap(renamed: list)
                },
                onListDeleted: { listID in
                    Task { @MainActor in
                        await clearActiveListMap(deletedListID: listID)
                    }
                }
            )
        }
        .fullScreenCover(isPresented: updateRequiredPresentationBinding) {
            if let surface = updateRequiredSurface {
                UpdateRequiredBlockingView(surface: surface)
                    .interactiveDismissDisabled(true)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            LocationSessionPolicies.handleScenePhaseChange(
                newPhase,
                userTrackingMode: &userTrackingMode,
                stopUpdatingLocation: { locationManager.stopUpdatingLocation() },
                stopUpdatingHeading: { locationManager.stopUpdatingHeading() }
            )
        }
        .onChange(of: locationPermission.authorizationStatus) { _, newStatus in
            LocationSessionPolicies.handleAuthorizationStatusChange(
                newStatus,
                userTrackingMode: &userTrackingMode,
                pendingLocateMeActivation: &pendingLocateMeActivation
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in
            scheduleDeferredOfflineMaintenanceIfReady()
        }
        .task(id: mapLoadAttemptID) {
            guard isMapLoading else { return }
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if isMapLoading {
                    didMapLoadFail = true
                    let attempt = mapLoadAttemptID
                    MakingTracksLog.startup.error("overlay transition surface=map state=timeout attempt=\(attempt, privacy: .public)")
                    scheduleDeferredOfflineMaintenanceIfReady()
                }
            }
        }
        .task {
            await start()
            Task { await refreshStorageMenuStatus() }
            if let model {
                await observeChanges(from: model)
            }
        }
        .onChange(of: appShell.isMenuPresented) { _, isPresented in
            guard isPresented else { return }
            Task { await refreshStorageMenuStatus() }
        }
        .onChange(of: layerVisibility) { _, visibility in
            Task { @MainActor in
                await applyLayerVisibility(visibility)
            }
        }
        .sheet(isPresented: $showLayers) {
            LayersSheet(
                visibility: $layerVisibility
            )
                .presentationDetents([.medium, .large])
        }
        .sheet(item: cardPresentationItemBinding) { presentation in
            PlaceCardSheet(
                placeID: presentation.placeID,
                model: model,
                onHide: { placeID, name in
                    showHiddenToast(placeID: placeID, name: name)
                },
                showHiddenMode: layerVisibility.showHiddenPlaces
            )
        }
        .onDisappear {
            cancelHiddenToastDismissTask()
        }
    }

    private var cardPresentationItemBinding: Binding<PlaceCardPresentation.Item?> {
        Binding(
            get: { cardPresentation.item },
            set: { item in
                if item == nil {
                    cardPresentation.dismiss()
                }
            }
        )
    }

    private func showHiddenToast(placeID: String, name: String) {
        nextHiddenToastID += 1
        let toast = HiddenToast(id: nextHiddenToastID, placeID: placeID, name: name)
        hiddenToast = toast
        UIAccessibility.post(notification: .announcement, argument: "\(name) hidden. Undo available.")
        cancelHiddenToastDismissTask()
        hiddenToastDismissTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if hiddenToast == toast {
                    hiddenToast = nil
                    hiddenToastDismissTask = nil
                }
            }
        }
    }

    private func undoHiddenToast() async {
        guard let toast = hiddenToast, let model else { return }
        do {
            try await model.setHidden(placeID: toast.placeID, hidden: false)
            await MainActor.run {
                guard hiddenToast == toast else { return }
                cancelHiddenToastDismissTask()
                self.hiddenToast = nil
                UIAccessibility.post(notification: .announcement, argument: "\(toast.name) restored.")
            }
        } catch {
            return
        }
    }

    private func cancelHiddenToastDismissTask() {
        hiddenToastDismissTask?.cancel()
        hiddenToastDismissTask = nil
    }

    private func hiddenToastView(for _: HiddenToast) -> some View {
        HStack(spacing: 10) {
            Text(verbatim: "Hidden — Undo")
                .font(.callout.weight(.medium))
            Button("Undo") {
                Task { await undoHiddenToast() }
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("place-card.hide.undo")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
    }

    private var isMapLoading: Bool {
        guard !didMapLoadFail else { return false }
        return !isMapReady || (isFixtureMap && !hasLoadedFixtureFeatures)
    }

    private var isViewportLoading: Bool {
        viewportRefreshTracker.isLoading
    }

    private var updateRequiredSurface: MapBlockingSurface? {
        MapBlockingSurface.resolve(loadState: loadState)
    }

    private var updateRequiredPresentationBinding: Binding<Bool> {
        Binding(
            get: { updateRequiredSurface != nil },
            set: { _ in }
        )
    }

    private var emptyRegionSurface: MapEmptyRegionSurface? {
        MapEmptyRegionSurface.resolve(
            features: features,
            loadState: loadState,
            viewport: currentViewport ?? startupViewport,
            isFixtureMap: isFixtureMap,
            isViewportLoading: isViewportLoading
        )
    }

    private var mapChrome: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if loadState != .ok {
                Text(verbatim: loadState.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
            }

            if isFixtureMap {
#if DEBUG
                Text(verbatim: "Startup region: \(startupViewport.fixtureRegionLabel)")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .accessibilityIdentifier("map.startup-region")
#endif

                Text(verbatim: "Tracks visits: \(fixtureVisitCount)")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .accessibilityIdentifier("tracks.visit-count.\(Self.primaryFixturePlaceID)")
#if DEBUG
                Text(verbatim: "Loaded theme: \(loadedThemeID ?? "loading")")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .accessibilityIdentifier("map.loaded-theme")

                HStack(spacing: 6) {
                    if debugExposeFixturePinDiagnostics {
                        Button("Open fixture") {
                            cardPresentation.show(placeID: Self.primaryFixturePlaceID)
                        }
                        .font(.caption2)
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("debug.open-fixture")
                    }

                    Button("Hide fixture") {
                        Task { await setPrimaryFixtureHidden(true) }
                    }
                    .font(.caption2)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("debug.hide-fixture")

                    Button("Unhide fixture") {
                        Task { await setPrimaryFixtureHidden(false) }
                    }
                    .font(.caption2)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("debug.unhide-fixture")
                }
                Text(verbatim: "Fixture hidden: \(isPrimaryFixtureHidden ? "true" : "false")")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .accessibilityIdentifier("debug.fixture-hidden-state")
#endif
            }

#if DEBUG
            if debugExposeFixturePinDiagnostics {
                Text(verbatim: "ready:\(isMapReady) applied:\(hasLoadedFixtureFeatures) features:\(features.count)")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .accessibilityIdentifier("map.debug-readiness")

                Text(verbatim: debugMapUpdateStatus)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .accessibilityIdentifier("map.debug-source-status")

                Text(verbatim: debugTapStatus)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .accessibilityIdentifier("map.debug-tap-status")

                Text(verbatim: "theme:\(selectedTheme.id)")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .accessibilityIdentifier("map.debug-theme")

                Text(verbatim: "pin-size:\(PinSize(multiplier: pinSizeMultiplier).accessibilityValue)")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .accessibilityIdentifier("map.debug-pin-size")

                Text(verbatim: debugPinLayerSizeStatus)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .accessibilityIdentifier("map.debug-pin-layer-size")

                Text(verbatim: "coverage-bboxes:\(installedCoverageBBoxes.count)")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .accessibilityIdentifier("map.debug-coverage")
            }

            if let debugOfflineStatus {
                Text(verbatim: debugOfflineStatus)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .accessibilityIdentifier("debug.offline-status")
            }
#endif
        }
    }

    private var statusChrome: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if let activeListMap {
                listMapChrome(activeListMap)
            }
            mapChrome
        }
    }

    private var selectedTheme: MapTheme {
        MapTheme.named(selectedThemeID)
    }

#if DEBUG
    private var isPrimaryFixtureHidden: Bool {
        model?.hiddenIDs.contains(Self.primaryFixturePlaceID) ?? false
    }
#endif

    private var shellChrome: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                appShell.deepLinkPath = nil
                appShell.isMenuPresented = true
            } label: {
                Image(systemName: MapHomeChromeSpec.menuSymbolName)
                    .font(.system(size: MapHomeChromeSpec.menuGlyphPointSize, weight: .bold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(mapBareGlyphStyle)
                    .mapChromeGlyphHalo()
                    .frame(width: MapHomeChromeSpec.hitTargetSide, height: MapHomeChromeSpec.hitTargetSide)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Menu")
            .accessibilityHint("Opens app menu")
            .accessibilityIdentifier("map.menu")

            if let offlineDownloadProgress = currentOfflineDownloadProgress {
                Button {
                    appShell.deepLinkPath = .offlineMaps
                    appShell.isMenuPresented = true
                } label: {
                    Label(
                        offlineDownloadProgress.isWaitingForConnectivity
                            ? "Offline maps \(offlineDownloadProgress.statusText)"
                            : "Offline maps \(offlineDownloadProgress.percentComplete)%",
                        systemImage: "arrow.down.circle"
                    )
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                .accessibilityIdentifier("map.download-progress")
            }

            layersButton
        }
    }

    @ViewBuilder
    private func listMapChrome(_ list: ActiveListMap) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            Text(verbatim: list.name)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .accessibilityIdentifier("map.list-mode.title")

            Picker("List map mode", selection: listMapShowVisitedBinding) {
                Text("Fresh snow").tag(false)
                Text("My tracks").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 190)
            .accessibilityIdentifier("map.list-mode.toggle")

            Button {
                Task { @MainActor in
                    activeListMap = nil
                    listCameraRequest = nil
                    await refreshCurrentViewport()
                }
            } label: {
                Label("Close list", systemImage: "xmark")
                    .labelStyle(.iconOnly)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("map.list-mode.close")
        }
    }

    private var listMapShowVisitedBinding: Binding<Bool> {
        Binding(
            get: { activeListMap?.showVisited ?? true },
            set: { showVisited in
                guard var list = activeListMap else { return }
                list.showVisited = showVisited
                activeListMap = list
                Task { @MainActor in
                    await refreshActiveListMap()
                }
            }
        )
    }

    private var attributionText: some View {
        Text(verbatim: "© OpenStreetMap")
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .accessibilityLabel("OpenStreetMap attribution")
            .accessibilityIdentifier("map.openstreetmap-attribution")
    }

    private var currentOfflineDownloadProgress: OfflineDownloadProgress? {
        offlineDownloadSession.chromeProgress ?? offlineDownloadProgress
    }

    private var locationMenuStatus: LocationMenuStatus {
        LocationMenuStatus(
            label: locationPermission.isLocationOff ? "Location off" : "Location available",
            canOpenSettings: locationPermission.isLocationOff
        )
    }

    private func refreshStorageMenuStatus() async {
        guard let model else {
            storageMenuStatus = .unavailable
            installedCoverageBBoxes = debugCoverageBBoxes
            MakingTracksLog.startup.info("storage status state=unavailable")
            return
        }
        storageMenuStatus = .loading
        MakingTracksLog.startup.debug("storage status state=loading")
        async let nextStorageMenuStatus = model.storageMenuStatus()
        async let nextInstalledCoverageBBoxes = model.installedOfflineCoverageBBoxes(for: OfflineRegionCatalog.debugFixture)
        storageMenuStatus = await nextStorageMenuStatus
        installedCoverageBBoxes = debugCoverageBBoxes + (await nextInstalledCoverageBBoxes)
        let statusKind = storageMenuStatus.kind.logLabel
        let regionCount = storageMenuStatus.regions.count
        let failedCount = storageMenuStatus.failedRegions.count
        let totalBytes = storageMenuStatus.totalBytes
        MakingTracksLog.startup.info("storage status state=\(statusKind, privacy: .public) regions=\(regionCount, privacy: .public) failed=\(failedCount, privacy: .public) bytes=\(totalBytes, privacy: .public)")
    }

    @MainActor
    private func schedulePostFirstRenderManifestRefresh() {
        guard !didSchedulePostFirstRenderManifestRefresh else { return }
        didSchedulePostFirstRenderManifestRefresh = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await refreshManifestAndMapState()
        }
    }

    @MainActor
    private func scheduleDeferredOfflineMaintenanceIfReady() {
        guard MapDeferredOfflineMaintenancePolicy.allowsDeferredMaintenance(
            isMapReady: isMapReady,
            didMapLoadFail: didMapLoadFail,
            didScheduleMaintenance: didScheduleDeferredOfflineMaintenance,
            isProtectedDataAvailable: UIApplication.shared.isProtectedDataAvailable,
            hasPausedDownload: offlineDownloadSession.pausedRegion != nil,
            hasActiveDownload: offlineDownloadSession.hasActiveDownload
        )
        else { return }
        didScheduleDeferredOfflineMaintenance = true
        MakingTracksLog.gc.info("deferred maintenance scheduled")
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            guard UIApplication.shared.isProtectedDataAvailable else {
                didScheduleDeferredOfflineMaintenance = false
                MakingTracksLog.gc.info("deferred maintenance deferred reason=protected-data")
                return
            }
            guard offlineDownloadSession.pausedRegion == nil else {
                didScheduleDeferredOfflineMaintenance = false
                MakingTracksLog.gc.info("deferred maintenance deferred reason=paused-download")
                return
            }
            guard !offlineDownloadSession.hasActiveDownload else {
                didScheduleDeferredOfflineMaintenance = false
                MakingTracksLog.gc.info("deferred maintenance deferred reason=active-download")
                return
            }
            let replayControl = OfflineRegionDownloadControl()
            let replayDownloadID = UUID()
            let didPerformMaintenance = await model?.performDeferredOfflineMaintenance(
                allowsCellularDownloads: allowsCellularDownloads,
                control: replayControl,
                onReplayRegionStart: { region in
                    offlineDownloadSession.beginDeferredReplay(
                        region: region,
                        control: replayControl,
                        downloadID: replayDownloadID
                    )
                },
                onReplayRegionPause: { region in
                    offlineDownloadSession.pauseDeferredReplay(region: region, downloadID: replayDownloadID)
                }
            ) { progress in
                offlineDownloadSession.updateDeferredReplay(
                    progress: OfflineDownloadProgress(progress),
                    downloadID: replayDownloadID
                )
            } ?? true
            if !didPerformMaintenance || !UIApplication.shared.isProtectedDataAvailable {
                if !didPerformMaintenance {
                    replayControl.cancel()
                    if offlineDownloadSession.activeDownloadID == replayDownloadID {
                        offlineDownloadSession.clear()
                    }
                }
                didScheduleDeferredOfflineMaintenance = false
                let reason = didPerformMaintenance ? "protected-data" : "failed"
                MakingTracksLog.gc.info("deferred maintenance retry scheduled reason=\(reason, privacy: .public)")
                return
            }
            if offlineDownloadSession.activeDownloadID == replayDownloadID {
                offlineDownloadSession.clear()
            }
            await refreshStorageMenuStatus()
            MakingTracksLog.gc.info("deferred maintenance storage refreshed")
        }
    }

    @MainActor
    private func refreshManifestAndMapState() async {
        await model?.refreshManifest()
        let nextRegionPMTilesURL = await model?.pmtilesURL
        let nextAttribution = await model?.attribution ?? []
        let nextLoadState = await model?.loadState ?? .unavailable
        regionPMTilesURL = nextRegionPMTilesURL
        attribution = nextAttribution
        loadState = nextLoadState
        didCompletePostFirstRenderManifestRefresh = true
        await refreshCurrentViewport()
    }

    @MainActor
    private func refreshAfterOfflineMapsChanged() async {
        MakingTracksLog.startup.info("offline refresh started")
        await model?.refreshManifest()
        await refreshCurrentViewport()
        await refreshStorageMenuStatus()
        MakingTracksLog.startup.info("offline refresh finished")
    }

    private var layersButton: some View {
        Button {
            showLayers = true
        } label: {
            layersIcon
                .frame(width: MapHomeChromeSpec.hitTargetSide, height: MapHomeChromeSpec.hitTargetSide)
                .background(layerVisibility.isDefault ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color.accentColor), in: Circle())
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Layers")
        .accessibilityHint("Shows map layer controls")
        .accessibilityValue(layerVisibility.isDefault ? "Default" : "Custom")
        .accessibilityIdentifier("map.layers")
    }

    @ViewBuilder
    private var layersIcon: some View {
        let icon = Image(systemName: MapHomeChromeSpec.layersSymbolName(isActive: !layerVisibility.isDefault))
            .font(.title3)
            .foregroundStyle(layerVisibility.isDefault ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.white))
        if layerVisibility.isDefault {
            icon.mapChromeGlyphHalo()
        } else {
            icon
        }
    }

    private var mapBareGlyphStyle: AnyShapeStyle {
        // Current map themes are light paper palettes; revisit this if a dark basemap theme lands.
        AnyShapeStyle(Color.black)
    }

    private var locationChrome: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if locationPermission.isLocationOff {
                locationOffBanner
            }

            locateMeButton
        }
    }

    private var locationOffBanner: some View {
        HStack(spacing: 8) {
            Text("Location is off")
                .font(.caption2)
                .fontWeight(.semibold)

            LocationSettingsButton {
                openLocationSettings()
            }
            .frame(width: 68, height: 16)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var locateMeButton: some View {
        Button {
            handleLocateMeTap()
        } label: {
            Image(systemName: locateMeButtonSystemName)
                .font(.title3)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
        }
        .accessibilityLabel(locateMeButtonAccessibilityLabel)
        .accessibilityHint("Centers the map on your location")
        .accessibilityIdentifier("map.locate-me")
    }

    private var locateMeButtonSystemName: String {
        switch userTrackingMode {
        case .none:
            return "location"
        case .follow:
            return "location.fill"
        case .followWithHeading:
            return "location.north.line"
        default:
            return "location"
        }
    }

    private var locateMeButtonAccessibilityLabel: String {
        switch userTrackingMode {
        case .none:
            return "Locate me"
        case .follow:
            return "Follow me"
        case .followWithHeading:
            return "Follow me with heading"
        default:
            return "Locate me"
        }
    }

    private var nearbyPromptCandidate: NearbyPromptCandidate? {
        guard showsUserLocation,
              userTrackingMode != .none,
              let coordinate = locationPermission.currentCoordinate
        else { return nil }

        guard let candidate = NearbyPromptSelector.candidate(
            features: features,
            names: nearbyPromptNames,
            userLatitude: coordinate.latitude,
            userLongitude: coordinate.longitude,
            maxDistanceMeters: Self.nearbyPromptDistanceMeters,
            suppressedPlaceIDs: suppressedNearbyPromptPlaceIDs,
            hiddenPlaceIDs: model?.hiddenIDs ?? []
        ) else { return nil }
        return NearbyPromptCandidate(
            placeID: candidate.placeID,
            name: candidate.name,
            distanceMeters: candidate.distanceMeters
        )
    }

    @ViewBuilder
    private func nearbyPromptView(for prompt: NearbyPromptCandidate) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(verbatim: "You're near \(prompt.name) — seen it?")
                .font(.caption2)
                .fontWeight(.semibold)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button("Seen it") {
                handleNearbyPromptSeen(prompt)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("map.nearby-prompt.seen")

            Button {
                suppressedNearbyPromptPlaceIDs.insert(prompt.placeID)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Dismiss nearby prompt")
            .accessibilityIdentifier("map.nearby-prompt.dismiss")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map.nearby-prompt")
    }

    private func start() async {
        let startedAt = Date()
        let fixture = isFixtureMap
        MakingTracksLog.startup.info("map start started fixture=\(fixture, privacy: .public)")
        if model == nil {
            model = try? MapScreenModel(
                database: database,
                fixturePlaces: isFixtureMap ? Self.fixturePlaces : [],
                forceTileNetworkOffline: debugForceTileNetworkOffline
            )
            let hasModel = model != nil
            MakingTracksLog.startup.info("map model initialized available=\(hasModel, privacy: .public)")
        }
        model?.setShowHidden(layerVisibility.showHiddenPlaces)
        appliedShowHiddenPlaces = layerVisibility.showHiddenPlaces
#if DEBUG
        if let debugInstallOfflineRegion, let model {
            let progressID = UUID()
            await MainActor.run {
                debugOfflineStatus = "Installing \(debugInstallOfflineRegion)"
                liveOfflineDownloadProgressID = progressID
                offlineDownloadSession.update(OfflineDownloadProgress(fractionComplete: 0))
            }
            let status = await model.installDebugOfflineRegion(
                debugInstallOfflineRegion,
                allowsCellularDownloads: allowsCellularDownloads
            ) { progress in
                Task { @MainActor in
                    guard liveOfflineDownloadProgressID == progressID else { return }
                    offlineDownloadSession.update(OfflineDownloadProgress(progress))
                }
            }
            await MainActor.run {
                debugOfflineStatus = status
                if liveOfflineDownloadProgressID == progressID {
                    liveOfflineDownloadProgressID = nil
                    offlineDownloadSession.clear()
                }
            }
        } else if debugForceTileNetworkOffline {
            await MainActor.run {
                debugOfflineStatus = "Network disabled"
            }
        }
#endif
        await refreshViewport(
            bbox: startupViewport.bbox,
            zoom: startupViewport.zoom,
            requestID: nextViewportRequestID(),
            stateEpoch: currentStateEpoch(),
            allowManifestRefresh: MapManifestRefreshPolicy.startupAllowsManifestRefresh
        )
        await refreshFixtureVisitCount()
        let elapsedMS = Int(Date().timeIntervalSince(startedAt) * 1000)
        let finalState = loadState.rawValue
        let featureCount = features.count
        MakingTracksLog.startup.info("map start finished state=\(finalState, privacy: .public) features=\(featureCount, privacy: .public) durationMS=\(elapsedMS, privacy: .public)")
    }

    @MainActor
    private func handleLocateMeTap() {
        LocationSessionPolicies.handleLocateMeTap(
            authorizationStatus: locationPermission.authorizationStatus,
            userTrackingMode: &userTrackingMode,
            requestCurrentLocation: { locationPermission.requestCurrentLocation() },
            openSettings: { openLocationSettings() },
            deferFollowUntilAuthorized: { pendingLocateMeActivation = true }
        )
    }

    @MainActor
    private func scheduleViewportRefresh(
        bbox: BBox,
        zoom: Int,
        requestID: Int,
        stateEpoch capturedStateEpoch: Int,
        allowManifestRefresh: Bool = true
    ) {
        viewportRefreshDebouncer.schedule { [bbox, zoom, requestID, capturedStateEpoch, allowManifestRefresh] in
            await refreshViewport(
                bbox: bbox,
                zoom: zoom,
                requestID: requestID,
                stateEpoch: capturedStateEpoch,
                allowManifestRefresh: allowManifestRefresh
            )
        }
    }

    @MainActor
    private func handleNearbyPromptSeen(_ prompt: NearbyPromptCandidate) {
        suppressedNearbyPromptPlaceIDs.insert(prompt.placeID)
        Task { @MainActor in
            do {
                try await model?.setVisited(placeID: prompt.placeID, visited: true)
            } catch {
                suppressedNearbyPromptPlaceIDs.remove(prompt.placeID)
                assertionFailure("Failed to persist nearby prompt seen state: \(error)")
            }
        }
    }

#if DEBUG
    @MainActor
    private func setPrimaryFixtureHidden(_ hidden: Bool) async {
        do {
            try await model?.setHidden(placeID: Self.primaryFixturePlaceID, hidden: hidden)
        } catch {
            assertionFailure("Failed to persist fixture hidden state: \(error)")
        }
    }
#endif

    private func openLocationSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(settingsURL)
    }

    @MainActor
    private func nextViewportRequestID() -> Int {
        viewportRefreshTracker.nextRequestID()
    }

    @MainActor
    private func currentStateEpoch() -> Int {
        stateEpoch
    }

    private var showsUserLocation: Bool {
        LocationSessionPolicies.shouldShowUserLocation(
            authorizationStatus: locationPermission.authorizationStatus,
            userTrackingMode: userTrackingMode
        )
    }

    private func refreshViewport(
        bbox: BBox,
        zoom: Int,
        requestID: Int,
        stateEpoch capturedStateEpoch: Int,
        allowManifestRefresh: Bool = true
    ) async {
        guard activeListMap == nil else { return }
        guard let model else { return }
        let startedAt = Date()
        MakingTracksLog.resolution.debug("viewport refresh started request=\(requestID, privacy: .public) zoom=\(zoom, privacy: .public)")
        let next = await model.features(in: bbox, zoom: zoom, allowManifestRefresh: allowManifestRefresh)
        let nextRegionPMTilesURL = await model.pmtilesURL
        let nextAttribution = await model.attribution
        let nextLoadState = await model.loadState
        var nextNearbyPromptNames: [String: String] = [:]
        for (place, _) in next {
            if let card = await model.cardModel(for: place.id) {
                nextNearbyPromptNames[place.id] = card.name
            }
        }
        await MainActor.run {
            guard requestID == viewportRefreshTracker.latestRequestID else { return }
            viewportRefreshTracker.complete(requestID: requestID)
            if capturedStateEpoch == stateEpoch {
                features = next
                nearbyPromptNames = nextNearbyPromptNames
                currentViewport = ViewportSeed(bbox: bbox, zoom: zoom)
            }
            regionPMTilesURL = nextRegionPMTilesURL
            attribution = nextAttribution
            loadState = nextLoadState
            let elapsedMS = Int(Date().timeIntervalSince(startedAt) * 1000)
            let stateLabel = nextLoadState.rawValue
            let featureCount = next.count
            let hasRegionalBasemap = nextRegionPMTilesURL != nil
            MakingTracksLog.resolution.info("viewport refresh finished request=\(requestID, privacy: .public) state=\(stateLabel, privacy: .public) features=\(featureCount, privacy: .public) regionalBasemap=\(hasRegionalBasemap, privacy: .public) durationMS=\(elapsedMS, privacy: .public)")
        }
    }

    @MainActor
    private func refreshCurrentViewport() async {
        stateEpoch += 1
        guard activeListMap == nil else {
            await refreshActiveListMap()
            return
        }
        let viewport = currentViewport ?? startupViewport
        await refreshViewport(
            bbox: viewport.bbox,
            zoom: viewport.zoom,
            requestID: nextViewportRequestID(),
            stateEpoch: currentStateEpoch()
        )
    }

    private func observeChanges(from model: MapScreenModel) async {
        for await ids in model.changes {
            if activeListMap != nil {
                await refreshActiveListMap()
                await refreshFixtureVisitCount()
                continue
            }
            if model.consumeHiddenMembershipChange(overlapping: ids) {
                let refresh = await MainActor.run { () -> (viewport: ViewportSeed, requestID: Int, stateEpoch: Int) in
                    stateEpoch += 1
                    return (
                        viewport: currentViewport ?? startupViewport,
                        requestID: nextViewportRequestID(),
                        stateEpoch: currentStateEpoch()
                    )
                }
                await refreshViewport(
                    bbox: refresh.viewport.bbox,
                    zoom: refresh.viewport.zoom,
                    requestID: refresh.requestID,
                    stateEpoch: refresh.stateEpoch
                )
                await refreshFixtureVisitCount()
                continue
            }
            let states = await model.states(for: ids)
            await MainActor.run {
                stateEpoch += 1
                features = features.map { place, state in
                    (place, states[place.id] ?? state)
                }
            }
            await refreshFixtureVisitCount()
        }
    }

    private func refreshFixtureVisitCount() async {
        guard isFixtureMap, let model else { return }
        let count = await model.visitCount(placeID: Self.primaryFixturePlaceID)
        await MainActor.run {
            fixtureVisitCount = count
        }
    }

    @MainActor
    private func applyLayerVisibility(_ visibility: MapLayerVisibility) async {
        guard visibility.showHiddenPlaces != appliedShowHiddenPlaces else { return }
        guard let model else { return }
        model.setShowHidden(visibility.showHiddenPlaces)
        appliedShowHiddenPlaces = visibility.showHiddenPlaces
        guard activeListMap == nil else {
            await refreshActiveListMap()
            return
        }
        await refreshCurrentViewport()
    }

    @MainActor
    private func showListOnMap(_ list: PlaceList) async {
        guard let id = list.id else { return }
        activeListMap = ActiveListMap(listID: id, name: list.name, showVisited: true)
        await refreshActiveListMap(updateCamera: true)
    }

    @MainActor
    private func refreshActiveListMap(updateCamera: Bool = false) async {
        guard let model, let list = activeListMap else { return }
        let next = await model.listMapFeatures(
            listID: list.listID,
            showVisited: list.showVisited
        )
        guard let currentList = activeListMap,
              currentList.listID == list.listID,
              currentList.showVisited == list.showVisited
        else { return }
        features = next
        nearbyPromptNames = [:]
        stateEpoch += 1
        if updateCamera, let viewport = Self.viewport(for: next.map(\.0)) {
            nextListCameraRequestID += 1
            listCameraRequest = ViewportCameraRequest(id: nextListCameraRequestID, viewport: viewport)
            currentViewport = viewport
        }
    }

    @MainActor
    private func reconcileActiveListMap(renamed list: PlaceList) {
        guard let id = list.id,
              var active = activeListMap,
              active.listID == id
        else { return }
        active.name = list.name
        activeListMap = active
    }

    @MainActor
    private func clearActiveListMap(deletedListID listID: Int64) async {
        guard activeListMap?.listID == listID else { return }
        activeListMap = nil
        listCameraRequest = nil
        await refreshCurrentViewport()
    }

    private static func viewport(for places: [MapPlace]) -> ViewportSeed? {
        guard let first = places.first else { return nil }
        var minLon = first.lon
        var maxLon = first.lon
        var minLat = first.lat
        var maxLat = first.lat
        for place in places.dropFirst() {
            minLon = min(minLon, place.lon)
            maxLon = max(maxLon, place.lon)
            minLat = min(minLat, place.lat)
            maxLat = max(maxLat, place.lat)
        }
        let lonPad = max((maxLon - minLon) * 0.18, 0.01)
        let latPad = max((maxLat - minLat) * 0.18, 0.01)
        return ViewportSeed(
            bbox: BBox(
                minLon: minLon - lonPad,
                minLat: minLat - latPad,
                maxLon: maxLon + lonPad,
                maxLat: maxLat + latPad
            ),
            zoom: places.count == 1 ? 14 : 12
        )
    }

    private struct NearbyPromptCandidate {
        let placeID: String
        let name: String
        let distanceMeters: CLLocationDistance
    }

    private struct HiddenToast: Equatable {
        let id: Int
        let placeID: String
        let name: String
    }

    private struct ActiveListMap: Equatable {
        let listID: Int64
        var name: String
        var showVisited: Bool
    }

    private static let fixturePlaces = [
        try! PlaceRef(
            placeID: "mt1_00000000000000000000000000",
            name: "Ghost Sign",
            lat: 3.14,
            lon: 101.69,
            category: "attraction",
            tier: 3,
            schemaVersion: 1,
            fetchedAt: Date(timeIntervalSince1970: 0),
            rawJSON: """
            {"blurb":"A hand-painted sign still visible above the old shopfront.","category":"attraction","lat":3.14,"lon":101.69,"name":"Ghost Sign","place_id":"mt1_00000000000000000000000000","score":0.5,"source_refs":["osm:node/1"],"tier":3}
            """
        ),
        try! PlaceRef(
            placeID: "mt1_00000000000000000000000001",
            name: "Art Deco Cinema",
            lat: 3.16,
            lon: 101.702,
            category: "historic_building",
            tier: 3,
            schemaVersion: 1,
            fetchedAt: Date(timeIntervalSince1970: 0),
            rawJSON: """
            {"blurb":"A restored neighborhood cinema with stepped plasterwork and neon trim.","category":"historic_building","lat":3.16,"lon":101.702,"name":"Art Deco Cinema","place_id":"mt1_00000000000000000000000001","score":0.5,"source_refs":["osm:node/2"],"tier":3}
            """
        ),
    ]

    private static func initialFixtureFeatures() -> [(MapPlace, PinState)] {
        fixturePlaces.map { fixturePlace in
            (
                MapPlace(
                    id: fixturePlace.placeID,
                    lat: fixturePlace.lat,
                    lon: fixturePlace.lon,
                    tier: fixturePlace.tier,
                    category: fixturePlace.category
                ),
                PinState(saved: false, visit: .none)
            )
        }
    }
}

private struct LocationMenuStatus: Sendable {
    let label: String
    let canOpenSettings: Bool
}

struct StorageMenuRegion: Identifiable, Equatable, Sendable {
    let region: String
    let publishVersion: String
    let bytes: Int
    let tileCount: Int

    var id: String { region }
    var title: String { region }
    var bytesText: String { StorageMenuStatus.formatBytes(bytes) }

    var detail: String {
        "\(publishVersion) · \(tileCount) \(tileCount == 1 ? "tile" : "tiles")"
    }
}

struct StorageMenuStatus: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case loading
        case unavailable
        case ready
    }

    let kind: Kind
    let totalBytes: Int
    let regions: [StorageMenuRegion]
    let failedRegions: [String]

    static let loading = StorageMenuStatus(kind: .loading, totalBytes: 0, regions: [], failedRegions: [])
    static let unavailable = StorageMenuStatus(kind: .unavailable, totalBytes: 0, regions: [], failedRegions: [])

    static func ready(totalBytes: Int, regions: [StorageMenuRegion], failedRegions: [String] = []) -> StorageMenuStatus {
        StorageMenuStatus(
            kind: .ready,
            totalBytes: max(totalBytes, 0),
            regions: regions.sorted { $0.region < $1.region },
            failedRegions: failedRegions.sorted()
        )
    }

    static func ready(from summary: OfflinePackStorageSummary) -> StorageMenuStatus {
        ready(
            totalBytes: summary.totalBytes,
            regions: summary.packs.map {
                StorageMenuRegion(
                    region: $0.region,
                    publishVersion: $0.publishVersion,
                    bytes: $0.referencedBytes,
                    tileCount: $0.tileCount
                )
            },
            failedRegions: summary.failedRegions
        )
    }

    var totalBytesText: String {
        Self.formatBytes(totalBytes)
    }

    static func formatBytes(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(max(bytes, 0)), countStyle: .file)
    }
}

private extension StorageMenuStatus.Kind {
    var logLabel: String {
        switch self {
        case .loading:
            return "loading"
        case .unavailable:
            return "unavailable"
        case .ready:
            return "ready"
        }
    }
}

private struct UpdateRequiredBlockingView: View {
    let surface: MapBlockingSurface
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Image(systemName: "arrow.down.app")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)

                    VStack(spacing: 8) {
                        Text(surface.title)
                            .font(.title.weight(.bold))
                            .multilineTextAlignment(.center)
                        Text(surface.message)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        openURL(surface.appStoreURL)
                    } label: {
                        Label(surface.primaryActionTitle, systemImage: "arrow.up.forward.app")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("map.update-required.app-store")
                }
                .frame(maxWidth: 420)
                .padding(.horizontal, 28)
                .padding(.vertical, 48)
                .frame(maxWidth: .infinity, minHeight: 520)
            }
            .navigationTitle("Update required")
            .navigationBarTitleDisplayMode(.inline)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("map.update-required")
    }
}

private struct MapEmptyRegionSurfaceView: View {
    let surface: MapEmptyRegionSurface
    let openOfflineMaps: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: surface.systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            VStack(spacing: 5) {
                Text(surface.title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text(surface.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let primaryActionTitle = surface.primaryActionTitle {
                Button {
                    openOfflineMaps()
                } label: {
                    Label(primaryActionTitle, systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .accessibilityIdentifier("map.empty-region.offline-maps")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(surface.accessibilityIdentifier)
    }
}

private extension MapEmptyRegionSurface {
    var systemImage: String {
        switch self {
        case .unsupportedRegion:
            return "map"
        case .mapDataUnavailable:
            return "wifi.slash"
        case .noPlaces:
            return "mappin.slash"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .unsupportedRegion:
            return "map.empty-region.unsupported"
        case .mapDataUnavailable:
            return "map.empty-region.data-unavailable"
        case .noPlaces:
            return "map.empty-region.no-places"
        }
    }
}

private struct AppMenuSheet: View {
    @Bindable var shell: AppShellModel
    let model: MapScreenModel?
    let attribution: [Attribution]
    @Binding var selectedThemeID: String
    @Binding var pinSizeMultiplier: Double
    let seededOfflineDownloadProgress: OfflineDownloadProgress?
    let offlineDownloadSession: OfflineRegionDownloadSession
    let locationStatus: LocationMenuStatus
    let storageStatus: StorageMenuStatus
    let openLocationSettings: () -> Void
    let replayOnboarding: @MainActor () -> Void
    let onOfflineMapsChanged: @MainActor () async -> Void
    let onShowListOnMap: @MainActor (PlaceList) -> Void
    let onListRenamed: @MainActor (PlaceList) -> Void
    let onListDeleted: @MainActor (Int64) -> Void

    @State private var path: [MenuDestination] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack(path: $path) {
            AppMenuRootView(path: $path)
                .navigationTitle("Menu")
                .navigationDestination(for: MenuDestination.self) { destination in
                    destinationView(destination)
                }
                .toolbar {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("menu.done")
                }
        }
        .onAppear {
            applyDeepLinkIfNeeded(resetToRootWhenNoDeepLink: true)
        }
        .onChange(of: shell.deepLinkPath) { _, _ in
            applyDeepLinkIfNeeded(resetToRootWhenNoDeepLink: false)
        }
    }

    @ViewBuilder
    private func destinationView(_ destination: MenuDestination) -> some View {
        switch destination {
        case .lists:
            destinationWithDone(ListsView(
                model: model,
                onShowOnMap: onShowListOnMap,
                onListRenamed: onListRenamed,
                onListDeleted: onListDeleted
            ))
        case .offlineMaps:
#if DEBUG
            destinationWithDone(OfflineMapsView(
                model: model,
                seededProgress: seededOfflineDownloadProgress,
                downloadSession: offlineDownloadSession,
                storageStatus: storageStatus,
                onOfflineMapsChanged: onOfflineMapsChanged
            ))
#else
            destinationWithDone(OfflineMapsReleaseGatedView())
#endif
        case .settings:
            destinationWithDone(SettingsView(
                selectedThemeID: $selectedThemeID,
                pinSizeMultiplier: $pinSizeMultiplier,
                locationStatus: locationStatus,
                storageStatus: storageStatus,
                openLocationSettings: openLocationSettings,
                replayOnboarding: replayOnboardingAndDismiss
            ))
        case .about:
            destinationWithDone(AboutView(attribution: attribution))
        }
    }

    private func destinationWithDone<Content: View>(_ content: Content) -> some View {
        content.toolbar {
            Button("Done") { dismiss() }
                .accessibilityIdentifier("menu.done")
        }
    }

    private func applyDeepLinkIfNeeded(resetToRootWhenNoDeepLink: Bool) {
        guard let destination = shell.deepLinkPath else {
            if resetToRootWhenNoDeepLink {
                path = []
            }
            return
        }
        path = [destination]
        shell.deepLinkPath = nil
    }

    private func replayOnboardingAndDismiss() {
        dismiss()
        replayOnboarding()
    }
}

private struct AppMenuRootView: View {
    @Binding var path: [MenuDestination]

    var body: some View {
        List {
            Button {
                path.append(.lists)
            } label: {
                menuRow(title: "Lists", subtitle: "Saved places and collections", systemImage: "list.bullet")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("menu.row.lists")

            Button {
                path.append(.offlineMaps)
            } label: {
                menuRow(title: "Offline maps", subtitle: "Download regions for later", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("menu.row.offline-maps")

            Button {
                path.append(.settings)
            } label: {
                menuRow(title: "Settings", subtitle: "Map theme, location, and storage", systemImage: "gearshape")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("menu.row.settings")

            Button {
                path.append(.about)
            } label: {
                menuRow(title: "About", subtitle: "Credits, attribution, and build info", systemImage: "info.circle")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("menu.row.about")
        }
    }

    private func menuRow(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.headline)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .foregroundStyle(.primary)
    }
}

private struct ListsView: View {
    let model: MapScreenModel?
    let onShowOnMap: @MainActor (PlaceList) -> Void
    let onListRenamed: @MainActor (PlaceList) -> Void
    let onListDeleted: @MainActor (Int64) -> Void

    @State private var lists: [PlaceList] = []
    @State private var progress: [Int64: ListProgress] = [:]
    @State private var draftName = ""
    @State private var actionError: String?
    @State private var pendingDeleteList: PlaceList?

    var body: some View {
        List {
            Section {
                HStack(spacing: 8) {
                    TextField("New list", text: $draftName)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("lists.create.name")
                    Button {
                        Task { await createList() }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Create list")
                    .accessibilityIdentifier("lists.create")
                }
                if let actionError {
                    Text(verbatim: actionError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("lists.error")
                }
            }

            Section {
                ForEach(lists) { list in
                    NavigationLink {
                        ListDetailView(
                            model: model,
                            list: list,
                            onChanged: { Task { await reload() } },
                            onShowOnMap: onShowOnMap,
                            onListRenamed: onListRenamed
                        )
                    } label: {
                        listRow(list)
                    }
                    .accessibilityIdentifier("lists.row.\(list.id ?? -1)")
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if !list.isSystem, let id = list.id {
                            Button("Delete", role: .destructive) {
                                pendingDeleteList = list
                            }
                            .accessibilityIdentifier("lists.delete.\(id)")
                        }
                    }
                }
            }
        }
        .navigationTitle("Lists")
        .task { await reload() }
        .refreshable { await reload() }
        .toolbar {
            Button {
                Task { await reload() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .accessibilityLabel("Refresh lists")
        }
        .confirmationDialog(
            pendingDeleteList.map { "Delete \($0.name)?" } ?? "Delete list?",
            isPresented: Binding(
                get: { pendingDeleteList != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDeleteList = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let id = pendingDeleteList?.id else { return }
                pendingDeleteList = nil
                Task { await deleteList(id: id) }
            }
            .accessibilityIdentifier("lists.delete.confirm")
            Button("Cancel", role: .cancel) {
                pendingDeleteList = nil
            }
        }
    }

    private func listRow(_ list: PlaceList) -> some View {
        let p = progress[list.id ?? -1] ?? ListProgress(visited: 0, total: 0)
        return HStack(spacing: 12) {
            Image(systemName: list.isSystem ? "bookmark.fill" : "list.bullet")
                .frame(width: 24)
                .foregroundStyle(list.isSystem ? Color.accentColor : Color.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: list.name)
                    .font(.body)
                Text(verbatim: ListsCopy.progress(visited: p.visited, total: p.total))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 44, alignment: .leading)
    }

    @MainActor
    private func reload() async {
        guard let model else { return }
        let nextLists = await model.lists()
        var nextProgress: [Int64: ListProgress] = [:]
        for list in nextLists {
            guard let id = list.id else { continue }
            nextProgress[id] = await model.listProgress(listID: id)
        }
        lists = nextLists
        progress = nextProgress
    }

    @MainActor
    private func createList() async {
        guard let model else { return }
        do {
            _ = try await model.createList(named: draftName)
            draftName = ""
            actionError = nil
            await reload()
        } catch {
            actionError = "Use a shorter list name."
        }
    }

    @MainActor
    private func deleteList(id: Int64) async {
        guard let model else { return }
        do {
            try await model.deleteList(id: id)
            actionError = nil
            await reload()
            onListDeleted(id)
        } catch {
            actionError = "Could not delete that list."
        }
    }
}

private struct ListDetailView: View {
    let model: MapScreenModel?
    let list: PlaceList
    let onChanged: @MainActor () -> Void
    let onShowOnMap: @MainActor (PlaceList) -> Void
    let onListRenamed: @MainActor (PlaceList) -> Void

    @State private var items: [ListPlace] = []
    @State private var progress = ListProgress(visited: 0, total: 0)
    @State private var currentList: PlaceList
    @State private var renameDraft: String
    @State private var actionError: String?

    init(
        model: MapScreenModel?,
        list: PlaceList,
        onChanged: @escaping @MainActor () -> Void,
        onShowOnMap: @escaping @MainActor (PlaceList) -> Void,
        onListRenamed: @escaping @MainActor (PlaceList) -> Void
    ) {
        self.model = model
        self.list = list
        self.onChanged = onChanged
        self.onShowOnMap = onShowOnMap
        self.onListRenamed = onListRenamed
        _currentList = State(initialValue: list)
        _renameDraft = State(initialValue: list.name)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: ListsCopy.progress(visited: progress.visited, total: progress.total))
                        .font(.headline)
                        .accessibilityIdentifier("lists.detail.progress")
                    Button {
                        onShowOnMap(currentList)
                    } label: {
                        Label("Show on map", systemImage: "map")
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("lists.detail.show-map")
                }
                if !list.isSystem, let id = list.id {
                    HStack(spacing: 8) {
                        TextField("List name", text: $renameDraft)
                            .textInputAutocapitalization(.words)
                            .accessibilityIdentifier("lists.detail.rename.name")
                        Button("Rename") {
                            Task { await rename(id: id) }
                        }
                        .accessibilityIdentifier("lists.detail.rename")
                    }
                }
                if let actionError {
                    Text(verbatim: actionError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("lists.detail.error")
                }
            }

            Section {
                if items.isEmpty {
                    ContentUnavailableView("No places yet", systemImage: "mappin.slash")
                } else {
                    ForEach(items) { item in
                        listItemRow(item)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if let id = list.id {
                                    Button("Remove", role: .destructive) {
                                        Task { await remove(item.placeID, listID: id) }
                                    }
                                    .accessibilityIdentifier("lists.detail.remove.\(item.placeID)")
                                }
                            }
                    }
                }
            }
        }
        .navigationTitle(currentList.name)
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func listItemRow(_ item: ListPlace) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.pinState.visit == .none ? "circle" : "checkmark.circle.fill")
                .foregroundStyle(item.pinState.visit == .none ? Color.secondary : Color.accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: item.name)
                    .font(.body)
                HStack(spacing: 6) {
                    Text(verbatim: categoryLabel(item.category))
                    if item.pinState.hidden {
                        Text(verbatim: "Hidden")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if item.pinState.hidden {
                Button("Unhide") {
                    Task { await unhide(item.placeID) }
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("lists.detail.unhide.\(item.placeID)")
            }
        }
        .frame(minHeight: 44, alignment: .leading)
        .accessibilityIdentifier("lists.detail.item.\(item.placeID)")
    }

    @MainActor
    private func reload() async {
        guard let model, let id = list.id else { return }
        items = await model.listItems(listID: id)
        progress = await model.listProgress(listID: id)
    }

    @MainActor
    private func rename(id: Int64) async {
        guard let model else { return }
        do {
            currentList = try await model.renameList(id: id, name: renameDraft)
            renameDraft = currentList.name
            actionError = nil
            onChanged()
            onListRenamed(currentList)
        } catch {
            actionError = "Use a shorter list name."
        }
    }

    @MainActor
    private func remove(_ placeID: String, listID: Int64) async {
        guard let model else { return }
        do {
            try await model.removeFromList(placeID: placeID, listID: listID)
            actionError = nil
            await reload()
            onChanged()
        } catch {
            actionError = "Could not remove that place."
        }
    }

    @MainActor
    private func unhide(_ placeID: String) async {
        guard let model else { return }
        do {
            try await model.setHidden(placeID: placeID, hidden: false)
            actionError = nil
            await reload()
            onChanged()
        } catch {
            actionError = "Could not unhide that place."
        }
    }

    private func categoryLabel(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

private struct OfflineMapsReleaseGatedView: View {
    var body: some View {
        ContentUnavailableView(
            "Offline maps",
            systemImage: "arrow.down.circle",
            description: Text("Region downloads are not enabled in this build.")
        )
        .navigationTitle("Offline maps")
    }
}

#if DEBUG
private struct OfflineMapsView: View {
    let model: MapScreenModel?
    let seededProgress: OfflineDownloadProgress?
    let downloadSession: OfflineRegionDownloadSession
    let onOfflineMapsChanged: @MainActor () async -> Void

    private let catalog = OfflineRegionCatalog.debugFixture
    @State private var installed: [String: String] = [:]
    @State private var availablePublishVersions: [String: String] = [:]
    @State private var pausedRegions: Set<String> = []
    @State private var quarantines: [OfflinePackQuarantine] = []
    @State private var storageStatus: StorageMenuStatus
    @State private var statusMessage: String?
    @State private var pendingDeleteRegion: String?
    @State private var pendingDeleteRegionName: String?
    @AppStorage(OfflineDownloadSettings.allowsCellularDownloadsKey) private var allowsCellularDownloads = OfflineDownloadSettings.defaultAllowsCellularDownloads

    init(
        model: MapScreenModel?,
        seededProgress: OfflineDownloadProgress?,
        downloadSession: OfflineRegionDownloadSession,
        storageStatus: StorageMenuStatus,
        onOfflineMapsChanged: @escaping @MainActor () async -> Void
    ) {
        self.model = model
        self.seededProgress = seededProgress
        self.downloadSession = downloadSession
        self._storageStatus = State(initialValue: storageStatus)
        self.onOfflineMapsChanged = onOfflineMapsChanged
    }

    private var activeProgress: OfflineDownloadProgress? {
        downloadSession.liveProgress ?? seededProgress
    }

    private var pausedProgress: OfflineDownloadProgress? {
        downloadSession.pausedProgress
    }

    private var rows: [OfflineRegionCatalogRow] {
        catalog.rows(
            installed: installed,
            availablePublishVersions: availablePublishVersions,
            activeProgress: activeProgress,
            pausedProgress: pausedProgress,
            pausedRegions: pausedRegions,
            quarantines: quarantines
        )
    }

    var body: some View {
        List {
            Section {
                ForEach(rows) { row in
                    rowView(row)
                }
            } header: {
                Text("Named zones")
            }

            Section("Storage") {
                storageView
            }

            if let statusMessage {
                Section {
                    Label(statusMessage, systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("offline-maps.status")
                }
            }
        }
        .navigationTitle("Offline maps")
        .task {
            await refresh()
        }
        .refreshable {
            await refresh()
        }
        .confirmationDialog(
            pendingDeleteRegionName.map { "Delete \($0)?" } ?? "Delete downloaded map?",
            isPresented: Binding(
                get: { pendingDeleteRegion != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDeleteRegion = nil
                        pendingDeleteRegionName = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let region = pendingDeleteRegion else { return }
                pendingDeleteRegion = nil
                pendingDeleteRegionName = nil
                Task { await delete(region) }
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteRegion = nil
                pendingDeleteRegionName = nil
            }
        } message: {
            Text("This removes the downloaded region from this device.")
        }
    }

    @ViewBuilder
    private var storageView: some View {
        switch storageStatus.kind {
        case .loading:
            ProgressView("Calculating installed maps")
                .accessibilityIdentifier("offline-maps.storage.loading")
        case .unavailable:
            Label("Storage unavailable", systemImage: "externaldrive.badge.exclamationmark")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("offline-maps.storage.unavailable")
        case .ready:
            LabeledContent("Installed maps", value: storageStatus.totalBytesText)
                .accessibilityIdentifier("offline-maps.storage.total")
            if storageStatus.regions.isEmpty {
                Text("No downloaded regions")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("offline-maps.storage.empty")
            } else {
                ForEach(storageStatus.regions) { region in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: region.title)
                        Text(verbatim: region.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .badge(Text(verbatim: region.bytesText))
                    .accessibilityIdentifier("offline-maps.storage.region.\(region.region)")
                }
            }
            ForEach(storageStatus.failedRegions, id: \.self) { region in
                Label {
                    Text(verbatim: region)
                } icon: {
                    Image(systemName: "externaldrive.badge.xmark")
                }
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("offline-maps.storage.failed-region.\(region)")
            }
        }
    }

    private func rowView(_ row: OfflineRegionCatalogRow) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: row.zone.displayName)
                    .font(row.depth == 0 ? .headline : .body)
                Text(verbatim: "\(row.zone.sizeLabel(includeThumbnails: false)) · \(row.statusLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if case let .quarantined(quarantine) = row.state {
                    Text(verbatim: quarantineDetail(quarantine))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.leading, CGFloat(row.depth) * 18)

            Spacer(minLength: 8)

            actionButtons(for: row)
        }
        .frame(minHeight: 56)
        .accessibilityIdentifier("offline-maps.zone.\(row.zone.id)")
    }

    @ViewBuilder
    private func actionButtons(for row: OfflineRegionCatalogRow) -> some View {
        switch row.state {
        case .notInstalled:
            iconButton("Download", systemImage: "arrow.down.circle") {
                startDownload(row.zone.id)
            }
        case .unavailable:
            if row.hasUnavailableLocalData || row.hasUnavailablePausedDownload {
                HStack(spacing: 8) {
                    if row.hasUnavailablePausedDownload {
                        iconButton("Cancel", systemImage: "xmark.circle", role: .destructive) {
                            Task { await cancelDownload(region: row.cancelRegion) }
                        }
                    }
                    if row.hasUnavailableLocalData {
                        iconButton("Delete", systemImage: "trash", role: .destructive) {
                            pendingDeleteRegion = row.zone.id
                            pendingDeleteRegionName = row.zone.displayName
                        }
                    }
                }
            } else {
                EmptyView()
            }
        case .installed:
            iconButton("Delete", systemImage: "trash", role: .destructive) {
                pendingDeleteRegion = row.zone.id
                pendingDeleteRegionName = row.zone.displayName
            }
        case .updateAvailable:
            HStack(spacing: 8) {
                iconButton("Update", systemImage: "arrow.triangle.2.circlepath") {
                    startDownload(row.zone.id)
                }
                iconButton("Delete", systemImage: "trash", role: .destructive) {
                    pendingDeleteRegion = row.zone.id
                    pendingDeleteRegionName = row.zone.displayName
                }
            }
        case .quarantined:
            iconButton("Re-download", systemImage: "arrow.clockwise.circle") {
                startDownload(row.zone.id)
            }
        case .downloading:
            HStack(spacing: 8) {
                if downloadSession.activeControl != nil {
                    iconButton("Pause", systemImage: "pause.circle") {
                        downloadSession.activeControl?.pause()
                    }
                }
                iconButton("Cancel", systemImage: "xmark.circle", role: .destructive) {
                    Task { await cancelDownload() }
                }
            }
        case .paused:
            HStack(spacing: 8) {
                iconButton("Resume", systemImage: "play.circle") {
                    startDownload(row.zone.id, resumingPausedDownload: true)
                }
                iconButton("Cancel", systemImage: "xmark.circle", role: .destructive) {
                    Task { await cancelDownload(region: row.cancelRegion) }
                }
            }
        }
    }

    private func iconButton(
        _ label: String,
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
    }

    private func startDownload(_ region: String, resumingPausedDownload: Bool = false) {
        guard let model else {
            statusMessage = "Offline downloads unavailable"
            MakingTracksLog.downloads.error("ui download unavailable region=\(region, privacy: .private(mask: .hash))")
            return
        }
        guard downloadSession.canBegin(region: region) else {
            statusMessage = "Resume or cancel the paused download first"
            MakingTracksLog.downloads.info("ui download blocked region=\(region, privacy: .private(mask: .hash))")
            return
        }
        let downloadID = UUID()
        let control = OfflineRegionDownloadControl()
        downloadSession.begin(region: region, control: control, downloadID: downloadID)
        statusMessage = nil
        MakingTracksLog.downloads.info("ui download started region=\(region, privacy: .private(mask: .hash))")
        let task = Task {
            let message = await model.installOfflineRegion(
                region,
                control: control,
                resumingPausedDownload: resumingPausedDownload,
                allowsCellularDownloads: allowsCellularDownloads
            ) { progress in
                Task { @MainActor in
                    guard downloadSession.activeDownloadID == downloadID else { return }
                    downloadSession.update(OfflineDownloadProgress(progress))
                }
            }
            let shouldRefreshMap = await MainActor.run { () -> Bool in
                guard downloadSession.activeDownloadID == downloadID else { return false }
                if message == "Download paused" {
                    downloadSession.pause(region: region)
                } else {
                    downloadSession.clear()
                }
                statusMessage = message
                let result = statusLogLabel(message)
                MakingTracksLog.downloads.info("ui download finished region=\(region, privacy: .private(mask: .hash)) result=\(result, privacy: .public)")
                return message.hasPrefix("Installed ")
            }
            if shouldRefreshMap {
                await onOfflineMapsChanged()
            }
            await refresh()
        }
        downloadSession.attach(task: task)
    }

    private func cancelDownload(region persistedPausedRegion: String? = nil) async {
        guard downloadSession.activeControl != nil
            || downloadSession.activeTask != nil
            || downloadSession.liveProgress != nil
            || downloadSession.pausedProgress != nil
            || persistedPausedRegion != nil
        else { return }
        let regionToDiscard = downloadSession.regionForCancel(fallbackRegion: persistedPausedRegion)
        MakingTracksLog.downloads.info("ui cancel requested region=\(regionToDiscard ?? "unknown", privacy: .private(mask: .hash))")
        if downloadSession.shouldClearSessionForCancel(fallbackRegion: persistedPausedRegion) {
            downloadSession.activeControl?.cancel()
            downloadSession.activeTask?.cancel()
            downloadSession.clear()
        }
        if let regionToDiscard, let model {
            statusMessage = await model.discardOfflineRegionDownload(regionToDiscard)
            await refresh()
            let result = statusLogLabel(statusMessage)
            MakingTracksLog.downloads.info("ui cancel finished region=\(regionToDiscard, privacy: .private(mask: .hash)) result=\(result, privacy: .public)")
        } else {
            statusMessage = "Download cancelled"
            MakingTracksLog.downloads.info("ui cancel finished region=unknown result=cancelled")
        }
    }

    private func delete(_ region: String) async {
        guard let model else {
            statusMessage = "Offline downloads unavailable"
            MakingTracksLog.downloads.error("ui delete unavailable region=\(region, privacy: .private(mask: .hash))")
            return
        }
        MakingTracksLog.downloads.info("ui delete requested region=\(region, privacy: .private(mask: .hash))")
        statusMessage = await model.deleteOfflineRegion(region)
        downloadSession.noteDeleted(region: region)
        await onOfflineMapsChanged()
        await refresh()
        let result = statusLogLabel(statusMessage)
        MakingTracksLog.downloads.info("ui delete finished region=\(region, privacy: .private(mask: .hash)) result=\(result, privacy: .public)")
    }

    private func refresh() async {
        guard let model else {
            installed = [:]
            availablePublishVersions = [:]
            pausedRegions = []
            quarantines = []
            storageStatus = .unavailable
            MakingTracksLog.startup.info("offline rows state=unavailable")
            return
        }
        installed = await model.installedOfflinePublishVersions(for: catalog)
        availablePublishVersions = await model.availableOfflinePublishVersions(
            for: catalog,
            installedRegions: Set(installed.keys),
            allowsCellularDownloads: allowsCellularDownloads
        )
        pausedRegions = await model.pausedOfflineDownloadRegions(for: catalog)
        quarantines = model.offlinePackQuarantines()
        storageStatus = await model.storageMenuStatus()
        let installedCount = installed.count
        let quarantineCount = quarantines.count
        MakingTracksLog.startup.info("offline rows refreshed installed=\(installedCount, privacy: .public) quarantines=\(quarantineCount, privacy: .public)")
    }

    private func quarantineDetail(_ quarantine: OfflinePackQuarantine) -> String {
        let version = quarantine.publishVersion ?? "unknown version"
        let cells = quarantine.coordinates.count
        return "\(version) · \(cells) affected \(cells == 1 ? "cell" : "cells")"
    }

    private func statusLogLabel(_ message: String?) -> String {
        guard let message else { return "none" }
        if message.hasPrefix("Installed ") {
            return "installed"
        }
        if message.hasPrefix("Deleted ") {
            return "deleted"
        }
        if message.hasPrefix("Install failed:") {
            return "install-failed"
        }
        if message.hasPrefix("Delete failed:") {
            return "delete-failed"
        }
        if message.hasPrefix("Cancel failed:") {
            return "cancel-failed"
        }
        if message == "Download paused" {
            return "download-paused"
        }
        if message == "Download cancelled" {
            return "download-cancelled"
        }
        if message == "Offline downloads unavailable" || message == "Offline install unavailable" || message == "Offline delete unavailable" {
            return "offline-unavailable"
        }
        return "other"
    }
}
#endif

private struct SettingsView: View {
    @Binding var selectedThemeID: String
    @Binding var pinSizeMultiplier: Double
    let locationStatus: LocationMenuStatus
    let storageStatus: StorageMenuStatus
    let openLocationSettings: () -> Void
    let replayOnboarding: @MainActor () -> Void
    @AppStorage(OfflineDownloadSettings.allowsCellularDownloadsKey) private var allowsCellularDownloads = OfflineDownloadSettings.defaultAllowsCellularDownloads

    var body: some View {
        List {
            Section("Map theme") {
                ForEach(MapTheme.allCandidates, id: \.id) { theme in
                    let isSelected = MapTheme.named(selectedThemeID).id == theme.id
                    Button {
                        selectedThemeID = theme.id
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(verbatim: theme.displayName)
                                    .foregroundStyle(.primary)
                                Text(verbatim: theme.id)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.headline)
                                    .foregroundStyle(Color.accentColor)
                                    .accessibilityHidden(true)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(isSelected ? "Selected" : "Not selected")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityIdentifier("settings.theme.\(theme.id)")
                }
            }

            Section("Downloads") {
                Toggle(isOn: $allowsCellularDownloads) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Allow cellular downloads")
                        Text("Off keeps offline maps waiting for Wi-Fi.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("settings.downloads.allow-cellular")
            }

            Section("Pins") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Pin size")
                        Spacer()
                        Text(pinSize.accessibilityValue)
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: pinSizeBinding,
                        in: PinSize.minimumMultiplier...PinSize.maximumMultiplier,
                        step: 0.1
                    )
                    .accessibilityLabel("Pin size")
                    .accessibilityValue(pinSize.accessibilityValue)
                    .accessibilityIdentifier("settings.pin-size")
                }
            }

            Section("Location") {
                HStack {
                    Label(locationStatus.label, systemImage: "location")
                    Spacer()
                    if locationStatus.canOpenSettings {
                        Button("Settings", action: openLocationSettings)
                            .accessibilityIdentifier("settings.location.open-system")
                    }
                }
            }

            Section("Storage") {
                switch storageStatus.kind {
                case .loading:
                    Label("Checking installed maps", systemImage: "internaldrive")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings.storage.loading")
                case .unavailable:
                    Label("Storage unavailable", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings.storage.unavailable")
                case .ready:
                    LabeledContent("Installed maps", value: storageStatus.totalBytesText)
                        .accessibilityIdentifier("settings.storage.total")
                    if storageStatus.regions.isEmpty {
                        Label("No offline regions installed", systemImage: "internaldrive")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("settings.storage.empty")
                    } else {
                        ForEach(storageStatus.regions) { region in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(region.title)
                                    Spacer()
                                    Text(region.bytesText)
                                        .foregroundStyle(.secondary)
                                }
                                Text(region.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("settings.storage.region.\(region.region)")
                        }
                    }
                    ForEach(storageStatus.failedRegions, id: \.self) { region in
                        HStack {
                            Text(region)
                            Spacer()
                            Text("Unavailable")
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("settings.storage.failed-region.\(region)")
                    }
                }
            }

            Section("Onboarding") {
                Button(action: replayOnboarding) {
                    Text("Replay onboarding")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.replay-onboarding")
            }
        }
        .navigationTitle("Settings")
    }

    private var pinSize: PinSize {
        PinSize(multiplier: pinSizeMultiplier)
    }

    private var pinSizeBinding: Binding<Double> {
        Binding(
            get: { pinSize.multiplier },
            set: { pinSizeMultiplier = PinSize(multiplier: $0).multiplier }
        )
    }
}

private struct AboutView: View {
    let attribution: [Attribution]

    private static let buildCommit = loadBuildCommit()
    private static let ossCredits = loadOSSCredits()
    private static let osmCopyrightURL = URL(string: "https://www.openstreetmap.org/copyright")!

    private static func loadBuildCommit() -> String {
        guard let url = Bundle.main.url(forResource: "BuildInfo", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String],
              let commit = plist["GitCommit"]
        else { return "unknown" }
        return commit
    }

    private static func loadOSSCredits() -> [OSSCreditEntry] {
        guard let url = Bundle.main.url(forResource: "OSSCredits", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(OSSCreditsManifest.self, from: data)
        else { return [] }
        return manifest.credits
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Open data")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Text("Places come from open data including Wikipedia, OpenStreetMap, and heritage registers.")
                    Text(OnboardingCopy.savedActivityPrivacy)
                        .accessibilityIdentifier("about.privacy-saved-activity")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Build")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: "Build \(Self.buildCommit)")
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .accessibilityIdentifier("credits.build-commit")
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Map attribution")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Text("Map data © OpenStreetMap contributors.")
                    Link(destination: Self.osmCopyrightURL) {
                        Text("OpenStreetMap copyright")
                    }
                    .accessibilityValue(Self.osmCopyrightURL.absoluteString)
                    .accessibilityIdentifier("about.openstreetmap-copyright")
                }

                if !attribution.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Manifest attribution")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(attribution.enumerated()), id: \.offset) { _, item in
                                CreditEntryView(
                                    title: item.source,
                                    subtitle: item.license,
                                    text: item.text
                                )
                            }
                        }
                    }
                }

                if !Self.ossCredits.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Open source acknowledgements")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        VStack(alignment: .leading, spacing: 20) {
                            ForEach(Self.ossCredits) { credit in
                                OpenSourceCreditView(credit: credit)
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("About")
    }
}

private struct CreditEntryView: View {
    let title: String
    let subtitle: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: title)
                .font(.headline)
            Text(verbatim: subtitle)
                .font(.subheadline)
            Text(verbatim: text)
                .font(.body)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("credits.manifest.\(title)")
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ListPickerView: View {
    let placeID: String
    let model: MapScreenModel?
    let onChanged: @MainActor () -> Void

    @State private var lists: [PlaceList] = []
    @State private var memberships: Set<Int64> = []
    @State private var newListName = ""
    @State private var actionError: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 8) {
                        TextField("New list", text: $newListName)
                            .textInputAutocapitalization(.words)
                            .accessibilityIdentifier("list-picker.new-name")
                        Button {
                            Task { await createAndAdd() }
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Create list and add place")
                        .accessibilityIdentifier("list-picker.create")
                    }
                    if let actionError {
                        Text(verbatim: actionError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("list-picker.error")
                    }
                }

                Section {
                    ForEach(lists.filter { !$0.isSystem }) { list in
                        Button {
                            Task { await toggle(list) }
                        } label: {
                            HStack {
                                Text(verbatim: list.name)
                                Spacer()
                                if let id = list.id, memberships.contains(id) {
                                    Image(systemName: "checkmark")
                                        .accessibilityLabel("In list")
                                }
                            }
                        }
                        .accessibilityIdentifier("list-picker.row.\(list.id ?? -1)")
                    }
                }
            }
            .navigationTitle("Add to list")
            .toolbar {
                Button("Done") { dismiss() }
                    .accessibilityIdentifier("list-picker.done")
            }
            .task { await reload() }
        }
    }

    @MainActor
    private func reload() async {
        guard let model else { return }
        let nextLists = await model.lists()
        lists = nextLists
        memberships = Set(await model.listMemberships(containing: placeID))
    }

    @MainActor
    private func toggle(_ list: PlaceList) async {
        guard let id = list.id, let model else { return }
        do {
            if memberships.contains(id) {
                try await model.removeFromList(placeID: placeID, listID: id)
            } else {
                try await model.addToList(placeID: placeID, listID: id)
            }
            actionError = nil
            await reload()
            onChanged()
        } catch {
            actionError = "Could not update that list."
        }
    }

    @MainActor
    private func createAndAdd() async {
        guard let model else { return }
        do {
            let list = try await model.createList(named: newListName)
            guard let id = list.id else { throw AppDatabaseError.unreadableDatabase }
            try await model.addToList(placeID: placeID, listID: id)
            newListName = ""
            actionError = nil
            await reload()
            onChanged()
        } catch {
            actionError = "Use a shorter list name."
        }
    }
}

private struct OpenSourceCreditView: View {
    let credit: OSSCreditEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: credit.name)
                    .font(.headline)
                Text(verbatim: credit.acknowledgement)
                    .font(.subheadline)
                Text(verbatim: "\(credit.category) | \(credit.versionOrPin)")
                    .font(.caption)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("credits.oss.\(credit.id)")
            if let licenseURL = credit.licenseURL {
                Link(destination: licenseURL) {
                    Text("License")
                        .font(.caption)
                }
                .accessibilityLabel("License for \(credit.name)")
                .accessibilityValue(licenseURL.absoluteString)
                .accessibilityIdentifier("credits.oss.\(credit.id).license")
            }
            Text(verbatim: credit.noticeText)
                .font(.footnote)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct OSSCreditsManifest: Decodable {
    let credits: [OSSCreditEntry]
}

private struct OSSCreditEntry: Decodable, Identifiable {
    let acknowledgement: String
    let category: String
    let licenseURLString: String
    let name: String
    let noticeText: String
    let versionOrPin: String

    var id: String { "\(name)|\(versionOrPin)" }

    var licenseURL: URL? {
        guard let url = URL(string: licenseURLString), url.scheme == "https" else { return nil }
        return url
    }

    private enum CodingKeys: String, CodingKey {
        case acknowledgement
        case category
        case licenseURLString = "license_url"
        case name
        case noticeText = "notice_text"
        case versionOrPin = "version_or_pin"
    }
}

private struct LocationSettingsButton: UIViewRepresentable {
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "gearshape.fill")
        configuration.title = "Settings"
        configuration.imagePadding = 4
        configuration.contentInsets = .zero
        configuration.baseForegroundColor = .label
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            let baseFont = UIFont.systemFont(ofSize: 11, weight: .semibold)
            outgoing.font = UIFontMetrics(forTextStyle: .caption2).scaledFont(for: baseFont)
            return outgoing
        }
        button.configuration = configuration
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.accessibilityLabel = "Settings"
        button.accessibilityHint = "Opens location settings"
        button.accessibilityIdentifier = "map.location-settings"
        button.addTarget(context.coordinator, action: #selector(Coordinator.tap), for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: UIButton, context: Context) {
        context.coordinator.action = action
    }

    final class Coordinator {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func tap() {
            action()
        }
    }
}

private extension View {
    func mapChromeGlyphHalo() -> some View {
        shadow(color: Color.white.opacity(0.95), radius: MapHomeChromeSpec.glyphHaloRadius, x: 0, y: 0)
            .shadow(color: Color.white.opacity(0.95), radius: 0.5, x: 0, y: MapHomeChromeSpec.glyphHaloYOffset)
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(in: proposal.width ?? .greatestFiniteMagnitude, subviews: subviews)
        return CGSize(width: rows.width, height: rows.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        let maxWidth = proposal.width ?? bounds.width

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.minX + maxWidth {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }

    private func rows(in maxWidth: CGFloat, subviews: Subviews) -> CGSize {
        var width: CGFloat = 0
        var height: CGFloat = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                width = max(width, rowWidth)
                height += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth = rowWidth == 0 ? size.width : rowWidth + spacing + size.width
            rowHeight = max(rowHeight, size.height)
        }

        width = max(width, rowWidth)
        height += rowHeight
        return CGSize(width: width, height: height)
    }
}

private struct LayersSheet: View {
    @Binding var visibility: MapLayerVisibility
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(
                        "Include hidden places",
                        isOn: Binding(
                            get: { visibility.showHiddenPlaces },
                            set: { visible in
                                var next = visibility
                                next.showHiddenPlaces = visible
                                visibility = next
                            }
                        )
                    )
                        .accessibilityIdentifier("map.layers.show-hidden")
                }

                Section("Categories") {
                    ForEach(visibility.categories) { category in
                        Toggle(
                            isOn: Binding(
                                get: { visibility.isCategoryVisible(category.id) },
                                set: { visible in
                                    var next = visibility
                                    next.setCategory(category.id, visible: visible)
                                    visibility = next
                                }
                            )
                        ) {
                            Label {
                                Text(verbatim: category.title)
                            } icon: {
                                Image(systemName: PinLayers.categorySymbolNames[category.iconName] ?? "mappin")
                            }
                        }
                        .accessibilityIdentifier("map.layers.category.\(category.id)")
                    }
                    Button(visibility.toggleAllCategoriesTitle) {
                        var next = visibility
                        next.toggleAllCategories()
                        visibility = next
                    }
                    .accessibilityIdentifier("map.layers.show-all-categories")
                }
            }
            .navigationTitle("Layers")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityIdentifier("map.layers.done")
                }
            }
        }
    }
}

private struct PlaceCardSheet: View {
    let placeID: String
    let model: MapScreenModel?
    let onHide: (String, String) -> Void
    let showHiddenMode: Bool

    @State private var sheetInstanceID = UUID().uuidString
    @State private var card: PlaceCardModel?
    @State private var isLoading = true
    @State private var actionError: String?
    @State private var showListPicker = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let card {
                    HStack {
                        Spacer()
                        Button("Close") {
                            dismiss()
                        }
                        .accessibilityIdentifier("place-card.close")
                    }
                    Text(verbatim: card.name)
                        .font(.title2.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("place-card.title")
                    typeRow(card)
                    if dynamicTypeSize.isAccessibilitySize {
                        actionButtons(card)
                    }
                    if let blurb = card.blurb {
                        Text(verbatim: blurb)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("place-card.description")
                    }
                    photoSlot(card)
                    listChips(card.listNames)
                    if let actionError {
                        Text(verbatim: actionError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("place-card.action-error")
                    }
                    if !dynamicTypeSize.isAccessibilitySize {
                        actionButtons(card)
                    }
                    attributionText(card)
                } else if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    Text(verbatim: "Place unavailable")
                        .font(.headline)
                    Text(verbatim: placeID)
                        .font(.caption2)
                        .textSelection(.enabled)
                }
            }
            .padding()
        }
        .accessibilityIdentifier("place-card.instance.\(sheetInstanceID)")
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium])
        .presentationBackgroundInteraction(.enabled(upThrough: dynamicTypeSize.isAccessibilitySize ? .large : .medium))
        .task(id: placeID) {
            await loadCard()
        }
        .sheet(isPresented: $showListPicker) {
            ListPickerView(
                placeID: placeID,
                model: model,
                onChanged: {
                    Task { await refreshCard() }
                }
            )
        }
    }

    @ViewBuilder
    private func typeRow(_ card: PlaceCardModel) -> some View {
        HStack(spacing: 8) {
            Image(systemName: categorySymbolName(for: card.category))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(verbatim: categoryLabel(card.category))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("place-card.type.label")
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func photoSlot(_ card: PlaceCardModel) -> some View {
        if let photo = card.photo {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.thinMaterial)
                Image(systemName: "photo")
                    .font(.system(size: 42, weight: .regular))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(photo.accessibilityLabel)
            .accessibilityIdentifier("place-card.photo")
        }
    }

    @ViewBuilder
    private func listChips(_ names: [String]) -> some View {
        if !names.isEmpty {
            FlowLayout(spacing: 8) {
                ForEach(names, id: \.self) { name in
                    Button {
                        showListPicker = true
                    } label: {
                        Text(verbatim: name)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.thinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .accessibilityIdentifier("place-card.list-chips")
        }
    }

    @ViewBuilder
    private func attributionText(_ card: PlaceCardModel) -> some View {
        let parts = attributionParts(card)
        if !parts.isEmpty {
            Text(verbatim: parts.joined(separator: " / "))
                .font(.caption2)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("place-card.attribution")
        }
    }

    @ViewBuilder
    private func actionButtons(_ card: PlaceCardModel) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                saveButton(card)
                addToListButton()
                seenButton(card)
                if card.pinState.visit != .none {
                    loveButton(card)
                }
                if card.pinState.hidden {
                    if showHiddenMode {
                        unhideButton()
                    }
                } else {
                    hideButton(card)
                }
            }
        } else {
            HStack(spacing: 10) {
                saveButton(card)
                addToListButton()
                seenButton(card)
                if card.pinState.visit != .none {
                    loveButton(card)
                }
                if card.pinState.hidden {
                    if showHiddenMode {
                        unhideButton()
                    }
                } else {
                    hideButton(card)
                }
            }
        }
    }

    private func saveButton(_ card: PlaceCardModel) -> some View {
        Button(card.pinState.saved ? "Saved" : "Save") {
            Task { await setSaved(!card.pinState.saved) }
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("place-card.save")
        .accessibilityValue(card.pinState.saved ? "Saved" : "Not saved")
    }

    private func addToListButton() -> some View {
        Button("Add to list") {
            showListPicker = true
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("place-card.add-to-list")
    }

    private func seenButton(_ card: PlaceCardModel) -> some View {
        Button(card.pinState.visit == .none ? "Seen" : "Unsee") {
            Task { await setVisited(card.pinState.visit == .none) }
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("place-card.visited")
        .accessibilityValue(card.pinState.visit == .none ? "Not seen" : "Seen")
    }

    private func loveButton(_ card: PlaceCardModel) -> some View {
        Button(card.pinState.visit == .loved ? "Loved" : "Love") {
            Task { await setLoved(card.pinState.visit != .loved) }
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("place-card.loved")
        .accessibilityValue(card.pinState.visit == .loved ? "Loved" : "Not loved")
    }

    private func hideButton(_ card: PlaceCardModel) -> some View {
        Button("Hide", role: .destructive) {
            Task { await setHidden(card) }
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("place-card.hide")
        .accessibilityValue("Not hidden")
    }

    private func unhideButton() -> some View {
        Button("Unhide") {
            Task { await setHidden(false) }
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("place-card.unhide")
        .accessibilityValue("Hidden")
    }

    private func loadCard() async {
        await MainActor.run {
            card = nil
            actionError = nil
            isLoading = true
        }
        let nextCard = await model?.cardModel(for: placeID)
        await MainActor.run {
            card = nextCard
            isLoading = false
        }
    }

    private func refreshCard() async {
        let nextCard = await model?.cardModel(for: placeID)
        await MainActor.run {
            card = nextCard
        }
    }

    private func setSaved(_ saved: Bool) async {
        await performAction {
            try await model?.setSaved(placeID: placeID, saved: saved)
        }
    }

    private func setVisited(_ visited: Bool) async {
        await performAction {
            try await model?.setVisited(placeID: placeID, visited: visited)
        }
    }

    private func setLoved(_ loved: Bool) async {
        await performAction {
            try await model?.setLoved(placeID: placeID, loved: loved)
        }
    }

    private func setHidden(_ card: PlaceCardModel) async {
        await MainActor.run {
            actionError = nil
        }
        do {
            try await model?.setHidden(placeID: placeID, hidden: true)
            await MainActor.run {
                self.card = nil
                dismiss()
                onHide(placeID, card.name)
            }
        } catch {
            await MainActor.run {
                actionError = "Could not save that change."
            }
        }
    }

    private func setHidden(_ hidden: Bool) async {
        await performAction {
            try await model?.setHidden(placeID: placeID, hidden: hidden)
        }
    }

    private func performAction(_ action: () async throws -> Void) async {
        do {
            try await action()
            await MainActor.run { actionError = nil }
            await refreshCard()
        } catch {
            await MainActor.run {
                actionError = "Could not save that change."
            }
        }
    }

    private func categoryLabel(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private func categorySymbolName(for raw: String) -> String {
        let iconName = PinLayers.categoryIconNames[raw.lowercased()] ?? PinLayers.fallbackCategoryIconName
        return PinLayers.categorySymbolNames[iconName] ?? "mappin"
    }

    private func attributionParts(_ card: PlaceCardModel) -> [String] {
        var parts: [String] = []
        if let photo = card.photo {
            parts.append(photo.attribution)
        }
        if !card.sourceNames.isEmpty {
            parts.append(card.sourceNames.joined(separator: " / "))
        }
        return parts
    }

}

private enum MapScreenActionError: Error {
    case placeUnavailable
}

enum MapManifestRefreshPolicy {
    static let startupAllowsManifestRefresh = false

    static func cameraIdleAllowsManifestRefresh(afterPostFirstRenderRefreshCompleted completed: Bool) -> Bool {
        completed
    }

    static func mapLoadFailureAllowsManifestRefresh(afterPostFirstRenderRefreshCompleted completed: Bool) -> Bool {
        !completed
    }
}

enum MapDeferredOfflineMaintenancePolicy {
    static func allowsDeferredMaintenance(
        isMapReady: Bool,
        didMapLoadFail: Bool,
        didScheduleMaintenance: Bool,
        isProtectedDataAvailable: Bool,
        hasPausedDownload: Bool,
        hasActiveDownload: Bool
    ) -> Bool {
        (isMapReady || didMapLoadFail)
            && !didScheduleMaintenance
            && isProtectedDataAvailable
            && !hasPausedDownload
            && !hasActiveDownload
    }
}

enum MapThemeColor {
    static func color(hex: String) -> Color {
        Color(uiColor: uiColor(hex: hex))
    }

    static func uiColor(hex: String) -> UIColor {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard value.count == 6, let rgb = Int(value, radix: 16) else {
            return UIColor(red: 0.953, green: 0.937, blue: 0.898, alpha: 1)
        }
        let red = CGFloat((rgb >> 16) & 0xff) / 255
        let green = CGFloat((rgb >> 8) & 0xff) / 255
        let blue = CGFloat(rgb & 0xff) / 255
        return UIColor(red: red, green: green, blue: blue, alpha: 1)
    }
}

func offlineDownloadCancelMessage(discarding discard: () throws -> Void) -> String {
    do {
        try discard()
        return "Download cancelled"
    } catch {
        return offlineDownloadCancelMessage(for: error)
    }
}

func offlineDownloadCancelMessage(for error: Error) -> String {
    if let tileError = error as? TileError,
       tileError == .downloadAlreadyInProgress {
        return "Download cancelled"
    }
    return "Cancel failed: \(String(describing: error))"
}

enum ListMapFeatureFilter {
    static func visibleFeatures(
        _ features: [(MapPlace, PinState)],
        showVisited: Bool
    ) -> [(MapPlace, PinState)] {
        showVisited ? features : features.filter { _, state in
            state.visit == .none
        }
    }
}

enum ListMapCategoryVisibility {
    static func visibleCategories(
        discoveryVisibleCategories: Set<String>?,
        isListMapActive: Bool
    ) -> Set<String>? {
        isListMapActive ? nil : discoveryVisibleCategories
    }
}

@MainActor
private final class MapScreenModel {
    private let database: AppDatabase
    private let tileCache: TileCache?
    private let offlineStore: OfflineRegionStore?
    private let forceTileNetworkOffline: Bool
    private let fixturePlaces: [String: PlaceRef]
    private let coreLoop: CoreLoopController
    private var tileClients: [MapRegion: TileClient] = [:]
    private var selectedRegion: MapRegion = .malaysia
    private var hiddenTracker: HiddenMembershipTracker
    private var showHiddenPlaces = false

    var changes: AsyncStream<Set<String>> { coreLoop.changes }

    init(
        database: AppDatabase,
        fixturePlaces: [PlaceRef] = [],
        forceTileNetworkOffline: Bool = false
    ) throws {
        MakingTracksLog.startup.info("map model init started fixture=\(fixturePlaces.isEmpty == false, privacy: .public) forcedOffline=\(forceTileNetworkOffline, privacy: .public)")
        self.database = database
        self.forceTileNetworkOffline = forceTileNetworkOffline
        self.fixturePlaces = Dictionary(uniqueKeysWithValues: fixturePlaces.map { ($0.placeID, $0) })
        coreLoop = CoreLoopController(database: database)
        hiddenTracker = HiddenMembershipTracker(hiddenPlaceIDs: try database.hiddenPlaceIDs())
        if fixturePlaces.isEmpty {
            let cacheRoot = try FileManager.default.url(
                for: .cachesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("MakingTracks/Tiles", isDirectory: true)
            tileCache = try TileCache(directory: cacheRoot)
            offlineStore = try? OfflineRegionStore.documentsStore()
        } else {
            tileCache = nil
            offlineStore = nil
        }
        let hasCache = tileCache != nil
        let hasOfflineStore = offlineStore != nil
        MakingTracksLog.startup.info("map model init finished cache=\(hasCache, privacy: .public) offlineStore=\(hasOfflineStore, privacy: .public)")
    }

#if DEBUG
    func installDebugOfflineRegion(
        _ region: String,
        allowsCellularDownloads: Bool,
        progress: @escaping @Sendable (OfflineRegionDownloadProgress) -> Void
    ) async -> String {
        await installOfflineRegion(
            region,
            control: OfflineRegionDownloadControl(),
            allowsCellularDownloads: allowsCellularDownloads,
            progress: progress
        )
    }

    func installOfflineRegion(
        _ region: String,
        control: OfflineRegionDownloadControl,
        resumingPausedDownload: Bool = false,
        allowsCellularDownloads: Bool,
        progress: @escaping @Sendable (OfflineRegionDownloadProgress) -> Void
    ) async -> String {
        guard fixturePlaces.isEmpty,
              let offlineStore,
              Self.isValidRegion(region)
        else {
            MakingTracksLog.install.error("offline install unavailable region=\(region, privacy: .private(mask: .hash))")
            return "Offline install unavailable"
        }
        MakingTracksLog.install.info("offline install requested region=\(region, privacy: .private(mask: .hash))")
        do {
            let documents = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let backgroundIdentifier = OfflineDownloadSession.backgroundIdentifier(region: region)
            await OfflineDownloadSession.prepareBackgroundSessionForPolicyChange(
                identifier: backgroundIdentifier,
                allowsCellularDownloads: allowsCellularDownloads
            )
            let result = try await OfflineDownloadSession.withBackgroundSessionUse(
                identifier: backgroundIdentifier
            ) {
                let downloader = OfflineRegionDownloader(
                    region: region,
                    metadataFetcher: HTTPTileFetcher.offlineForeground(
                        allowsCellularDownloads: allowsCellularDownloads
                    ),
                    objectFetcher: HTTPTileFetcher.offlineBackground(
                        identifier: backgroundIdentifier,
                        allowsCellularDownloads: allowsCellularDownloads
                    ),
                    store: offlineStore,
                    availableBytes: { StorageHeadroom.availableBytes(at: documents) }
                )
                return try await downloader.downloadCurrentRegion(
                    resumingPausedDownload: resumingPausedDownload,
                    control: control,
                    progress: progress
                )
            }
            MakingTracksLog.install.info("offline install completed region=\(region, privacy: .private(mask: .hash)) version=\(result.publish.publishVersion, privacy: .public) bytes=\(result.fetchedBytes, privacy: .public)")
            return "Installed \(result.publish.publishVersion)"
        } catch TileError.downloadPaused {
            MakingTracksLog.install.info("offline install paused region=\(region, privacy: .private(mask: .hash))")
            return "Download paused"
        } catch TileError.downloadCancelled {
            MakingTracksLog.install.info("offline install cancelled region=\(region, privacy: .private(mask: .hash))")
            return "Download cancelled"
        } catch {
            MakingTracksLog.install.error("offline install failed region=\(region, privacy: .private(mask: .hash)) reason=\(MakingTracksLog.errorLabel(error), privacy: .public)")
            return "Install failed: \(String(describing: error))"
        }
    }

    func installedOfflinePublishVersions(for catalog: OfflineRegionCatalog) async -> [String: String] {
        guard let offlineStore else { return [:] }
        let regionIDs = catalog.zones.map(\.id)
        return await Task.detached {
            var installed: [String: String] = [:]
            for regionID in regionIDs {
                guard let publish = try? offlineStore.installedPublish(region: regionID) else { continue }
                installed[regionID] = publish.publishVersion
            }
            return installed
        }.value
    }

    func installedOfflineCoverageBBoxes(for catalog: OfflineRegionCatalog) async -> [CoverageBBox] {
        guard let offlineStore else { return [] }
        let regionIDs = catalog.zones.compactMap { MapRegion(rawValue: $0.id)?.rawValue }
        return await Task.detached {
            var coverage: [CoverageBBox] = []
            for regionID in regionIDs {
                guard let publish = try? offlineStore.installedPublish(region: regionID),
                      publish.manifest.basemap.bbox.count == 4
                else { continue }
                let bbox = publish.manifest.basemap.bbox
                let coverageBBox = CoverageBBox(
                    minLon: bbox[0],
                    minLat: bbox[1],
                    maxLon: bbox[2],
                    maxLat: bbox[3]
                )
                guard coverageBBox.isValid else { continue }
                coverage.append(coverageBBox)
            }
            return coverage.sorted { lhs, rhs in
                if lhs.minLon != rhs.minLon { return lhs.minLon < rhs.minLon }
                if lhs.minLat != rhs.minLat { return lhs.minLat < rhs.minLat }
                if lhs.maxLon != rhs.maxLon { return lhs.maxLon < rhs.maxLon }
                return lhs.maxLat < rhs.maxLat
            }
        }.value
    }

    func availableOfflinePublishVersions(
        for catalog: OfflineRegionCatalog,
        installedRegions: Set<String>,
        allowsCellularDownloads: Bool
    ) async -> [String: String] {
        let regionIDs: [String] = catalog.zones.compactMap { zone in
            guard installedRegions.contains(zone.id) else { return nil }
            return MapRegion(rawValue: zone.id)?.rawValue
        }
        return await withTaskGroup(of: (String, String)?.self) { group in
            for regionID in regionIDs {
                group.addTask {
                    do {
                        let version = try await ManifestClient.currentPublishVersion(
                            region: regionID,
                            fetcher: HTTPTileFetcher.offlineForeground(
                                allowsCellularDownloads: allowsCellularDownloads
                            )
                        )
                        MakingTracksLog.downloads.info("offline catalog current fetched region=\(regionID, privacy: .private(mask: .hash)) version=\(version, privacy: .public)")
                        return (regionID, version)
                    } catch {
                        MakingTracksLog.downloads.error("offline catalog current failed region=\(regionID, privacy: .private(mask: .hash)) reason=\(MakingTracksLog.errorLabel(error), privacy: .public)")
                        return nil
                    }
                }
            }
            var versions: [String: String] = [:]
            for await result in group {
                guard let (regionID, version) = result else { continue }
                versions[regionID] = version
            }
            return versions
        }
    }

    func pausedOfflineDownloadRegions(for catalog: OfflineRegionCatalog) async -> Set<String> {
        guard let offlineStore else { return [] }
        let validRegionIDs = Set(catalog.zones.map(\.id))
        return await Task.detached {
            let paused = (try? offlineStore.pausedPendingDownloadRegions()) ?? []
            return Set(paused.filter { validRegionIDs.contains($0) })
        }.value
    }

    func offlinePackQuarantines() -> [OfflinePackQuarantine] {
        offlineStore?.lastPackQuarantines() ?? []
    }

    func deleteOfflineRegion(_ region: String) async -> String {
        guard let offlineStore, Self.isValidRegion(region) else {
            MakingTracksLog.install.error("offline delete unavailable region=\(region, privacy: .private(mask: .hash))")
            return "Offline delete unavailable"
        }
        return await Task.detached {
            do {
                try offlineStore.delete(region: region)
                MakingTracksLog.install.info("offline delete completed region=\(region, privacy: .private(mask: .hash))")
                return "Deleted \(region)"
            } catch {
                MakingTracksLog.install.error("offline delete failed region=\(region, privacy: .private(mask: .hash)) reason=\(MakingTracksLog.errorLabel(error), privacy: .public)")
                return "Delete failed: \(String(describing: error))"
            }
        }.value
    }

    func discardOfflineRegionDownload(_ region: String) async -> String {
        guard let offlineStore, Self.isValidRegion(region) else {
            MakingTracksLog.downloads.info("offline discard unavailable region=\(region, privacy: .private(mask: .hash))")
            return "Download cancelled"
        }
        return await Task.detached {
            let message = offlineDownloadCancelMessage {
                try offlineStore.discardInProgressDownloads(region: region)
            }
            if message == "Download cancelled" {
                MakingTracksLog.downloads.info("offline discard completed region=\(region, privacy: .private(mask: .hash))")
            } else {
                MakingTracksLog.downloads.error("offline discard failed region=\(region, privacy: .private(mask: .hash)) result=cancel-failed")
            }
            return message
        }.value
    }

    private static func isValidRegion(_ value: String) -> Bool {
        value.range(of: "^[a-z][a-z0-9_]{0,63}$", options: .regularExpression) == value.startIndex..<value.endIndex
    }
#endif

    func performDeferredOfflineMaintenance(
        allowsCellularDownloads: Bool,
        control: OfflineRegionDownloadControl = OfflineRegionDownloadControl(),
        onReplayRegionStart: (@MainActor @Sendable (String) -> Bool)? = nil,
        onReplayRegionPause: (@MainActor @Sendable (String) -> Void)? = nil,
        progress: (@MainActor @Sendable (OfflineRegionDownloadProgress) -> Void)? = nil
    ) async -> Bool {
        guard let offlineStore else { return true }
        return await Task.detached {
            var didResumePendingDownloads = true
            let pendingRegions = (try? offlineStore.pendingDownloadRegions()) ?? []
            for region in pendingRegions {
                do {
                    if let onReplayRegionStart {
                        let didAcquireReplayOwnership = await MainActor.run {
                            onReplayRegionStart(region)
                        }
                        guard didAcquireReplayOwnership else {
                            control.cancel()
                            didResumePendingDownloads = false
                            continue
                        }
                    }
                    let documents = try FileManager.default.url(
                        for: .documentDirectory,
                        in: .userDomainMask,
                        appropriateFor: nil,
                        create: true
                    )
                    let route = DeferredOfflineMaintenanceDownloadRoute(
                        region: region,
                        allowsCellularDownloads: allowsCellularDownloads
                    )
                    await OfflineDownloadSession.prepareBackgroundSessionForPolicyChange(
                        identifier: route.backgroundIdentifier,
                        allowsCellularDownloads: allowsCellularDownloads
                    )
                    _ = try await OfflineDownloadSession.withBackgroundSessionUse(
                        identifier: route.backgroundIdentifier
                    ) {
                        let downloader = OfflineRegionDownloader(
                            region: region,
                            metadataFetcher: route.metadataFetcher(),
                            objectFetcher: route.objectFetcher(),
                            store: offlineStore,
                            availableBytes: { StorageHeadroom.availableBytes(at: documents) }
                        )
                        return try await downloader.downloadCurrentRegion(control: control) { event in
                            if let progress {
                                Task { @MainActor in
                                    progress(event)
                                }
                            }
                        }
                    }
                } catch TileError.downloadPaused {
                    if let onReplayRegionPause {
                        await MainActor.run {
                            onReplayRegionPause(region)
                        }
                    }
                    return false
                } catch {
                    didResumePendingDownloads = false
                }
            }
            do {
                try offlineStore.performDeferredMaintenance()
                return didResumePendingDownloads
            } catch {
                return false
            }
        }.value
    }

    func refreshManifest() async {
        let startedAt = Date()
        guard let client = tileClient(for: selectedRegion) else { return }
        try? await client.refreshPin()
        let state = await client.loadState
        let elapsedMS = Int(Date().timeIntervalSince(startedAt) * 1000)
        let regionID = selectedRegion.rawValue
        let stateLabel = state.rawValue
        MakingTracksLog.startup.info("manifest refresh finished region=\(regionID, privacy: .private(mask: .hash)) state=\(stateLabel, privacy: .public) durationMS=\(elapsedMS, privacy: .public)")
    }

    func storageMenuStatus() async -> StorageMenuStatus {
        guard let offlineStore else {
            MakingTracksLog.startup.info("storage summary unavailable")
            return .unavailable
        }
        let startedAt = Date()
        return await Task.detached {
            do {
                let status = StorageMenuStatus.ready(from: try offlineStore.installedPackStorageSummary())
                let elapsedMS = Int(Date().timeIntervalSince(startedAt) * 1000)
                MakingTracksLog.startup.info("storage summary finished regions=\(status.regions.count, privacy: .public) failed=\(status.failedRegions.count, privacy: .public) bytes=\(status.totalBytes, privacy: .public) durationMS=\(elapsedMS, privacy: .public)")
                return status
            } catch {
                let elapsedMS = Int(Date().timeIntervalSince(startedAt) * 1000)
                MakingTracksLog.startup.error("storage summary failed reason=\(MakingTracksLog.errorLabel(error), privacy: .public) durationMS=\(elapsedMS, privacy: .public)")
                return .unavailable
            }
        }.value
    }

    func features(in bbox: BBox, zoom: Int, allowManifestRefresh: Bool = true) async -> [(MapPlace, PinState)] {
        if !fixturePlaces.isEmpty {
            let sortedFixtures = fixturePlaces.values.sorted { $0.placeID < $1.placeID }
            let states = await states(for: Set(sortedFixtures.map(\.placeID)))
            let next = sortedFixtures.map { fixturePlace in
                let place = MapPlace(
                    id: fixturePlace.placeID,
                    lat: fixturePlace.lat,
                    lon: fixturePlace.lon,
                    tier: fixturePlace.tier,
                    category: fixturePlace.category
                )
                return (place, states[fixturePlace.placeID] ?? PinState(saved: false, visit: .none))
            }
            return PinFeatureFilter.discoveryFeatures(next, showHidden: showHiddenPlaces)
        }
        guard let client = await selectClient(for: bbox, allowManifestRefresh: allowManifestRefresh) else { return [] }
        let places = await client.places(inViewport: bbox, zoom: zoom, allowManifestRefresh: allowManifestRefresh)
        let ids = places.map(\.id)
        let states = await states(for: Set(ids))
        let next = places.map { ($0, states[$0.id] ?? PinState(saved: false, visit: .none)) }
        return PinFeatureFilter.discoveryFeatures(next, showHidden: showHiddenPlaces)
    }

    func setShowHidden(_ showHidden: Bool) {
        showHiddenPlaces = showHidden
    }

    func states(for ids: Set<String>) async -> [String: PinState] {
        let db = database
        var resolved = await Task.detached {
            (try? db.viewportState(Array(ids))) ?? [:]
        }.value
        for id in ids {
            var state = resolved[id] ?? PinState(saved: false, visit: .none)
            state.hidden = hiddenTracker.hiddenIDs.contains(id)
            resolved[id] = state
        }
        return resolved
    }

    var hiddenIDs: Set<String> {
        hiddenTracker.hiddenIDs
    }

    func consumeHiddenMembershipChange(overlapping ids: Set<String>) -> Bool {
        hiddenTracker.consumeHiddenMembershipChange(overlapping: ids)
    }

    func visitCount(placeID: String) async -> Int {
        let db = database
        return await Task.detached {
            (try? db.visitCount(placeID: placeID)) ?? 0
        }.value
    }

    func lists() async -> [PlaceList] {
        let db = database
        return await Task.detached {
            (try? db.lists()) ?? []
        }.value
    }

    func listProgress(listID: Int64) async -> ListProgress {
        let db = database
        return await Task.detached {
            guard let progress = try? db.listProgress(listID: listID) else {
                return ListProgress(visited: 0, total: 0)
            }
            return ListProgress(visited: progress.visited, total: progress.total)
        }.value
    }

    func listItems(listID: Int64) async -> [ListPlace] {
        let db = database
        return await Task.detached {
            (try? db.listItems(listID: listID)) ?? []
        }.value
    }

    func listMemberships(containing placeID: String) async -> [Int64] {
        let db = database
        return await Task.detached {
            (try? db.listMemberships(containing: placeID)) ?? []
        }.value
    }

    func listMapFeatures(listID: Int64, showVisited: Bool) async -> [(MapPlace, PinState)] {
        let db = database
        let features = await Task.detached {
            (try? db.listMapFeatures(listID: listID)) ?? []
        }.value
        return ListMapFeatureFilter.visibleFeatures(
            features,
            showVisited: showVisited
        )
    }

    func createList(named name: String) async throws -> PlaceList {
        let db = database
        return try await Task.detached {
            try db.createList(named: name)
        }.value
    }

    func renameList(id: Int64, name: String) async throws -> PlaceList {
        let db = database
        return try await Task.detached {
            try db.renameList(id: id, name: name)
        }.value
    }

    func deleteList(id: Int64) async throws {
        let db = database
        try await Task.detached {
            try db.deleteList(id: id)
        }.value
    }

    func cardModel(for placeID: String) async -> PlaceCardModel? {
        let pinState = await states(for: [placeID])[placeID] ?? PinState(saved: false, visit: .none)
        guard let source = await cardSource(for: placeID) else { return nil }

        let base: PlaceCardModel?
        switch source {
        case let .tile(placeRef):
            base = PlaceCardModel.from(placeRef: placeRef, pinState: pinState)
        case let .snapshot(_, snapshot):
            base = PlaceCardModel.from(snapshot: snapshot, pinState: pinState)
        case .unavailable:
            return nil
        }
        guard let base else { return nil }
        let lists = await userListNames(containing: placeID)
        return base.enriching(photo: fixturePhoto(for: placeID, name: base.name), listNames: lists)
    }

    private func userListNames(containing placeID: String) async -> [String] {
        let db = database
        return await Task.detached {
            (try? db.userListNames(containing: placeID)) ?? []
        }.value
    }

    private func fixturePhoto(for placeID: String, name: String) -> PlaceCardPhoto? {
        guard fixturePlaces[placeID] != nil else { return nil }
        return PlaceCardPhoto(
            accessibilityLabel: "Photo of \(name)",
            attribution: "Fixture photo"
        )
    }

    func setSaved(placeID: String, saved: Bool) async throws {
        guard let placeRef = await actionPlaceRef(for: placeID) else { throw MapScreenActionError.placeUnavailable }
        try coreLoop.setSaved(placeRef, saved)
    }

    func addToList(placeID: String, listID: Int64) async throws {
        guard let placeRef = await actionPlaceRef(for: placeID) else { throw MapScreenActionError.placeUnavailable }
        try coreLoop.addToList(placeRef, listID: listID)
    }

    func removeFromList(placeID: String, listID: Int64) async throws {
        try coreLoop.removeFromList(placeID: placeID, listID: listID)
    }

    func setVisited(placeID: String, visited: Bool) async throws {
        guard let placeRef = await actionPlaceRef(for: placeID) else { throw MapScreenActionError.placeUnavailable }
        try coreLoop.setVisited(placeRef, visited)
    }

    func setLoved(placeID: String, loved: Bool) async throws {
        try coreLoop.setLoved(placeID: placeID, loved)
    }

    func setHidden(placeID: String, hidden: Bool) async throws {
        guard let placeRef = await actionPlaceRef(for: placeID) else { throw MapScreenActionError.placeUnavailable }
        let rollback = hiddenTracker.beginSetHidden(placeID: placeID, hidden: hidden)
        do {
            try coreLoop.setHidden(placeRef, hidden)
        } catch {
            hiddenTracker.rollback(rollback)
            throw error
        }
    }

    private func cardSource(for placeID: String) async -> CardSource? {
        if let fixturePlace = fixturePlaces[placeID] {
            if let snapshot = try? database.snapshot(for: placeID),
               let placeRef = try? PlaceRef(
                placeID: snapshot.placeID,
                name: snapshot.name,
                lat: snapshot.lat,
                lon: snapshot.lon,
                category: snapshot.category,
                tier: snapshot.tier,
                schemaVersion: snapshot.snapshotSchemaVersion,
                fetchedAt: snapshot.fetchedAt,
                rawJSON: snapshot.snapshotJSON
               ) {
                return .snapshot(placeRef, snapshot)
            }
            return .tile(fixturePlace)
        }
        guard let tileClient = tileClient(for: selectedRegion) else { return nil }
        return await PlaceResolver(tile: tileClient, snapshots: database).source(for: placeID)
    }

    private func actionPlaceRef(for placeID: String) async -> PlaceRef? {
        guard let source = await cardSource(for: placeID) else { return nil }
        switch source {
        case let .tile(placeRef), let .snapshot(placeRef, _):
            return placeRef
        case .unavailable:
            return nil
        }
    }

    var pmtilesURL: String? {
        get async {
            guard let client = tileClient(for: selectedRegion),
                  let url = await client.basemapURL,
                  await client.basemapIntegrity != nil
            else { return nil }
            return "pmtiles://\(url.absoluteString)"
        }
    }

    var attribution: [Attribution] {
        get async {
            guard let client = tileClient(for: selectedRegion) else {
                return [Attribution(source: "osm", license: "ODbL-1.0", text: "OSM credit")]
            }
            return await client.attribution
        }
    }

    var loadState: TileLoadState {
        get async {
            guard let client = tileClient(for: selectedRegion) else { return .ok }
            return await client.loadState
        }
    }

    private func selectClient(for bbox: BBox, allowManifestRefresh: Bool = true) async -> TileClient? {
        let nextRegion = MapRegion.select(for: bbox, current: selectedRegion)
        let changed = nextRegion != selectedRegion
        selectedRegion = nextRegion
        guard let client = tileClient(for: nextRegion) else { return nil }
        if changed {
            MakingTracksLog.resolution.info("region selected region=\(nextRegion.rawValue, privacy: .private(mask: .hash))")
            if allowManifestRefresh {
                try? await client.refreshPin()
            } else {
                await client.loadLocalPin()
            }
        }
        return client
    }

    private func tileClient(for region: MapRegion) -> TileClient? {
        guard let tileCache else { return nil }
        if let cached = tileClients[region] {
            return cached
        }
#if DEBUG
        let fetcher: TileFetching = forceTileNetworkOffline ? OfflineProofFetcher() : HTTPTileFetcher()
#else
        let fetcher: TileFetching = HTTPTileFetcher()
#endif
        let client = TileClient(
            region: region.rawValue,
            fetcher: fetcher,
            cache: tileCache,
            offlineStore: offlineStore
        )
        tileClients[region] = client
        let regionID = region.rawValue
        let hasOfflineStore = offlineStore != nil
        MakingTracksLog.startup.info("tile client created region=\(regionID, privacy: .private(mask: .hash)) offlineStore=\(hasOfflineStore, privacy: .public)")
        return client
    }
}

#if DEBUG
private struct OfflineProofFetcher: TileFetching {
    func fetch(_ url: URL) async throws -> Data {
        throw URLError(.notConnectedToInternet)
    }
}
#endif
