import CryptoKit
import Foundation
import Security

public enum DiagnosticLogCategory: String, Sendable {
    case downloads
    case gc
    case install
    case resolution
    case startup
}

public enum DiagnosticLogLevel: String, Sendable {
    case debug
    case info
    case error
}

public enum DiagnosticLogField: Sendable {
    case `public`(String, String)
    case object(String, String)
}

public enum DiagnosticLogWindow: Hashable, Sendable {
    case fifteenMinutes
    case lastHour
    case everything

    fileprivate func contains(_ date: Date, relativeTo now: Date) -> Bool {
        switch self {
        case .fifteenMinutes:
            return date >= now.addingTimeInterval(-15 * 60)
        case .lastHour:
            return date >= now.addingTimeInterval(-60 * 60)
        case .everything:
            return true
        }
    }
}

public struct DiagnosticInstalledPack: Equatable, Sendable {
    public var id: String
    public var publishVersion: String
    public var state: String

    public init(id: String, publishVersion: String, state: String) {
        self.id = id
        self.publishVersion = publishVersion
        self.state = state
    }
}

public struct DiagnosticLogMetadata: Equatable, Sendable {
    public var appVersion: String
    public var build: String
    public var commit: String
    public var osVersion: String
    public var deviceModel: String
    public var installedPacks: [DiagnosticInstalledPack]

    public init(
        appVersion: String,
        build: String,
        commit: String,
        osVersion: String,
        deviceModel: String,
        installedPacks: [DiagnosticInstalledPack]
    ) {
        self.appVersion = appVersion
        self.build = build
        self.commit = commit
        self.osVersion = osVersion
        self.deviceModel = deviceModel
        self.installedPacks = installedPacks
    }
}

public struct DiagnosticLogArtifact: Equatable, Sendable {
    public var directoryURL: URL
    public var archiveURL: URL
    public var summaryURL: URL
    public var logURL: URL
    public var decodeTableURL: URL
    public var byteCount: Int
    public var preview: String
}

public enum DiagnosticLogExportError: Error, Equatable {
    case privacyScrubFailed
}

public enum DiagnosticLogSalt {
    public static func loadOrCreate(service: String, account: String, length: Int = 32) throws -> Data {
        precondition(length > 0)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let readStatus = SecItemCopyMatching(query as CFDictionary, &result)
        if readStatus == errSecSuccess, let data = result as? Data {
            return data
        }
        if readStatus != errSecItemNotFound {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(readStatus))
        }

        var bytes = Data(count: length)
        let randomStatus = bytes.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, length, baseAddress)
        }
        guard randomStatus == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(randomStatus))
        }

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: bytes,
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess || addStatus == errSecDuplicateItem else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus))
        }
        if addStatus == errSecDuplicateItem {
            return try loadOrCreate(service: service, account: account, length: length)
        }
        return bytes
    }
}

public final class DiagnosticLogStore {
    public let root: URL
    private let salt: Data
    private let now: @Sendable () -> Date
    private let fileManager: FileManager
    private let lock = NSLock()

    public init(
        root: URL,
        salt: Data,
        now: @escaping @Sendable () -> Date = Date.init,
        fileManager: FileManager = .default
    ) {
        self.root = root
        self.salt = salt
        self.now = now
        self.fileManager = fileManager
    }

    public static func defaultRoot(bundleIdentifier: String, fileManager: FileManager = .default) throws -> URL {
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return support
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("Diagnostics", isDirectory: true)
    }

    public func append(
        category: DiagnosticLogCategory,
        level: DiagnosticLogLevel,
        message: String,
        fields: [DiagnosticLogField]
    ) throws {
        let timestamp = Self.timestampFormatter().string(from: now())
        var objectDecodeEntries: [String: String] = [:]
        let renderedFields = fields.map { field in
            switch field {
            case let .public(name, value):
                return "\(name)=\(Self.sanitizePublicValue(value))"
            case let .object(name, value):
                let hash = hashObject(value)
                objectDecodeEntries[hash] = Self.sanitizePublicValue(value)
                return "\(name)=\(hash)"
            }
        }
        let line = ([timestamp, category.rawValue, level.rawValue, message] + renderedFields)
            .joined(separator: " ")
        try appendRawLine(line, objectDecodeEntries: objectDecodeEntries)
    }

    public func hashObject(_ value: String) -> String {
        var data = Data()
        data.append(salt)
        data.append(Data(value.utf8))
        let digest = SHA256.hash(data: data)
        return "h:" + digest.map { String(format: "%02x", $0) }.joined().prefix(16)
    }

    public func deleteDiagnostics(stagingRoot: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        if fileManager.fileExists(atPath: root.path) {
            try fileManager.removeItem(at: root)
        }
        if fileManager.fileExists(atPath: stagingRoot.path) {
            try fileManager.removeItem(at: stagingRoot)
        }
        try createDirectoryIfNeeded(root)
    }

