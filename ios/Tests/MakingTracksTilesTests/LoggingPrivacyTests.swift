import Foundation
import XCTest
@testable import MakingTracksTiles

final class LoggingPrivacyTests: XCTestCase {
    func testLoggingFacadeDeclaresRequiredSubsystemAndCategories() throws {
        let source = try sourceFile("Sources/MakingTracksTiles/MakingTracksLog.swift")

        XCTAssertTrue(source.contains(#"static let subsystem = "app.making-tracks""#))
        for category in ["downloads", "flow", "gc", "install", "resolution", "startup"] {
            XCTAssertTrue(source.contains(#"Logger(subsystem: subsystem, category: "\#(category)")"#), category)
        }
    }

    func testPrivacyLintAllowsRuledSessionFlowFields() {
        let allowedSource = #"""
        func logFlow(place: PlaceRef) {
            MakingTracksLog.file(category: .flow, level: .info, "place viewed", fields: [
                .object("placeID", place.placeID),
                .object("placeName", place.name),
                .public("region", "malaysia-singapore-brunei"),
                .public("zoom", "14"),
                .public("tileZ", "10"),
                .public("covered", "12"),
                .public("requests", "9"),
                .public("blocked", "3")
            ])
        }
        """#

        XCTAssertTrue(privacyLintFindings(in: allowedSource).isEmpty)
    }

    func testPrivacyLintRejectsFixedExcludedClassesInFileSinkFields() {
        let unsafeCases = [
            (
                "device name",
                #"""
                MakingTracksLog.file(category: .flow, level: .info, "device", fields: [
                    .object("deviceName", UIDevice.current.name)
                ])
                """#
            ),
            (
                "precise GPS coordinate",
                #"""
                MakingTracksLog.file(category: .flow, level: .info, "located", fields: [
                    .public("gpsLatitude", "\(location.coordinate.latitude)"),
                    .public("gpsLongitude", "\(location.coordinate.longitude)")
                ])
                """#
            ),
            (
                "raw search query",
                #"""
                MakingTracksLog.file(category: .flow, level: .info, "search", fields: [
                    .object("queryText", searchQuery)
                ])
                """#
            ),
            (
                "viewport center coordinate",
                #"""
                MakingTracksLog.file(category: .flow, level: .info, "viewport", fields: [
                    .public("viewportCenter", bbox.center.logDescription)
                ])
                """#
            ),
            (
                "viewport bbox coordinate",
                #"""
                MakingTracksLog.file(category: .flow, level: .info, "viewport", fields: [
                    .public("viewportBbox", bbox.logDescription)
                ])
                """#
            ),
            (
                "absolute tile coordinate",
                #"""
                MakingTracksLog.file(category: .flow, level: .info, "viewport", fields: [
                    .public("tileX", "\(tile.x)"),
                    .public("tileY", "\(tile.y)")
                ])
                """#
            ),
        ]

        for (label, source) in unsafeCases {
            XCTAssertFalse(privacyLintFindings(in: source).isEmpty, label)
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
            #"MakingTracksLog.downloads.info("device=\(UIDevice.current.name, privacy: .public)")"#,
            #"MakingTracksLog.downloads.info("gps=\(location.coordinate.latitude, privacy: .public)")"#,
            #"MakingTracksLog.downloads.info("detail=\(prebuilt)")"#,
        ]
        let forbiddenPatterns = [
            #"UIDevice\s*\.\s*current\s*\.\s*name"#,
            #"(?i)\blocation\s*\.\s*coordinate\s*\.\s*(latitude|longitude)"#,
            #"\\\(url(?:[,)]|\s)"#,
        ]

        XCTAssertFalse(logLineHasExplicitPrivacyAnnotations(unsafeLines[0]))
        XCTAssertTrue(unsafeLines[1].range(of: forbiddenPatterns[0], options: .regularExpression) != nil)
        XCTAssertTrue(unsafeLines[2].range(of: forbiddenPatterns[1], options: .regularExpression) != nil)
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

    func testLoggingSanitizersClassifySidecarObjectsWithoutRawPaths() throws {
        let imageURL = try XCTUnwrap(URL(string: "https://tiles.making-tracks.app/malaysia-singapore-brunei/20260719T125813Z/images/10/795/493.json"))
        let descriptionURL = try XCTUnwrap(URL(string: "https://tiles.making-tracks.app/malaysia-singapore-brunei/20260719T125813Z/descriptions/10/795/493.json"))
        let thumbnailURL = try XCTUnwrap(URL(string: "https://tiles.making-tracks.app/thumbs/ab/abcdef.webp"))
        let searchURL = try XCTUnwrap(URL(string: "https://tiles.making-tracks.app/malaysia-singapore-brunei/20260719T125813Z/search/compact.json"))

        XCTAssertEqual(MakingTracksLog.objectKind(imageURL), "image-index")
        XCTAssertEqual(MakingTracksLog.objectKind(descriptionURL), "description-index")
        XCTAssertEqual(MakingTracksLog.objectKind(thumbnailURL), "thumbnail")
        XCTAssertEqual(MakingTracksLog.objectKind(searchURL), "search-compact")
        XCTAssertEqual(MakingTracksLog.objectPublishVersion(imageURL), "20260719T125813Z")
        XCTAssertEqual(MakingTracksLog.objectTileZ(imageURL), "10")
        XCTAssertEqual(MakingTracksLog.objectPublishVersion(thumbnailURL), "none")
        XCTAssertEqual(MakingTracksLog.objectTileZ(thumbnailURL), "none")

        let sanitizerOutputs = [
            MakingTracksLog.objectKind(imageURL),
            MakingTracksLog.objectPublishVersion(imageURL),
            MakingTracksLog.objectTileZ(imageURL),
        ]
        for output in sanitizerOutputs {
            XCTAssertFalse(output.contains("malaysia-singapore-brunei"), output)
            XCTAssertFalse(output.contains("795"), output)
            XCTAssertFalse(output.contains("493"), output)
            XCTAssertFalse(output.contains("/"), output)
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

    func testMapScreenEmitsRuledSessionFlowEvents() throws {
        let source = try String(
            contentsOf: packageRoot().appendingPathComponent("App/Sources/Map/MapScreen.swift"),
            encoding: .utf8
        )

        for expected in [
            #"MakingTracksLog.flowEvent("screen opened""#,
            #"MakingTracksLog.flowEvent("sheet opened""#,
            #"MakingTracksLog.flowEvent("place tapped""#,
            #"MakingTracksLog.flowEvent("place viewed""#,
            #"MakingTracksLog.flowEvent("verdict changed""#,
            #"MakingTracksLog.viewportFlowEvent("#,
        ] {
            XCTAssertTrue(source.contains(expected), expected)
        }
    }

    func testDiagnosticsConsentCopyUsesHumanLabelsWithoutChangingExportClasses() throws {
        let source = try String(
            contentsOf: packageRoot().appendingPathComponent("App/Sources/Map/MapScreen.swift"),
            encoding: .utf8
        )
        let exportSource = try String(
            contentsOf: packageRoot().appendingPathComponent("Sources/MakingTracksTiles/DiagnosticLogExport.swift"),
            encoding: .utf8
        )

        for expected in [
            "Nothing is sent automatically. The app prepares a file on this phone",
            "App details", "Device type", "Steps in the app", "Downloaded maps",
            "Map file links", "Problems", "Load times", "Places and taps",
            "Device name", "Precise location", "Search text",
            "Your exact coordinates are not included.",
        ] {
            XCTAssertTrue(source.contains(expected), expected)
        }
        for technicalLabel in [
            #"DiagnosticsDisclosureClass(title: "Session flow""#,
            #"DiagnosticsDisclosureClass(title: "Object URLs""#,
            #"DiagnosticsDisclosureClass(title: "Places/actions""#,
            #"DiagnosticsDisclosureClass(title: "Search wording""#,
        ] {
            XCTAssertFalse(source.contains(technicalLabel), technicalLabel)
        }
        XCTAssertTrue(exportSource.contains("included=app-version,device-model,installed-packs,session-flow,object-urls,error-codes,timings"))
        XCTAssertTrue(exportSource.contains("not-included=device-name,exact-location,search-wording"))
        XCTAssertFalse(source.contains("Phone model"))
        XCTAssertFalse(source.contains("Phone name"))
        XCTAssertFalse(source.contains("Your coordinates never leave."))
        XCTAssertFalse(source.contains("Your coordinates are excluded."))
        XCTAssertFalse(source.contains("Places you looked at, saved, loved, hid or visited."))
        XCTAssertFalse(source.contains("Your searches, lists, location, viewport or device name."))
    }

    func testDiagnosticsRedesignKeepsDeleteInsideDiagnosticsContext() throws {
        let source = try String(
            contentsOf: packageRoot().appendingPathComponent("App/Sources/Map/MapScreen.swift"),
            encoding: .utf8
        )
        let settingsSource = try XCTUnwrap(source.components(separatedBy: "private struct DiagnosticsView").first)

        XCTAssertTrue(settingsSource.contains("Text(\"Diagnostic log\")"))
        XCTAssertTrue(settingsSource.contains("Review, prepare, share, or delete local logs."))
        XCTAssertFalse(settingsSource.contains("settings.diagnostics.delete"))
        XCTAssertTrue(source.contains(".accessibilityIdentifier(\"settings.diagnostics.delete\")"))
    }

    func testDiagnosticsPreparedCopyUsesPlainConsentLanguage() throws {
        let source = try String(
            contentsOf: packageRoot().appendingPathComponent("App/Sources/Map/MapScreen.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("Tap Share when you are ready to choose who gets it. Nothing leaves Making Tracks before then."))
        XCTAssertTrue(source.contains("Making Tracks has no upload endpoint."))
        XCTAssertFalse(source.contains("Share boundary"))
        XCTAssertFalse(source.localizedCaseInsensitiveContains("system share sheet"))
    }

    func testDiagnosticsPreviewGetsReadableScrollAreaForVerboseLogs() throws {
        let source = try String(
            contentsOf: packageRoot().appendingPathComponent("App/Sources/Map/MapScreen.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("ScrollView([.horizontal, .vertical])"))
        XCTAssertTrue(source.contains(".frame(minHeight: 220"))
        XCTAssertTrue(source.contains(".font(.system(.footnote, design: .monospaced))"))
    }

    func testDiagnosticsDeleteRequiresConfirmation() throws {
        let source = try String(
            contentsOf: packageRoot().appendingPathComponent("App/Sources/Map/MapScreen.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("@State private var showDeleteConfirmation = false"))
        XCTAssertTrue(source.contains(".confirmationDialog(\"Delete diagnostic logs?\""))
        XCTAssertTrue(source.contains("Button(\"Delete logs\", role: .destructive)"))
        XCTAssertTrue(source.contains("showDeleteConfirmation = true"))
    }

    func testDiagnosticsPrepareDoesNotRunExporterSynchronouslyOnMainThread() throws {
        let source = try String(
            contentsOf: packageRoot().appendingPathComponent("App/Sources/Map/MapScreen.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("Task {"), "Prepare actions should enter Swift concurrency.")
        XCTAssertTrue(source.contains("await prepare(coverCurrentSession:"), "Prepare actions should await the async prepare path.")
        XCTAssertTrue(source.contains("private func prepare(coverCurrentSession: Bool) async"), "Diagnostics prepare should be async.")
        XCTAssertTrue(source.contains("Task.detached(priority: .userInitiated)"), "Exporter work should run off the main actor.")
        XCTAssertFalse(
            source.contains("private func prepare() {\n        isPreparing = true"),
            "Diagnostics prepare should not use the old synchronous body."
        )
    }

    func testDiagnosticsNormalPrepareUsesSessionCoveringWindowButShortRetryStaysExplicit() throws {
        let source = try String(
            contentsOf: packageRoot().appendingPathComponent("App/Sources/Map/MapScreen.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("await prepare(coverCurrentSession: true)"))
        XCTAssertTrue(source.contains("await prepare(coverCurrentSession: false)"))
        XCTAssertTrue(source.contains("private func prepare(coverCurrentSession: Bool) async"))
        XCTAssertTrue(source.contains("prepareCoveringCurrentSession(preferredWindow: window"))
        XCTAssertTrue(source.contains(".prepare(window: window"))
    }

    func testTrackVisitDateHeadersAreNotStandaloneMovableRows() throws {
        let source = try sourceFile("App/Sources/Map/MapScreen.swift")
        let movableRowsStart = "ForEach(TrackVisitReordering.rows(for: visibleTrackVisits, calendar: calendar)) { row in"
        let onMoveStart = "\n                        .onMove"

        XCTAssertFalse(
            source.contains(#"Text(verbatim: formattedDay(calendar.startOfDay(for: visit.visitedAt)))"#),
            "Date headers must be rendered inside the visit row, not as standalone rows in the movable ForEach."
        )
        guard let forEachRange = source.range(of: movableRowsStart) else {
            return XCTFail("The My tracks movable ForEach should be built from TrackVisitReordering.rows.")
        }
        let afterForEach = source[forEachRange.upperBound...]
        guard let onMoveRange = afterForEach.range(of: onMoveStart) else {
            return XCTFail("The My tracks movable ForEach should apply onMove directly to visit rows.")
        }
        let movableBodyLines = afterForEach[..<onMoveRange.lowerBound]
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != "}" }

        XCTAssertEqual(
            movableBodyLines,
            ["trackVisitRow(row.visit, dayHeader: row.dayHeader)"],
            "The movable track visit ForEach must contain only visit rows with inline day headers before onMove."
        )
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
            #"UIDevice\s*\.\s*current\s*\.\s*name"#, #"(?i)\bdeviceName\b"#,
            #"(?i)\bgps[A-Za-z]*(lat|lon|latitude|longitude)\b"#,
            #"(?i)\blocation\s*\.\s*coordinate\s*\.\s*(latitude|longitude)"#,
            #"(?i)\bviewport(Center|Bbox)\b"#, #"(?i)\bbbox\b"#, #"(?i)\bcenter\b"#,
            #"(?i)\btile[XY]\b"#,
            #"(?i)\braw(Search)?Query\b"#, #"(?i)\bsearchQuery\b"#, #"(?i)\bqueryText\b"#,
            #"(?i)absoluteString"#, #"(?i)path:"#, #"(?i)url:"#, #"URL\("#,
            #"\\\(url(?:[,)]|\s)"#,
            #"(?i)\bregion=\\\([^)]*, privacy: \.public"#,
            #"(?i)\bpausedRegion=\\\([^)]*, privacy: \.public"#,
            #"(?i)\bidentifier=\\\([^)]*, privacy: \.public"#,
        ]
        var findings: [String] = []
        for call in logFacadeCalls(in: source) {
            if !isClassifiedFileSinkCall(call),
               !logLineHasExplicitPrivacyAnnotations(call) {
                findings.append("log interpolation lacks explicit privacy annotation: \(call)")
            }
            for pattern in forbiddenPatterns where call.range(of: pattern, options: .regularExpression) != nil {
                findings.append("log call matches forbidden pattern '\(pattern)': \(call)")
            }
        }
        return findings
    }

    private func isClassifiedFileSinkCall(_ call: String) -> Bool {
        call.contains("MakingTracksLog.file(")
            || call.contains("MakingTracksLog.flowEvent(")
            || call.contains("MakingTracksLog.viewportFlowEvent(")
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
