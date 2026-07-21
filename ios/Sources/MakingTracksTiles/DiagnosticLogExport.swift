import Foundation

public enum DiagnosticLogCategory: String, Sendable {
    case downloads
    case flow
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
    public var byteCount: Int
    public var preview: String
}

struct DiagnosticLogSnapshot: Equatable, Sendable {
    var totalLineCount: Int
    var lines: [String]

    var windowLineCount: Int {
        lines.count
    }
}

struct DiagnosticLogWindowedSnapshot: Equatable, Sendable {
    var window: DiagnosticLogWindow
    var snapshot: DiagnosticLogSnapshot
}

struct DiagnosticVisiblePreview: Equatable, Sendable {
    var text: String
    var logLineCount: Int
    var omittedLogLineCount: Int

    var isCapped: Bool {
        omittedLogLineCount > 0
    }
}

public enum DiagnosticLogExportError: Error, Equatable {
    case privacyScrubFailed
}

public final class DiagnosticLogStore {
    public let root: URL
    private let now: @Sendable () -> Date
    private let fileManager: FileManager
    private let lock = NSLock()

    public init(
        root: URL,
        now: @escaping @Sendable () -> Date = Date.init,
        fileManager: FileManager = .default
    ) {
        self.root = root
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
        let renderedFields = fields.map { field in
            switch field {
            case let .public(name, value):
                return "\(name)=\(Self.sanitizePublicValue(value))"
            case let .object(name, value):
                return "\(name)=\(Self.sanitizePublicValue(value))"
            }
        }
        let line = ([timestamp, category.rawValue, level.rawValue, message] + renderedFields)
            .joined(separator: " ")
        try appendRawLine(line)
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
        try snapshot(window: window).lines
    }

    func sessionCoveringWindow(preferredWindow: DiagnosticLogWindow) throws -> DiagnosticLogWindow {
        lock.lock()
        defer { lock.unlock() }
        let allLines = try readAllLinesLocked()
        return sessionCoveringWindowLocked(preferredWindow: preferredWindow, allLines: allLines)
    }

    func snapshot(window: DiagnosticLogWindow) throws -> DiagnosticLogSnapshot {
        lock.lock()
        defer { lock.unlock() }
        let allLines = try readAllLinesLocked()
        return snapshotLocked(window: window, allLines: allLines)
    }

    func snapshotCoveringCurrentSession(preferredWindow: DiagnosticLogWindow) throws -> DiagnosticLogWindowedSnapshot {
        lock.lock()
        defer { lock.unlock() }
        let allLines = try readAllLinesLocked()
        let window = sessionCoveringWindowLocked(preferredWindow: preferredWindow, allLines: allLines)
        return DiagnosticLogWindowedSnapshot(window: window, snapshot: snapshotLocked(window: window, allLines: allLines))
    }

    func appendRawLineForTesting(_ line: String) throws {
        try appendRawLine(line)
    }

    private var logURL: URL {
        root.appendingPathComponent("making-tracks.log", isDirectory: false)
    }

    private func readAllLinesLocked() throws -> [String] {
        let current = logURL
        guard fileManager.fileExists(atPath: current.path) else { return [] }
        let text = try String(contentsOf: current, encoding: .utf8)
        return text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }

    private func sessionCoveringWindowLocked(preferredWindow: DiagnosticLogWindow, allLines: [String]) -> DiagnosticLogWindow {
        let dates = allLines.compactMap { Self.dateFromLine($0) }
        guard !dates.isEmpty else { return preferredWindow }
        return DiagnosticLogWindow.sessionCoveringCandidates(from: preferredWindow)
            .first { candidate in
                dates.allSatisfy { candidate.contains($0, relativeTo: now()) }
            } ?? .everything
    }

    private func snapshotLocked(window: DiagnosticLogWindow, allLines: [String]) -> DiagnosticLogSnapshot {
        let referenceNow = now()
        let windowLines = allLines.filter { line in
            guard let date = Self.dateFromLine(line) else { return true }
            return window.contains(date, relativeTo: referenceNow)
        }
        return DiagnosticLogSnapshot(totalLineCount: allLines.count, lines: windowLines)
    }

