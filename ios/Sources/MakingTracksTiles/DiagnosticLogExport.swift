import Foundation
import Dispatch

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

    fileprivate func cutoff(relativeTo now: Date) -> Date? {
        switch self {
        case .fifteenMinutes:
            return now.addingTimeInterval(-15 * 60)
        case .lastHour:
            return now.addingTimeInterval(-60 * 60)
        case .everything:
            return nil
        }
    }

    fileprivate func contains(_ date: Date, relativeTo now: Date) -> Bool {
        guard let cutoff = cutoff(relativeTo: now) else { return true }
        return date >= cutoff
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
    public var phaseTimings: [DiagnosticLogPreparePhaseTiming]
}

public struct DiagnosticLogPreparePhaseTiming: Equatable, Sendable {
    public var phase: String
    public var durationMilliseconds: Int
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

private struct DiagnosticLogPreparePhaseTimings: Equatable, Sendable {
    private(set) var entries: [DiagnosticLogPreparePhaseTiming] = []

    mutating func measure<T>(_ phase: String, _ work: () throws -> T) rethrows -> T {
        let startedAt = Self.now()
        defer {
            append(phase, startedAt: startedAt)
        }
        return try work()
    }

    mutating func append(_ phase: String, startedAt: UInt64) {
        entries.append(
            DiagnosticLogPreparePhaseTiming(
                phase: phase,
                durationMilliseconds: Self.durationMilliseconds(since: startedAt)
            )
        )
    }

