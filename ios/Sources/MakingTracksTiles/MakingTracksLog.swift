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

    public static func objectPath(_ url: URL) -> String {
        guard url.host == "tiles.making-tracks.app" else { return "unknown" }
        let path = url.path
        return path.isEmpty ? "/" : path
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
