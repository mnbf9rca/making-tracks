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

        for sourceRoot in sourceRoots {
            for fileURL in try swiftFiles(under: sourceRoot) {
                let source = try String(contentsOf: fileURL, encoding: .utf8)
                for finding in privacyLintFindings(in: source) {
                    XCTFail("\(fileURL.path): \(finding)")
                }
            }
        }
    }

    func testPrivacyLintRejectsWrappedFileSinkBypasses() {
        let unsafeSource = #"""
        func leak(placeID: String, url: URL) {
            MakingTracksLog.file(
                .resolution,
                level: .error,
                "export leak",
                fields: [
                    .public("placeID", placeID),
                    .public("rawURL", url.absoluteString)
                ]
            )
        }
        """#

        let findings = privacyLintFindings(in: unsafeSource)

        XCTAssertFalse(findings.isEmpty)
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

    func testLoggingPrivacySuiteIsWiredIntoCI() throws {
        let workflow = try String(
            contentsOf: repoRoot().appendingPathComponent(".github/workflows/ios-logging-privacy.yml"),
            encoding: .utf8
        )

        XCTAssertTrue(workflow.contains("swift test --filter LoggingPrivacyTests"))
    }

    private func logLineHasExplicitPrivacyAnnotations(_ line: String) -> Bool {
        for interpolation in logInterpolations(in: line) {
            if interpolation.range(of: #"privacy\s*:"#, options: .regularExpression) == nil {
                return false
            }
        }
        return true
    }

    private func privacyLintFindings(in source: String) -> [String] {
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
        var findings: [String] = []
        for call in logFacadeCalls(in: source) {
            if !logLineHasExplicitPrivacyAnnotations(call) {
                findings.append("log interpolation lacks explicit privacy annotation: \(call)")
            }
            for pattern in forbiddenPatterns where call.range(of: pattern, options: .regularExpression) != nil {
                findings.append("log call matches forbidden pattern '\(pattern)': \(call)")
            }
        }
        return findings
    }

    private func logFacadeCalls(in source: String) -> [String] {
        var calls: [String] = []
        var searchStart = source.startIndex

        while let match = source.range(of: "MakingTracksLog.", range: searchStart..<source.endIndex) {
            let start = match.lowerBound
            guard let open = firstOpeningParenthesis(in: source, from: match.upperBound) else {
                searchStart = match.upperBound
                continue
            }

            var cursor = open
            var depth = 0
            var isInString = false
            var escaped = false
            while cursor < source.endIndex {
                let character = source[cursor]
                if isInString {
                    if escaped {
                        escaped = false
                    } else if character == "\\" {
                        escaped = true
                    } else if character == "\"" {
                        isInString = false
                    }
                } else if character == "\"" {
                    isInString = true
                } else if character == "(" {
                    depth += 1
                } else if character == ")" {
                    depth -= 1
                    if depth == 0 {
                        calls.append(String(source[start...cursor]))
                        searchStart = source.index(after: cursor)
                        break
                    }
                }
                cursor = source.index(after: cursor)
            }

            if cursor >= source.endIndex {
                searchStart = source.endIndex
            }
        }
        return calls
    }

    private func firstOpeningParenthesis(in source: String, from start: String.Index) -> String.Index? {
        var cursor = start
        while cursor < source.endIndex {
            let character = source[cursor]
            if character == "(" {
                return cursor
            }
            if character.isWhitespace == false,
               character != ".",
               character != "_",
               character.isLetter == false,
               character.isNumber == false {
                return nil
            }
            cursor = source.index(after: cursor)
        }
        return nil
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

    private func repoRoot() throws -> URL {
        let package = try packageRoot()
        return package.deletingLastPathComponent()
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
