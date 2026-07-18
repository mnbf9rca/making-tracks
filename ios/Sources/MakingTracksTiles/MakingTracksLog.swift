import Foundation
import OSLog

public enum MakingTracksLog {
    public static let subsystem = "app.making-tracks"

    public static let downloads = Logger(subsystem: subsystem, category: "downloads")
    public static let gc = Logger(subsystem: subsystem, category: "gc")
    public static let install = Logger(subsystem: subsystem, category: "install")
    public static let resolution = Logger(subsystem: subsystem, category: "resolution")
    public static let startup = Logger(subsystem: subsystem, category: "startup")

    public static func host(_ url: URL) -> String {
        url.host ?? "unknown"
    }

    public static func objectKind(_ url: URL) -> String {
        let last = url.lastPathComponent
        if last == "current.json" {
            return "current"
        }
        if last == "manifest.json" {
            return "manifest"
        }
        if last == "regions.json" {
            return "region-index"
        }
        if last.hasSuffix(".pmtiles") {
            return "basemap"
        }
        if last.hasSuffix(".json.gz") {
            return "tile"
        }
        return "unknown"
    }

    public static func errorLabel(_ error: Error) -> String {
        if let tileError = error as? TileError {
            return tileError.logLabel
        }
        if let urlError = error as? URLError {
            return "url-\(urlError.code.rawValue)"
        }
        return String(describing: type(of: error))
    }
}

private extension TileError {
    var logLabel: String {
        switch self {
        case .invalidURL:
            return "invalid-url"
        case .untrustedHost:
            return "untrusted-host"
        case .invalidRedirect:
            return "invalid-redirect"
        case .invalidCurrent:
            return "invalid-current"
        case .invalidManifest:
            return "invalid-manifest"
        case .invalidRegionIndex:
            return "invalid-region-index"
        case .invalidTile:
            return "invalid-tile"
        case .invalidOfflinePack:
            return "invalid-offline-pack"
        case .invalidBackgroundFetch:
            return "invalid-background-fetch"
        case .insufficientStorage:
            return "insufficient-storage"
        case .checksumMismatch:
            return "checksum-mismatch"
        case .byteCountMismatch:
            return "byte-count-mismatch"
        case .compressedTooLarge:
            return "compressed-too-large"
        case .inflatedTooLarge:
            return "inflated-too-large"
        case .invalidGzip:
            return "invalid-gzip"
        case let .httpStatus(status):
            return "http-\(status)"
        case .downloadPaused:
            return "download-paused"
        case .downloadCancelled:
            return "download-cancelled"
        case .downloadAlreadyInProgress:
            return "download-already-in-progress"
        }
    }
}
