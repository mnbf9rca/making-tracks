import Foundation
import XCTest
import MakingTracksTiles
@testable import MakingTracks

final class DiagnosticsRuntimeTests: XCTestCase {
    func testPrepareArtifactRequestHonorsLastHourWindow() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiagnosticsRuntimeTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let logs = root.appendingPathComponent("logs", isDirectory: true)
        let staging = root.appendingPathComponent("staging", isDirectory: true)
        let now = Date(timeIntervalSince1970: 1_785_000_000)
        let old = now.addingTimeInterval(-2 * 60 * 60)
        try DiagnosticLogStore(root: logs, now: { old }).append(
            category: .startup,
            level: .info,
            message: "old diagnostic line",
            fields: []
        )
        let store = DiagnosticLogStore(root: logs, now: { now })
        try store.append(
            category: .startup,
            level: .info,
            message: "current diagnostic line",
            fields: []
        )
        let metadata = DiagnosticLogMetadata(
            appVersion: "test",
            build: "1",
            commit: "abcdef0",
            osVersion: "iOS test",
            deviceModel: "simulator",
            installedPacks: []
        )

        let artifact = try DiagnosticsRuntime.prepareArtifact(
            request: DiagnosticsExportRequest(selectedWindow: .lastHour),
            store: store,
            metadata: metadata,
            stagingRoot: staging,
            exportedAt: { now }
        )
        let log = try String(contentsOf: artifact.logURL, encoding: .utf8)
        let summary = try String(contentsOf: artifact.summaryURL, encoding: .utf8)

        XCTAssertTrue(log.contains("current diagnostic line"), log)
        XCTAssertFalse(log.contains("old diagnostic line"), log)
        XCTAssertTrue(summary.contains("window=last-hour"), summary)
        XCTAssertFalse(summary.contains("window=everything"), summary)
    }
}
