import Foundation
import XCTest
@testable import MakingTracksTiles

final class DiagnosticLogExportTests: XCTestCase {
    func testExportNamesMalaysiaCurrent404ThroughHashDecodeTable() throws {
        let fixture = try makeFixture()
        let objectPath = "/malaysia-singapore-brunei/20260719T125813Z/current.json"
        let store = DiagnosticLogStore(root: fixture.logs, salt: fixture.salt, now: { fixture.now })
        try store.append(
            category: .resolution,
            level: .error,
            message: "fetch failed",
            fields: [
                .public("host", "tiles.making-tracks.app"),
                .public("status", "http-404"),
                .object("object", objectPath),
            ]
        )

        let artifact = try DiagnosticLogExporter(
            store: store,
            metadata: fixture.metadata,
            knownObjects: [objectPath]
        ).prepare(window: .everything, stagingRoot: fixture.staging)

        let log = try String(contentsOf: artifact.logURL, encoding: .utf8)
        let decodeTable = try String(contentsOf: artifact.decodeTableURL, encoding: .utf8)
        let summary = try String(contentsOf: artifact.summaryURL, encoding: .utf8)

        XCTAssertTrue(log.contains("host=tiles.making-tracks.app"))
        XCTAssertTrue(log.contains("status=http-404"))
        XCTAssertFalse(log.contains(objectPath), log)
        XCTAssertTrue(decodeTable.contains("\(store.hashObject(objectPath))\t\(objectPath)"))
        XCTAssertTrue(summary.contains("pack=malaysia-singapore-brunei publish=20260719T125813Z state=installed"))
        XCTAssertTrue(artifact.preview.contains("decode-table:"))
        XCTAssertTrue(artifact.preview.contains("malaysia-singapore-brunei"))
    }

    func testExportOmitsPromisedUserDataClasses() throws {
        let fixture = try makeFixture()
        let store = DiagnosticLogStore(root: fixture.logs, salt: fixture.salt, now: { fixture.now })
        try store.append(
            category: .downloads,
            level: .info,
            message: "region download finished",
            fields: [
                .object("region", "malaysia-singapore-brunei"),
                .public("bytes", "1200"),
            ]
        )

        let artifact = try DiagnosticLogExporter(
            store: store,
            metadata: fixture.metadata,
            knownObjects: ["malaysia-singapore-brunei"]
        ).prepare(window: .everything, stagingRoot: fixture.staging)

        let bundleText = try [
            artifact.summaryURL,
            artifact.logURL,
            artifact.decodeTableURL,
        ].map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")

        for forbidden in [
            "mt1_00000000000000000000000001",
            "Petronas Towers",
            "coffee near me",
            "Favorites",
            "51.5074",
            "-0.1278",
            "Rob's iPhone",
        ] {
            XCTAssertFalse(bundleText.contains(forbidden), forbidden)
        }
    }

    func testExportScrubFailsClosedForPlaceIdentifiersAndCoordinates() throws {
        let fixture = try makeFixture()
        let store = DiagnosticLogStore(root: fixture.logs, salt: fixture.salt, now: { fixture.now })
        try store.appendRawLineForTesting("2026-07-19T12:58:13Z resolution error place_id=mt1_00000000000000000000000001 lat=51.5074")

        XCTAssertThrowsError(try DiagnosticLogExporter(
            store: store,
            metadata: fixture.metadata,
            knownObjects: []
        ).prepare(window: .everything, stagingRoot: fixture.staging)) { error in
            XCTAssertEqual(error as? DiagnosticLogExportError, .privacyScrubFailed)
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.staging.path))
    }

    func testDeleteDiagnosticsClearsLogsAndStaging() throws {
        let fixture = try makeFixture()
        let store = DiagnosticLogStore(root: fixture.logs, salt: fixture.salt, now: { fixture.now })
        try store.append(category: .startup, level: .info, message: "app init finished", fields: [])
        try FileManager.default.createDirectory(at: fixture.staging, withIntermediateDirectories: true)
        try "staged".write(to: fixture.staging.appendingPathComponent("old.txt"), atomically: true, encoding: .utf8)

        try store.deleteDiagnostics(stagingRoot: fixture.staging)

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.logs.path), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.staging.path))
    }

    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiagnosticLogExportTests-\(UUID().uuidString)", isDirectory: true)
        let logs = root.appendingPathComponent("logs", isDirectory: true)
        let staging = root.appendingPathComponent("staging", isDirectory: true)
        let now = Date(timeIntervalSince1970: 1_784_463_493)
        let metadata = DiagnosticLogMetadata(
            appVersion: "1.0",
            build: "42",
            commit: "abcdef0",
            osVersion: "iOS 18.6",
            deviceModel: "iPhone17,3",
            installedPacks: [
                DiagnosticInstalledPack(
                    id: "malaysia-singapore-brunei",
                    publishVersion: "20260719T125813Z",
                    state: "installed"
                ),
            ]
        )
        return Fixture(
            logs: logs,
            staging: staging,
            salt: Data("test-install-salt".utf8),
            now: now,
            metadata: metadata
        )
    }
}

private struct Fixture {
    let logs: URL
    let staging: URL
    let salt: Data
    let now: Date
    let metadata: DiagnosticLogMetadata
}