    func snapshotLines(window: DiagnosticLogWindow) throws -> [String] {
        lock.lock()
        defer { lock.unlock() }
        let current = logURL
        guard fileManager.fileExists(atPath: current.path) else { return [] }
        let text = try String(contentsOf: current, encoding: .utf8)
        return text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { line in
                guard let date = Self.dateFromLine(line) else { return true }
                return window.contains(date, relativeTo: now())
            }
    }

    func appendRawLineForTesting(_ line: String) throws {
        try appendRawLine(line, objectDecodeEntries: [:])
    }

    func snapshotObjectDecodeEntries() throws -> [String: String] {
        lock.lock()
        defer { lock.unlock() }
        return try readObjectDecodeEntries()
    }

    private var logURL: URL {
        root.appendingPathComponent("making-tracks.log", isDirectory: false)
    }

    private var objectDecodeURL: URL {
        root.appendingPathComponent("object-decode.tsv", isDirectory: false)
    }

    private func appendRawLine(_ line: String, objectDecodeEntries: [String: String]) throws {
        lock.lock()
        defer { lock.unlock() }
        try createDirectoryIfNeeded(root)
        let output = line + "\n"
        if fileManager.fileExists(atPath: logURL.path) {
            let handle = try FileHandle(forWritingTo: logURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(output.utf8))
        } else {
            try output.write(to: logURL, atomically: true, encoding: .utf8)
            try Self.setDiagnosticsResourceValues(logURL)
        }
        if objectDecodeEntries.isEmpty == false {
            try mergeObjectDecodeEntries(objectDecodeEntries)
        }
    }

    private func readObjectDecodeEntries() throws -> [String: String] {
        guard fileManager.fileExists(atPath: objectDecodeURL.path) else { return [:] }
        let text = try String(contentsOf: objectDecodeURL, encoding: .utf8)
        return text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .dropFirst()
            .reduce(into: [String: String]()) { entries, line in
                let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2 else { return }
                entries[String(parts[0])] = String(parts[1])
            }
    }

    private func mergeObjectDecodeEntries(_ newEntries: [String: String]) throws {
        var entries = try readObjectDecodeEntries()
        for (hash, plaintext) in newEntries {
            entries[hash] = plaintext
        }
        var lines = ["hash\tplaintext"]
        lines.append(contentsOf: entries.sorted { $0.key < $1.key }.map { "\($0.key)\t\($0.value)" })
        try (lines.joined(separator: "\n") + "\n").write(to: objectDecodeURL, atomically: true, encoding: .utf8)
        try Self.setDiagnosticsResourceValues(objectDecodeURL)
    }

    private func createDirectoryIfNeeded(_ url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        try Self.setDiagnosticsResourceValues(url)
    }

    private static func sanitizePublicValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
    }

    private static func setDiagnosticsResourceValues(_ url: URL) throws {
        var mutableURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try mutableURL.setResourceValues(values)
        try (url as NSURL).setResourceValue(URLFileProtection.completeUntilFirstUserAuthentication, forKey: .fileProtectionKey)
    }

    private static func timestampFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

    private static func dateFromLine(_ line: String) -> Date? {
        guard let timestamp = line.split(separator: " ", maxSplits: 1).first else { return nil }
        return timestampFormatter().date(from: String(timestamp))
    }
}

public struct DiagnosticLogExporter {
    private let store: DiagnosticLogStore
    private let metadata: DiagnosticLogMetadata
    private let knownObjects: [String]
    private let fileManager: FileManager
    private let exportedAt: @Sendable () -> Date

    public init(
        store: DiagnosticLogStore,
        metadata: DiagnosticLogMetadata,
        knownObjects: [String],
        fileManager: FileManager = .default,
        exportedAt: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = store
        self.metadata = metadata
        self.knownObjects = knownObjects
        self.fileManager = fileManager
        self.exportedAt = exportedAt
    }

