import Foundation
import XCTest
import MakingTracksTiles
@testable import MakingTracks

final class DiagnosticsRuntimeTests: XCTestCase {
    func testDetachedPreparationOperationObservesParentCancellation() async throws {
        let started = DispatchSemaphore(value: 0)
        let cancellationObserved = DispatchSemaphore(value: 0)
        let task = Task.detached {
            try await DiagnosticsRuntime.runCancellableDetachedOperation { () throws -> Int in
                started.signal()
                while !Task.isCancelled {
                    Thread.sleep(forTimeInterval: 0.001)
                }
                cancellationObserved.signal()
                throw CancellationError()
            }
        }

        XCTAssertEqual(started.wait(timeout: .now() + 2), .success)
        task.cancel()
        XCTAssertEqual(cancellationObserved.wait(timeout: .now() + 2), .success)
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        }
    }

    func testCancelledPreparationAttemptRemovesOnlyItsLateStagingRoot() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiagnosticsCancellationTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let successor = base.appendingPathComponent("successor", isDirectory: true)
        try FileManager.default.createDirectory(at: successor, withIntermediateDirectories: true)
        try Data("new attempt".utf8).write(to: successor.appendingPathComponent("archive.zip"))

        let started = DispatchSemaphore(value: 0)
        let finishLate = DispatchSemaphore(value: 0)
        let task = Task.detached {
            try await DiagnosticsRuntime.runPreparationAttempt(stagingBase: base) { attemptRoot in
                started.signal()
                finishLate.wait()
                try FileManager.default.createDirectory(at: attemptRoot, withIntermediateDirectories: true)
                try Data("abandoned attempt".utf8).write(
                    to: attemptRoot.appendingPathComponent("archive.zip")
                )
                return attemptRoot
            }
        }

        XCTAssertEqual(started.wait(timeout: .now() + 2), .success)
        task.cancel()
        finishLate.signal()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: successor.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: base.path), ["successor"])
    }

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
