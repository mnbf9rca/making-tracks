import CoreLocation
import ImageIO
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

struct PlaceCardVisualSpec {
    enum ActionTone: Equatable {
        case primary
        case neutral
        case love
        case warning
        case disabled
    }

    static let closeSystemImageName = "ellipsis"
    static let showsMediaSlotWhenPhotoMissing = false
    static let actionCornerRadius: CGFloat = 8
    static let actionMinimumHeight: CGFloat = 44
    static let mediaSlotHeight: CGFloat = 132
    static let cardCornerRadius: CGFloat = 22
    static let typeSwatchSide: CGFloat = 14
    static let actionBarHorizontalPadding: CGFloat = 18
    static let cardBackground = Color(red: 0.985, green: 0.98, blue: 0.95)
    static let mediaBackground = Color(red: 0.82, green: 0.79, blue: 0.70)
    static let neutralActionBackground = Color(red: 0.93, green: 0.92, blue: 0.88)
    static let primaryActionBackground = Color(red: 0.02, green: 0.46, blue: 0.39)
    static let loveActionBackground = Color(red: 0.99, green: 0.89, blue: 0.89)
    static let warningActionBackground = Color(red: 0.95, green: 0.91, blue: 0.82)
    static let disabledActionBackground = Color(red: 0.96, green: 0.95, blue: 0.91)
    static let primaryText = Color(red: 0.12, green: 0.12, blue: 0.11)
    static let secondaryText = Color(red: 0.43, green: 0.42, blue: 0.38)
    static let linkText = Color(red: 0.0, green: 0.43, blue: 0.37)
    static let loveText = Color(red: 0.77, green: 0.19, blue: 0.17)
    static let warningText = Color(red: 0.46, green: 0.34, blue: 0.12)
    static let disabledText = Color(red: 0.68, green: 0.66, blue: 0.61)

    static func tone(for action: PlaceCardAction) -> ActionTone {
        switch action {
        case .seen:
            return .primary
        case .love, .unlove:
            return .love
        case .unsee(isEnabled: true):
            return .warning
        case .unsee(isEnabled: false), .seenDisabled:
            return .disabled
        case .save, .hide, .unhide:
            return .neutral
        }
    }

    static func actionBackground(for tone: ActionTone) -> Color {
        switch tone {
        case .primary:
            return primaryActionBackground
        case .neutral:
            return neutralActionBackground
        case .love:
            return loveActionBackground
        case .warning:
            return warningActionBackground
        case .disabled:
            return disabledActionBackground
        }
    }

    static func actionForeground(for tone: ActionTone) -> Color {
        switch tone {
        case .primary:
            return .white
        case .neutral:
            return primaryText
        case .love:
            return loveText
        case .warning:
            return warningText
        case .disabled:
            return disabledText
        }
    }
}

private enum MapOverlayChromeSpec {
    static let edgePadding: CGFloat = 16
    static let topPadding: CGFloat = 12
    static let listModeControlHeight: CGFloat = 56
    static let listModeControlBottomPadding: CGFloat = 24
    static let listModeAuxiliaryChromeClearance: CGFloat = 12

    static var listModeAuxiliaryBottomPadding: CGFloat {
        listModeControlHeight + listModeControlBottomPadding + listModeAuxiliaryChromeClearance
    }
}

struct OfflineRegionCatalogZone: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let parentID: String?
    let bbox: BBox
    let publishVersion: String
    let searchCompactPublishVersion: String?
    let bytesWithoutThumbnails: Int
    let bytesWithThumbnails: Int

    init(
        id: String,
        displayName: String,
        parentID: String?,
        bbox: BBox = BBox(minLon: -180, minLat: -90, maxLon: 180, maxLat: 90),
        publishVersion: String,
        searchCompactPublishVersion: String? = nil,
        bytesWithoutThumbnails: Int,
        bytesWithThumbnails: Int
    ) {
        self.id = id
        self.displayName = displayName
        self.parentID = parentID
        self.bbox = bbox
        self.publishVersion = publishVersion
        self.searchCompactPublishVersion = searchCompactPublishVersion
        self.bytesWithoutThumbnails = bytesWithoutThumbnails
        self.bytesWithThumbnails = bytesWithThumbnails
    }

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

    static let empty = OfflineRegionCatalog(zones: [])

#if DEBUG
    static let debugFixture = OfflineRegionCatalog(zones: [
        OfflineRegionCatalogZone(
            id: MapRegion.unitedKingdom.rawValue,
            displayName: "United Kingdom",
            parentID: nil,
            bbox: MapRegion.unitedKingdom.viewportBBox,
            publishVersion: "20260718T000000Z",
            searchCompactPublishVersion: "20260718T000000Z",
            bytesWithoutThumbnails: 2_640_000_000,
            bytesWithThumbnails: 3_180_000_000
        ),
        OfflineRegionCatalogZone(
            id: "united-kingdom_london",
            displayName: "London",
            parentID: MapRegion.unitedKingdom.rawValue,
            bbox: BBox(minLon: -0.51, minLat: 51.28, maxLon: 0.33, maxLat: 51.70),
            publishVersion: "20260718T000000Z",
            searchCompactPublishVersion: "20260718T000000Z",
            bytesWithoutThumbnails: 842_000_000,
            bytesWithThumbnails: 1_160_000_000
        ),
        OfflineRegionCatalogZone(
            id: "united-kingdom_south_east",
            displayName: "South East England",
            parentID: MapRegion.unitedKingdom.rawValue,
            bbox: BBox(minLon: -1.9, minLat: 50.7, maxLon: 1.9, maxLat: 52.2),
            publishVersion: "20260718T000000Z",
            searchCompactPublishVersion: "20260718T000000Z",
            bytesWithoutThumbnails: 1_120_000_000,
            bytesWithThumbnails: 1_410_000_000
        ),
        OfflineRegionCatalogZone(
            id: MapRegion.malaysiaSingaporeBrunei.rawValue,
            displayName: "Malaysia, Singapore, and Brunei",
            parentID: nil,
            bbox: MapRegion.malaysiaSingaporeBrunei.viewportBBox,
            publishVersion: "20260718T000000Z",
            searchCompactPublishVersion: "20260718T000000Z",
            bytesWithoutThumbnails: 1_420_000_000,
            bytesWithThumbnails: 1_980_000_000
        ),
        OfflineRegionCatalogZone(
            id: "malaysia-singapore-brunei_kl",
            displayName: "Kuala Lumpur",
            parentID: MapRegion.malaysiaSingaporeBrunei.rawValue,
            bbox: BBox(minLon: 101.4, minLat: 2.8, maxLon: 101.9, maxLat: 3.4),
            publishVersion: "20260718T000000Z",
            searchCompactPublishVersion: "20260718T000000Z",
            bytesWithoutThumbnails: 610_000_000,
            bytesWithThumbnails: 915_000_000
        ),
        OfflineRegionCatalogZone(
            id: "malaysia-singapore-brunei_penang",
            displayName: "Penang",
            parentID: MapRegion.malaysiaSingaporeBrunei.rawValue,
            bbox: BBox(minLon: 100.1, minLat: 5.1, maxLon: 100.6, maxLat: 5.7),
            publishVersion: "20260718T000000Z",
            searchCompactPublishVersion: "20260718T000000Z",
            bytesWithoutThumbnails: 520_000_000,
            bytesWithThumbnails: 760_000_000
        ),
    ])
#endif

    init(zones: [OfflineRegionCatalogZone]) {
        self.zones = zones
    }

    init(regionIndex: RegionIndex) {
        self.zones = regionIndex.regions.map { entry in
            guard let searchPublishVersion = Self.publishVersion(fromSearchCompactPath: entry.searchCompact.path) else {
                preconditionFailure("RegionIndex.decode must validate search_compact.path before catalog construction")
            }
            return OfflineRegionCatalogZone(
                id: entry.id,
                displayName: entry.displayName,
                parentID: entry.parent,
                bbox: entry.bbox,
                publishVersion: searchPublishVersion,
                searchCompactPublishVersion: searchPublishVersion,
                bytesWithoutThumbnails: entry.bytesWithoutThumbnails,
                bytesWithThumbnails: entry.bytesWithThumbnails
            )
        }
    }

    static func current(fetcher: TileFetching, cache: OfflineRegionCatalogCache? = nil) async throws -> OfflineRegionCatalog {
        guard let url = URL(string: "https://\(HTTPTileFetcher.trustedHost)/regions.json") else {
            throw TileError.invalidURL
        }
        try HTTPTileFetcher.validateOrigin(url)
        do {
            let data: Data
            if let boundedFetcher = fetcher as? BoundedTileFetching {
                data = try await boundedFetcher.fetch(url, maxBytes: RegionIndex.maxBytes)
            } else {
                data = try await fetcher.fetch(url)
            }
            guard data.count <= RegionIndex.maxBytes else { throw TileError.responseTooLarge }
            let catalog = try OfflineRegionCatalog(regionIndex: RegionIndex.decode(data))
            try? cache?.store(data)
            return catalog
        } catch {
            if let cached = try? cache?.cachedCatalog() {
                return cached
            }
            throw error
        }
    }

    private static func publishVersion(fromSearchCompactPath path: String) -> String? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count >= 4,
              parts[parts.count - 2] == "search",
              parts[parts.count - 1] == "compact.json"
        else { return nil }
        return String(parts[parts.count - 3])
    }

    var rootZones: [OfflineRegionCatalogZone] {
        zones.filter { $0.parentID == nil }.sorted(by: zoneSort)
    }

    func zone(id: String) -> OfflineRegionCatalogZone? {
        zones.first { $0.id == id }
    }

    func children(of parentID: String) -> [OfflineRegionCatalogZone] {
        zones.filter { $0.parentID == parentID }.sorted(by: zoneSort)
    }

    func selectedRootZoneID(for viewport: BBox, current: String? = nil) -> String? {
        let roots = rootZones
        if let current,
           let currentZone = roots.first(where: { $0.id == current }),
           currentZone.bbox.intersects(viewport) {
            return current
        }
        let intersecting = roots.filter { $0.bbox.intersects(viewport) }
        if intersecting.count == 1 {
            return intersecting[0].id
        }
        if let current, roots.contains(where: { $0.id == current }) {
            return current
        }
        return roots.min(by: {
            Self.distanceSquared($0.bbox.center, viewport.center)
                < Self.distanceSquared($1.bbox.center, viewport.center)
        })?.id
    }

    func rows(
        installed: [String: String],
        installedStorageBytes: [String: Int] = [:],
        availablePublishVersions: [String: String] = [:],
        availableStorageBytes: [String: Int] = [:],
        activeProgress: OfflineDownloadProgress?,
        pausedProgress: OfflineDownloadProgress? = nil,
        pausedRegions: Set<String> = [],
        quarantines: [OfflinePackQuarantine]
    ) -> [OfflineRegionCatalogRow] {
        let quarantineByRegion = quarantines.reduce(into: [String: OfflinePackQuarantine]()) { byRegion, quarantine in
            byRegion[quarantine.region] = quarantine
        }
        let catalogRows = rootZones.flatMap {
            rows(
                for: $0,
                depth: 0,
                installed: installed,
                installedStorageBytes: installedStorageBytes,
                availablePublishVersions: availablePublishVersions,
                availableStorageBytes: availableStorageBytes,
                activeProgress: activeProgress,
                pausedProgress: pausedProgress,
                pausedRegions: pausedRegions,
                quarantines: quarantineByRegion
            )
        }
        return catalogRows + unavailableLocalRows(
            knownZoneIDs: Set(zones.map(\.id)),
            installed: installed,
            installedStorageBytes: installedStorageBytes,
            activeProgress: activeProgress,
            pausedProgress: pausedProgress,
            pausedRegions: pausedRegions,
            quarantines: quarantineByRegion
        )
    }

    private func rows(
        for zone: OfflineRegionCatalogZone,
        depth: Int,
        installed: [String: String],
        installedStorageBytes: [String: Int],
        availablePublishVersions: [String: String],
        availableStorageBytes: [String: Int],
        activeProgress: OfflineDownloadProgress?,
        pausedProgress: OfflineDownloadProgress?,
        pausedRegions: Set<String>,
        quarantines: [String: OfflinePackQuarantine]
    ) -> [OfflineRegionCatalogRow] {
        let state: OfflineRegionCatalogRow.State
        if let quarantine = quarantines[zone.id] {
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
            if let availablePublishVersion = availablePublishVersions[zone.id],
               zone.searchCompactPublishVersion == availablePublishVersion
            {
                state = .notInstalled
            } else {
                state = .unavailable
            }
        }
        let current = OfflineRegionCatalogRow(
            zone: zone,
            depth: depth,
            state: state,
            knownByteSize: knownByteSize(
                for: zone.id,
                state: state,
                installedStorageBytes: installedStorageBytes,
                availableStorageBytes: availableStorageBytes
            ),
            hasUnavailableLocalData: false,
            hasUnavailablePausedDownload: false
        )
        return [current] + children(of: zone.id).flatMap {
            rows(
                for: $0,
                depth: depth + 1,
                installed: installed,
                installedStorageBytes: installedStorageBytes,
                availablePublishVersions: availablePublishVersions,
                availableStorageBytes: availableStorageBytes,
                activeProgress: activeProgress,
                pausedProgress: pausedProgress,
                pausedRegions: pausedRegions,
                quarantines: quarantines
            )
        }
    }

    private func unavailableLocalRows(
        knownZoneIDs: Set<String>,
        installed: [String: String],
        installedStorageBytes: [String: Int],
        activeProgress: OfflineDownloadProgress?,
        pausedProgress: OfflineDownloadProgress?,
        pausedRegions: Set<String>,
        quarantines: [String: OfflinePackQuarantine]
    ) -> [OfflineRegionCatalogRow] {
        let localIDs = Set(installed.keys)
            .union(pausedRegions)
            .union(quarantines.keys)
            .union([activeProgress?.region, pausedProgress?.region].compactMap { $0 })
        return localIDs
            .subtracting(knownZoneIDs)
            .sorted()
            .map { regionID in
                OfflineRegionCatalogRow(
                    zone: OfflineRegionCatalogZone(
                        id: regionID,
                        displayName: regionID,
                        parentID: nil,
                        publishVersion: "",
                        bytesWithoutThumbnails: 0,
                        bytesWithThumbnails: 0
                    ),
                    depth: 0,
                    state: .unavailable,
                    knownByteSize: installedStorageBytes[regionID],
                    hasUnavailableLocalData: installed[regionID] != nil || quarantines[regionID] != nil,
                    hasUnavailablePausedDownload: activeProgress?.region == regionID
                        || pausedProgress?.region == regionID
                        || pausedRegions.contains(regionID)
                )
            }
    }

    private func knownByteSize(
        for region: String,
        state: OfflineRegionCatalogRow.State,
        installedStorageBytes: [String: Int],
        availableStorageBytes: [String: Int]
    ) -> Int? {
        switch state {
        case let .downloading(progress), let .paused(progress):
            if progress.region == region, let totalBytes = progress.totalBytes, totalBytes > 0 {
                return totalBytes
            }
            return installedStorageBytes[region]
        case .installed, .unavailable, .quarantined:
            return installedStorageBytes[region]
        case .notInstalled, .updateAvailable:
            return availableStorageBytes[region]
        }
    }

    private func zoneSort(_ lhs: OfflineRegionCatalogZone, _ rhs: OfflineRegionCatalogZone) -> Bool {
        if lhs.displayName != rhs.displayName {
            return lhs.displayName < rhs.displayName
        }
        return lhs.id < rhs.id
    }

    private static func distanceSquared(
        _ lhs: (lon: Double, lat: Double),
        _ rhs: (lon: Double, lat: Double)
    ) -> Double {
        let dLon = lhs.lon - rhs.lon
        let dLat = lhs.lat - rhs.lat
        return dLon * dLon + dLat * dLat
    }
}

struct OfflineRegionCatalogCache: Sendable, Equatable {
    let directory: URL

    init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    static func appCache() throws -> OfflineRegionCatalogCache {
        let cacheRoot = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return try OfflineRegionCatalogCache(
            directory: cacheRoot.appendingPathComponent("MakingTracks/RegionCatalog", isDirectory: true)
        )
    }

    func cachedCatalog() throws -> OfflineRegionCatalog? {
        guard FileManager.default.fileExists(atPath: catalogURL.path) else { return nil }
        let data = try Data(contentsOf: catalogURL)
        guard data.count <= RegionIndex.maxBytes else { throw TileError.responseTooLarge }
        return try OfflineRegionCatalog(regionIndex: RegionIndex.decode(data))
    }

    func store(_ data: Data) throws {
        guard data.count <= RegionIndex.maxBytes else { throw TileError.responseTooLarge }
        _ = try OfflineRegionCatalog(regionIndex: RegionIndex.decode(data))
        try data.write(to: catalogURL, options: .atomic)
    }