    private func appendRawLine(_ line: String) throws {
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
    private static let maxVisiblePreviewLogLines = 100

    private let store: DiagnosticLogStore
    private let metadata: DiagnosticLogMetadata
    private let fileManager: FileManager
    private let exportedAt: @Sendable () -> Date

    public init(
        store: DiagnosticLogStore,
        metadata: DiagnosticLogMetadata,
        fileManager: FileManager = .default,
        exportedAt: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = store
        self.metadata = metadata
        self.fileManager = fileManager
        self.exportedAt = exportedAt
    }

    public func prepare(window: DiagnosticLogWindow, stagingRoot: URL) throws -> DiagnosticLogArtifact {
        try prepare(windowedSnapshot: DiagnosticLogWindowedSnapshot(window: window, snapshot: store.snapshot(window: window)), stagingRoot: stagingRoot)
    }

    private func prepare(windowedSnapshot: DiagnosticLogWindowedSnapshot, stagingRoot: URL) throws -> DiagnosticLogArtifact {
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

            let window = windowedSnapshot.window
            let snapshot = windowedSnapshot.snapshot
            let log = snapshot.lines.joined(separator: "\n") + "\n"
            let summary = renderSummary(
                window: window,
                snapshot: snapshot,
                scrubStatus: "pending",
                previewLineCount: 0,
                previewLogLineCount: 0,
                omittedPreviewLogLineCount: 0
            )
            let scrubText = [summary, log].joined(separator: "\n")
            guard Self.passesPrivacyScrub(scrubText) else {
                throw DiagnosticLogExportError.privacyScrubFailed
            }
            let previewLogLineCount = Self.lineCount(in: log)
            let visiblePreview = renderVisiblePreview(summary: summary, logLines: snapshot.lines)
            let summaryForPreviewCounts = renderSummary(
                window: window,
                snapshot: snapshot,
                scrubStatus: "passed",
                previewLineCount: 0,
                previewLogLineCount: previewLogLineCount,
                omittedPreviewLogLineCount: visiblePreview.omittedLogLineCount
            )
            let visiblePreviewForCounts = renderVisiblePreview(summary: summaryForPreviewCounts, logLines: snapshot.lines)
            let previewLineCount = Self.lineCount(in: visiblePreviewForCounts.text)
            let exportedSummary = renderSummary(
                window: window,
                snapshot: snapshot,
                scrubStatus: "passed",
                previewLineCount: previewLineCount,
                previewLogLineCount: previewLogLineCount,
                omittedPreviewLogLineCount: visiblePreview.omittedLogLineCount
            )
            let exportedVisiblePreview = renderVisiblePreview(summary: exportedSummary, logLines: snapshot.lines)

            try exportedSummary.write(to: summaryURL, atomically: true, encoding: .utf8)
            try log.write(to: logURL, atomically: true, encoding: .utf8)
            let archiveURL = try makeArchive(directory: directory, stagingRoot: stagingRoot, exportTimestamp: exportTimestamp)
            let byteCount = try archiveByteCount(archiveURL)

            return DiagnosticLogArtifact(
                directoryURL: directory,
                archiveURL: archiveURL,
                summaryURL: summaryURL,
                logURL: logURL,
                byteCount: byteCount,
                preview: exportedVisiblePreview.text
            )
        } catch {
            if fileManager.fileExists(atPath: stagingRoot.path) {
                try? fileManager.removeItem(at: stagingRoot)
            }
            throw error
        }
    }