    public func prepare(window: DiagnosticLogWindow, stagingRoot: URL) throws -> DiagnosticLogArtifact {
        if fileManager.fileExists(atPath: stagingRoot.path) {
            try fileManager.removeItem(at: stagingRoot)
        }
        let exportTimestamp = Self.filenameTimestampFormatter().string(from: exportedAt())
        let directory = stagingRoot.appendingPathComponent("MakingTracksDiagnostics-\(exportTimestamp)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try DiagnosticLogStore.setDiagnosticsResourceValuesForExporter(directory)

            let summaryURL = directory.appendingPathComponent("summary-\(exportTimestamp).txt")
            let logURL = directory.appendingPathComponent("diagnostic-log-\(exportTimestamp).txt")
            let decodeTableURL = directory.appendingPathComponent("decode-table-\(exportTimestamp).tsv")

            let summary = renderSummary()
            let log = try store.snapshotLines(window: window).joined(separator: "\n") + "\n"
            let decodeTable = try renderDecodeTable(log: log)
            let scrubText = [summary, log, decodeTable].joined(separator: "\n")
            guard Self.passesPrivacyScrub(scrubText) else {
                throw DiagnosticLogExportError.privacyScrubFailed
            }

            try summary.write(to: summaryURL, atomically: true, encoding: .utf8)
            try log.write(to: logURL, atomically: true, encoding: .utf8)
            try decodeTable.write(to: decodeTableURL, atomically: true, encoding: .utf8)
            let archiveURL = try makeArchive(directory: directory, stagingRoot: stagingRoot, exportTimestamp: exportTimestamp)
            let byteCount = try archiveByteCount(archiveURL)
            let preview = renderPreview(summary: summary, log: log, decodeTable: decodeTable)

            return DiagnosticLogArtifact(
                directoryURL: directory,
                archiveURL: archiveURL,
                summaryURL: summaryURL,
                logURL: logURL,
                decodeTableURL: decodeTableURL,
                byteCount: byteCount,
                preview: preview
            )
        } catch {
            if fileManager.fileExists(atPath: stagingRoot.path) {
                try? fileManager.removeItem(at: stagingRoot)
            }
            throw error
        }
    }

    private func makeArchive(directory: URL, stagingRoot: URL, exportTimestamp: String) throws -> URL {
        let destination = stagingRoot.appendingPathComponent("MakingTracksDiagnostics-\(exportTimestamp).zip", isDirectory: false)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        var coordinatorError: NSError?
        var copyError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(
            readingItemAt: directory,
            options: .forUploading,
            error: &coordinatorError
        ) { archiveURL in
            do {
                try fileManager.copyItem(at: archiveURL, to: destination)
            } catch {
                copyError = error
            }
        }
        if let copyError {
            throw copyError
        }
        if let coordinatorError {
            throw coordinatorError
        }
        return destination
    }

    private func archiveByteCount(_ archiveURL: URL) throws -> Int {
        let attributes = try fileManager.attributesOfItem(atPath: archiveURL.path)
        guard let size = attributes[.size] as? NSNumber else { return 0 }
        return max(0, size.intValue)
    }

    private func renderSummary() -> String {
        var lines = [
            "Making Tracks diagnostics",
            "app=\(metadata.appVersion) build=\(metadata.build) commit=\(metadata.commit)",
            "system=\(metadata.deviceModel) \(metadata.osVersion)",
            "installed-packs:",
        ]
        lines.append(contentsOf: metadata.installedPacks.map {
            "pack=\($0.id) publish=\($0.publishVersion) state=\($0.state)"
        })
        lines.append("not-included=places-viewed,saved,loved,hidden,searches,lists,location,viewport,device-name")
        return lines.joined(separator: "\n") + "\n"
    }

    private func renderDecodeTable(log: String) throws -> String {
        var entries: [String: String] = [:]
        let values = Set(knownObjects + metadata.installedPacks.flatMap { [$0.id, "\($0.id)/\($0.publishVersion)"] })
        for value in values {
            entries[store.hashObject(value)] = value
        }
        let logHashes = Self.objectHashes(in: log)
        for (hash, plaintext) in try store.snapshotObjectDecodeEntries() where logHashes.contains(hash) {
            entries[hash] = plaintext
        }
        var lines = ["hash\tplaintext"]
        lines.append(contentsOf: entries.sorted { $0.key < $1.key }.map { "\($0.key)\t\($0.value)" })
        return lines.joined(separator: "\n") + "\n"
    }

    private func renderPreview(summary: String, log: String, decodeTable: String) -> String {
        [
            "metadata:",
            summary.trimmingCharacters(in: .whitespacesAndNewlines),
            "log:",
            log.trimmingCharacters(in: .whitespacesAndNewlines),
            "decode-table:",
            decodeTable.trimmingCharacters(in: .whitespacesAndNewlines),
        ].joined(separator: "\n")
    }

    private static func passesPrivacyScrub(_ text: String) -> Bool {
        let forbiddenPatterns = [
            #"\bmt[0-9a-zA-Z_]{20,}\b"#,
            #"[-+]?\d{1,3}\.\d{4,}"#,
            #"(?i)\bplace[_-]?id\b"#,
            #"(?i)\blat(?:itude)?\b"#,
            #"(?i)\blon(?:gitude)?\b"#,
        ]
        return forbiddenPatterns.allSatisfy { pattern in
            text.range(of: pattern, options: .regularExpression) == nil
        }
    }

    private static func objectHashes(in log: String) -> Set<String> {
        let matches = log.matches(of: /h:[0-9a-f]{16}/)
        return Set(matches.map { String($0.output) })
    }

    private static func filenameTimestampFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter
    }
}

private extension DiagnosticLogStore {
    static func setDiagnosticsResourceValuesForExporter(_ url: URL) throws {
        try setDiagnosticsResourceValues(url)
    }
}