    private var catalogURL: URL {
        directory.appendingPathComponent("regions.json")
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
    let knownByteSize: Int?
    let hasUnavailableLocalData: Bool
    let hasUnavailablePausedDownload: Bool

    init(
        zone: OfflineRegionCatalogZone,
        depth: Int,
        state: State,
        knownByteSize: Int? = nil,
        hasUnavailableLocalData: Bool = false,
        hasUnavailablePausedDownload: Bool = false
    ) {
        self.zone = zone
        self.depth = depth
        self.state = state
        self.knownByteSize = knownByteSize
        self.hasUnavailableLocalData = hasUnavailableLocalData
        self.hasUnavailablePausedDownload = hasUnavailablePausedDownload
    }

    var id: String { zone.id }

    func sizeLabel(includeThumbnails: Bool) -> String {
        if let knownByteSize {
            return ByteCountFormatter.string(fromByteCount: Int64(max(knownByteSize, 0)), countStyle: .file)
        }
        return zone.sizeLabel(includeThumbnails: includeThumbnails)
    }

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
            progress.isWaitingForConnectivity ? progress.statusText : progress.isComplete ? "Installing" : "Downloading \(progress.percentComplete)%"
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

    static let klMid = ViewportSeed(
        bbox: kl.bbox,
        zoom: 13
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

    static let klStreet = ViewportSeed(
        bbox: BBox(minLon: 101.676, minLat: 3.126, maxLon: 101.704, maxLat: 3.154),
        zoom: 14
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
        case "kl-mid":
            return .klMid
        case "kl-street":
            return .klStreet
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
    let fitBounds: Bool

    init(id: Int, viewport: ViewportSeed, fitBounds: Bool = false) {
        self.id = id
        self.viewport = viewport
        self.fitBounds = fitBounds
    }
}

enum MenuDestination: Hashable {
    case lists
    case listDetail(Int64)
    case tracks
    case offlineMaps
    case settings
    case diagnostics
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
    var tracksFocusPlaceID: String?
    var listDetailVisitFilter = TracksVisitFilter.all

    func openMenu() {
        tracksFocusPlaceID = nil
        listDetailVisitFilter = .all
        deepLinkPath = nil
        isMenuPresented = true
    }

    func openListDetailDeepLink(listID: Int64, visitFilter: TracksVisitFilter = .all) {
        tracksFocusPlaceID = nil
        listDetailVisitFilter = visitFilter
        deepLinkPath = .listDetail(listID)
        isMenuPresented = true
    }
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

    static func listNameCreateFailureMessage(for error: Error, draftName _: String) -> String {
        switch error as? AppDatabaseError {
        case .emptyListName:
            return "Enter a list name."
        case .listNameTooLong:
            return "Use a shorter list name."
        case .invalidListName:
            return "Could not create that list."
        default:
            return "Could not create that list."
        }
    }
}

struct TracksCopy {
    static let sortDirectionLabel = "Oldest first"

    static func summary(visible: Int, lovedOnly: Bool) -> String {
        guard visible > 0 else { return lovedOnly ? "No loved visits yet" : "No visits yet" }
        let noun = visible == 1 ? "visit" : "visits"
        return lovedOnly ? "\(visible) \(noun) for loved places" : "\(visible) \(noun)"
    }
}

enum TrackVisitRowDensitySpec {
    static let usesInlineEditControls = false
    static let showsStandaloneDateLabel = true
    static let verticalSpacing: CGFloat = 8
    static let horizontalSpacing: CGFloat = 10
    static let minimumHeight: CGFloat = 112
}

enum TrackVisitEditorVisualSpec {
    static let paperBackground = MapThemeColor.color(hex: "#f1eddf")
    static let cardBackground = MapThemeColor.color(hex: "#fffdf7")
    static let divider = MapThemeColor.color(hex: "#ddd8ca")
    static let accent = MapThemeColor.color(hex: "#0a6b5c")
    static let accentSoft = MapThemeColor.color(hex: "#e3f0eb")
    static let danger = MapThemeColor.color(hex: "#b42318")
    static let dangerSoft = MapThemeColor.color(hex: "#f8e7e4")
}

struct TrackVisitDaySection: Identifiable, Equatable {
    let day: Date
    let visits: [TrackVisit]

    var id: Date { day }
}

struct TrackVisitRow: Identifiable, Equatable {
    let visit: TrackVisit
    let dayHeader: Date?

    var id: Int64 { visit.id }
}

enum TrackVisitReordering {
    enum MovePlan: Equatable {
        case reorderDay(day: Date, orderedIDs: [Int64])
        case moveVisit(id: Int64, targetDay: Date, targetDayOrderedIDs: [Int64])
    }

    static func daySections(
        for visits: [TrackVisit],
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> [TrackVisitDaySection] {
        visits.reduce(into: []) { sections, visit in
            let day = calendar.startOfDay(for: visit.visitedAt)
            if let index = sections.indices.last, sections[index].day == day {
                sections[index] = TrackVisitDaySection(
                    day: day,
                    visits: sections[index].visits + [visit]
                )
            } else {
                sections.append(TrackVisitDaySection(day: day, visits: [visit]))
            }
        }
    }

    static func reorderedIDs(
        in visits: [TrackVisit],
        fromOffsets source: IndexSet,
        toOffset destination: Int
    ) -> [Int64]? {
        guard !source.isEmpty,
              destination >= 0,
              destination <= visits.count,
              source.allSatisfy({ visits.indices.contains($0) })
        else {
            return nil
        }

        var nextVisits = visits
        let movingVisits = source.sorted().map { visits[$0] }
        for index in source.sorted(by: >) {
            nextVisits.remove(at: index)
        }

        let removedBeforeDestination = source.filter { $0 < destination }.count
        let insertionIndex = destination - removedBeforeDestination
        guard insertionIndex >= 0, insertionIndex <= nextVisits.count else {
            return nil
        }

        nextVisits.insert(contentsOf: movingVisits, at: insertionIndex)
        let nextIDs = nextVisits.map(\.id)
        return nextIDs == visits.map(\.id) ? nil : nextIDs
    }

    static func startsNewDay(
        visit: TrackVisit,
        previous: TrackVisit?,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> Bool {
        guard let previous else { return true }
        return calendar.startOfDay(for: visit.visitedAt) != calendar.startOfDay(for: previous.visitedAt)
    }

    static func rows(
        for visits: [TrackVisit],
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> [TrackVisitRow] {
        visits.enumerated().map { index, visit in
            let day = calendar.startOfDay(for: visit.visitedAt)
            let previous = index > 0 ? visits[index - 1] : nil
            return TrackVisitRow(
                visit: visit,
                dayHeader: startsNewDay(visit: visit, previous: previous, calendar: calendar) ? day : nil
            )
        }
    }

    static func movePlan(
        in visits: [TrackVisit],
        fromOffsets source: IndexSet,
        toOffset destination: Int,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> MovePlan? {
        guard !source.isEmpty,
              destination >= 0,
              destination <= visits.count,
              source.allSatisfy({ visits.indices.contains($0) })
        else {
            return nil
        }

        let movingVisits = source.sorted().map { visits[$0] }
        var remainingVisits = visits
        for index in source.sorted(by: >) {
            remainingVisits.remove(at: index)
        }

        let removedBeforeDestination = source.filter { $0 < destination }.count
        let insertionIndex = destination - removedBeforeDestination
        guard insertionIndex >= 0, insertionIndex <= remainingVisits.count else {
            return nil
        }

        var nextVisits = remainingVisits
        nextVisits.insert(contentsOf: movingVisits, at: insertionIndex)
        guard nextVisits.map(\.id) != visits.map(\.id) else { return nil }

        func day(for visit: TrackVisit) -> Date {
            calendar.startOfDay(for: visit.visitedAt)
        }

        let originalDays = Set(movingVisits.map(day))
        let originalDay = originalDays.count == 1 ? originalDays.first : nil
        let previousDay = insertionIndex > 0 ? day(for: nextVisits[insertionIndex - 1]) : nil
        let nextIndex = insertionIndex + movingVisits.count
        let nextDay = nextIndex < nextVisits.count ? day(for: nextVisits[nextIndex]) : nil
        let targetDay: Date
        if let previousDay, previousDay == nextDay {
            targetDay = previousDay
        } else if let originalDay, previousDay == originalDay || nextDay == originalDay {
            targetDay = originalDay
        } else if let nextDay {
            targetDay = nextDay
        } else if let previousDay {
            targetDay = previousDay
        } else {
            targetDay = day(for: movingVisits[0])
        }

        let movingIDs = Set(movingVisits.map(\.id))
        let targetDayOrderedIDs = nextVisits.compactMap { visit -> Int64? in
            movingIDs.contains(visit.id) || day(for: visit) == targetDay ? visit.id : nil
        }

        if movingVisits.count == 1, originalDays.first != targetDay {
            return .moveVisit(
                id: movingVisits[0].id,
                targetDay: targetDay,
                targetDayOrderedIDs: targetDayOrderedIDs
            )
        }

        guard originalDays == [targetDay] else { return nil }
        return .reorderDay(day: targetDay, orderedIDs: targetDayOrderedIDs)
    }
}

enum ListMapModeCopy {
    static let tracksLayerTitle = "My tracks"

    static func freshLayerTitle(theme: MapTheme) -> String {
        theme.freshPhrase
    }
}

struct TrackTimelineDateMarker: Equatable, Sendable {
    let eventIndex: Int
    let position: Double
    let label: String
}

enum TrackTimelineAutoplayStep: Equatable, Sendable {
    case event(index: Int)
    case finished
}

extension Calendar {
    static var gregorianCurrentTimeZone: Calendar {
        Calendar(identifier: .gregorian)
    }
}

enum TrackReplayPinPresentation {
    static func features(
        _ features: [(MapPlace, PinState)],
        context: TrackGeometryContext,
        throughEventIndex index: Int?
    ) -> [(MapPlace, PinState)] {
        guard !context.visits.isEmpty else { return [] }
        let replayPlaceIDs = Set(context.visits.map(\.placeID))
        let reachedVisitStateByPlaceID = context.clipped(throughEventIndex: index).visits.reduce(into: [String: VisitState]()) { states, visit in
            states[visit.placeID] = visit.verdict == .loved ? .loved : .visited
        }
        return features.compactMap { place, state in
            guard replayPlaceIDs.contains(place.id) else { return nil }
            return (
                place,
                PinState(
                    saved: state.saved,
                    visit: reachedVisitStateByPlaceID[place.id] ?? .none,
                    hidden: state.hidden
                )
            )
        }
    }

    static func pulsePlaceID(context: TrackGeometryContext, throughEventIndex index: Int?) -> String? {
        guard let index,
              context.visits.indices.contains(index)
        else { return nil }
        return context.visits[index].placeID
    }

    static func pulsePlaceIDs(
        context: TrackGeometryContext,
        throughEventIndex index: Int?,
        isArrivalPulsing: Bool
    ) -> Set<String> {
        guard isArrivalPulsing,
              let placeID = pulsePlaceID(context: context, throughEventIndex: index)
        else { return [] }
        return [placeID]
    }
}

enum TrackMapFeatureFilter {
    static func visibleFeatures(
        _ features: [(MapPlace, PinState)],
        context: TrackGeometryContext
    ) -> [(MapPlace, PinState)] {
        let visiblePlaceIDs = Set(context.visits.map(\.placeID))
        return features.filter { place, _ in visiblePlaceIDs.contains(place.id) }
    }
}

enum ListMapFilteredFeatures {
    static func visibleFeatures(
        _ features: [(MapPlace, PinState)],
        showVisited: Bool,
        visitFilter: TracksVisitFilter,
        context: TrackGeometryContext
    ) -> [(MapPlace, PinState)] {
        guard showVisited, visitFilter.isActive else { return features }
        return TrackMapFeatureFilter.visibleFeatures(features, context: context)
    }
}

struct ListMapFilterChip: Equatable, Identifiable {
    let id: String
    let title: String
    let systemImage: String?
    let accessibilityIdentifier: String
    let isToggle: Bool
    let isSelected: Bool
}

enum ListMapFilterChips {
    static func chips(for filter: TracksVisitFilter) -> [ListMapFilterChip] {
        var chips: [ListMapFilterChip] = [
            ListMapFilterChip(
                id: "loved",
                title: "Loved",
                systemImage: "heart.fill",
                accessibilityIdentifier: "map.list-mode.filter.loved",
                isToggle: false,
                isSelected: filter.lovedOnly
            )
        ]
        if !filter.listIDs.isEmpty {
            let count = filter.listIDs.count
            chips.append(ListMapFilterChip(
                id: "lists",
                title: count == 1 ? "1 list" : "\(count) lists",
                systemImage: "list.bullet",
                accessibilityIdentifier: "map.list-mode.filter.lists",
                isToggle: false,
                isSelected: true
            ))
        }
        for category in filter.categories.sorted() {
            chips.append(ListMapFilterChip(
                id: "category-\(identifierSuffix(for: category))",
                title: category,
                systemImage: "tag.fill",
                accessibilityIdentifier: "map.list-mode.filter.category.\(identifierSuffix(for: category))",
                isToggle: false,
                isSelected: true
            ))
        }
        return chips
    }

    private static func identifierSuffix(for value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.lowercased().unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        return String(scalars)
    }
}

struct TrackFilterPickerDraft: Equatable, Sendable {
    var lovedOnly: Bool
    var listIDs: Set<Int64>
    var categories: Set<String>

    init(filter: TracksVisitFilter = .all) {
        lovedOnly = filter.lovedOnly
        listIDs = filter.listIDs
        categories = filter.categories
    }

    var filter: TracksVisitFilter {
        TracksVisitFilter(lovedOnly: lovedOnly, listIDs: listIDs, categories: categories)
    }

    mutating func toggleLoved() {
        lovedOnly.toggle()
    }

    mutating func toggleList(id: Int64) {
        if listIDs.contains(id) {
            listIDs.remove(id)
        } else {
            listIDs.insert(id)
        }
    }

    mutating func toggleCategory(_ category: String) {
        if categories.contains(category) {
            categories.remove(category)
        } else {
            categories.insert(category)
        }
    }
}

enum TrackFilterPickerCopy {
    static func applyLabel(scopedVisitCount: Int) -> String {
        let count = max(0, scopedVisitCount)
        return count == 1 ? "Show 1 visit" : "Show \(count) visits"
    }
}

struct TrackFilterPickerListOption: Equatable, Identifiable {
    let id: Int64
    let title: String
}

struct TrackReplaySnapshotCache: Sendable {
    static let empty = TrackReplaySnapshotCache(context: .empty)

    private let context: TrackGeometryContext
    private let snapshots: [TrackSourceSnapshot]

    init(context: TrackGeometryContext) {
        self.context = context
        snapshots = []
    }

    private init(context: TrackGeometryContext, snapshots: [TrackSourceSnapshot]) {
        self.context = context
        self.snapshots = snapshots
    }

    static func precomputed(
        context: TrackGeometryContext,
        isCancelled: @Sendable () -> Bool = { Task.isCancelled }
    ) -> TrackReplaySnapshotCache? {
        var snapshots = [TrackSourceSnapshot]()
        snapshots.reserveCapacity(context.visits.count)
        for index in context.visits.indices {
            guard !isCancelled() else { return nil }
            snapshots.append(makeSnapshot(context: context, throughEventIndex: index))
        }
        guard !isCancelled() else { return nil }
        return TrackReplaySnapshotCache(context: context, snapshots: snapshots)
    }

    func snapshot(throughEventIndex index: Int?) -> TrackSourceSnapshot {
        guard let index else {
            return snapshots.last ?? Self.makeSnapshot(context: context, throughEventIndex: context.visits.indices.last)
        }
        guard index >= 0 else { return .empty }
        if snapshots.indices.contains(index) {
            return snapshots[index]
        }
        guard context.visits.indices.contains(index) else {
            return snapshots.last ?? Self.makeSnapshot(context: context, throughEventIndex: context.visits.indices.last)
        }
        return Self.makeSnapshot(context: context, throughEventIndex: index)
    }

    func snapshot(throughEventIndex index: Int?, activeArcProgress: Double) -> TrackSourceSnapshot {
        guard activeArcProgress < 1,
              let index,
              index > 0
        else { return snapshot(throughEventIndex: index) }
        guard context.visits.indices.contains(index) else { return snapshot(throughEventIndex: nil) }
        let context = context.clipped(throughEventIndex: index)
        return TrackSourceSnapshot.make(
            context: context,
            activeToVisitID: context.visits.last?.id,
            activeArcProgress: activeArcProgress
        )
    }

    private static func makeSnapshot(context: TrackGeometryContext, throughEventIndex index: Int?) -> TrackSourceSnapshot {
        guard let index else { return .empty }
        guard index >= 0 else { return .empty }
        let clippedContext = context.clipped(throughEventIndex: index)
        return TrackSourceSnapshot.make(
            context: clippedContext,
            activeToVisitID: index > 0 ? clippedContext.visits.last?.id : nil
        )
    }
}

enum TrackTimelineDateMarkerLayout {
    static let markerSlotWidth: CGFloat = 56 // Tunable UI slot width for abbreviated dates near slider edges.
}

enum TrackReplayTimelineZoomLevel: Equatable, Sendable {
    case coarse
    case detail

    static let detailVelocityThreshold: CGFloat = 240

    static func level(forDragVelocity velocity: CGFloat) -> TrackReplayTimelineZoomLevel {
        abs(velocity) > detailVelocityThreshold ? .coarse : .detail
    }
}

struct TrackReplayTimelineMark: Equatable, Sendable {
    let eventIndex: Int
    let position: Double
    let label: String
    let isLabeled: Bool
    let isSelected: Bool
}

enum TrackReplayTimelineLayout {
    static func marks(
        timeline: TrackTimelineModel,
        selectedIndex: Int?,
        availableWidth: Double,
        zoomLevel: TrackReplayTimelineZoomLevel
    ) -> [TrackReplayTimelineMark] {
        guard !timeline.visits.isEmpty else { return [] }
        let labeledIndices = labeledEventIndices(
            timeline: timeline,
            selectedIndex: selectedIndex,
            availableWidth: availableWidth,
            zoomLevel: zoomLevel
        )
        return timeline.visits.indices.map { index in
            TrackReplayTimelineMark(
                eventIndex: index,
                position: TrackTimelineModel.normalizedPosition(eventIndex: index, eventCount: timeline.visits.count),
                label: label(for: timeline.visits[index], zoomLevel: zoomLevel),
                isLabeled: labeledIndices.contains(index),
                isSelected: selectedIndex == index
            )
        }
    }

    private static func labeledEventIndices(
        timeline: TrackTimelineModel,
        selectedIndex: Int?,
        availableWidth: Double,
        zoomLevel: TrackReplayTimelineZoomLevel
    ) -> Set<Int> {
        switch zoomLevel {
        case .coarse:
            let maxCount = max(Int(availableWidth / Double(TrackTimelineDateMarkerLayout.markerSlotWidth)), 2)
            guard timeline.visits.count > maxCount else { return Set(timeline.visits.indices) }
            return Set([timeline.visits.startIndex, timeline.visits.index(before: timeline.visits.endIndex)])
        case .detail:
            let selected = selectedIndex ?? timeline.visits.startIndex
            return Set((selected - 1...selected + 1).filter { timeline.visits.indices.contains($0) })
        }
    }

    private static func label(for visit: TrackVisit, zoomLevel: TrackReplayTimelineZoomLevel) -> String {
        switch zoomLevel {
        case .coarse:
            return visit.visitedAt.formatted(.dateTime.year())
        case .detail:
            return visit.visitedAt.formatted(date: .omitted, time: .shortened)
        }
    }
}

struct TrackTimelineModel: Equatable, Sendable {
    // Tunable per #257; autoplay is event-paced, not derived from visit timestamps or slider distance.
    static var autoplayBeatDuration: TimeInterval {
#if DEBUG
        if let override = debugAutoplayBeatDuration {
            return override
        }
#endif
        return 0.5
    }

#if DEBUG
    private static var debugAutoplayBeatDuration: TimeInterval? {
        guard let index = CommandLine.arguments.firstIndex(of: "--ui-testing-track-replay-beat-duration"),
              CommandLine.arguments.indices.contains(index + 1),
              let value = TimeInterval(CommandLine.arguments[index + 1]),
              value.isFinite,
              value > 0
        else { return nil }
        return value
    }
#endif

    let visits: [TrackVisit]
    let dateMarkers: [TrackTimelineDateMarker]

    init(visits: [TrackVisit], calendar: Calendar = .gregorianCurrentTimeZone) {
        self.visits = visits
        var seenDays = Set<DateComponents>()
        dateMarkers = visits.enumerated().compactMap { index, visit in
            let components = calendar.dateComponents([.year, .month, .day], from: visit.visitedAt)
            guard seenDays.insert(components).inserted else { return nil }
            return TrackTimelineDateMarker(
                eventIndex: index,
                position: Self.normalizedPosition(eventIndex: index, eventCount: visits.count),
                label: Self.dateLabel(for: visit.visitedAt, calendar: calendar)
            )
        }
    }

    var sliderRange: ClosedRange<Double> {
        0...Double(max(visits.count - 1, 0))
    }

    var hasInteractiveReplayControls: Bool {
        visits.count > 1
    }

    func eventIndex(forSliderValue value: Double) -> Int {
        guard !visits.isEmpty else { return 0 }
        let rounded = Int(value.rounded())
        return min(max(rounded, 0), visits.count - 1)
    }

    func autoplayStep(after index: Int?) -> TrackTimelineAutoplayStep {
        let next = (index ?? -1) + 1
        guard next < visits.count else { return .finished }
        return .event(index: next)
    }

    func shouldPulseArrival(previousIndex: Int?, nextIndex: Int) -> Bool {
        previousIndex != nextIndex && visits.indices.contains(nextIndex)
    }

    func scrubEventPath(from currentIndex: Int?, to targetIndex: Int) -> [Int] {
        guard !visits.isEmpty else { return [] }
        let target = eventIndex(forSliderValue: Double(targetIndex))
        let start = currentIndex.map { eventIndex(forSliderValue: Double($0)) } ?? -1
        guard start != target else { return [target] }
        let step = start < target ? 1 : -1
        return stride(from: start + step, through: target, by: step).map { $0 }
    }

    func visitsThroughEvent(index: Int?) -> [TrackVisit] {
        guard let index, visits.indices.contains(index) else { return [] }
        return Array(visits.prefix(index + 1))
    }

    func dateMarkers(availableWidth: Double) -> [TrackTimelineDateMarker] {
        guard dateMarkers.count > 2 else { return dateMarkers }
        let maxMarkerCount = Self.maxDateMarkerCount(availableWidth: availableWidth)
        guard dateMarkers.count > maxMarkerCount else { return dateMarkers }
        guard maxMarkerCount > 2 else {
            return [dateMarkers[0], dateMarkers[dateMarkers.count - 1]]
        }
        let stride = Double(dateMarkers.count - 1) / Double(maxMarkerCount - 1)
        var selected: [TrackTimelineDateMarker] = []
        var selectedEventIndices = Set<Int>()
        for slot in 0..<maxMarkerCount {
            let markerIndex = Int((Double(slot) * stride).rounded())
            let clampedIndex = min(max(markerIndex, 0), dateMarkers.count - 1)
            let marker = dateMarkers[clampedIndex]
            if selectedEventIndices.insert(marker.eventIndex).inserted {
                selected.append(marker)
            }
        }
        return selected
    }

    func selectedVisit(after index: Int?) -> TrackVisit? {
        guard let index, visits.indices.contains(index) else { return nil }
        return visits[index]
    }

    func selectedTimeLabel(after index: Int?) -> String {
        selectedVisit(after: index).map { Self.timeLabel(for: $0.visitedAt) } ?? ""
    }

    var startTimeLabel: String {
        visits.first.map { Self.timeLabel(for: $0.visitedAt) } ?? ""
    }

    var endTimeLabel: String {
        visits.last.map { Self.timeLabel(for: $0.visitedAt) } ?? ""
    }

    func accessibilityValue(for index: Int?) -> String {
        guard !visits.isEmpty else { return "No visits" }
        let eventIndex = eventIndex(forSliderValue: Double(index ?? 0))
        let visit = visits[eventIndex]
        let loved = visit.verdict == .loved ? ", loved" : ""
        return "Visit \(eventIndex + 1) of \(visits.count), \(visit.name), \(visit.visitedAt.formatted(date: .abbreviated, time: .shortened))\(loved)"
    }

    static func normalizedPosition(eventIndex: Int, eventCount: Int) -> Double {
        guard eventCount > 1 else { return 0 }
        return Double(eventIndex) / Double(eventCount - 1)
    }

    private static func maxDateMarkerCount(availableWidth: Double) -> Int {
        max(Int(availableWidth / Double(TrackTimelineDateMarkerLayout.markerSlotWidth)), 2)
    }

    private static func dateLabel(for date: Date, calendar: Calendar) -> String {
        var format = Date.FormatStyle.dateTime.day().month(.abbreviated)
        format.calendar = calendar
        format.locale = calendar.locale ?? .current
        format.timeZone = calendar.timeZone
        return date.formatted(format)
    }

    private static func timeLabel(for date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

}

private struct TrackTimelineDateMarkersView: View {
    let timeline: TrackTimelineModel

    private static let markerHeight: CGFloat = 14

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(timeline.dateMarkers(availableWidth: proxy.size.width), id: \.eventIndex) { marker in
                    Text(verbatim: marker.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: TrackTimelineDateMarkerLayout.markerSlotWidth, alignment: marker.position < 0.5 ? .leading : .trailing)
                        .offset(x: xOffset(for: marker, width: proxy.size.width))
                }
            }
        }
        .frame(height: Self.markerHeight)
        .accessibilityHidden(true)
    }

    private func xOffset(for marker: TrackTimelineDateMarker, width: CGFloat) -> CGFloat {
        guard width > TrackTimelineDateMarkerLayout.markerSlotWidth else { return 0 }
        let centered = width * CGFloat(marker.position) - TrackTimelineDateMarkerLayout.markerSlotWidth / 2
        return min(max(centered, 0), width - TrackTimelineDateMarkerLayout.markerSlotWidth)
    }
}

private enum TrackReplayTimelineControlSpec {
    static let height: CGFloat = 58
    static let trackY: CGFloat = 27
    static let trackHeight: CGFloat = 5
    static let tickHeight: CGFloat = 13
    static let selectedTickHeight: CGFloat = 20
    static let handleOuterSize: CGFloat = 28
    static let handleInnerSize: CGFloat = 12
    static let labelSlotWidth: CGFloat = 56
    static let elapsedColor = Color(red: 0.176, green: 0.549, blue: 0.514)
    static let remainingColor = Color(uiColor: .systemGray4)
    static let activeColor = Color(red: 0.859, green: 0.325, blue: 0.267)
}

private enum TrackReplayArcGlideSpec {
    static let frameCount = 10
    static let frameIntervalMilliseconds = 32
    static let arrivalPulseMilliseconds = 260
}

private struct TrackReplayTimelineAccessibilitySlider: UIViewRepresentable {
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    let accessibilityValue: String
    let onValueChanged: (Double) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UISlider {
        let slider = UISlider(frame: .zero)
        slider.addTarget(
            context.coordinator,
            action: #selector(Coordinator.valueChanged(_:)),
            for: .valueChanged
        )
        configure(slider)
        return slider
    }

    func updateUIView(_ slider: UISlider, context: Context) {
        context.coordinator.parent = self
        configure(slider)
        let nextValue = Float(value)
        if abs(slider.value - nextValue) > 0.001 {
            slider.value = nextValue
        }
    }

    private func configure(_ slider: UISlider) {
        slider.minimumValue = Float(range.lowerBound)
        slider.maximumValue = Float(range.upperBound)
        slider.isContinuous = true
        slider.minimumTrackTintColor = .clear
        slider.maximumTrackTintColor = .clear
        slider.thumbTintColor = .clear
        slider.setThumbImage(Self.transparentThumbImage, for: .normal)
        slider.setThumbImage(Self.transparentThumbImage, for: .highlighted)
        slider.accessibilityLabel = "Track replay"
        slider.accessibilityValue = accessibilityValue
        slider.accessibilityIdentifier = "map.track-replay.slider"
    }

    private static let transparentThumbImage: UIImage = {
        UIGraphicsImageRenderer(size: CGSize(width: 28, height: 28)).image { rendererContext in
            UIColor.clear.setFill()
            rendererContext.cgContext.fill(CGRect(x: 0, y: 0, width: 28, height: 28))
        }
    }()

    final class Coordinator: NSObject {
        var parent: TrackReplayTimelineAccessibilitySlider

        init(parent: TrackReplayTimelineAccessibilitySlider) {
            self.parent = parent
        }

        @MainActor
        @objc func valueChanged(_ sender: UISlider) {
            let rawValue = Double(sender.value)
            let steppedValue: Double
            if parent.step > 0 {
                steppedValue = (rawValue / parent.step).rounded() * parent.step
            } else {
                steppedValue = rawValue
            }
            let clampedValue = min(max(steppedValue, parent.range.lowerBound), parent.range.upperBound)
            if abs(Double(sender.value) - clampedValue) > 0.001 {
                sender.value = Float(clampedValue)
            }
            parent.onValueChanged(clampedValue)
        }
    }
}

private struct TrackReplayTimelineControl: View {
    let timeline: TrackTimelineModel
    let selectedIndex: Int?
    let zoomLevel: TrackReplayTimelineZoomLevel
    let onZoomLevelChanged: (TrackReplayTimelineZoomLevel) -> Void
    let onScrub: (Int) -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let selected = resolvedSelectedIndex
            let selectedPosition = CGFloat(TrackTimelineModel.normalizedPosition(
                eventIndex: selected,
                eventCount: timeline.visits.count
            )) * width
            let marks = TrackReplayTimelineLayout.marks(
                timeline: timeline,
                selectedIndex: selected,
                availableWidth: Double(width),
                zoomLevel: zoomLevel
            )

            ZStack(alignment: .topLeading) {
                timelineChrome(width: width, selected: selected, selectedPosition: selectedPosition, marks: marks)
                    .accessibilityHidden(true)

                TrackReplayTimelineAccessibilitySlider(
                    value: Double(selected),
                    range: timeline.sliderRange,
                    step: 1,
                    accessibilityValue: timeline.accessibilityValue(for: selected),
                    onValueChanged: { value in
                        onScrub(timeline.eventIndex(forSliderValue: value))
                    }
                )
                .frame(height: TrackReplayTimelineControlSpec.height)
                .simultaneousGesture(dragGesture(width: width))
            }
        }
        .frame(height: TrackReplayTimelineControlSpec.height)
    }

    private var resolvedSelectedIndex: Int {
        timeline.eventIndex(forSliderValue: Double(selectedIndex ?? 0))
    }

    private func timelineChrome(
        width: CGFloat,
        selected: Int,
        selectedPosition: CGFloat,
        marks: [TrackReplayTimelineMark]
    ) -> some View {
        ZStack(alignment: .topLeading) {
            Capsule()
                .fill(TrackReplayTimelineControlSpec.remainingColor)
                .frame(width: width, height: TrackReplayTimelineControlSpec.trackHeight)
                .position(x: width / 2, y: TrackReplayTimelineControlSpec.trackY)

            Capsule()
                .fill(TrackReplayTimelineControlSpec.elapsedColor)
                .frame(width: max(selectedPosition, TrackReplayTimelineControlSpec.trackHeight), height: TrackReplayTimelineControlSpec.trackHeight)
                .position(x: max(selectedPosition / 2, TrackReplayTimelineControlSpec.trackHeight / 2), y: TrackReplayTimelineControlSpec.trackY)

            if selected > 0 {
                let previousPosition = CGFloat(TrackTimelineModel.normalizedPosition(
                    eventIndex: selected - 1,
                    eventCount: timeline.visits.count
                )) * width
                Capsule()
                    .fill(TrackReplayTimelineControlSpec.activeColor)
                    .frame(
                        width: max(selectedPosition - previousPosition, TrackReplayTimelineControlSpec.trackHeight),
                        height: TrackReplayTimelineControlSpec.trackHeight
                    )
                    .position(
                        x: previousPosition + max(selectedPosition - previousPosition, TrackReplayTimelineControlSpec.trackHeight) / 2,
                        y: TrackReplayTimelineControlSpec.trackY
                    )
            }

            ForEach(marks, id: \.eventIndex) { mark in
                let x = CGFloat(mark.position) * width
                Rectangle()
                    .fill(tickColor(for: mark, selected: selected))
                    .frame(
                        width: mark.isSelected ? 3 : 2,
                        height: mark.isSelected
                            ? TrackReplayTimelineControlSpec.selectedTickHeight
                            : TrackReplayTimelineControlSpec.tickHeight
                    )
                    .position(x: x, y: TrackReplayTimelineControlSpec.trackY)

                if mark.isLabeled {
                    Text(verbatim: mark.label)
                        .font(.caption2.weight(mark.isSelected ? .semibold : .regular))
                        .foregroundStyle(mark.isSelected ? TrackReplayTimelineControlSpec.activeColor : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: TrackReplayTimelineControlSpec.labelSlotWidth, alignment: labelAlignment(for: mark.position))
                        .position(x: labelX(for: x, width: width), y: 48)
                }
            }

            Text(verbatim: timeline.selectedTimeLabel(after: selected))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(TrackReplayTimelineControlSpec.activeColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: TrackReplayTimelineControlSpec.labelSlotWidth)
                .position(x: labelX(for: selectedPosition, width: width), y: 8)

            Circle()
                .fill(Color(uiColor: .systemBackground))
                .frame(
                    width: TrackReplayTimelineControlSpec.handleOuterSize,
                    height: TrackReplayTimelineControlSpec.handleOuterSize
                )
                .overlay {
                    Circle()
                        .stroke(TrackReplayTimelineControlSpec.activeColor, lineWidth: 3)
                    Circle()
                        .fill(TrackReplayTimelineControlSpec.activeColor)
                        .frame(
                            width: TrackReplayTimelineControlSpec.handleInnerSize,
                            height: TrackReplayTimelineControlSpec.handleInnerSize
                        )
                }
                .shadow(color: .black.opacity(0.14), radius: 3, x: 0, y: 1)
                .position(x: selectedPosition, y: TrackReplayTimelineControlSpec.trackY)
        }
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let velocity = value.predictedEndTranslation.width - value.translation.width
                onZoomLevelChanged(TrackReplayTimelineZoomLevel.level(forDragVelocity: velocity))
                onScrub(eventIndex(forLocationX: value.location.x, width: width))
            }
            .onEnded { _ in
                onZoomLevelChanged(.coarse)
            }
    }

    private func tickColor(for mark: TrackReplayTimelineMark, selected: Int) -> Color {
        if mark.isSelected { return TrackReplayTimelineControlSpec.activeColor }
        return mark.eventIndex < selected
            ? TrackReplayTimelineControlSpec.elapsedColor
            : TrackReplayTimelineControlSpec.remainingColor
    }

    private func labelAlignment(for position: Double) -> Alignment {
        if position < 0.08 { return .leading }
        if position > 0.92 { return .trailing }
        return .center
    }

    private func labelX(for x: CGFloat, width: CGFloat) -> CGFloat {
        let half = TrackReplayTimelineControlSpec.labelSlotWidth / 2
        return min(max(x, half), max(half, width - half))
    }

    private func eventIndex(forLocationX locationX: CGFloat, width: CGFloat) -> Int {
        guard width > 0 else { return 0 }
        let normalized = min(max(locationX / width, 0), 1)
        let rawIndex = Double(normalized) * Double(max(timeline.visits.count - 1, 0))
        return timeline.eventIndex(forSliderValue: rawIndex)
    }
}

enum ListMapPinPresentation {
    static func presentation(showVisited: Bool) -> PinPresentation {
        showVisited ? .tracks : .discovery
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
        if let totalBytes, totalBytes <= 0 { return 0 }
        if boundedFraction >= 1 { return 100 }
        return Int((boundedFraction * 100).rounded(.down))
    }

    var isComplete: Bool {
        if let totalBytes {
            return totalBytes > 0 && (completedBytes ?? 0) >= totalBytes
        }
        return boundedFraction >= 1
    }

    private var boundedFraction: Double {
        guard fractionComplete.isFinite else { return 0 }
        return min(max(fractionComplete, 0), 1)
    }

    private var floorFraction: Double {
        if let totalBytes {
            guard totalBytes > 0 else { return 0 }
            if let completedBytes {
                return min(max(Double(completedBytes) / Double(totalBytes), 0), 1)
            }
        }
        return boundedFraction
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

    func floored(by previous: OfflineDownloadProgress?) -> OfflineDownloadProgress {
        guard let previous,
              previous.region == nil || region == nil || previous.region == region,
              previous.floorFraction > floorFraction
        else { return self }
        return OfflineDownloadProgress(
            region: region ?? previous.region,
            publishVersion: publishVersion ?? previous.publishVersion,
            completedBytes: maxOptional(completedBytes, previous.completedBytes),
            totalBytes: totalBytes ?? previous.totalBytes,
            fractionComplete: previous.floorFraction,
            isWaitingForConnectivity: isWaitingForConnectivity
        )
    }

    private func maxOptional(_ lhs: Int?, _ rhs: Int?) -> Int? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return max(lhs, rhs)
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        case (nil, nil):
            return nil
        }
    }
}

func offlineInstallFailureMessage(for error: Error) -> String {
    if case TileError.httpStatus(404) = error {
        return "This area isn't available yet"
    }
    return "Install failed: \(String(describing: error))"
}

func offlineInstallFailureDetail(for error: Error) -> String {
    MakingTracksLog.errorLabel(error)
}

enum OfflineCoverageBBox {
    static func coverage(fromManifestBasemapBBox bbox: [Double]) -> CoverageBBox? {
        guard bbox.count == 4 else { return nil }
        let coverage = CoverageBBox(
            minLon: bbox[0],
            minLat: bbox[1],
            maxLon: bbox[2],
            maxLat: bbox[3]
        )
        guard coverage.isValid else { return nil }
        return coverage
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
        sourceFeatureCount: Int? = nil,
        loadState: TileLoadState,
        viewport: ViewportSeed,
        isFixtureMap: Bool,
        isViewportLoading: Bool = false
    ) -> MapEmptyRegionSurface? {
        let availableFeatureCount = sourceFeatureCount ?? features.count
        guard !isFixtureMap, !isViewportLoading, features.isEmpty, availableFeatureCount == 0 else { return nil }
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
            return "Making Tracks v1 covers \(MapRegion.coverageListText)."
        case .mapDataUnavailable:
            return "The world map is still available. Check your connection or download a region for offline browsing."
        case .noPlaces:
            return "Try another part of \(MapRegion.coverageListText)."
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
        tracksFocusPlaceID = nil
        listDetailVisitFilter = .all
        deepLinkPath = .lists
        isMenuPresented = true
    }

