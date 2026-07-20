import Foundation
import OSLog

public enum MakingTracksLog {
    public static let subsystem = "app.making-tracks"
    private static let diagnosticSink = DiagnosticLogSinkRegistry()

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
        let components = publicObjectPathComponents(url)
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
        if components.count >= 5, components[2] == "images", last.hasSuffix(".json") {
            return "image-index"
        }
        if components.count >= 5, components[2] == "descriptions", last.hasSuffix(".json") {
            return "description-index"
        }
        if components.count >= 3, components[0] == "thumbs", last.hasSuffix(".webp") {
            return "thumbnail"
        }
        if components.count >= 4, components[2] == "search", last == "compact.json" {
            return "search-compact"
        }
        return "unknown"
    }

    public static func objectPath(_ url: URL) -> String {
        guard url.host == "tiles.making-tracks.app" else { return "unknown" }
        let path = url.path
        return path.isEmpty ? "/" : path
    }

    public static func objectPublishVersion(_ url: URL) -> String {
        let components = publicObjectPathComponents(url)
        guard components.count >= 2,
              isPublishVersion(components[1])
        else { return "none" }
        return components[1]
    }

    public static func objectTileZ(_ url: URL) -> String {
        let components = publicObjectPathComponents(url)
        guard components.count >= 5,
              ["tiles", "images", "descriptions"].contains(components[2]),
              components[3].allSatisfy(\.isNumber)
        else { return "none" }
        return components[3]
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

    public static func configureDiagnosticLogStore(_ store: DiagnosticLogStore?) {
        diagnosticSink.configure(store)
    }

    public static func file(
        category: DiagnosticLogCategory,
        level: DiagnosticLogLevel,
        _ message: String,
        fields: [DiagnosticLogField]
    ) {
        diagnosticSink.append(category: category, level: level, message: message, fields: fields)
    }

    private static func publicObjectPathComponents(_ url: URL) -> [String] {
        guard url.host == "tiles.making-tracks.app" else { return [] }
        return url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    private static func isPublishVersion(_ value: String) -> Bool {
        guard value.count == "20260719T125813Z".count else { return false }
        let characters = Array(value)
        guard characters[8] == "T", characters[15] == "Z" else { return false }
        return characters.enumerated().allSatisfy { index, character in
            index == 8 || index == 15 || character.isNumber
        }
    }
}

private final class DiagnosticLogSinkRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var store: DiagnosticLogStore?

    func configure(_ store: DiagnosticLogStore?) {
        lock.lock()
        self.store = store
        lock.unlock()
    }

    func append(
        category: DiagnosticLogCategory,
        level: DiagnosticLogLevel,
        message: String,
        fields: [DiagnosticLogField]
    ) {
        lock.lock()
        let currentStore = store
        lock.unlock()
        try? currentStore?.append(category: category, level: level, message: message, fields: fields)
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
        case .invalidImageIndex:
            return "invalid-image-index"
        case .invalidTile:
            return "invalid-tile"
        case .invalidOfflinePack:
            return "invalid-offline-pack"
        case .invalidBackgroundFetch:
            return "invalid-background-fetch"
        case .insufficientStorage:
            return "insufficient-storage"
        case .responseTooLarge:
            return "response-too-large"
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
