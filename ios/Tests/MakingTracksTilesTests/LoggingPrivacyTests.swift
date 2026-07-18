import Foundation
import XCTest
@testable import MakingTracksTiles

final class LoggingPrivacyTests: XCTestCase {
    func testLoggingFacadeDeclaresRequiredSubsystemAndCategories() throws {
        let source = try sourceFile("Sources/MakingTracksTiles/MakingTracksLog.swift")

        XCTAssertTrue(source.contains(#"static let subsystem = "app.making-tracks""#))
        for category in ["downloads", "gc", "install", "resolution", "startup"] {
            XCTAssertTrue(source.contains(#"Logger(subsystem: subsystem, category: "\#(category)")"#), category)
        }
    }

    func testStructuredLogCallsDoNotFormatCoordinatesPlacesOrRawURLs() throws {
        let root = try packageRoot()
        let sourceRoots = [
            root.appendingPathComponent("Sources"),
            root.appendingPathComponent("App/Sources"),
        ]
        let forbiddenPatterns = [
            #"(?i)\blat\b"#, #"(?i)\blatitude\b"#, #"(?i)\blon\b"#, #"(?i)\blongitude\b"#,
            #"(?i)coordinate"#, #"(?i)\bbbox\b"#,
            #"(?i)placeID"#, #"(?i)placeId"#, #"(?i)place_id"#, #"(?i)placeName"#, #"(?i)name:"#,
            #"(?i)absoluteString"#, #"(?i)path:"#, #"(?i)url:"#, #"URL\("#,
            #"(?i)\bregion=\\\([^)]*, privacy: \.public"#,
            #"(?i)\bpausedRegion=\\\([^)]*, privacy: \.public"#,
        ]

        for sourceRoot in sourceRoots {
            for fileURL in try swiftFiles(under: sourceRoot) {
                let source = try String(contentsOf: fileURL, encoding: .utf8)
                for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
                    guard line.contains("MakingTracksLog.") else { continue }
                    for pattern in forbiddenPatterns {
                        XCTAssertFalse(
                            line.range(of: pattern, options: .regularExpression) != nil,
                            "\(fileURL.path): log line matches forbidden pattern '\(pattern)': \(line)"
                        )
                    }
                }
            }
        }
    }

    func testLoggingSanitizersDoNotEchoRawURLsOrErrorText() throws {
        let hostileURL = try XCTUnwrap(URL(
            string: "https://tiles.making-tracks.app/uk_london/20260718T010203Z/tiles/10/1/2.json.gz?place_id=mt_123&lat=51.5&name=secret"
        ))

        XCTAssertEqual(MakingTracksLog.host(hostileURL), "tiles.making-tracks.app")
        XCTAssertEqual(MakingTracksLog.objectKind(hostileURL), "tile")
        XCTAssertEqual(MakingTracksLog.errorLabel(TileError.httpStatus(503)), "http-503")
        XCTAssertEqual(MakingTracksLog.errorLabel(TileError.invalidRedirect), "invalid-redirect")

        let rawError = NSError(
            domain: "https://tiles.making-tracks.app/uk_london/private/path?lat=51.5&place_id=mt_123",
            code: 7
        )
        XCTAssertEqual(MakingTracksLog.errorLabel(rawError), "NSError")

        let sanitizerOutputs = [
            MakingTracksLog.host(hostileURL),
            MakingTracksLog.objectKind(hostileURL),
            MakingTracksLog.errorLabel(rawError),
        ]
        for output in sanitizerOutputs {
            XCTAssertFalse(output.contains("uk_london"), output)
            XCTAssertFalse(output.contains("place_id"), output)
            XCTAssertFalse(output.contains("lat"), output)
            XCTAssertFalse(output.contains("private/path"), output)
            XCTAssertFalse(output.contains("?"), output)
        }
    }

    func testOSLogUsageRoutesThroughSharedFacade() throws {
        let root = try packageRoot()
        let sourceRoots = [
            root.appendingPathComponent("Sources"),
            root.appendingPathComponent("App/Sources"),
        ]
        let allowedFacade = root.appendingPathComponent("Sources/MakingTracksTiles/MakingTracksLog.swift").standardizedFileURL

        for sourceRoot in sourceRoots {
            for fileURL in try swiftFiles(under: sourceRoot) {
                let standardized = fileURL.standardizedFileURL
                let source = try String(contentsOf: fileURL, encoding: .utf8)
                if standardized == allowedFacade {
                    continue
                }
                XCTAssertFalse(source.contains("import OSLog"), "\(fileURL.path): import OSLog must stay behind MakingTracksLog")
                XCTAssertFalse(source.contains("Logger("), "\(fileURL.path): Logger construction must stay behind MakingTracksLog")
            }
        }
    }

    private func sourceFile(_ relativePath: String) throws -> String {
        try String(contentsOf: packageRoot().appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func packageRoot() throws -> URL {
        var current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        while current.path != "/" {
            if FileManager.default.fileExists(atPath: current.appendingPathComponent("Package.swift").path) {
                return current
            }
            current.deleteLastPathComponent()
        }
        throw NSError(domain: "LoggingPrivacyTests", code: 1)
    }

    private func swiftFiles(under root: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return try enumerator.compactMap { item -> URL? in
            guard let url = item as? URL, url.pathExtension == "swift" else { return nil }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            return values.isRegularFile == true ? url : nil
        }
    }
}