    func openTracksDeepLink(focusingPlaceID placeID: String? = nil) {
        tracksFocusPlaceID = placeID
        listDetailVisitFilter = .all
        deepLinkPath = .tracks
        isMenuPresented = true
    }

    func openOfflineMapsDeepLink() {
        tracksFocusPlaceID = nil
        listDetailVisitFilter = .all
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

enum ListMapViewport {
    static func places(
        for features: [(MapPlace, PinState)],
        showVisited: Bool,
        visitFilter: TracksVisitFilter,
        context: TrackGeometryContext
    ) -> [MapPlace] {
        guard showVisited, visitFilter.isActive else {
            return features.map(\.0)
        }
        let filteredPlaceIDs = Set(context.visits.map(\.placeID))
        return features.map(\.0).filter { filteredPlaceIDs.contains($0.id) }
    }

    static func viewport(for places: [MapPlace]) -> ViewportSeed? {
        guard let first = places.first else { return nil }
        var minLat = first.lat
        var maxLat = first.lat
        var longitudes = [first.lon]
        for place in places.dropFirst() {
            longitudes.append(place.lon)
            minLat = min(minLat, place.lat)
            maxLat = max(maxLat, place.lat)
        }
        let lonBounds = shortestLongitudeBounds(for: longitudes)
        let lonSpan = lonBounds.max - lonBounds.min
        let lonPad = padding(for: lonSpan, placeCount: places.count)
        let latPad = padding(for: maxLat - minLat, placeCount: places.count)
        return ViewportSeed(
            bbox: BBox(
                minLon: lonBounds.min - lonPad,
                minLat: minLat - latPad,
                maxLon: lonBounds.max + lonPad,
                maxLat: maxLat + latPad
            ),
            zoom: places.count == 1 ? 14 : 12
        )
    }

    private static func padding(for span: Double, placeCount: Int) -> Double {
        guard placeCount > 1 else { return 0.01 }
        return max(span * 0.12, 0.001)
    }

    private static func shortestLongitudeBounds(for longitudes: [Double]) -> (min: Double, max: Double) {
        let sorted = longitudes.map(normalizeLongitude).sorted()
        guard sorted.count > 1 else {
            let lon = sorted.first ?? 0
            return (lon, lon)
        }

        var largestGap = -Double.infinity
        var largestGapIndex = 0
        for index in sorted.indices {
            let nextIndex = sorted.index(after: index)
            let next = nextIndex == sorted.endIndex ? sorted[sorted.startIndex] + 360 : sorted[nextIndex]
            let gap = next - sorted[index]
            if gap > largestGap {
                largestGap = gap
                largestGapIndex = index
            }
        }

        let startIndex = sorted.index(after: largestGapIndex) == sorted.endIndex ? sorted.startIndex : sorted.index(after: largestGapIndex)
        let start = sorted[startIndex]
        let end = sorted[largestGapIndex] < start ? sorted[largestGapIndex] + 360 : sorted[largestGapIndex]
        return (start, end)
    }

    private static func normalizeLongitude(_ longitude: Double) -> Double {
        var value = longitude.truncatingRemainder(dividingBy: 360)
        if value < -180 {
            value += 360
        } else if value >= 180 {
            value -= 360
        }
        return value
    }
}

extension BBox {
    func contains(lon: Double, lat: Double) -> Bool {
        let normalizedLon = lon < minLon ? lon + 360 : lon
        return (minLon...maxLon).contains(normalizedLon) && (minLat...maxLat).contains(lat)
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
        let resumedProgress = pausedProgress?.region == region ? pausedProgress : nil
        activeControl = control
        activeTask = nil
        activeDownloadID = downloadID
        pausedProgress = nil
        liveProgress = resumedProgress ?? OfflineDownloadProgress(region: region, publishVersion: nil, completedBytes: 0, totalBytes: nil, fractionComplete: 0)
        MakingTracksLog.downloads.info("ui session began region=\(region, privacy: .private(mask: .hash))")
    }

    func attach(task: Task<Void, Never>) {
        activeTask = task
        MakingTracksLog.downloads.debug("ui session task attached")
    }

    func update(_ progress: OfflineDownloadProgress) {
        let next = progress.floored(by: liveProgress ?? pausedProgress)
        liveProgress = next
        MakingTracksLog.downloads.debug("ui progress updated region=\(next.region ?? "unknown", privacy: .private(mask: .hash)) version=\(next.publishVersion ?? "unknown", privacy: .public) percent=\(next.percentComplete, privacy: .public) bytes=\(next.completedBytes ?? -1, privacy: .public) total=\(next.totalBytes ?? -1, privacy: .public)")
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
    static let coverageShadingStorageKey = "map.coverageShading.visible"

    let database: AppDatabase
    let startupViewport: ViewportSeed
    var isFixtureMap = false
    var debugInstallOfflineRegion: String?
    var debugForceTileNetworkOffline = false
    var offlineDownloadProgress: OfflineDownloadProgress?
    var debugCoverageBBoxes: [CoverageBBox] = []
    var debugExposeFixturePinDiagnostics = false
    var debugHideFixtureChrome = false
    var debugUseDenseFixturePins = false
    var onReplayOnboarding: @MainActor () -> Void = {}
    var cameraRequest: ViewportCameraRequest?

    @State private var model: MapScreenModel?
    @StateObject private var locationPermission: LocationPermission
    @AppStorage(Self.themeStorageKey) private var selectedThemeID = MapTheme.definedPaper.id
    @AppStorage(OfflineDownloadSettings.allowsCellularDownloadsKey) private var allowsCellularDownloads = OfflineDownloadSettings.defaultAllowsCellularDownloads
    @AppStorage(Self.pinSizeMultiplierStorageKey) private var pinSizeMultiplier = PinSize.defaultMultiplier
    @AppStorage(Self.coverageShadingStorageKey) private var showCoverageShading = true
    @Environment(\.scenePhase) private var scenePhase
    @State private var worldPMTilesURL: String? = WorldBasemap.pmtilesURL()
    @State private var features: [(MapPlace, PinState)] = []
    @State private var sourceFeatureCount = 0
    @State private var trackSourceSnapshot = TrackSourceSnapshot.empty
    @State private var trackReplayContext = TrackGeometryContext.empty
    @State private var trackReplaySnapshotCache = TrackReplaySnapshotCache.empty
    @State private var selectedTrackReplayEventIndex: Int?
    @State private var trackReplayTimelineZoomLevel = TrackReplayTimelineZoomLevel.coarse
    @State private var isTrackReplayAutoplaying = false
    @State private var trackReplayArrivalPulseVisitID: Int64?
    @State private var trackReplaySnapshotPrecomputeTask: Task<Void, Never>?
    @State private var trackReplaySnapshotPrecomputeGeneration = 0
    @State private var trackReplayAutoplayTask: Task<Void, Never>?
    @State private var trackReplayScrubTask: Task<Void, Never>?
    @State private var trackReplayArcGlideTask: Task<Void, Never>?
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
    @State private var isTrackFilterPickerPresented = false
    @State private var trackFilterPickerDraft = TrackFilterPickerDraft()
    @State private var trackFilterPickerLists: [PlaceList] = []
    @State private var trackFilterPickerScopedVisitCount = 0
    private let viewportRefreshDebouncer = ViewportRefreshDebouncer()
    @State private var suppressedNearbyPromptPlaceIDs: Set<String> = []
    @State private var nearbyPromptFeatures: [(MapPlace, PinState)] = []
    @State private var nearbyPromptNames: [String: String] = [:]
    @State private var listMapPinNames: [String: String] = [:]
    @State private var debugProjectedFixturePins: [ProjectedFeatureDiagnostic] = []
    @State private var debugMapUpdateStatus = "not-updated"
    @State private var debugTrackSourceStatus = "track source not-updated"
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
        debugHideFixtureChrome: Bool = false,
        debugUseDenseFixturePins: Bool = false,
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
        self.debugHideFixtureChrome = debugHideFixtureChrome
        self.debugUseDenseFixturePins = debugUseDenseFixturePins
        self.onReplayOnboarding = onReplayOnboarding
        self.cameraRequest = cameraRequest
        self.locationManager = locationManager
        _features = State(initialValue: isFixtureMap ? Self.initialFixtureFeatures(dense: debugUseDenseFixturePins) : [])
        _installedCoverageBBoxes = State(initialValue: debugCoverageBBoxes)
        _layerVisibility = State(initialValue: MapLayerVisibility(showCoverageShading: UserDefaults.standard.object(forKey: Self.coverageShadingStorageKey) as? Bool ?? true))
        _locationPermission = StateObject(wrappedValue: locationPermission ?? LocationPermission(manager: locationManager))
    }

    var body: some View {
        ZStack {
            GeometryReader { _ in
                MLNMapViewRepresentable(
                worldPMTilesURL: worldPMTilesURL,
                regionPMTilesURL: regionPMTilesURL,
                coverageBBoxes: installedCoverageBBoxes,
                showsCoverageShading: layerVisibility.showCoverageShading,
                theme: selectedTheme,
                startupViewport: startupViewport,
                features: visibleMapFeatures,
                pinPresentation: pinPresentation,
                trackReplayPulsePlaceIDs: trackReplayPulsePlaceIDs,
                trackSourceSnapshot: visibleTrackSourceSnapshot,
                pinAccessibilityNames: pinAccessibilityNames,
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
                        MakingTracksLog.flowEvent("place tapped", fields: [
                            .object("placeID", placeID),
                            .public("source", "map"),
                        ])
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
                        MakingTracksLog.flowEvent("screen opened", fields: [
                            .public("screen", "map"),
                            .public("state", "ready"),
                        ])
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
                debugReportTrackSourceStatus: { status in
                    guard debugExposeFixturePinDiagnostics else { return }
                    Task { @MainActor in
                        guard debugTrackSourceStatus != status else { return }
                        debugTrackSourceStatus = status
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
                    .padding(.top, MapOverlayChromeSpec.topPadding)
                    .padding(.leading, MapOverlayChromeSpec.edgePadding)
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
                    .padding(.top, MapOverlayChromeSpec.topPadding)
                    .padding(.trailing, MapOverlayChromeSpec.edgePadding)
            }
            .overlay(alignment: .bottomLeading) {
                attributionText
                    .padding(.leading, MapOverlayChromeSpec.edgePadding)
                    .padding(.bottom, auxiliaryBottomChromePadding)
            }
            .overlay(alignment: .bottomTrailing) {
                locationChrome
                    .padding(.trailing, MapOverlayChromeSpec.edgePadding)
                    .padding(.bottom, auxiliaryBottomChromePadding)
            }
            .overlay(alignment: .bottom) {
                Group {
                    if let activeListMap {
                        if TrackReplayControlVisibility.showOnMap(list: activeListMap, timeline: trackReplayTimeline) {
                            mapTrackReplayControls(trackReplayTimeline)
                        } else {
                            listMapModeChrome(activeListMap)
                        }
                    }
                }
                .padding(.horizontal, MapOverlayChromeSpec.edgePadding)
                .padding(.bottom, MapOverlayChromeSpec.listModeControlBottomPadding)
            }
            .overlay(alignment: .bottom) {
                if let prompt = nearbyPromptCandidate {
                    nearbyPromptView(for: prompt)
                        .padding(.bottom, 88)
                        .padding(.horizontal, MapOverlayChromeSpec.edgePadding)
                }
            }
            .overlay(alignment: .bottom) {
                if let hiddenToast {
                    hiddenToastView(for: hiddenToast)
                        .padding(.bottom, hiddenToastBottomPadding)
                        .padding(.horizontal, MapOverlayChromeSpec.edgePadding)
                }
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
                onShowListOnMap: { list, filter in
                    Task { @MainActor in
                        await showListOnMap(list, filter: filter)
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
        .sheet(isPresented: $isTrackFilterPickerPresented) {
            TrackFilterPickerSheet(
                draft: $trackFilterPickerDraft,
                listOptions: trackFilterPickerListOptions,
                categoryOptions: layerVisibility.categories,
                scopedVisitCount: trackFilterPickerScopedVisitCount,
                onDraftChanged: {
                    Task { @MainActor in
                        await refreshTrackFilterPickerScopedVisitCount()
                    }
                },
                onApply: {
                    applyTrackFilterPickerDraft()
                }
            )
            .presentationDetents([.medium, .large])
            .onAppear {
                logSheetOpened("track-filter-picker")
            }
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
            ensureModel()
            if let model {
                async let dataChanges: Void = observeChanges(from: model)
                async let viewportChanges: Void = observeViewportChanges(from: model)
                await start()
                Task { await refreshStorageMenuStatus() }
                _ = await (dataChanges, viewportChanges)
            } else {
                await start()
                Task { await refreshStorageMenuStatus() }
            }
        }
        .onChange(of: appShell.isMenuPresented) { _, isPresented in
            guard isPresented else { return }
            cardPresentation.dismiss()
            Task { await refreshStorageMenuStatus() }
        }
        .onChange(of: layerVisibility) { _, visibility in
            showCoverageShading = visibility.showCoverageShading
            Task { @MainActor in
                await applyLayerVisibility(visibility)
            }
        }
        .sheet(isPresented: $showLayers) {
            LayersSheet(
                visibility: $layerVisibility
            )
                .presentationDetents([.medium, .large])
                .onAppear {
                    logSheetOpened("layers")
                }
        }
        .sheet(item: cardPresentationItemBinding) { presentation in
            PlaceCardSheet(
                placeID: presentation.placeID,
                model: model,
                onHide: { placeID, name in
                    showHiddenToast(placeID: placeID, name: name)
                },
                onManageVisits: { placeID in
                    appShell.openTracksDeepLink(focusingPlaceID: placeID)
                },
                setNearbyPromptSuppressed: { placeID, suppressed in
                    setNearbyPromptSuppressed(placeID: placeID, suppressed: suppressed)
                },
                showHiddenMode: layerVisibility.showHiddenPlaces
            )
        }
        .onDisappear {
            cancelHiddenToastDismissTask()
            stopMapTrackAutoplay()
            stopTrackReplaySnapshotPrecompute()
        }
    }

    private var pinAccessibilityNames: [String: String] {
        var names = nearbyPromptNames
        names.merge(listMapPinNames) { _, listName in listName }
        if isFixtureMap {
            for fixturePlace in Self.uiTestingFixturePlaces(dense: debugUseDenseFixturePins) {
                names[fixturePlace.placeID] = fixturePlace.name
            }
        }
        return names
    }

    private var trackFilterPickerListOptions: [TrackFilterPickerListOption] {
        trackFilterPickerLists.compactMap { list in
            guard !list.isSystem, let id = list.id else { return nil }
            return TrackFilterPickerListOption(id: id, title: list.name)
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

    private func logSheetOpened(_ sheet: String) {
        MakingTracksLog.flowEvent("sheet opened", fields: [
            .public("sheet", sheet),
        ])
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
            sourceFeatureCount: sourceFeatureCount,
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

            if isFixtureMap && !debugHideFixtureChrome {
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

                Text(verbatim: debugTrackSourceStatus)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .accessibilityIdentifier("map.debug-track-source-status")

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
            mapChrome
        }
    }

    private var auxiliaryBottomChromePadding: CGFloat {
        activeListMap == nil ? MapOverlayChromeSpec.edgePadding : MapOverlayChromeSpec.listModeAuxiliaryBottomPadding
    }

    private var hiddenToastBottomPadding: CGFloat {
        activeListMap == nil ? MapOverlayChromeSpec.listModeControlBottomPadding : MapOverlayChromeSpec.listModeAuxiliaryBottomPadding
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
            if let activeListMap {
                listMapNavigationChrome(activeListMap)
                layersButton
                listMapFilterChips(activeListMap)
            } else {
                Button {
                    appShell.openMenu()
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
                        appShell.openOfflineMapsDeepLink()
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
    }

    @ViewBuilder
    private func listMapNavigationChrome(_ list: ActiveListMap) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Task { @MainActor in
                    let returnListID = list.listID
                    activeListMap = nil
                    listCameraRequest = nil
                    clearTrackReplay()
                    await refreshCurrentViewport()
                    await refreshTrackGeometry()
                    appShell.openListDetailDeepLink(listID: returnListID, visitFilter: list.visitFilter)
                }
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("map.list-mode.back")

            Text(verbatim: list.name)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .accessibilityIdentifier("map.list-mode.title")
        }
    }

    private func listMapModeChrome(_: ActiveListMap) -> some View {
        HStack(spacing: 0) {
            listMapModeButton(
                title: ListMapModeCopy.freshLayerTitle(theme: selectedTheme),
                showVisited: false
            )
            listMapModeButton(
                title: ListMapModeCopy.tracksLayerTitle,
                showVisited: true
            )
        }
        .frame(width: 280, height: 40)
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.clear)
                .accessibilityIdentifier("map.list-mode.control")
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(uiColor: .separator), lineWidth: 1)
        }
    }

    private func listMapModeButton(title: String, showVisited: Bool) -> some View {
        let isSelected = activeListMap?.showVisited == showVisited
        return Button {
            listMapShowVisitedBinding.wrappedValue = showVisited
        } label: {
            Text(verbatim: title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundStyle(isSelected ? Color(uiColor: .systemBackground) : Color(uiColor: .label))
                .background(isSelected ? Color(uiColor: .label) : Color.clear)
        }
        .buttonStyle(.plain)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityIdentifier(showVisited ? "map.list-mode.tracks" : "map.list-mode.fresh")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    private func listMapFilterChips(_ list: ActiveListMap) -> some View {
        HStack(spacing: 6) {
            ForEach(ListMapFilterChips.chips(for: list.visitFilter)) { chip in
                Button {
                    presentTrackFilterPicker(for: list)
                } label: {
                    HStack(spacing: 5) {
                        if let systemImage = chip.systemImage {
                            Image(systemName: systemImage)
                        }
                        Text(verbatim: chip.title)
                    }
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .foregroundStyle(chip.isSelected ? Color(uiColor: .systemBackground) : Color(uiColor: .label))
                    .background(chip.isSelected ? Color(uiColor: .label) : Color.clear, in: Capsule())
                    .background(.regularMaterial, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(chip.title)
                .accessibilityIdentifier(chip.accessibilityIdentifier)
                .accessibilityValue(chip.isSelected ? "Selected" : "Not selected")
            }
        }
    }

    private func mapTrackReplayControls(_ timeline: TrackTimelineModel) -> some View {
        let selectedIndex = clampedSelectedTrackReplayIndex(selectedTrackReplayEventIndex, in: timeline)
        let selectedVisit = timeline.selectedVisit(after: selectedIndex)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    toggleMapTrackAutoplay(timeline)
                } label: {
                    Image(systemName: isTrackReplayAutoplaying ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(isTrackReplayAutoplaying ? "Pause track replay" : "Play track replay")
                .accessibilityIdentifier("map.track-replay.play")

                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: timeline.selectedTimeLabel(after: selectedIndex))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .accessibilityIdentifier("map.track-replay.selected-time")
                    Text(verbatim: selectedVisit?.name ?? "")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(verbatim: "Visit \((selectedIndex ?? 0) + 1) of \(timeline.visits.count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityIdentifier("map.track-replay.counter")
            }

            VStack(alignment: .leading, spacing: 2) {
                TrackReplayTimelineControl(
                    timeline: timeline,
                    selectedIndex: selectedIndex,
                    zoomLevel: trackReplayTimelineZoomLevel,
                    onZoomLevelChanged: { zoomLevel in
                        trackReplayTimelineZoomLevel = zoomLevel
                    },
                    onScrub: { nextIndex in
                        scrubSelectedTrackReplayEventIndex(nextIndex, timeline: timeline)
                    }
                )

                HStack {
                    Text(verbatim: timeline.startTimeLabel)
                        .accessibilityIdentifier("map.track-replay.start-time")
                    Spacer()
                    Text(verbatim: timeline.endTimeLabel)
                        .accessibilityIdentifier("map.track-replay.end-time")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            if let visit = selectedVisit {
                HStack(spacing: 6) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .scaleEffect(trackReplayArrivalPulseVisitID == visit.id ? 1.22 : 1.0)
                        .animation(.spring(response: 0.22, dampingFraction: 0.45), value: trackReplayArrivalPulseVisitID)
                        .accessibilityHidden(true)
                    Text(verbatim: visit.name)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .accessibilityLabel(timeline.accessibilityValue(for: selectedTrackReplayEventIndex))
                .accessibilityIdentifier("map.track-replay.arrival")
            }
        }
        .frame(maxWidth: 360)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(uiColor: .separator), lineWidth: 1)
        }
    }

    private func toggleMapTrackAutoplay(_ timeline: TrackTimelineModel) {
        if isTrackReplayAutoplaying {
            stopMapTrackAutoplay()
        } else {
            stopMapTrackScrub()
            startMapTrackAutoplay(timeline)
        }
    }

    private func startMapTrackAutoplay(_ timeline: TrackTimelineModel) {
        guard !timeline.visits.isEmpty else { return }
        trackReplayAutoplayTask?.cancel()
        isTrackReplayAutoplaying = true
        let startIndex = selectedTrackReplayEventIndex == timeline.visits.indices.last ? nil : selectedTrackReplayEventIndex
        trackReplayAutoplayTask = Task { @MainActor in
            var currentIndex = startIndex
            while isTrackReplayAutoplaying, !Task.isCancelled {
                switch timeline.autoplayStep(after: currentIndex) {
                case .event(let nextIndex):
                    setSelectedTrackReplayEventIndex(nextIndex, timeline: timeline)
                    currentIndex = nextIndex
                    try? await Task.sleep(for: .seconds(TrackTimelineModel.autoplayBeatDuration))
                case .finished:
                    stopMapTrackAutoplay()
                }
            }
        }
    }

    private func stopMapTrackAutoplay() {
        trackReplayAutoplayTask?.cancel()
        trackReplayAutoplayTask = nil
        isTrackReplayAutoplaying = false
    }

    private func stopMapTrackScrub() {
        trackReplayScrubTask?.cancel()
        trackReplayScrubTask = nil
    }

    private func stopMapTrackArcGlide() {
        trackReplayArcGlideTask?.cancel()
        trackReplayArcGlideTask = nil
    }

    private func stopTrackReplaySnapshotPrecompute() {
        trackReplaySnapshotPrecomputeGeneration += 1
        trackReplaySnapshotPrecomputeTask?.cancel()
        trackReplaySnapshotPrecomputeTask = nil
    }

    private func scrubSelectedTrackReplayEventIndex(_ nextIndex: Int, timeline: TrackTimelineModel) {
        stopMapTrackAutoplay()
        stopMapTrackScrub()
        let path = timeline.scrubEventPath(from: selectedTrackReplayEventIndex, to: nextIndex)
        guard path.count > 1 else {
            setSelectedTrackReplayEventIndex(path.first ?? nextIndex, timeline: timeline)
            return
        }
        trackReplayScrubTask = Task { @MainActor in
            for index in path {
                guard !Task.isCancelled else { return }
                setSelectedTrackReplayEventIndex(index, timeline: timeline)
                try? await Task.sleep(for: .milliseconds(32))
            }
            trackReplayScrubTask = nil
        }
    }

    private func setSelectedTrackReplayEventIndex(_ nextIndex: Int, timeline: TrackTimelineModel) {
        let previousIndex = selectedTrackReplayEventIndex
        let clampedIndex = clampedSelectedTrackReplayIndex(nextIndex, in: timeline)
        selectedTrackReplayEventIndex = clampedIndex
        stopMapTrackArcGlide()
        guard let clampedIndex else {
            trackSourceSnapshot = trackReplaySnapshotCache.snapshot(throughEventIndex: clampedIndex)
            return
        }
        let shouldAnimateArrival = clampedIndex > 0
            && timeline.shouldPulseArrival(previousIndex: previousIndex, nextIndex: clampedIndex)
            && timeline.visits.indices.contains(clampedIndex)
        guard shouldAnimateArrival else {
            trackSourceSnapshot = trackReplaySnapshotCache.snapshot(throughEventIndex: clampedIndex)
            return
        }
        startTrackReplayArcGlide(to: clampedIndex, timeline: timeline)
    }

    private func startTrackReplayArcGlide(to eventIndex: Int, timeline: TrackTimelineModel) {
        let visitID = timeline.visits[eventIndex].id
        trackReplayArrivalPulseVisitID = nil
        trackSourceSnapshot = trackReplaySnapshotCache.snapshot(throughEventIndex: eventIndex, activeArcProgress: 0)
        trackReplayArcGlideTask = Task { @MainActor in
            for frame in 1...TrackReplayArcGlideSpec.frameCount {
                try? await Task.sleep(for: .milliseconds(TrackReplayArcGlideSpec.frameIntervalMilliseconds))
                guard !Task.isCancelled else { return }
                let progress = Double(frame) / Double(TrackReplayArcGlideSpec.frameCount)
                trackSourceSnapshot = trackReplaySnapshotCache.snapshot(
                    throughEventIndex: eventIndex,
                    activeArcProgress: progress
                )
            }
            guard !Task.isCancelled else { return }
            trackReplayArrivalPulseVisitID = visitID
            trackReplayArcGlideTask = nil
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(TrackReplayArcGlideSpec.arrivalPulseMilliseconds))
                if trackReplayArrivalPulseVisitID == visitID {
                    trackReplayArrivalPulseVisitID = nil
                }
            }
        }
    }

    private func clampedSelectedTrackReplayIndex(_ index: Int?, in timeline: TrackTimelineModel) -> Int? {
        guard !timeline.visits.isEmpty else { return nil }
        return min(max(index ?? timeline.visits.count - 1, 0), timeline.visits.count - 1)
    }

    private func applyTrackReplayContext(_ context: TrackGeometryContext) {
        stopMapTrackAutoplay()
        stopMapTrackScrub()
        stopMapTrackArcGlide()
        stopTrackReplaySnapshotPrecompute()
        trackReplayContext = context
        trackReplaySnapshotCache = TrackReplaySnapshotCache(context: context)
        let timeline = TrackTimelineModel(visits: context.visits)
        selectedTrackReplayEventIndex = clampedSelectedTrackReplayIndex(selectedTrackReplayEventIndex, in: timeline)
        trackReplayTimelineZoomLevel = .coarse
        trackReplayArrivalPulseVisitID = nil
        trackSourceSnapshot = trackReplaySnapshotCache.snapshot(throughEventIndex: selectedTrackReplayEventIndex)
        startTrackReplaySnapshotPrecompute(context: context)
    }

    private func applyStaticTrackContext(_ context: TrackGeometryContext) {
        stopMapTrackAutoplay()
        stopMapTrackScrub()
        stopMapTrackArcGlide()
        stopTrackReplaySnapshotPrecompute()
        trackReplayContext = .empty
        trackReplaySnapshotCache = .empty
        selectedTrackReplayEventIndex = nil
        trackReplayTimelineZoomLevel = .coarse
        trackReplayArrivalPulseVisitID = nil
        trackSourceSnapshot = TrackSourceSnapshot.make(context: context)
    }

    private func clearTrackReplay() {
        stopMapTrackAutoplay()
        stopMapTrackScrub()
        stopMapTrackArcGlide()
        stopTrackReplaySnapshotPrecompute()
        trackReplayContext = .empty
        trackReplaySnapshotCache = .empty
        selectedTrackReplayEventIndex = nil
        trackReplayTimelineZoomLevel = .coarse
        trackReplayArrivalPulseVisitID = nil
        trackSourceSnapshot = .empty
    }

    private func startTrackReplaySnapshotPrecompute(context: TrackGeometryContext) {
        guard context.visits.count > 1 else { return }
        trackReplaySnapshotPrecomputeGeneration += 1
        let generation = trackReplaySnapshotPrecomputeGeneration
        trackReplaySnapshotPrecomputeTask = Task.detached(priority: .utility) {
            guard let warmedCache = TrackReplaySnapshotCache.precomputed(context: context) else { return }
            await MainActor.run {
                guard trackReplaySnapshotPrecomputeGeneration == generation,
                      trackReplayContext == context
                else { return }
                trackReplaySnapshotCache = warmedCache
                if trackReplayArcGlideTask == nil {
                    trackSourceSnapshot = warmedCache.snapshot(throughEventIndex: selectedTrackReplayEventIndex)
                }
                trackReplaySnapshotPrecomputeTask = nil
            }
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

    private var visibleTrackSourceSnapshot: TrackSourceSnapshot {
        guard activeListMap?.showVisited == true else { return .empty }
        return trackSourceSnapshot
    }

    private var visibleMapFeatures: [(MapPlace, PinState)] {
        guard activeListMap?.usesTrackReplay == true else { return features }
        return TrackReplayPinPresentation.features(
            features,
            context: trackReplayContext,
            throughEventIndex: selectedTrackReplayEventIndex
        )
    }

    private var trackReplayTimeline: TrackTimelineModel {
        TrackTimelineModel(visits: trackReplayContext.visits)
    }

    private var pinPresentation: PinPresentation {
        if activeListMap?.usesTrackReplay == true,
           !trackReplayContext.visits.isEmpty {
            return .trackReplay
        }
        return ListMapPinPresentation.presentation(showVisited: activeListMap?.showVisited == true)
    }

    private var trackReplayPulsePlaceIDs: Set<String> {
        TrackReplayPinPresentation.pulsePlaceIDs(
            context: trackReplayContext,
            throughEventIndex: selectedTrackReplayEventIndex,
            isArrivalPulsing: activeListMap?.usesTrackReplay == true && trackReplayArrivalPulseVisitID != nil
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
        async let nextInstalledCoverageBBoxes = model.installedOfflineCoverageBBoxes()
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
            features: nearbyPromptFeatures,
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
        ensureModel()
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
        await refreshTrackGeometry()
        await refreshFixtureVisitCount()
        let elapsedMS = Int(Date().timeIntervalSince(startedAt) * 1000)
        let finalState = loadState.rawValue
        let featureCount = features.count
        MakingTracksLog.startup.info("map start finished state=\(finalState, privacy: .public) features=\(featureCount, privacy: .public) durationMS=\(elapsedMS, privacy: .public)")
    }

    private func ensureModel() {
        if model == nil {
            model = try? MapScreenModel(
                database: database,
                fixturePlaces: isFixtureMap ? Self.uiTestingFixturePlaces(dense: debugUseDenseFixturePins) : [],
                forceTileNetworkOffline: debugForceTileNetworkOffline
            )
            let hasModel = model != nil
            MakingTracksLog.startup.info("map model initialized available=\(hasModel, privacy: .public)")
        }
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

    @MainActor
    @discardableResult
    private func setNearbyPromptSuppressed(placeID: String, suppressed: Bool) -> Bool {
        if suppressed {
            return suppressedNearbyPromptPlaceIDs.insert(placeID).inserted
        }
        return suppressedNearbyPromptPlaceIDs.remove(placeID) != nil
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
            authorizationStatus: locationPermission.authorizationStatus
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
        let viewportFeatures = await model.viewportFeatures(
            in: bbox,
            zoom: zoom,
            allowManifestRefresh: allowManifestRefresh
        )
        let next = viewportFeatures.display
        let nextSourceFeatureCount = viewportFeatures.sourceCount
        let nextNearbyPromptFeatures = viewportFeatures.nearbyPrompt
        let nextRegionPMTilesURL = await model.pmtilesURL
        let nextAttribution = await model.attribution
        let nextLoadState = await model.loadState
        var nextNearbyPromptNames: [String: String] = [:]
        for (place, _) in nextNearbyPromptFeatures {
            if let card = await model.cardModel(for: place.id) {
                nextNearbyPromptNames[place.id] = card.name
            }
        }
        await MainActor.run {
            guard requestID == viewportRefreshTracker.latestRequestID else { return }
            viewportRefreshTracker.complete(requestID: requestID)
            if capturedStateEpoch == stateEpoch {
                features = next
                sourceFeatureCount = nextSourceFeatureCount
                nearbyPromptFeatures = nextNearbyPromptFeatures
                nearbyPromptNames = nextNearbyPromptNames
                listMapPinNames = [:]
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
            if let flowMetrics = viewportFeatures.flowMetrics {
                MakingTracksLog.viewportFlowEvent(
                    region: flowMetrics.region,
                    zoom: flowMetrics.zoom,
                    tileZ: flowMetrics.tileZ,
                    covered: flowMetrics.covered,
                    requests: flowMetrics.requests,
                    blocked: flowMetrics.blocked,
                    source: "camera-idle"
                )
            }
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
                await refreshTrackGeometry()
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
                await refreshTrackGeometry()
                await refreshFixtureVisitCount()
                continue
            }
            let states = await model.states(for: ids)
            await MainActor.run {
                stateEpoch += 1
                features = features.map { place, state in
                    (place, states[place.id] ?? state)
                }
                nearbyPromptFeatures = nearbyPromptFeatures.map { place, state in
                    (place, states[place.id] ?? state)
                }
            }
            await refreshTrackGeometry()
            await refreshFixtureVisitCount()
        }
    }

    private func observeViewportChanges(from model: MapScreenModel) async {
        for await _ in model.viewportChanges {
            guard !Task.isCancelled else { return }
            guard await MainActor.run(body: { activeListMap == nil }) else { continue }
            let viewportFeatures = await model.currentViewportFeatures()
            let next = viewportFeatures.display
            let nextSourceFeatureCount = viewportFeatures.sourceCount
            let nextNearbyPromptFeatures = viewportFeatures.nearbyPrompt
            let nextRegionPMTilesURL = await model.pmtilesURL
            let nextAttribution = await model.attribution
            let nextLoadState = await model.loadState
            var nextNearbyPromptNames: [String: String] = [:]
            for (place, _) in nextNearbyPromptFeatures {
                if let card = await model.cardModel(for: place.id) {
                    nextNearbyPromptNames[place.id] = card.name
                }
            }
            await MainActor.run {
                guard activeListMap == nil else { return }
                features = next
                sourceFeatureCount = nextSourceFeatureCount
                nearbyPromptFeatures = nextNearbyPromptFeatures
                nearbyPromptNames = nextNearbyPromptNames
                listMapPinNames = [:]
                regionPMTilesURL = nextRegionPMTilesURL
                attribution = nextAttribution
                loadState = nextLoadState
            }
        }
    }

    @MainActor
    private func refreshTrackGeometry() async {
        guard let model else { return }
        guard let list = activeListMap, list.showVisited else {
            clearTrackReplay()
            return
        }
        let context = await model.trackGeometryContext(listID: list.listID, filter: list.visitFilter)
        guard let currentList = activeListMap,
              currentList.listID == list.listID,
              currentList.visitFilter == list.visitFilter,
              currentList.showVisited == list.showVisited
        else { return }
        if list.usesTrackReplay {
            applyTrackReplayContext(context)
        } else {
            applyStaticTrackContext(context)
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
    private func presentTrackFilterPicker(for list: ActiveListMap) {
        trackFilterPickerDraft = TrackFilterPickerDraft(filter: list.visitFilter)
        trackFilterPickerScopedVisitCount = trackReplayContext.visits.count
        isTrackFilterPickerPresented = true
        Task { @MainActor in
            trackFilterPickerLists = await model?.lists() ?? []
            await refreshTrackFilterPickerScopedVisitCount()
        }
    }

    @MainActor
    private func refreshTrackFilterPickerScopedVisitCount() async {
        guard isTrackFilterPickerPresented, let model, let list = activeListMap else { return }
        let draft = trackFilterPickerDraft
        let context = await model.trackGeometryContext(listID: list.listID, filter: draft.filter)
        guard isTrackFilterPickerPresented,
              activeListMap?.listID == list.listID,
              trackFilterPickerDraft == draft
        else { return }
        trackFilterPickerScopedVisitCount = context.visits.count
    }

    @MainActor
    private func applyTrackFilterPickerDraft() {
        guard var list = activeListMap else { return }
        list.showVisited = true
        list.visitFilter = trackFilterPickerDraft.filter
        activeListMap = list
        isTrackFilterPickerPresented = false
        stopMapTrackAutoplay()
        Task { @MainActor in
            await refreshActiveListMap(updateCamera: true)
        }
    }

    @MainActor
    private func showListOnMap(_ list: PlaceList, filter: TracksVisitFilter = .all) async {
        guard let id = list.id else { return }
        cardPresentation.dismiss()
        activeListMap = ActiveListMap(listID: id, name: list.name, kind: list.kind, visitFilter: filter, showVisited: true)
        await refreshActiveListMap(updateCamera: true)
    }

    @MainActor
    private func refreshActiveListMap(updateCamera: Bool = false) async {
        guard let model, let list = activeListMap else { return }
        let rawFeatures = await model.listMapFeatures(
            listID: list.listID,
            showVisited: list.showVisited
        )
        let nextTrackContext = if list.showVisited {
            await model.trackGeometryContext(listID: list.listID, filter: list.visitFilter)
        } else {
            TrackGeometryContext.empty
        }
        let next = ListMapFilteredFeatures.visibleFeatures(
            rawFeatures,
            showVisited: list.showVisited,
            visitFilter: list.visitFilter,
            context: nextTrackContext
        )
        let nextNames = await model.listMapPinAccessibilityNames(
            listID: list.listID,
            visiblePlaceIDs: Set(next.map(\.0.id))
        )
        guard let currentList = activeListMap,
              currentList.listID == list.listID,
              currentList.visitFilter == list.visitFilter,
              currentList.showVisited == list.showVisited
        else { return }
        features = next
        nearbyPromptFeatures = []
        nearbyPromptNames = [:]
        sourceFeatureCount = next.count
        listMapPinNames = nextNames
        if list.usesTrackReplay {
            applyTrackReplayContext(nextTrackContext)
        } else if list.showVisited {
            applyStaticTrackContext(nextTrackContext)
        } else {
            clearTrackReplay()
        }
        stateEpoch += 1
        let viewportPlaces = ListMapViewport.places(
            for: next,
            showVisited: list.showVisited,
            visitFilter: list.visitFilter,
            context: nextTrackContext
        )
        if updateCamera, let viewport = ListMapViewport.viewport(for: viewportPlaces) {
            nextListCameraRequestID += 1
            listCameraRequest = ViewportCameraRequest(id: nextListCameraRequestID, viewport: viewport, fitBounds: true)
        }
    }

    @MainActor
    private func reconcileActiveListMap(renamed list: PlaceList) {
        guard let id = list.id,
              var active = activeListMap,
              active.listID == id
        else { return }
        active.name = list.name
        active.kind = list.kind
        activeListMap = active
    }

    @MainActor
    private func clearActiveListMap(deletedListID listID: Int64) async {
        if activeListMap?.listID == listID {
            activeListMap = nil
            listCameraRequest = nil
            clearTrackReplay()
        }
        await refreshCurrentViewport()
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

    struct ActiveListMap: Equatable {
        let listID: Int64
        var name: String
        var kind: String
        var visitFilter: TracksVisitFilter
        var showVisited: Bool

        var usesTrackReplay: Bool {
            showVisited && kind == PlaceList.trackKind
        }
    }

    enum TrackReplayControlVisibility {
        static func showOnMap(list: ActiveListMap, timeline: TrackTimelineModel) -> Bool {
            list.usesTrackReplay && timeline.hasInteractiveReplayControls
        }
    }

    static let fixturePlaces = [
        try! PlaceRef(
            placeID: "mt1_00000000000000000000000000",
            name: "Ghost Sign",
            lat: 3.14,
            lon: 101.69,
            category: "attraction",
            tier: 1,
            schemaVersion: 1,
            fetchedAt: Date(timeIntervalSince1970: 0),
            rawJSON: """
            {"blurb":"A hand-painted sign still visible above the old shopfront.","category":"attraction","lat":3.14,"lon":101.69,"name":"Ghost Sign","place_id":"mt1_00000000000000000000000000","score":0.5,"source_refs":["osm:node/1","wp:12345"],"tier":1,"wikipedia_title":"Ghost Sign"}
            """
        ),
        try! PlaceRef(
            placeID: "mt1_00000000000000000000000001",
            name: "Art Deco Cinema",
            lat: 3.16,
            lon: 101.702,
            category: "historic_building",
            tier: 2,
            schemaVersion: 1,
            fetchedAt: Date(timeIntervalSince1970: 0),
            rawJSON: """
            {"category":"historic_building","lat":3.16,"lon":101.702,"name":"Art Deco Cinema","place_id":"mt1_00000000000000000000000001","score":0.5,"source_refs":["osm:node/2"],"tier":2}
            """
        ),
    ]

    static func uiTestingFixturePlaces(dense: Bool) -> [PlaceRef] {
        dense ? denseFixturePlaces : fixturePlaces
    }

    private static let denseFixturePlaces: [PlaceRef] = {
        let categories = ["attraction", "historic_building", "museum", "artwork", "memorial", "religious"]
        return (0..<24).map { index in
            let tier: Int
            if index < 4 {
                tier = 1
            } else if index < 10 {
                tier = 2
            } else if index < 16 {
                tier = 3
            } else {
                tier = 4
            }
            let lat = 3.132 + (Double(index / 6) * 0.004)
            let lon = 101.682 + (Double(index % 6) * 0.004)
            let category = categories[index % categories.count]
            let placeID = "mt1_D000000000000000000000000\(crockfordDigit(for: index + 1))"
            let name = "Dense Pin \(index + 1)"
            return try! PlaceRef(
                placeID: placeID,
                name: name,
                lat: lat,
                lon: lon,
                category: category,
                tier: tier,
                schemaVersion: 1,
                fetchedAt: Date(timeIntervalSince1970: 0),
                rawJSON: """
                {"blurb":"Fixture pin for tier/zoom density screenshots.","category":"\(category)","lat":\(lat),"lon":\(lon),"name":"\(name)","place_id":"\(placeID)","score":0.5,"source_refs":["osm:node/\(10_000 + index)"],"tier":\(tier)}
                """
            )
        }
    }()

    static let spreadFixturePlaces: [PlaceRef] = {
        let fixtures: [(id: String, name: String, lat: Double, lon: Double, category: String)] = [
            ("mt1_S0000000000000000000000001", "Spread West", 3.12, 101.60, "museum"),
            ("mt1_S0000000000000000000000002", "Spread East", 3.20, 101.78, "historic_building"),
            ("mt1_S0000000000000000000000003", "Spread South", 3.06, 101.70, "artwork"),
            ("mt1_S0000000000000000000000004", "Spread North", 3.24, 101.68, "memorial"),
            ("mt1_S0000000000000000000000005", "Spread Middle", 3.16, 101.69, "attraction"),
        ]
        return fixtures.map { fixture in
            try! PlaceRef(
                placeID: fixture.id,
                name: fixture.name,
                lat: fixture.lat,
                lon: fixture.lon,
                category: fixture.category,
                tier: 2,
                schemaVersion: 1,
                fetchedAt: Date(timeIntervalSince1970: 0),
                rawJSON: """
                {"blurb":"Fixture pin for list-map camera fitting.","category":"\(fixture.category)","lat":\(fixture.lat),"lon":\(fixture.lon),"name":"\(fixture.name)","place_id":"\(fixture.id)","score":0.5,"source_refs":["osm:node/\(fixture.id.suffix(1))"],"tier":2}
                """
            )
        }
    }()

    private static func crockfordDigit(for index: Int) -> Character {
        Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")[index]
    }

    private static func initialFixtureFeatures(dense: Bool) -> [(MapPlace, PinState)] {
        uiTestingFixturePlaces(dense: dense).map { fixturePlace in
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
    let title: String
    let publishVersion: String
    let bytes: Int
    let tileCount: Int

    init(region: String, title: String? = nil, publishVersion: String, bytes: Int, tileCount: Int) {
        self.region = region
        self.title = title ?? region
        self.publishVersion = publishVersion
        self.bytes = bytes
        self.tileCount = tileCount
    }

    var id: String { region }
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

    static func ready(from summary: OfflinePackStorageSummary, catalog: OfflineRegionCatalog? = nil) -> StorageMenuStatus {
        ready(
            totalBytes: summary.totalBytes,
            regions: summary.packs.map {
                StorageMenuRegion(
                    region: $0.region,
                    title: catalog?.zone(id: $0.region)?.displayName,
                    publishVersion: $0.publishVersion,
                    bytes: $0.referencedBytes,
                    tileCount: $0.tileCount
                )
            },
            failedRegions: summary.failedRegions
        )
    }

    var installedStorageBytes: [String: Int] {
        regions.reduce(into: [:]) { summary, region in
            summary[region.region] = region.bytes
        }
    }

    var diagnosticInstalledPacks: [DiagnosticInstalledPack] {
        let installed = regions.map {
            DiagnosticInstalledPack(id: $0.region, publishVersion: $0.publishVersion, state: "installed")
        }
        let failed = failedRegions.map {
            DiagnosticInstalledPack(id: $0, publishVersion: "unknown", state: "failed")
        }
        return installed + failed
    }

    var totalBytesText: String {
        Self.formatBytes(totalBytes)
    }

    static func formatBytes(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(max(bytes, 0)), countStyle: .file)
    }
}

struct OfflineMapsLocalState: Equatable, Sendable {
    let installed: [String: String]
    let pausedRegions: Set<String>
    let quarantines: [OfflinePackQuarantine]
    let storageStatus: StorageMenuStatus

    static let unavailable = OfflineMapsLocalState(
        installed: [:],
        pausedRegions: [],
        quarantines: [],
        storageStatus: .unavailable
    )
}

struct OfflineMapsAvailability: Equatable, Sendable {
    let publishVersions: [String: String]
    let storageBytes: [String: Int]

    static let empty = OfflineMapsAvailability(publishVersions: [:], storageBytes: [:])
}

enum OfflineMapsRefreshCoordinator {
    @MainActor
    static func refresh(
        loadLocalState: @MainActor () async -> OfflineMapsLocalState,
        loadAvailability: @escaping @MainActor (_ installedRegions: Set<String>) async -> OfflineMapsAvailability,
        applyLocalState: @MainActor (OfflineMapsLocalState) -> Void,
        applyAvailability: @escaping @MainActor (_ availability: OfflineMapsAvailability, _ installedRegions: Set<String>) -> Void
    ) async -> Task<Void, Never> {
        let localState = await loadLocalState()
        applyLocalState(localState)
        let installedRegions = Set(localState.installed.keys)
        return Task { @MainActor in
            let availability = await loadAvailability(installedRegions)
            guard !Task.isCancelled else { return }
            applyAvailability(availability, installedRegions)
        }
    }
}

enum OfflinePublishAvailability {
    static func currentAvailability(
        for catalog: OfflineRegionCatalog,
        installedRegions: Set<String>,
        fetcher: TileFetching
    ) async throws -> OfflineMapsAvailability {
        let regionIDs = catalog.zones.map(\.id)
        let allVersions = await currentPublishVersionsOrEmpty(
            regions: regionIDs,
            fetcher: fetcher
        )
        return OfflineMapsAvailability(
            publishVersions: allVersions,
            storageBytes: currentStorageBytes(for: catalog, currentPublishVersions: allVersions)
        )
    }

    static func currentPublishVersions(
        for catalog: OfflineRegionCatalog,
        installedRegions: Set<String>,
        fetcher: TileFetching
    ) async throws -> [String: String] {
        let regionIDs = catalog.zones
            .map(\.id)
            .filter { installedRegions.contains($0) }
        return try await ManifestClient.currentPublishVersions(regions: regionIDs, fetcher: fetcher)
    }

    private static func currentStorageBytes(
        for catalog: OfflineRegionCatalog,
        currentPublishVersions: [String: String]
    ) -> [String: Int] {
        catalog.zones.reduce(into: [String: Int]()) { bytes, zone in
            guard let currentPublishVersion = currentPublishVersions[zone.id],
                  zone.searchCompactPublishVersion == currentPublishVersion
            else { return }
            bytes[zone.id] = zone.bytesWithoutThumbnails
        }
    }

    private static func currentPublishVersionsOrEmpty(
        regions: [String],
        fetcher: TileFetching
    ) async -> [String: String] {
        // RegionIndex is capped at 512 entries; that cap bounds the fan-out behind this shared catalog probe.
        (try? await ManifestClient.currentPublishVersions(regions: regions, fetcher: fetcher)) ?? [:]
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
    let onShowListOnMap: @MainActor (PlaceList, TracksVisitFilter) -> Void
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
                onShowOnMap: showListOnMapAndDismiss,
                onListRenamed: onListRenamed,
                onListDeleted: onListDeleted
            ))
        case let .listDetail(listID):
            destinationWithDone(ListDetailDeepLinkView(
                model: model,
                listID: listID,
                visitFilter: shell.listDetailVisitFilter,
                onShowOnMap: showListOnMapAndDismiss,
                onListRenamed: onListRenamed
            ))
        case .tracks:
            destinationWithDone(TrackListDetailDeepLinkView(
                model: model,
                focusPlaceID: shell.tracksFocusPlaceID,
                onShowOnMap: showListOnMapAndDismiss,
                onListRenamed: onListRenamed
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
                path: $path,
                selectedThemeID: $selectedThemeID,
                pinSizeMultiplier: $pinSizeMultiplier,
                locationStatus: locationStatus,
                storageStatus: storageStatus,
                openLocationSettings: openLocationSettings,
                replayOnboarding: replayOnboardingAndDismiss
            ))
        case .diagnostics:
            destinationWithDone(DiagnosticsView(storageStatus: storageStatus))
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
        if destination != .tracks {
            shell.tracksFocusPlaceID = nil
        }
        switch destination {
        case let .listDetail(listID):
            path = [.lists, .listDetail(listID)]
        default:
            path = [destination]
        }
        shell.deepLinkPath = nil
    }

    private func replayOnboardingAndDismiss() {
        dismiss()
        replayOnboarding()
    }

    private func showListOnMapAndDismiss(_ list: PlaceList, filter: TracksVisitFilter = .all) {
        shell.isMenuPresented = false
        dismiss()
        onShowListOnMap(list, filter)
    }
}

private struct ListDetailDeepLinkView: View {
    let model: MapScreenModel?
    let listID: Int64
    let visitFilter: TracksVisitFilter
    let onShowOnMap: @MainActor (PlaceList, TracksVisitFilter) -> Void
    let onListRenamed: @MainActor (PlaceList) -> Void

    @State private var list: PlaceList?
    @State private var didLoad = false

    var body: some View {
        Group {
            if let list {
                ListDetailView(
                    model: model,
                    list: list,
                    visitFilter: visitFilter,
                    onChanged: {},
                    onShowOnMap: onShowOnMap,
                    onListRenamed: onListRenamed
                )
            } else if didLoad {
                ContentUnavailableView("List not found", systemImage: "list.bullet")
            } else {
                ProgressView()
                    .accessibilityIdentifier("lists.detail.loading")
            }
        }
        .task { await load() }
    }

    @MainActor
    private func load() async {
        guard let model else {
            didLoad = true
            return
        }
        list = await model.lists().first { $0.id == listID }
        didLoad = true
    }
}

private struct TrackListDetailDeepLinkView: View {
    let model: MapScreenModel?
    let focusPlaceID: String?
    let onShowOnMap: @MainActor (PlaceList, TracksVisitFilter) -> Void
    let onListRenamed: @MainActor (PlaceList) -> Void

    @State private var list: PlaceList?
    @State private var didLoad = false

    var body: some View {
        Group {
            if let list {
                ListDetailView(
                    model: model,
                    list: list,
                    focusPlaceID: focusPlaceID,
                    onChanged: {},
                    onShowOnMap: onShowOnMap,
                    onListRenamed: onListRenamed
                )
            } else if didLoad {
                ContentUnavailableView("List not found", systemImage: "list.bullet")
            } else {
                ProgressView()
                    .accessibilityIdentifier("lists.detail.loading")
            }
        }
        .task { await load() }
    }

    @MainActor
    private func load() async {
        guard let model else {
            didLoad = true
            return
        }
        list = await model.lists().first { $0.isSystem && $0.kind == PlaceList.trackKind }
        didLoad = true
    }
}

private struct AppMenuRootView: View {
    @Binding var path: [MenuDestination]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                path.append(.tracks)
            } label: {
                menuRow(title: "Tracks", subtitle: "Places you've seen", systemImage: "clock.arrow.circlepath")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("menu.row.tracks")

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
                if !dynamicTypeSize.isAccessibilitySize {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .foregroundStyle(.primary)
        .accessibilityElement(children: .combine)
        .accessibilityHint(dynamicTypeSize.isAccessibilitySize ? subtitle : "")
    }
}

private struct ListsView: View {
    let model: MapScreenModel?
    let onShowOnMap: @MainActor (PlaceList, TracksVisitFilter) -> Void
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
        actionError = nil
        do {
            _ = try await model.createList(named: draftName)
            draftName = ""
            actionError = nil
            await reload()
        } catch {
            actionError = ListsCopy.listNameCreateFailureMessage(for: error, draftName: draftName)
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
    let visitFilter: TracksVisitFilter
    let focusPlaceID: String?
    let onChanged: @MainActor () -> Void
    let onShowOnMap: @MainActor (PlaceList, TracksVisitFilter) -> Void
    let onListRenamed: @MainActor (PlaceList) -> Void

    @State private var items: [ListPlace] = []
    @State private var trackVisits: [TrackVisit] = []
    @State private var progress = ListProgress(visited: 0, total: 0)
    @State private var currentList: PlaceList
    @State private var renameDraft: String
    @State private var actionError: String?
    @State private var trackEditMode: EditMode = .active
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        model: MapScreenModel?,
        list: PlaceList,
        visitFilter: TracksVisitFilter = .all,
        focusPlaceID: String? = nil,
        onChanged: @escaping @MainActor () -> Void,
        onShowOnMap: @escaping @MainActor (PlaceList, TracksVisitFilter) -> Void,
        onListRenamed: @escaping @MainActor (PlaceList) -> Void
    ) {
        self.model = model
        self.list = list
        self.visitFilter = visitFilter
        self.focusPlaceID = focusPlaceID
        self.onChanged = onChanged
        self.onShowOnMap = onShowOnMap
        self.onListRenamed = onListRenamed
        _currentList = State(initialValue: list)
        _renameDraft = State(initialValue: list.name)
    }

    private var isTrackListDetail: Bool {
        ListDetailVisitActions.canEditTrackVisits(from: currentList)
    }

    private var visibleTrackVisits: [TrackVisit] {
        guard let focusPlaceID else { return trackVisits }
        return trackVisits.filter { $0.placeID == focusPlaceID }
    }

    private var focusedTrackVisitCount: Int {
        guard focusPlaceID != nil else { return 0 }
        return visibleTrackVisits.count
    }

    private var canReorderTrackVisits: Bool {
        focusPlaceID == nil && !visitFilter.isActive
    }

    private var calendar: Calendar {
        Calendar(identifier: .gregorian)
    }

    var body: some View {
        if isTrackListDetail {
            trackListBody
        } else {
            collectionListBody
        }
    }

    private var trackListBody: some View {
        List {
            Section {
                trackSummaryCard
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }

            Section {
                if visibleTrackVisits.isEmpty {
                    ContentUnavailableView("No visits yet", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(TrackVisitReordering.rows(for: visibleTrackVisits, calendar: calendar)) { row in
                        trackVisitRow(row.visit, dayHeader: row.dayHeader)
                            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    .onMove { source, destination in
                        guard canReorderTrackVisits else { return }
                        Task {
                            await moveTrackVisits(
                                visibleTrackVisits,
                                fromOffsets: source,
                                toOffset: destination
                            )
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(TrackVisitEditorVisualSpec.paperBackground)
        .environment(\.editMode, canReorderTrackVisits ? $trackEditMode : .constant(.inactive))
        .navigationTitle(currentList.name)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("lists.detail.surface.track")
        .task { await reload() }
        .refreshable { await reload() }
    }

    private var collectionListBody: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: ListsCopy.progress(visited: progress.visited, total: progress.total))
                        .font(.headline)
                        .accessibilityIdentifier("lists.detail.progress")
                    Button {
                        onShowOnMap(currentList, visitFilter)
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
                if isTrackListDetail {
                    if visibleTrackVisits.isEmpty {
                        ContentUnavailableView("No visits yet", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    } else {
                        ForEach(TrackVisitReordering.rows(for: visibleTrackVisits, calendar: calendar)) { row in
                            trackVisitRow(row.visit, dayHeader: row.dayHeader)
                        }
                        .onMove { source, destination in
                            guard canReorderTrackVisits else { return }
                            Task {
                                await moveTrackVisits(
                                    visibleTrackVisits,
                                    fromOffsets: source,
                                    toOffset: destination
                                )
                            }
                        }
                    }
                } else if items.isEmpty {
                    ContentUnavailableView("No places yet", systemImage: "mappin.slash")
                } else {
                    ForEach(items) { item in
                        listItemRow(item)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if let id = currentList.id,
                                   ListDetailItemActions.canRemoveStoredMembership(from: currentList) {
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
        .accessibilityIdentifier("lists.detail.surface.collection")
        .task { await reload() }
        .refreshable { await reload() }
    }

    private var trackSummaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if focusPlaceID == nil {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.down")
                        .accessibilityHidden(true)
                    Text(verbatim: TracksCopy.sortDirectionLabel)
                        .accessibilityIdentifier("lists.detail.track.sort-direction")
                }
                .font(.subheadline.weight(.semibold))

                Text(verbatim: TracksCopy.summary(
                    visible: visibleTrackVisits.count,
                    lovedOnly: false
                ))
                .font(.title2.weight(.bold))
                .accessibilityIdentifier("lists.detail.track.summary")

                Text("Your track is a sequence of visits you entered. Edit a row when the remembered day or order needs correcting.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button {
                        onShowOnMap(currentList, .all)
                    } label: {
                        Label("Map", systemImage: "map")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(TrackVisitEditorVisualSpec.accent)
                    .accessibilityIdentifier("lists.detail.show-map")

                    Button {
                        Task { await reload() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Refresh tracks")
                    .accessibilityIdentifier("lists.detail.track.refresh")
                }
            } else {
                Label("Multiple visits to this place", systemImage: "mappin.and.ellipse")
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("lists.detail.track.focus-message")

                Text("Choose the visit")
                    .font(.title2.weight(.bold))
                    .accessibilityIdentifier("lists.detail.track.summary")

                Text("Delete only the row you mean to remove.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TrackVisitEditorVisualSpec.cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(TrackVisitEditorVisualSpec.divider, lineWidth: 1)
        }
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

    private func trackVisitRow(_ visit: TrackVisit, dayHeader: Date?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let dayHeader {
                Text(verbatim: formattedDay(dayHeader))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: TrackVisitRowDensitySpec.horizontalSpacing) {
                    Text("pin")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(TrackVisitEditorVisualSpec.accent)
                        .frame(width: 30, height: 30)
                        .background(TrackVisitEditorVisualSpec.accentSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: TrackVisitRowDensitySpec.verticalSpacing) {
                        Text(verbatim: visit.name)
                            .font(.body)
                            .lineLimit(2)
                        Text(verbatim: "\(categoryLabel(visit.category)) · \(formattedVisitedAt(visit))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .layoutPriority(1)

                    Button {
                        Task { await setLoved(visit) }
                    } label: {
                        Text("heart")
                            .font(.caption.weight(.bold))
                            .frame(minWidth: 34, minHeight: 30)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(TrackVisitEditorVisualSpec.danger)
                    .accessibilityLabel(lovedButtonAccessibilityLabel(for: visit))
                    .accessibilityIdentifier("lists.detail.track.row.loved.\(visit.id)")
                }

                visitEditControls(visit)
            }
            .padding(11)
            .frame(maxWidth: .infinity, minHeight: TrackVisitRowDensitySpec.minimumHeight, alignment: .leading)
            .background(TrackVisitEditorVisualSpec.cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(TrackVisitEditorVisualSpec.divider, lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private func visitEditControls(_ visit: TrackVisit) -> some View {
        let datePicker = DatePicker(
            "Visit date",
            selection: Binding(
                get: { visit.visitedAt },
                set: { day in
                    Task { await updateVisitDate(visit, toDayContaining: day) }
                }
            ),
            displayedComponents: .date
        )
        .datePickerStyle(.compact)
        .labelsHidden()
        .accessibilityLabel("Visit date for \(visit.name), \(formattedVisitedAt(visit))")
        .accessibilityIdentifier("lists.detail.track.row.date.\(visit.id)")

        let dateBox = VStack(alignment: .leading, spacing: 2) {
            Text("Visit date")
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            datePicker
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TrackVisitEditorVisualSpec.cardBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(TrackVisitEditorVisualSpec.divider, lineWidth: 1)
        }

        let deleteButton = Button(role: .destructive) {
            Task { await deleteVisit(visit) }
        } label: {
            if dynamicTypeSize.isAccessibilitySize {
                Text("delete")
                    .font(.caption.weight(.bold))
            } else {
                Text("del")
                    .font(.caption.weight(.bold))
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(TrackVisitEditorVisualSpec.danger)
        .accessibilityLabel("Delete \(visit.name), \(formattedVisitedAt(visit))")
        .accessibilityIdentifier("lists.detail.track.row.delete.\(visit.id)")

        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                dateBox
                deleteButton
            }
        } else {
            HStack(alignment: .center, spacing: 8) {
                dateBox
                deleteButton
            }
        }
    }

    @MainActor
    private func reload() async {
        guard let model, let id = list.id else { return }
        if isTrackListDetail {
            let nextVisits = await model.trackVisits(listID: id, filter: visitFilter)
            guard currentList.id == id else { return }
            let nextVisibleVisits = if let focusPlaceID {
                nextVisits.filter { $0.placeID == focusPlaceID }
            } else {
                nextVisits
            }
            trackVisits = nextVisits
            progress = ListProgress(visited: nextVisibleVisits.count, total: nextVisibleVisits.count)
            items = []
        } else {
            let nextItems = await model.listItems(listID: id)
            let nextVisibleItems: [ListPlace]
            if currentList.kind == PlaceList.trackKind && visitFilter.isActive {
                let visits = await model.trackVisits(listID: id, filter: visitFilter)
                let visiblePlaceIDs = Set(visits.map(\.placeID))
                nextVisibleItems = nextItems.filter { visiblePlaceIDs.contains($0.placeID) }
            } else {
                nextVisibleItems = nextItems
            }
            items = nextVisibleItems
            if currentList.kind == PlaceList.trackKind {
                progress = ListProgress(visited: nextVisibleItems.count, total: nextVisibleItems.count)
            } else {
                progress = await model.listProgress(listID: id)
            }
            trackVisits = []
        }
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

    @MainActor
    private func setLoved(_ visit: TrackVisit) async {
        guard let model else { return }
        do {
            try await model.setVisitLoved(visitID: visit.id, loved: visit.verdict != .loved)
            actionError = nil
            await reload()
            onChanged()
        } catch {
            actionError = "Could not update that visit."
        }
    }

    @MainActor
    private func updateVisitDate(_ visit: TrackVisit, toDayContaining day: Date) async {
        guard let model else { return }
        do {
            try await model.updateVisitDate(visitID: visit.id, toDayContaining: day)
            actionError = nil
            await reload()
            onChanged()
        } catch {
            actionError = "Could not update that visit."
        }
    }

    @MainActor
    private func moveTrackVisits(
        _ visits: [TrackVisit],
        fromOffsets source: IndexSet,
        toOffset destination: Int
    ) async {
        guard let model,
              let plan = TrackVisitReordering.movePlan(
                in: visits,
                fromOffsets: source,
                toOffset: destination,
                calendar: calendar
              )
        else { return }
        do {
            switch plan {
            case .reorderDay(let day, let orderedIDs):
                try await model.reorderVisitsWithinDay(orderedIDs, dayContaining: day)
            case .moveVisit(let id, let targetDay, let targetDayOrderedIDs):
                try await model.moveVisit(
                    visitID: id,
                    toDayContaining: targetDay,
                    targetDayOrderedIDs: targetDayOrderedIDs
                )
            }
            actionError = nil
            await reload()
            onChanged()
        } catch {
            actionError = "Could not reorder that day."
        }
    }

    @MainActor
    private func deleteVisit(_ visit: TrackVisit) async {
        guard let model else { return }
        do {
            try await model.deleteVisit(visitID: visit.id)
            actionError = nil
            await reload()
            onChanged()
        } catch {
            actionError = "Could not delete that visit."
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

    private func formattedVisitedAt(_ visit: TrackVisit) -> String {
        visit.visitedAt.formatted(date: .abbreviated, time: .shortened)
    }

    private func formattedDay(_ day: Date) -> String {
        day.formatted(date: .abbreviated, time: .omitted)
    }

    private func lovedButtonAccessibilityLabel(for visit: TrackVisit) -> String {
        let action = visit.verdict == .loved ? "Remove loved from" : "Mark loved for"
        return "\(action) \(visit.name), \(formattedVisitedAt(visit))"
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

    @State private var catalog = OfflineRegionCatalog.empty
    @State private var installed: [String: String] = [:]
    @State private var availablePublishVersions: [String: String] = [:]
    @State private var availableStorageBytes: [String: Int] = [:]
    @State private var pausedRegions: Set<String> = []
    @State private var quarantines: [OfflinePackQuarantine] = []
    @State private var storageStatus: StorageMenuStatus
    @State private var statusMessage: String?
    @State private var pendingDeleteRegion: String?
    @State private var pendingDeleteRegionName: String?
    @State private var availabilityRefreshTask: Task<Void, Never>?
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
            installedStorageBytes: installedStorageBytes,
            availablePublishVersions: availablePublishVersions,
            availableStorageBytes: availableStorageBytes,
            activeProgress: activeProgress,
            pausedProgress: pausedProgress,
            pausedRegions: pausedRegions,
            quarantines: quarantines
        )
    }

    private var installedStorageBytes: [String: Int] {
        storageStatus.installedStorageBytes
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
        .onDisappear {
            availabilityRefreshTask?.cancel()
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
                Text(verbatim: "\(row.sizeLabel(includeThumbnails: false)) · \(row.statusLabel)")
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
            availabilityRefreshTask?.cancel()
            availablePublishVersions = [:]
            availableStorageBytes = [:]
            applyLocalState(.unavailable)
            MakingTracksLog.startup.info("offline rows state=unavailable")
            return
        }
        availabilityRefreshTask?.cancel()
        let refreshedCatalog = await model.offlineRegionCatalog(allowsCellularDownloads: allowsCellularDownloads)
        catalog = refreshedCatalog
        availabilityRefreshTask = await OfflineMapsRefreshCoordinator.refresh(
            loadLocalState: {
                await model.offlineMapsLocalState(for: refreshedCatalog)
            },
            loadAvailability: { installedRegions in
                await model.availableOfflineAvailability(
                    for: refreshedCatalog,
                    installedRegions: installedRegions,
                    allowsCellularDownloads: allowsCellularDownloads
                )
            },
            applyLocalState: { localState in
                availablePublishVersions = [:]
                availableStorageBytes = [:]
                applyLocalState(localState)
                let installedCount = localState.installed.count
                let quarantineCount = localState.quarantines.count
                MakingTracksLog.startup.info("offline rows refreshed installed=\(installedCount, privacy: .public) quarantines=\(quarantineCount, privacy: .public)")
            },
            applyAvailability: { availability, refreshedInstalledRegions in
                guard Set(installed.keys) == refreshedInstalledRegions else { return }
                availablePublishVersions = availability.publishVersions
                availableStorageBytes = availability.storageBytes
            }
        )
    }

    private func applyLocalState(_ localState: OfflineMapsLocalState) {
        installed = localState.installed
        pausedRegions = localState.pausedRegions
        quarantines = localState.quarantines
        storageStatus = localState.storageStatus
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
        if message == "This area isn't available yet" {
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
    @Binding var path: [MenuDestination]
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
                    PinSizePreview(pinSize: pinSize, theme: MapTheme.named(selectedThemeID))
                        .padding(.bottom, 2)
                        .accessibilityHidden(true)

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
                Button {
                    path.append(SettingsStorageNavigation.destination)
                } label: {
                    SettingsStorageSummary(storageStatus: storageStatus)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.storage.manage")
            }

            Section("Diagnostics") {
                Button {
                    path.append(.diagnostics)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.up.doc")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Diagnostic log")
                                .foregroundStyle(.primary)
                            Text("Review, prepare, share, or delete local logs.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.diagnostics.export")
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

private struct DiagnosticsView: View {
    let storageStatus: StorageMenuStatus

    @State private var selectedWindow = DiagnosticLogWindow.lastHour
    @State private var artifact: DiagnosticLogArtifact?
    @State private var scrubFailed = false
    @State private var isPreparing = false
    @State private var preparationTask: Task<Void, Never>?
    @State private var shareItem: DiagnosticsShareItem?
    @State private var showDeleteConfirmation = false

    var body: some View {
        List {
            Section {
                Picker("Time range", selection: $selectedWindow) {
                    ForEach(DiagnosticLogWindow.settingsOptions, id: \.self) { window in
                        Text(window.label).tag(window)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("settings.diagnostics.window")
            } header: {
                Text("Send a diagnostic log")
            } footer: {
                Text("Nothing is sent automatically. The app prepares a file on this phone; when you share, you pick who gets it.")
            }

            if let artifact {
                Section("Preview") {
                    ScrollView([.horizontal, .vertical]) {
                        Text(verbatim: artifact.preview)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .frame(minHeight: 220, maxHeight: 320, alignment: .topLeading)
                    .accessibilityIdentifier("settings.diagnostics.preview")
                }

                Section("Diagnostic file ready") {
                    Text("\(formattedByteCount(artifact.byteCount)) archive is ready on this phone. Tap Share when you are ready to choose who gets it. Nothing leaves Making Tracks before then.")
                        .font(.callout.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }

            }

            Section("Before sharing") {
                if artifact != nil {
                    diagnosticsBullet("You choose the person or app that gets the file.")
                }
                diagnosticsBullet("Your device name, exact location, and searches are not included in the export.")
                if artifact != nil {
                    diagnosticsBullet("Making Tracks has no upload endpoint.")
                }
            }

            if scrubFailed {
                Section("Nothing was shared") {
                    diagnosticsBullet("No archive was created and staged files were deleted.")
                    diagnosticsBullet("Retry with a shorter window, or send a screenshot of this screen.")
                }

                Section("Blocked pattern") {
                    Text("privacy scrub failed: reason=place-identifier-shaped-content action=staging-deleted")
                        .font(.system(.caption, design: .monospaced))
                        .accessibilityIdentifier("settings.diagnostics.scrub-failed")
                }
            }
        }
        .navigationTitle("Diagnostics")
        .safeAreaInset(edge: .bottom) {
            actionBar
        }
        .sheet(item: $shareItem) { item in
            ActivityShareSheet(activityItems: [item.url])
        }
        .onDisappear {
            preparationTask?.cancel()
            cleanupPreparedArtifact()
        }
        .confirmationDialog("Delete diagnostic logs?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete logs", role: .destructive) {
                deleteDiagnostics()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes logs and prepared diagnostic files stored on this phone. It cannot delete anything you already shared.")
        }
    }

    @ViewBuilder
    private var actionBar: some View {
        HStack(spacing: 10) {
            if scrubFailed {
                Button("Try 15 min") {
                    selectedWindow = .fifteenMinutes
                    beginPreparation()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("settings.diagnostics.retry-shorter")

                Button("Delete logs", role: .destructive) {
                    showDeleteConfirmation = true
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("settings.diagnostics.delete")
            } else if let artifact {
                Button("Cancel") {
                    cleanupPreparedArtifact()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("settings.diagnostics.cancel")

                Button("Share") {
                    shareItem = DiagnosticsShareItem(url: artifact.archiveURL)
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("settings.diagnostics.share")
            } else {
                Button(isPreparing ? "Preparing" : "Prepare") {
                    beginPreparation()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isPreparing)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("settings.diagnostics.prepare")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func diagnosticsBullet(_ text: String) -> some View {
        Label(text, systemImage: "circle.fill")
            .symbolRenderingMode(.palette)
            .foregroundStyle(.primary, Color.accentColor)
    }

    private func formattedByteCount(_ byteCount: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }

    private func beginPreparation() {
        guard preparationTask == nil else { return }
        preparationTask = Task {
            await prepare()
            preparationTask = nil
        }
    }

    private func prepare() async {
        guard !isPreparing else { return }
        isPreparing = true
        defer { isPreparing = false }
        scrubFailed = false
        artifact = nil
        let request = DiagnosticsExportRequest(selectedWindow: selectedWindow)
        let currentStorageStatus = storageStatus
        do {
            let preparedArtifact = try await DiagnosticsRuntime.prepareArtifact(
                request: request,
                storageStatus: currentStorageStatus
            )
            try Task.checkCancellation()
            artifact = preparedArtifact
        } catch is CancellationError {
            return
        } catch DiagnosticLogExportError.privacyScrubFailed {
            scrubFailed = true
        } catch {
            MakingTracksLog.startup.error("diagnostics export failed reason=\(MakingTracksLog.errorLabel(error), privacy: .public)")
            scrubFailed = true
        }
    }

    private func cleanupPreparedArtifact() {
        let staging = try? DiagnosticsRuntime.stagingRoot()
        if let staging, FileManager.default.fileExists(atPath: staging.path) {
            try? FileManager.default.removeItem(at: staging)
        }
        artifact = nil
        shareItem = nil
    }

    private func deleteDiagnostics() {
        do {
            let store = try DiagnosticsRuntime.makeStore()
            try store.deleteDiagnostics(stagingRoot: DiagnosticsRuntime.stagingRoot())
            artifact = nil
            scrubFailed = false
            showDeleteConfirmation = false
        } catch {
            MakingTracksLog.startup.error("diagnostics delete failed reason=\(MakingTracksLog.errorLabel(error), privacy: .public)")
        }
    }

}

private struct DiagnosticsShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct DiagnosticsExportRequest: Equatable, Sendable {
    let window: DiagnosticLogWindow

    init(selectedWindow: DiagnosticLogWindow) {
        self.window = selectedWindow
    }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

enum DiagnosticsRuntime {
    static func makeStore() throws -> DiagnosticLogStore {
        let bundleIdentifier = Self.bundleIdentifier
        let root = try DiagnosticLogStore.defaultRoot(bundleIdentifier: bundleIdentifier)
        return DiagnosticLogStore(root: root)
    }

    static func stagingRoot() throws -> URL {
        let root = try DiagnosticLogStore.defaultRoot(bundleIdentifier: bundleIdentifier)
        return root.deletingLastPathComponent().appendingPathComponent("DiagnosticExports", isDirectory: true)
    }

    @MainActor
    static func metadata(storageStatus: StorageMenuStatus) -> DiagnosticLogMetadata {
        DiagnosticLogMetadata(
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            commit: buildCommit(),
            osVersion: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            deviceModel: deviceModel(),
            installedPacks: storageStatus.diagnosticInstalledPacks
        )
    }

    @MainActor
    static func prepareArtifact(
        request: DiagnosticsExportRequest,
        storageStatus: StorageMenuStatus
    ) async throws -> DiagnosticLogArtifact {
        let exportMetadata = metadata(storageStatus: storageStatus)
        let stagingBase = try stagingRoot()
        return try await runPreparationAttempt(stagingBase: stagingBase) { attemptRoot in
            let store = try makeStore()
            return try prepareArtifact(
                request: request,
                store: store,
                metadata: exportMetadata,
                stagingRoot: attemptRoot
            )
        }
    }

    static func runPreparationAttempt<Value: Sendable>(
        stagingBase: URL,
        operation: @escaping @Sendable (URL) throws -> Value
    ) async throws -> Value {
        let attemptRoot = stagingBase.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            return try await runCancellableDetachedOperation {
                try operation(attemptRoot)
            }
        } catch {
            if FileManager.default.fileExists(atPath: attemptRoot.path) {
                try? FileManager.default.removeItem(at: attemptRoot)
            }
            throw error
        }
    }

    static func runCancellableDetachedOperation<Value: Sendable>(
        _ operation: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        let worker = Task.detached(priority: .userInitiated, operation: operation)
        return try await withTaskCancellationHandler {
            let value = try await worker.value
            try Task.checkCancellation()
            return value
        } onCancel: {
            worker.cancel()
        }
    }

    static func prepareArtifact(
        request: DiagnosticsExportRequest,
        store: DiagnosticLogStore,
        metadata: DiagnosticLogMetadata,
        stagingRoot: URL,
        exportedAt: @escaping @Sendable () -> Date = Date.init
    ) throws -> DiagnosticLogArtifact {
        let exporter = DiagnosticLogExporter(
            store: store,
            metadata: metadata,
            exportedAt: exportedAt
        )
        return try exporter.prepare(window: request.window, stagingRoot: stagingRoot)
    }

    private static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "app.making-tracks.MakingTracks"
    }

    private static func buildCommit() -> String {
        guard let url = Bundle.main.url(forResource: "BuildInfo", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dictionary = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let commit = dictionary["GitCommit"] as? String
        else { return "unknown" }
        return commit
    }

    private static func deviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingCString: $0) ?? "unknown"
            }
        }
    }
}

private extension DiagnosticLogWindow {
    static let settingsOptions: [DiagnosticLogWindow] = [.fifteenMinutes, .lastHour, .everything]

    var label: String {
        switch self {
        case .fifteenMinutes:
            return "15 min"
        case .lastHour:
            return "Last hour"
        case .everything:
            return "Everything"
        }
    }
}

struct PinSizePreviewMetrics: Equatable {
    let circleDiameter: Double
    let categoryIconScale: Double
    let badgeIconScale: Double
    let badgeOffset: Double

    init(pinSize: PinSize) {
        circleDiameter = pinSize.circleRadius * 2
        categoryIconScale = pinSize.categoryIconScale
        badgeIconScale = pinSize.badgeIconScale
        badgeOffset = PinLayers.baseBadgeOffset * pinSize.multiplier
    }
}

private struct PinSizePreview: View {
    let pinSize: PinSize
    let theme: MapTheme

    private var metrics: PinSizePreviewMetrics {
        PinSizePreviewMetrics(pinSize: pinSize)
    }

    var body: some View {
        ZStack {
            MapThemeColor.color(hex: theme.background)
            dummyMapLines
            dummyPin
        }
        .frame(maxWidth: .infinity, minHeight: 96)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(MapThemeColor.color(hex: theme.boundaries).opacity(0.55), lineWidth: 1)
        )
    }

    private var dummyMapLines: some View {
        GeometryReader { proxy in
            let size = proxy.size
            Path { path in
                path.move(to: CGPoint(x: size.width * 0.06, y: size.height * 0.72))
                path.addCurve(
                    to: CGPoint(x: size.width * 0.94, y: size.height * 0.28),
                    control1: CGPoint(x: size.width * 0.30, y: size.height * 0.50),
                    control2: CGPoint(x: size.width * 0.58, y: size.height * 0.84)
                )
                path.move(to: CGPoint(x: size.width * 0.12, y: size.height * 0.22))
                path.addLine(to: CGPoint(x: size.width * 0.82, y: size.height * 0.58))
                path.move(to: CGPoint(x: size.width * 0.22, y: size.height * 0.88))
                path.addLine(to: CGPoint(x: size.width * 0.62, y: size.height * 0.10))
            }
            .stroke(MapThemeColor.color(hex: theme.roads), lineWidth: 5)

            Path { path in
                path.addRect(CGRect(x: size.width * 0.06, y: size.height * 0.10, width: size.width * 0.26, height: size.height * 0.22))
                path.addRect(CGRect(x: size.width * 0.68, y: size.height * 0.66, width: size.width * 0.24, height: size.height * 0.18))
            }
            .fill(MapThemeColor.color(hex: theme.parks).opacity(theme.showsParks ? 0.75 : 0.35))
        }
    }

    private var dummyPin: some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(MapThemeColor.color(hex: PinLayers.pinColor))
                .frame(width: CGFloat(metrics.circleDiameter), height: CGFloat(metrics.circleDiameter))
                .overlay {
                    Image(systemName: "star.fill")
                        .font(.system(size: CGFloat(PinLayers.categorySymbolPointSize * metrics.categoryIconScale), weight: .bold))
                        .foregroundStyle(.white)
                }

            Image(systemName: "bookmark.fill")
                .font(.system(size: CGFloat(10 * metrics.badgeIconScale), weight: .bold))
                .foregroundStyle(.white)
                .frame(width: CGFloat(15 * metrics.badgeIconScale), height: CGFloat(15 * metrics.badgeIconScale))
                .background(Color.accentColor, in: Circle())
                .offset(x: CGFloat(metrics.badgeOffset * 0.55), y: CGFloat(-metrics.badgeOffset * 0.55))
        }
    }
}

enum SettingsStorageNavigation {
    static let destination = MenuDestination.offlineMaps
}

private struct SettingsStorageSummary: View {
    let storageStatus: StorageMenuStatus

    var body: some View {
        HStack(spacing: 10) {
            storageIcon
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text("Manage offline maps")
                    .foregroundStyle(.primary)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var storageIcon: some View {
        switch storageStatus.kind {
        case .loading:
            Image(systemName: "internaldrive")
        case .unavailable:
            Image(systemName: "exclamationmark.triangle")
        case .ready:
            Image(systemName: "arrow.down.circle")
        }
    }

    private var statusText: String {
        switch storageStatus.kind {
        case .loading:
            return "Checking installed maps"
        case .unavailable:
            return "Storage unavailable"
        case .ready:
            if storageStatus.regions.isEmpty {
                return "No offline regions installed"
            }
            return "\(storageStatus.totalBytesText) installed"
        }
    }
}

private struct AboutView: View {
    let attribution: [Attribution]

    private static let buildCommit = loadBuildCommit()
    private static let appVersion = loadAppVersion()
    private static let ossCredits = loadOSSCredits()
    private static let osmCopyrightURL = URL(string: "https://www.openstreetmap.org/copyright")!
    private static let privacyPolicyURL = URL(string: "https://making-tracks.app/privacy")!

    private static func loadBuildCommit() -> String {
        guard let url = Bundle.main.url(forResource: "BuildInfo", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String],
              let commit = plist["GitCommit"]
        else { return "unknown" }
        return commit
    }

    private static func loadAppVersion() -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String
        let build = info["CFBundleVersion"] as? String
        switch (version?.isEmpty == false ? version : nil, build?.isEmpty == false ? build : nil) {
        case let (.some(version), .some(build)):
            return "\(version) (\(build))"
        case let (.some(version), nil):
            return version
        case let (nil, .some(build)):
            return build
        case (nil, nil):
            return "unknown"
        }
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
                    Text(verbatim: "Version \(Self.appVersion)")
                        .font(.caption)
                        .accessibilityIdentifier("about.app-version")
                    Text(verbatim: "Build \(Self.buildCommit)")
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .accessibilityIdentifier("credits.build-commit")
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Privacy")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Link(destination: Self.privacyPolicyURL) {
                        Text("Privacy policy")
                    }
                    .accessibilityValue(Self.privacyPolicyURL.absoluteString)
                    .accessibilityIdentifier("about.privacy-policy")
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
                    ForEach(ListPickerTargetLists.options(from: lists)) { list in
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
        actionError = nil
        let trimmedName = newListName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            actionError = "Enter a list name."
            return
        }
        do {
            let list = try await model.createList(named: trimmedName)
            guard let id = list.id else { throw AppDatabaseError.unreadableDatabase }
            try await model.addToList(placeID: placeID, listID: id)
            newListName = ""
            actionError = nil
            await reload()
            onChanged()
        } catch {
            actionError = ListsCopy.listNameCreateFailureMessage(for: error, draftName: trimmedName)
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

private struct TrackFilterPickerSheet: View {
    @Binding var draft: TrackFilterPickerDraft
    let listOptions: [TrackFilterPickerListOption]
    let categoryOptions: [MapLayerCategory]
    let scopedVisitCount: Int
    let onDraftChanged: @MainActor () -> Void
    let onApply: @MainActor () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.clear
                .accessibilityIdentifier("track-filter-picker.sheet")

            NavigationStack {
                List {
                    Section {
                        filterButton(
                            title: "Loved",
                            systemImage: "heart.fill",
                            isSelected: draft.lovedOnly,
                            accessibilityIdentifier: "track-filter-picker.loved"
                        ) {
                            draft.toggleLoved()
                        }
                    }

                    Section("Lists") {
                        if listOptions.isEmpty {
                            Text("No saved lists")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(listOptions) { option in
                                filterButton(
                                    title: option.title,
                                    systemImage: "list.bullet",
                                    isSelected: draft.listIDs.contains(option.id),
                                    accessibilityIdentifier: "track-filter-picker.list.\(option.id)"
                                ) {
                                    draft.toggleList(id: option.id)
                                }
                            }
                        }
                    }

                    Section("Types") {
                        ForEach(categoryOptions) { category in
                            filterButton(
                                title: category.title,
                                systemImage: PinLayers.categorySymbolNames[category.iconName] ?? "mappin",
                                isSelected: draft.categories.contains(category.id),
                                accessibilityIdentifier: "track-filter-picker.category.\(category.id)"
                            ) {
                                draft.toggleCategory(category.id)
                            }
                        }
                    }
                }
                .navigationTitle("Filter tracks")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel("Close")
                        .accessibilityIdentifier("track-filter-picker.close")
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    Button {
                        onApply()
                    } label: {
                        Text(verbatim: TrackFilterPickerCopy.applyLabel(scopedVisitCount: scopedVisitCount))
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial)
                    .accessibilityIdentifier("track-filter-picker.apply")
                }
            }
        }
    }

    private func filterButton(
        title: String,
        systemImage: String,
        isSelected: Bool,
        accessibilityIdentifier: String,
        toggle: @escaping () -> Void
    ) -> some View {
        Button {
            toggle()
            onDraftChanged()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .frame(width: 24)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
                Text(verbatim: title)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
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

                    Toggle(
                        "Show offline coverage shading",
                        isOn: Binding(
                            get: { visibility.showCoverageShading },
                            set: { visible in
                                var next = visibility
                                next.showCoverageShading = visible
                                visibility = next
                            }
                        )
                    )
                    .accessibilityIdentifier("map.layers.coverage-shading")
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
    let onManageVisits: (String) -> Void
    let setNearbyPromptSuppressed: @MainActor (String, Bool) -> Bool
    let showHiddenMode: Bool

    @State private var sheetInstanceID = UUID().uuidString
    @State private var card: PlaceCardModel?
    @State private var isLoading = true
    @State private var actionError: String?
    @State private var showListPicker = false
    @State private var actionBarHeight: CGFloat = 0
    @State private var isPerformingAction = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                cardContent
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, CGFloat(
                        PlaceCardOverlayMetrics.contentBottomPadding(actionBarHeight: Double(actionBarHeight))
                    ))
            }
            .accessibilityIdentifier("place-card.instance.\(sheetInstanceID)")

            if let card {
                VStack(spacing: 0) {
                    placeCardBottomFade
                        .allowsHitTesting(false)
                    actionBar(card)
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(key: PlaceCardActionBarHeightKey.self, value: proxy.size.height)
                            }
                        )
                }
                .onPreferenceChange(PlaceCardActionBarHeightKey.self) { height in
                    actionBarHeight = height
                }
            }
        }
        .presentationDetents(cardDetents)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(PlaceCardVisualSpec.cardCornerRadius)
        .presentationBackground(PlaceCardVisualSpec.cardBackground)
        .presentationBackgroundInteraction(.enabled(upThrough: dynamicTypeSize.isAccessibilitySize ? .large : .medium))
        .preferredColorScheme(.light)
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
        .task(id: placeID) {
            await observeImageChanges()
        }
    }

    @ViewBuilder
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let card {
                header
                Text(verbatim: card.name)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(PlaceCardVisualSpec.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("place-card.title")
                typeRow(card)
                photoSlot(card)
                if let blurb = card.blurb {
                    Text(verbatim: blurb)
                        .font(.body)
                        .foregroundStyle(PlaceCardVisualSpec.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("place-card.description")
                }
                sourceArticleLink(card.sourceArticleLink)
                listChips(card.listNames)
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
    }

    private var cardDetents: Set<PresentationDetent> {
        Set(PlaceCardDetentPolicy.identifiers(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize).compactMap { identifier in
            switch identifier {
            case "medium":
                return .medium
            case "large":
                return .large
            default:
                return nil
            }
        })
    }

    private var header: some View {
        HStack {
            Spacer()

            Menu {
                Button("Add to list") {
                    showListPicker = true
                }
                .accessibilityIdentifier("place-card.add-to-list")
            } label: {
                Image(systemName: PlaceCardVisualSpec.closeSystemImageName)
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(PlaceCardVisualSpec.secondaryText)
            .accessibilityLabel("More")
            .accessibilityIdentifier("place-card.more")
        }
    }

    private var placeCardBottomFade: some View {
        LinearGradient(
            stops: [
                Gradient.Stop(color: Color(.systemBackground).opacity(0), location: 0),
                Gradient.Stop(color: Color(.systemBackground), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: CGFloat(PlaceCardOverlayMetrics.fadeHeight))
    }

    @ViewBuilder
    private func sourceArticleLink(_ link: SourceArticleLink?) -> some View {
        if let link {
            Link(destination: link.url) {
                Text(verbatim: link.label)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(PlaceCardVisualSpec.linkText)
            }
            .accessibilityIdentifier("place-card.source-article")
            .accessibilityLabel(Text(verbatim: "\(link.sourceName) source article"))
        }
    }

    @ViewBuilder
    private func typeRow(_ card: PlaceCardModel) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(PlaceCardVisualSpec.mediaBackground)
                .frame(
                    width: PlaceCardVisualSpec.typeSwatchSide,
                    height: PlaceCardVisualSpec.typeSwatchSide
                )
                .accessibilityHidden(true)
            Text(verbatim: categoryLabel(card.category))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(PlaceCardVisualSpec.secondaryText)
                .accessibilityIdentifier("place-card.type.label")
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func photoSlot(_ card: PlaceCardModel) -> some View {
        if let photo = card.photo {
            PlaceCardPhotoSlot(photo: photo, model: model)
        } else if PlaceCardVisualSpec.showsMediaSlotWhenPhotoMissing {
            PlaceCardMissingPhotoSlot(placeName: card.name)
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
                            .foregroundStyle(PlaceCardVisualSpec.primaryText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(PlaceCardVisualSpec.neutralActionBackground, in: Capsule())
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
                .foregroundStyle(PlaceCardVisualSpec.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("place-card.attribution")
        }
    }

    @ViewBuilder
    private func actionBar(_ card: PlaceCardModel) -> some View {
        let slots = PlaceCardActionSlots(pinState: card.pinState).actions
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 10))

        VStack(alignment: .leading, spacing: 8) {
            if let actionError {
                Text(verbatim: actionError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("place-card.action-error")
            }

            layout {
                ForEach(Array(slots.enumerated()), id: \.offset) { _, action in
                    actionButton(action, card: card)
                        .frame(maxWidth: .infinity)
                        .accessibilitySortPriority(10)
                }
            }
        }
        .disabled(isPerformingAction)
        .padding(.horizontal, PlaceCardVisualSpec.actionBarHorizontalPadding)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(PlaceCardVisualSpec.cardBackground)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("place-card.action-bar")
        .accessibilitySortPriority(10)
    }

    @ViewBuilder
    private func actionButton(_ action: PlaceCardAction, card: PlaceCardModel) -> some View {
        switch action {
        case .save:
            saveButton(card)
        case .seen:
            Button {
                startAction { await setVisited(true, action: .seen) }
            } label: {
                actionLabel(action)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("place-card.visited")
            .accessibilityValue("Not seen")
        case .love:
            Button {
                startAction { await setLoved(true, action: .love) }
            } label: {
                actionLabel(action)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("place-card.loved")
            .accessibilityValue("Not loved")
        case .unlove:
            Button {
                startAction { await setLoved(false, action: .unlove) }
            } label: {
                actionLabel(action)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("place-card.loved")
            .accessibilityValue("Loved")
        case .hide:
            hideButton(card)
        case let .unsee(isEnabled):
            Button {
                startAction { await setVisited(false, action: action) }
            } label: {
                actionLabel(action)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("place-card.unsee")
            .accessibilityValue("Seen")
            .disabled(!isEnabled)
        case .seenDisabled:
            Button {} label: {
                actionLabel(action)
            }
                .buttonStyle(.plain)
                .accessibilityIdentifier("place-card.visited")
                .accessibilityValue("Hidden")
                .disabled(true)
        case .unhide:
            unhideButton()
        }
    }

    private func saveButton(_ card: PlaceCardModel) -> some View {
        Button {
            showListPicker = true
        } label: {
            actionLabel(.save, title: card.pinState.saved ? "Saved" : "Save")
        }
        .highPriorityGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    showListPicker = true
                }
        )
        .buttonStyle(.plain)
        .accessibilityIdentifier("place-card.save")
        .accessibilityValue(card.pinState.saved ? "Saved" : "Not saved")
        .accessibilityHint(PlaceCardAction.save.accessibilityHint(isSaved: card.pinState.saved) ?? "")
    }

    private func hideButton(_ card: PlaceCardModel) -> some View {
        Button {
            startAction { await setHidden(card) }
        } label: {
            actionLabel(.hide)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("place-card.hide")
        .accessibilityValue("Not hidden")
    }

    private func unhideButton() -> some View {
        Button {
            startAction { await setHidden(false) }
        } label: {
            actionLabel(.unhide)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("place-card.unhide")
        .accessibilityValue("Hidden")
    }

    private func actionLabel(_ action: PlaceCardAction, title: String? = nil) -> some View {
        let tone = PlaceCardVisualSpec.tone(for: action)
        return Text(verbatim: title ?? action.title)
            .font(.headline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .frame(minHeight: PlaceCardVisualSpec.actionMinimumHeight)
            .foregroundStyle(PlaceCardVisualSpec.actionForeground(for: tone))
            .background(PlaceCardVisualSpec.actionBackground(for: tone))
            .clipShape(RoundedRectangle(cornerRadius: PlaceCardVisualSpec.actionCornerRadius, style: .continuous))
            .overlay {
                if tone == .disabled {
                    RoundedRectangle(cornerRadius: PlaceCardVisualSpec.actionCornerRadius, style: .continuous)
                        .stroke(PlaceCardVisualSpec.disabledText.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
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
            if let nextCard {
                MakingTracksLog.flowEvent("place viewed", fields: [
                    .object("placeID", placeID),
                    .object("placeName", nextCard.name),
                    .public("source", "card"),
                ])
            }
        }
    }

    private func refreshCard() async {
        let nextCard = await model?.cardModel(for: placeID)
        await MainActor.run {
            card = nextCard
        }
    }

    private func observeImageChanges() async {
        guard let changes = model?.imageChanges else { return }
        for await ids in changes {
            guard !Task.isCancelled else { return }
            guard ids.contains(placeID) else { continue }
            await refreshCard()
        }
    }

    private func setVisited(_ visited: Bool, action: PlaceCardAction) async {
        if !visited, (await model?.visitCount(placeID: placeID) ?? 0) > 1 {
            // #217: Rob has not fixed the stale single-visit threshold yet, so
            // only the unambiguous multi-visit case routes to row selection here.
            await MainActor.run {
                isPerformingAction = false
                dismiss()
                onManageVisits(placeID)
            }
            return
        }
        await performAction(suppressingPromptFor: action) {
            try await model?.setVisited(placeID: placeID, visited: visited)
        }
    }

    private func setLoved(_ loved: Bool, action: PlaceCardAction) async {
        await performAction(suppressingPromptFor: action) {
            try await model?.setLoved(placeID: placeID, loved: loved)
        }
    }

    private func startAction(_ action: @escaping () async -> Void) {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        actionError = nil
        Task {
            await action()
        }
    }

    private func setHidden(_ card: PlaceCardModel) async {
        let insertedNearbyPromptSuppression = await beginNearbyPromptSuppression(for: .hide)
        await MainActor.run {
            actionError = nil
        }
        do {
            try await model?.setHidden(placeID: placeID, hidden: true)
            await MainActor.run {
                isPerformingAction = false
                self.card = nil
                dismiss()
                onHide(placeID, card.name)
            }
        } catch {
            await rollbackNearbyPromptSuppressionIfNeeded(insertedNearbyPromptSuppression)
            await MainActor.run {
                isPerformingAction = false
                actionError = "Could not save that change."
            }
        }
    }

    private func setHidden(_ hidden: Bool) async {
        await performAction(suppressingPromptFor: hidden ? .hide : .unhide) {
            try await model?.setHidden(placeID: placeID, hidden: hidden)
        }
    }

    private func performAction(
        suppressingPromptFor nearbyPromptAction: PlaceCardAction? = nil,
        _ action: () async throws -> Void
    ) async {
        let insertedNearbyPromptSuppression = await beginNearbyPromptSuppression(for: nearbyPromptAction)
        do {
            try await action()
            await clearNearbyPromptSuppressionIfNeeded(for: nearbyPromptAction)
            await MainActor.run { actionError = nil }
            await refreshCard()
            await MainActor.run { isPerformingAction = false }
        } catch {
            await rollbackNearbyPromptSuppressionIfNeeded(insertedNearbyPromptSuppression)
            await MainActor.run {
                isPerformingAction = false
                actionError = "Could not save that change."
            }
        }
    }

    private func beginNearbyPromptSuppression(for action: PlaceCardAction?) async -> Bool {
        guard let action,
              NearbyPromptSuppressionPolicy.suppressesPromptImmediately(for: action)
        else { return false }
        return setNearbyPromptSuppressed(placeID, true)
    }

    private func clearNearbyPromptSuppressionIfNeeded(for action: PlaceCardAction?) async {
        guard let action,
              NearbyPromptSuppressionPolicy.clearsPromptSuppressionOnSuccess(for: action)
        else { return }
        _ = setNearbyPromptSuppressed(placeID, false)
    }

    private func rollbackNearbyPromptSuppressionIfNeeded(_ insertedSuppression: Bool) async {
        guard insertedSuppression else { return }
        // Correct while startAction serialises card actions; concurrent suppressing actions would need per-action
        // contribution tracking instead of this single inserted/not-inserted rollback flag.
        _ = setNearbyPromptSuppressed(placeID, false)
    }

    private func categoryLabel(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
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

private struct PlaceCardActionBarHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct PlaceCardMissingPhotoSlot: View {
    let placeName: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: PlaceCardVisualSpec.actionCornerRadius, style: .continuous)
                .fill(PlaceCardVisualSpec.mediaBackground)
            Image(systemName: "photo")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(PlaceCardVisualSpec.secondaryText.opacity(0.8))
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .frame(height: PlaceCardVisualSpec.mediaSlotHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("No photo available for \(placeName)")
        .accessibilityIdentifier("place-card.photo.placeholder")
    }
}

private struct PlaceCardPhotoSlot: View {
    let photo: PlaceCardPhoto
    let model: MapScreenModel?

    @State private var image: UIImage?
    @State private var didFail = false

    private var loadID: String {
        photo.thumbSHA256 ?? photo.accessibilityLabel
    }

    private var slotAccessibilityLabel: String {
        didFail && photo.thumbURL != nil ? "Photo unavailable" : photo.accessibilityLabel
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.thinMaterial)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .accessibilityHidden(true)
            } else if photo.thumbURL == nil || didFail {
                Image(systemName: "photo")
                    .font(.system(size: 42, weight: .regular))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            } else if !didFail {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: PlaceCardVisualSpec.mediaSlotHeight)
        .clipShape(RoundedRectangle(cornerRadius: PlaceCardVisualSpec.actionCornerRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(slotAccessibilityLabel)
        .accessibilityIdentifier("place-card.photo")
        .task(id: loadID) {
            await loadPhoto(expectedLoadID: loadID)
        }
    }

    private func loadPhoto(expectedLoadID: String) async {
        guard !Task.isCancelled else { return }
        await MainActor.run {
            guard !Task.isCancelled, loadID == expectedLoadID else { return }
            image = nil
            didFail = false
        }
        guard photo.thumbURL != nil else { return }
        guard let data = await model?.photoData(for: photo) else {
            await MainActor.run {
                guard !Task.isCancelled, loadID == expectedLoadID else { return }
                didFail = true
            }
            return
        }
        await MainActor.run {
            guard !Task.isCancelled, loadID == expectedLoadID else { return }
            if Self.isSafeDecodedImage(data), let decoded = UIImage(data: data) {
                image = decoded
            } else {
                didFail = true
            }
        }
    }

    private static func isSafeDecodedImage(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0,
              height > 0
        else { return false }
        // Tunable guard shared with the card contract: enough for thumbnails, bounded against decode bombs.
        return width <= 16_000_000 / height
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

enum ListMapPinAccessibilityNames {
    static func names(from items: [ListPlace], visiblePlaceIDs: Set<String>) -> [String: String] {
        items.reduce(into: [:]) { names, item in
            guard visiblePlaceIDs.contains(item.placeID) else { return }
            names[item.placeID] = item.name
        }
    }
}

enum ListDetailItemActions {
    static func canRemoveStoredMembership(from list: PlaceList) -> Bool {
        !(list.isSystem && list.kind == PlaceList.trackKind)
    }
}

enum ListDetailVisitActions {
    static func canEditTrackVisits(from list: PlaceList) -> Bool {
        list.isSystem && list.kind == PlaceList.trackKind
    }
}

private final class MapScreenAsyncBroadcaster<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var nextID = 0
    private var continuations: [Int: AsyncStream<Element>.Continuation] = [:]

    func stream() -> AsyncStream<Element> {
        AsyncStream { continuation in
            let id = lock.withLock {
                let id = nextID
                nextID += 1
                continuations[id] = continuation
                return id
            }
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock {
                    self?.continuations[id] = nil
                }
            }
        }
    }

    func yield(_ value: Element) {
        let snapshot = lock.withLock { Array(continuations.values) }
        for continuation in snapshot {
            continuation.yield(value)
        }
    }
}

enum ListPickerTargetLists {
    static func options(from lists: [PlaceList]) -> [PlaceList] {
        lists.filter(canStoreMembership)
    }

    private static func canStoreMembership(_ list: PlaceList) -> Bool {
        if !list.isSystem { return true }
        return list.kind == PlaceList.defaultKind && list.name == AppDatabase.wantToGoListName
    }
}

@MainActor
final class MapScreenModel {
    private let database: AppDatabase
    private let tileCache: TileCache?
    private let thumbnailLoader: ThumbnailLoader?
    private let offlineStore: OfflineRegionStore?
    private let forceTileNetworkOffline: Bool
    private let fixturePlaces: [String: PlaceRef]
    private let coreLoop: CoreLoopController
    private var tileClients: [String: TileClient] = [:]
    private var tileClientViewportTasks: [String: Task<Void, Never>] = [:]
    private var mapRegionCatalog = OfflineRegionCatalog.empty
    private let viewportChangeBroadcaster = MapScreenAsyncBroadcaster<Void>()
    private var selectedRegionID = MapRegion.malaysiaSingaporeBrunei.rawValue
    private var hiddenTracker: HiddenMembershipTracker
    private var showHiddenPlaces = false

    var changes: AsyncStream<Set<String>> { coreLoop.changes }

    var imageChanges: AsyncStream<Set<String>>? {
        tileClient(for: selectedRegionID)?.imageChanges
    }

    var viewportChanges: AsyncStream<Void> {
        viewportChangeBroadcaster.stream()
    }

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
            let thumbnailCache = try ThumbnailCache(directory: cacheRoot.appendingPathComponent("Thumbs", isDirectory: true))
#if DEBUG
            let thumbnailFetcher: TileFetching = forceTileNetworkOffline ? OfflineProofFetcher() : HTTPTileFetcher()
#else
            let thumbnailFetcher: TileFetching = HTTPTileFetcher()
#endif
            thumbnailLoader = ThumbnailLoader(fetcher: thumbnailFetcher, cache: thumbnailCache)
            offlineStore = try? OfflineRegionStore.documentsStore()
        } else {
            tileCache = nil
            thumbnailLoader = nil
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
            let detail = offlineInstallFailureDetail(for: error)
            MakingTracksLog.install.error("offline install failed region=\(region, privacy: .private(mask: .hash)) reason=\(detail, privacy: .public)")
            return offlineInstallFailureMessage(for: error)
        }
    }

    func installedOfflinePublishVersions(for catalog: OfflineRegionCatalog) async -> [String: String] {
        guard let offlineStore else { return [:] }
        return await Task.detached {
            var installed: [String: String] = [:]
            if let summary = try? offlineStore.installedPackStorageSummary() {
                for pack in summary.packs {
                    installed[pack.region] = pack.publishVersion
                }
            }
            return installed
        }.value
    }

    func offlineMapsLocalState(for catalog: OfflineRegionCatalog) async -> OfflineMapsLocalState {
        async let installed = installedOfflinePublishVersions(for: catalog)
        async let pausedRegions = pausedOfflineDownloadRegions(for: catalog)
        async let storageStatus = storageMenuStatus(catalog: catalog)
        let quarantines = offlinePackQuarantines()
        return await OfflineMapsLocalState(
            installed: installed,
            pausedRegions: pausedRegions,
            quarantines: quarantines,
            storageStatus: storageStatus
        )
    }

    func offlineRegionCatalog(
        allowsCellularDownloads: Bool,
        catalogFetcher: TileFetching? = nil
    ) async -> OfflineRegionCatalog {
        let usesDefaultFetcher = catalogFetcher == nil
        let catalogFetcher = catalogFetcher ?? offlineAvailabilityFetcher(
            allowsCellularDownloads: allowsCellularDownloads
        )
#if DEBUG
        if forceTileNetworkOffline, usesDefaultFetcher {
            return .empty
        }
#endif
        do {
            let catalog = try await OfflineRegionCatalog.current(
                fetcher: catalogFetcher,
                cache: try? OfflineRegionCatalogCache.appCache()
            )
            MakingTracksLog.downloads.info("offline regions index fetched regions=\(catalog.zones.count, privacy: .public)")
            return catalog
        } catch {
            MakingTracksLog.downloads.error("offline regions index failed reason=\(MakingTracksLog.errorLabel(error), privacy: .public)")
            return .empty
        }
    }

    func availableOfflinePublishVersions(
        for catalog: OfflineRegionCatalog,
        installedRegions: Set<String>,
        allowsCellularDownloads: Bool,
        availabilityFetcher: TileFetching? = nil
    ) async -> [String: String] {
        let availabilityFetcher = availabilityFetcher ?? offlineAvailabilityFetcher(
            allowsCellularDownloads: allowsCellularDownloads
        )
        do {
            let versions = try await OfflinePublishAvailability.currentPublishVersions(
                for: catalog,
                installedRegions: installedRegions,
                fetcher: availabilityFetcher
            )
            MakingTracksLog.downloads.info("offline catalog current fetched regions=\(versions.count, privacy: .public)")
            return versions
        } catch {
            MakingTracksLog.downloads.error("offline catalog current failed regions=\(installedRegions.count, privacy: .public) reason=\(MakingTracksLog.errorLabel(error), privacy: .public)")
            return [:]
        }
    }

    func availableOfflineAvailability(
        for catalog: OfflineRegionCatalog,
        installedRegions: Set<String>,
        allowsCellularDownloads: Bool,
        availabilityFetcher: TileFetching? = nil
    ) async -> OfflineMapsAvailability {
        let availabilityFetcher = availabilityFetcher ?? offlineAvailabilityFetcher(
            allowsCellularDownloads: allowsCellularDownloads
        )
        do {
            let availability = try await OfflinePublishAvailability.currentAvailability(
                for: catalog,
                installedRegions: installedRegions,
                fetcher: availabilityFetcher
            )
            MakingTracksLog.downloads.info("offline catalog current fetched regions=\(availability.publishVersions.count, privacy: .public) bytes=\(availability.storageBytes.count, privacy: .public)")
            return availability
        } catch {
            MakingTracksLog.downloads.error("offline catalog current failed regions=\(installedRegions.count, privacy: .public) reason=\(MakingTracksLog.errorLabel(error), privacy: .public)")
            return .empty
        }
    }

    private func offlineAvailabilityFetcher(allowsCellularDownloads: Bool) -> TileFetching {
#if DEBUG
        if forceTileNetworkOffline {
            return OfflineProofFetcher()
        }
#endif
        return HTTPTileFetcher.offlineAvailabilityProbe(
            allowsCellularDownloads: allowsCellularDownloads
        )
    }

    func pausedOfflineDownloadRegions(for catalog: OfflineRegionCatalog) async -> Set<String> {
        guard let offlineStore else { return [] }
        return await Task.detached {
            let paused = (try? offlineStore.pausedPendingDownloadRegions()) ?? []
            return Set(paused)
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

#endif

    func installedOfflineCoverageBBoxes() async -> [CoverageBBox] {
        guard let offlineStore else { return [] }
        return await Task.detached {
            var coverage: [CoverageBBox] = []
            let regionIDs = (try? offlineStore.installedPackStorageSummary().packs.map(\.region)) ?? []
            for regionID in regionIDs {
                guard let publish = try? offlineStore.installedPublish(region: regionID),
                      let coverageBBox = OfflineCoverageBBox.coverage(
                        fromManifestBasemapBBox: publish.manifest.basemap.bbox
                      )
                else { continue }
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
        guard let client = tileClient(for: selectedRegionID) else { return }
        try? await client.refreshPin()
        let state = await client.loadState
        let elapsedMS = Int(Date().timeIntervalSince(startedAt) * 1000)
        let regionID = selectedRegionID
        let stateLabel = state.rawValue
        MakingTracksLog.startup.info("manifest refresh finished region=\(regionID, privacy: .private(mask: .hash)) state=\(stateLabel, privacy: .public) durationMS=\(elapsedMS, privacy: .public)")
    }

    func storageMenuStatus(catalog: OfflineRegionCatalog? = nil) async -> StorageMenuStatus {
        guard let offlineStore else {
            MakingTracksLog.startup.info("storage summary unavailable")
            return .unavailable
        }
        let startedAt = Date()
        return await Task.detached {
            do {
                let status = StorageMenuStatus.ready(
                    from: try offlineStore.installedPackStorageSummary(),
                    catalog: catalog
                )
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
        await viewportFeatures(in: bbox, zoom: zoom, allowManifestRefresh: allowManifestRefresh).display
    }

    struct ViewportFeatures: Sendable {
        let display: [(MapPlace, PinState)]
        let nearbyPrompt: [(MapPlace, PinState)]
        let sourceCount: Int
        let flowMetrics: ViewportFlowMetrics?
    }

    func viewportFeatures(in bbox: BBox, zoom: Int, allowManifestRefresh: Bool = true) async -> ViewportFeatures {
        if !fixturePlaces.isEmpty {
            let sortedFixtures = fixturePlaces.values.sorted { $0.placeID < $1.placeID }
            let states = await states(for: Set(sortedFixtures.map(\.placeID)))
            let sourceFeatures = sortedFixtures.map { fixturePlace in
                let place = MapPlace(
                    id: fixturePlace.placeID,
                    lat: fixturePlace.lat,
                    lon: fixturePlace.lon,
                    tier: fixturePlace.tier,
                    category: fixturePlace.category
                )
                return (place, states[fixturePlace.placeID] ?? PinState(saved: false, visit: .none))
            }
            return ViewportFeatures(
                display: PinFeatureFilter.discoveryFeatures(sourceFeatures, showHidden: showHiddenPlaces),
                nearbyPrompt: PinFeatureFilter.nearbyPromptFeatures(sourceFeatures),
                sourceCount: sourceFeatures.count,
                flowMetrics: nil
            )
        }
        guard let client = await selectClient(for: bbox, allowManifestRefresh: allowManifestRefresh) else {
            return ViewportFeatures(display: [], nearbyPrompt: [], sourceCount: 0, flowMetrics: nil)
        }
        let places = await client.places(inViewport: bbox, zoom: zoom, allowManifestRefresh: allowManifestRefresh)
        let flowMetrics = await client.viewportFlowMetrics(in: bbox, zoom: zoom)
        let ids = places.map(\.id)
        let states = await states(for: Set(ids))
        let sourceFeatures = places.map { ($0, states[$0.id] ?? PinState(saved: false, visit: .none)) }
        return ViewportFeatures(
            display: PinFeatureFilter.discoveryFeatures(
                sourceFeatures,
                showHidden: showHiddenPlaces
            ),
            nearbyPrompt: PinFeatureFilter.nearbyPromptFeatures(sourceFeatures),
            sourceCount: sourceFeatures.count,
            flowMetrics: flowMetrics
        )
    }

    func currentViewportFeatures() async -> ViewportFeatures {
        if !fixturePlaces.isEmpty {
            let sortedFixtures = fixturePlaces.values.sorted { $0.placeID < $1.placeID }
            let states = await states(for: Set(sortedFixtures.map(\.placeID)))
            let sourceFeatures = sortedFixtures.map { fixturePlace in
                let place = MapPlace(
                    id: fixturePlace.placeID,
                    lat: fixturePlace.lat,
                    lon: fixturePlace.lon,
                    tier: fixturePlace.tier,
                    category: fixturePlace.category
                )
                return (place, states[fixturePlace.placeID] ?? PinState(saved: false, visit: .none))
            }
            return ViewportFeatures(
                display: PinFeatureFilter.discoveryFeatures(sourceFeatures, showHidden: showHiddenPlaces),
                nearbyPrompt: PinFeatureFilter.nearbyPromptFeatures(sourceFeatures),
                sourceCount: sourceFeatures.count,
                flowMetrics: nil
            )
        }
        guard let client = tileClient(for: selectedRegionID) else {
            return ViewportFeatures(display: [], nearbyPrompt: [], sourceCount: 0, flowMetrics: nil)
        }
        let places = await client.currentPlaces()
        let ids = places.map(\.id)
        let states = await states(for: Set(ids))
        let sourceFeatures = places.map { ($0, states[$0.id] ?? PinState(saved: false, visit: .none)) }
        return ViewportFeatures(
            display: PinFeatureFilter.discoveryFeatures(
                sourceFeatures,
                showHidden: showHiddenPlaces
            ),
            nearbyPrompt: PinFeatureFilter.nearbyPromptFeatures(sourceFeatures),
            sourceCount: sourceFeatures.count,
            flowMetrics: nil
        )
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

    func listMapPinAccessibilityNames(listID: Int64, visiblePlaceIDs: Set<String>) async -> [String: String] {
        let items = await listItems(listID: listID)
        return ListMapPinAccessibilityNames.names(from: items, visiblePlaceIDs: visiblePlaceIDs)
    }

    func trackVisits(listID: Int64? = nil, filter: TracksVisitFilter = .all) async -> [TrackVisit] {
        let db = database
        return await Task.detached {
            (try? db.trackVisits(listID: listID, filter: filter)) ?? []
        }.value
    }

    func trackGeometryContext(listID: Int64? = nil, filter: TracksVisitFilter = .all) async -> TrackGeometryContext {
        let db = database
        return await Task.detached {
            (try? db.trackGeometryContext(listID: listID, filter: filter)) ?? .empty
        }.value
    }

    func trackFeatureCollectionSnapshot(listID: Int64, filter: TracksVisitFilter = .all) async -> TrackSourceSnapshot {
        let db = database
        return await Task.detached {
            TrackSourceSnapshot.make(context: (try? db.trackGeometryContext(listID: listID, filter: filter)) ?? .empty)
        }.value
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
        let coreLoop = coreLoop
        try await Task.detached {
            try coreLoop.deleteList(id: id)
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
        let photo = await cardPhoto(for: placeID, name: base.name) ?? fixturePhoto(for: placeID, name: base.name)
        return base.enriching(photo: photo, listNames: lists)
    }

    func photoData(for photo: PlaceCardPhoto) async -> Data? {
        guard let image = photo.image,
              let thumbnailLoader
        else { return nil }
        return try? await thumbnailLoader.data(for: image)
    }

    private func cardPhoto(for placeID: String, name: String) async -> PlaceCardPhoto? {
        guard thumbnailLoader != nil,
              fixturePlaces[placeID] == nil,
              let tileClient = tileClient(for: selectedRegionID),
              let image = await tileClient.placeImage(for: placeID)
        else { return nil }
        return PlaceCardPhoto(placeName: name, image: image)
    }

    private func userListNames(containing placeID: String) async -> [String] {
        let db = database
        return await Task.detached {
            (try? db.userListNames(containing: placeID)) ?? []
        }.value
    }

    private func fixturePhoto(for placeID: String, name: String) -> PlaceCardPhoto? {
        guard placeID == "mt1_00000000000000000000000000" else { return nil }
        return PlaceCardPhoto(
            accessibilityLabel: "Photo of \(name)",
            attribution: "Fixture photo"
        )
    }

    func addToList(placeID: String, listID: Int64) async throws {
        guard let placeRef = await actionPlaceRef(for: placeID) else { throw MapScreenActionError.placeUnavailable }
        try coreLoop.addToList(placeRef, listID: listID)
        MakingTracksLog.flowEvent("verdict changed", fields: placeFields(placeRef) + [
            .public("action", "add-to-list"),
            .public("listID", String(listID)),
        ])
    }

    func removeFromList(placeID: String, listID: Int64) async throws {
        try coreLoop.removeFromList(placeID: placeID, listID: listID)
        MakingTracksLog.flowEvent("verdict changed", fields: [
            .object("placeID", placeID),
            .public("action", "remove-from-list"),
            .public("listID", String(listID)),
        ])
    }

    func setVisited(placeID: String, visited: Bool) async throws {
        guard let placeRef = await actionPlaceRef(for: placeID) else { throw MapScreenActionError.placeUnavailable }
        try coreLoop.setVisited(placeRef, visited)
        logVerdictChanged(placeRef: placeRef, action: "visited", enabled: visited)
    }

    func setLoved(placeID: String, loved: Bool) async throws {
        let placeRef = await actionPlaceRef(for: placeID)
        try coreLoop.setLoved(placeID: placeID, loved)
        MakingTracksLog.flowEvent("verdict changed", fields: (placeRef.map(placeFields) ?? [
            .object("placeID", placeID),
        ]) + [
            .public("action", "love"),
            .public("state", loved ? "on" : "off"),
        ])
    }

    func setVisitLoved(visitID: Int64, loved: Bool) async throws {
        try coreLoop.setVisitVerdict(id: visitID, loved ? .loved : nil)
    }

    func updateVisitDate(visitID: Int64, toDayContaining day: Date) async throws {
        try coreLoop.updateVisitDate(id: visitID, toDayContaining: day)
    }

    func reorderVisitsWithinDay(_ visitIDs: [Int64], dayContaining day: Date) async throws {
        try coreLoop.reorderVisitsWithinDay(visitIDs, dayContaining: day)
    }

    func moveVisit(visitID: Int64, toDayContaining day: Date, targetDayOrderedIDs: [Int64]) async throws {
        try coreLoop.moveVisit(id: visitID, toDayContaining: day, targetDayOrderedIDs: targetDayOrderedIDs)
    }

    func deleteVisit(visitID: Int64) async throws {
        try coreLoop.deleteVisit(id: visitID)
    }

    func setHidden(placeID: String, hidden: Bool) async throws {
        guard let placeRef = await actionPlaceRef(for: placeID) else { throw MapScreenActionError.placeUnavailable }
        let rollback = hiddenTracker.beginSetHidden(placeID: placeID, hidden: hidden)
        do {
            try coreLoop.setHidden(placeRef, hidden)
            logVerdictChanged(placeRef: placeRef, action: "hide", enabled: hidden)
        } catch {
            hiddenTracker.rollback(rollback)
            throw error
        }
    }

    private func logVerdictChanged(placeRef: PlaceRef, action: String, enabled: Bool) {
        MakingTracksLog.flowEvent("verdict changed", fields: placeFields(placeRef) + [
            .public("action", action),
            .public("state", enabled ? "on" : "off"),
        ])
    }

    private func placeFields(_ placeRef: PlaceRef) -> [DiagnosticLogField] {
        [
            .object("placeID", placeRef.placeID),
            .object("placeName", placeRef.name),
        ]
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
        guard let tileClient = tileClient(for: selectedRegionID) else { return nil }
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
            guard let client = tileClient(for: selectedRegionID),
                  let url = await client.basemapURL,
                  await client.basemapIntegrity != nil
            else { return nil }
            return "pmtiles://\(url.absoluteString)"
        }
    }

    var attribution: [Attribution] {
        get async {
            guard let client = tileClient(for: selectedRegionID) else {
                return [Attribution(source: "osm", license: "ODbL-1.0", text: "OSM credit")]
            }
            return await client.attribution
        }
    }

    var loadState: TileLoadState {
        get async {
            guard let client = tileClient(for: selectedRegionID) else { return .ok }
            return await client.loadState
        }
    }

    private func selectClient(for bbox: BBox, allowManifestRefresh: Bool = true) async -> TileClient? {
        let nextRegion = await selectedRegionID(for: bbox, current: selectedRegionID)
        let changed = nextRegion != selectedRegionID
        selectedRegionID = nextRegion
        guard let client = tileClient(for: nextRegion) else { return nil }
        if changed {
            MakingTracksLog.resolution.info("region selected region=\(nextRegion, privacy: .private(mask: .hash))")
            if allowManifestRefresh {
                try? await client.refreshPin()
            } else {
                await client.loadLocalPin()
            }
        }
        return client
    }

    private func selectedRegionID(for bbox: BBox, current: String) async -> String {
        let catalog = await mapSelectionCatalog()
        if let selected = catalog.selectedRootZoneID(for: bbox, current: current) {
            return selected
        }
        return MapRegion.select(for: bbox, current: MapRegion(rawValue: current)).rawValue
    }

    private func mapSelectionCatalog() async -> OfflineRegionCatalog {
        guard mapRegionCatalog.zones.isEmpty else { return mapRegionCatalog }
        let catalog = await loadMapSelectionCatalog()
        mapRegionCatalog = catalog
        return catalog
    }

    private func loadMapSelectionCatalog() async -> OfflineRegionCatalog {
#if DEBUG
        if forceTileNetworkOffline {
            return .empty
        }
#endif
        do {
            let catalog = try await OfflineRegionCatalog.current(
                fetcher: HTTPTileFetcher.offlineAvailabilityProbe(allowsCellularDownloads: false),
                cache: try? OfflineRegionCatalogCache.appCache()
            )
            MakingTracksLog.downloads.info("map regions index fetched regions=\(catalog.zones.count, privacy: .public)")
            return catalog
        } catch {
            MakingTracksLog.downloads.error("map regions index failed reason=\(MakingTracksLog.errorLabel(error), privacy: .public)")
            return .empty
        }
    }

    private func tileClient(for region: String) -> TileClient? {
        guard let tileCache,
              Self.isValidRegion(region)
        else { return nil }
        if let cached = tileClients[region] {
            return cached
        }
#if DEBUG
        let fetcher: TileFetching = forceTileNetworkOffline ? OfflineProofFetcher() : HTTPTileFetcher()
#else
        let fetcher: TileFetching = HTTPTileFetcher()
#endif
        let client = TileClient(
            region: region,
            fetcher: fetcher,
            cache: tileCache,
            offlineStore: offlineStore
        )
        tileClients[region] = client
        let viewportChanges = client.viewportChanges
        tileClientViewportTasks[region]?.cancel()
        tileClientViewportTasks[region] = Task { [weak self] in
            for await _ in viewportChanges {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.viewportChangeBroadcaster.yield(())
                }
            }
        }
        let regionID = region
        let hasOfflineStore = offlineStore != nil
        MakingTracksLog.startup.info("tile client created region=\(regionID, privacy: .private(mask: .hash)) offlineStore=\(hasOfflineStore, privacy: .public)")
        return client
    }

    private static func isValidRegion(_ value: String) -> Bool {
        value.range(of: "^[a-z][a-z0-9_-]{0,63}$", options: .regularExpression) == value.startIndex..<value.endIndex
    }
}

#if DEBUG
private struct OfflineProofFetcher: TileFetching {
    func fetch(_ url: URL) async throws -> Data {
        throw URLError(.notConnectedToInternet)
    }
}
#endif
