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
            #"(?i)\blat\b"#, #"(?i)latitude"#, #"(?i)\blon\b"#, #"(?i)longitude"#,
            #"(?i)coordinate"#, #"(?i)\bbbox\b"#,
            #"(?i)placeID"#, #"(?i)placeId"#, #"(?i)place_id"#, #"(?i)placeName"#, #"(?i)\bplace\."#, #"(?i)name:"#,
            #"(?i)absoluteString"#, #"(?i)path:"#, #"(?i)url:"#, #"URL\("#,
            #"\\\(url(?:[,)]|\s)"#,
            #"(?i)\bregion=\\\([^)]*, privacy: \.public"#,
            #"(?i)\bpausedRegion=\\\([^)]*, privacy: \.public"#,
            #"(?i)\bidentifier=\\\([^)]*, privacy: \.public"#,
        ]

        for sourceRoot in sourceRoots {
            for fileURL in try swiftFiles(under: sourceRoot) {
                let source = try String(contentsOf: fileURL, encoding: .utf8)
                for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
                    guard line.contains("MakingTracksLog.") else { continue }
                    XCTAssertTrue(
                        logLineHasExplicitPrivacyAnnotations(String(line)),
                        "\(fileURL.path): log interpolation lacks explicit privacy annotation: \(line)"
                    )
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

    func testPrivacyLintRejectsRepresentativeBypasses() {
        let unsafeLines = [
            #"MakingTracksLog.downloads.info("raw=\(url)")"#,
            #"MakingTracksLog.downloads.info("place=\(place.name, privacy: .public)")"#,
            #"MakingTracksLog.downloads.info("center=\(centerLatitude, privacy: .public)")"#,
            #"MakingTracksLog.downloads.info("detail=\(prebuilt)")"#,
        ]
        let forbiddenPatterns = [
            #"(?i)latitude"#,
            #"(?i)\bplace\."#,
            #"\\\(url(?:[,)]|\s)"#,
        ]

        XCTAssertFalse(logLineHasExplicitPrivacyAnnotations(unsafeLines[0]))
        XCTAssertTrue(unsafeLines[1].range(of: forbiddenPatterns[1], options: .regularExpression) != nil)
        XCTAssertTrue(unsafeLines[2].range(of: forbiddenPatterns[0], options: .regularExpression) != nil)
        XCTAssertFalse(logLineHasExplicitPrivacyAnnotations(unsafeLines[3]))
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
                XCTAssertFalse(source.contains("import os"), "\(fileURL.path): import os must stay behind MakingTracksLog")
                XCTAssertFalse(source.contains("Logger("), "\(fileURL.path): Logger construction must stay behind MakingTracksLog")
                XCTAssertFalse(source.contains("OSLog("), "\(fileURL.path): OSLog construction must stay behind MakingTracksLog")
                XCTAssertFalse(source.contains("os_log("), "\(fileURL.path): legacy os_log must stay behind MakingTracksLog")
            }
        }
    }

    private func logLineHasExplicitPrivacyAnnotations(_ line: String) -> Bool {
        for interpolation in logInterpolations(in: line) {
            if interpolation.range(of: #"privacy\s*:"#, options: .regularExpression) == nil {
                return false
            }
        }
        return true
    }

    private func logInterpolations(in line: String) -> [String] {
        let characters = Array(line)
        var results: [String] = []
        var index = characters.startIndex
        while index < characters.endIndex {
            guard characters[index] == "\\",
                  characters.index(after: index) < characters.endIndex,
                  characters[characters.index(after: index)] == "("
            else {
                index = characters.index(after: index)
                continue
            }

            var cursor = characters.index(index, offsetBy: 2)
            var depth = 1
            var interpolation = ""
            while cursor < characters.endIndex, depth > 0 {
                let character = characters[cursor]
                if character == "(" {
                    depth += 1
                } else if character == ")" {
                    depth -= 1
                    if depth == 0 {
                        break
                    }
                }
                interpolation.append(character)
                cursor = characters.index(after: cursor)
            }
            results.append(interpolation)
            index = cursor < characters.endIndex ? characters.index(after: cursor) : cursor
        }
        return results
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