    public func prepareCoveringCurrentSession(
        preferredWindow: DiagnosticLogWindow,
        stagingRoot: URL
    ) throws -> DiagnosticLogArtifact {
        let snapshot = try store.snapshotCoveringCurrentSession(preferredWindow: preferredWindow)
        return try prepare(windowedSnapshot: snapshot, stagingRoot: stagingRoot)
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

    private func renderSummary(
        window: DiagnosticLogWindow,
        snapshot: DiagnosticLogSnapshot,
        scrubStatus: String,
        previewLineCount: Int,
        previewLogLineCount: Int,
        omittedPreviewLogLineCount: Int
    ) -> String {
        var lines = [
            "Making Tracks diagnostics",
            "app=\(metadata.appVersion) build=\(metadata.build) commit=\(metadata.commit)",
            "system=\(metadata.deviceModel) \(metadata.osVersion)",
            "installed-packs:",
        ]
        lines.append(contentsOf: metadata.installedPacks.map {
            "pack=\($0.id) publish=\($0.publishVersion) state=\($0.state)"
        })
        lines.append("included=app-version,device-model,installed-packs,session-flow,object-urls,error-codes,timings")
        lines.append("not-included=device-name,exact-location,search-wording")
        lines.append("log-stage=raw lines=\(snapshot.totalLineCount)")
        lines.append("log-stage=window input-lines=\(snapshot.totalLineCount) output-lines=\(snapshot.windowLineCount) window=\(window.exportLabel)")
        lines.append("log-stage=scrub input-log-lines=\(snapshot.windowLineCount) output-log-lines=\(snapshot.windowLineCount) status=\(scrubStatus)")
        lines.append("log-stage=preview lines=\(previewLineCount) log-lines=\(previewLogLineCount)")
        let visiblePreviewStatus = omittedPreviewLogLineCount > 0 ? "capped" : "complete"
        lines.append("visible-preview=\(visiblePreviewStatus) max-log-lines=\(Self.maxVisiblePreviewLogLines) omitted-log-lines=\(omittedPreviewLogLineCount)")
        return lines.joined(separator: "\n") + "\n"
    }

    private func renderVisiblePreview(summary: String, logLines: [String]) -> DiagnosticVisiblePreview {
        let omittedLineCount = max(0, logLines.count - Self.maxVisiblePreviewLogLines)
        let visibleLogLines = Array(logLines.suffix(Self.maxVisiblePreviewLogLines))
        var parts = [
            "metadata:",
            summary.trimmingCharacters(in: .whitespacesAndNewlines),
            "log:",
        ]
        if omittedLineCount > 0 {
            parts.append("preview capped: showing last \(visibleLogLines.count) of \(logLines.count) log lines; full log is in the archive.")
        }
        parts.append(visibleLogLines.joined(separator: "\n"))
        return DiagnosticVisiblePreview(
            text: parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
            logLineCount: visibleLogLines.count,
            omittedLogLineCount: omittedLineCount
        )
    }

    private static func passesPrivacyScrub(_ text: String) -> Bool {
        let forbiddenPatterns = [
            #"(?i)\bdeviceName\b"#,
            #"UIDevice\s*\.\s*current\s*\.\s*name"#,
            #"(?i)\bgps[A-Za-z]*(lat|lon|latitude|longitude)\b"#,
            #"(?i)\blocation\s*\.\s*coordinate\s*\.\s*(latitude|longitude)"#,
            #"(?i)\bviewport(Center|Bbox)\b"#,
            #"(?i)\bbbox\b"#,
            #"(?i)\bcenter\b"#,
            #"(?i)\btile[XY]\b"#,
            #"(?i)\braw(Search)?Query\b"#,
            #"(?i)\bsearchQuery\b"#,
            #"(?i)\bqueryText\b"#,
        ]
        return forbiddenPatterns.allSatisfy { pattern in
            text.range(of: pattern, options: .regularExpression) == nil
        }
    }

    private static func lineCount(in text: String) -> Int {
        text.split(separator: "\n", omittingEmptySubsequences: true).count
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

private extension DiagnosticLogWindow {
    static func sessionCoveringCandidates(from preferredWindow: DiagnosticLogWindow) -> [DiagnosticLogWindow] {
        switch preferredWindow {
        case .fifteenMinutes:
            return [.fifteenMinutes, .lastHour, .everything]
        case .lastHour:
            return [.lastHour, .everything]
        case .everything:
            return [.everything]
        }
    }

    var exportLabel: String {
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

private extension DiagnosticLogStore {
    static func setDiagnosticsResourceValuesForExporter(_ url: URL) throws {
        try setDiagnosticsResourceValues(url)
    }
}
