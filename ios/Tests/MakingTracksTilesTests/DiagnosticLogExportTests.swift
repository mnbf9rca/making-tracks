import Foundation
import XCTest
@testable import MakingTracksTiles

final class DiagnosticLogExportTests: XCTestCase {
    func testExportNamesMalaysiaCurrent404DirectlyInDiagnosticLog() throws {
        let fixture = try makeFixture()
        let objectPath = "/malaysia-singapore-brunei/20260719T125813Z/current.json"
        let store = DiagnosticLogStore(root: fixture.logs, now: { fixture.now })
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
            metadata: fixture.metadata
        ).prepare(window: .everything, stagingRoot: fixture.staging)

        let log = try String(contentsOf: artifact.logURL, encoding: .utf8)
        let summary = try String(contentsOf: artifact.summaryURL, encoding: .utf8)

        XCTAssertTrue(log.contains("host=tiles.making-tracks.app"))
        XCTAssertTrue(log.contains("status=http-404"))
        XCTAssertTrue(log.contains("object=\(objectPath)"))
        XCTAssertTrue(summary.contains("pack=malaysia-singapore-brunei publish=20260719T125813Z state=installed"))
        XCTAssertTrue(summary.contains("included=app-version,device-model,installed-packs,session-flow,object-urls,error-codes,timings"))
        XCTAssertTrue(summary.contains("not-included=device-name,exact-location,search-wording"))
        XCTAssertTrue(artifact.preview.contains("log:"))
        XCTAssertTrue(artifact.preview.contains(objectPath))
        XCTAssertFalse(artifact.preview.contains("decode-table:"))
    }

    func testFlowHelpersRenderReadableSessionEvents() throws {
        let fixture = try makeFixture()
        let store = DiagnosticLogStore(root: fixture.logs, now: { fixture.now })
        MakingTracksLog.configureDiagnosticLogStore(store)
        defer { MakingTracksLog.configureDiagnosticLogStore(nil) }

        MakingTracksLog.flowEvent(
            "place viewed",
            fields: [
                .object("placeID", "mt1_00000000000000000000000001"),
                .object("placeName", "Cheong Fatt Tze Mansion"),
                .public("source", "card"),
            ]
        )
        MakingTracksLog.flowEvent(
            "verdict changed",
            fields: [
                .object("placeID", "mt1_00000000000000000000000001"),
                .public("action", "love"),
                .public("state", "on"),
            ]
        )
        MakingTracksLog.viewportFlowEvent(
            region: "malaysia-singapore-brunei",
            zoom: 14,
            tileZ: 10,
            covered: 12,
            requests: 9,
            blocked: 3,
            source: "pan"
        )

        let log = try store.snapshotLines(window: .everything).joined(separator: "\n")

        XCTAssertTrue(log.contains("flow info place viewed placeID=mt1_00000000000000000000000001 placeName=Cheong Fatt Tze Mansion source=card"), log)
        XCTAssertTrue(log.contains("flow info verdict changed placeID=mt1_00000000000000000000000001 action=love state=on"), log)
        XCTAssertTrue(log.contains("flow info viewport browsed region=malaysia-singapore-brunei zoom=14 tileZ=10 covered=12 requests=9 blocked=3 source=pan"), log)
        XCTAssertFalse(log.contains("bbox="), log)
        XCTAssertFalse(log.contains("center="), log)
    }

    func testExportDoesNotCreateDecodeTable() throws {
        let fixture = try makeFixture()
        let store = DiagnosticLogStore(root: fixture.logs, now: { fixture.now })
        try store.append(category: .startup, level: .info, message: "app init finished", fields: [])

        let artifact = try DiagnosticLogExporter(
            store: store,
            metadata: fixture.metadata,
            exportedAt: { fixture.now }
        ).prepare(window: .everything, stagingRoot: fixture.staging)

        let files = try FileManager.default.contentsOfDirectory(atPath: artifact.directoryURL.path)

        XCTAssertEqual(Set(files), [
            "diagnostic-log-20260719T121813Z.txt",
            "summary-20260719T121813Z.txt",
        ])
        XCTAssertFalse(files.contains { $0.contains("decode-table") })
    }

    func testExportOmitsPromisedUserDataClasses() throws {
        let fixture = try makeFixture()
        let store = DiagnosticLogStore(root: fixture.logs, now: { fixture.now })
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
            metadata: fixture.metadata
        ).prepare(window: .everything, stagingRoot: fixture.staging)

        let bundleText = try [
            artifact.summaryURL,
            artifact.logURL,
        ].map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")

        XCTAssertTrue(bundleText.contains("region=malaysia-singapore-brunei"))
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

    func testExportUsesTimestampedArchiveAndMemberNames() throws {
        let fixture = try makeFixture()
        let store = DiagnosticLogStore(root: fixture.logs, now: { fixture.now })
        try store.append(category: .startup, level: .info, message: "app init finished", fields: [])

        let artifact = try DiagnosticLogExporter(
            store: store,
            metadata: fixture.metadata,
            exportedAt: { fixture.now }
        ).prepare(window: .everything, stagingRoot: fixture.staging)

        XCTAssertEqual(artifact.directoryURL.lastPathComponent, "MakingTracksDiagnostics-20260719T121813Z")
        XCTAssertEqual(artifact.archiveURL.lastPathComponent, "MakingTracksDiagnostics-20260719T121813Z.zip")
        XCTAssertEqual(artifact.summaryURL.lastPathComponent, "summary-20260719T121813Z.txt")
        XCTAssertEqual(artifact.logURL.lastPathComponent, "diagnostic-log-20260719T121813Z.txt")
    }

    func testPreparedArtifactReportsArchiveByteCount() throws {
        let fixture = try makeFixture()
        let store = DiagnosticLogStore(root: fixture.logs, now: { fixture.now })
        try store.append(category: .startup, level: .info, message: "app init finished", fields: [])

        let artifact = try DiagnosticLogExporter(
            store: store,
            metadata: fixture.metadata,
            exportedAt: { fixture.now }
        ).prepare(window: .everything, stagingRoot: fixture.staging)

        let archiveAttributes = try FileManager.default.attributesOfItem(atPath: artifact.archiveURL.path)
        let archiveSize = try XCTUnwrap(archiveAttributes[.size] as? NSNumber)
        XCTAssertEqual(artifact.byteCount, archiveSize.intValue)
        XCTAssertGreaterThan(artifact.byteCount, 0)
    }

    func testExportAllowsRuledFlowPlaceAndViewportScaleContent() throws {
        let fixture = try makeFixture()
        let store = DiagnosticLogStore(root: fixture.logs, now: { fixture.now })
        try store.appendRawLineForTesting("2026-07-19T12:58:13Z flow info place viewed placeID=mt1_00000000000000000000000001 placeName=Blue Mansion")
        try store.appendRawLineForTesting("2026-07-19T12:58:14Z flow info viewport browsed region=malaysia-singapore-brunei zoom=14 tileZ=10 covered=12 requests=9 blocked=3")

        let artifact = try DiagnosticLogExporter(
            store: store,
            metadata: fixture.metadata
        ).prepare(window: .everything, stagingRoot: fixture.staging)

        let log = try String(contentsOf: artifact.logURL, encoding: .utf8)

        XCTAssertTrue(log.contains("placeID=mt1_00000000000000000000000001"))
        XCTAssertTrue(log.contains("placeName=Blue Mansion"))
        XCTAssertTrue(log.contains("region=malaysia-singapore-brunei"))
        XCTAssertTrue(log.contains("covered=12"))
        XCTAssertFalse(log.contains("bbox="))
        XCTAssertFalse(log.contains("center="))
    }

    func testExportScrubFailsClosedForFixedExcludedClasses() throws {
        let fixture = try makeFixture()
        let excludedLines = [
            "2026-07-19T12:58:13Z flow info device deviceName=Rob's iPhone",
            "2026-07-19T12:58:13Z flow info located gpsLatitude=51.50740 gpsLongitude=-0.12780",
            "2026-07-19T12:58:13Z flow info search queryText=private medical search",
            "2026-07-19T12:58:13Z flow info viewport browsed viewportCenter=100.29400,5.45200",
            "2026-07-19T12:58:13Z flow info viewport browsed bbox=100.28200,5.44000,100.30600,5.46400",
            "2026-07-19T12:58:13Z flow info viewport browsed tileX=795 tileY=493",
        ]

        for line in excludedLines {
            let store = DiagnosticLogStore(
                root: fixture.logs.appendingPathComponent(UUID().uuidString, isDirectory: true),
                now: { fixture.now }
            )
            try store.appendRawLineForTesting(line)
            XCTAssertThrowsError(try DiagnosticLogExporter(
                store: store,
                metadata: fixture.metadata
            ).prepare(
                window: .everything,
                stagingRoot: fixture.staging.appendingPathComponent(UUID().uuidString, isDirectory: true)
            )) { error in
                XCTAssertEqual(error as? DiagnosticLogExportError, .privacyScrubFailed)
            }
        }
    }

    func testDeleteDiagnosticsClearsLogsAndStaging() throws {
        let fixture = try makeFixture()
        let store = DiagnosticLogStore(root: fixture.logs, now: { fixture.now })
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
        return Fixture(logs: logs, staging: staging, now: now, metadata: metadata)
    }
}

private struct Fixture {
    let logs: URL
    let staging: URL
    let now: Date
    let metadata: DiagnosticLogMetadata
}