    static func now() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    private static func durationMilliseconds(since startedAt: UInt64) -> Int {
        let elapsed = DispatchTime.now().uptimeNanoseconds - startedAt
        return Int(elapsed / 1_000_000)
    }
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
        guard let cutoff = window.cutoff(relativeTo: now()) else {
            return DiagnosticLogSnapshot(totalLineCount: allLines.count, lines: allLines)
        }
        let firstIncludedSecond = Date(
            timeIntervalSince1970: cutoff.timeIntervalSince1970.rounded(.up)
        )
        let cutoffToken = Self.timestampFormatter().string(from: firstIncludedSecond)
        let windowLines = allLines.filter { line in
            guard let timestamp = Self.canonicalTimestampToken(from: line) else { return true }
            return timestamp >= cutoffToken[...]
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

    private static func canonicalTimestampToken(from line: String) -> Substring? {
        guard let token = line.split(separator: " ", maxSplits: 1).first else { return nil }
        let bytes = Array(token.utf8)
        guard bytes.count == 20,
              bytes[4] == Character("-").asciiValue,
              bytes[7] == Character("-").asciiValue,
              bytes[10] == Character("T").asciiValue,
              bytes[13] == Character(":").asciiValue,
              bytes[16] == Character(":").asciiValue,
              bytes[19] == Character("Z").asciiValue
        else {
            return nil
        }
        let digitPositions = [0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17, 18]
        guard digitPositions.allSatisfy({ (48...57).contains(bytes[$0]) }) else { return nil }

        func decimal(_ first: Int, _ second: Int) -> Int {
            Int(bytes[first] - 48) * 10 + Int(bytes[second] - 48)
        }
        let year = decimal(0, 1) * 100 + decimal(2, 3)
        let month = decimal(5, 6)
        let day = decimal(8, 9)
        let hour = decimal(11, 12)
        let minute = decimal(14, 15)
        let second = decimal(17, 18)
        guard year > 0,
              (1...12).contains(month),
              (1...daysInMonth(month, year: year)).contains(day),
              (0...23).contains(hour),
              (0...59).contains(minute),
              (0...59).contains(second)
        else {
            return nil
        }
        return token
    }

    private static func daysInMonth(_ month: Int, year: Int) -> Int {
        switch month {
        case 2:
            let isLeapYear = year.isMultiple(of: 400)
                || (year.isMultiple(of: 4) && !year.isMultiple(of: 100))
            return isLeapYear ? 29 : 28
        case 4, 6, 9, 11:
            return 30
        default:
            return 31
        }
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
        try Task.checkCancellation()
        var timings = DiagnosticLogPreparePhaseTimings()
        let totalStartedAt = DiagnosticLogPreparePhaseTimings.now()
        let snapshot = try timings.measure("snapshot") {
            try store.snapshot(window: window)
        }
        try Task.checkCancellation()
        return try prepare(
            windowedSnapshot: DiagnosticLogWindowedSnapshot(window: window, snapshot: snapshot),
            stagingRoot: stagingRoot,
            timings: timings,
            totalStartedAt: totalStartedAt
        )
    }

    private func prepare(
        windowedSnapshot: DiagnosticLogWindowedSnapshot,
        stagingRoot: URL,
        timings initialTimings: DiagnosticLogPreparePhaseTimings,
        totalStartedAt: UInt64
    ) throws -> DiagnosticLogArtifact {
        var timings = initialTimings
        try timings.measure("stage-clean") {
            if fileManager.fileExists(atPath: stagingRoot.path) {
                try fileManager.removeItem(at: stagingRoot)
            }
        }
        try Task.checkCancellation()
        let exportTimestamp = Self.filenameTimestampFormatter().string(from: exportedAt())
        let directory = stagingRoot.appendingPathComponent("MakingTracksDiagnostics-\(exportTimestamp)", isDirectory: true)
        do {
            try timings.measure("stage-create") {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                try DiagnosticLogStore.setDiagnosticsResourceValuesForExporter(directory)
            }
            try Task.checkCancellation()

            let summaryURL = directory.appendingPathComponent("summary-\(exportTimestamp).txt")
            let logURL = directory.appendingPathComponent("diagnostic-log-\(exportTimestamp).txt")

            let window = windowedSnapshot.window
            let snapshot = windowedSnapshot.snapshot
            let log = timings.measure("log-render") {
                snapshot.lines.joined(separator: "\n") + "\n"
            }
            let summary = renderSummary(
                window: window,
                snapshot: snapshot,
                scrubStatus: "pending",
                previewLineCount: 0,
                previewLogLineCount: 0,
                omittedPreviewLogLineCount: 0,
                phaseTimings: timings.entries
            )
            let scrubText = [summary, log].joined(separator: "\n")
            let passedScrub = timings.measure("scrub") {
                Self.passesPrivacyScrub(scrubText)
            }
            guard passedScrub else {
                throw DiagnosticLogExportError.privacyScrubFailed
            }
            try Task.checkCancellation()
            let previewPhaseTimings = timings.entries + [
                DiagnosticLogPreparePhaseTiming(phase: "preview", durationMilliseconds: 0),
            ]
            let previewRender = timings.measure("preview") {
                renderSummaryAndVisiblePreview(
                    window: window,
                    snapshot: snapshot,
                    scrubStatus: "passed",
                    phaseTimings: previewPhaseTimings
                )
            }

            try timings.measure("write-files") {
                try previewRender.summary.write(to: summaryURL, atomically: true, encoding: .utf8)
                try log.write(to: logURL, atomically: true, encoding: .utf8)
            }
            try Task.checkCancellation()
            let archiveURL = try timings.measure("archive") {
                try makeArchive(directory: directory, stagingRoot: stagingRoot, exportTimestamp: exportTimestamp)
            }
            try Task.checkCancellation()
            let byteCount = try timings.measure("byte-count") {
                try archiveByteCount(archiveURL)
            }
            timings.append("total", startedAt: totalStartedAt)
            let finalPreview = renderSummaryAndVisiblePreview(
                window: window,
                snapshot: snapshot,
                scrubStatus: "passed",
                phaseTimings: timings.entries
            ).preview

            return DiagnosticLogArtifact(
                directoryURL: directory,
                archiveURL: archiveURL,
                summaryURL: summaryURL,
                logURL: logURL,
                byteCount: byteCount,
                preview: finalPreview.text,
                phaseTimings: timings.entries
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
        var timings = DiagnosticLogPreparePhaseTimings()
        let totalStartedAt = DiagnosticLogPreparePhaseTimings.now()
        let snapshot = try timings.measure("snapshot") {
            try store.snapshotCoveringCurrentSession(preferredWindow: preferredWindow)
        }
        return try prepare(
            windowedSnapshot: snapshot,
            stagingRoot: stagingRoot,
            timings: timings,
            totalStartedAt: totalStartedAt
        )
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
        omittedPreviewLogLineCount: Int,
        phaseTimings: [DiagnosticLogPreparePhaseTiming]
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
        lines.append(contentsOf: phaseTimings.map {
            "prepare-phase=\($0.phase) duration-ms=\($0.durationMilliseconds)"
        })
        return lines.joined(separator: "\n") + "\n"
    }

    private func renderSummaryAndVisiblePreview(
        window: DiagnosticLogWindow,
        snapshot: DiagnosticLogSnapshot,
        scrubStatus: String,
        phaseTimings: [DiagnosticLogPreparePhaseTiming]
    ) -> (summary: String, preview: DiagnosticVisiblePreview) {
        let omittedPreviewLogLineCount = max(0, snapshot.windowLineCount - Self.maxVisiblePreviewLogLines)
        var previewLineCount = 0
        var summary = ""
        var preview = DiagnosticVisiblePreview(text: "", logLineCount: 0, omittedLogLineCount: omittedPreviewLogLineCount)
        for _ in 0..<3 {
            summary = renderSummary(
                window: window,
                snapshot: snapshot,
                scrubStatus: scrubStatus,
                previewLineCount: previewLineCount,
                previewLogLineCount: snapshot.windowLineCount,
                omittedPreviewLogLineCount: omittedPreviewLogLineCount,
                phaseTimings: phaseTimings
            )
            preview = renderVisiblePreview(summary: summary, logLines: snapshot.lines)
            let measuredPreviewLineCount = Self.lineCount(in: preview.text)
            if measuredPreviewLineCount == previewLineCount {
                break
            }
            previewLineCount = measuredPreviewLineCount
        }
        return (summary, preview)
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
        let lowercased = text.lowercased()
        let compacted = lowercased.filter { !$0.isWhitespace }
        guard !compacted.contains("uidevice.current.name"),
              !compacted.contains("location.coordinate.latitude"),
              !compacted.contains("location.coordinate.longitude")
        else {
            return false
        }

        let tokens = lowercased.split { !$0.isLetter && !$0.isNumber }
        for token in tokens {
            if Self.isForbiddenPrivacyToken(token) {
                return false
            }
        }
        return true
    }

    private static func isForbiddenPrivacyToken(_ token: Substring) -> Bool {
        switch token {
        case "devicename",
            "viewportcenter",
            "viewportbbox",
            "bbox",
            "center",
            "tilex",
            "tiley",
            "rawquery",
            "rawsearchquery",
            "searchquery",
            "querytext":
            return true
        default:
            return token.hasPrefix("gps") && (token.contains("lat") || token.contains("lon"))
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
