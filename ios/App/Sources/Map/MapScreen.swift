import CoreLocation
import Observation
import SwiftUI
import UIKit
@preconcurrency import MapLibre
import DesignSystem
import MakingTracksCore
import MakingTracksData
import MakingTracksMapStyle
import MakingTracksTiles

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
        self.zones = regionIndex.regions.compactMap { entry in
            guard let searchPublishVersion = Self.publishVersion(
                fromSearchCompactPath: entry.searchCompact.path,
                matchingEntryID: entry.id
            ) else {
                MakingTracksLog.file(
                    category: .downloads,
                    level: .error,
                    "region catalog entry dropped",
                    fields: [
                        .object("region", entry.id),
                        .public("reason", "invalid-search-compact-publish-version"),
                    ]
                )
                return nil
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

    private static func publishVersion(
        fromSearchCompactPath path: String,
        matchingEntryID entryID: String
    ) -> String? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 4,
              parts[0] == entryID,
              parts[2] == "search",
              parts[3] == "compact.json",
              Self.isPublishVersion(parts[1])
        else { return nil }
        return String(parts[1])
    }

    private static func isPublishVersion(_ value: Substring) -> Bool {
        let bytes = Array(value.utf8)
        return bytes.count == 16
            && bytes[0..<8].allSatisfy(Self.isASCIIDigit)
            && bytes[8] == 84 // T
            && bytes[9..<15].allSatisfy(Self.isASCIIDigit)
            && bytes[15] == 90 // Z
    }

    private static func isASCIIDigit(_ byte: UInt8) -> Bool {
        (48...57).contains(byte)
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
            knownZoneIDs: Set(catalogRows.map(\.zone.id)),
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

enum MapShellDestination: Hashable {
    case listDetail(Int64)
    case tracks
    case lovedPlaces
    case hiddenPlaces
    case offlineMaps
    case settings
    case diagnostics
    case about
}

enum MapDoor: Hashable, Identifiable {
    case explore
    case journal

    var id: Self { self }
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
    var presentedDoor: MapDoor?
    var deepLinkDestination: MapShellDestination?
    var tracksFocusPlaceID: String?
    var listDetailVisitFilter = TracksVisitFilter.all

    func openExploreDoor() {
        prepareDoorRoot(.explore)
    }

    func openJournalDoor() {
        prepareDoorRoot(.journal)
    }

    func openListDetailDeepLink(listID: Int64, visitFilter: TracksVisitFilter = .all) {
        tracksFocusPlaceID = nil
        listDetailVisitFilter = visitFilter
        deepLinkDestination = .listDetail(listID)
        presentedDoor = .journal
    }

    func prepareTracksHistory() {
        tracksFocusPlaceID = nil
        listDetailVisitFilter = .all
    }

    private func prepareDoorRoot(_ door: MapDoor) {
        tracksFocusPlaceID = nil
        listDetailVisitFilter = .all
        presentedDoor = door
        deepLinkDestination = nil
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
    static let chromeMinimumHeight: CGFloat = 50
    static let paperBackground = MapThemeColor.color(css: "#f1eddf")
    static let cardBackground = MapThemeColor.color(css: "#fffdf7")
    static let primaryText = MapThemeColor.color(css: "#1c1c1e")
    static let secondaryText = MapThemeColor.color(css: "#64635d")
    static let divider = MapThemeColor.color(css: "#ddd8ca")
    static let reorderHandle = MapThemeColor.color(css: "#aaa89d")
    static let accent = MapThemeColor.color(css: "#0a6b5c")
    static let accentSoft = MapThemeColor.color(css: "#e3f0eb")
    static let danger = MapThemeColor.color(css: "#b42318")
    static let dangerSoft = MapThemeColor.color(css: "#f8e7e4")
}

private struct TrackVisitRowBoundsPreferenceKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: [Int64: CGRect] = [:]

    static func reduce(
        value: inout [Int64: CGRect],
        nextValue: () -> [Int64: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct TrackVisitCardBoundsPreferenceKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: [Int64: CGRect] = [:]

    static func reduce(
        value: inout [Int64: CGRect],
        nextValue: () -> [Int64: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct TrackVisitViewportBoundsPreferenceKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue = CGRect.zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct TrackVisitAutoScrollRequest: Equatable {
    let sequence: Int
    let deltaY: CGFloat
}

@MainActor
private struct TrackVisitAutoScrollBridge: UIViewRepresentable {
    let request: TrackVisitAutoScrollRequest?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let request,
              context.coordinator.lastSequence != request.sequence,
              let window = uiView.window
        else { return }

        let probeFrame = uiView.convert(uiView.bounds, to: window)
        let candidates = collectionViews(in: window)
            .filter {
                $0.accessibilityIdentifier == "lists.detail.surface.track"
                    && isEffectivelyVisible($0, in: window)
            }
            .map {
                (
                    view: $0,
                    overlap: overlapArea($0, with: probeFrame, in: window)
                )
            }
            .filter { $0.overlap > 0 }
        guard let scrollView = candidates
            .max(by: { $0.overlap < $1.overlap })?
            .view
        else { return }
        context.coordinator.lastSequence = request.sequence

        let minimumY = -scrollView.adjustedContentInset.top
        let maximumY = max(
            minimumY,
            scrollView.contentSize.height
                - scrollView.bounds.height
                + scrollView.adjustedContentInset.bottom
        )
        let targetY = min(
            maximumY,
            max(minimumY, scrollView.contentOffset.y + request.deltaY)
        )
        scrollView.setContentOffset(
            CGPoint(x: scrollView.contentOffset.x, y: targetY),
            animated: false
        )
    }

    private func collectionViews(in view: UIView) -> [UICollectionView] {
        var matches = view.subviews.compactMap { $0 as? UICollectionView }
        for subview in view.subviews {
            matches.append(contentsOf: collectionViews(in: subview))
        }
        return matches
    }

    private func overlapArea(
        _ scrollView: UICollectionView,
        with probeFrame: CGRect,
        in window: UIWindow
    ) -> CGFloat {
        let scrollFrame = scrollView.convert(scrollView.bounds, to: window)
        let intersection = scrollFrame.intersection(probeFrame)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }

    private func isEffectivelyVisible(_ view: UIView, in window: UIWindow) -> Bool {
        var candidate: UIView? = view
        while let current = candidate {
            guard !current.isHidden, current.alpha > 0.01 else { return false }
            if current === window {
                return true
            }
            candidate = current.superview
        }
        return false
    }

    @MainActor
    final class Coordinator {
        var lastSequence: Int?
    }
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

enum TrackVisitDragTrigger {
    static let coordinateSpaceName = "track-visit-reorder"

    static func destinationOffset(
        for visitID: Int64,
        translationY: CGFloat,
        sourceMidY: CGFloat? = nil,
        orderedVisitIDs: [Int64],
        rowFrames: [Int64: CGRect]
    ) -> Int? {
        guard orderedVisitIDs.contains(visitID),
              let resolvedSourceMidY = sourceMidY ?? rowFrames[visitID]?.midY
        else { return nil }
        return destinationOffset(
            dropY: resolvedSourceMidY + translationY,
            orderedVisitIDs: orderedVisitIDs,
            rowFrames: rowFrames
        )
    }

    static func destinationOffset(
        for visitID: Int64,
        dropY: CGFloat,
        orderedVisitIDs: [Int64],
        rowFrames: [Int64: CGRect]
    ) -> Int? {
        guard orderedVisitIDs.contains(visitID), rowFrames[visitID] != nil else {
            return nil
        }
        return destinationOffset(
            dropY: dropY,
            orderedVisitIDs: orderedVisitIDs,
            rowFrames: rowFrames
        )
    }

    private static func destinationOffset(
        dropY: CGFloat,
        orderedVisitIDs: [Int64],
        rowFrames: [Int64: CGRect]
    ) -> Int? {
        let measuredRows = orderedVisitIDs.enumerated().compactMap { index, id in
            rowFrames[id].map { (index: index, frame: $0) }
        }
        guard let first = measuredRows.first, let last = measuredRows.last else {
            return nil
        }
        if dropY < first.frame.midY {
            return first.index
        }
        if let destination = measuredRows.first(where: { dropY < $0.frame.midY }) {
            return destination.index
        }
        return min(last.index + 1, orderedVisitIDs.count)
    }

    static func autoScrollTargetID(
        dropY: CGFloat,
        orderedVisitIDs: [Int64],
        rowFrames: [Int64: CGRect],
        viewportBounds: CGRect
    ) -> Int64? {
        guard !viewportBounds.isEmpty else { return nil }
        let visibleRows = orderedVisitIDs.enumerated().compactMap { index, id in
            rowFrames[id].flatMap { frame in
                frame.intersects(viewportBounds) ? (index: index, frame: frame) : nil
            }
        }
        guard let first = visibleRows.first, let last = visibleRows.last else {
            return nil
        }

        let edgeInset: CGFloat = 32
        if dropY <= viewportBounds.minY + edgeInset, first.index > 0 {
            return orderedVisitIDs[first.index - 1]
        }
        if dropY >= viewportBounds.maxY - edgeInset, last.index + 1 < orderedVisitIDs.count {
            return orderedVisitIDs[last.index + 1]
        }
        return nil
    }

    static func accessibilityDestinationOffset(
        sourceIndex: Int,
        movingTowardEnd: Bool,
        visitCount: Int
    ) -> Int? {
        guard sourceIndex >= 0, sourceIndex < visitCount else { return nil }
        if movingTowardEnd {
            guard sourceIndex + 1 < visitCount else { return nil }
            return sourceIndex + 2
        }
        guard sourceIndex > 0 else { return nil }
        return sourceIndex - 1
    }
}

enum TrackVisitDragVisualSpec {
    static func scale(isActive: Bool) -> CGFloat {
        isActive ? 1.015 : 1
    }

    static func overlayFrame(
        startFrame: CGRect,
        translationY: CGFloat
    ) -> CGRect {
        startFrame.offsetBy(dx: 0, dy: translationY - 3)
    }

    static func shadowOpacity(isActive: Bool) -> Double {
        isActive ? 0.22 : 0
    }

    static func shadowRadius(isActive: Bool) -> CGFloat {
        isActive ? 9 : 0
    }

    static func shadowY(isActive: Bool) -> CGFloat {
        isActive ? 5 : 0
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
        for category in (filter.categories ?? []).sorted() {
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
    var categories: Set<String>?

    init(filter: TracksVisitFilter = .all) {
        lovedOnly = filter.lovedOnly
        listIDs = filter.listIDs
        categories = filter.categories
    }

    var filter: TracksVisitFilter {
        TracksVisitFilter(lovedOnly: lovedOnly, listIDs: listIDs, categories: categories)
    }

    var includesAllCategories: Bool {
        categories == nil
    }

    mutating func selectAllCategories() {
        categories = nil
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
        var next = categories ?? []
        if next.contains(category) {
            next.remove(category)
            categories = next.isEmpty ? nil : next
        } else {
            next.insert(category)
            categories = next
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
        openJournalDoor()
    }

    func openTracksDeepLink(focusingPlaceID placeID: String? = nil) {
        tracksFocusPlaceID = placeID
        listDetailVisitFilter = .all
        deepLinkDestination = .tracks
        presentedDoor = .journal
    }

    func openOfflineMapsDeepLink() {
        tracksFocusPlaceID = nil
        listDetailVisitFilter = .all
        deepLinkDestination = .offlineMaps
        presentedDoor = .explore
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
    @State private var layerVisibility = MapLayerVisibility()
    @State private var appliedShowHiddenPlaces = false
    @State private var appliedShowSavedPlaces = true
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
            GeometryReader { proxy in
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
                        MapThemeColor.color(css: selectedTheme.background)
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
                        MapThemeColor.color(css: selectedTheme.background)
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
                .padding(.bottom, listModeControlBottomPadding)
            }
            .overlay(alignment: .bottom) {
                if let prompt = nearbyPromptCandidate {
                    MapNearbyPromptToast(
                        message: "You're near \(prompt.name) — seen it?",
                        onSeen: { handleNearbyPromptSeen(prompt) },
                        onDismiss: {
                            suppressedNearbyPromptPlaceIDs.insert(prompt.placeID)
                        }
                    )
                        .padding(.bottom, nearbyPromptBottomPadding)
                        .padding(.horizontal, MapOverlayChromeSpec.edgePadding)
                }
            }
            .overlay(alignment: .bottom) {
                if hiddenToast != nil {
                    MapHiddenUndoToast {
                        Task { await undoHiddenToast() }
                    }
                        .padding(.bottom, hiddenToastBottomPadding)
                        .padding(.horizontal, MapOverlayChromeSpec.edgePadding)
                }
            }
            .overlay(alignment: .bottom) {
                MapDoorBar(
                    openExplore: appShell.openExploreDoor,
                    openJournal: appShell.openJournalDoor
                )
                .padding(.horizontal, MapOverlayChromeSpec.edgePadding)
                .padding(
                    .bottom,
                    MapDoorChromeSpec.effectiveDoorBarBottomPadding(
                        containerHeight: proxy.size.height,
                        isPlaceCardPresented: cardPresentation.item != nil
                    )
                )
            }
            }
        }
        .sheet(
            item: $appShell.presentedDoor,
            onDismiss: {
                appShell.deepLinkDestination = nil
            }
        ) { door in
            MapDoorSheetIntegration(
                door: door,
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
                visibility: layersSheetVisibilityBinding,
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
        .onChange(of: appShell.presentedDoor) { _, presentedDoor in
            guard presentedDoor != nil else { return }
            cardPresentation.dismiss()
            Task { await refreshStorageMenuStatus() }
        }
        .onChange(of: layerVisibility) { _, visibility in
            showCoverageShading = visibility.showCoverageShading
            Task { @MainActor in
                await applyLayerVisibility(visibility)
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
        doorBarClearance + (
            activeListMap == nil
                ? MapOverlayChromeSpec.edgePadding
                : MapOverlayChromeSpec.listModeAuxiliaryBottomPadding
        )
    }

    private var hiddenToastBottomPadding: CGFloat {
        doorBarClearance + (
            activeListMap == nil
                ? MapOverlayChromeSpec.listModeControlBottomPadding
                : MapOverlayChromeSpec.listModeAuxiliaryBottomPadding
        )
    }

    private var doorBarClearance: CGFloat {
        MapDoorChromeSpec.doorBarClearance(
            isAccessibilitySize: dynamicTypeSize.isAccessibilitySize
        )
    }

    private var listModeControlBottomPadding: CGFloat {
        doorBarClearance + MapOverlayChromeSpec.listModeControlBottomPadding
    }

    private var nearbyPromptBottomPadding: CGFloat {
        doorBarClearance + 88
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
                listMapFilterChips(activeListMap)
            } else if let offlineDownloadProgress = currentOfflineDownloadProgress {
                MapDownloadProgressToast(
                    progress: offlineDownloadProgress,
                    onOpenOfflineMaps: appShell.openOfflineMapsDeepLink
                )
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
            .font(Typography.font(for: MapDoorChromeSpec.attributionTypographyRole))
            .foregroundStyle(MaterialTheme.snow.tokens.muted.swiftUIColor)
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

    private var layersSheetVisibility: MapLayerVisibility {
        ListMapLayerVisibility.displayed(
            discoveryVisibility: layerVisibility,
            visitFilter: activeListMap?.visitFilter
        )
    }

    private var layersSheetVisibilityBinding: Binding<MapLayerVisibility> {
        Binding(
            get: { layersSheetVisibility },
            set: { updateLayersSheetVisibility($0) }
        )
    }

    @MainActor
    private func updateLayersSheetVisibility(_ visibility: MapLayerVisibility) {
        guard var list = activeListMap else {
            layerVisibility = visibility
            return
        }

        layerVisibility = MapLayerVisibility(
            categories: layerVisibility.categories,
            showHiddenPlaces: visibility.showHiddenPlaces,
            showSavedPlaces: visibility.showSavedPlaces,
            showCoverageShading: visibility.showCoverageShading,
            visibleCategories: layerVisibility.visibleCategories
        )

        let nextFilter = ListMapLayerVisibility.updating(
            visitFilter: list.visitFilter,
            from: visibility
        )
        guard nextFilter != list.visitFilter else { return }
        list.visitFilter = nextFilter
        list.showVisited = true
        activeListMap = list
        stopMapTrackAutoplay()
        Task { @MainActor in
            await refreshActiveListMap(updateCamera: true)
        }
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
        MapLocationOffToast(onOpenSettings: openLocationSettings)
    }

    private var locateMeButton: some View {
        Button {
            handleLocateMeTap()
        } label: {
            Image(systemName: locateMeButtonSystemName)
                .font(.title3)
                .frame(
                    width: MapDoorChromeSpec.locateMinimumHitTarget,
                    height: MapDoorChromeSpec.locateMinimumHitTarget
                )
                .background(
                    MaterialTheme.snow.tokens.surface.swiftUIColor,
                    in: Circle()
                )
                .overlay {
                    Circle()
                        .stroke(
                            MaterialTheme.snow.tokens.hairline.swiftUIColor,
                            lineWidth: 1
                        )
                }
                .shadow(
                    color: MaterialTheme.snow.tokens.shadow.swiftUIColor,
                    radius: 8,
                    x: 0,
                    y: 3
                )
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

    private func start() async {
        let startedAt = Date()
        let fixture = isFixtureMap
        MakingTracksLog.startup.info("map start started fixture=\(fixture, privacy: .public)")
        ensureModel()
        model?.setShowHidden(layerVisibility.showHiddenPlaces)
        model?.setShowSaved(layerVisibility.showSavedPlaces)
        appliedShowHiddenPlaces = layerVisibility.showHiddenPlaces
        appliedShowSavedPlaces = layerVisibility.showSavedPlaces
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
        guard visibility.requiresDiscoveryFeatureRefresh(
            appliedShowHiddenPlaces: appliedShowHiddenPlaces,
            appliedShowSavedPlaces: appliedShowSavedPlaces
        ) else { return }
        guard let model else { return }
        model.setShowHidden(visibility.showHiddenPlaces)
        model.setShowSaved(visibility.showSavedPlaces)
        appliedShowHiddenPlaces = visibility.showHiddenPlaces
        appliedShowSavedPlaces = visibility.showSavedPlaces
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

private struct MapDoorSheetIntegration: View {
    let door: MapDoor
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
    let visibility: Binding<MapLayerVisibility>
    let replayOnboarding: @MainActor () -> Void
    let onOfflineMapsChanged: @MainActor () async -> Void
    let onShowListOnMap: @MainActor (PlaceList, TracksVisitFilter) -> Void
    let onListRenamed: @MainActor (PlaceList) -> Void
    let onListDeleted: @MainActor (Int64) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        MapDoorSheet(
            door: door,
            deepLinkDestination: shell.deepLinkDestination,
            model: model,
            visibility: visibility,
            prepareTracksHistory: shell.prepareTracksHistory,
            onListDeleted: onListDeleted
        ) { destination in
            destinationView(destination)
        }
    }

    @ViewBuilder
    private func destinationView(_ destination: MapShellDestination) -> some View {
        switch destination {
        case let .listDetail(listID):
            ListDetailDeepLinkView(
                model: model,
                listID: listID,
                visitFilter: shell.listDetailVisitFilter,
                onShowOnMap: showListOnMapAndDismiss,
                onListRenamed: onListRenamed,
                onDone: { dismiss() }
            )
        case .tracks:
            TrackListDetailDeepLinkView(
                model: model,
                focusPlaceID: shell.tracksFocusPlaceID,
                onShowOnMap: showListOnMapAndDismiss,
                onListRenamed: onListRenamed,
                onDone: { dismiss() }
            )
        case .lovedPlaces:
            ManagedPlacesView(model: model, mode: .loved)
        case .hiddenPlaces:
            ManagedPlacesView(model: model, mode: .hidden)
        case .offlineMaps:
#if DEBUG
            OfflineMapsView(
                model: model,
                seededProgress: seededOfflineDownloadProgress,
                downloadSession: offlineDownloadSession,
                storageStatus: storageStatus,
                onOfflineMapsChanged: onOfflineMapsChanged
            )
#else
            OfflineMapsReleaseGatedView()
#endif
        case .settings:
            SettingsView(
                selectedThemeID: $selectedThemeID,
                pinSizeMultiplier: $pinSizeMultiplier,
                locationStatus: locationStatus,
                storageStatus: storageStatus,
                openLocationSettings: openLocationSettings,
                replayOnboarding: replayOnboardingAndDismiss
            )
        case .diagnostics:
            DiagnosticsView(storageStatus: storageStatus)
        case .about:
            AboutView(attribution: attribution)
        }
    }

    private func replayOnboardingAndDismiss() {
        dismiss()
        replayOnboarding()
    }

    private func showListOnMapAndDismiss(_ list: PlaceList, filter: TracksVisitFilter = .all) {
        shell.presentedDoor = nil
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
    let onDone: @MainActor () -> Void

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
                    onListRenamed: onListRenamed,
                    onDone: onDone
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
    let onDone: @MainActor () -> Void

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
                    onListRenamed: onListRenamed,
                    onDone: onDone
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

private struct ListDetailView: View {
    let model: MapScreenModel?
    let list: PlaceList
    let visitFilter: TracksVisitFilter
    let focusPlaceID: String?
    let onChanged: @MainActor () -> Void
    let onShowOnMap: @MainActor (PlaceList, TracksVisitFilter) -> Void
    let onListRenamed: @MainActor (PlaceList) -> Void
    let onDone: @MainActor () -> Void

    @State private var items: [ListPlace] = []
    @State private var trackVisits: [TrackVisit] = []
    @State private var progress = ListProgress(visited: 0, total: 0)
    @State private var currentList: PlaceList
    @State private var renameDraft: String
    @State private var actionError: String?
    @State private var selectedVisitForEditing: TrackVisit?
    @State private var trackVisitRowFrames: [Int64: CGRect] = [:]
    @State private var trackVisitCardFrames: [Int64: CGRect] = [:]
    @State private var trackVisitViewportBounds = CGRect.zero
    @State private var draggingTrackVisitID: Int64?
    @State private var trackVisitDragStartMidY: CGFloat?
    @State private var trackVisitDragStartCardFrame: CGRect?
    @GestureState private var trackVisitDragTranslationY: CGFloat = 0
    @GestureState private var trackVisitGestureIsActive = false
    @State private var trackAutoScrollTask: Task<Void, Never>?
    @State private var trackAutoScrollGeneration = 0
    @State private var trackAutoScrollRequest: TrackVisitAutoScrollRequest?
    @State private var trackAutoScrollRequestSequence = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss

    init(
        model: MapScreenModel?,
        list: PlaceList,
        visitFilter: TracksVisitFilter = .all,
        focusPlaceID: String? = nil,
        onChanged: @escaping @MainActor () -> Void,
        onShowOnMap: @escaping @MainActor (PlaceList, TracksVisitFilter) -> Void,
        onListRenamed: @escaping @MainActor (PlaceList) -> Void,
        onDone: @escaping @MainActor () -> Void
    ) {
        self.model = model
        self.list = list
        self.visitFilter = visitFilter
        self.focusPlaceID = focusPlaceID
        self.onChanged = onChanged
        self.onShowOnMap = onShowOnMap
        self.onListRenamed = onListRenamed
        self.onDone = onDone
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

    @ViewBuilder
    private var trackVisitEditorPage: some View {
        if let visit = selectedVisitForEditing {
            TrackVisitDateEditorView(
                model: model,
                visit: visit,
                onChanged: {
                    await reload()
                    onChanged()
                },
                onDismiss: {
                    selectedVisitForEditing = nil
                }
            )
        }
    }

    private var calendar: Calendar {
        Calendar(identifier: .gregorian)
    }

    var body: some View {
        if isTrackListDetail {
            ZStack(alignment: .top) {
                trackListPage
                trackVisitEditorPage
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(TrackVisitEditorVisualSpec.paperBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        } else {
            collectionListBody
        }
    }

    private var trackListPage: some View {
        VStack(spacing: 0) {
            trackListChrome
            trackListBody
        }
        .accessibilityHidden(selectedVisitForEditing != nil)
        .allowsHitTesting(selectedVisitForEditing == nil)
    }

    private var trackListChrome: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                trackListBackButton

                if dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: 12)
                } else {
                    trackListTitle
                        .frame(maxWidth: .infinity)
                }

                trackListDoneButton
            }

            if dynamicTypeSize.isAccessibilitySize {
                trackListTitle
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: TrackVisitEditorVisualSpec.chromeMinimumHeight)
        .background(TrackVisitEditorVisualSpec.paperBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(TrackVisitEditorVisualSpec.divider)
                .frame(height: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lists.detail.track.chrome")
    }

    private var trackListBackButton: some View {
        Button {
            dismiss()
        } label: {
            Text("‹ Back")
                .font(.body.weight(.semibold))
                .foregroundStyle(TrackVisitEditorVisualSpec.accent)
                .frame(minWidth: 88, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("lists.detail.track.back")
    }

    private var trackListDoneButton: some View {
        Button {
            onDone()
        } label: {
            Text("Done")
                .font(.body.weight(.semibold))
                .foregroundStyle(TrackVisitEditorVisualSpec.accent)
                .frame(minWidth: 88, minHeight: 44, alignment: .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("lists.detail.track.done")
    }

    private var trackListTitle: some View {
        Text(verbatim: currentList.name)
            .font(.headline)
            .foregroundStyle(TrackVisitEditorVisualSpec.primaryText)
            .multilineTextAlignment(.center)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            .accessibilityIdentifier("lists.detail.track.title")
    }

    private var trackListBody: some View {
        ScrollViewReader { _ in
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
                                .id(row.visit.id)
                                .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(TrackVisitEditorVisualSpec.paperBackground)
            .foregroundStyle(TrackVisitEditorVisualSpec.primaryText)
            .background {
                TrackVisitAutoScrollBridge(request: trackAutoScrollRequest)
            }
            .overlay {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: TrackVisitViewportBoundsPreferenceKey.self,
                        value: geometry.frame(
                            in: .named(TrackVisitDragTrigger.coordinateSpaceName)
                        )
                    )
                }
                .allowsHitTesting(false)
            }
            .onPreferenceChange(TrackVisitRowBoundsPreferenceKey.self) { frames in
                trackVisitRowFrames = frames
            }
            .onPreferenceChange(TrackVisitCardBoundsPreferenceKey.self) { frames in
                trackVisitCardFrames = frames
            }
            .onPreferenceChange(TrackVisitViewportBoundsPreferenceKey.self) { bounds in
                trackVisitViewportBounds = bounds
            }
            .onChange(of: trackVisitGestureIsActive) { wasActive, isActive in
                if wasActive, !isActive, draggingTrackVisitID != nil {
                    resetTrackVisitDragState()
                }
            }
            .onDisappear { resetTrackVisitDragState() }
            .accessibilityIdentifier("lists.detail.surface.track")
            .task { await reload() }
            .refreshable { await reload() }
        }
        .coordinateSpace(name: TrackVisitDragTrigger.coordinateSpaceName)
        .overlay(alignment: .topLeading) {
            trackVisitReorderGestureSurfaces
        }
        .overlay(alignment: .topLeading) {
            GeometryReader { geometry in
                trackVisitDragOverlay(
                    overlayOrigin: geometry.frame(
                        in: .named(TrackVisitDragTrigger.coordinateSpaceName)
                    ).origin
                )
            }
        }
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
                .foregroundStyle(TrackVisitEditorVisualSpec.primaryText)

                Text(verbatim: TracksCopy.summary(
                    visible: visibleTrackVisits.count,
                    lovedOnly: false
                ))
                .font(.title2.weight(.bold))
                .foregroundStyle(TrackVisitEditorVisualSpec.primaryText)
                .accessibilityIdentifier("lists.detail.track.summary")

                Text("Your track is a sequence of visits you entered. Edit a row when the remembered day or order needs correcting.")
                    .font(.subheadline)
                    .foregroundStyle(TrackVisitEditorVisualSpec.secondaryText)

                HStack(spacing: 8) {
                    Button {
                        onShowOnMap(currentList, .all)
                    } label: {
                        Label("Map", systemImage: "map")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(
                                TrackVisitEditorVisualSpec.accent,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("lists.detail.show-map")

                    Button {
                        Task { await reload() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(TrackVisitEditorVisualSpec.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(
                                TrackVisitEditorVisualSpec.paperBackground,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(TrackVisitEditorVisualSpec.divider, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Refresh tracks")
                    .accessibilityIdentifier("lists.detail.track.refresh")
                }
            } else {
                Label("Multiple visits to this place", systemImage: "mappin.and.ellipse")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TrackVisitEditorVisualSpec.primaryText)
                    .accessibilityIdentifier("lists.detail.track.focus-message")

                Text("Choose the visit")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(TrackVisitEditorVisualSpec.primaryText)
                    .accessibilityIdentifier("lists.detail.track.summary")

                Text("Delete only the row you mean to remove.")
                    .font(.subheadline)
                    .foregroundStyle(TrackVisitEditorVisualSpec.secondaryText)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TrackVisitEditorVisualSpec.cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(TrackVisitEditorVisualSpec.divider, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lists.detail.track.summary-card")
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
                Text(verbatim: formattedTrackDay(dayHeader))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TrackVisitEditorVisualSpec.secondaryText)
                    .padding(.horizontal, 8)
                    .accessibilityIdentifier("lists.detail.track.day-header.\(visit.id)")
            }

            trackVisitCard(visit)
                .opacity(draggingTrackVisitID == visit.id ? 0 : 1)
                .accessibilityHidden(draggingTrackVisitID == visit.id)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: TrackVisitCardBoundsPreferenceKey.self,
                            value: [
                                visit.id: geometry.frame(
                                    in: .named(TrackVisitDragTrigger.coordinateSpaceName)
                                ),
                            ]
                        )
                    }
                }
                .animation(.easeOut(duration: 0.12), value: draggingTrackVisitID == visit.id)
        }
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: TrackVisitRowBoundsPreferenceKey.self,
                    value: [
                        visit.id: geometry.frame(
                            in: .named(TrackVisitDragTrigger.coordinateSpaceName)
                        ),
                    ]
                )
            }
        }
    }

    private func trackVisitCard(_ visit: TrackVisit) -> some View {
        HStack(alignment: .center, spacing: TrackVisitRowDensitySpec.horizontalSpacing) {
            Text("pin")
                .font(.caption2.weight(.bold))
                .foregroundStyle(TrackVisitEditorVisualSpec.accent)
                .frame(width: 30, height: 30)
                .background(
                    TrackVisitEditorVisualSpec.accentSoft,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: visit.name)
                    .font(.body)
                    .foregroundStyle(TrackVisitEditorVisualSpec.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .accessibilityIdentifier("lists.detail.track.row.name.\(visit.id)")
                Text(verbatim: "\(categoryLabel(visit.category)) · \(formattedVisitTime(visit))")
                    .font(.caption)
                    .foregroundStyle(TrackVisitEditorVisualSpec.secondaryText)
                    .lineLimit(2)
                    .accessibilityIdentifier("lists.detail.track.row.metadata.\(visit.id)")
            }
            .layoutPriority(1)

            Spacer(minLength: 4)

            Button {
                Task { await setLoved(visit) }
            } label: {
                Image(systemName: visit.verdict == .loved ? "heart.fill" : "heart")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(TrackVisitEditorVisualSpec.danger)
                    .frame(width: 30, height: 30)
                    .background(
                        TrackVisitEditorVisualSpec.cardBackground,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(TrackVisitEditorVisualSpec.danger, lineWidth: 1)
                    }
                    .frame(minWidth: 45, minHeight: 45)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(lovedButtonAccessibilityLabel(for: visit))
            .accessibilityIdentifier("lists.detail.track.row.loved.\(visit.id)")

            if canReorderTrackVisits {
                invariantReorderHandle(for: visit)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(
            TrackVisitEditorVisualSpec.cardBackground,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(TrackVisitEditorVisualSpec.divider, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lists.detail.track.row.card.\(visit.id)")
        .accessibilityAction(named: "Edit visit") {
            presentVisitEditor(visit)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            presentVisitEditor(visit)
        }
    }

    private var trackVisitReorderGestureSurfaceFrames: [Int64: CGRect] {
        var frames = trackVisitCardFrames
        if let draggingTrackVisitID, let trackVisitDragStartCardFrame {
            frames[draggingTrackVisitID] = trackVisitDragStartCardFrame
        }
        return frames
    }

    @ViewBuilder
    private var trackVisitReorderGestureSurfaces: some View {
        if canReorderTrackVisits {
            GeometryReader { geometry in
                let overlayOrigin = geometry.frame(
                    in: .named(TrackVisitDragTrigger.coordinateSpaceName)
                ).origin
                ZStack(alignment: .topLeading) {
                    ForEach(
                        trackVisitReorderGestureSurfaceFrames.keys.sorted(),
                        id: \.self
                    ) { visitID in
                        if let frame = trackVisitReorderGestureSurfaceFrames[visitID] {
                            Rectangle()
                                .fill(Color.black.opacity(0.001))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                                .position(
                                    x: frame.maxX - 33 - overlayOrigin.x,
                                    y: frame.midY - overlayOrigin.y
                                )
                                .simultaneousGesture(trackVisitReorderGesture(for: visitID))
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func trackVisitDragOverlay(overlayOrigin: CGPoint) -> some View {
        if let draggingTrackVisitID,
           let startFrame = trackVisitDragStartCardFrame,
           let visit = visibleTrackVisits.first(where: { $0.id == draggingTrackVisitID })
        {
            let frame = TrackVisitDragVisualSpec.overlayFrame(
                startFrame: startFrame,
                translationY: trackVisitDragTranslationY
            )
            trackVisitCard(visit)
                .frame(width: frame.width, height: frame.height)
                .scaleEffect(TrackVisitDragVisualSpec.scale(isActive: true))
                .shadow(
                    color: Color.black.opacity(
                        TrackVisitDragVisualSpec.shadowOpacity(isActive: true)
                    ),
                    radius: TrackVisitDragVisualSpec.shadowRadius(isActive: true),
                    y: TrackVisitDragVisualSpec.shadowY(isActive: true)
                )
                .position(
                    x: frame.midX - overlayOrigin.x,
                    y: frame.midY - overlayOrigin.y
                )
                .allowsHitTesting(false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Dragging \(visit.name)")
                .accessibilityIdentifier("lists.detail.track.row.drag-overlay.\(visit.id)")
        }
    }

    private func presentVisitEditor(_ visit: TrackVisit) {
        selectedVisitForEditing = visit
    }

    private func invariantReorderHandle(for visit: TrackVisit) -> some View {
        ZStack {
            Rectangle()
                .fill(TrackVisitEditorVisualSpec.cardBackground)
            VStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in
                    Capsule()
                        .fill(TrackVisitEditorVisualSpec.reorderHandle)
                        .frame(width: 22, height: 2)
                }
            }
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reorder \(visit.name)")
        .accessibilityHint("Drag, or swipe up or down, to change this visit's order")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                moveTrackVisitByAccessibility(visit, movingTowardEnd: true)
            case .decrement:
                moveTrackVisitByAccessibility(visit, movingTowardEnd: false)
            @unknown default:
                break
            }
        }
        .accessibilityIdentifier("lists.detail.track.row.reorder.\(visit.id)")
    }

    private func trackVisitReorderGesture(for visitID: Int64) -> some Gesture {
        DragGesture(
            minimumDistance: 0,
            coordinateSpace: .named(TrackVisitDragTrigger.coordinateSpaceName)
        )
        .updating($trackVisitDragTranslationY) { value, translationY, _ in
            translationY = value.translation.height
        }
        .updating($trackVisitGestureIsActive) { _, isActive, _ in
            isActive = true
        }
        .onChanged { value in
            guard canReorderTrackVisits else { return }
            if draggingTrackVisitID == nil {
                guard let sourceFrame = trackVisitRowFrames[visitID],
                    let sourceCardFrame = trackVisitCardFrames[visitID]
                else { return }
                draggingTrackVisitID = visitID
                trackVisitDragStartMidY = sourceFrame.midY
                trackVisitDragStartCardFrame = sourceCardFrame
            }
            guard draggingTrackVisitID == visitID,
                  let sourceMidY = trackVisitDragStartMidY
            else { return }
            updateTrackVisitAutoScroll(
                dropY: sourceMidY + value.translation.height
            )
        }
        .onEnded { value in
            defer {
                resetTrackVisitDragState()
            }
            guard canReorderTrackVisits,
                  draggingTrackVisitID == visitID,
                  let sourceMidY = trackVisitDragStartMidY,
                  let source = visibleTrackVisits.firstIndex(where: { $0.id == visitID }),
                  let destination = TrackVisitDragTrigger.destinationOffset(
                    for: visitID,
                    translationY: value.translation.height,
                    sourceMidY: sourceMidY,
                    orderedVisitIDs: visibleTrackVisits.map(\.id),
                    rowFrames: trackVisitRowFrames
                  )
            else { return }

            let visits = visibleTrackVisits
            Task {
                await moveTrackVisits(
                    visits,
                    fromOffsets: IndexSet(integer: source),
                    toOffset: destination
                )
            }
        }
    }

    @MainActor
    private func resetTrackVisitDragState() {
        draggingTrackVisitID = nil
        trackVisitDragStartMidY = nil
        trackVisitDragStartCardFrame = nil
        stopTrackVisitAutoScroll()
    }

    @MainActor
    private func updateTrackVisitAutoScroll(dropY: CGFloat) {
        let targetID = TrackVisitDragTrigger.autoScrollTargetID(
            dropY: dropY,
            orderedVisitIDs: visibleTrackVisits.map(\.id),
            rowFrames: trackVisitRowFrames,
            viewportBounds: trackVisitViewportBounds
        )
        guard targetID != nil
        else {
            stopTrackVisitAutoScroll()
            return
        }
        guard trackAutoScrollTask == nil else { return }

        trackAutoScrollGeneration &+= 1
        let generation = trackAutoScrollGeneration
        trackAutoScrollTask = Task { @MainActor in
            defer {
                if trackAutoScrollGeneration == generation {
                    trackAutoScrollTask = nil
                }
            }
            while !Task.isCancelled {
                guard TrackVisitDragTrigger.autoScrollTargetID(
                    dropY: dropY,
                    orderedVisitIDs: visibleTrackVisits.map(\.id),
                    rowFrames: trackVisitRowFrames,
                    viewportBounds: trackVisitViewportBounds
                ) != nil else {
                    return
                }
                trackAutoScrollRequestSequence &+= 1
                trackAutoScrollRequest = TrackVisitAutoScrollRequest(
                    sequence: trackAutoScrollRequestSequence,
                    deltaY: dropY >= trackVisitViewportBounds.midY ? 56 : -56
                )
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    @MainActor
    private func stopTrackVisitAutoScroll() {
        trackAutoScrollGeneration &+= 1
        trackAutoScrollTask?.cancel()
        trackAutoScrollTask = nil
    }

    @MainActor
    private func moveTrackVisitByAccessibility(
        _ visit: TrackVisit,
        movingTowardEnd: Bool
    ) {
        let visits = visibleTrackVisits
        guard canReorderTrackVisits,
              let source = visits.firstIndex(where: { $0.id == visit.id }),
              let destination = TrackVisitDragTrigger.accessibilityDestinationOffset(
                sourceIndex: source,
                movingTowardEnd: movingTowardEnd,
                visitCount: visits.count
              )
        else { return }

        Task {
            await moveTrackVisits(
                visits,
                fromOffsets: IndexSet(integer: source),
                toOffset: destination
            )
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

    private func formattedVisitTime(_ visit: TrackVisit) -> String {
        visit.visitedAt.formatted(date: .omitted, time: .shortened)
    }

    private func formattedDay(_ day: Date) -> String {
        day.formatted(date: .abbreviated, time: .omitted)
    }

    private func formattedTrackDay(_ day: Date) -> String {
        day.formatted(.dateTime.day(.twoDigits).month(.abbreviated).year(.defaultDigits)).uppercased()
    }

    private func lovedButtonAccessibilityLabel(for visit: TrackVisit) -> String {
        let action = visit.verdict == .loved ? "Remove loved from" : "Mark loved for"
        return "\(action) \(visit.name), \(formattedVisitedAt(visit))"
    }
}

private struct TrackVisitDateEditorView: View {
    let model: MapScreenModel?
    let onChanged: @MainActor () async -> Void
    let onDismiss: @MainActor () -> Void

    @State private var visit: TrackVisit
    @State private var selectedDate: Date
    @State private var actionError: String?

    init(
        model: MapScreenModel?,
        visit: TrackVisit,
        onChanged: @escaping @MainActor () async -> Void,
        onDismiss: @escaping @MainActor () -> Void
    ) {
        self.model = model
        self.onChanged = onChanged
        self.onDismiss = onDismiss
        _visit = State(initialValue: visit)
        _selectedDate = State(initialValue: visit.visitedAt)
    }

    var body: some View {
        VStack(spacing: 0) {
            navigationChrome

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 6) {
                            Image(systemName: "mappin")
                                .foregroundStyle(TrackVisitEditorVisualSpec.accent)
                                .accessibilityLabel("Pinned visit")
                                .accessibilityIdentifier("lists.detail.visit-date.summary-pin")
                            Text(verbatim: visit.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(TrackVisitEditorVisualSpec.primaryText)
                        }
                        Text("Correct the day")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(TrackVisitEditorVisualSpec.primaryText)
                        Text("Choose the day this visit belongs to. Making Tracks keeps the visit as your own entry, not as a GPS trace.")
                            .font(.subheadline)
                            .foregroundStyle(TrackVisitEditorVisualSpec.secondaryText)
                    }
                    .padding(13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(TrackVisitEditorVisualSpec.cardBackground, in: RoundedRectangle(cornerRadius: 10))

                    Text("SELECTED VISIT")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(TrackVisitEditorVisualSpec.secondaryText)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .center, spacing: 10) {
                            Image(systemName: "mappin")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(TrackVisitEditorVisualSpec.accent)
                                .frame(width: 30, height: 30)
                                .background(
                                    TrackVisitEditorVisualSpec.accentSoft,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )
                                .accessibilityLabel("Pinned visit")
                                .accessibilityIdentifier("lists.detail.visit-date.selected-pin")
                            Text(verbatim: visit.name)
                                .font(.body)
                                .foregroundStyle(TrackVisitEditorVisualSpec.primaryText)
                                .lineLimit(2)
                            Spacer()
                            Image(systemName: visit.verdict == .loved ? "heart.fill" : "heart")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(TrackVisitEditorVisualSpec.danger)
                                .frame(width: 30, height: 30)
                                .accessibilityLabel(visit.verdict == .loved ? "Loved" : "Not loved")
                                .accessibilityIdentifier("lists.detail.visit-date.heart")
                        }
                        HStack(spacing: 8) {
                            ZStack(alignment: .leading) {
                                DatePicker(
                                    "Visit date",
                                    selection: Binding(
                                        get: { selectedDate },
                                        set: { date in
                                            selectedDate = date
                                        }
                                    ),
                                    displayedComponents: .date
                                )
                                .datePickerStyle(.compact)
                                .labelsHidden()
                                .accessibilityIdentifier("lists.detail.visit-date.picker")
                                HStack(spacing: 6) {
                                    Text(selectedDate.formatted(date: .abbreviated, time: .omitted))
                                        .font(.callout.weight(.medium))
                                        .foregroundStyle(TrackVisitEditorVisualSpec.primaryText)
                                    Image(systemName: "calendar")
                                        .foregroundStyle(TrackVisitEditorVisualSpec.accent)
                                }
                                .padding(9)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .background(TrackVisitEditorVisualSpec.cardBackground)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(TrackVisitEditorVisualSpec.cardBackground, in: RoundedRectangle(cornerRadius: 8))
                            Button("Delete", role: .destructive) {
                                Task { await deleteVisit() }
                            }
                            .font(.caption.weight(.bold))
                            .foregroundStyle(TrackVisitEditorVisualSpec.danger)
                            .frame(minWidth: 45, minHeight: 45)
                            .background(TrackVisitEditorVisualSpec.dangerSoft, in: RoundedRectangle(cornerRadius: 8))
                            .accessibilityIdentifier("lists.detail.visit-date.delete")
                            .accessibilityLabel("Delete visit \(visit.name)")
                        }
                    }
                    .padding(13)
                    .background(TrackVisitEditorVisualSpec.cardBackground, in: RoundedRectangle(cornerRadius: 10))

                    if let actionError {
                        Text(actionError).font(.caption).foregroundStyle(TrackVisitEditorVisualSpec.danger)
                    }
                    HStack {
                        Button("Cancel") { onDismiss() }
                            .foregroundStyle(TrackVisitEditorVisualSpec.accent)
                            .frame(minWidth: 100, minHeight: 44)
                        Spacer()
                        Button("Save day") { Task { await saveDate() } }
                            .font(.body.weight(.semibold))
                            .foregroundStyle(TrackVisitEditorVisualSpec.accent)
                            .frame(minWidth: 100, minHeight: 44)
                            .accessibilityIdentifier("lists.detail.visit-date.save")
                    }
                }
                .padding(16)
            }
        }
        .background(TrackVisitEditorVisualSpec.paperBackground.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lists.detail.visit-date.surface")
    }

    private var navigationChrome: some View {
        HStack {
            Button("‹ My tracks") { onDismiss() }
                .font(.body.weight(.semibold))
                .foregroundStyle(TrackVisitEditorVisualSpec.accent)
                .frame(minWidth: 88, minHeight: 44, alignment: .leading)
                .accessibilityIdentifier("lists.detail.visit-date.back")
            Spacer()
            Text("Visit date")
                .font(.headline)
                .foregroundStyle(TrackVisitEditorVisualSpec.primaryText)
                .accessibilityIdentifier("lists.detail.visit-date.title")
            Spacer()
            Text("‹ My tracks")
                .font(.body.weight(.semibold))
                .frame(minWidth: 88, minHeight: 44, alignment: .trailing)
                .hidden()
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: TrackVisitEditorVisualSpec.chromeMinimumHeight)
        .background(TrackVisitEditorVisualSpec.paperBackground)
        .overlay(alignment: .bottom) {
            Rectangle().fill(TrackVisitEditorVisualSpec.divider).frame(height: 1)
        }
    }

    @MainActor
    private func saveDate() async {
        guard let model else { return }
        do {
            try await model.updateVisitDate(visitID: visit.id, toDayContaining: selectedDate)
            actionError = nil
            await onChanged()
            onDismiss()
        } catch {
            actionError = "Could not update that visit."
        }
    }

    @MainActor
    private func deleteVisit() async {
        guard let model else { return }
        do {
            try await model.deleteVisit(visitID: visit.id)
            await onChanged()
            onDismiss()
        } catch {
            actionError = "Could not delete that visit."
        }
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
                NavigationLink(value: SettingsStorageNavigation.destination) {
                    SettingsStorageSummary(storageStatus: storageStatus)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.storage.manage")
            }

            Section("Diagnostics") {
                NavigationLink(value: MapShellDestination.diagnostics) {
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                VStack(alignment: .leading, spacing: 10) {
                    Text("Send a diagnostic log")
                        .font(.title3.weight(.bold))

                    Text("Nothing is sent automatically. The app prepares a file on this phone; when you share, you pick who gets it.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    diagnosticsWindowPicker

                    diagnosticsWindowStatus
                }
                .padding(.vertical, 4)
            }

            if artifact == nil {
                Section("Included") {
                    diagnosticsClassGrid(Self.includedDisclosureClasses, isIncluded: true)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("settings.diagnostics.included")

                Section("Excluded") {
                    diagnosticsClassGrid(Self.excludedDisclosureClasses, isIncluded: false)
                    diagnosticsBullet("Your device name, exact location, and searches are not included in the export.")
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("settings.diagnostics.excluded")
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

            if artifact != nil {
                Section("Before sharing") {
                    diagnosticsBullet("Your device name, exact location, and searches are not included in the export.")
                    diagnosticsBullet("You choose the person or app that gets the file.")
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
                Button {
                    selectedWindow = .fifteenMinutes
                    beginPreparation()
                } label: {
                    Text("Try 15 min")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(DiagnosticsVisualSpec.accent)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("settings.diagnostics.retry-shorter")

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Text("Delete logs")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("settings.diagnostics.delete")
            } else if let artifact {
                Button {
                    cleanupPreparedArtifact()
                } label: {
                    Text("Cancel")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("settings.diagnostics.cancel")

                Button {
                    shareItem = DiagnosticsShareItem(url: artifact.archiveURL)
                } label: {
                    Text("Share")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(DiagnosticsVisualSpec.accent)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("settings.diagnostics.share")
            } else {
                Button {
                    beginPreparation()
                } label: {
                    Text(isPreparing ? "Preparing" : "Prepare file")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(DiagnosticsVisualSpec.accent)
                .disabled(isPreparing)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("settings.diagnostics.prepare")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    @ViewBuilder
    private var diagnosticsWindowPicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 4) {
                ForEach(DiagnosticLogWindow.settingsOptions, id: \.self) { window in
                    Button {
                        selectedWindow = window
                    } label: {
                        HStack {
                            Text(window.label)
                                .fontWeight(.semibold)
                            Spacer()
                            Image(systemName: selectedWindow == window ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(
                                    selectedWindow == window ? DiagnosticsVisualSpec.accent : .secondary
                                )
                        }
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(
                                    selectedWindow == window
                                        ? DiagnosticsVisualSpec.accent.opacity(0.12)
                                        : Color.secondary.opacity(0.06)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isPreparing || artifact != nil)
                    .accessibilityValue(selectedWindow == window ? "Selected" : "")
                    .accessibilityIdentifier("settings.diagnostics.window.\(window.accessibilityID)")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("settings.diagnostics.window")
        } else {
            Picker("Time range", selection: $selectedWindow) {
                ForEach(DiagnosticLogWindow.settingsOptions, id: \.self) { window in
                    Text(window.label).tag(window)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isPreparing || artifact != nil)
            .accessibilityIdentifier("settings.diagnostics.window")
        }
    }

    private var diagnosticsWindowStatus: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("Showing \(selectedWindow.statusLabel)")
                    .font(.callout.weight(.semibold))
                Text("Archive size is shown after Prepare.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "arrow.up.doc")
                .foregroundStyle(DiagnosticsVisualSpec.accent)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings.diagnostics.window-status")
    }

    private func diagnosticsBullet(_ text: String) -> some View {
        Label(text, systemImage: "circle.fill")
            .symbolRenderingMode(.palette)
            .foregroundStyle(.primary, DiagnosticsVisualSpec.accent)
    }

    private func diagnosticsClassGrid(_ classes: [DiagnosticsDisclosureClass], isIncluded: Bool) -> some View {
        let columns = dynamicTypeSize.isAccessibilitySize ? [GridItem(.flexible())] : [
            GridItem(.flexible()),
            GridItem(.flexible()),
        ]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(classes) { item in
                diagnosticsClassTile(item, isIncluded: isIncluded)
            }
        }
        .padding(.vertical, 4)
    }

    private func diagnosticsClassTile(_ item: DiagnosticsDisclosureClass, isIncluded: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isIncluded ? "checkmark.circle.fill" : "slash.circle")
                .foregroundStyle(isIncluded ? DiagnosticsVisualSpec.accent : .secondary)
                .imageScale(.medium)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                if !dynamicTypeSize.isAccessibilitySize {
                    Text(item.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
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

    private static let includedDisclosureClasses: [DiagnosticsDisclosureClass] = [
        DiagnosticsDisclosureClass(title: "App details", detail: "App release and build number."),
        DiagnosticsDisclosureClass(title: "Device type", detail: "Model and iOS version."),
        DiagnosticsDisclosureClass(title: "Steps in the app", detail: "Screens opened and buttons used."),
        DiagnosticsDisclosureClass(title: "Downloaded maps", detail: "Offline maps and their versions."),
        DiagnosticsDisclosureClass(title: "Map file links", detail: "Making Tracks map file paths."),
        DiagnosticsDisclosureClass(title: "Problems", detail: "Status codes and failure labels."),
        DiagnosticsDisclosureClass(title: "Load times", detail: "Fetch and map drawing times."),
        DiagnosticsDisclosureClass(title: "Places and taps", detail: "Places opened, saved, hidden, or marked seen."),
    ]

    private static let excludedDisclosureClasses: [DiagnosticsDisclosureClass] = [
        DiagnosticsDisclosureClass(title: "Device name", detail: "Your personal device label."),
        DiagnosticsDisclosureClass(title: "Precise location", detail: "Your exact coordinates are not included."),
        DiagnosticsDisclosureClass(title: "Search text", detail: "What you typed is omitted."),
    ]

}

private enum DiagnosticsVisualSpec {
    static let accent = MapThemeColor.color(css: "#0a6b5c")
}

private struct DiagnosticsDisclosureClass: Identifiable {
    let title: String
    let detail: String

    var id: String { title }
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

    var statusLabel: String {
        switch self {
        case .fifteenMinutes:
            return "the last 15 minutes"
        case .lastHour:
            return "the last hour"
        case .everything:
            return "everything"
        }
    }

    var accessibilityID: String {
        switch self {
        case .fifteenMinutes:
            return "fifteen-minutes"
        case .lastHour:
            return "last-hour"
        case .everything:
            return "everything"
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
            MapThemeColor.color(css: theme.background)
            dummyMapLines
            dummyPin
        }
        .frame(maxWidth: .infinity, minHeight: 96)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(MapThemeColor.color(css: theme.boundaries).opacity(0.55), lineWidth: 1)
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
            .stroke(MapThemeColor.color(css: theme.roads), lineWidth: 5)

            Path { path in
                path.addRect(CGRect(x: size.width * 0.06, y: size.height * 0.10, width: size.width * 0.26, height: size.height * 0.22))
                path.addRect(CGRect(x: size.width * 0.68, y: size.height * 0.66, width: size.width * 0.24, height: size.height * 0.18))
            }
            .fill(MapThemeColor.color(css: theme.parks).opacity(theme.showsParks ? 0.75 : 0.35))
        }
    }

    private var dummyPin: some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(MapThemeColor.color(css: PinLayers.pinColor))
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
    static let destination = MapShellDestination.offlineMaps
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

struct AboutSoftwareLicenceEntry: Identifiable {
    let acknowledgement: String
    let category: String
    let licenseURL: URL?
    let name: String
    let noticeText: String
    let versionOrPin: String

    var id: String { "\(name)|\(versionOrPin)" }

    init(credit: OSSCreditEntry) {
        acknowledgement = credit.acknowledgement
        category = credit.category
        licenseURL = credit.licenseURL
        name = credit.name
        noticeText = credit.noticeText
        versionOrPin = credit.versionOrPin
    }
}

struct AboutDataLicenceEntry {
    let name: String
    let license: String?
    let text: String
    let licenseURL: URL?

    static let openStreetMap = AboutDataLicenceEntry(
        name: "OpenStreetMap",
        license: nil,
        text: "Map data © OpenStreetMap contributors.",
        licenseURL: URL(string: "https://www.openstreetmap.org/copyright")!
    )
}

struct AboutLicenceInventory {
    let software: [AboutSoftwareLicenceEntry]
    let data: [AboutDataLicenceEntry]

    init(softwareCredits: [OSSCreditEntry], attribution: [Attribution]) {
        software = softwareCredits.map(AboutSoftwareLicenceEntry.init)
        data = [AboutDataLicenceEntry.openStreetMap] + attribution.map { item in
            AboutDataLicenceEntry(
                name: item.source,
                license: item.license,
                text: item.text,
                licenseURL: nil
            )
        }
    }
}

private struct AboutView: View {
    let attribution: [Attribution]

    private let tokens = MaterialTheme.snow.tokens

    private static let buildCommit = loadBuildCommit()
    private static let appVersion = loadAppVersion()
    private static let softwareCredits = OSSCreditsManifest.load()?.credits ?? []
    private static let privacyPolicyURL = URL(string: "https://making-tracks.app/privacy")!

    private var licenceInventory: AboutLicenceInventory {
        AboutLicenceInventory(
            softwareCredits: Self.softwareCredits,
            attribution: attribution
        )
    }

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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Making Tracks")
                        .font(Typography.font(for: .label))
                        .textCase(.uppercase)
                        .tracking(1.2)
                        .foregroundStyle(tokens.muted.swiftUIColor)

                    Text("About")
                        .font(Typography.font(for: .sheetTitle))
                        .foregroundStyle(tokens.ink.swiftUIColor)
                        .accessibilityAddTraits(.isHeader)

                    Text("The story, the privacy promise, and the credits.")
                        .font(Typography.font(for: .evocativeSubline))
                        .foregroundStyle(tokens.muted.swiftUIColor)
                }
                .fixedSize(horizontal: false, vertical: true)

                MaterialRaisedCardRow {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("The map is fresh snow.")
                            .font(Typography.font(for: .heroTitle))
                            .foregroundStyle(tokens.ink.swiftUIColor)
                            .accessibilityAddTraits(.isHeader)
                        Text(
                            "Moving through the world marks it. Places come from open data "
                                + "including Wikipedia, OpenStreetMap, and heritage registers."
                        )
                        .font(Typography.font(for: .body))
                        .foregroundStyle(tokens.ink.swiftUIColor)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                MaterialRaisedCardRow {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "lock")
                            .iconRole(.inline)
                            .foregroundStyle(tokens.accent.swiftUIColor)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Private by construction")
                                .font(Typography.font(for: .listRowTitle))
                                .foregroundStyle(tokens.ink.swiftUIColor)
                                .accessibilityAddTraits(.isHeader)
                            Text(OnboardingCopy.savedActivityPrivacy)
                                .font(Typography.font(for: .body))
                                .foregroundStyle(tokens.ink.swiftUIColor)
                                .accessibilityIdentifier("about.privacy-saved-activity")
                            Link(destination: Self.privacyPolicyURL) {
                                Text("Privacy policy")
                                    .font(Typography.font(for: .button))
                            }
                            .foregroundStyle(tokens.accent.swiftUIColor)
                            .frame(minWidth: 44, minHeight: 45, alignment: .leading)
                            .contentShape(Rectangle())
                            .accessibilityValue(Self.privacyPolicyURL.absoluteString)
                            .accessibilityIdentifier("about.privacy-policy")
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text("Licences")
                    .font(Typography.font(for: .label))
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(tokens.muted.swiftUIColor)
                    .padding(.top, 4)
                    .accessibilityAddTraits(.isHeader)

                MaterialRaisedCardRow {
                    VStack(spacing: 0) {
                        AboutLicenceDestinationLink(
                            title: "Software licences",
                            summary: "GRDB.swift · MapLibre · Newsreader OFL · Noto Sans",
                            systemImage: "chevron.left.forwardslash.chevron.right",
                            accessibilityIdentifier: "about.software-licences"
                        ) {
                            SoftwareLicencesView(credits: licenceInventory.software)
                        }

                        AboutLicenceDestinationLink(
                            title: "Data licences",
                            summary: "OpenStreetMap · Wikipedia · regional sources",
                            systemImage: "cylinder.split.1x2",
                            accessibilityIdentifier: "about.data-licences"
                        ) {
                            DataLicencesView(entries: licenceInventory.data)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "Version \(Self.appVersion)")
                        .font(Typography.font(for: .metadata))
                        .foregroundStyle(tokens.muted.swiftUIColor)
                        .accessibilityIdentifier("about.app-version")
                    Text(verbatim: "Build \(Self.buildCommit)")
                        .font(Typography.font(for: .data))
                        .foregroundStyle(tokens.muted.swiftUIColor)
                        .accessibilityIdentifier("credits.build-commit")
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .accessibilityIdentifier("about.root")
        .background(tokens.surface.swiftUIColor)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AboutLicenceDestinationLink<Destination: View>: View {
    let title: String
    let summary: String
    let systemImage: String
    let accessibilityIdentifier: String
    @ViewBuilder let destination: () -> Destination

    private let tokens = MaterialTheme.snow.tokens

    var body: some View {
        NavigationLink(destination: destination) {
            MaterialHairlineRow {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: systemImage)
                        .iconRole(.inline)
                        .foregroundStyle(tokens.accent.swiftUIColor)
                        .frame(width: 24)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: title)
                            .font(Typography.font(for: .listRowTitle))
                            .foregroundStyle(tokens.ink.swiftUIColor)
                        Text(verbatim: summary)
                            .font(Typography.font(for: .metadata))
                            .foregroundStyle(tokens.muted.swiftUIColor)
                    }
                    .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .iconRole(.accessory)
                        .foregroundStyle(tokens.muted.swiftUIColor)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(summary)
        .accessibilityHint("Opens \(title.lowercased())")
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct SoftwareLicencesView: View {
    let credits: [AboutSoftwareLicenceEntry]

    private let tokens = MaterialTheme.snow.tokens

    var body: some View {
        ScrollView {
            MaterialRaisedCardRow {
                VStack(spacing: 0) {
                    ForEach(credits) { credit in
                        MaterialHairlineRow {
                            OpenSourceCreditView(credit: credit)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .accessibilityIdentifier("about.software-licences.root")
        .background(tokens.surface.swiftUIColor)
        .navigationTitle("Software licences")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DataLicencesView: View {
    let entries: [AboutDataLicenceEntry]

    private let tokens = MaterialTheme.snow.tokens

    var body: some View {
        ScrollView {
            MaterialRaisedCardRow {
                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                        MaterialHairlineRow {
                            if let licenseURL = entry.licenseURL {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(verbatim: entry.name)
                                        .font(Typography.font(for: .listRowTitle))
                                        .foregroundStyle(tokens.ink.swiftUIColor)
                                        .accessibilityIdentifier("about.openstreetmap-name")
                                    if let license = entry.license {
                                        Text(verbatim: license)
                                            .font(Typography.font(for: .metadata))
                                            .foregroundStyle(tokens.muted.swiftUIColor)
                                    }
                                    Text(verbatim: entry.text)
                                        .font(Typography.font(for: .body))
                                        .foregroundStyle(tokens.ink.swiftUIColor)
                                        .accessibilityIdentifier("about.openstreetmap-attribution")
                                    Link(destination: licenseURL) {
                                        Text("OpenStreetMap copyright")
                                            .font(Typography.font(for: .button))
                                    }
                                    .foregroundStyle(tokens.accent.swiftUIColor)
                                    .frame(minWidth: 44, minHeight: 45, alignment: .leading)
                                    .contentShape(Rectangle())
                                    .accessibilityValue(licenseURL.absoluteString)
                                    .accessibilityIdentifier("about.openstreetmap-copyright")
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                CreditEntryView(
                                    title: entry.name,
                                    subtitle: entry.license,
                                    text: entry.text
                                )
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .accessibilityIdentifier("about.data-licences.root")
        .background(tokens.surface.swiftUIColor)
        .navigationTitle("Data licences")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct CreditEntryView: View {
    let title: String
    let subtitle: String?
    let text: String

    private let tokens = MaterialTheme.snow.tokens

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: title)
                .font(Typography.font(for: .listRowTitle))
                .foregroundStyle(tokens.ink.swiftUIColor)
            if let subtitle {
                Text(verbatim: subtitle)
                    .font(Typography.font(for: .metadata))
                    .foregroundStyle(tokens.muted.swiftUIColor)
            }
            Text(verbatim: text)
                .font(Typography.font(for: .body))
                .foregroundStyle(tokens.ink.swiftUIColor)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("credits.manifest.\(title)")
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum ListPickerMembershipChange: Equatable {
    case added(listID: Int64)
    case removed(listID: Int64)

    static func completed(wasMember: Bool, listID: Int64) -> Self {
        wasMember ? .removed(listID: listID) : .added(listID: listID)
    }
}

struct ListPickerMembershipState: Equatable {
    private(set) var memberships: Set<Int64>
    private(set) var isUpdating = false

    init(memberships: Set<Int64> = []) {
        self.memberships = memberships
    }

    func contains(_ listID: Int64) -> Bool {
        memberships.contains(listID)
    }

    mutating func beginToggle(listID: Int64) -> ListPickerMembershipChange? {
        guard beginMutation() else { return nil }
        return .completed(wasMember: memberships.contains(listID), listID: listID)
    }

    mutating func beginMutation() -> Bool {
        guard !isUpdating else { return false }
        isUpdating = true
        return true
    }

    mutating func replaceMemberships(_ memberships: Set<Int64>) {
        self.memberships = memberships
    }

    mutating func finishMutation() {
        isUpdating = false
    }
}

struct ListPickerSnapshot {
    let lists: [PlaceList]
    let memberships: Set<Int64>
}

@MainActor
enum ListPickerReloadCoordinator {
    static func perform(
        begin: () -> Bool,
        finish: () -> Void,
        load: () async -> ListPickerSnapshot,
        apply: (ListPickerSnapshot) -> Void
    ) async {
        // An overlapping mutation owns freshness; callers must not treat this
        // Void return as proof that a new snapshot was published.
        guard begin() else { return }
        defer { finish() }
        apply(await load())
    }
}

struct ListPickerView: View {
    let placeID: String
    let model: MapScreenModel?
    let onChanged: @MainActor (ListPickerMembershipChange) -> Void

    @State private var lists: [PlaceList] = []
    @State private var membershipState = ListPickerMembershipState()
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
                        .disabled(membershipState.isUpdating)
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
                                if let id = list.id, membershipState.contains(id) {
                                    Image(systemName: "checkmark")
                                        .accessibilityLabel("In list")
                                }
                            }
                        }
                        .accessibilityIdentifier("list-picker.row.\(list.id ?? -1)")
                        .disabled(list.id == nil || membershipState.isUpdating)
                    }
                }
            }
            .navigationTitle("Add to list")
            .toolbar {
                Button("Done") { dismiss() }
                    .accessibilityIdentifier("list-picker.done")
                    .disabled(membershipState.isUpdating)
            }
            .task { await reload() }
        }
    }

    @MainActor
    private func reload() async {
        guard let model else { return }
        await ListPickerReloadCoordinator.perform {
            membershipState.beginMutation()
        } finish: {
            membershipState.finishMutation()
        } load: {
            await loadSnapshot(using: model)
        } apply: { snapshot in
            applySnapshot(snapshot)
        }
    }

    @MainActor
    private func loadSnapshot(using model: MapScreenModel) async -> ListPickerSnapshot {
        let nextLists = await model.lists()
        let nextMemberships = Set(
            await model.listMemberships(containing: placeID)
        )
        return ListPickerSnapshot(lists: nextLists, memberships: nextMemberships)
    }

    @MainActor
    private func applySnapshot(_ snapshot: ListPickerSnapshot) {
        lists = snapshot.lists
        membershipState.replaceMemberships(snapshot.memberships)
    }

    @MainActor
    private func toggle(_ list: PlaceList) async {
        guard
            let id = list.id,
            let model,
            let change = membershipState.beginToggle(listID: id)
        else { return }
        defer { membershipState.finishMutation() }
        do {
            switch change {
            case .removed:
                try await model.removeFromList(placeID: placeID, listID: id)
            case .added:
                try await model.addToList(placeID: placeID, listID: id)
            }
            actionError = nil
            applySnapshot(await loadSnapshot(using: model))
            onChanged(change)
        } catch {
            actionError = "Could not update that list."
        }
    }

    @MainActor
    private func createAndAdd() async {
        guard let model, membershipState.beginMutation() else { return }
        defer { membershipState.finishMutation() }
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
            applySnapshot(await loadSnapshot(using: model))
            onChanged(.added(listID: id))
        } catch {
            actionError = ListsCopy.listNameCreateFailureMessage(for: error, draftName: trimmedName)
        }
    }
}

private struct OpenSourceCreditView: View {
    let credit: AboutSoftwareLicenceEntry

    private let tokens = MaterialTheme.snow.tokens

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: credit.name)
                    .font(Typography.font(for: .listRowTitle))
                    .foregroundStyle(tokens.ink.swiftUIColor)
                Text(verbatim: credit.acknowledgement)
                    .font(Typography.font(for: .body))
                    .foregroundStyle(tokens.ink.swiftUIColor)
                Text(verbatim: "\(credit.category) | \(credit.versionOrPin)")
                    .font(Typography.font(for: .metadata))
                    .foregroundStyle(tokens.muted.swiftUIColor)
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("credits.oss.\(credit.id)")
            if let licenseURL = credit.licenseURL {
                Link(destination: licenseURL) {
                    Text("License")
                        .font(Typography.font(for: .button))
                }
                .foregroundStyle(tokens.accent.swiftUIColor)
                .frame(minWidth: 44, minHeight: 45, alignment: .leading)
                .contentShape(Rectangle())
                .accessibilityLabel("License for \(credit.name)")
                .accessibilityValue(licenseURL.absoluteString)
                .accessibilityIdentifier("credits.oss.\(credit.id).license")
            }
            Text(verbatim: credit.noticeText)
                .font(Typography.font(for: .data))
                .foregroundStyle(tokens.ink.swiftUIColor)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .accessibilityIdentifier("credits.oss.\(credit.id).notice")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct OSSCreditsManifest: Decodable {
    let credits: [OSSCreditEntry]

    static func load(from bundle: Bundle = .main) -> OSSCreditsManifest? {
        guard let url = bundle.url(forResource: "OSSCredits", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(OSSCreditsManifest.self, from: data)
    }
}

struct OSSCreditEntry: Decodable, Identifiable {
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

struct FlowLayout: Layout {
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
                        filterButton(
                            title: "All types",
                            systemImage: "checkmark.circle",
                            isSelected: draft.includesAllCategories,
                            accessibilityIdentifier: "track-filter-picker.category.all"
                        ) {
                            draft.selectAllCategories()
                        }

                        ForEach(categoryOptions) { category in
                            filterButton(
                                title: category.title,
                                systemImage: PinLayers.categorySymbolNames[category.iconName] ?? "mappin",
                                isSelected: draft.categories?.contains(category.id) == true,
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
    struct Components {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat
    }

    static func color(css: String) -> Color {
        guard let color = uiColor(css: css) else {
            preconditionFailure("Unsupported map theme colour: \(css)")
        }
        return Color(uiColor: color)
    }

    static func uiColor(css: String) -> UIColor? {
        guard let components = components(css: css) else {
            return nil
        }

        return UIColor(
            red: components.red,
            green: components.green,
            blue: components.blue,
            alpha: components.alpha
        )
    }

    static func components(css: String) -> Components? {
        let trimmed = css.trimmingCharacters(in: .whitespacesAndNewlines)
        let hex = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        let isSixDigitHex = hex.utf8.count == 6 && hex.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
        }
        if isSixDigitHex, let rgb = Int(hex, radix: 16) {
            return Components(
                red: CGFloat((rgb >> 16) & 0xff) / 255,
                green: CGFloat((rgb >> 8) & 0xff) / 255,
                blue: CGFloat(rgb & 0xff) / 255,
                alpha: 1
            )
        }

        guard trimmed.hasPrefix("rgba("), trimmed.hasSuffix(")") else {
            return nil
        }
        let contents = trimmed.dropFirst(5).dropLast()
        let fields = contents.split(separator: ",", omittingEmptySubsequences: false)
        guard fields.count == 4,
              let red = byte(from: fields[0]),
              let green = byte(from: fields[1]),
              let blue = byte(from: fields[2]),
              let alpha = Double(String(fields[3]).trimmingCharacters(in: .whitespacesAndNewlines)),
              alpha.isFinite,
              (0...1).contains(alpha)
        else {
            return nil
        }

        return Components(
            red: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: CGFloat(alpha)
        )
    }

    private static func byte(from field: Substring) -> Int? {
        guard let value = Int(String(field).trimmingCharacters(in: .whitespacesAndNewlines)),
              (0...255).contains(value)
        else {
            return nil
        }
        return value
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
    private var showSavedPlaces = true

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
                display: PinFeatureFilter.discoveryFeatures(
                    sourceFeatures,
                    showHidden: showHiddenPlaces,
                    showSaved: showSavedPlaces
                ),
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
                showHidden: showHiddenPlaces,
                showSaved: showSavedPlaces
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
                display: PinFeatureFilter.discoveryFeatures(
                    sourceFeatures,
                    showHidden: showHiddenPlaces,
                    showSaved: showSavedPlaces
                ),
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
                showHidden: showHiddenPlaces,
                showSaved: showSavedPlaces
            ),
            nearbyPrompt: PinFeatureFilter.nearbyPromptFeatures(sourceFeatures),
            sourceCount: sourceFeatures.count,
            flowMetrics: nil
        )
    }

    func setShowHidden(_ showHidden: Bool) {
        showHiddenPlaces = showHidden
    }

    func setShowSaved(_ showSaved: Bool) {
        showSavedPlaces = showSaved
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

    func lovedPlaces() async -> [ListPlace] {
        let db = database
        return await Task.detached {
            (try? db.lovedPlaces()) ?? []
        }.value
    }

    func hiddenPlaces() async -> [ListPlace] {
        let db = database
        return await Task.detached {
            (try? db.hiddenPlaces()) ?? []
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
        guard let placeRef = await actionPlaceRef(for: placeID) else {
            throw MapScreenActionError.placeUnavailable
        }
        let rollback = hiddenTracker.hiddenIDs.contains(placeID)
            ? hiddenTracker.beginSetHidden(placeID: placeID, hidden: false)
            : nil
        do {
            try coreLoop.addToList(placeRef, listID: listID)
        } catch {
            if let rollback {
                hiddenTracker.rollback(rollback)
            }
            throw error
        }
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
            if let source = snapshotCardSource(for: placeID) {
                return source
            }
            return .tile(fixturePlace)
        }
        if let tileClient = tileClient(for: selectedRegionID) {
            return await PlaceResolver(tile: tileClient, snapshots: database).source(for: placeID)
        }
        return snapshotCardSource(for: placeID)
    }

    private func snapshotCardSource(for placeID: String) -> CardSource? {
        guard let snapshot = try? database.snapshot(for: placeID) else { return nil }
        let source = CardSource.actionSafeSnapshot(snapshot)
        guard source != .unavailable else { return nil }
        return source
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
