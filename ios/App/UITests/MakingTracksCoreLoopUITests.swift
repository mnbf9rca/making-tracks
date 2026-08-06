import CryptoKit
import Foundation
import UIKit
import XCTest

private struct AXSampleMatch: Equatable {
    var matched: Bool
    var observed: String?
}

private struct AXExistenceMatch: Equatable {
    var matched: Bool
    var observedExists: Bool
}

private struct AXFocusAcquisitionMatch: Equatable {
    let matched: Bool
    let attempts: Int
}

private enum AXScrollObservation: String, Equatable {
    case missing
    case presentNotHittable = "present but not hittable"
    case hittable
}

private enum FixturePinRepositionObservation {
    static func classify(
        exists: Bool,
        isHittable: Bool,
        frameContainsMapCenter: Bool
    ) -> AXScrollObservation {
        guard exists else { return .missing }
        guard isHittable, !frameContainsMapCenter else {
            return .presentNotHittable
        }
        return .hittable
    }
}

private struct AXScrollMatch: Equatable {
    let matched: Bool
    let scrolls: Int
    let observation: AXScrollObservation
}

private enum KeyboardFocusProxy: String, Equatable {
    case softwareKeyboardPresence = "software-keyboard presence"
    case focusedElementQuery = "focused-element query"
}

private struct KeyboardFocusObservation: Equatable {
    let focused: Bool
    let proxy: KeyboardFocusProxy
}

private enum KeyboardFocusProxySelector {
    static func observe(
        softwareKeyboardPresent: Bool,
        elementFocused: Bool
    ) -> KeyboardFocusObservation {
        if softwareKeyboardPresent {
            return KeyboardFocusObservation(
                focused: true,
                proxy: .softwareKeyboardPresence
            )
        }
        return KeyboardFocusObservation(
            focused: elementFocused,
            proxy: .focusedElementQuery
        )
    }
}

private struct RenderedDifferenceMatch: Equatable {
    let matched: Bool
    let observed: Int?
    let attempts: Int
}

private struct AXStubElement {
    var exists: Bool
    var label: String
}

private struct RenderedRGB: Equatable {
    let red: Int
    let green: Int
    let blue: Int

    init(_ red: Int, _ green: Int, _ blue: Int) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    func matches(_ other: RenderedRGB, tolerance: Int = 5) -> Bool {
        abs(red - other.red) <= tolerance
            && abs(green - other.green) <= tolerance
            && abs(blue - other.blue) <= tolerance
    }

    var relativeLuminance: Double {
        func linear(_ component: Int) -> Double {
            let value = Double(component) / 255
            return value <= 0.04045
                ? value / 12.92
                : pow((value + 0.055) / 1.055, 2.4)
        }

        return (0.2126 * linear(red)) + (0.7152 * linear(green)) + (0.0722 * linear(blue))
    }

    func contrastRatio(with other: RenderedRGB) -> Double {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }
}

@MainActor
private struct RenderedPixelRaster {
    private let pixels: [UInt8]
    private let width: Int
    private let height: Int
    private let bytesPerRow: Int
    private let appFrame: CGRect

    init?(screenshot: XCUIScreenshot, appFrame: CGRect) {
        guard let image = UIImage(data: screenshot.pngRepresentation)?.cgImage,
              appFrame.width > 0,
              appFrame.height > 0
        else {
            return nil
        }

        width = image.width
        height = image.height
        bytesPerRow = image.width * 4
        self.appFrame = appFrame

        var storage = [UInt8](repeating: 0, count: image.height * bytesPerRow)
        guard let context = CGContext(
            data: &storage,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            return nil
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        pixels = storage
    }

    func samples(in frame: CGRect) -> [RenderedRGB] {
        let clipped = frame.intersection(appFrame)
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return [] }

        let scaleX = CGFloat(width) / appFrame.width
        let scaleY = CGFloat(height) / appFrame.height
        let minX = max(0, Int(((clipped.minX - appFrame.minX) * scaleX).rounded(.down)))
        let maxX = min(width - 1, Int(((clipped.maxX - appFrame.minX) * scaleX).rounded(.up)))
        let minY = max(0, Int(((clipped.minY - appFrame.minY) * scaleY).rounded(.down)))
        let maxY = min(height - 1, Int(((clipped.maxY - appFrame.minY) * scaleY).rounded(.up)))
        guard minX <= maxX, minY <= maxY else { return [] }

        var result: [RenderedRGB] = []
        result.reserveCapacity((maxX - minX + 1) * (maxY - minY + 1))
        for y in minY...maxY {
            for x in minX...maxX {
                let offset = (y * bytesPerRow) + (x * 4)
                result.append(RenderedRGB(
                    Int(pixels[offset]),
                    Int(pixels[offset + 1]),
                    Int(pixels[offset + 2])
                ))
            }
        }
        return result
    }

    func tokenCount(_ token: RenderedRGB, in frame: CGRect, tolerance: Int = 5) -> Int {
        samples(in: frame).lazy.filter { $0.matches(token, tolerance: tolerance) }.count
    }

    func tokenCoverage(_ token: RenderedRGB, in frame: CGRect, tolerance: Int = 5) -> Double {
        let region = samples(in: frame)
        guard !region.isEmpty else { return 0 }
        let matches = region.lazy.filter { $0.matches(token, tolerance: tolerance) }.count
        return Double(matches) / Double(region.count)
    }

    func verticalTokenBounds(
        _ token: RenderedRGB,
        in frame: CGRect,
        tolerance: Int = 5,
        minimumMatchingWidth: CGFloat = 2
    ) -> ClosedRange<CGFloat>? {
        let clipped = frame.intersection(appFrame)
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else {
            return nil
        }

        let scaleX = CGFloat(width) / appFrame.width
        let scaleY = CGFloat(height) / appFrame.height
        let minX = max(0, Int(((clipped.minX - appFrame.minX) * scaleX).rounded(.down)))
        let maxX = min(width - 1, Int(((clipped.maxX - appFrame.minX) * scaleX).rounded(.up)))
        let minY = max(0, Int(((clipped.minY - appFrame.minY) * scaleY).rounded(.down)))
        let maxY = min(height - 1, Int(((clipped.maxY - appFrame.minY) * scaleY).rounded(.up)))
        guard minX <= maxX, minY <= maxY else { return nil }

        let minimumRun = max(
            2,
            Int((minimumMatchingWidth * scaleX).rounded(.up))
        )
        var matchingBands: [ClosedRange<Int>] = []
        var bandStart: Int?
        for y in minY...maxY {
            var longestRun = 0
            var currentRun = 0
            for x in minX...maxX {
                let offset = (y * bytesPerRow) + (x * 4)
                let pixel = RenderedRGB(
                    Int(pixels[offset]),
                    Int(pixels[offset + 1]),
                    Int(pixels[offset + 2])
                )
                if pixel.matches(token, tolerance: tolerance) {
                    currentRun += 1
                    longestRun = max(longestRun, currentRun)
                } else {
                    currentRun = 0
                }
            }

            if longestRun >= minimumRun {
                bandStart = bandStart ?? y
            } else if let start = bandStart {
                matchingBands.append(start...(y - 1))
                bandStart = nil
            }
        }
        if let bandStart {
            matchingBands.append(bandStart...maxY)
        }

        guard let largestBand = matchingBands.max(by: {
            $0.count < $1.count
        }) else {
            return nil
        }
        return (
            appFrame.minY + (CGFloat(largestBand.lowerBound) / scaleY)
        )...(
            appFrame.minY + (CGFloat(largestBand.upperBound + 1) / scaleY)
        )
    }

    func representativeToken(
        _ token: RenderedRGB,
        in frame: CGRect,
        tolerance: Int = 5
    ) -> (color: RenderedRGB, count: Int)? {
        let matches = samples(in: frame).filter { $0.matches(token, tolerance: tolerance) }
        guard !matches.isEmpty else { return nil }
        let sums = matches.reduce(into: (red: 0, green: 0, blue: 0)) { result, pixel in
            result.red += pixel.red
            result.green += pixel.green
            result.blue += pixel.blue
        }
        return (
            RenderedRGB(
                Int((Double(sums.red) / Double(matches.count)).rounded()),
                Int((Double(sums.green) / Double(matches.count)).rounded()),
                Int((Double(sums.blue) / Double(matches.count)).rounded())
            ),
            matches.count
        )
    }

    func systemBlueCount(in frame: CGRect) -> Int {
        samples(in: frame).lazy.filter { pixel in
            pixel.blue >= 160
                && pixel.blue - pixel.red >= 70
                && pixel.blue - pixel.green >= 35
        }.count
    }

    func contrastPixelCount(
        against background: RenderedRGB,
        minimum: Double,
        in frame: CGRect
    ) -> Int {
        samples(in: frame).lazy.filter { pixel in
            pixel.contrastRatio(with: background) >= minimum
        }.count
    }

    func highestContrastRatio(
        against background: RenderedRGB,
        in frame: CGRect
    ) -> Double? {
        samples(in: frame).lazy.map { pixel in
            pixel.contrastRatio(with: background)
        }.max()
    }

    func differingPixelCount(
        comparedTo other: RenderedPixelRaster,
        in frame: CGRect,
        tolerance: Int = 0
    ) -> Int? {
        guard width == other.width,
              height == other.height,
              bytesPerRow == other.bytesPerRow,
              appFrame == other.appFrame
        else {
            return nil
        }

        let clipped = frame.intersection(appFrame)
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return 0 }

        let scaleX = CGFloat(width) / appFrame.width
        let scaleY = CGFloat(height) / appFrame.height
        let minX = max(0, Int(((clipped.minX - appFrame.minX) * scaleX).rounded(.down)))
        let maxX = min(width - 1, Int(((clipped.maxX - appFrame.minX) * scaleX).rounded(.up)))
        let minY = max(0, Int(((clipped.minY - appFrame.minY) * scaleY).rounded(.down)))
        let maxY = min(height - 1, Int(((clipped.maxY - appFrame.minY) * scaleY).rounded(.up)))
        guard minX <= maxX, minY <= maxY else { return 0 }

        var differenceCount = 0
        for y in minY...maxY {
            for x in minX...maxX {
                let offset = (y * bytesPerRow) + (x * 4)
                if abs(Int(pixels[offset]) - Int(other.pixels[offset])) > tolerance
                    || abs(Int(pixels[offset + 1]) - Int(other.pixels[offset + 1])) > tolerance
                    || abs(Int(pixels[offset + 2]) - Int(other.pixels[offset + 2])) > tolerance {
                    differenceCount += 1
                }
            }
        }
        return differenceCount
    }
}

private enum MyTracksRenderedFrameGeometry {
    static let systemOwnedBottomInset: CGFloat = 34
}

private enum MyTracksRenderedComparisonFrame {
    static func appOwnedIntersection(light: CGRect, dark: CGRect) -> CGRect {
        // Match visitDateSurfaceFrame's home-indicator exclusion while retaining
        // every app-owned editor pixel in the comparison.
        light.intersection(dark).inset(
            by: UIEdgeInsets(
                top: 1,
                left: 1,
                bottom: MyTracksRenderedFrameGeometry.systemOwnedBottomInset,
                right: 1
            )
        )
    }
}

@MainActor
private struct MyTracksAppearanceCapture {
    let raster: RenderedPixelRaster
    let trackSurfaceFrame: CGRect
    let visitDateRaster: RenderedPixelRaster
    let visitDateSurfaceFrame: CGRect
}

@MainActor
private struct SettingsThemeLockRegionCapture {
    let raster: RenderedPixelRaster
    let comparisonFrame: CGRect
    let primaryInkFrame: CGRect?
    let secondaryInkFrame: CGRect?
}

@MainActor
private struct SettingsThemeLockCapture {
    let regions: [String: SettingsThemeLockRegionCapture]
}

@MainActor
private enum SettingsAppearanceTarget {
    case matches(SettingsThemeLockRegionCapture)
    case differs(SettingsThemeLockRegionCapture)
}

private enum AXResampler {
    static func matches(
        expected: String,
        attempts: Int,
        interval: TimeInterval = 0,
        sample: () -> String?
    ) -> AXSampleMatch {
        precondition(attempts > 0, "AX resampling must make at least one sample")

        var observed: String?
        for attempt in 0..<attempts {
            observed = sample()
            if observed == expected {
                return AXSampleMatch(matched: true, observed: observed)
            }
            if interval > 0, attempt < attempts - 1 {
                RunLoop.current.run(until: Date().addingTimeInterval(interval))
            }
        }
        return AXSampleMatch(matched: false, observed: observed)
    }
}

private enum AXValueWaiter {
    static func wait(
        expected: String,
        attempts: Int,
        interval: TimeInterval = 0,
        sample: () -> String?
    ) -> AXSampleMatch {
        AXResampler.matches(expected: expected, attempts: attempts, interval: interval, sample: sample)
    }

    static func wait(
        matching predicate: (String) -> Bool,
        attempts: Int,
        interval: TimeInterval = 0,
        sample: () -> String?
    ) -> AXSampleMatch {
        precondition(attempts > 0, "AX value wait must make at least one sample")

        var observed: String?
        for attempt in 0..<attempts {
            observed = sample()
            if let observed, predicate(observed) {
                return AXSampleMatch(matched: true, observed: observed)
            }
            if interval > 0, attempt < attempts - 1 {
                RunLoop.current.run(until: Date().addingTimeInterval(interval))
            }
        }
        return AXSampleMatch(matched: false, observed: observed)
    }

    static func wait(
        expected: String,
        timeout: TimeInterval,
        interval: TimeInterval = 0.1,
        sample: () -> String?
    ) -> AXSampleMatch {
        precondition(interval > 0, "AX value wait interval must be positive")

        let attempts = max(1, Int(ceil(timeout / interval)))
        return wait(expected: expected, attempts: attempts, interval: interval, sample: sample)
    }

    static func wait(
        matching predicate: @escaping (String) -> Bool,
        timeout: TimeInterval,
        interval: TimeInterval = 0.1,
        sample: () -> String?
    ) -> AXSampleMatch {
        precondition(interval > 0, "AX value wait interval must be positive")

        let attempts = max(1, Int(ceil(timeout / interval)))
        return wait(matching: predicate, attempts: attempts, interval: interval, sample: sample)
    }
}

private enum AXExistenceWaiter {
    static func waitForAbsence(
        attempts: Int,
        interval: TimeInterval = 0,
        exists: () -> Bool
    ) -> AXExistenceMatch {
        precondition(attempts > 0, "AX existence wait must make at least one sample")

        var observed = true
        for attempt in 0..<attempts {
            observed = exists()
            if !observed {
                return AXExistenceMatch(matched: true, observedExists: observed)
            }
            if interval > 0, attempt < attempts - 1 {
                RunLoop.current.run(until: Date().addingTimeInterval(interval))
            }
        }
        return AXExistenceMatch(matched: false, observedExists: observed)
    }

    static func waitForAbsence(
        timeout: TimeInterval,
        interval: TimeInterval = 0.1,
        exists: () -> Bool
    ) -> AXExistenceMatch {
        precondition(interval > 0, "AX existence wait interval must be positive")

        let attempts = max(1, Int(ceil(timeout / interval)))
        return waitForAbsence(attempts: attempts, interval: interval, exists: exists)
    }

    static func confirmContinuousAbsence(
        attempts: Int,
        interval: TimeInterval = 0,
        exists: () -> Bool
    ) -> AXExistenceMatch {
        precondition(attempts > 0, "AX existence wait must make at least one sample")

        var observed = false
        for attempt in 0..<attempts {
            observed = exists()
            if observed {
                return AXExistenceMatch(matched: false, observedExists: observed)
            }
            if interval > 0, attempt < attempts - 1 {
                RunLoop.current.run(until: Date().addingTimeInterval(interval))
            }
        }
        return AXExistenceMatch(matched: true, observedExists: observed)
    }

    static func confirmContinuousAbsence(
        timeout: TimeInterval,
        interval: TimeInterval = 0.1,
        exists: () -> Bool
    ) -> AXExistenceMatch {
        precondition(interval > 0, "AX existence wait interval must be positive")

        let attempts = max(1, Int(ceil(timeout / interval)))
        return confirmContinuousAbsence(attempts: attempts, interval: interval, exists: exists)
    }
}

private enum AXFocusAcquirer {
    static func acquire(
        maxAttempts: Int,
        interval: TimeInterval = 0,
        isFocused: () -> Bool,
        requestFocus: () -> Void
    ) -> AXFocusAcquisitionMatch {
        precondition(maxAttempts > 0, "AX focus acquisition must make at least one attempt")

        var attempts = 0
        var focused = isFocused()
        while !focused, attempts < maxAttempts {
            requestFocus()
            attempts += 1
            focused = isFocused()
            if !focused, interval > 0, attempts < maxAttempts {
                RunLoop.current.run(until: Date().addingTimeInterval(interval))
            }
        }
        return AXFocusAcquisitionMatch(matched: focused, attempts: attempts)
    }
}

private enum AXBoundedScroller {
    static func acquire(
        maxScrolls: Int,
        observe: () -> AXScrollObservation,
        scroll: () -> Void
    ) -> AXScrollMatch {
        precondition(maxScrolls > 0, "bounded scrolling must allow at least one scroll")

        var observation = observe()
        guard observation != .hittable else {
            return AXScrollMatch(matched: true, scrolls: 0, observation: observation)
        }

        for scrollCount in 1...maxScrolls {
            scroll()
            observation = observe()
            if observation == .hittable {
                return AXScrollMatch(
                    matched: true,
                    scrolls: scrollCount,
                    observation: observation
                )
            }
        }

        return AXScrollMatch(
            matched: false,
            scrolls: maxScrolls,
            observation: observation
        )
    }
}

private enum UITestArtifactDirectorySelector {
    private static let fallbackPath = "/private/tmp/making-tracks-artifacts"

    static func directory(simulatorID: String?) -> URL {
        let simulatorID = simulatorID?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let simulatorID, !simulatorID.isEmpty else {
            return URL(fileURLWithPath: fallbackPath, isDirectory: true)
        }
        return URL(
            fileURLWithPath: "\(fallbackPath).\(simulatorID)",
            isDirectory: true
        )
    }

    static func directory(environment: [String: String]) -> URL {
        let simulatorID = ["SIMULATOR_UDID", "MT_SIM_LOCK_UDID"].lazy.compactMap { key in
            environment[key].flatMap { rawValue in
                let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
        }.first
        return directory(simulatorID: simulatorID)
    }
}

private enum RenderedDifferenceWaiter {
    static func wait(
        exceeding threshold: Int,
        attempts: Int,
        interval: TimeInterval = 0,
        sample: () -> Int?
    ) -> RenderedDifferenceMatch {
        wait(
            attempts: attempts,
            interval: interval,
            matches: { $0 > threshold },
            sample: sample
        )
    }

    static func wait(
        atMost threshold: Int,
        attempts: Int,
        interval: TimeInterval = 0,
        sample: () -> Int?
    ) -> RenderedDifferenceMatch {
        wait(
            attempts: attempts,
            interval: interval,
            matches: { $0 <= threshold },
            sample: sample
        )
    }

    private static func wait(
        attempts: Int,
        interval: TimeInterval,
        matches: (Int) -> Bool,
        sample: () -> Int?
    ) -> RenderedDifferenceMatch {
        precondition(attempts > 0, "rendered difference wait must make at least one sample")

        var observed: Int?
        for attempt in 1...attempts {
            observed = sample()
            if let observed, matches(observed) {
                return RenderedDifferenceMatch(
                    matched: true,
                    observed: observed,
                    attempts: attempt
                )
            }
            if interval > 0, attempt < attempts {
                RunLoop.current.run(until: Date().addingTimeInterval(interval))
            }
        }
        return RenderedDifferenceMatch(
            matched: false,
            observed: observed,
            attempts: attempts
        )
    }
}

private enum AXElementReadback {
    static func label(
        for identifier: String,
        using element: (String) -> (exists: Bool, label: String)
    ) -> String? {
        let current = element(identifier)
        return current.exists ? current.label : nil
    }

    static func value(
        for identifier: String,
        using element: (String) -> (exists: Bool, value: () -> String?)
    ) -> String? {
        let current = element(identifier)
        return current.exists ? current.value() : nil
    }
}

private enum AXSliderUpperEdgeAdjuster {
    struct DragPlan: Equatable {
        var start: CGVector
        var end: CGVector
        var holdDuration: TimeInterval
        var fallbackNormalizedPositions: [Double]
    }

    static func upperEdgeDragPlan() -> DragPlan {
        DragPlan(
            start: CGVector(dx: 0.04, dy: 0.5),
            end: CGVector(dx: 1.0, dy: 0.5),
            holdDuration: 0.1,
            fallbackNormalizedPositions: [0.99, 0.995, 1.0]
        )
    }
}

@MainActor
final class MakingTracksCoreLoopUITests: XCTestCase {
    private let placeID = "mt1_00000000000000000000000000"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func assertMinimumInteractiveTarget(
        _ element: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let calculationEpsilon: CGFloat = 0.001
        XCTAssertGreaterThanOrEqual(
            element.frame.width,
            44 - calculationEpsilon,
            file: file,
            line: line
        )
        XCTAssertGreaterThanOrEqual(
            element.frame.height,
            44 - calculationEpsilon,
            file: file,
            line: line
        )
    }

    private func assertAccessibilityInteractiveTarget(
        _ element: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let calculationEpsilon: CGFloat = 0.001
        XCTAssertGreaterThanOrEqual(
            element.frame.width,
            52 - calculationEpsilon,
            file: file,
            line: line
        )
        XCTAssertGreaterThanOrEqual(
            element.frame.height,
            52 - calculationEpsilon,
            file: file,
            line: line
        )
    }

    private func assertContainedInAppFrame(
        _ element: XCUIElement,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let appFrame = app.windows.firstMatch.exists ? app.windows.firstMatch.frame : app.frame
        XCTAssertTrue(
            appFrame.contains(element.frame),
            "\(element.identifier) frame \(element.frame) escapes app frame \(appFrame)",
            file: file,
            line: line
        )
    }

    func testMapHomeExposesBothDoorsAndExploreOpensScopeDirectly() {
        let app = launch(reset: true, pinDiagnostics: true)

        XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMapToFinishLoading(in: app))
        XCTAssertTrue(app.buttons["map.door.explore"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["map.door.journal"].exists)
        XCTAssertFalse(app.buttons["map.menu"].exists)
        XCTAssertFalse(app.buttons["Layers"].exists)

        app.buttons["map.door.explore"].tap()
        XCTAssertTrue(app.scrollViews["explore.root"].waitForExistence(timeout: 5))
        let showHidden = app.switches["explore.scope.include-hidden"]
        let showSaved = app.switches["explore.scope.show-saved"]
        let coverageShading = app.switches["explore.scope.coverage-shading"]
        XCTAssertTrue(showHidden.exists)
        XCTAssertTrue(showSaved.exists)
        XCTAssertTrue(coverageShading.exists)
        XCTAssertEqual(showHidden.value as? String, "0")
        XCTAssertEqual(showSaved.value as? String, "1")
        XCTAssertEqual(coverageShading.value as? String, "1")
        XCTAssertLessThan(showHidden.frame.minY, showSaved.frame.minY)
        XCTAssertLessThan(showSaved.frame.minY, coverageShading.frame.minY)
        XCTAssertEqual(
            showSaved.frame.minY - showHidden.frame.minY,
            52,
            accuracy: 1,
            "The hidden Scope row must keep the measured 52pt pitch."
        )
        XCTAssertEqual(
            coverageShading.frame.minY - showSaved.frame.minY,
            52,
            accuracy: 1,
            "The saved Scope row must keep the measured 52pt pitch."
        )
        XCTAssertEqual(
            showHidden.frame.height,
            showSaved.frame.height,
            accuracy: 0.5
        )
        XCTAssertEqual(
            showSaved.frame.height,
            coverageShading.frame.height,
            accuracy: 0.5
        )
        XCTAssertTrue(app.buttons["explore.scope.category.historic_building"].exists)
        XCTAssertFalse(app.buttons["world.row.scope"].exists)
        let exploreRoot = app.scrollViews["explore.root"]
        let about = app.buttons["explore.row.about"]
        XCTAssertTrue(about.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(
            exploreRoot.frame.maxY - about.frame.maxY,
            64,
            // The root frame includes the 34pt home-indicator safe area; the
            // content adds its deliberate 24pt bottom inset.
            "Quiet Explore destinations must remain bottom rows in the large detent."
        )
        attachScreenshot(named: "explore-door-default", forceExport: true)
        exportMeasurements(
            named: "explore-door-default",
            elements: [
                ("root", exploreRoot),
                ("include-hidden", showHidden),
                ("show-saved", showSaved),
                ("coverage-shading", coverageShading),
                ("about", about),
            ],
            notes: [
                "hidden-to-saved-pitch: \(showSaved.frame.minY - showHidden.frame.minY)",
                "saved-to-coverage-pitch: \(coverageShading.frame.minY - showSaved.frame.minY)",
            ]
        )

        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["map.door.journal"].waitForExistence(timeout: 5))
        app.buttons["map.door.journal"].tap()
        XCTAssertTrue(app.collectionViews["journal.root"].waitForExistence(timeout: 5))
        attachScreenshot(named: "journal-door-default")
    }

    func testDoorsRemainTappableAtAX5InDarkAppearance() {
        let app = launch(
            reset: true,
            accessibilityTextSize: true,
            forceDarkAppearance: true
        )

        XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 10))

        let exploreDoor = app.buttons["map.door.explore"]
        let journalDoor = app.buttons["map.door.journal"]
        XCTAssertTrue(exploreDoor.waitForExistence(timeout: 5))
        XCTAssertTrue(journalDoor.waitForExistence(timeout: 5))
        XCTAssertTrue(exploreDoor.isHittable)
        XCTAssertTrue(journalDoor.isHittable)
        XCTAssertGreaterThanOrEqual(exploreDoor.frame.height, 44)
        XCTAssertGreaterThanOrEqual(journalDoor.frame.height, 44)
        assertNoFrameIntersection(exploreDoor, journalDoor)

        exploreDoor.tap()
        let historicBuildings = app.buttons["explore.scope.category.historic_building"]
        XCTAssertTrue(scrollToHittable(historicBuildings, in: app))
        XCTAssertGreaterThanOrEqual(
            historicBuildings.frame.height,
            38,
            "AX category chips must mount the frozen expanded visual geometry."
        )
        var scopeRowsChecked = 0
        var quietRowsChecked = 0
        for identifier in [
            "explore.scope.include-hidden",
            "explore.scope.show-saved",
            "explore.scope.coverage-shading",
            "explore.row.settings",
            "explore.row.about",
        ] {
            let control = element(identifier: identifier, in: app)
            let isQuietDestination = identifier.hasPrefix("explore.row.")
            XCTAssertTrue(
                isQuietDestination
                    ? scrollToFullyContained(control, in: app)
                    : scrollToHittable(control, in: app)
            )
            XCTAssertTrue(control.isHittable)
            XCTAssertGreaterThanOrEqual(control.frame.height, 44)
            if identifier.hasPrefix("explore.scope.") {
                scopeRowsChecked += 1
                XCTAssertGreaterThanOrEqual(
                    control.frame.height,
                    86,
                    "AX Scope rows must mount the frozen expanded minimum height."
                )
            } else if isQuietDestination {
                quietRowsChecked += 1
                assertContainedInAppFrame(control, in: app)
            }
        }
        XCTAssertEqual(
            scopeRowsChecked,
            3,
            "The AX Scope-row minimum must execute for every scope control."
        )
        XCTAssertEqual(
            quietRowsChecked,
            2,
            "The AX quiet-row containment proof must execute for every destination."
        )
        attachScreenshot(named: "explore-door-ax", forceExport: true)
        exportMeasurements(
            named: "explore-door-ax",
            elements: [
                ("include-hidden", app.switches["explore.scope.include-hidden"]),
                ("show-saved", app.switches["explore.scope.show-saved"]),
                ("coverage-shading", app.switches["explore.scope.coverage-shading"]),
                ("settings", app.buttons["explore.row.settings"]),
                ("about", app.buttons["explore.row.about"]),
            ],
            notes: ["dynamic-type: AX5"]
        )
        app.buttons["Close"].tap()

        XCTAssertTrue(journalDoor.waitForExistence(timeout: 5))
        journalDoor.tap()
        let myTracksRow = app.buttons["journal.row.my-tracks"]
        let firstListRow = app.buttons.matching(identifierPrefix: "lists.row.").firstMatch
        XCTAssertTrue(myTracksRow.waitForExistence(timeout: 5))
        XCTAssertTrue(firstListRow.waitForExistence(timeout: 5))
        XCTAssertTrue(myTracksRow.isHittable)
        XCTAssertTrue(firstListRow.isHittable)
        XCTAssertGreaterThanOrEqual(myTracksRow.frame.height, 44)
        XCTAssertGreaterThanOrEqual(firstListRow.frame.height, 44)
        XCTAssertLessThan(
            myTracksRow.frame.minY,
            firstListRow.frame.minY
        )
        let retrace = app.staticTexts["Retrace"]
        XCTAssertTrue(retrace.waitForExistence(timeout: 5))
        XCTAssertTrue(
            myTracksRow.frame.contains(
                CGPoint(x: retrace.frame.midX, y: retrace.frame.midY)
            ),
            "AX5 Retrace cue must remain inside the My tracks hero"
        )
        XCTAssertEqual(screenshotExportNames["journal-door-ax"], "journal-door-ax")
        attachScreenshot(named: "journal-door-ax")
    }

    func testDoorGlyphEvidenceFixturePinsColumnsAndCopySeparation() {
        struct Metrics {
            let raisedIcon: CGRect
            let raisedCopy: CGRect
            let quietIcon: CGRect
            let quietCopy: CGRect
        }

        func capture(variant: String, accessibility5: Bool) -> Metrics {
            let app = XCUIApplication()
            app.launchArguments = [
                "--ui-testing-door-glyph-fixture",
                variant,
            ]
            if accessibility5 {
                app.launchArguments += [
                    "-UIPreferredContentSizeCategoryName",
                    "UICTContentSizeCategoryAccessibilityXXXL",
                    "-AppleInterfaceStyle",
                    "Dark",
                ]
            }
            app.launch()

            let state = app.staticTexts["door-glyph.fixture.state"]
            XCTAssertTrue(state.waitForExistence(timeout: 5))

            let raisedIcon = element(identifier: "door-glyph.fixture.raised.icon", in: app)
            let raisedCopy = element(identifier: "door-glyph.fixture.raised.copy", in: app)
            let quietIcon = element(identifier: "door-glyph.fixture.quiet.icon", in: app)
            let quietCopy = element(identifier: "door-glyph.fixture.quiet.copy", in: app)
            for element in [raisedIcon, raisedCopy, quietIcon, quietCopy] {
                XCTAssertTrue(element.waitForExistence(timeout: 5))
                assertContainedInAppFrame(element, in: app)
            }

            let suffix = accessibility5 ? "ax" : "default"
            attachScreenshot(
                named: "t2.3-door-glyph-\(variant)-\(suffix)",
                forceExport: true
            )

            let metrics = Metrics(
                raisedIcon: raisedIcon.frame,
                raisedCopy: raisedCopy.frame,
                quietIcon: quietIcon.frame,
                quietCopy: quietCopy.frame
            )
            app.terminate()
            return metrics
        }

        let beforeDefault = capture(variant: "before", accessibility5: false)
        let afterDefault = capture(variant: "after", accessibility5: false)
        let beforeAX = capture(variant: "before", accessibility5: true)
        let afterAX = capture(variant: "after", accessibility5: true)

        XCTAssertEqual(beforeDefault.raisedIcon.width, 26, accuracy: 1)
        XCTAssertEqual(beforeDefault.quietIcon.width, 26, accuracy: 1)
        XCTAssertEqual(afterDefault.raisedIcon.width, 30, accuracy: 1)
        XCTAssertEqual(afterDefault.quietIcon.width, 27, accuracy: 1)
        XCTAssertEqual(beforeAX.raisedIcon.width, 80, accuracy: 1)
        XCTAssertEqual(beforeAX.quietIcon.width, 80, accuracy: 1)
        XCTAssertEqual(afterAX.raisedIcon.width, 85, accuracy: 1)
        XCTAssertEqual(afterAX.quietIcon.width, 79, accuracy: 1)

        for metrics in [beforeDefault, afterDefault, afterAX] {
            XCTAssertGreaterThanOrEqual(
                metrics.raisedCopy.minX - metrics.raisedIcon.maxX,
                11.9
            )
            XCTAssertGreaterThanOrEqual(
                metrics.quietCopy.minX - metrics.quietIcon.maxX,
                11.9
            )
        }
        XCTAssertLessThan(beforeAX.raisedCopy.minX - beforeAX.raisedIcon.maxX, 0)
        XCTAssertLessThan(beforeAX.quietCopy.minX - beforeAX.quietIcon.maxX, 0)
    }

    func testExploreSavedVisibilityFiltersOnlySavedDiscoveryPinsAndKeepsCategoryScope() {
        let app = launch(
            reset: true,
            seedUserList: true,
            pinDiagnostics: true
        )
        XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMapToFinishLoading(in: app))
        XCTAssertTrue(waitForSourceFeatureCount(2, in: app))

        openScope(in: app)
        let showSaved = "explore.scope.show-saved"
        let attractionCategory = "explore.scope.category.attraction"
        XCTAssertTrue(app.switches[showSaved].waitForExistence(timeout: 5))
        XCTAssertEqual(app.switches[showSaved].value as? String, "1")
        XCTAssertEqual(app.buttons[attractionCategory].value as? String, "Selected")

        tapSwitch(in: app, identifier: showSaved, expectedValue: "0")
        XCTAssertEqual(app.buttons[attractionCategory].value as? String, "Selected")
        app.buttons["Close"].tap()

        XCTAssertTrue(
            waitForSourceFeatureCount(1, in: app),
            "Show saved OFF must remove exactly the saved fixture discovery pin."
        )

        openScope(in: app)
        XCTAssertEqual(app.switches[showSaved].value as? String, "0")
        XCTAssertEqual(app.buttons[attractionCategory].value as? String, "Selected")
        tapSwitch(in: app, identifier: showSaved, expectedValue: "1")
        app.buttons["Close"].tap()

        XCTAssertTrue(
            waitForSourceFeatureCount(2, in: app),
            "Show saved ON must restore the saved fixture discovery pin."
        )
    }

    func testExploreDoorIndicatorAndClearScopeRoundTrip() {
        let app = launch(reset: true)
        XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 10))

        let exploreDoor = app.buttons["map.door.explore"]
        XCTAssertTrue(exploreDoor.waitForExistence(timeout: 5))
        XCTAssertEqual(exploreDoor.value as? String, "Default scope")
        attachScreenshot(named: "explore-door-scope-default", forceExport: true)
        exportMeasurements(
            named: "explore-door-scope-default",
            elements: [("explore-door", exploreDoor)],
            notes: ["accessibility-value: Default scope"]
        )

        exploreDoor.tap()
        tapSwitch(
            in: app,
            identifier: "explore.scope.include-hidden",
            expectedValue: "1"
        )
        let clear = app.buttons["explore.scope.clear"]
        XCTAssertTrue(scrollToHittable(clear, in: app))
        app.buttons["Close"].tap()
        XCTAssertTrue(exploreDoor.waitForExistence(timeout: 5))
        XCTAssertEqual(exploreDoor.value as? String, "Scope adjusted")
        attachScreenshot(named: "explore-door-scope-adjusted", forceExport: true)
        exportMeasurements(
            named: "explore-door-scope-adjusted",
            elements: [("explore-door", exploreDoor)],
            notes: ["accessibility-value: Scope adjusted"]
        )

        exploreDoor.tap()
        XCTAssertTrue(scrollToHittable(clear, in: app))
        clear.tap()
        XCTAssertTrue(waitForNonExistence(of: clear, timeout: 5))
        app.buttons["Close"].tap()
        XCTAssertTrue(exploreDoor.waitForExistence(timeout: 5))
        XCTAssertEqual(exploreDoor.value as? String, "Default scope")
    }

    func testJournalDoorPreservesLiteralLongContentAndProgressAtAX5() {
        let placeName =
            "[Riverside](https://example.com) **Plaques** "
            + String(repeating: "x", count: 155)
        let listName =
            "Longest list **literal** 0123456789 0123456789 0123456789 "
            + "0123456789 0123456789!"
        XCTAssertEqual(placeName.count, 200)
        XCTAssertEqual(listName.unicodeScalars.count, 80)

        let app = launch(
            reset: true,
            accessibilityTextSize: true,
            seedJournalDoorTextStress: true
        )

        XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 10))
        openJournalDoor(in: app)

        let hero = app.buttons["journal.row.my-tracks"]
        let metadata = app.staticTexts.matching(
            NSPredicate(
                format: "label == %@",
                "2 visits · last: \(placeName)"
            )
        ).firstMatch
        let retrace = app.staticTexts["Retrace"]
        XCTAssertTrue(hero.waitForExistence(timeout: 5))
        XCTAssertTrue(metadata.waitForExistence(timeout: 5))
        XCTAssertTrue(retrace.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(
            metadata.frame.height,
            100,
            "A maximum-length hostile place name must grow beyond one AX5 line"
        )
        XCTAssertFalse(
            metadata.frame.intersects(retrace.frame),
            "Wrapped metadata must not collide with the Retrace cue"
        )
        XCTAssertTrue(
            hero.frame.contains(
                CGPoint(x: retrace.frame.midX, y: retrace.frame.midY)
            ),
            "Retrace must remain inside the growing hero"
        )

        let longListRow = app.buttons.matching(identifierPrefix: "lists.row.").matching(
            NSPredicate(format: "label CONTAINS %@", listName)
        ).firstMatch
        XCTAssertTrue(scrollToHittable(longListRow, in: app))
        XCTAssertTrue(longListRow.isHittable)
        XCTAssertTrue(
            longListRow.label.contains(listName),
            "Markdown-shaped list punctuation must remain literal"
        )
        XCTAssertEqual(
            longListRow.value as? String,
            "1 of 1 seen",
            "The live root must expose its derived progress count as a non-colour value"
        )
        XCTAssertGreaterThan(
            longListRow.frame.height,
            120,
            "A maximum-length list name must grow instead of clipping to one line"
        )
    }

    func testAXResamplerUsesFreshSamplesAfterPredicateMiss() {
        var samples = ["stale", "Ghost Sign, Attraction, not visited"]

        let result = AXResampler.matches(
            expected: "Ghost Sign, Attraction, not visited",
            attempts: 2,
            sample: { samples.removeFirst() }
        )

        XCTAssertTrue(result.matched)
        XCTAssertEqual(result.observed, "Ghost Sign, Attraction, not visited")
        XCTAssertTrue(samples.isEmpty)
    }

    func testAXResamplerFailsForElementScopedWrongLabelEvenWhenExpectedLabelExistsElsewhere() {
        let elementsByIdentifier = [
            "map.pin.target": AXStubElement(exists: true, label: "Ghost Sign, Attraction, not visited"),
            "map.pin.other": AXStubElement(exists: true, label: "Art Deco Cinema, Historic Building, not visited"),
        ]

        let result = AXResampler.matches(
            expected: "Art Deco Cinema, Historic Building, not visited",
            attempts: 3,
            sample: {
                AXElementReadback.label(for: "map.pin.target") { identifier in
                    let element = elementsByIdentifier[identifier] ?? AXStubElement(exists: false, label: "")
                    return (exists: element.exists, label: element.label)
                }
            }
        )

        XCTAssertEqual(elementsByIdentifier["map.pin.other"]?.label, "Art Deco Cinema, Historic Building, not visited")
        XCTAssertFalse(result.matched)
        XCTAssertEqual(result.observed, "Ghost Sign, Attraction, not visited")
    }

    func testAXElementReadbackSkipsValueLookupWhenElementDisappears() {
        var valueWasRead = false

        let result = AXElementReadback.value(for: "settings.pin-size") { _ in
            (
                exists: false,
                value: {
                    valueWasRead = true
                    return "160%"
                }
            )
        }

        XCTAssertNil(result)
        XCTAssertFalse(valueWasRead)
    }

    func testAXValueWaiterToleratesMissingSamplesUntilExpectedValueAppears() {
        var samples: [String?] = [nil, "1", "0"]

        let result = AXValueWaiter.wait(expected: "0", attempts: 3, interval: 0) {
            samples.removeFirst()
        }

        XCTAssertTrue(result.matched)
        XCTAssertEqual(result.observed, "0")
        XCTAssertTrue(samples.isEmpty)
    }

    func testAXValueWaiterReportsMissingWithoutThrowingWhenElementNeverReturns() {
        let result = AXValueWaiter.wait(expected: "160%", attempts: 2, interval: 0) {
            nil
        }

        XCTAssertFalse(result.matched)
        XCTAssertNil(result.observed)
    }

    func testAXValueWaiterMatchesPredicateAfterMissingSample() {
        var samples: [String?] = [nil, "source applied features:24 layer:true"]

        let result = AXValueWaiter.wait(
            matching: { $0.hasPrefix("source applied features:24") },
            attempts: 2,
            interval: 0
        ) {
            samples.removeFirst()
        }

        XCTAssertTrue(result.matched)
        XCTAssertEqual(result.observed, "source applied features:24 layer:true")
        XCTAssertTrue(samples.isEmpty)
    }

    func testAXFocusAcquirerSkipsRequestWhenAlreadyFocused() {
        var requests = 0
        let result = AXFocusAcquirer.acquire(
            maxAttempts: 3,
            interval: 0,
            isFocused: { true },
            requestFocus: { requests += 1 }
        )

        XCTAssertEqual(result, AXFocusAcquisitionMatch(matched: true, attempts: 0))
        XCTAssertEqual(requests, 0)
    }

    func testAXFocusAcquirerReacquiresWithinBound() {
        var samples = [false, false, true]
        var requests = 0
        let result = AXFocusAcquirer.acquire(
            maxAttempts: 3,
            interval: 0,
            isFocused: { samples.removeFirst() },
            requestFocus: { requests += 1 }
        )

        XCTAssertEqual(result, AXFocusAcquisitionMatch(matched: true, attempts: 2))
        XCTAssertEqual(requests, 2)
    }

    func testAXFocusAcquirerReportsExhaustedBound() {
        var samples = [false, false, false, false]
        var requests = 0
        let result = AXFocusAcquirer.acquire(
            maxAttempts: 3,
            interval: 0,
            isFocused: { samples.removeFirst() },
            requestFocus: { requests += 1 }
        )

        XCTAssertEqual(result, AXFocusAcquisitionMatch(matched: false, attempts: 3))
        XCTAssertEqual(requests, 3)
    }

    func testUITestArtifactDirectorySelectorSeparatesSimulatorIdentities() {
        let first = UITestArtifactDirectorySelector.directory(simulatorID: "simulator-a")
        let second = UITestArtifactDirectorySelector.directory(simulatorID: "simulator-b")

        XCTAssertEqual(first.path, "/private/tmp/making-tracks-artifacts.simulator-a")
        XCTAssertEqual(second.path, "/private/tmp/making-tracks-artifacts.simulator-b")
        XCTAssertNotEqual(first, second)
    }

    func testUITestArtifactDirectorySelectorUsesDocumentedFallbackWithoutIdentity() {
        let fallback = URL(fileURLWithPath: "/private/tmp/making-tracks-artifacts", isDirectory: true)

        XCTAssertEqual(UITestArtifactDirectorySelector.directory(simulatorID: nil), fallback)
        XCTAssertEqual(UITestArtifactDirectorySelector.directory(simulatorID: ""), fallback)
        XCTAssertEqual(UITestArtifactDirectorySelector.directory(simulatorID: " \n"), fallback)
    }

    func testUITestArtifactDirectorySelectorPrefersXcodeSimulatorIdentity() {
        let directory = UITestArtifactDirectorySelector.directory(environment: [
            "SIMULATOR_UDID": "xcode-simulator",
            "MT_SIM_LOCK_UDID": "wrapper-simulator",
        ])

        XCTAssertEqual(directory.path, "/private/tmp/making-tracks-artifacts.xcode-simulator")
    }

    func testMyTracksRenderedComparisonFrameExcludesBottomSystemChrome() {
        let trackSurface = CGRect(x: 0, y: 100, width: 402, height: 774)

        XCTAssertEqual(
            MyTracksRenderedComparisonFrame.appOwnedIntersection(
                light: trackSurface,
                dark: trackSurface
            ),
            CGRect(x: 1, y: 101, width: 400, height: 739)
        )
    }

    func testAXBoundedScrollerSkipsScrollWhenAlreadyHittable() {
        var scrolls = 0
        let result = AXBoundedScroller.acquire(
            maxScrolls: 3,
            observe: { .hittable },
            scroll: { scrolls += 1 }
        )

        XCTAssertEqual(
            result,
            AXScrollMatch(matched: true, scrolls: 0, observation: .hittable)
        )
        XCTAssertEqual(scrolls, 0)
    }

    func testAXBoundedScrollerReachesHittableWithinBound() {
        var observations: [AXScrollObservation] = [
            .missing,
            .presentNotHittable,
            .hittable,
        ]
        var scrolls = 0
        let result = AXBoundedScroller.acquire(
            maxScrolls: 3,
            observe: { observations.removeFirst() },
            scroll: { scrolls += 1 }
        )

        XCTAssertEqual(
            result,
            AXScrollMatch(matched: true, scrolls: 2, observation: .hittable)
        )
        XCTAssertEqual(scrolls, 2)
        XCTAssertTrue(observations.isEmpty)
    }

    func testAXBoundedScrollerReportsExactBoundAndFinalObservation() {
        var observations: [AXScrollObservation] = [
            .missing,
            .missing,
            .presentNotHittable,
            .presentNotHittable,
        ]
        var scrolls = 0
        let result = AXBoundedScroller.acquire(
            maxScrolls: 3,
            observe: { observations.removeFirst() },
            scroll: { scrolls += 1 }
        )

        XCTAssertEqual(
            result,
            AXScrollMatch(matched: false, scrolls: 3, observation: .presentNotHittable)
        )
        XCTAssertEqual(scrolls, 3)
        XCTAssertTrue(observations.isEmpty)
    }

    func testFixturePinRepositionObservationRejectsOffCentreNonHittablePin() {
        XCTAssertEqual(
            FixturePinRepositionObservation.classify(
                exists: true,
                isHittable: false,
                frameContainsMapCenter: false
            ),
            .presentNotHittable
        )
    }

    func testKeyboardFocusProxyUsesSoftwareKeyboardWhenPresent() {
        XCTAssertEqual(
            KeyboardFocusProxySelector.observe(
                softwareKeyboardPresent: true,
                elementFocused: false
            ),
            KeyboardFocusObservation(
                focused: true,
                proxy: .softwareKeyboardPresence
            )
        )
    }

    func testKeyboardFocusProxyUsesElementFocusWithoutSoftwareKeyboard() {
        XCTAssertEqual(
            KeyboardFocusProxySelector.observe(
                softwareKeyboardPresent: false,
                elementFocused: true
            ),
            KeyboardFocusObservation(
                focused: true,
                proxy: .focusedElementQuery
            )
        )
    }

    func testKeyboardFocusProxyRejectsFreshUnfocusedField() {
        XCTAssertEqual(
            KeyboardFocusProxySelector.observe(
                softwareKeyboardPresent: false,
                elementFocused: false
            ),
            KeyboardFocusObservation(
                focused: false,
                proxy: .focusedElementQuery
            )
        )
    }

    func testRenderedDifferenceWaiterWaitsForValueAboveThreshold() {
        var samples: [Int?] = [nil, 100, 101]
        let result = RenderedDifferenceWaiter.wait(
            exceeding: 100,
            attempts: 3,
            interval: 0,
            sample: { samples.removeFirst() }
        )

        XCTAssertEqual(
            result,
            RenderedDifferenceMatch(matched: true, observed: 101, attempts: 3)
        )
    }

    func testRenderedDifferenceWaiterReportsExhaustedBound() {
        var samples: [Int?] = [nil, 0, 100]
        let result = RenderedDifferenceWaiter.wait(
            exceeding: 100,
            attempts: 3,
            interval: 0,
            sample: { samples.removeFirst() }
        )

        XCTAssertEqual(
            result,
            RenderedDifferenceMatch(matched: false, observed: 100, attempts: 3)
        )
    }

    func testRenderedDifferenceWaiterWaitsForValueAtMostThreshold() {
        var samples: [Int?] = [nil, 101, 0]
        let result = RenderedDifferenceWaiter.wait(
            atMost: 0,
            attempts: 3,
            interval: 0,
            sample: { samples.removeFirst() }
        )

        XCTAssertEqual(
            result,
            RenderedDifferenceMatch(matched: true, observed: 0, attempts: 3)
        )
    }

    func testAXExistenceWaiterWaitsThroughTransientPresence() {
        var samples = [true, true, false]

        let result = AXExistenceWaiter.waitForAbsence(attempts: 3, interval: 0) {
            samples.removeFirst()
        }

        XCTAssertTrue(result.matched)
        XCTAssertEqual(result.observedExists, false)
        XCTAssertTrue(samples.isEmpty)
    }

    func testAXExistenceWaiterReportsStillPresentWhenElementNeverDisappears() {
        let result = AXExistenceWaiter.waitForAbsence(attempts: 2, interval: 0) {
            true
        }

        XCTAssertFalse(result.matched)
        XCTAssertEqual(result.observedExists, true)
    }

    func testAXExistenceWaiterConfirmsContinuousAbsence() {
        var samples = [false, false, false]

        let result = AXExistenceWaiter.confirmContinuousAbsence(attempts: 3, interval: 0) {
            samples.removeFirst()
        }

        XCTAssertTrue(result.matched)
        XCTAssertEqual(result.observedExists, false)
        XCTAssertTrue(samples.isEmpty)
    }

    func testAXExistenceWaiterFailsContinuousAbsenceOnFirstObservedPresence() {
        var samples = [false, true, false]

        let result = AXExistenceWaiter.confirmContinuousAbsence(attempts: 3, interval: 0) {
            samples.removeFirst()
        }

        XCTAssertFalse(result.matched)
        XCTAssertEqual(result.observedExists, true)
        XCTAssertEqual(samples, [false])
    }

    func testAXSliderUpperEdgeDragPlanTargetsCoordinateMaxEdge() {
        let plan = AXSliderUpperEdgeAdjuster.upperEdgeDragPlan()

        XCTAssertGreaterThan(plan.start.dx, 0.0)
        XCTAssertLessThan(plan.start.dx, 0.1)
        XCTAssertEqual(plan.start.dy, 0.5)
        XCTAssertEqual(plan.end.dx, 1.0)
        XCTAssertEqual(plan.end.dy, 0.5)
        XCTAssertEqual(plan.fallbackNormalizedPositions, [0.99, 0.995, 1.0])
    }

    func testFixturePinTapUsesNamedPinAfterMapRepositionAtAX5() {
        let app = launch(reset: true, accessibilityTextSize: true)
        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        let pin = app.buttons["map.pin.\(placeID)"]
        XCTAssertTrue(pin.waitForExistence(timeout: 10))

        let mapCenter = CGPoint(x: map.frame.midX, y: map.frame.midY)
        let match = AXBoundedScroller.acquire(
            maxScrolls: 3,
            observe: {
                let exists = pin.waitForExistence(timeout: 5)
                return FixturePinRepositionObservation.classify(
                    exists: exists,
                    isHittable: exists && pin.isHittable,
                    frameContainsMapCenter: exists && pin.frame.contains(mapCenter)
                )
            },
            scroll: {
                let start = map.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.08, dy: 0.58)
                )
                let end = map.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.08, dy: 0.25)
                )
                start.press(forDuration: 0.1, thenDragTo: end)
            }
        )
        guard match.matched else {
            XCTFail(
                "Fixture accessibility pin map.pin.\(placeID) did not become hittable "
                    + "outside the captured map centre after \(match.scrolls) bounded map "
                    + "repositions; final=\(match.observation), exists=\(pin.exists), "
                    + "hittable=\(pin.isHittable), pinFrame=\(pin.frame), "
                    + "mapCenter=\(mapCenter), mapFrame=\(map.frame)"
            )
            return
        }

        XCTAssertTrue(pin.isHittable)
        XCTAssertFalse(pin.frame.contains(mapCenter))

        tapFixtureCoordinate(in: map)
        XCTAssertFalse(app.staticTexts["Ghost Sign"].waitForExistence(timeout: 2))

        tapFixturePin(in: map, app: app)

        XCTAssertTrue(app.staticTexts["Ghost Sign"].waitForExistence(timeout: 5))
    }

    func testCardTogglesPersistAndRestyleMapPin() {
        let app = launch(reset: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))

        tapFixturePin(in: map, app: app)
        XCTAssertTrue(app.staticTexts["Ghost Sign"].waitForExistence(timeout: 5))
        attachScreenshot(named: "card-open")

        app.buttons["place-card.save"].tap()
        XCTAssertTrue(app.navigationBars["Add to list"].waitForExistence(timeout: 5))
        let wantToGoRow = app.buttons["Want to go"]
        XCTAssertTrue(wantToGoRow.waitForExistence(timeout: 5))
        wantToGoRow.tap()
        app.buttons["list-picker.done"].tap()
        app.buttons["place-card.visited"].tap()
        XCTAssertTrue(waitForButtonLabel("Love", identifier: "place-card.loved", in: app))
        app.buttons["place-card.loved"].tap()
        XCTAssertTrue(waitForButtonLabel("Loved", identifier: "place-card.loved", in: app))
        closePlaceCard(in: app)

        XCTAssertEqual(app.staticTexts["tracks.visit-count.\(placeID)"].label, "Tracks visits: 1")
        XCTAssertTrue(waitForAccessibilityPin(
            in: app,
            placeID: placeID,
            label: "Ghost Sign, Attraction, loved, saved"
        ))
        attachScreenshot(named: "map-after-visited-fade")

        app.terminate()

        let relaunched = launch(reset: false)
        let relaunchedMap = relaunched.otherElements["map.surface"]
        XCTAssertTrue(relaunchedMap.waitForExistence(timeout: 10))
        XCTAssertEqual(relaunched.staticTexts["tracks.visit-count.\(placeID)"].label, "Tracks visits: 1")
        tapFixturePin(in: relaunchedMap, app: relaunched)
        XCTAssertTrue(relaunched.staticTexts["Ghost Sign"].waitForExistence(timeout: 5))
        XCTAssertEqual(relaunched.buttons["place-card.save"].label, "Saved")
        XCTAssertTrue(waitForButtonLabel("Loved", identifier: "place-card.loved", in: relaunched))
    }

    func testFirstRunOnboardingPersistsRegionAndCompletesBeforeRelaunch() {
        let app = launch(reset: true, resetOnboarding: true)

        XCTAssertTrue(app.staticTexts["Interesting places around you"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["map.surface"].exists)
        XCTAssertFalse(app.otherElements["map.loading"].exists)
        XCTAssertTrue(app.staticTexts["onboarding.progress"].waitForExistence(timeout: 5))
        app.buttons["onboarding.next"].tap()

        XCTAssertTrue(app.staticTexts["Where places come from"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Nothing you save leaves unless you choose to share it."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "no one can see where you look")).firstMatch.exists)
        app.buttons["onboarding.next"].tap()

        XCTAssertTrue(app.staticTexts["Choose your first region"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["onboarding.region.uk"].value as? String, "Not selected")
        XCTAssertFalse(app.buttons["onboarding.next"].isEnabled)
        app.buttons["onboarding.region.uk"].tap()
        app.buttons["onboarding.next"].tap()

        XCTAssertTrue(app.staticTexts["Download UK"].waitForExistence(timeout: 5))
        XCTAssertTrue(element(identifier: "onboarding.download.size", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["onboarding.include-images"].exists)
        app.buttons["onboarding.next"].tap()

        XCTAssertTrue(app.staticTexts["Show your position?"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["onboarding.location-requested"].exists)
        app.buttons["onboarding.location.skip"].tap()

        XCTAssertTrue(app.staticTexts["Fresh snow"].waitForExistence(timeout: 5))
        app.buttons["onboarding.finish"].tap()

        XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["map.startup-region"].label, "Startup region: UK")
        XCTAssertFalse(app.staticTexts["Interesting places around you"].exists)

        app.terminate()

        let relaunched = launch(reset: false)
        XCTAssertTrue(relaunched.otherElements["map.surface"].waitForExistence(timeout: 10))
        XCTAssertEqual(relaunched.staticTexts["map.startup-region"].label, "Startup region: UK")
        XCTAssertFalse(relaunched.staticTexts["Interesting places around you"].exists)
    }

    func testReplayOnboardingPreselectsPersistedRegionFromSettings() {
        let app = launch(reset: true, resetOnboarding: true)
        completeOnboardingSelectingUK(in: app)

        openExploreDoor(in: app)
        app.buttons["explore.row.settings"].tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
        let replayOnboardingButton = app.buttons["settings.replay-onboarding"]
        XCTAssertTrue(scrollToHittable(replayOnboardingButton, in: app))
        replayOnboardingButton.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()

        XCTAssertTrue(app.staticTexts["Interesting places around you"].waitForExistence(timeout: 5))
        app.buttons["onboarding.next"].tap()
        app.buttons["onboarding.next"].tap()

        XCTAssertTrue(app.staticTexts["Choose your first region"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["onboarding.region.uk"].value as? String, "Selected")
    }

    func testOnboardingRequestsLocationOnlyOnAffirmativeTap() {
        let app = launch(reset: true, locationNotDetermined: true, resetOnboarding: true)

        app.buttons["onboarding.next"].tap()
        app.buttons["onboarding.next"].tap()
        app.buttons["onboarding.region.malaysia"].tap()
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.staticTexts["Download Malaysia"].waitForExistence(timeout: 5))
        app.buttons["onboarding.next"].tap()

        XCTAssertTrue(app.staticTexts["Show your position?"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["onboarding.location-request-count"].label, "Location requests: 0")
        app.buttons["onboarding.location.allow"].tap()

        XCTAssertTrue(app.staticTexts["Fresh snow"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["onboarding.location-request-count"].label, "Location requests: 1")
    }

    func testOnboardingControlsRemainReachableAtAccessibilityTextSize() {
        let app = launch(reset: true, accessibilityTextSize: true, resetOnboarding: true)

        XCTAssertTrue(app.buttons["onboarding.next"].waitForExistence(timeout: 5))
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.staticTexts["Where places come from"].waitForExistence(timeout: 5))
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.staticTexts["Choose your first region"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["onboarding.region.uk"].waitForExistence(timeout: 5))
        app.buttons["onboarding.region.uk"].tap()
        XCTAssertTrue(waitForButtonEnabled(true, identifier: "onboarding.next", in: app))
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.staticTexts["Download UK"].waitForExistence(timeout: 5))
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.buttons["onboarding.location.skip"].waitForExistence(timeout: 5))
    }

    func testTappingAnotherPinSwitchesOpenCard() throws {
        let app = launch(reset: true, pinDiagnostics: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMapToFinishLoading(in: app))

        XCTAssertTrue(activateFixturePin(
            in: map,
            app: app,
            placeID: placeID,
            title: "Ghost Sign",
            expectedLabel: "Ghost Sign, Attraction, not visited"
        ))
        XCTAssertTrue(app.staticTexts["Ghost Sign"].waitForExistence(timeout: 5))
        let sheet = app.scrollViews.matching(identifierPrefix: "place-card.instance.").firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        let sheetInstanceIdentifier = sheet.identifier

        XCTAssertTrue(activateFixturePin(
            in: map,
            app: app,
            placeID: "mt1_00000000000000000000000001",
            title: "Art Deco Cinema",
            expectedLabel: "Art Deco Cinema, Historic Building, not visited"
        ))
        XCTAssertTrue(app.staticTexts["Art Deco Cinema"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.scrollViews[sheetInstanceIdentifier].exists)
        XCTAssertFalse(app.staticTexts["Ghost Sign"].exists)
        XCTAssertFalse(element(identifier: "place-card.description", in: app).exists)
        let mediaSlot = element(identifier: "place-card.photo", in: app)
        XCTAssertFalse(mediaSlot.waitForExistence(timeout: 1))
        let placeholder = element(identifier: "place-card.photo.placeholder", in: app)
        XCTAssertFalse(placeholder.waitForExistence(timeout: 1))
        let sourceArticle = app.buttons["place-card.source-article"]
        XCTAssertTrue(sourceArticle.exists)
        XCTAssertEqual(sourceArticle.label, "OpenStreetMap source article")
        XCTAssertTrue(sourceArticle.isHittable)
        assertDoesNotExposeURL(sourceArticle)
        attachScreenshot(named: "card-switched-to-art-deco-cinema")

        closePlaceCard(in: app)
        XCTAssertFalse(app.staticTexts["Art Deco Cinema"].waitForExistence(timeout: 2))
    }

    func testPlaceCardOverhaulRendersHierarchyForSavedPlace() {
        let app = launch(reset: true, seedUserList: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))

        openFixtureCard(in: map, app: app)

        let title = element(identifier: "place-card.title", in: app)
        let typeLabel = element(identifier: "place-card.type.label", in: app)
        let description = element(identifier: "place-card.description", in: app)
        let sourceArticle = app.buttons["place-card.source-article"]
        let photo = element(identifier: "place-card.photo", in: app)
        let chips = element(identifier: "place-card.list-chips", in: app)
        let attribution = element(identifier: "place-card.attribution", in: app)

        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "Ghost Sign")
        XCTAssertEqual(typeLabel.label, "Attraction")
        XCTAssertEqual(
            description.label,
            "A hand-painted sign still visible above the old shopfront."
        )
        XCTAssertTrue(sourceArticle.waitForExistence(timeout: 5))
        XCTAssertEqual(sourceArticle.label, "Wikipedia source article")
        assertDoesNotExposeURL(sourceArticle)
        XCTAssertTrue(expandPlaceCardSheet(in: app))
        XCTAssertTrue(sourceArticle.isHittable)

        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        XCTAssertEqual(photo.label, "Photo of Ghost Sign")
        XCTAssertGreaterThan(photo.frame.height, 132)
        XCTAssertLessThanOrEqual(photo.frame.height, 260.5)

        let actionBar = app.otherElements["place-card.action-bar"]
        let saveButton = actionBar.buttons["place-card.save"]
        let seenButton = actionBar.buttons["place-card.visited"]
        XCTAssertTrue(actionBar.waitForExistence(timeout: 5))
        XCTAssertEqual(actionBar.buttons.count, 2)
        XCTAssertTrue(saveButton.exists)
        XCTAssertTrue(seenButton.exists)
        XCTAssertFalse(actionBar.buttons["place-card.hide"].exists)
        let moreButton = app.buttons["place-card.more"]
        XCTAssertTrue(moreButton.exists)
        assertMinimumInteractiveTarget(moreButton)
        assertContainedInAppFrame(moreButton, in: app)
        moreButton.tap()
        let addToListButton = app.buttons["place-card.add-to-list"]
        let initialCopyIDButton = app.buttons["place-card.copy-id"]
        XCTAssertTrue(addToListButton.waitForExistence(timeout: 5))
        XCTAssertTrue(initialCopyIDButton.waitForExistence(timeout: 5))
        XCTAssertEqual(addToListButton.label, "Add to list")
        XCTAssertEqual(initialCopyIDButton.label, "Copy ID")
        XCTAssertTrue(addToListButton.isEnabled)
        XCTAssertTrue(initialCopyIDButton.isEnabled)
        print(
            "PLACE_CARD_COPY_ID_DEFAULT_ROWS add=\(addToListButton.frame) "
                + "copy=\(initialCopyIDButton.frame)"
        )
        XCTAssertLessThanOrEqual(
            addToListButton.frame.maxY,
            initialCopyIDButton.frame.minY + 0.5
        )
        assertContainedInAppFrame(addToListButton, in: app)
        assertContainedInAppFrame(initialCopyIDButton, in: app)
        addToListButton.tap()
        XCTAssertTrue(app.navigationBars["Add to list"].waitForExistence(timeout: 5))
        app.buttons["list-picker.done"].tap()
        XCTAssertFalse(app.buttons["place-card.add-to-list"].exists)

        app.buttons["place-card.more"].tap()
        let copyIDButton = app.buttons["place-card.copy-id"]
        XCTAssertTrue(copyIDButton.waitForExistence(timeout: 5))
        XCTAssertEqual(copyIDButton.label, "Copy ID")
        copyIDButton.tap()

        let copiedButton = app.buttons["place-card.copy-id"]
        XCTAssertTrue(copiedButton.exists)
        XCTAssertEqual(copiedButton.label, "Copied")
        XCTAssertFalse(copiedButton.isEnabled)
        XCTAssertTrue(waitForNonExistence(of: copiedButton, timeout: 3))
        XCTAssertTrue(saveButton.isHittable, "Copy confirmation dismissal must restore the place card")

        app.buttons["place-card.more"].tap()
        XCTAssertTrue(copyIDButton.waitForExistence(timeout: 5))
        XCTAssertEqual(copyIDButton.label, "Copy ID")
        XCTAssertTrue(addToListButton.waitForExistence(timeout: 5))
        addToListButton.tap()
        XCTAssertTrue(app.navigationBars["Add to list"].waitForExistence(timeout: 5))
        app.buttons["list-picker.done"].tap()
        XCTAssertTrue(waitForNonExistence(of: copyIDButton, timeout: 3))
        XCTAssertTrue(saveButton.isHittable, "A subsequent menu action must restore the place card")
        XCTAssertEqual(seenButton.label, "Seen")
        let saveFrameBeforeAttributionScroll = saveButton.frame
        XCTAssertTrue(chips.waitForExistence(timeout: 5))
        XCTAssertTrue(chips.label.contains("Date night"))

        XCTAssertTrue(scrollToExistence(of: attribution, in: app))
        XCTAssertTrue(attribution.label.contains("Fixture photo"))

        assertVerticallyOrdered([
            ("title", title),
            ("type", typeLabel),
            ("photo", photo),
            ("description", description),
            ("sourceArticle", sourceArticle),
            ("chips", chips),
            ("attribution", attribution),
        ])
        XCTAssertLessThan(abs(saveButton.frame.minY - saveFrameBeforeAttributionScroll.minY), 3)
        XCTAssertTrue(saveButton.isHittable)
        XCTAssertFalse(actionBar.buttons["place-card.hide"].exists)
    }

    func testPlaceCardMoreMenuCopyConfirmationRemainsReachableAtAX5() {
        let app = launch(
            reset: true,
            accessibilityTextSize: true,
            seedUserList: true
        )
        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        openFixtureCard(in: map, app: app)

        let moreButton = app.buttons["place-card.more"]
        XCTAssertTrue(moreButton.waitForExistence(timeout: 5))
        let accessibilityTargetPredicate = NSPredicate { object, _ in
            guard let element = object as? XCUIElement else { return false }
            return element.frame.width >= 51.999
                && element.frame.height >= 51.999
        }
        let minimumTargetExpectation = XCTNSPredicateExpectation(
            predicate: accessibilityTargetPredicate,
            object: moreButton
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [minimumTargetExpectation], timeout: 5),
            .completed
        )
        print("PLACE_CARD_COPY_ID_AX_MORE frame=\(moreButton.frame) app=\(app.frame)")
        assertAccessibilityInteractiveTarget(moreButton)
        assertContainedInAppFrame(moreButton, in: app)
        moreButton.tap()

        let addToListButton = app.buttons["place-card.add-to-list"]
        let copyIDButton = app.buttons["place-card.copy-id"]
        XCTAssertTrue(addToListButton.waitForExistence(timeout: 5))
        XCTAssertTrue(copyIDButton.waitForExistence(timeout: 5))
        XCTAssertEqual(addToListButton.label, "Add to list")
        XCTAssertEqual(copyIDButton.label, "Copy ID")
        XCTAssertTrue(addToListButton.isEnabled)
        XCTAssertTrue(copyIDButton.isEnabled)
        print(
            "PLACE_CARD_COPY_ID_AX_ROWS add=\(addToListButton.frame) "
                + "copy=\(copyIDButton.frame)"
        )
        XCTAssertLessThanOrEqual(
            addToListButton.frame.maxY,
            copyIDButton.frame.minY + 0.5
        )
        assertContainedInAppFrame(addToListButton, in: app)
        assertContainedInAppFrame(copyIDButton, in: app)

        copyIDButton.tap()

        let copiedButton = app.buttons["place-card.copy-id"]
        XCTAssertTrue(copiedButton.exists)
        XCTAssertEqual(copiedButton.label, "Copied")
        XCTAssertFalse(copiedButton.isEnabled)

        XCTAssertTrue(waitForNonExistence(of: copiedButton, timeout: 3))
        XCTAssertTrue(moreButton.isHittable)
        moreButton.tap()
        XCTAssertTrue(copyIDButton.waitForExistence(timeout: 5))
        XCTAssertEqual(copyIDButton.label, "Copy ID")
    }

    func testSavedPlaceCardOmitsHideAcrossVisitStates() {
        let app = launch(reset: true, seedUserList: true)
        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        openFixtureCard(in: map, app: app)

        let actionBar = app.otherElements["place-card.action-bar"]
        XCTAssertTrue(actionBar.waitForExistence(timeout: 5))
        XCTAssertFalse(actionBar.buttons["place-card.hide"].exists)
        actionBar.buttons["place-card.visited"].tap()
        XCTAssertFalse(actionBar.buttons["place-card.hide"].exists)
        actionBar.buttons["place-card.loved"].tap()
        XCTAssertFalse(actionBar.buttons["place-card.hide"].exists)
    }

    func testMaterialChipExtendsHitTargetBeyondVisualCapsule() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-fixture-map",
            "--ui-testing-reset-database",
            "--ui-testing-chip-target",
        ]
        app.launch()

        // `contentShape(.interaction, ...)` expands the accessibility frame,
        // so only rendered accent pixels identify the visible capsule.
        let chip = app.buttons["chip-target.left"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        let chipFrame = chip.frame
        let screenshot = app.screenshot()
        guard let raster = RenderedPixelRaster(
            screenshot: screenshot,
            appFrame: app.frame
        ) else {
            XCTFail("Could not decode the app screenshot")
            return
        }
        guard let visualCapsuleBounds = raster.verticalTokenBounds(
            RenderedRGB(10, 107, 92),
            in: chipFrame,
            tolerance: 8
        ) else {
            XCTFail("Could not locate the accent capsule pixels inside the chip")
            return
        }
        let visualCapsuleHeight: CGFloat = 22
        let requiredHitOutset: CGFloat = 11
        XCTAssertEqual(
            visualCapsuleBounds.upperBound - visualCapsuleBounds.lowerBound,
            visualCapsuleHeight,
            accuracy: 1.5
        )
        let visualCenterY = (
            visualCapsuleBounds.lowerBound + visualCapsuleBounds.upperBound
        ) / 2
        let topOutsideVisualCapsule = CGPoint(
            x: chipFrame.midX,
            y: visualCenterY - (visualCapsuleHeight / 2) - requiredHitOutset
        )
        let bottomOutsideVisualCapsule = CGPoint(
            x: chipFrame.midX,
            y: visualCenterY + (visualCapsuleHeight / 2) + requiredHitOutset
        )

        let appFrame = app.frame
        func coordinate(at point: CGPoint) -> XCUICoordinate {
            app.coordinate(withNormalizedOffset: CGVector(
                dx: (point.x - appFrame.minX) / appFrame.width,
                dy: (point.y - appFrame.minY) / appFrame.height
            ))
        }

        let activationCount = app.staticTexts["chip-target.activation-count"]
        XCTAssertTrue(activationCount.waitForExistence(timeout: 5))
        func waitForActivationCount(_ expected: String) -> Bool {
            let predicate = NSPredicate(
                format: "exists == true AND label == %@",
                expected
            )
            let expectation = XCTNSPredicateExpectation(
                predicate: predicate,
                object: activationCount
            )
            return XCTWaiter.wait(
                for: [expectation],
                timeout: 5
            ) == .completed
        }

        coordinate(at: topOutsideVisualCapsule).press(forDuration: 0.2)
        XCTAssertTrue(waitForActivationCount("1"))

        coordinate(at: bottomOutsideVisualCapsule).tap()
        XCTAssertTrue(waitForActivationCount("2"))
    }

    func testMaterialChipTiledAdjacencyRoutesGapToExactlyOneNearerAction() {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-fixture-map",
            "--ui-testing-reset-database",
            "--ui-testing-chip-target",
        ]
        app.launch()

        let left = app.buttons["chip-target.left"]
        let right = app.buttons["chip-target.right"]
        XCTAssertTrue(left.waitForExistence(timeout: 5))
        XCTAssertTrue(right.waitForExistence(timeout: 5))
        let visibleGap = right.frame.minX - left.frame.maxX
        XCTAssertGreaterThan(visibleGap, 0)
        XCTAssertLessThan(visibleGap, 22)

        let appFrame = app.frame
        func coordinate(at point: CGPoint) -> XCUICoordinate {
            app.coordinate(withNormalizedOffset: CGVector(
                dx: (point.x - appFrame.minX) / appFrame.width,
                dy: (point.y - appFrame.minY) / appFrame.height
            ))
        }
        func waitForCount(_ identifier: String, _ expected: String) -> Bool {
            let label = app.staticTexts[identifier]
            let predicate = NSPredicate(
                format: "exists == true AND label == %@",
                expected
            )
            return XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(predicate: predicate, object: label)],
                timeout: 5
            ) == .completed
        }

        coordinate(at: CGPoint(x: left.frame.maxX + 1, y: left.frame.midY)).tap()
        XCTAssertTrue(waitForCount("chip-target.left-count", "1"))
        XCTAssertTrue(waitForCount("chip-target.right-count", "0"))

        coordinate(at: CGPoint(x: right.frame.minX - 1, y: right.frame.midY)).tap()
        XCTAssertTrue(waitForCount("chip-target.left-count", "1"))
        XCTAssertTrue(waitForCount("chip-target.right-count", "1"))
    }

    func testPlaceCardKeepsSnowTokensInDarkSystemAppearance() throws {
        let app = launch(reset: true, forceDarkAppearance: true)
        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        openFixtureCard(in: map, app: app)

        let sheet = app.scrollViews.matching(
            identifierPrefix: "place-card.instance."
        ).firstMatch
        let actionBar = app.otherElements["place-card.action-bar"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        XCTAssertTrue(actionBar.waitForExistence(timeout: 5))
        XCTAssertTrue(actionBar.buttons["place-card.visited"].isHittable)

        let screenshot = app.screenshot()
        let raster = try XCTUnwrap(
            RenderedPixelRaster(screenshot: screenshot, appFrame: app.frame)
        )
        let cardFrame = sheet.frame.union(actionBar.frame)
        XCTAssertGreaterThan(
            raster.tokenCount(RenderedRGB(251, 250, 242), in: cardFrame, tolerance: 8),
            1_000,
            "Snow surface must remain #FBFAF2 under a dark system appearance."
        )
        XCTAssertGreaterThan(
            raster.tokenCount(RenderedRGB(10, 107, 92), in: cardFrame, tolerance: 8),
            250,
            "The Snow accent-filled Seen control must not resolve to a system-dark colour."
        )

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "place-card-snow-under-dark-system"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testSnowSettingsAdaptiveInkIsLegibleAndInvariantAcrossSystemAppearances() throws {
        let provenance = XCTAttachment(
            string: "Dark-state provenance: INJECTED through --ui-testing-color-scheme on Xcode 26.6 / iOS 26.5. System-delivered appearance is untestable under xcodebuild due to Apple thread 812656; the invariant under test is that the production Snow pin beats the injected color scheme."
        )
        provenance.name = "snow-theme-lock-dark-state-provenance"
        provenance.lifetime = .keepAlways
        add(provenance)

        let light = try XCTUnwrap(captureSnowSettingsThemeLock(
            forceDarkAppearance: false,
            appearanceName: "light"
        ))
        let lightAppearance = try XCTUnwrap(light.regions["appearance"])
        let legacyLight = try XCTUnwrap(captureSnowSettingsThemeLock(
            forceDarkAppearance: false,
            disableMaterialModeLock: true,
            appearanceName: "legacy-light",
            appearanceTarget: .matches(lightAppearance)
        ))
        let dark = try XCTUnwrap(captureSnowSettingsThemeLock(
            forceDarkAppearance: true,
            appearanceName: "dark"
        ))
        let darkAppearance = try XCTUnwrap(dark.regions["appearance"])
        let legacyDark = try XCTUnwrap(captureSnowSettingsThemeLock(
            forceDarkAppearance: true,
            disableMaterialModeLock: true,
            appearanceName: "legacy-dark",
            appearanceTarget: .differs(darkAppearance)
        ))

        let regionNames = [
            "appearance", "offline-maps", "coverage", "map-data",
            "location", "diagnostics", "replay-welcome",
        ]
        let frozenEvidenceRegionNames = Set(["appearance", "map-data", "location"])
        XCTAssertEqual(Set(legacyLight.regions.keys), Set(regionNames))
        XCTAssertEqual(Set(light.regions.keys), Set(regionNames))
        XCTAssertEqual(Set(dark.regions.keys), Set(regionNames))
        XCTAssertEqual(Set(legacyDark.regions.keys), Set(regionNames))

        let raisedSurface = RenderedRGB(255, 255, 255)
        var measurements = [
            "evidence_class: nondeterministic-content",
            "comparison_oracle: inclusive raster envelopes covering opaque card regions; exact fixed Light/Dark and legacy/fixed Light equality",
        ]
        for name in regionNames {
            let legacyLightRegion = try XCTUnwrap(legacyLight.regions[name], name)
            let lightRegion = try XCTUnwrap(light.regions[name], name)
            let darkRegion = try XCTUnwrap(dark.regions[name], name)
            let legacyDarkRegion = try XCTUnwrap(legacyDark.regions[name], name)
            XCTAssertEqual(legacyLightRegion.comparisonFrame, lightRegion.comparisonFrame, name)
            XCTAssertEqual(lightRegion.comparisonFrame, darkRegion.comparisonFrame, name)
            XCTAssertEqual(darkRegion.comparisonFrame, legacyDarkRegion.comparisonFrame, name)
            XCTAssertEqual(legacyLightRegion.primaryInkFrame, lightRegion.primaryInkFrame, name)
            XCTAssertEqual(lightRegion.primaryInkFrame, darkRegion.primaryInkFrame, name)
            XCTAssertEqual(darkRegion.primaryInkFrame, legacyDarkRegion.primaryInkFrame, name)
            XCTAssertEqual(legacyLightRegion.secondaryInkFrame, lightRegion.secondaryInkFrame, name)
            XCTAssertEqual(lightRegion.secondaryInkFrame, darkRegion.secondaryInkFrame, name)
            XCTAssertEqual(darkRegion.secondaryInkFrame, legacyDarkRegion.secondaryInkFrame, name)

            let systemDifferenceCount = try XCTUnwrap(
                lightRegion.raster.differingPixelCount(
                    comparedTo: darkRegion.raster,
                    in: lightRegion.comparisonFrame,
                    tolerance: 0
                ),
                name
            )
            let lightBaselineDifferenceCount = try XCTUnwrap(
                legacyLightRegion.raster.differingPixelCount(
                    comparedTo: lightRegion.raster,
                    in: lightRegion.comparisonFrame,
                    tolerance: 0
                ),
                name
            )
            let legacyDarkDifferenceCount = try XCTUnwrap(
                legacyDarkRegion.raster.differingPixelCount(
                    comparedTo: darkRegion.raster,
                    in: darkRegion.comparisonFrame,
                    tolerance: 0
                ),
                name
            )
            XCTAssertEqual(
                systemDifferenceCount,
                0,
                "\(name) must render identically in forced Light and Dark appearances"
            )
            XCTAssertEqual(
                lightBaselineDifferenceCount,
                0,
                "\(name) fixed Light must remain byte-identical to the legacy Light rendering"
            )

            guard frozenEvidenceRegionNames.contains(name) else { continue }
            let primaryInkFrame = try XCTUnwrap(darkRegion.primaryInkFrame, name)
            let primaryInkPixels = darkRegion.raster.contrastPixelCount(
                against: raisedSurface,
                minimum: 4.5,
                in: primaryInkFrame
            )
            let primaryContrast = darkRegion.raster.highestContrastRatio(
                against: raisedSurface,
                in: primaryInkFrame
            ) ?? 0
            let primaryBackgroundPixels = darkRegion.raster.tokenCount(
                raisedSurface,
                in: primaryInkFrame,
                tolerance: 3
            )
            let backgroundPixels = darkRegion.raster.tokenCount(
                raisedSurface,
                in: darkRegion.comparisonFrame,
                tolerance: 3
            )

            XCTAssertGreaterThan(
                legacyDarkDifferenceCount,
                100,
                "\(name) oracle must detect the legacy Dark adaptive-colour regression"
            )
            XCTAssertGreaterThan(
                primaryInkPixels,
                8,
                "\(name) must render primary adaptive ink at WCAG AA contrast on Snow"
            )
            XCTAssertGreaterThanOrEqual(
                primaryContrast,
                4.5,
                "\(name) primary adaptive ink must clear WCAG AA on Snow"
            )
            XCTAssertGreaterThan(
                primaryBackgroundPixels,
                primaryInkPixels,
                "\(name) primary contrast sample must be dominated by its local Snow background"
            )
            XCTAssertGreaterThan(
                backgroundPixels,
                100,
                "\(name) must visibly render the Snow raised-surface token"
            )

            var line = String(
                format: "%@: frame=%.2f,%.2f,%.2f,%.2f system_diff_pixels=%d light_baseline_diff_pixels=%d legacy_dark_diff_pixels=%d primary_aa_pixels=%d primary_max_contrast=%.3f primary_background_pixels=%d background_pixels=%d",
                name,
                darkRegion.comparisonFrame.minX,
                darkRegion.comparisonFrame.minY,
                darkRegion.comparisonFrame.width,
                darkRegion.comparisonFrame.height,
                systemDifferenceCount,
                lightBaselineDifferenceCount,
                legacyDarkDifferenceCount,
                primaryInkPixels,
                primaryContrast,
                primaryBackgroundPixels,
                backgroundPixels
            )
            if let secondaryInkFrame = darkRegion.secondaryInkFrame {
                let secondaryInkPixels = darkRegion.raster.contrastPixelCount(
                    against: raisedSurface,
                    minimum: 3,
                    in: secondaryInkFrame
                )
                let secondaryContrast = darkRegion.raster.highestContrastRatio(
                    against: raisedSurface,
                    in: secondaryInkFrame
                ) ?? 0
                let secondaryBackgroundPixels = darkRegion.raster.tokenCount(
                    raisedSurface,
                    in: secondaryInkFrame,
                    tolerance: 3
                )
                XCTAssertGreaterThan(
                    secondaryInkPixels,
                    8,
                    "\(name) must render secondary adaptive ink at legible contrast on Snow"
                )
                XCTAssertGreaterThanOrEqual(
                    secondaryContrast,
                    3,
                    "\(name) secondary adaptive ink must preserve the legible Light rendering on Snow"
                )
                XCTAssertGreaterThan(
                    secondaryBackgroundPixels,
                    secondaryInkPixels,
                    "\(name) secondary contrast sample must be dominated by its local Snow background"
                )
                line += String(
                    format: " secondary_3_to_1_pixels=%d secondary_max_contrast=%.3f secondary_background_pixels=%d",
                    secondaryInkPixels,
                    secondaryContrast,
                    secondaryBackgroundPixels
                )
            }
            measurements.append(line)
        }
        exportTextArtifact(
            named: "snow-theme-lock-measurements",
            contents: measurements.joined(separator: "\n") + "\n"
        )
    }

    func testSavedTapReopensListPickerForPerListRemoval() {
        let app = launch(reset: true, seedUserList: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        openFixtureCard(in: map, app: app)

        let saveButton = app.otherElements["place-card.action-bar"].buttons["place-card.save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForButtonLabel("Saved", identifier: "place-card.save", in: app))
        XCTAssertTrue(element(identifier: "place-card.list-chips", in: app).label.contains("Date night"))

        saveButton.tap()
        XCTAssertTrue(app.navigationBars["Add to list"].waitForExistence(timeout: 5))
        let dateNightRow = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "list-picker.row.",
            "Date night"
        )).firstMatch
        XCTAssertTrue(dateNightRow.waitForExistence(timeout: 5))
        dateNightRow.tap()
        app.buttons["list-picker.done"].tap()

        XCTAssertTrue(waitForButtonLabel("Save", identifier: "place-card.save", in: app))
        XCTAssertFalse(element(identifier: "place-card.list-chips", in: app).exists)
    }

    func testDeletingOnlyCustomListRefreshesRenderedSavedPin() {
        let app = launch(reset: true, seedUserList: true, pinDiagnostics: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMapToFinishLoading(in: app))
        XCTAssertTrue(waitForAccessibilityPin(
            in: app,
            placeID: placeID,
            label: "Ghost Sign, Attraction, not visited, saved"
        ))
        let pin = app.buttons["map.pin.\(placeID)"]
        let savedBookmarkPixels = waitForBookmarkPixelCount(
            around: pin,
            in: app,
            matching: { $0 >= 12 },
            failure: "Expected rendered bookmark badge pixels before deleting the containing list"
        )

        openJournalDoor(in: app)
        let dateNightRow = app.buttons.matching(identifierPrefix: "lists.row.").matching(
            NSPredicate(format: "label CONTAINS %@", "Date night")
        ).firstMatch
        XCTAssertTrue(dateNightRow.waitForExistence(timeout: 5))
        dateNightRow.swipeLeft()
        let deleteButton = app.buttons.matching(identifierPrefix: "lists.delete.").firstMatch
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5))
        deleteButton.tap()
        let confirmDelete = app.buttons.matching(identifier: "lists.delete.confirm").firstMatch
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: 5))
        confirmDelete.tap()
        XCTAssertTrue(waitForNonExistence(of: dateNightRow, timeout: 5))
        app.buttons["Close"].tap()

        XCTAssertTrue(waitForAccessibilityPin(
            in: app,
            placeID: placeID,
            label: "Ghost Sign, Attraction, not visited"
        ))
        _ = waitForBookmarkPixelCount(
            around: pin,
            in: app,
            matching: { $0 * 3 < savedBookmarkPixels },
            failure: "Expected rendered bookmark badge pixels to clear after deleting the final containing list"
        )
    }

    func testCustomListCanBeCreatedBrowsedAndShownOnMap() {
        let app = launch(reset: true, resetTheme: true, pinDiagnostics: true, seedTrackVisits: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMapToFinishLoading(in: app))
        let openFixture = app.buttons["debug.open-fixture"]
        XCTAssertTrue(openFixture.waitForExistence(timeout: 5))
        openFixture.tap()
        XCTAssertTrue(app.staticTexts["Ghost Sign"].waitForExistence(timeout: 5))

        let saveButton = app.otherElements["place-card.action-bar"].buttons["place-card.save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.press(forDuration: 1.0)
        XCTAssertTrue(app.navigationBars["Add to list"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Want to go"].waitForExistence(timeout: 5))
        app.buttons["list-picker.create"].tap()
        let listPickerError = app.staticTexts["list-picker.error"]
        XCTAssertTrue(listPickerError.waitForExistence(timeout: 5))
        XCTAssertEqual(listPickerError.label, "Enter a list name.")
        let listPickerName = app.textFields["list-picker.new-name"]
        guard acquireKeyboardFocus(listPickerName, in: app) else { return }
        listPickerName.typeText("KL walk")
        app.buttons["list-picker.create"].tap()
        XCTAssertTrue(app.buttons.matching(identifierPrefix: "list-picker.row.").firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(listPickerError.exists)
        app.buttons["list-picker.done"].tap()

        let savedButton = app.otherElements["place-card.action-bar"].buttons["place-card.save"]
        XCTAssertTrue(savedButton.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForButtonLabel("Saved", identifier: "place-card.save", in: app))
        let listChips = element(identifier: "place-card.list-chips", in: app)
        XCTAssertTrue(listChips.waitForExistence(timeout: 5))
        XCTAssertTrue(listChips.label.contains("KL walk"))
        XCTAssertFalse(listChips.label.contains("Want to go"))
        closePlaceCard(in: app)

        openJournalDoor(in: app)
        let tracksRoot = app.collectionViews["journal.root"]
        XCTAssertTrue(tracksRoot.waitForExistence(timeout: 5))
        tracksRoot.swipeUp()
        let createList = app.buttons["lists.create"]
        XCTAssertTrue(createList.isHittable)
        createList.tap()
        let listsError = app.staticTexts["lists.error"]
        XCTAssertTrue(listsError.waitForExistence(timeout: 5))
        XCTAssertEqual(listsError.label, "Enter a list name.")

        let rootListName = "Journal root proof"
        let rootListField = app.textFields["lists.create.name"]
        guard acquireKeyboardFocus(rootListField, in: app) else { return }
        rootListField.typeText(rootListName)
        createList.tap()
        XCTAssertTrue(waitForNonExistence(of: listsError, timeout: 5))
        XCTAssertNotEqual(rootListField.value as? String, rootListName)

        let rootListRow = app.buttons.matching(identifierPrefix: "lists.row.").matching(
            NSPredicate(format: "label CONTAINS %@", rootListName)
        ).firstMatch
        let rootListScrollLimit = 10
        let rootListScroll = scrollToHittableMatch(
            rootListRow,
            in: app,
            maxScrolls: rootListScrollLimit
        )
        XCTAssertTrue(
            rootListScroll.matched,
            "lists.row.* label CONTAINS \(rootListName) was not hittable after "
                + "\(rootListScrollLimit) scrolls; final observation: "
                + "\(rootListScroll.observation.rawValue) — known to amplify under "
                + "concurrent-gate load, see #600 cap-2 rep1"
        )
        guard rootListScroll.matched else { return }
        rootListRow.tap()
        XCTAssertTrue(app.navigationBars[rootListName].waitForExistence(timeout: 5))
        XCTAssertTrue(app.collectionViews["lists.detail.surface.collection"].exists)
        app.buttons["door.destination.close"].tap()

        openJournalDoor(in: app)
        openListFromTracksRoot(named: "KL walk", in: app)

        XCTAssertTrue(app.staticTexts["lists.detail.progress"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["lists.detail.progress"].label, "you've been to 1 of these · all seen")
        XCTAssertTrue(app.buttons["lists.detail.show-map"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Ghost Sign"].waitForExistence(timeout: 5))
        app.buttons["lists.detail.show-map"].tap()

        XCTAssertTrue(app.staticTexts["map.list-mode.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["map.list-mode.title"].label, "KL walk")
        XCTAssertTrue(app.buttons["map.list-mode.back"].exists)
        XCTAssertFalse(app.buttons["map.list-mode.close"].exists)
        XCTAssertTrue(app.buttons["map.door.explore"].exists)
        XCTAssertTrue(app.buttons["map.door.journal"].exists)
        XCTAssertTrue(waitForSourceFeatureCount(1, in: app))
        XCTAssertTrue(waitForTrackSegmentCount(0, in: app))

        let freshLayerButton = app.buttons["map.list-mode.fresh"]
        let tracksLayerButton = app.buttons["map.list-mode.tracks"]
        XCTAssertTrue(freshLayerButton.waitForExistence(timeout: 5))
        XCTAssertTrue(tracksLayerButton.waitForExistence(timeout: 5))
        XCTAssertEqual(freshLayerButton.label, "Unmarked paper")
        XCTAssertEqual(freshLayerButton.value as? String, "Not selected")
        XCTAssertEqual(tracksLayerButton.label, "My tracks")
        XCTAssertEqual(tracksLayerButton.value as? String, "Selected")
        XCTAssertGreaterThan(freshLayerButton.frame.midY, map.frame.midY)
        XCTAssertGreaterThan(tracksLayerButton.frame.midY, map.frame.midY)
        XCTAssertLessThan(freshLayerButton.frame.midX, tracksLayerButton.frame.midX)
        let locateButton = app.buttons["map.locate-me"]
        let attribution = app.staticTexts["map.openstreetmap-attribution"]
        let listModeControl = app.otherElements["map.list-mode.control"]
        XCTAssertTrue(locateButton.waitForExistence(timeout: 5))
        XCTAssertTrue(attribution.waitForExistence(timeout: 5))
        XCTAssertTrue(listModeControl.waitForExistence(timeout: 5))
        assertNoFrameIntersection(locateButton, listModeControl)
        assertNoFrameIntersection(attribution, listModeControl)
        openScope(in: app)
        app.buttons["Close"].tap()
        attachScreenshot(named: "list-map-polished-chrome")
        freshLayerButton.tap()
        XCTAssertTrue(waitForSourceFeatureCount(0, in: app))
        XCTAssertTrue(waitForTrackSegmentCount(0, in: app))
        XCTAssertEqual(freshLayerButton.value as? String, "Selected")

        app.buttons["map.list-mode.back"].tap()
        XCTAssertTrue(app.staticTexts["KL walk"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["lists.detail.show-map"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForNonExistence(of: app.staticTexts["map.list-mode.title"], timeout: 5))
    }

    func testJournalDoorOpensUnifiedMyTracksVisitEditor() {
        let app = launch(reset: true, pinDiagnostics: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMapToFinishLoading(in: app))
        openFixtureCard(in: map, app: app)

        app.buttons["place-card.visited"].tap()
        closePlaceCard(in: app)

        openJournalDoor(in: app)
        XCTAssertTrue(app.buttons["journal.row.my-tracks"].waitForExistence(timeout: 5))
        app.buttons["journal.row.my-tracks"].tap()

        let trackDetail = app.collectionViews["lists.detail.surface.track"]
        XCTAssertTrue(trackDetail.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["My tracks"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["lists.detail.track.sort-direction"].label, "Oldest first")
        XCTAssertEqual(app.staticTexts["lists.detail.track.summary"].label, "1 visit")
        XCTAssertTrue(app.staticTexts["Ghost Sign"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifierPrefix: "lists.detail.track.row.").firstMatch.exists)
        XCTAssertFalse(app.sliders["tracks.timeline.slider"].exists)
        trackDetail.swipeUp()
        XCTAssertEqual(screenshotExportNames["tracks-unified-visit-editing"], "tracks-unified-visit-editing")
        attachScreenshot(named: "tracks-unified-visit-editing")

        let firstRow = app.otherElements.matching(identifierPrefix: "lists.detail.track.row.card.").firstMatch
        XCTAssertTrue(firstRow.exists)
        firstRow.tap()
        XCTAssertTrue(app.staticTexts["lists.detail.visit-date.title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["lists.detail.visit-date.back"].exists)
        XCTAssertTrue(app.buttons["lists.detail.visit-date.delete"].exists)
        XCTAssertTrue(app.datePickers["lists.detail.visit-date.picker"].exists)
        XCTAssertTrue(app.datePickers["lists.detail.visit-date.picker"].isHittable)
        XCTAssertTrue(app.images["lists.detail.visit-date.summary-pin"].exists)
        XCTAssertTrue(app.images["lists.detail.visit-date.selected-pin"].exists)
        XCTAssertTrue(app.images["lists.detail.visit-date.heart"].exists)
        XCTAssertFalse(app.staticTexts["heart"].exists)
        XCTAssertTrue(app.buttons["lists.detail.track.refresh"].exists)
        XCTAssertFalse(app.buttons["lists.detail.track.edit-order"].exists)
        XCTAssertFalse(app.buttons.matching(identifierPrefix: "lists.detail.track.row.move-up.").firstMatch.exists)
        XCTAssertFalse(app.buttons.matching(identifierPrefix: "lists.detail.track.row.move-down.").firstMatch.exists)
    }

    func testMyTracksCompactRowsFitSixVisitsWithoutInlineDateField() {
        let app = launch(
            reset: true,
            seedVisitsEditorVisual: true,
            hideFixtureChrome: true
        )
        XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 10))
        openJournalDoor(in: app)
        app.buttons["journal.row.my-tracks"].tap()

        let trackSurface = app.collectionViews["lists.detail.surface.track"]
        XCTAssertTrue(trackSurface.waitForExistence(timeout: 5))
        XCTAssertEqual(
            app.descendants(matching: .any)
                .matching(identifierPrefix: "lists.detail.track.row.date.").count,
            0,
            "Compact rows must not expose inline date controls"
        )

        let visibleRows = app.otherElements
            .matching(identifierPrefix: "lists.detail.track.row.card.")
            .allElementsBoundByIndex
            .filter { row in
                row.exists
                    && row.frame.minY >= trackSurface.frame.minY
                    && row.frame.maxY <= trackSurface.frame.maxY
            }
        XCTAssertGreaterThanOrEqual(
            visibleRows.count,
            6,
            "At least six compact visit rows must fit in the 390x844-class viewport; surface=\(trackSurface.frame), rows=\(visibleRows.map(\.frame))"
        )
    }

    func testMyTracksReorderHandleDragMovesTheSelectedVisit() {
        let app = launch(
            reset: true,
            seedVisitsEditorVisual: true,
            hideFixtureChrome: true
        )
        XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 10))
        openJournalDoor(in: app)
        app.buttons["journal.row.my-tracks"].tap()

        let trackSurface = app.collectionViews["lists.detail.surface.track"]
        XCTAssertTrue(trackSurface.waitForExistence(timeout: 5))
        let sourceCard = app.otherElements["lists.detail.track.row.card.1"]
        let displacedCard = app.otherElements["lists.detail.track.row.card.2"]
        let targetCard = app.otherElements["lists.detail.track.row.card.3"]
        let sourceHandle = element(identifier: "lists.detail.track.row.reorder.1", in: app)
        let targetHandle = element(identifier: "lists.detail.track.row.reorder.3", in: app)
        XCTAssertTrue(sourceCard.exists)
        XCTAssertTrue(displacedCard.exists)
        XCTAssertTrue(targetCard.exists)
        XCTAssertTrue(sourceHandle.exists)
        XCTAssertTrue(targetHandle.exists)
        XCTAssertLessThan(sourceCard.frame.minY, displacedCard.frame.minY)

        sourceHandle.press(forDuration: 0.5, thenDragTo: targetHandle)

        let reordered = NSPredicate { _, _ in
            sourceCard.exists
                && displacedCard.exists
                && sourceCard.frame.minY > displacedCard.frame.minY
        }
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(predicate: reordered, object: sourceCard)],
                timeout: 5
            ),
            .completed,
            "Dragging visit 1 to visit 3 must move the selected visit through the real SwiftUI gesture path"
        )
    }

    func testMyTracksReorderHandleDragSurvivesEdgeAutoScroll() {
        let app = launch(
            reset: true,
            seedVisitsEditorVisual: true,
            hideFixtureChrome: true
        )
        XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 10))
        openJournalDoor(in: app)
        app.buttons["journal.row.my-tracks"].tap()

        let trackSurface = app.collectionViews["lists.detail.surface.track"]
        XCTAssertTrue(trackSurface.waitForExistence(timeout: 5))
        let sourceCard = app.otherElements["lists.detail.track.row.card.1"]
        let initiallyOffscreenCard = app.otherElements["lists.detail.track.row.card.8"]
        let sourceHandle = element(identifier: "lists.detail.track.row.reorder.1", in: app)
        XCTAssertTrue(sourceCard.exists)
        XCTAssertTrue(sourceHandle.exists)
        XCTAssertFalse(
            initiallyOffscreenCard.exists
                && initiallyOffscreenCard.frame.intersects(trackSurface.frame),
            "Visit 8 must begin outside the rendered viewport so it can witness auto-scroll"
        )

        let dragStart = sourceHandle.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        )
        let lowerEdge = trackSurface.coordinate(
            withNormalizedOffset: CGVector(dx: 0.9, dy: 0.96)
        )
        dragStart.press(
            forDuration: 0.5,
            thenDragTo: lowerEdge,
            withVelocity: .slow,
            thenHoldForDuration: 3
        )

        let autoScrolled = NSPredicate { _, _ in
            initiallyOffscreenCard.exists
                && initiallyOffscreenCard.frame.intersects(trackSurface.frame)
        }
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [
                    XCTNSPredicateExpectation(
                        predicate: autoScrolled,
                        object: initiallyOffscreenCard
                    ),
                ],
                timeout: 5
            ),
            .completed,
            "Holding at the lower edge must scroll visit 8 into the rendered viewport"
        )

        trackSurface.swipeUp()
        let persistedBeyondWitness = NSPredicate { _, _ in
            initiallyOffscreenCard.exists
                && sourceCard.exists
                && initiallyOffscreenCard.frame.minY < sourceCard.frame.minY
        }
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [
                    XCTNSPredicateExpectation(
                        predicate: persistedBeyondWitness,
                        object: sourceCard
                    ),
                ],
                timeout: 5
            ),
            .completed,
            "The persisted order must place visit 1 beyond the initially offscreen visit 8"
        )
    }

    func testMyTracksTrailingGutterStillScrollsOutsideReorderHandles() {
        let app = launch(
            reset: true,
            seedVisitsEditorVisual: true,
            hideFixtureChrome: true
        )
        XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 10))
        openJournalDoor(in: app)
        app.buttons["journal.row.my-tracks"].tap()

        let trackSurface = app.collectionViews["lists.detail.surface.track"]
        XCTAssertTrue(trackSurface.waitForExistence(timeout: 5))
        let firstCard = app.otherElements["lists.detail.track.row.card.1"]
        let initiallyOffscreenCard = app.otherElements["lists.detail.track.row.card.8"]
        XCTAssertTrue(firstCard.exists)
        XCTAssertFalse(
            initiallyOffscreenCard.exists
                && initiallyOffscreenCard.frame.intersects(trackSurface.frame)
        )

        let gutterStartY = max(
            0.2,
            min(
                0.8,
                (firstCard.frame.minY - trackSurface.frame.minY - 3)
                    / trackSurface.frame.height
            )
        )
        let gutterStart = trackSurface.coordinate(
            withNormalizedOffset: CGVector(dx: 0.98, dy: gutterStartY)
        )
        let gutterEnd = trackSurface.coordinate(
            withNormalizedOffset: CGVector(dx: 0.98, dy: 0.12)
        )
        gutterStart.press(
            forDuration: 0.05,
            thenDragTo: gutterEnd,
            withVelocity: .fast,
            thenHoldForDuration: 0
        )

        let scrolled = NSPredicate { _, _ in
            initiallyOffscreenCard.exists
                && initiallyOffscreenCard.frame.intersects(trackSurface.frame)
        }
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [
                    XCTNSPredicateExpectation(
                        predicate: scrolled,
                        object: initiallyOffscreenCard
                    ),
                ],
                timeout: 5
            ),
            .completed,
            "A vertical swipe in the trailing List gutter must scroll rather than start a reorder"
        )
    }

    func testMyTracksRenderedPixelOraclesAcrossLightAndDarkAppearances() {
        guard let light = assertMyTracksRenderedPixelOracle(
            forceDarkAppearance: false,
            appearanceName: "light"
        ), let dark = assertMyTracksRenderedPixelOracle(
            forceDarkAppearance: true,
            appearanceName: "dark"
        ) else {
            return
        }

        XCTAssertEqual(light.trackSurfaceFrame, dark.trackSurfaceFrame)
        let comparisonFrame = MyTracksRenderedComparisonFrame.appOwnedIntersection(
            light: light.trackSurfaceFrame,
            dark: dark.trackSurfaceFrame
        )
        guard let differenceCount = light.raster.differingPixelCount(
            comparedTo: dark.raster,
            in: comparisonFrame
        ) else {
            XCTFail("Could not compare Light and Dark My tracks editor rasters")
            return
        }
        XCTAssertEqual(
            differenceCount,
            0,
            "My tracks editor must render identically in forced Light and Dark appearances"
        )

        XCTAssertEqual(light.visitDateSurfaceFrame, dark.visitDateSurfaceFrame)
        let visitDateComparisonFrame = light.visitDateSurfaceFrame
            .intersection(dark.visitDateSurfaceFrame)
            // The system-owned sheet corners expose the appearance-dependent
            // map underneath. Compare the opaque editor interior, including
            // its navigation content, rather than those translucent corners.
            .insetBy(dx: 20, dy: 1)
        guard let visitDateDifferenceCount = light.visitDateRaster.differingPixelCount(
            comparedTo: dark.visitDateRaster,
            in: visitDateComparisonFrame
        ) else {
            XCTFail("Could not compare Light and Dark Visit date rasters")
            return
        }
        XCTAssertEqual(
            visitDateDifferenceCount,
            0,
            "Visit date editor must render identically in forced Light and Dark appearances"
        )
    }

    func testFilteredMyTracksHidesInvariantReorderHandleToken() {
        XCUIDevice.shared.appearance = .light
        defer { XCUIDevice.shared.appearance = .light }

        let app = launch(
            reset: true,
            seedVisitsEditorVisual: true,
            hideFixtureChrome: true
        )
        XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 10))
        openJournalDoor(in: app)
        app.buttons["journal.row.my-tracks"].tap()

        let trackSurface = app.collectionViews["lists.detail.surface.track"]
        XCTAssertTrue(trackSurface.waitForExistence(timeout: 5))
        app.buttons["lists.detail.show-map"].tap()
        XCTAssertTrue(app.staticTexts["map.list-mode.title"].waitForExistence(timeout: 5))

        openScope(in: app)
        let toggleAll = app.buttons["explore.scope.categories.toggle-all"]
        XCTAssertTrue(scrollToHittable(toggleAll, in: app))
        toggleAll.tap()
        let category = app.buttons["explore.scope.category.historic_building"]
        XCTAssertTrue(scrollToHittable(category, in: app))
        category.tap()
        app.buttons["Close"].tap()

        app.buttons["map.list-mode.back"].tap()
        XCTAssertTrue(trackSurface.waitForExistence(timeout: 5))
        // The amended dense fixture contains two historic-building visits; the filter
        // must still suppress reorder affordances on the filtered surface.
        XCTAssertEqual(app.staticTexts["lists.detail.track.summary"].label, "2 visits")

        let screenshot = XCUIScreen.main.screenshot()
        let appFrame = app.windows.firstMatch.exists ? app.windows.firstMatch.frame : app.frame
        guard let raster = RenderedPixelRaster(screenshot: screenshot, appFrame: appFrame) else {
            XCTFail("Could not decode filtered My tracks screenshot")
            return
        }
        XCTAssertEqual(
            app.descendants(matching: .any)
                .matching(identifierPrefix: "lists.detail.track.row.reorder.").count,
            0,
            "Filtered My tracks must not expose app-drawn reorder handles"
        )
        let renderedRows = app.otherElements
            .matching(identifierPrefix: "lists.detail.track.row.card.")
            .allElementsBoundByIndex
            .filter(\.exists)
        let reorderTokenCount = renderedRows.reduce(into: 0) { count, row in
            let reorderStrip = CGRect(
                x: row.frame.maxX - 60,
                y: row.frame.minY,
                width: 60,
                height: row.frame.height
            )
            count += raster.tokenCount(RenderedRGB(170, 168, 157), in: reorderStrip)
        }
        XCTAssertEqual(
            reorderTokenCount,
            0,
            "Filtered My tracks must not render the reorder-handle token in any row's trailing bounds"
        )
    }

    func testMyTracksControlsRemainAccessibleAtAccessibilityTextSize() {
        XCUIDevice.shared.appearance = .light
        defer { XCUIDevice.shared.appearance = .light }

        let app = launch(
            reset: true,
            accessibilityTextSize: true,
            seedVisitsEditorVisual: true,
            hideFixtureChrome: true
        )
        XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 10))
        openJournalDoor(in: app)
        app.buttons["journal.row.my-tracks"].tap()
        XCTAssertTrue(app.collectionViews["lists.detail.surface.track"].waitForExistence(timeout: 5))

        let back = app.buttons["lists.detail.track.back"]
        let title = app.staticTexts["lists.detail.track.title"]
        let done = app.buttons["lists.detail.track.done"]
        for (element, name) in [(back, "Back"), (done, "Done")] {
            XCTAssertTrue(element.exists, "\(name) must exist")
            XCTAssertGreaterThanOrEqual(element.frame.width, 44, "\(name) touch width")
            XCTAssertGreaterThanOrEqual(element.frame.height, 44, "\(name) touch height")
        }
        XCTAssertTrue(title.exists)
        XCTAssertFalse(back.frame.intersects(title.frame), "Back must not collide with the title")
        XCTAssertFalse(done.frame.intersects(title.frame), "Done must not collide with the title")

        let heart = app.buttons.matching(identifierPrefix: "lists.detail.track.row.loved.").firstMatch
        XCTAssertTrue(scrollToExistence(of: heart, in: app))
        XCTAssertGreaterThanOrEqual(heart.frame.width, 44, "heart touch width")
        XCTAssertGreaterThanOrEqual(heart.frame.height, 44, "heart touch height")
        let firstRow = app.otherElements.matching(identifierPrefix: "lists.detail.track.row.card.").firstMatch
        let renderedRowCount = app.descendants(matching: .any)
            .matching(identifierPrefix: "lists.detail.track.row.card.").count
        let renderedHandleCount = app.descendants(matching: .any)
            .matching(identifierPrefix: "lists.detail.track.row.reorder.").count
        XCTAssertEqual(
            renderedHandleCount,
            renderedRowCount,
            "Every rendered visit row must expose exactly one app-drawn reorder handle"
        )
        XCTAssertTrue(firstRow.exists)
        firstRow.tap()
        XCTAssertTrue(app.buttons["lists.detail.visit-date.delete"].waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(app.buttons["lists.detail.visit-date.delete"].frame.width, 44)
        XCTAssertGreaterThanOrEqual(app.buttons["lists.detail.visit-date.delete"].frame.height, 44)
        let visitBack = app.buttons["lists.detail.visit-date.back"]
        let visitTitle = app.staticTexts["lists.detail.visit-date.title"]
        XCTAssertTrue(visitBack.exists)
        XCTAssertTrue(visitTitle.exists)
        XCTAssertFalse(
            visitBack.frame.intersects(visitTitle.frame),
            "Visit date Back control must not collide with the title at accessibility text sizes"
        )
    }

    func testMyTracksHeroClearsFocusedManageVisitsRoute() {
        let app = launch(
            reset: true,
            pinDiagnostics: true,
            seedFocusedTracksRoute: true
        )
        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMapToFinishLoading(in: app))
        openFixtureCard(in: map, app: app)

        let unsee = app.buttons["place-card.unsee"]
        XCTAssertTrue(unsee.waitForExistence(timeout: 5))
        unsee.tap()

        let summary = app.staticTexts["lists.detail.track.summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertEqual(summary.label, "Choose the visit")
        app.buttons["lists.detail.track.back"].tap()

        let hero = app.buttons["journal.row.my-tracks"]
        XCTAssertTrue(hero.waitForExistence(timeout: 5))
        hero.tap()
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertEqual(
            summary.label,
            "3 visits",
            "The root hero must open the whole history after a focused Manage Visits route"
        )
        XCTAssertFalse(app.staticTexts["lists.detail.track.focus-message"].exists)
    }

    func testJournalDoorIsTheSingleListsSurface() {
        let app = launch(reset: true, seedUserList: true, pinDiagnostics: true)
        XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMapToFinishLoading(in: app))
        openJournalDoor(in: app)

        let myTracks = app.buttons["journal.row.my-tracks"]
        let dateNight = app.buttons.matching(identifierPrefix: "lists.row.").matching(
            NSPredicate(format: "label CONTAINS %@", "Date night")
        ).firstMatch
        XCTAssertTrue(myTracks.waitForExistence(timeout: 5))
        XCTAssertTrue(dateNight.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(myTracks.frame.height, 44)
        XCTAssertLessThanOrEqual(
            myTracks.frame.height,
            100,
            "Default-size My tracks hero must keep the ruled compact raised-row geometry"
        )
        XCTAssertTrue(app.staticTexts["Retrace"].exists)
        XCTAssertTrue(app.textFields["lists.create.name"].exists)
        XCTAssertTrue(app.buttons["lists.create"].exists)
        XCTAssertFalse(app.buttons["journal.row.lists"].exists)
        XCTAssertFalse(app.navigationBars["Lists"].exists)
        XCTAssertEqual(screenshotExportNames["journal-door-default"], "journal-door-default")
        attachScreenshot(named: "journal-door-default")

        myTracks.tap()
        XCTAssertTrue(app.collectionViews["lists.detail.surface.track"].waitForExistence(timeout: 5))
        app.buttons["lists.detail.track.back"].tap()

        XCTAssertTrue(dateNight.waitForExistence(timeout: 5))
        dateNight.tap()
        XCTAssertTrue(app.collectionViews["lists.detail.surface.collection"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["lists.detail.show-map"].exists)
    }

    func testLovedAndHiddenSurfacesManagePlaceMembership() {
        let app = launch(reset: true, seedManagedPlaces: true)
        XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 10))
        openJournalDoor(in: app)

        let myTracks = app.buttons["journal.row.my-tracks"]
        let dateNight = app.buttons.matching(identifierPrefix: "lists.row.").matching(
            NSPredicate(format: "label CONTAINS %@", "Date night")
        ).firstMatch
        let newList = app.buttons["lists.create"]
        let loved = app.buttons["journal.row.loved"]
        let hidden = app.buttons["journal.row.hidden"]
        XCTAssertTrue(myTracks.waitForExistence(timeout: 5))
        XCTAssertTrue(dateNight.waitForExistence(timeout: 5))
        XCTAssertEqual(
            dateNight.value as? String,
            "1 of 1 seen",
            "Only the visible saved primary fixture belongs to Date night."
        )
        XCTAssertTrue(scrollToHittable(newList, in: app))
        XCTAssertTrue(scrollToHittable(loved, in: app))
        XCTAssertTrue(scrollToHittable(hidden, in: app))
        XCTAssertEqual(loved.value as? String, "2 places")
        XCTAssertEqual(hidden.value as? String, "2 places")
        assertMinimumInteractiveTarget(loved)
        assertMinimumInteractiveTarget(hidden)
        attachScreenshot(named: "loved-hidden-door")

        loved.tap()
        XCTAssertTrue(app.collectionViews["tracks.loved.surface"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Loved places"].exists)
        let ghostRow = element(
            identifier: "tracks.loved.row.mt1_00000000000000000000000000",
            in: app
        )
        let overlapRow = element(
            identifier: "tracks.loved.row.mt1_00000000000000000000000001",
            in: app
        )
        XCTAssertTrue(overlapRow.waitForExistence(timeout: 5))
        XCTAssertTrue(overlapRow.label.contains("Historic Building · Hidden"))
        let removeGhost = app.buttons[
            "tracks.loved.remove.mt1_00000000000000000000000000"
        ]
        XCTAssertTrue(scrollToHittable(removeGhost, in: app))
        assertMinimumInteractiveTarget(removeGhost)
        removeGhost.tap()
        XCTAssertTrue(waitForNonExistence(of: ghostRow, timeout: 5))
        XCTAssertTrue(scrollToHittable(overlapRow, in: app))
        attachScreenshot(named: "loved-places")

        app.buttons["Back"].tap()
        XCTAssertTrue(scrollToHittable(loved, in: app))
        XCTAssertEqual(loved.value as? String, "1 place")
        XCTAssertTrue(scrollToHittable(hidden, in: app))
        hidden.tap()
        XCTAssertTrue(app.collectionViews["tracks.hidden.surface"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Hidden places"].exists)
        let hiddenOverlapRow = element(
            identifier: "tracks.hidden.row.mt1_00000000000000000000000001",
            in: app
        )
        let hiddenOnlyRow = element(
            identifier: "tracks.hidden.row.mt1_S0000000000000000000000001",
            in: app
        )
        XCTAssertTrue(hiddenOverlapRow.waitForExistence(timeout: 5))
        XCTAssertTrue(hiddenOnlyRow.waitForExistence(timeout: 5))
        let unhideOverlap = app.buttons[
            "tracks.hidden.unhide.mt1_00000000000000000000000001"
        ]
        let saveOverlap = app.buttons[
            "tracks.hidden.save.mt1_00000000000000000000000001"
        ]
        let unhideHiddenOnly = app.buttons[
            "tracks.hidden.unhide.mt1_S0000000000000000000000001"
        ]
        let saveHiddenOnly = app.buttons[
            "tracks.hidden.save.mt1_S0000000000000000000000001"
        ]
        XCTAssertTrue(scrollToFullyContained(saveOverlap, in: app))
        assertContainedInAppFrame(hiddenOverlapRow, in: app)
        assertMinimumInteractiveTarget(unhideOverlap)
        assertContainedInAppFrame(unhideOverlap, in: app)
        assertMinimumInteractiveTarget(saveOverlap)
        assertContainedInAppFrame(saveOverlap, in: app)
        assertHorizontallyOrdered(hiddenOverlapRow, unhideOverlap)
        assertHorizontallyOrdered(unhideOverlap, saveOverlap)
        XCTAssertTrue(scrollToFullyContained(saveHiddenOnly, in: app))
        assertContainedInAppFrame(hiddenOnlyRow, in: app)
        assertMinimumInteractiveTarget(unhideHiddenOnly)
        assertContainedInAppFrame(unhideHiddenOnly, in: app)
        assertMinimumInteractiveTarget(saveHiddenOnly)
        assertContainedInAppFrame(saveHiddenOnly, in: app)
        assertHorizontallyOrdered(hiddenOnlyRow, unhideHiddenOnly)
        assertHorizontallyOrdered(unhideHiddenOnly, saveHiddenOnly)
        attachScreenshot(named: "a6-hidden-actions")
        XCTAssertTrue(scrollToHittable(unhideOverlap, in: app))
        unhideOverlap.tap()
        XCTAssertTrue(waitForNonExistence(of: hiddenOverlapRow, timeout: 5))
        XCTAssertTrue(scrollToHittable(hiddenOnlyRow, in: app))
        attachScreenshot(named: "hidden-places")

        app.buttons["Back"].tap()
        XCTAssertTrue(scrollToHittable(hidden, in: app))
        XCTAssertEqual(hidden.value as? String, "1 place")
        XCTAssertTrue(scrollToHittable(dateNight, in: app))
        XCTAssertEqual(
            dateNight.value as? String,
            "1 of 1 seen",
            "Unhiding an unsaved place must not change Date night progress."
        )
    }

    func testHiddenSurfaceSaveAutoUnhidesAndKeepsPickerOpen() {
        let app = launch(reset: true, seedManagedPlaces: true)
        XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 10))
        openJournalDoor(in: app)
        let hidden = app.buttons["journal.row.hidden"]
        XCTAssertTrue(scrollToHittable(hidden, in: app))
        hidden.tap()

        let placeID = "mt1_S0000000000000000000000001"
        let row = element(identifier: "tracks.hidden.row.\(placeID)", in: app)
        let save = app.buttons["tracks.hidden.save.\(placeID)"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(scrollToHittable(save, in: app))
        assertMinimumInteractiveTarget(save)
        save.tap()

        XCTAssertTrue(app.navigationBars["Add to list"].waitForExistence(timeout: 5))
        let wantToGo = app.buttons["list-picker.row.1"]
        XCTAssertTrue(wantToGo.waitForExistence(timeout: 5))
        let selectedWantToGo = app.buttons.matching(NSPredicate(
            format: "identifier == %@ AND label CONTAINS %@",
            "list-picker.row.1",
            "In list"
        )).firstMatch
        wantToGo.tap()
        XCTAssertTrue(selectedWantToGo.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Add to list"].exists)
        wantToGo.tap()
        XCTAssertTrue(waitForNonExistence(of: selectedWantToGo, timeout: 5))
        XCTAssertTrue(app.navigationBars["Add to list"].exists)
        app.buttons["list-picker.done"].tap()
        XCTAssertFalse(app.navigationBars["Add to list"].waitForExistence(timeout: 2))
        XCTAssertTrue(waitForNonExistence(of: row, timeout: 5))
    }

    func testHiddenSurfaceRoundTripsWithScopeWithoutChangingTrackCounts() {
        let app = launch(
            reset: true,
            pinDiagnostics: true,
            seedManagedPlaces: true
        )
        XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMapToFinishLoading(in: app))
        XCTAssertTrue(waitForSourceFeatureCount(1, in: app))

        openJournalDoor(in: app)
        let myTracks = app.buttons["journal.row.my-tracks"]
        XCTAssertTrue(myTracks.waitForExistence(timeout: 5))
        XCTAssertTrue(myTracks.label.contains("2 visits"))
        let loved = app.buttons["journal.row.loved"]
        XCTAssertTrue(scrollToHittable(loved, in: app))
        loved.tap()
        XCTAssertTrue(app.buttons["door.destination.close"].waitForExistence(timeout: 5))
        app.buttons["door.destination.close"].tap()

        openScope(in: app)
        let showHidden = "explore.scope.include-hidden"
        XCTAssertTrue(app.switches[showHidden].waitForExistence(timeout: 5))
        XCTAssertEqual(
            app.switches[showHidden].value as? String,
            "0",
            "The unhide proof must begin with Include hidden off."
        )
        app.buttons["Close"].tap()
        XCTAssertTrue(waitForSourceFeatureCount(1, in: app))

        openJournalDoor(in: app)
        XCTAssertTrue(myTracks.waitForExistence(timeout: 5))
        XCTAssertTrue(
            myTracks.label.contains("2 visits"),
            "Hidden places must not contribute to Tracks progress"
        )
        let hidden = app.buttons["journal.row.hidden"]
        XCTAssertTrue(scrollToHittable(hidden, in: app))
        hidden.tap()
        let unhideOverlap = app.buttons[
            "tracks.hidden.unhide.mt1_00000000000000000000000001"
        ]
        XCTAssertTrue(scrollToHittable(unhideOverlap, in: app))
        unhideOverlap.tap()
        XCTAssertTrue(waitForNonExistence(
            of: element(
                identifier: "tracks.hidden.row.mt1_00000000000000000000000001",
                in: app
            ),
            timeout: 5
        ))
        XCTAssertTrue(app.buttons["door.destination.close"].waitForExistence(timeout: 5))
        app.buttons["door.destination.close"].tap()
        XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            waitForSourceFeatureCount(2, in: app),
            "Controller-routed unhide must restore discovery while Include hidden is off."
        )

        openJournalDoor(in: app)
        XCTAssertTrue(myTracks.waitForExistence(timeout: 5))
        XCTAssertTrue(
            myTracks.label.contains("3 visits"),
            "Live unhide must restore the visit to ordinary Tracks progress"
        )
        XCTAssertTrue(scrollToHittable(hidden, in: app))
        XCTAssertEqual(hidden.value as? String, "1 place")
    }

    func testLovedAndHiddenSurfacesRemainUsableAtAX5() {
        let app = launch(
            reset: true,
            accessibilityTextSize: true,
            seedManagedPlaces: true
        )
        XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 10))
        openJournalDoor(in: app)

        let loved = app.buttons["journal.row.loved"]
        let hidden = app.buttons["journal.row.hidden"]
        XCTAssertTrue(scrollToHittable(loved, in: app))
        XCTAssertTrue(scrollToHittable(hidden, in: app))
        assertMinimumInteractiveTarget(loved)
        assertMinimumInteractiveTarget(hidden)
        assertNoFrameIntersection(loved, hidden)

        loved.tap()
        XCTAssertTrue(app.collectionViews["tracks.loved.surface"].waitForExistence(timeout: 5))
        let removeGhost = app.buttons[
            "tracks.loved.remove.mt1_00000000000000000000000000"
        ]
        let removeOverlap = app.buttons[
            "tracks.loved.remove.mt1_00000000000000000000000001"
        ]
        XCTAssertTrue(scrollToHittable(removeGhost, in: app))
        assertMinimumInteractiveTarget(removeGhost)
        assertContainedInAppFrame(removeGhost, in: app)
        XCTAssertTrue(scrollToHittable(removeOverlap, in: app))
        assertMinimumInteractiveTarget(removeOverlap)
        assertContainedInAppFrame(removeOverlap, in: app)
        attachScreenshot(named: "loved-hidden-ax")

        app.buttons["Back"].tap()
        XCTAssertTrue(scrollToHittable(hidden, in: app))
        hidden.tap()
        let unhideOverlap = app.buttons[
            "tracks.hidden.unhide.mt1_00000000000000000000000001"
        ]
        let saveOverlap = app.buttons[
            "tracks.hidden.save.mt1_00000000000000000000000001"
        ]
        let unhideHiddenOnly = app.buttons[
            "tracks.hidden.unhide.mt1_S0000000000000000000000001"
        ]
        let saveHiddenOnly = app.buttons[
            "tracks.hidden.save.mt1_S0000000000000000000000001"
        ]
        let hiddenOverlapRow = element(
            identifier: "tracks.hidden.row.mt1_00000000000000000000000001",
            in: app
        )
        let hiddenOnlyRow = element(
            identifier: "tracks.hidden.row.mt1_S0000000000000000000000001",
            in: app
        )
        XCTAssertTrue(hiddenOverlapRow.waitForExistence(timeout: 5))
        XCTAssertTrue(hiddenOnlyRow.waitForExistence(timeout: 5))
        XCTAssertTrue(scrollToFullyContained(saveOverlap, in: app))
        assertMinimumInteractiveTarget(unhideOverlap)
        assertContainedInAppFrame(unhideOverlap, in: app)
        assertContainedInAppFrame(hiddenOverlapRow, in: app)
        assertMinimumInteractiveTarget(saveOverlap)
        assertContainedInAppFrame(saveOverlap, in: app)
        assertNoFrameIntersection(unhideOverlap, saveOverlap)
        assertVerticallyOrdered(hiddenOverlapRow, unhideOverlap)
        assertVerticallyOrdered(unhideOverlap, saveOverlap)
        XCTAssertEqual(
            unhideOverlap.frame.minX,
            saveOverlap.frame.minX,
            accuracy: 1,
            "AX Hidden actions must share the leading edge."
        )
        XCTAssertTrue(scrollToFullyContained(saveHiddenOnly, in: app))
        assertMinimumInteractiveTarget(unhideHiddenOnly)
        assertContainedInAppFrame(unhideHiddenOnly, in: app)
        assertContainedInAppFrame(hiddenOnlyRow, in: app)
        assertMinimumInteractiveTarget(saveHiddenOnly)
        assertContainedInAppFrame(saveHiddenOnly, in: app)
        assertNoFrameIntersection(unhideHiddenOnly, saveHiddenOnly)
        assertVerticallyOrdered(hiddenOnlyRow, unhideHiddenOnly)
        assertVerticallyOrdered(unhideHiddenOnly, saveHiddenOnly)
        XCTAssertEqual(
            unhideHiddenOnly.frame.minX,
            saveHiddenOnly.frame.minX,
            accuracy: 1,
            "AX Hidden actions must share the leading edge."
        )
        attachScreenshot(named: "a6-hidden-actions-ax")
    }

    func testTrackGeometryDrawsConnectorFromSeededFixtureVisits() {
        let app = launch(reset: true, pinDiagnostics: true, seedTrackList: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMapToFinishLoading(in: app))
        XCTAssertTrue(waitForTrackSegmentCount(0, in: app))

        openJournalDoor(in: app)
        openListFromTracksRoot(named: "Track pair", in: app)
        XCTAssertTrue(app.buttons["lists.detail.show-map"].waitForExistence(timeout: 5))
        app.buttons["lists.detail.show-map"].tap()
        XCTAssertTrue(app.staticTexts["map.list-mode.title"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForSourceFeatureCount(2, in: app))
        XCTAssertTrue(waitForTrackSegmentCount(1, in: app))
        attachScreenshot(named: "tracks-static-geometry")
    }

    func testOpeningJournalDoorDismissesOpenPlaceCardBeforeReplayEntry() {
        let app = launch(reset: true, pinDiagnostics: true, seedMultiDayTrackList: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMapToFinishLoading(in: app))

        openFixtureCard(in: map, app: app)
        let card = app.scrollViews.matching(identifierPrefix: "place-card.instance.").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))

        openJournalDoor(in: app)
        XCTAssertTrue(waitForNonExistence(of: card, timeout: 5), card.debugDescription)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifierPrefix: "place-card.").firstMatch.exists)

        openListFromTracksRoot(named: "Replay week", in: app)
        XCTAssertTrue(app.buttons["lists.detail.show-map"].waitForExistence(timeout: 5))
        app.buttons["lists.detail.show-map"].tap()
        XCTAssertTrue(app.staticTexts["map.list-mode.title"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any).matching(identifierPrefix: "place-card.").firstMatch.exists)
    }

    func testTrackReplaySliderAndAutoplayDriveMapPins() {
        let app = launch(
            reset: true,
            pinDiagnostics: true,
            seedMultiDayTrackList: true,
            densePins: true,
            startupViewport: "kl-street",
            trackReplayBeatDuration: 5
        )

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMapToFinishLoading(in: app))

        openJournalDoor(in: app)
        openListFromTracksRoot(named: "Replay week", in: app)
        XCTAssertTrue(app.buttons["lists.detail.show-map"].waitForExistence(timeout: 5))
        app.buttons["lists.detail.show-map"].tap()

        XCTAssertTrue(app.staticTexts["map.list-mode.title"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForSourceFeatureCount(6, in: app))
        XCTAssertTrue(waitForTrackSegmentCount(5, in: app))
        XCTAssertTrue(waitForAccessibilityPin(
            in: app,
            placeID: "mt1_D0000000000000000000000001",
            label: "Dense Pin 1, Attraction, visited, saved"
        ))
        XCTAssertTrue(waitForAccessibilityPin(
            in: app,
            placeID: "mt1_D0000000000000000000000002",
            label: "Dense Pin 2, Historic Building, visited, saved"
        ))

        let slider = app.sliders["map.track-replay.slider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(slider.frame.midY, map.frame.midY)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifierPrefix: "place-card.").firstMatch.exists)
        XCTAssertTrue(app.staticTexts["map.track-replay.selected-time"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["map.track-replay.start-time"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["map.track-replay.end-time"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["map.track-replay.counter"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["map.list-mode.control"].exists)
        slider.adjust(toNormalizedSliderPosition: 0.0)
        XCTAssertTrue(waitForTrackReplayCounter("Visit 1 of 6", in: app))
        XCTAssertTrue(waitForTrackSegmentCount(0, in: app))
        XCTAssertTrue(waitForAccessibilityPin(
            in: app,
            placeID: "mt1_D0000000000000000000000001",
            label: "Dense Pin 1, Attraction, visited, saved"
        ))
        XCTAssertTrue(waitForAccessibilityPin(
            in: app,
            placeID: "mt1_D0000000000000000000000002",
            label: "Dense Pin 2, Historic Building, not visited, saved"
        ))

        let play = app.buttons["map.track-replay.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        attachScreenshot(named: "track-replay-scrub-frame-00")
        play.tap()
        XCTAssertTrue(waitForTrackReplayCounter("Visit 2 of 6", in: app))
        XCTAssertTrue(waitForTrackSegmentCount(1, in: app))
        XCTAssertTrue(waitForAccessibilityPin(
            in: app,
            placeID: "mt1_D0000000000000000000000002",
            label: "Dense Pin 2, Historic Building, visited, saved"
        ))
        XCTAssertTrue(waitForButtonLabel(
            "Pause track replay",
            identifier: "map.track-replay.play",
            in: app
        ))
        play.tap()
        XCTAssertTrue(waitForButtonLabel(
            "Play track replay",
            identifier: "map.track-replay.play",
            in: app
        ))

        for eventIndex in 1...5 {
            slider.adjust(toNormalizedSliderPosition: Double(eventIndex) / 5.0)
            XCTAssertTrue(waitForTrackReplayCounter("Visit \(eventIndex + 1) of 6", in: app))
            XCTAssertTrue(waitForTrackSegmentCount(eventIndex, in: app))
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            attachScreenshot(named: "track-replay-scrub-frame-0\(eventIndex)")
        }
        attachScreenshot(named: "track-replay-pin-arrival")
    }

    func testTrackReplayProductionMapRecording() {
        let app = launch(
            reset: true,
            seedMultiDayTrackList: true,
            densePins: true,
            startupViewport: "kl-street",
            trackReplayBeatDuration: 1.1,
            replayVisualSeed: true,
            hideFixtureChrome: true
        )

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMapSurfaceToSettle(in: app))

        openJournalDoor(in: app)
        openListFromTracksRoot(named: "Replay week", in: app)
        XCTAssertTrue(app.buttons["lists.detail.show-map"].waitForExistence(timeout: 5))
        app.buttons["lists.detail.show-map"].tap()

        XCTAssertTrue(app.staticTexts["map.list-mode.title"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForMapSurfaceToSettle(in: app))
        XCTAssertFalse(app.descendants(matching: .any).matching(identifierPrefix: "place-card.").firstMatch.exists)

        let slider = app.sliders["map.track-replay.slider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(slider.frame.midY, map.frame.midY)
        XCTAssertTrue(app.staticTexts["map.track-replay.selected-time"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["map.track-replay.start-time"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["map.track-replay.end-time"].waitForExistence(timeout: 5))
        XCTAssertNotEqual(
            app.staticTexts["map.track-replay.start-time"].label,
            app.staticTexts["map.track-replay.end-time"].label
        )
        XCTAssertTrue(app.staticTexts["map.track-replay.counter"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["map.debug-readiness"].exists)
        XCTAssertFalse(app.staticTexts["map.debug-track-source-status"].exists)
        XCTAssertFalse(app.staticTexts["map.startup-region"].exists)

        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        attachScreenshot(named: "track-replay-production-entry")

        slider.adjust(toNormalizedSliderPosition: 0.0)
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        attachScreenshot(named: "track-replay-production-start")

        let play = app.buttons["map.track-replay.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        play.tap()
        XCTAssertTrue(waitForTrackReplayCounter("Visit 6 of 6", in: app, timeout: 9))
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        attachScreenshot(named: "track-replay-production-arrival")
    }

    func testLovedTrackChipDrivesMapSource() {
        let app = launch(
            reset: true,
            pinDiagnostics: true,
            seedMultiDayTrackList: true,
            densePins: true,
            startupViewport: "kl-street"
        )

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMapToFinishLoading(in: app))

        openJournalDoor(in: app)
        openListFromTracksRoot(named: "Replay week", in: app)

        XCTAssertTrue(app.buttons["lists.detail.show-map"].waitForExistence(timeout: 5))
        app.buttons["lists.detail.show-map"].tap()
        XCTAssertTrue(app.staticTexts["map.list-mode.title"].waitForExistence(timeout: 5))

        openScope(in: app)
        var lovedFilter = app.buttons["explore.scope.list-visits.loved"]
        XCTAssertTrue(scrollToHittable(lovedFilter, in: app))
        XCTAssertTrue(lovedFilter.waitForExistence(timeout: 5))
        XCTAssertEqual(lovedFilter.value as? String, "Not selected")
        lovedFilter.tap()
        XCTAssertTrue(waitForElementValue("Selected", identifier: "explore.scope.list-visits.loved", in: app))
        app.buttons["Close"].tap()
        XCTAssertTrue(waitForSourceFeatureCount(0, in: app))
        XCTAssertTrue(waitForTrackSegmentCount(0, in: app))

        app.terminate()

        let lovedApp = launch(
            reset: true,
            pinDiagnostics: true,
            seedMultiDayTrackList: true,
            seedTrackListLovedVisit: true,
            densePins: true,
            startupViewport: "kl-street"
        )
        XCTAssertTrue(lovedApp.otherElements["map.surface"].waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMapToFinishLoading(in: lovedApp))

        openJournalDoor(in: lovedApp)
        openListFromTracksRoot(named: "Replay week", in: lovedApp)
        XCTAssertTrue(lovedApp.buttons["lists.detail.show-map"].waitForExistence(timeout: 5))
        lovedApp.buttons["lists.detail.show-map"].tap()

        XCTAssertTrue(lovedApp.staticTexts["map.list-mode.title"].waitForExistence(timeout: 5))
        openScope(in: lovedApp)
        lovedFilter = lovedApp.buttons["explore.scope.list-visits.loved"]
        XCTAssertTrue(scrollToHittable(lovedFilter, in: lovedApp))
        XCTAssertTrue(lovedFilter.waitForExistence(timeout: 5))
        attachScreenshot(named: "explore-scope-list-open", forceExport: true)
        exportMeasurements(
            named: "explore-scope-list-open",
            elements: [
                ("root", lovedApp.scrollViews["explore.root"]),
                ("loved-visits", lovedFilter),
                ("other-lists", lovedApp.buttons["explore.scope.list-visits.lists"]),
            ],
            notes: ["context: Replay week"]
        )
        XCTAssertEqual(lovedFilter.value as? String, "Not selected")
        lovedFilter.tap()
        XCTAssertTrue(waitForElementValue("Selected", identifier: "explore.scope.list-visits.loved", in: lovedApp))
        lovedApp.buttons["Close"].tap()
        XCTAssertTrue(waitForSourceFeatureCount(1, in: lovedApp))
        XCTAssertTrue(waitForTrackSegmentCount(0, in: lovedApp))
        attachScreenshot(named: "track-loved-filter-map-source")
    }

    func testExploreOtherListsDrillInUpdatesLiveAndClearStaysOutsideCollection() {
        let app = launch(
            reset: true,
            seedUserList: true,
            seedMultiDayTrackList: true
        )
        XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 10))
        openJournalDoor(in: app)
        openListFromTracksRoot(named: "Replay week", in: app)
        app.buttons["lists.detail.show-map"].tap()
        XCTAssertTrue(app.staticTexts["map.list-mode.title"].waitForExistence(timeout: 5))

        openScope(in: app)
        let otherLists = app.buttons["explore.scope.list-visits.lists"]
        XCTAssertTrue(scrollToHittable(otherLists, in: app))
        XCTAssertEqual(otherLists.value as? String, "None selected")
        otherLists.tap()

        XCTAssertTrue(
            app.otherElements["explore.scope.list-visits.lists.root"]
                .waitForExistence(timeout: 5)
        )
        let back = app.buttons["explore.scope.list-visits.lists.back"]
        XCTAssertTrue(back.exists)
        XCTAssertTrue(back.isHittable)
        let option = app.buttons.matching(
            identifierPrefix: "explore.scope.list-visits.list."
        ).firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        XCTAssertEqual(option.label, "Date night")
        XCTAssertEqual(option.value as? String, "Off")
        XCTAssertGreaterThanOrEqual(option.frame.height, 52)
        option.tap()
        XCTAssertTrue(waitForElementValue(
            "Included",
            identifier: option.identifier,
            in: app
        ))
        let clear = app.buttons["explore.scope.clear"]
        XCTAssertTrue(clear.exists)
        XCTAssertTrue(clear.isHittable)
        attachScreenshot(named: "explore-scope-other-lists", forceExport: true)
        exportMeasurements(
            named: "explore-scope-other-lists",
            elements: [
                ("root", app.otherElements["explore.scope.list-visits.lists.root"]),
                ("back", back),
                ("selected-list", option),
                ("clear", clear),
            ],
            notes: ["selected-list-value: Included"]
        )

        back.tap()
        XCTAssertTrue(otherLists.waitForExistence(timeout: 5))
        XCTAssertEqual(otherLists.value as? String, "Date night")
        XCTAssertTrue(scrollToHittable(clear, in: app))
        clear.tap()
        XCTAssertEqual(otherLists.value as? String, "None selected")
    }

    func testExploreOtherListsEmptyStateNamesExcludedLists() {
        let app = launch(reset: true, seedMultiDayTrackList: true)
        XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 10))
        openJournalDoor(in: app)
        openListFromTracksRoot(named: "Replay week", in: app)
        app.buttons["lists.detail.show-map"].tap()
        XCTAssertTrue(app.staticTexts["map.list-mode.title"].waitForExistence(timeout: 5))

        openScope(in: app)
        let otherLists = app.buttons["explore.scope.list-visits.lists"]
        XCTAssertTrue(scrollToHittable(otherLists, in: app))
        otherLists.tap()

        let empty = app.staticTexts["explore.scope.list-visits.lists.empty"]
        XCTAssertTrue(empty.waitForExistence(timeout: 5))
        XCTAssertTrue(empty.label.contains("active and system lists are excluded"))
        XCTAssertEqual(
            app.buttons.matching(identifierPrefix: "explore.scope.list-visits.list.").count,
            0
        )
        XCTAssertTrue(app.buttons["explore.scope.list-visits.lists.back"].isHittable)
        attachScreenshot(named: "explore-scope-other-lists-empty", forceExport: true)
        exportMeasurements(
            named: "explore-scope-other-lists-empty",
            elements: [
                ("root", app.otherElements["explore.scope.list-visits.lists.root"]),
                ("back", app.buttons["explore.scope.list-visits.lists.back"]),
                ("empty", empty),
            ],
            notes: ["option-count: 0"]
        )
    }

    func testExploreOtherListsAX5KeepsLongLiteralRowsAndFixedActionsContained() {
        let longListName =
            "Longest list **literal** 0123456789 0123456789 0123456789 "
            + "0123456789 0123456789!"
        XCTAssertEqual(longListName.unicodeScalars.count, 80)

        let app = launch(
            reset: true,
            accessibilityTextSize: true,
            seedUserList: true,
            seedJournalDoorTextStress: true
        )
        XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 10))
        openJournalDoor(in: app)
        openListFromTracksRoot(named: "Date night", in: app)
        app.buttons["lists.detail.show-map"].tap()
        XCTAssertTrue(app.staticTexts["map.list-mode.title"].waitForExistence(timeout: 5))

        openScope(in: app)
        let otherLists = app.buttons["explore.scope.list-visits.lists"]
        XCTAssertTrue(scrollToHittable(otherLists, in: app))
        otherLists.tap()

        let root = app.otherElements["explore.scope.list-visits.lists.root"]
        XCTAssertTrue(root.waitForExistence(timeout: 5))
        let back = app.buttons["explore.scope.list-visits.lists.back"]
        XCTAssertTrue(back.isHittable)
        assertMinimumInteractiveTarget(back)
        assertContainedInAppFrame(back, in: app)

        let collection = app.scrollViews["explore.scope.list-visits.lists.collection"]
        XCTAssertTrue(collection.exists)
        XCTAssertEqual(collection.frame.height, 350, accuracy: 1)
        let options = app.buttons.matching(
            identifierPrefix: "explore.scope.list-visits.list."
        )
        XCTAssertEqual(
            options.count,
            1,
            "The active Date night list is excluded, leaving the one long literal fixture list."
        )
        for option in options.allElementsBoundByIndex {
            XCTAssertGreaterThanOrEqual(option.frame.height, 86)
            XCTAssertLessThanOrEqual(option.frame.height, collection.frame.height)
            XCTAssertTrue(
                collection.frame.contains(option.frame),
                "\(option.identifier) frame \(option.frame) escapes collection frame \(collection.frame)"
            )
        }

        let longOption = options.matching(
            NSPredicate(format: "label == %@", longListName)
        ).firstMatch
        XCTAssertEqual(longOption.label, longListName)
        longOption.tap()
        XCTAssertTrue(waitForElementValue(
            "Included",
            identifier: longOption.identifier,
            in: app
        ))

        let clear = app.buttons["explore.scope.clear"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        XCTAssertTrue(clear.isHittable)
        assertMinimumInteractiveTarget(clear)
        assertContainedInAppFrame(clear, in: app)
        assertNoFrameIntersection(collection, clear)
        assertNoFrameIntersection(longOption, clear)
        attachScreenshot(named: "explore-scope-other-lists-ax", forceExport: true)
        exportMeasurements(
            named: "explore-scope-other-lists-ax",
            elements: [
                ("root", root),
                ("back", back),
                ("collection", collection),
                ("long-list", longOption),
                ("clear", clear),
            ],
            notes: [
                "dynamic-type: AX5",
                "long-list-unicode-scalars: 80",
                "long-list-value: Included",
            ]
        )
    }

    func testEditingListFilterFromFreshPromotesTracksAndUpdatesTheMap() {
        let app = launch(
            reset: true,
            seedUserList: true,
            pinDiagnostics: true,
            seedMultiDayTrackList: true,
            seedTrackListLovedVisit: true,
            startupViewport: "kl-street"
        )
        XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMapToFinishLoading(in: app))
        openJournalDoor(in: app)
        openListFromTracksRoot(named: "Date night", in: app)
        app.buttons["lists.detail.show-map"].tap()
        XCTAssertTrue(app.staticTexts["map.list-mode.title"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForMapSurfaceToSettle(in: app))

        let fresh = app.buttons["map.list-mode.fresh"]
        let tracks = app.buttons["map.list-mode.tracks"]
        XCTAssertTrue(fresh.waitForExistence(timeout: 5))
        XCTAssertTrue(tracks.exists)
        fresh.tap()
        XCTAssertTrue(waitForElementValue(
            "Selected",
            identifier: "map.list-mode.fresh",
            in: app
        ))
        XCTAssertEqual(tracks.value as? String, "Not selected")

        openScope(in: app)
        let loved = app.buttons["explore.scope.list-visits.loved"]
        XCTAssertTrue(scrollToHittable(loved, in: app))
        loved.tap()
        XCTAssertTrue(waitForElementValue(
            "Selected",
            identifier: "map.list-mode.tracks",
            in: app
        ))
        XCTAssertEqual(fresh.value as? String, "Not selected")
        app.buttons["Close"].tap()

        let exploreDoor = app.buttons["map.door.explore"]
        XCTAssertTrue(exploreDoor.waitForExistence(timeout: 5))
        XCTAssertEqual(exploreDoor.value as? String, "Scope adjusted")
        XCTAssertTrue(waitForSourceFeatureCount(1, in: app))
        XCTAssertTrue(waitForTrackSegmentCount(0, in: app))
    }

    func testTrackCategoryFilterScopesReplayDisplayAndCamera() {
        let app = launch(
            reset: true,
            pinDiagnostics: true,
            seedMultiDayTrackList: true,
            densePins: true,
            startupViewport: "kl-street"
        )

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMapToFinishLoading(in: app))

        openJournalDoor(in: app)
        openListFromTracksRoot(named: "Replay week", in: app)
        XCTAssertTrue(app.buttons["lists.detail.show-map"].waitForExistence(timeout: 5))
        app.buttons["lists.detail.show-map"].tap()
        XCTAssertTrue(app.staticTexts["map.list-mode.title"].waitForExistence(timeout: 5))

        openScope(in: app)
        let toggleAll = app.buttons["explore.scope.categories.toggle-all"]
        XCTAssertTrue(scrollToHittable(toggleAll, in: app))
        toggleAll.tap()
        let attraction = app.buttons["explore.scope.category.attraction"]
        XCTAssertTrue(scrollToHittable(attraction, in: app))
        attraction.tap()
        app.buttons["Close"].tap()

        XCTAssertTrue(waitForSourceFeatureCount(1, in: app))
        XCTAssertTrue(waitForTrackSegmentCount(0, in: app))
        XCTAssertTrue(waitForProjectedFixturePinCount(1, in: app))
        let projectedPin = app.staticTexts.matching(identifierPrefix: "map.fixture-pin.").firstMatch
        XCTAssertTrue(projectedPin.identifier.contains("mt1_D0000000000000000000000001"), projectedPin.identifier)
        XCTAssertEqual(projectedPin.label, "hit", projectedPin.identifier)
        guard let projectedValue = projectedPin.value as? String else {
            return XCTFail("missing normalized coordinates for \(projectedPin.identifier)")
        }
        let normalized = normalizedPoint(from: projectedValue)
        XCTAssertGreaterThan(normalized.x, 0.04, projectedPin.identifier)
        XCTAssertLessThan(normalized.x, 0.96, projectedPin.identifier)
        XCTAssertGreaterThan(normalized.y, 0.08, projectedPin.identifier)
        XCTAssertLessThan(normalized.y, 0.92, projectedPin.identifier)
        attachScreenshot(named: "track-category-filter-map-source")

        app.buttons["map.list-mode.back"].tap()
        XCTAssertTrue(app.staticTexts["Replay week"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["lists.detail.show-map"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["lists.detail.progress"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["lists.detail.progress"].label, "you've been to 1 of these · all seen")
        XCTAssertTrue(app.staticTexts["Dense Pin 1"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Dense Pin 2"].exists)

        app.buttons["lists.detail.show-map"].tap()
        XCTAssertTrue(app.staticTexts["map.list-mode.title"].waitForExistence(timeout: 5))
        openScope(in: app)
        let showAll = app.buttons["explore.scope.categories.toggle-all"]
        XCTAssertTrue(scrollToHittable(showAll, in: app))
        showAll.tap()
        app.buttons["Close"].tap()

        XCTAssertTrue(waitForSourceFeatureCount(6, in: app))
        app.buttons["map.list-mode.back"].tap()
        XCTAssertTrue(app.staticTexts["Replay week"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["lists.detail.progress"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["lists.detail.progress"].label, "you've been to 6 of these · all seen")
        XCTAssertTrue(app.staticTexts["Dense Pin 2"].waitForExistence(timeout: 5))
    }

    func testTrackCategoryFilterScopesReplayTimelineAndAutoplay() {
        let app = launch(
            reset: true,
            seedVisitsEditorVisual: true,
            trackReplayBeatDuration: 5
        )

        XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 10))
        openJournalDoor(in: app)
        app.buttons["journal.row.my-tracks"].tap()
        XCTAssertTrue(app.collectionViews["lists.detail.surface.track"].waitForExistence(timeout: 5))
        app.buttons["lists.detail.show-map"].tap()
        XCTAssertTrue(app.staticTexts["map.list-mode.title"].waitForExistence(timeout: 5))

        openScope(in: app)
        let toggleAll = app.buttons["explore.scope.categories.toggle-all"]
        XCTAssertTrue(scrollToHittable(toggleAll, in: app))
        toggleAll.tap()
        let attraction = app.buttons["explore.scope.category.attraction"]
        XCTAssertTrue(scrollToHittable(attraction, in: app))
        attraction.tap()
        app.buttons["Close"].tap()

        XCTAssertTrue(waitForTrackReplayCounter("Visit 2 of 2", in: app))
        XCTAssertTrue(waitForTrackReplayArrival(
            prefix: "Visit 2 of 2, Petronas Twin Towers Observation Deck",
            in: app
        ))

        let play = app.buttons["map.track-replay.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        play.tap()
        XCTAssertTrue(waitForTrackReplayCounter("Visit 1 of 2", in: app))
        XCTAssertTrue(waitForTrackReplayArrival(
            prefix: "Visit 1 of 2, Ghost Sign",
            in: app
        ))
        play.tap()
    }

    func testExploreCategoryScopeFiltersReplayTimelineAndAutoplay() {
        let app = launch(
            reset: true,
            seedVisitsEditorVisual: true,
            trackReplayBeatDuration: 5
        )

        XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 10))
        openJournalDoor(in: app)
        app.buttons["journal.row.my-tracks"].tap()
        XCTAssertTrue(app.collectionViews["lists.detail.surface.track"].waitForExistence(timeout: 5))
        app.buttons["lists.detail.show-map"].tap()
        XCTAssertTrue(app.staticTexts["map.list-mode.title"].waitForExistence(timeout: 5))

        openScope(in: app)
        let toggleAll = app.buttons["explore.scope.categories.toggle-all"]
        XCTAssertTrue(scrollToHittable(toggleAll, in: app))
        XCTAssertEqual(toggleAll.label, "Hide all")
        toggleAll.tap()
        XCTAssertTrue(waitForButtonLabel(
            "Show all",
            identifier: "explore.scope.categories.toggle-all",
            in: app
        ))

        let attraction = "explore.scope.category.attraction"
        XCTAssertTrue(scrollToHittable(app.buttons[attraction], in: app))
        tapCategoryChip(in: app, identifier: attraction, expectedValue: "Selected")
        app.buttons["Close"].tap()

        XCTAssertTrue(waitForTrackReplayCounter("Visit 2 of 2", in: app))
        XCTAssertTrue(waitForTrackReplayArrival(
            prefix: "Visit 2 of 2, Petronas Twin Towers Observation Deck",
            in: app
        ))

        let play = app.buttons["map.track-replay.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        play.tap()
        XCTAssertTrue(waitForTrackReplayCounter("Visit 1 of 2", in: app))
        XCTAssertTrue(waitForTrackReplayArrival(
            prefix: "Visit 1 of 2, Ghost Sign",
            in: app
        ))
        play.tap()
    }

    func testExploreOtherCategoryScopesReplayToFallbackVisits() {
        let app = launch(
            reset: true,
            seedVisitsEditorVisual: true,
            trackReplayBeatDuration: 5
        )

        XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 10))
        openJournalDoor(in: app)
        app.buttons["journal.row.my-tracks"].tap()
        XCTAssertTrue(app.collectionViews["lists.detail.surface.track"].waitForExistence(timeout: 5))
        app.buttons["lists.detail.show-map"].tap()
        XCTAssertTrue(app.staticTexts["map.list-mode.title"].waitForExistence(timeout: 5))

        openScope(in: app)
        let toggleAll = app.buttons["explore.scope.categories.toggle-all"]
        XCTAssertTrue(scrollToHittable(toggleAll, in: app))
        toggleAll.tap()

        let other = "explore.scope.category.uncategorized"
        XCTAssertTrue(scrollToHittable(app.buttons[other], in: app))
        tapCategoryChip(in: app, identifier: other, expectedValue: "Selected")
        app.buttons["Close"].tap()

        XCTAssertTrue(waitForTrackReplayCounter("Visit 3 of 3", in: app))
        XCTAssertTrue(waitForTrackReplayArrival(
            prefix: "Visit 3 of 3, Jalan Alor Night Market",
            in: app
        ))

        let play = app.buttons["map.track-replay.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        play.tap()
        XCTAssertTrue(waitForTrackReplayCounter("Visit 1 of 3", in: app))
        XCTAssertTrue(waitForTrackReplayArrival(
            prefix: "Visit 1 of 3, Central Market",
            in: app
        ))
        play.tap()
    }

    func testExploreScopeExplicitlyReturnsFromNoCategoriesToAll() {
        let app = launch(reset: true, seedVisitsEditorVisual: true)

        XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 10))
        openJournalDoor(in: app)
        app.buttons["journal.row.my-tracks"].tap()
        XCTAssertTrue(app.collectionViews["lists.detail.surface.track"].waitForExistence(timeout: 5))
        app.buttons["lists.detail.show-map"].tap()
        XCTAssertTrue(app.staticTexts["map.list-mode.title"].waitForExistence(timeout: 5))

        openScope(in: app)
        let toggleAll = app.buttons["explore.scope.categories.toggle-all"]
        XCTAssertTrue(scrollToHittable(toggleAll, in: app))
        toggleAll.tap()
        XCTAssertTrue(waitForButtonLabel(
            "Show all",
            identifier: "explore.scope.categories.toggle-all",
            in: app
        ))
        toggleAll.tap()
        XCTAssertTrue(waitForButtonLabel(
            "Hide all",
            identifier: "explore.scope.categories.toggle-all",
            in: app
        ))
        app.buttons["Close"].tap()

        XCTAssertTrue(waitForTrackReplayCounter("Visit 8 of 8", in: app))
        XCTAssertTrue(waitForTrackReplayArrival(
            prefix: "Visit 8 of 8, Jalan Alor Night Market",
            in: app
        ))
    }

    func testListMapBackReturnsToSeededListDetail() {
        let app = launch(reset: true, pinDiagnostics: true, seedTrackList: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMapToFinishLoading(in: app))

        openJournalDoor(in: app)
        openListFromTracksRoot(named: "Track pair", in: app)
        XCTAssertTrue(app.buttons["lists.detail.show-map"].waitForExistence(timeout: 5))
        app.buttons["lists.detail.show-map"].tap()
        XCTAssertTrue(app.staticTexts["map.list-mode.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["map.list-mode.title"].label, "Track pair")

        app.buttons["map.list-mode.back"].tap()

        XCTAssertTrue(app.staticTexts["Track pair"].waitForExistence(timeout: 5))
        app.buttons["lists.detail.show-map"].tap()
        XCTAssertTrue(app.staticTexts["map.list-mode.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["map.list-mode.title"].label, "Track pair")
        XCTAssertFalse(app.staticTexts["Lists"].exists)
    }

    func testMyTracksSystemListDrawsWholeLogTrackWithoutStoredListMembership() {
        let app = launch(reset: true, pinDiagnostics: true, seedBurstTrackVisits: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMapToFinishLoading(in: app))
        XCTAssertTrue(waitForTrackSegmentCount(0, in: app))

        openJournalDoor(in: app)
        app.buttons["journal.row.my-tracks"].tap()
        XCTAssertTrue(app.buttons["lists.detail.show-map"].waitForExistence(timeout: 5))
        app.buttons["lists.detail.show-map"].tap()
        XCTAssertTrue(app.staticTexts["map.list-mode.title"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForSourceFeatureCount(2, in: app))
        XCTAssertTrue(waitForTrackSegmentCount(1, in: app))
        XCTAssertFalse(app.staticTexts["map.track-connection-readout"].exists)
        attachScreenshot(named: "my-tracks-continuous-line")
    }

    func testListMapCameraFitsSpreadListMembers() {
        let app = launch(reset: true, pinDiagnostics: true, seedSpreadList: true, startupViewport: "kl-street")

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMapToFinishLoading(in: app))

        openJournalDoor(in: app)
        openListFromTracksRoot(named: "Spread walk", in: app)
        XCTAssertTrue(app.buttons["lists.detail.show-map"].waitForExistence(timeout: 5))
        app.buttons["lists.detail.show-map"].tap()

        XCTAssertTrue(app.staticTexts["map.list-mode.title"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForSourceFeatureCount(5, in: app))
        XCTAssertTrue(waitForProjectedFixturePinCount(5, in: app))
        for pin in app.staticTexts.matching(identifierPrefix: "map.fixture-pin.").allElementsBoundByIndex {
            XCTAssertEqual(pin.label, "hit")
            guard let value = pin.value as? String else {
                return XCTFail("missing normalized coordinates for \(pin.identifier)")
            }
            let normalized = normalizedPoint(from: value)
            XCTAssertGreaterThan(normalized.x, 0.04, pin.identifier)
            XCTAssertLessThan(normalized.x, 0.96, pin.identifier)
            XCTAssertGreaterThan(normalized.y, 0.08, pin.identifier)
            XCTAssertLessThan(normalized.y, 0.92, pin.identifier)
        }
        attachScreenshot(named: "list-map-spread-fit")
    }

    func testHiddenToastAutoDismissesWithoutUnhidingPlace() {
        let app = launch(reset: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))

        openFixtureCard(in: map, app: app)
        app.buttons["place-card.hide"].tap()
        XCTAssertTrue(app.staticTexts["Hidden — Undo"].waitForExistence(timeout: 5))

        XCTAssertTrue(waitForNonExistence(of: app.staticTexts["Hidden — Undo"], timeout: 7))
        tapFixtureCoordinate(in: map)
        XCTAssertFalse(app.staticTexts["Ghost Sign"].waitForExistence(timeout: 2))
    }

    func testHiddenToastUndoRestoresHiddenPlaceAtAX5() {
        let app = launch(reset: true, accessibilityTextSize: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))

        openFixtureCard(in: map, app: app)
        app.buttons["place-card.hide"].tap()
        XCTAssertTrue(app.staticTexts["Hidden — Undo"].waitForExistence(timeout: 5))

        let undoButton = app.buttons["place-card.hide.undo"]
        XCTAssertTrue(undoButton.waitForExistence(timeout: 5))
        XCTAssertEqual(undoButton.label, "Undo")
        XCTAssertTrue(undoButton.isHittable)
        assertMinimumInteractiveTarget(undoButton)
        assertContainedInAppFrame(undoButton, in: app)
        undoButton.tap()
        XCTAssertFalse(app.staticTexts["Hidden — Undo"].waitForExistence(timeout: 2))

        openFixtureCard(in: map, app: app)
    }

    func testHideRemovesFixturePinFromMapSource() {
        let app = launch(reset: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))

        openFixtureCard(in: map, app: app)
        closePlaceCard(in: app)
        app.buttons["debug.hide-fixture"].tap()
        XCTAssertTrue(waitForFixtureHidden(true, in: app))

        tapFixtureCoordinate(in: map)
        XCTAssertFalse(app.staticTexts["Ghost Sign"].waitForExistence(timeout: 2))

        openSecondFixtureCard(in: map, app: app)
    }

    func testUnhideRestoresFixturePinToMapSourceBeforeCardDismissal() {
        let app = launch(reset: true, pinDiagnostics: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMapToFinishLoading(in: app))

        app.buttons["debug.hide-fixture"].tap()
        XCTAssertTrue(waitForFixtureHidden(true, in: app))
        XCTAssertTrue(waitForSourceFeatureCount(1, in: app))
        XCTAssertTrue(waitForNonExistence(of: app.staticTexts["map.fixture-pin.\(placeID)"], timeout: 5))

        app.buttons["debug.unhide-fixture"].tap()
        XCTAssertTrue(waitForFixtureHidden(false, in: app))
        XCTAssertTrue(waitForSourceFeatureCount(2, in: app))
        openFixtureCard(in: map, app: app)
    }

    func testExploreScopeCanHideCategoryPins() {
        let app = launch(reset: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))

        openScope(in: app)
        let historicBuildings = "explore.scope.category.historic_building"
        XCTAssertTrue(app.buttons[historicBuildings].waitForExistence(timeout: 5))
        tapCategoryChip(
            in: app,
            identifier: historicBuildings,
            expectedValue: "Not selected"
        )
        app.buttons["Close"].tap()

        XCTAssertTrue(waitForNonExistence(
            of: app.buttons["map.pin.mt1_00000000000000000000000001"],
            timeout: 5
        ))
        tapSecondFixturePin(in: map)
        XCTAssertFalse(app.staticTexts["Art Deco Cinema"].waitForExistence(timeout: 2))

        openScope(in: app)
        XCTAssertTrue(app.buttons[historicBuildings].waitForExistence(timeout: 5))
        tapCategoryChip(in: app, identifier: historicBuildings, expectedValue: "Selected")
        app.buttons["Close"].tap()
        XCTAssertTrue(waitForAccessibilityPin(
            in: app,
            placeID: "mt1_00000000000000000000000001",
            label: "Art Deco Cinema, Historic Building, not visited"
        ))

        openSecondFixtureCard(in: map, app: app)
        closePlaceCard(in: app)

        openFixtureCard(in: map, app: app)
    }

    func testExploreScopeToggleAllCategoriesHidesAndRestoresPins() {
        let app = launch(reset: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))

        openScope(in: app)
        let toggleAll = app.buttons["explore.scope.categories.toggle-all"]
        XCTAssertTrue(scrollToHittable(toggleAll, in: app))
        XCTAssertEqual(toggleAll.label, "Hide all")
        toggleAll.tap()
        XCTAssertTrue(waitForButtonLabel("Show all", identifier: "explore.scope.categories.toggle-all", in: app))
        app.buttons["Close"].tap()

        tapFixtureCoordinate(in: map)
        XCTAssertFalse(app.staticTexts["Ghost Sign"].waitForExistence(timeout: 2))
        tapSecondFixturePin(in: map)
        XCTAssertFalse(app.staticTexts["Art Deco Cinema"].waitForExistence(timeout: 2))

        openScope(in: app)
        XCTAssertTrue(scrollToHittable(toggleAll, in: app))
        XCTAssertTrue(waitForButtonLabel("Show all", identifier: "explore.scope.categories.toggle-all", in: app))
        toggleAll.tap()
        XCTAssertTrue(waitForButtonLabel("Hide all", identifier: "explore.scope.categories.toggle-all", in: app))
        app.buttons["Close"].tap()

        openFixtureCard(in: map, app: app)
        closePlaceCard(in: app)
        openSecondFixtureCard(in: map, app: app)
    }

    func testShowHiddenModeExposesUnhideAffordanceWithoutNormalHideOwnership() {
        let app = launch(reset: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))

        app.buttons["debug.hide-fixture"].tap()
        XCTAssertTrue(waitForFixtureHidden(true, in: app))
        tapFixtureCoordinate(in: map)
        XCTAssertFalse(app.staticTexts["Ghost Sign"].waitForExistence(timeout: 2))

        openScope(in: app)
        let showHidden = "explore.scope.include-hidden"
        XCTAssertTrue(app.switches[showHidden].waitForExistence(timeout: 5))
        tapSwitch(in: app, identifier: showHidden, expectedValue: "1")
        app.buttons["Close"].tap()

        openFixtureCard(in: map, app: app, expectedHidden: true)
        XCTAssertTrue(app.buttons["place-card.unhide"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["place-card.hide"].exists)

        app.buttons["place-card.unhide"].tap()
        XCTAssertFalse(app.buttons["place-card.unhide"].waitForExistence(timeout: 2))
        closePlaceCard(in: app)
        openFixtureCard(in: map, app: app)
    }

    func testDoorInventoriesAboutCreditsAndMapAttributionIsInert() throws {
        let app = launch(reset: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))

        XCTAssertFalse(app.buttons["map.openstreetmap-attribution"].exists)
        XCTAssertTrue(app.staticTexts["map.openstreetmap-attribution"].waitForExistence(timeout: 5))

        openExploreDoor(in: app)
        XCTAssertTrue(app.staticTexts["Explore"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.scrollViews["explore.root"].exists)
        XCTAssertFalse(app.buttons["world.row.scope"].exists)
        XCTAssertTrue(app.switches["explore.scope.include-hidden"].exists)
        XCTAssertTrue(app.switches["explore.scope.coverage-shading"].exists)
        XCTAssertTrue(app.buttons["explore.row.settings"].exists)
        XCTAssertTrue(app.buttons["explore.row.about"].exists)
        XCTAssertFalse(app.buttons["journal.row.lists"].exists)
        XCTAssertFalse(app.buttons["journal.row.my-tracks"].exists)

        app.buttons["explore.row.about"].tap()
        XCTAssertTrue(app.staticTexts["About"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts["The story, the privacy promise, and the credits."]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["The map is fresh snow."].exists)
        XCTAssertTrue(app.staticTexts["Private by construction"].exists)
        XCTAssertTrue(app.staticTexts["Nothing you save leaves unless you choose to share it."].exists)
        attachScreenshot(named: "t2.10-about", forceExport: true)
        let versionLabel = app.staticTexts["about.app-version"]
        XCTAssertTrue(versionLabel.waitForExistence(timeout: 5))
        XCTAssertEqual(versionLabel.label, try expectedAppVersionLabel())
        let expectedBuildLabel = "Build \(try currentGitCommit())"
        XCTAssertTrue(app.staticTexts[expectedBuildLabel].waitForExistence(timeout: 5))
        let privacyPolicy = element(identifier: "about.privacy-policy", in: app)
        XCTAssertTrue(privacyPolicy.waitForExistence(timeout: 5))
        XCTAssertEqual(privacyPolicy.label, "Privacy policy")
        XCTAssertEqual(privacyPolicy.value as? String, "https://making-tracks.app/privacy")
        XCTAssertTrue(privacyPolicy.isHittable)
        assertMinimumInteractiveTarget(privacyPolicy)
        assertContainedInAppFrame(privacyPolicy, in: app)
        XCTAssertFalse(app.staticTexts["Open source acknowledgements"].exists)

        let softwareLicences = app.buttons["about.software-licences"]
        let dataLicences = app.buttons["about.data-licences"]
        XCTAssertTrue(scrollToHittable(softwareLicences, in: app))
        XCTAssertEqual(softwareLicences.label, "Software licences")
        XCTAssertEqual(
            softwareLicences.value as? String,
            "GRDB.swift · MapLibre · Newsreader OFL · Noto Sans"
        )
        assertMinimumInteractiveTarget(softwareLicences)
        XCTAssertTrue(scrollToHittable(dataLicences, in: app))
        XCTAssertEqual(dataLicences.label, "Data licences")
        XCTAssertEqual(
            dataLicences.value as? String,
            "OpenStreetMap · Wikipedia · regional sources"
        )
        assertMinimumInteractiveTarget(dataLicences)

        XCTAssertTrue(scrollToHittable(softwareLicences, in: app))
        softwareLicences.tap()
        XCTAssertTrue(app.staticTexts["Software licences"].waitForExistence(timeout: 5))
        attachScreenshot(named: "t2.10-software-licences", forceExport: true)
        let softwareExpectations = [
            (
                id: "GRDB.swift|7.11.1",
                noticeDigest: "5477c7feb396cb058cf402697c9ef59c0221a68d63921d74f44670cb488d1a7f",
                licenseURL: "https://github.com/groue/GRDB.swift/blob/master/LICENSE"
            ),
            (
                id: "MapLibre Native iOS / maplibre-gl-native-distribution|6.27.0",
                noticeDigest: "691bbc091d6a3c1bd6f5c488612baf9635658bcfe2692e87f885a19e7315ba4f",
                licenseURL: "https://github.com/maplibre/maplibre-native/blob/main/LICENSE.md"
            ),
            (
                id: "Newsreader|productiontype/Newsreader commit cfcb4f7af0e52c25e8df2a2431814c8e5fe2e155; static TTF instances",
                noticeDigest: "fdfad38143ec470553cae82a1e45320bdd1b9ec70415d37bd0171051d8a4ded8",
                licenseURL: "https://github.com/productiontype/Newsreader/blob/cfcb4f7af0e52c25e8df2a2431814c8e5fe2e155/OFL.txt"
            ),
            (
                id: "Noto Sans glyph PBF mirror|protomaps/basemaps-assets commit 028c18f713baecad011301ff7a69acc39bcc2ae7; Noto Sans Regular",
                noticeDigest: "9eba12c12d46c3b966acaf5c82a33283fe48903a70618b99cb32e384cc216654",
                licenseURL: "https://openfontlicense.org/"
            ),
        ]
        let lastLicense = element(
            identifier: "credits.oss.\(softwareExpectations.last!.id).license",
            in: app
        )
        XCTAssertTrue(lastLicense.exists)
        XCTAssertFalse(lastLicense.isHittable, "The endpoint must begin off-screen so traversal has teeth")
        for expectation in softwareExpectations {
            let notice = element(identifier: "credits.oss.\(expectation.id).notice", in: app)
            XCTAssertTrue(notice.waitForExistence(timeout: 5))
            XCTAssertEqual(sha256(notice.label), expectation.noticeDigest)

            let license = element(identifier: "credits.oss.\(expectation.id).license", in: app)
            XCTAssertTrue(scrollToFullyContained(license, in: app, maxSwipes: 80))
            XCTAssertEqual(license.elementType, .button)
            XCTAssertTrue(license.isEnabled)
            XCTAssertEqual(license.value as? String, expectation.licenseURL)
            assertMinimumInteractiveTarget(license)
            assertContainedInAppFrame(license, in: app)
        }
        app.buttons["Back"].tap()

        XCTAssertTrue(scrollToHittable(dataLicences, in: app))
        dataLicences.tap()
        XCTAssertTrue(app.staticTexts["Data licences"].waitForExistence(timeout: 5))
        attachScreenshot(named: "t2.10-data-licences", forceExport: true)
        let osmText = app.staticTexts["about.openstreetmap-attribution"]
        XCTAssertTrue(osmText.waitForExistence(timeout: 5))
        XCTAssertEqual(osmText.label, "Map data © OpenStreetMap contributors.")
        let osmCopyright = element(identifier: "about.openstreetmap-copyright", in: app)
        XCTAssertTrue(scrollToFullyContained(osmCopyright, in: app, maxSwipes: 10))
        XCTAssertEqual(osmCopyright.value as? String, "https://www.openstreetmap.org/copyright")
        assertMinimumInteractiveTarget(osmCopyright)
        assertContainedInAppFrame(osmCopyright, in: app)
        let runtimeAttribution = element(identifier: "credits.manifest.osm", in: app)
        XCTAssertTrue(scrollToFullyContained(runtimeAttribution, in: app, maxSwipes: 10))
        XCTAssertTrue(runtimeAttribution.label.contains("osm"))
        XCTAssertTrue(runtimeAttribution.label.contains("ODbL-1.0"))
        XCTAssertTrue(runtimeAttribution.label.contains("OSM credit"))
        app.buttons["Back"].tap()
        app.buttons["Close"].tap()

        openJournalDoor(in: app)
        XCTAssertTrue(app.staticTexts["Journal"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifierPrefix: "journal.row.").count, 3)
        XCTAssertFalse(app.buttons["journal.row.lists"].exists)
        XCTAssertTrue(app.buttons["journal.row.my-tracks"].exists)
        XCTAssertTrue(app.buttons["journal.row.loved"].exists)
        XCTAssertTrue(app.buttons["journal.row.hidden"].exists)
        XCTAssertTrue(app.buttons.matching(identifierPrefix: "lists.row.").firstMatch.exists)
        XCTAssertTrue(app.textFields["lists.create.name"].exists)
        XCTAssertTrue(app.buttons["lists.create"].exists)
        XCTAssertFalse(app.buttons["world.row.scope"].exists)
        XCTAssertFalse(app.buttons["explore.row.settings"].exists)
        XCTAssertFalse(app.buttons["explore.row.about"].exists)
        app.buttons["Close"].tap()
    }

    func testOfflineProgressChipDeepLinksToOfflineMapsAtAX5() {
        let activeDownloadApp = launch(
            reset: true,
            accessibilityTextSize: true,
            offlineProgress: 0.42
        )
        let activeMap = activeDownloadApp.otherElements["map.surface"]
        XCTAssertTrue(activeMap.waitForExistence(timeout: 10))

        let progressChip = activeDownloadApp.buttons["map.download-progress"]
        XCTAssertTrue(progressChip.waitForExistence(timeout: 5))
        XCTAssertEqual(progressChip.label, "Offline maps download")
        XCTAssertEqual(progressChip.value as? String, "42%")
        XCTAssertTrue(progressChip.isHittable)
        assertMinimumInteractiveTarget(progressChip)
        assertContainedInAppFrame(progressChip, in: activeDownloadApp)
        progressChip.tap()

        XCTAssertTrue(activeDownloadApp.staticTexts["Offline maps"].waitForExistence(timeout: 5))
        activeDownloadApp.buttons["Close"].tap()

        XCTAssertTrue(activeMap.waitForExistence(timeout: 5))
        openExploreDoor(in: activeDownloadApp)
        XCTAssertTrue(activeDownloadApp.staticTexts["Explore"].waitForExistence(timeout: 5))
        XCTAssertTrue(activeDownloadApp.switches["explore.scope.include-hidden"].exists)
        XCTAssertTrue(activeDownloadApp.switches["explore.scope.coverage-shading"].exists)
        XCTAssertTrue(activeDownloadApp.buttons["explore.row.settings"].exists)
        XCTAssertTrue(activeDownloadApp.buttons["explore.row.about"].exists)
        activeDownloadApp.buttons["Close"].tap()
    }

    func testOfflineProgressChipAnnouncesWaitingConnectivity() {
        let app = launch(
            reset: true,
            accessibilityTextSize: true,
            offlineProgress: 0.42,
            offlineWaiting: true
        )
        XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 10))

        let progressChip = app.buttons["map.download-progress"]
        XCTAssertTrue(progressChip.waitForExistence(timeout: 5))
        XCTAssertEqual(progressChip.label, "Offline maps download, Waiting for Wi-Fi")
        XCTAssertEqual(progressChip.value as? String, "42%")
        XCTAssertTrue(progressChip.isHittable)
        assertMinimumInteractiveTarget(progressChip)
        assertContainedInAppFrame(progressChip, in: app)
    }

    func testSettingsThemePickerSelectsRealTheme() {
        let app = launch(reset: true, resetTheme: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))

        openExploreDoor(in: app)
        app.buttons["explore.row.settings"].tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
        let appearance = app.buttons["settings.group.appearance"]
        XCTAssertTrue(appearance.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["settings.theme.selected"].exists)
        XCTAssertFalse(app.buttons["settings.theme.defined-paper"].exists)
        appearance.tap()
        XCTAssertTrue(app.staticTexts["Appearance"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings.theme.defined-paper"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForElementValue("Selected", identifier: "settings.theme.defined-paper", in: app))
        XCTAssertTrue(waitForElementValue("Not selected", identifier: "settings.theme.snow", in: app))

        let snowThemeButton = app.buttons["settings.theme.snow"]
        XCTAssertTrue(scrollToHittable(snowThemeButton, in: app))
        snowThemeButton.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertTrue(waitForElementValue("Selected", identifier: "settings.theme.snow", in: app))
        XCTAssertTrue(waitForElementValue("Not selected", identifier: "settings.theme.defined-paper", in: app))
        app.buttons["Close"].tap()
    }

    func testSettingsHubRoutesEveryRuledGroupWithoutLosingExistingActions() {
        let app = launch(reset: true, locationDenied: true)
        XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 10))

        openExploreDoor(in: app)
        app.buttons["explore.row.settings"].tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))

        let rootIdentifiers = [
            "settings.group.appearance",
            "settings.storage.manage",
            "settings.group.coverage",
            "settings.group.map-data",
            "settings.group.location",
            "settings.diagnostics.export",
            "settings.replay-onboarding",
        ]
        let rootIdentifierSet = Set(rootIdentifiers)
        XCTAssertEqual(
            app.buttons.allElementsBoundByIndex
                .map(\.identifier)
                .filter { rootIdentifierSet.contains($0) },
            rootIdentifiers,
            "Settings groups must remain in the ruled W-2 order."
        )

        let appearance = app.buttons[rootIdentifiers[0]]
        assertSettingsRootRow(appearance, in: app)
        appearance.tap()
        XCTAssertTrue(app.staticTexts["Appearance"].waitForExistence(timeout: 5))
        for themeID in ["defined-paper", "snow", "street-contrast", "verdant-kl"] {
            XCTAssertTrue(app.buttons["settings.theme.\(themeID)"].exists, themeID)
        }
        app.buttons["Back"].tap()

        let offlineMaps = app.buttons[rootIdentifiers[1]]
        assertSettingsRootRow(offlineMaps, in: app)
        offlineMaps.tap()
        XCTAssertTrue(app.staticTexts["Offline maps"].waitForExistence(timeout: 5))
        app.buttons["Back"].tap()

        let coverage = app.buttons[rootIdentifiers[2]]
        assertSettingsRootRow(coverage, in: app)
        coverage.tap()
        XCTAssertTrue(app.staticTexts["Coverage"].waitForExistence(timeout: 5))
        for identifier in [
            "settings.coverage.published-regions",
            "settings.coverage.sources",
            "settings.coverage.extents",
        ] {
            XCTAssertTrue(element(identifier: identifier, in: app).exists, identifier)
        }
        XCTAssertFalse(element(identifier: "map.layers.coverage-shading", in: app).exists)
        app.buttons["Back"].tap()

        let mapAndData = app.buttons[rootIdentifiers[3]]
        assertSettingsRootRow(mapAndData, in: app)
        mapAndData.tap()
        XCTAssertTrue(app.staticTexts["Map & data"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["settings.downloads.allow-cellular"].exists)
        XCTAssertTrue(app.sliders["settings.pin-size"].exists)
        app.buttons["Back"].tap()

        let location = app.buttons[rootIdentifiers[4]]
        assertSettingsRootRow(location, in: app)
        location.tap()
        XCTAssertTrue(app.staticTexts["Location off"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings.location.open-system"].exists)
        app.buttons["Back"].tap()

        let diagnostics = app.buttons[rootIdentifiers[5]]
        assertSettingsRootRow(diagnostics, in: app)
        diagnostics.tap()
        XCTAssertTrue(
            element(identifier: "settings.diagnostics.window-status", in: app)
                .waitForExistence(timeout: 5)
        )
        app.buttons["Back"].tap()

        let replayWelcome = app.buttons[rootIdentifiers[6]]
        assertSettingsRootRow(replayWelcome, in: app)
        replayWelcome.tap()
        XCTAssertTrue(app.staticTexts["Interesting places around you"].waitForExistence(timeout: 5))
    }

    func testSettingsHubRendersEveryDestinationAtDefaultAndAccessibilityTextSizes() {
        for textSize in ["default", "ax"] {
            let app = launch(
                reset: true,
                locationDenied: true,
                accessibilityTextSize: textSize == "ax",
                resetTheme: true,
                theme: "snow"
            )
            XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 10), textSize)
            openExploreDoor(in: app)
            app.buttons["explore.row.settings"].tap()
            XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5), textSize)
            XCTAssertEqual(
                app.buttons["settings.group.appearance"].value as? String,
                "Snow selected. Four existing presets.",
                textSize
            )
            attachScreenshot(named: "settings-root-\(textSize)")
            assertSettingsRootRenderContract(
                in: app,
                accessibilityTextSize: textSize == "ax"
            )

            captureSettingsDestination(
                rowIdentifier: "settings.group.appearance",
                title: "Appearance",
                subtitle: "Choose how the map looks.",
                screenshotName: "settings-appearance-\(textSize)",
                accessibilityTextSize: textSize == "ax",
                minimumAXSubtitleHeight: 87,
                interactiveIdentifiers: [
                    "settings.theme.defined-paper",
                    "settings.theme.snow",
                    "settings.theme.street-contrast",
                    "settings.theme.verdant-kl",
                ],
                in: app
            )
            captureSettingsDestination(
                rowIdentifier: "settings.storage.manage",
                title: "Offline maps",
                screenshotName: "settings-offline-maps-\(textSize)",
                visibleIdentifiers: [
                    "offline-maps.zone.united-kingdom",
                ],
                in: app
            )
            captureSettingsDestination(
                rowIdentifier: "settings.group.coverage",
                title: "Coverage",
                subtitle: "Where published map data comes from and how far it reaches.",
                screenshotName: "settings-coverage-\(textSize)",
                accessibilityTextSize: textSize == "ax",
                minimumAXSubtitleHeight: 130,
                visibleIdentifiers: [
                    "settings.coverage.published-regions",
                    "settings.coverage.sources",
                    "settings.coverage.extents",
                ],
                in: app
            )
            captureSettingsDestination(
                rowIdentifier: "settings.group.map-data",
                title: "Map & data",
                subtitle: "Download policy and map pin sizing.",
                screenshotName: "settings-map-data-\(textSize)",
                accessibilityTextSize: textSize == "ax",
                minimumAXSubtitleHeight: 87,
                interactiveIdentifiers: [
                    "settings.downloads.allow-cellular",
                    "settings.pin-size",
                ],
                in: app
            )
            captureSettingsDestination(
                rowIdentifier: "settings.group.location",
                title: "Location",
                subtitle: "Permission status and the existing system settings action.",
                screenshotName: "settings-location-\(textSize)",
                accessibilityTextSize: textSize == "ax",
                minimumAXSubtitleHeight: 130,
                interactiveIdentifiers: ["settings.location.open-system"],
                in: app
            )
            captureSettingsDestination(
                rowIdentifier: "settings.diagnostics.export",
                title: "Diagnostics",
                screenshotName: "settings-diagnostics-\(textSize)",
                interactiveIdentifiers: ["settings.diagnostics.prepare"],
                visibleIdentifiers: ["settings.diagnostics.window-status"],
                in: app
            )

            let replayWelcome = app.buttons["settings.replay-onboarding"]
            XCTAssertTrue(scrollToHittable(replayWelcome, in: app), textSize)
            replayWelcome.tap()
            XCTAssertTrue(
                app.staticTexts["Interesting places around you"].waitForExistence(timeout: 5),
                textSize
            )
            attachScreenshot(named: "settings-replay-welcome-\(textSize)")
            let replayNext = app.buttons["onboarding.next"]
            XCTAssertTrue(scrollToFullyContained(replayNext, in: app), textSize)
            assertContainedInAppFrame(replayNext, in: app)
            app.terminate()
        }
    }

    func testPlaceCardPressInsetEvidenceDefault() {
        exercisePlaceCardPressInsetEvidence(accessibilityTextSize: false)
    }

    func testPlaceCardPressInsetEvidenceAX() {
        exercisePlaceCardPressInsetEvidence(accessibilityTextSize: true)
    }

    func testExploreRowPressSettingsDefaultEvidence() {
        exerciseExploreRowPressEvidence(kind: "settings", accessibility5: false)
    }

    func testExploreRowPressAboutDefaultEvidence() {
        exerciseExploreRowPressEvidence(kind: "about", accessibility5: false)
    }

    func testExploreRowPressSettingsAXEvidence() {
        exerciseExploreRowPressEvidence(kind: "settings", accessibility5: true)
    }

    func testExploreRowPressAboutAXEvidence() {
        exerciseExploreRowPressEvidence(kind: "about", accessibility5: true)
    }

    private func exerciseExploreRowPressEvidence(
        kind: String,
        accessibility5: Bool
    ) {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing-explore-row-press-fixture",
            kind,
            "-UIPreferredContentSizeCategoryName",
            accessibility5
                ? "UICTContentSizeCategoryAccessibilityXXXL"
                : "UICTContentSizeCategoryL",
        ]
        if accessibility5 {
            app.launchArguments.append("--ui-testing-explore-row-press-ax")
        }
        app.launch()

        let button = app.buttons["explore-row-press.fixture.button"]
        let kindMarker = element(identifier: "explore-row-press.fixture.kind", in: app)
        let sizeMarker = element(identifier: "explore-row-press.fixture.size", in: app)
        let prominenceMarker = element(identifier: "explore-row-press.fixture.prominence", in: app)
        let stateMarker = element(identifier: "explore-row-press.fixture.state", in: app)
        let icon = element(identifier: "explore-row-press.fixture.icon", in: app)
        let tapCount = app.staticTexts["explore-row-press.fixture.tap-count"]
        let edgeCount = app.staticTexts["explore-row-press.fixture.edge-count"]
        for target in [
            button,
            kindMarker,
            sizeMarker,
            prominenceMarker,
            stateMarker,
            icon,
            tapCount,
            edgeCount,
        ] {
            XCTAssertTrue(target.waitForExistence(timeout: 5))
            assertContainedInAppFrame(target, in: app)
        }
        XCTAssertTrue(button.isHittable)
        XCTAssertEqual(kindMarker.label, kind)
        XCTAssertEqual(sizeMarker.label, accessibility5 ? "ax" : "default")
        XCTAssertEqual(
            prominenceMarker.label,
            kind == "settings" ? "prominent" : "non-prominent"
        )
        XCTAssertEqual(stateMarker.label, "rest")
        XCTAssertEqual(edgeCount.label, "press-edges:0")

        let rowTop = stateMarker.frame.maxY + 24
        let rowFrame = CGRect(
            x: button.frame.minX,
            y: rowTop,
            width: button.frame.width,
            height: button.frame.maxY - rowTop
        )
        XCTAssertGreaterThanOrEqual(rowFrame.height, 44)
        XCTAssertTrue(app.frame.contains(rowFrame))

        let size = accessibility5 ? "ax" : "default"
        let artifactName = "explore-row-press-\(kind)-\(size)"
        let artifactDirectory = uiTestArtifactDirectory(for: artifactName)
        let coordinationRequest = artifactDirectory.appendingPathComponent(
            "\(artifactName)-sampler-coordinate"
        )
        let samplerReady = artifactDirectory.appendingPathComponent(
            "\(artifactName)-sampler-ready"
        )
        let measurementElements = [
            ("button", button),
            ("kind-marker", kindMarker),
            ("size-marker", sizeMarker),
            ("prominence-marker", prominenceMarker),
            ("state-marker", stateMarker),
            ("icon", icon),
            ("edge-count", edgeCount),
        ]
        let measurementNotes = [
            String(
                format: "app-frame: x=%.2f y=%.2f width=%.2f height=%.2f",
                app.frame.minX,
                app.frame.minY,
                app.frame.width,
                app.frame.height
            ),
            String(
                format: "row-derived: x=%.2f y=%.2f width=%.2f height=%.2f",
                rowFrame.minX,
                rowFrame.minY,
                rowFrame.width,
                rowFrame.height
            ),
            "evidence-class: Nondeterministic content",
            "pressed-state provenance: latched from live press edge",
            "interaction: 100 XCUIElement.tap() calls; press(forDuration:) intentionally excluded",
        ]
        exportMeasurements(
            named: artifactName,
            elements: measurementElements,
            notes: measurementNotes
        )

        if FileManager.default.fileExists(atPath: coordinationRequest.path) {
            XCTAssertTrue(
                waitForFile(at: samplerReady, timeout: 10),
                "Capture sampler did not acknowledge the exported resting frame."
            )
        }

        for _ in 0..<100 {
            button.tap()
        }

        let completed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND label == %@", "taps:100"),
            object: tapCount
        )
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 5), .completed)
        let latched = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "exists == true AND label == %@",
                "latched from live press edge"
            ),
            object: stateMarker
        )
        XCTAssertEqual(XCTWaiter.wait(for: [latched], timeout: 5), .completed)
        let edgeComponents = edgeCount.label.split(separator: ":", maxSplits: 1)
        XCTAssertEqual(edgeComponents.first, "press-edges")
        let observedLivePressEdges = Int(edgeComponents.last ?? "") ?? 0
        XCTAssertGreaterThanOrEqual(observedLivePressEdges, 1)
        exportMeasurements(
            named: artifactName,
            elements: measurementElements,
            notes: measurementNotes + [
                "observed-live-press-edges: \(observedLivePressEdges)"
            ]
        )
        app.terminate()
    }

    func testSettingsRootImplementationEvidenceCapturesDefaultAndAX5() {
        for evidenceCase in [
            (accessibilityTextSize: false, screenshotName: "t2.9-settings-root"),
            (accessibilityTextSize: true, screenshotName: "t2.9-settings-root-ax"),
        ] {
            let app = launch(
                reset: true,
                locationDenied: true,
                accessibilityTextSize: evidenceCase.accessibilityTextSize,
                resetTheme: true,
                theme: "snow"
            )
            XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 10))
            openExploreDoor(in: app)
            app.buttons["explore.row.settings"].tap()
            XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
            attachScreenshot(named: evidenceCase.screenshotName, forceExport: true)
            assertSettingsRootRenderContract(
                in: app,
                accessibilityTextSize: evidenceCase.accessibilityTextSize
            )
            app.terminate()
        }
    }

    func testSettingsStorageRowNavigatesToOfflineMaps() {
        let app = launch(reset: true)

        XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 10))

        openExploreDoor(in: app)
        app.buttons["explore.row.settings"].tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
        let storageRow = app.buttons["settings.storage.manage"]
        XCTAssertTrue(scrollToHittable(storageRow, in: app))
        storageRow.tap()

        XCTAssertTrue(app.staticTexts["Offline maps"].waitForExistence(timeout: 5))
    }

    func testDiagnosticsMatchesRuledReviewGuardrailsBeforePrepareInDarkAppearance() {
        // This asserts structural presence under a dark launch, not dark-color legibility.
        let app = launch(reset: true, forceDarkAppearance: true)
        XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 10))
        openExploreDoor(in: app)
        app.buttons["explore.row.settings"].tap()
        let diagnostics = app.buttons["settings.diagnostics.export"]
        XCTAssertTrue(scrollToHittable(diagnostics, in: app))
        diagnostics.tap()

        let windowStatus = app.descendants(matching: .any)["settings.diagnostics.window-status"]
        XCTAssertTrue(windowStatus.waitForExistence(timeout: 5))

        let included = app.descendants(matching: .any)["settings.diagnostics.included"]
        XCTAssertTrue(scrollToExistence(of: included, in: app))

        for title in [
            "App details", "Device type", "Steps in the app", "Downloaded maps",
            "Map file links", "Problems", "Load times", "Places and taps",
            "Device name", "Precise location", "Search text",
        ] {
            let disclosure = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label BEGINSWITH %@", title))
                .firstMatch
            XCTAssertTrue(scrollToExistence(of: disclosure, in: app), title)
        }

        let excluded = app.descendants(matching: .any)["settings.diagnostics.excluded"]
        XCTAssertTrue(scrollToExistence(of: excluded, in: app))

        let exclusion = app.staticTexts[
            "Your device name, exact location, and searches are not included in the export."
        ]
        XCTAssertTrue(scrollToExistence(of: exclusion, in: app))
        XCTAssertTrue(exclusion.isHittable)
        let prepare = app.buttons["settings.diagnostics.prepare"]
        XCTAssertTrue(prepare.exists)
        XCTAssertEqual(prepare.label, "Prepare file")
        attachScreenshot(named: "diagnostics-preprepare-exclusions-dark")
    }

    func testDiagnosticsAXXXLKeepsClassLabelsAndDropsSupportingBlurbs() {
        let app = launch(reset: true, accessibilityTextSize: true)
        XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 10))
        openExploreDoor(in: app)
        app.buttons["explore.row.settings"].tap()
        let diagnostics = app.buttons["settings.diagnostics.export"]
        XCTAssertTrue(scrollToHittable(diagnostics, in: app))
        diagnostics.tap()

        let windowOptionIdentifiers = [
            "settings.diagnostics.window.fifteen-minutes",
            "settings.diagnostics.window.last-hour",
            "settings.diagnostics.window.everything",
        ]
        for identifier in windowOptionIdentifiers {
            let option = app.buttons[identifier]
            XCTAssertTrue(option.waitForExistence(timeout: 5), identifier)
            XCTAssertGreaterThanOrEqual(option.frame.height, 44, identifier)
        }
        app.buttons[windowOptionIdentifiers[0]].tap()
        let windowStatus = app.descendants(matching: .any)["settings.diagnostics.window-status"]
        XCTAssertTrue(windowStatus.waitForExistence(timeout: 5))
        XCTAssertTrue(windowStatus.label.contains("Showing the last 15 minutes"), windowStatus.label)

        var disclosureLabelMinXs: [CGFloat] = []
        for (title, detail) in [
            ("App details", "App release and build number."),
            ("Device type", "Model and iOS version."),
            ("Steps in the app", "Screens opened and buttons used."),
            ("Downloaded maps", "Offline maps and their versions."),
            ("Map file links", "Making Tracks map file paths."),
            ("Problems", "Status codes and failure labels."),
            ("Load times", "Fetch and map drawing times."),
            ("Places and taps", "Places opened, saved, hidden, or marked seen."),
            ("Device name", "Your personal device label."),
            ("Precise location", "Your exact coordinates are not included."),
            ("Search text", "What you typed is omitted."),
        ] {
            let disclosure = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", title))
                .firstMatch
            XCTAssertTrue(scrollToExistence(of: disclosure, in: app), title)
            disclosureLabelMinXs.append(disclosure.frame.minX)
            XCTAssertEqual(
                app.descendants(matching: .any)
                    .matching(NSPredicate(format: "label CONTAINS %@", detail))
                    .count,
                0,
                detail
            )
        }
        XCTAssertLessThanOrEqual(
            (disclosureLabelMinXs.max() ?? 0) - (disclosureLabelMinXs.min() ?? 0),
            2,
            "AXXXL disclosure classes must collapse to one readable column."
        )
        attachScreenshot(named: "diagnostics-preprepare-axxxl")
    }

    func testDiagnosticsShareSheetDismissalKeepsPreparedArtifact() {
        let app = launch(reset: true)
        XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 10))
        openExploreDoor(in: app)
        app.buttons["explore.row.settings"].tap()
        let diagnostics = app.buttons["settings.diagnostics.export"]
        XCTAssertTrue(scrollToHittable(diagnostics, in: app))
        diagnostics.tap()

        let prepare = app.buttons["settings.diagnostics.prepare"]
        XCTAssertTrue(prepare.waitForExistence(timeout: 5))
        prepare.tap()
        let share = app.buttons["settings.diagnostics.share"]
        XCTAssertTrue(share.waitForExistence(timeout: 30))
        let windowPicker = app.descendants(matching: .any)["settings.diagnostics.window"]
        XCTAssertTrue(windowPicker.exists)
        XCTAssertFalse(windowPicker.isEnabled)
        XCTAssertFalse(app.descendants(matching: .any)["settings.diagnostics.included"].exists)
        let preview = app.descendants(matching: .any)["settings.diagnostics.preview"]
        XCTAssertTrue(scrollToExistence(of: preview, in: app))
        share.tap()

        let close = app.buttons["header.closeButton"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings.diagnostics.cancel"].exists)
    }

    func testMapHomeChromeHitTargetsAndThemeScreenshots() {
        let app = launch(reset: true, resetTheme: true, forceDarkAppearance: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMapTheme("defined-paper", in: app))

        let exploreDoor = app.buttons["map.door.explore"]
        let journalDoor = app.buttons["map.door.journal"]
        XCTAssertTrue(exploreDoor.waitForExistence(timeout: 5))
        XCTAssertTrue(journalDoor.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(exploreDoor.frame.width, 44)
        XCTAssertGreaterThanOrEqual(exploreDoor.frame.height, 44)
        XCTAssertGreaterThanOrEqual(journalDoor.frame.width, 44)
        XCTAssertGreaterThanOrEqual(journalDoor.frame.height, 44)
        XCTAssertGreaterThan(exploreDoor.frame.minY, map.frame.midY)
        XCTAssertGreaterThan(journalDoor.frame.minY, map.frame.midY)
        XCTAssertLessThan(exploreDoor.frame.maxX, journalDoor.frame.minX)
        attachScreenshot(named: "map-home-chrome-defined-paper")

        for themeID in ["snow", "street-contrast", "verdant-kl"] {
            selectMapTheme(themeID, in: app)
            attachScreenshot(named: "map-home-chrome-\(themeID)")
        }

        openScope(in: app)
        let historicBuildings = "explore.scope.category.historic_building"
        XCTAssertTrue(app.buttons[historicBuildings].waitForExistence(timeout: 5))
        tapCategoryChip(
            in: app,
            identifier: historicBuildings,
            expectedValue: "Not selected"
        )
        app.buttons["Close"].tap()
        openScope(in: app)
        XCTAssertTrue(waitForElementValue(
            "Not selected",
            identifier: historicBuildings,
            in: app
        ))
        app.buttons["Close"].tap()

        selectMapTheme("snow", in: app)

        XCTAssertTrue(map.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForMapTheme("snow", in: app))
        attachScreenshot(named: "map-home-chrome-snow-filtered")
    }

    func testAllScopeChoicesPersistAcrossRelaunch() {
        let coverageBBoxes = ["101.640,3.090,101.690,3.190"]
        let app = launch(reset: true, coverageBBoxes: coverageBBoxes)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))

        openScope(in: app)
        let showHidden = "explore.scope.include-hidden"
        let showSaved = "explore.scope.show-saved"
        let coverageShading = "explore.scope.coverage-shading"
        let historicBuildings = "explore.scope.category.historic_building"
        tapSwitch(in: app, identifier: showHidden, expectedValue: "1")
        tapSwitch(in: app, identifier: showSaved, expectedValue: "0")
        tapSwitch(in: app, identifier: coverageShading, expectedValue: "0")
        tapCategoryChip(
            in: app,
            identifier: historicBuildings,
            expectedValue: "Not selected"
        )
        app.buttons["Close"].tap()

        app.terminate()
        let relaunched = launch(reset: false, coverageBBoxes: coverageBBoxes)
        XCTAssertTrue(
            relaunched.otherElements["map.surface"].waitForExistence(timeout: 10)
        )
        openScope(in: relaunched)

        XCTAssertTrue(waitForElementValue(
            "1",
            identifier: showHidden,
            in: relaunched
        ))
        XCTAssertTrue(waitForElementValue(
            "0",
            identifier: showSaved,
            in: relaunched
        ))
        XCTAssertTrue(waitForElementValue(
            "0",
            identifier: coverageShading,
            in: relaunched
        ))
        XCTAssertTrue(waitForElementValue(
            "Not selected",
            identifier: historicBuildings,
            in: relaunched
        ))
        relaunched.buttons["Close"].tap()
    }

    func testPinSizeScreenshotsAcrossThemes() {
        let cases: [(theme: String, size: Double, screenshotName: String)] = [
            ("defined-paper", 0.8, "pin-defined-paper-min"),
            ("defined-paper", 1.2, "pin-defined-paper-default"),
            ("defined-paper", 1.6, "pin-defined-paper-max"),
            ("snow", 0.8, "pin-snow-min"),
            ("snow", 1.2, "pin-snow-default"),
            ("snow", 1.6, "pin-snow-max"),
        ]

        for testCase in cases {
            let app = launch(
                reset: true,
                resetTheme: true,
                theme: testCase.theme,
                pinSizeMultiplier: testCase.size,
                pinDiagnostics: true
            )
            XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 10), testCase.screenshotName)
            XCTAssertTrue(waitForMapToFinishLoading(in: app), testCase.screenshotName)
            XCTAssertFalse(app.otherElements["map.unavailable"].exists, testCase.screenshotName)
            XCTAssertTrue(waitForSourceFeatureCount(2, in: app), testCase.screenshotName)
            XCTAssertEqual(app.staticTexts["map.fixture-pin.\(placeID)"].label, "hit", testCase.screenshotName)
            XCTAssertEqual(app.staticTexts["map.debug-theme"].label, "theme:\(testCase.theme)", testCase.screenshotName)
            XCTAssertEqual(app.staticTexts["map.debug-pin-size"].label, "pin-size:\(pinSizeAccessibilityValue(for: testCase.size))", testCase.screenshotName)
            attachScreenshot(named: testCase.screenshotName)
            app.terminate()
        }
    }

    func testPinClusteringScreenshotsCompareCityAndStreetZoomDensity() {
        let cityApp = launch(reset: true, pinDiagnostics: true, densePins: true, startupViewport: "kl")
        XCTAssertTrue(cityApp.otherElements["map.surface"].waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMapToFinishLoading(in: cityApp))
        XCTAssertTrue(waitForSourceFeatureCount(24, in: cityApp))
        XCTAssertTrue(waitForClusterCount(atLeast: 1, in: cityApp))
        XCTAssertEqual(clusteredPlaceCount(in: cityApp), 24)
        let cluster = cityApp.buttons.matching(identifierPrefix: "map.cluster.").firstMatch
        attachScreenshot(named: "pin-clustering-city")
        cluster.tap()
        XCTAssertTrue(waitForClusterCount(0, in: cityApp))
        XCTAssertTrue(waitForHitProjectedFixturePinCount(atLeast: 4, in: cityApp))
        attachScreenshot(named: "pin-clustering-expanded")
        cityApp.terminate()

        let midApp = launch(reset: true, pinDiagnostics: true, densePins: true, startupViewport: "kl-mid")
        XCTAssertTrue(midApp.otherElements["map.surface"].waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMapToFinishLoading(in: midApp))
        XCTAssertTrue(waitForSourceFeatureCount(24, in: midApp))
        XCTAssertTrue(waitForProjectedFixturePinCount(24, in: midApp))
        XCTAssertTrue(waitForClusterCount(0, in: midApp))
        XCTAssertTrue(waitForHitProjectedFixturePinCount(atLeast: 24, in: midApp))
        attachScreenshot(named: "pin-clustering-mid")
        midApp.terminate()

        let streetApp = launch(reset: true, pinDiagnostics: true, densePins: true, startupViewport: "kl-street")
        XCTAssertTrue(streetApp.otherElements["map.surface"].waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMapToFinishLoading(in: streetApp))
        XCTAssertTrue(waitForSourceFeatureCount(24, in: streetApp))
        XCTAssertTrue(waitForProjectedFixturePinCount(24, in: streetApp))
        XCTAssertTrue(waitForClusterCount(0, in: streetApp))
        attachScreenshot(named: "pin-clustering-street")
        streetApp.terminate()
    }

    func testDenseClusterLayerRendersVisibleBubbleAtCityZoom() {
        let app = launch(
            reset: true,
            resetTheme: true,
            theme: "snow",
            pinDiagnostics: true,
            densePins: true,
            startupViewport: "kl"
        )
        XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMapToFinishLoading(in: app))
        XCTAssertTrue(waitForSourceFeatureCount(24, in: app))
        XCTAssertTrue(waitForClusterCount(atLeast: 1, in: app))
        XCTAssertEqual(clusteredPlaceCount(in: app), 24)
        XCTAssertTrue(waitForClusterPinPixels(in: app))
    }

    func testCoverageEdgeScreenshotsAcrossThemes() {
        let coverageBBox = "101.640,3.090,101.690,3.190"
        let diagnosticApp = launch(
            reset: true,
            resetTheme: true,
            theme: "defined-paper",
            pinDiagnostics: true,
            coverageBBoxes: [coverageBBox]
        )
        XCTAssertTrue(diagnosticApp.otherElements["map.surface"].waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMapToFinishLoading(in: diagnosticApp))
        XCTAssertEqual(diagnosticApp.staticTexts["map.debug-coverage"].label, "coverage-bboxes:1")

        for themeID in ["defined-paper", "snow", "street-contrast", "verdant-kl"] {
            let app = launch(
                reset: true,
                resetTheme: true,
                theme: themeID,
                coverageBBoxes: [coverageBBox]
            )
            XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 10), themeID)
            XCTAssertTrue(waitForMapTheme(themeID, in: app), themeID)
            attachScreenshot(named: "coverage-edge-\(themeID)")
        }
    }

    func testPinSizeSliderUpdatesLiveMapLayers() {
        let app = launch(
            reset: true,
            pinSizeMultiplier: 0.8,
            pinDiagnostics: true
        )
        XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMapToFinishLoading(in: app))
        XCTAssertTrue(waitForSourceFeatureCount(2, in: app))

        XCTAssertEqual(
            app.staticTexts["map.debug-pin-layer-size"].label,
            "pin-layer-size:80% circle:true icon:true bookmark:true heart:true"
        )

        openExploreDoor(in: app)
        app.buttons["explore.row.settings"].tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
        let mapAndData = app.buttons["settings.group.map-data"]
        XCTAssertTrue(scrollToHittable(mapAndData, in: app))
        mapAndData.tap()
        XCTAssertTrue(app.staticTexts["Map & data"].waitForExistence(timeout: 5))
        let slider = app.sliders["settings.pin-size"]
        XCTAssertTrue(scrollToHittable(slider, in: app))
        adjustSliderToTrueEdge(slider, in: app, identifier: "settings.pin-size", expectedValue: "160%")
        app.buttons["Close"].tap()

        let liveLayerSize = app.staticTexts["map.debug-pin-layer-size"]
        XCTAssertTrue(liveLayerSize.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForPinLayerSize(160, in: app))
        XCTAssertEqual(
            app.staticTexts["map.debug-pin-layer-size"].label,
            "pin-layer-size:160% circle:true icon:true bookmark:true heart:true"
        )
    }

    func testPlaceCardKeepsFixedActionSlotsReachableAtAccessibilityTextSize() {
        let app = launch(reset: true, accessibilityTextSize: true, pinDiagnostics: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMapToFinishLoading(in: app))

        let openFixture = app.buttons["debug.open-fixture"]
        XCTAssertTrue(openFixture.waitForExistence(timeout: 5))
        openFixture.tap()
        XCTAssertTrue(app.staticTexts["Ghost Sign"].waitForExistence(timeout: 5))

        let actionBar = app.otherElements["place-card.action-bar"]
        XCTAssertTrue(actionBar.waitForExistence(timeout: 5))
        let saveButton = actionBar.buttons["place-card.save"]
        let visitedButton = actionBar.buttons["place-card.visited"]
        let hideButton = actionBar.buttons["place-card.hide"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        XCTAssertTrue(visitedButton.waitForExistence(timeout: 5))
        XCTAssertTrue(hideButton.waitForExistence(timeout: 5))
        XCTAssertEqual(actionBar.buttons.count, 3)
        attachScreenshot(named: "place-card-a11y")
        assertVerticalActionStack([saveButton, visitedButton, hideButton], in: app)

        visitedButton.tap()
        let lovedButton = actionBar.buttons["place-card.loved"]
        let unseeButton = actionBar.buttons["place-card.unsee"]
        XCTAssertTrue(lovedButton.waitForExistence(timeout: 5))
        XCTAssertTrue(unseeButton.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForButtonLabel("Love", identifier: "place-card.loved", in: app))
        XCTAssertTrue(waitForButtonLabel("Seen", identifier: "place-card.unsee", in: app))
        XCTAssertTrue(waitForButtonEnabled(true, identifier: "place-card.unsee", in: app))
        XCTAssertTrue(actionBar.buttons["place-card.hide"].waitForExistence(timeout: 5))
        XCTAssertEqual(actionBar.buttons.count, 4)
        assertVerticalActionStack([saveButton, lovedButton, unseeButton, hideButton], in: app)

        lovedButton.tap()
        XCTAssertEqual(actionBar.buttons.count, 4)
        XCTAssertTrue(waitForButtonLabel("Loved", identifier: "place-card.loved", in: app))
        XCTAssertTrue(waitForButtonEnabled(false, identifier: "place-card.unsee", in: app))
        XCTAssertTrue(actionBar.buttons["place-card.hide"].exists)
        assertVerticalActionStack([saveButton, lovedButton, unseeButton, hideButton], in: app)
    }

    func testPlaceCardStateMorphologyRenderMatrix() {
        let configurations = [
            (name: "unsaved", saved: false, hidden: false, accessibilityTextSize: false),
            (name: "saved", saved: true, hidden: false, accessibilityTextSize: false),
            (name: "hidden", saved: false, hidden: true, accessibilityTextSize: false),
            (name: "unsaved", saved: false, hidden: false, accessibilityTextSize: true),
            (name: "saved", saved: true, hidden: false, accessibilityTextSize: true),
            (name: "hidden", saved: false, hidden: true, accessibilityTextSize: true),
        ]
        let states: [(name: String, action: String?)] = [
            (name: "unseen", action: nil),
            (name: "seen", action: "place-card.visited"),
            (name: "loved", action: "place-card.loved"),
        ]

        for configuration in configurations {
            let app = launch(
                reset: true,
                accessibilityTextSize: configuration.accessibilityTextSize,
                seedUserList: configuration.saved
            )
            let map = app.otherElements["map.surface"]
            XCTAssertTrue(map.waitForExistence(timeout: 10))
            if configuration.hidden {
                app.buttons["debug.hide-fixture"].tap()
                XCTAssertTrue(waitForFixtureHidden(true, in: app))
                openScope(in: app)
                let showHidden = "explore.scope.include-hidden"
                XCTAssertTrue(app.switches[showHidden].waitForExistence(timeout: 5))
                tapSwitch(in: app, identifier: showHidden, expectedValue: "1")
                app.buttons["Close"].tap()
            }
            openFixtureCard(
                in: map,
                app: app,
                expectedHidden: configuration.hidden
            )

            let sheet = app.scrollViews.matching(
                identifierPrefix: "place-card.instance."
            ).firstMatch
            XCTAssertTrue(sheet.waitForExistence(timeout: 5))
            if !configuration.accessibilityTextSize {
                XCTAssertTrue(expandPlaceCardSheet(in: app))
            }

            let actionBar = app.otherElements["place-card.action-bar"]
            XCTAssertTrue(actionBar.waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["place-card.more"].exists)
            XCTAssertEqual(app.buttons["place-card.more"].label, "More")

            for state in states {
                if let action = state.action {
                    let transitionButton = actionBar.buttons[action]
                    XCTAssertTrue(transitionButton.waitForExistence(timeout: 5))
                    transitionButton.tap()
                }

                let saveButton = actionBar.buttons["place-card.save"]
                XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
                XCTAssertTrue(waitForButtonLabel(
                    configuration.saved ? "Saved" : "Save",
                    identifier: "place-card.save",
                    in: app
                ))

                let stateButtons: [XCUIElement]
                switch state.name {
                case "unseen":
                    let seenButton = actionBar.buttons["place-card.visited"]
                    XCTAssertTrue(seenButton.waitForExistence(timeout: 5))
                    XCTAssertTrue(waitForButtonLabel(
                        "Seen",
                        identifier: "place-card.visited",
                        in: app
                    ))
                    XCTAssertFalse(actionBar.buttons["place-card.loved"].exists)
                    XCTAssertFalse(actionBar.buttons["place-card.unsee"].exists)
                    stateButtons = [saveButton, seenButton]
                case "seen":
                    let lovedButton = actionBar.buttons["place-card.loved"]
                    let seenButton = actionBar.buttons["place-card.unsee"]
                    XCTAssertTrue(lovedButton.waitForExistence(timeout: 5))
                    XCTAssertTrue(seenButton.waitForExistence(timeout: 5))
                    XCTAssertTrue(waitForButtonLabel(
                        "Love",
                        identifier: "place-card.loved",
                        in: app
                    ))
                    XCTAssertTrue(waitForButtonLabel(
                        "Seen",
                        identifier: "place-card.unsee",
                        in: app
                    ))
                    XCTAssertFalse(actionBar.buttons["place-card.visited"].exists)
                    XCTAssertTrue(seenButton.isEnabled)
                    stateButtons = [saveButton, lovedButton, seenButton]
                case "loved":
                    let lovedButton = actionBar.buttons["place-card.loved"]
                    let seenButton = actionBar.buttons["place-card.unsee"]
                    XCTAssertTrue(lovedButton.waitForExistence(timeout: 5))
                    XCTAssertTrue(seenButton.waitForExistence(timeout: 5))
                    XCTAssertTrue(waitForButtonLabel(
                        "Loved",
                        identifier: "place-card.loved",
                        in: app
                    ))
                    XCTAssertTrue(waitForButtonLabel(
                        "Seen",
                        identifier: "place-card.unsee",
                        in: app
                    ))
                    XCTAssertFalse(actionBar.buttons["place-card.visited"].exists)
                    XCTAssertFalse(seenButton.isEnabled)
                    stateButtons = [saveButton, lovedButton, seenButton]
                default:
                    XCTFail("Unexpected place-card state \(state.name)")
                    stateButtons = [saveButton]
                }

                let hideButton = actionBar.buttons["place-card.hide"]
                let unhideButton = actionBar.buttons["place-card.unhide"]
                let visibleButtons: [XCUIElement]
                if configuration.hidden {
                    XCTAssertFalse(hideButton.exists)
                    XCTAssertTrue(unhideButton.waitForExistence(timeout: 5))
                    XCTAssertEqual(unhideButton.label, "Unhide")
                    visibleButtons = stateButtons + [unhideButton]
                } else if configuration.saved {
                    XCTAssertFalse(hideButton.exists)
                    XCTAssertFalse(unhideButton.exists)
                    visibleButtons = stateButtons
                } else {
                    XCTAssertFalse(unhideButton.exists)
                    XCTAssertTrue(hideButton.waitForExistence(timeout: 5))
                    XCTAssertEqual(hideButton.label, "Hide")
                    visibleButtons = stateButtons + [hideButton]
                }
                XCTAssertEqual(actionBar.buttons.count, visibleButtons.count)

                if configuration.accessibilityTextSize {
                    assertVerticalActionStack(visibleButtons, in: app)
                } else {
                    for (leading, trailing) in zip(
                        visibleButtons,
                        visibleButtons.dropFirst()
                    ) {
                        assertHorizontallyOrdered(leading, trailing)
                        assertNoFrameIntersection(leading, trailing)
                    }
                }

                let name = [
                    "place-card-r15",
                    configuration.accessibilityTextSize ? "ax" : "default",
                    configuration.name,
                    state.name,
                ].joined(separator: "-")
                attachScreenshot(named: name, forceExport: true)
            }

            app.terminate()
        }
    }

    func testPlaceCardSavedLovedStateRetainsOpaqueSeenFact() {
        for accessibilityTextSize in [false, true] {
            let app = launch(
                reset: true,
                accessibilityTextSize: accessibilityTextSize,
                seedUserList: true
            )
            let map = app.otherElements["map.surface"]
            XCTAssertTrue(map.waitForExistence(timeout: 10))
            openFixtureCard(in: map, app: app)

            let sheet = app.scrollViews.matching(
                identifierPrefix: "place-card.instance."
            ).firstMatch
            XCTAssertTrue(sheet.waitForExistence(timeout: 5))
            if !accessibilityTextSize {
                XCTAssertTrue(expandPlaceCardSheet(in: app))
            }

            let actionBar = app.otherElements["place-card.action-bar"]
            XCTAssertTrue(actionBar.waitForExistence(timeout: 5))
            let saveButton = actionBar.buttons["place-card.save"]
            XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
            XCTAssertEqual(saveButton.label, "Saved")

            let visitedButton = actionBar.buttons["place-card.visited"]
            XCTAssertTrue(visitedButton.waitForExistence(timeout: 5))
            visitedButton.tap()

            let lovedButton = actionBar.buttons["place-card.loved"]
            XCTAssertTrue(lovedButton.waitForExistence(timeout: 5))
            XCTAssertEqual(lovedButton.label, "Love")
            lovedButton.tap()

            XCTAssertTrue(waitForButtonLabel(
                "Loved",
                identifier: "place-card.loved",
                in: app
            ))
            let seenButton = actionBar.buttons["place-card.unsee"]
            XCTAssertTrue(seenButton.waitForExistence(timeout: 5))
            XCTAssertEqual(seenButton.label, "Seen")
            XCTAssertFalse(seenButton.isEnabled)

            let visibleButtons = [saveButton, lovedButton, seenButton]
            for button in visibleButtons {
                assertMinimumInteractiveTarget(button)
            }
            if accessibilityTextSize {
                assertVerticalActionStack(visibleButtons, in: app)
                for (upper, lower) in zip(
                    visibleButtons,
                    visibleButtons.dropFirst()
                ) {
                    XCTAssertEqual(
                        lower.frame.minY - upper.frame.maxY,
                        8,
                        accuracy: 1
                    )
                }
            } else {
                for (leading, trailing) in zip(
                    visibleButtons,
                    visibleButtons.dropFirst()
                ) {
                    assertHorizontallyOrdered(leading, trailing)
                    assertNoFrameIntersection(leading, trailing)
                    XCTAssertEqual(
                        trailing.frame.minX - leading.frame.maxX,
                        8,
                        accuracy: 1
                    )
                }
            }

            let appFrame = app.windows.firstMatch.exists
                ? app.windows.firstMatch.frame
                : app.frame
            XCTAssertEqual(appFrame.width, 402, accuracy: 0.5)
            XCTAssertEqual(appFrame.height, 874, accuracy: 0.5)

            let name = [
                "place-card-r15",
                accessibilityTextSize ? "ax" : "default",
                "saved",
                "loved",
            ].joined(separator: "-")
            let screenshot = attachScreenshot(
                named: name,
                forceExport: true
            )
            guard let raster = RenderedPixelRaster(
                screenshot: screenshot,
                appFrame: appFrame
            ) else {
                XCTFail("Could not decode saved+loved state render")
                app.terminate()
                continue
            }
            let accentCoverage = raster.tokenCoverage(
                RenderedRGB(10, 107, 92),
                in: seenButton.frame
            )
            XCTAssertGreaterThan(
                accentCoverage,
                0.4,
                "Disabled Seen must preserve its opaque accent fact fill"
            )
            print(
                "PLACE_CARD_R15_METRICS mode=\(accessibilityTextSize ? "ax" : "default") "
                    + "frames=\(visibleButtons.map(\.frame)) "
                    + "seenAccentCoverage=\(accentCoverage)"
            )

            app.terminate()
        }
    }

    func testLocateMeChromeExplainsWhenLocationIsDeniedAtAX5() throws {
        let app = launch(
            reset: true,
            locationDenied: true,
            accessibilityTextSize: true
        )

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))

        XCTAssertEqual(app.buttons["map.locate-me"].label, "Locate me")
        XCTAssertTrue(app.staticTexts["Location is off"].waitForExistence(timeout: 5))
        let locationSettings = app.buttons["map.location-settings"]
        XCTAssertTrue(locationSettings.waitForExistence(timeout: 5))
        XCTAssertEqual(locationSettings.label, "Settings")
        XCTAssertTrue(locationSettings.isHittable)
        assertMinimumInteractiveTarget(locationSettings)
        assertContainedInAppFrame(locationSettings, in: app)
        attachScreenshot(named: "map-location-off")
        locationSettings.tap()
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
    }

    func testLocateMeShowsNearbyPromptForFixturePlaceAtAX5() {
        let app = launch(
            reset: true,
            simulatedLocationAuthorization: true,
            simulatedLatitude: 3.1402,
            simulatedLongitude: 101.6902,
            accessibilityTextSize: true
        )

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))

        app.buttons["map.locate-me"].tap()

        let nearbyPrompt = app.otherElements["map.nearby-prompt"]
        XCTAssertTrue(nearbyPrompt.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["You're near Ghost Sign — seen it?"].waitForExistence(timeout: 5))
        attachScreenshot(named: "nearby-prompt")

        let seenButton = app.buttons["map.nearby-prompt.seen"]
        let dismissButton = app.buttons["map.nearby-prompt.dismiss"]
        XCTAssertTrue(seenButton.waitForExistence(timeout: 5))
        XCTAssertTrue(dismissButton.waitForExistence(timeout: 5))
        XCTAssertEqual(seenButton.label, "Seen it")
        XCTAssertEqual(dismissButton.label, "Dismiss nearby prompt")
        XCTAssertTrue(seenButton.isHittable)
        XCTAssertTrue(dismissButton.isHittable)
        assertMinimumInteractiveTarget(seenButton)
        assertMinimumInteractiveTarget(dismissButton)
        assertContainedInAppFrame(seenButton, in: app)
        assertContainedInAppFrame(dismissButton, in: app)
        assertNoFrameIntersection(seenButton, dismissButton)
        seenButton.tap()

        XCTAssertFalse(nearbyPrompt.waitForExistence(timeout: 2))
        XCTAssertEqual(app.staticTexts["tracks.visit-count.\(placeID)"].label, "Tracks visits: 1")
    }

    func testNearbyPromptDismissSuppressesPrompt() {
        let app = launch(
            reset: true,
            simulatedLocationAuthorization: true,
            simulatedLatitude: 3.1402,
            simulatedLongitude: 101.6902
        )

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))

        app.buttons["map.locate-me"].tap()

        let nearbyPrompt = app.otherElements["map.nearby-prompt"]
        XCTAssertTrue(nearbyPrompt.waitForExistence(timeout: 5))
        app.buttons["map.nearby-prompt.dismiss"].tap()

        XCTAssertTrue(confirmPromptRemainsAbsent("map.nearby-prompt", in: app, timeout: 2))
        XCTAssertEqual(app.staticTexts["tracks.visit-count.\(placeID)"].label, "Tracks visits: 0")
    }

    func testCardVisitStateSuppressesNearbyPromptWithoutViewportRefresh() {
        let app = launch(
            reset: true,
            simulatedLocationAuthorization: true,
            simulatedLatitude: 3.1402,
            simulatedLongitude: 101.6902,
            pinDiagnostics: true,
            startupViewport: "kl-street"
        )

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMapToFinishLoading(in: app))

        app.buttons["map.locate-me"].tap()

        let nearbyPrompt = app.otherElements["map.nearby-prompt"]
        XCTAssertTrue(nearbyPrompt.waitForExistence(timeout: 5))

        XCTAssertTrue(activateFixturePin(
            in: map,
            app: app,
            placeID: placeID,
            title: "Ghost Sign",
            expectedLabel: "Ghost Sign, Attraction, not visited"
        ))
        XCTAssertTrue(app.staticTexts["Ghost Sign"].waitForExistence(timeout: 5))
        app.buttons["place-card.visited"].tap()
        closePlaceCard(in: app)

        XCTAssertTrue(confirmPromptRemainsAbsent("map.nearby-prompt", in: app, timeout: 2))
        XCTAssertEqual(app.staticTexts["tracks.visit-count.\(placeID)"].label, "Tracks visits: 1")
    }

    func testLocateMePromptsForNearbyPinWithAllDenseTiersVisible() {
        let app = launch(
            reset: true,
            simulatedLocationAuthorization: true,
            simulatedLatitude: 3.1400,
            simulatedLongitude: 101.6980,
            pinDiagnostics: true,
            densePins: true,
            startupViewport: "kl"
        )

        XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMapToFinishLoading(in: app))
        XCTAssertTrue(waitForSourceFeatureCount(24, in: app))
        XCTAssertTrue(app.staticTexts["map.fixture-pin.mt1_D000000000000000000000000H"].exists)

        app.buttons["map.locate-me"].tap()

        let nearbyPrompt = app.otherElements["map.nearby-prompt"]
        XCTAssertTrue(nearbyPrompt.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["You're near Dense Pin 17 — seen it?"].waitForExistence(timeout: 5))

        let seenButton = app.buttons["map.nearby-prompt.seen"]
        XCTAssertTrue(seenButton.waitForExistence(timeout: 5))
        seenButton.tap()

        XCTAssertFalse(nearbyPrompt.waitForExistence(timeout: 2))
    }

    func testCreditsStayGroupedAtAccessibilityTextSize() throws {
        let app = launch(reset: true, accessibilityTextSize: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))

        openExploreDoor(in: app)
        app.buttons["explore.row.about"].tap()
        XCTAssertTrue(app.staticTexts["About"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["The map is fresh snow."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Private by construction"].exists)
        attachScreenshot(named: "t2.10-about-ax", forceExport: true)
        XCTAssertEqual(try buildCommitLabel(in: app), "Build \(try currentGitCommit())")
        let privacyPolicy = element(identifier: "about.privacy-policy", in: app)
        XCTAssertTrue(scrollToFullyContained(privacyPolicy, in: app, maxSwipes: 10))
        assertMinimumInteractiveTarget(privacyPolicy)
        assertContainedInAppFrame(privacyPolicy, in: app)

        let softwareLicences = app.buttons["about.software-licences"]
        let dataLicences = app.buttons["about.data-licences"]
        XCTAssertTrue(scrollToHittable(softwareLicences, in: app))
        assertMinimumInteractiveTarget(softwareLicences)
        XCTAssertTrue(scrollToHittable(dataLicences, in: app))
        assertMinimumInteractiveTarget(dataLicences)
        assertNoFrameIntersection(softwareLicences, dataLicences)

        XCTAssertTrue(scrollToHittable(softwareLicences, in: app))
        softwareLicences.tap()
        XCTAssertTrue(app.staticTexts["Software licences"].waitForExistence(timeout: 5))
        attachScreenshot(named: "t2.10-software-licences-ax", forceExport: true)
        let softwareIDs = [
            "GRDB.swift|7.11.1",
            "MapLibre Native iOS / maplibre-gl-native-distribution|6.27.0",
            "Newsreader|productiontype/Newsreader commit cfcb4f7af0e52c25e8df2a2431814c8e5fe2e155; static TTF instances",
            "Noto Sans glyph PBF mirror|protomaps/basemaps-assets commit 028c18f713baecad011301ff7a69acc39bcc2ae7; Noto Sans Regular",
        ]
        let lastLicense = element(identifier: "credits.oss.\(softwareIDs.last!).license", in: app)
        XCTAssertTrue(lastLicense.exists)
        XCTAssertFalse(lastLicense.isHittable, "The AX endpoint must begin off-screen")
        for id in softwareIDs {
            let license = element(identifier: "credits.oss.\(id).license", in: app)
            XCTAssertTrue(scrollToFullyContained(license, in: app, maxSwipes: 120))
            assertMinimumInteractiveTarget(license)
            assertContainedInAppFrame(license, in: app)
        }

        app.buttons["Back"].tap()
        XCTAssertTrue(scrollToHittable(dataLicences, in: app))
        dataLicences.tap()
        XCTAssertTrue(app.staticTexts["Data licences"].waitForExistence(timeout: 5))
        attachScreenshot(named: "t2.10-data-licences-ax", forceExport: true)
        let osmCopyright = element(identifier: "about.openstreetmap-copyright", in: app)
        XCTAssertTrue(scrollToFullyContained(osmCopyright, in: app, maxSwipes: 10))
        assertMinimumInteractiveTarget(osmCopyright)
        assertContainedInAppFrame(osmCopyright, in: app)
        let runtimeAttribution = element(identifier: "credits.manifest.osm", in: app)
        XCTAssertTrue(scrollToFullyContained(runtimeAttribution, in: app, maxSwipes: 10))
        XCTAssertTrue(runtimeAttribution.label.contains("ODbL-1.0"))
    }

    private func captureSnowSettingsThemeLock(
        forceDarkAppearance: Bool,
        disableMaterialModeLock: Bool = false,
        appearanceName: String,
        appearanceTarget: SettingsAppearanceTarget? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> SettingsThemeLockCapture? {
        let injectedColorScheme = forceDarkAppearance ? "dark" : "light"

        let app = launch(
            reset: true,
            locationDenied: true,
            resetTheme: true,
            theme: "snow",
            forceDarkAppearance: false,
            disableMaterialModeLock: disableMaterialModeLock,
            uiTestingColorScheme: injectedColorScheme,
            forceTileNetworkOffline: true,
            hideFixtureChrome: true
        )
        guard app.otherElements["map.surface"].waitForExistence(timeout: 10) else {
            XCTFail("Snow theme-lock \(appearanceName): map did not launch", file: file, line: line)
            return nil
        }
        openExploreDoor(in: app)
        app.buttons["explore.row.settings"].tap()
        guard app.staticTexts["Settings"].waitForExistence(timeout: 5) else {
            XCTFail("Snow theme-lock \(appearanceName): Settings did not open", file: file, line: line)
            return nil
        }

        let expectedGroupIdentifiers = [
            "settings.group.appearance",
            "settings.storage.manage",
            "settings.group.coverage",
            "settings.group.map-data",
            "settings.group.location",
            "settings.diagnostics.export",
            "settings.replay-onboarding",
        ]
        let groupContainer = app.otherElements["settings.groups"]
        guard groupContainer.waitForExistence(timeout: 5) else {
            XCTFail(
                "Snow theme-lock \(appearanceName): Settings group classification boundary is missing",
                file: file,
                line: line
            )
            return nil
        }
        XCTAssertEqual(
            groupContainer.buttons.allElementsBoundByIndex.map(\.identifier),
            expectedGroupIdentifiers,
            "Every SettingsGroup.allCases row must be classified by the appearance oracle",
            file: file,
            line: line
        )

        let appFrame = app.windows.firstMatch.exists ? app.windows.firstMatch.frame : app.frame
        var regions: [String: SettingsThemeLockRegionCapture] = [:]

        func capture(
            name: String,
            comparisonElements: [XCUIElement],
            primaryInk: XCUIElement? = nil,
            secondaryInk: XCUIElement? = nil,
            exportsFrozenEvidence: Bool = false
        ) -> Bool {
            let requiredElements = comparisonElements
                + (primaryInk.map { [$0] } ?? [])
                + (secondaryInk.map { [$0] } ?? [])
            guard requiredElements.allSatisfy({ $0.waitForExistence(timeout: 5) }) else {
                XCTFail(
                    "Snow theme-lock \(appearanceName) \(name): a rendered target is missing",
                    file: file,
                    line: line
                )
                return false
            }
            let comparisonFrame = comparisonElements
                .map(\.frame)
                .reduce(CGRect.null) { $0.union($1) }
                .insetBy(dx: -4, dy: -4)
                .intersection(appFrame)
            guard !comparisonFrame.isNull,
                  comparisonFrame.width > 0,
                  comparisonFrame.height > 0
            else {
                XCTFail(
                    "Snow theme-lock \(appearanceName) \(name): comparison frame is empty",
                    file: file,
                    line: line
                )
                return false
            }

            let screenshot: XCUIScreenshot
            let raster: RenderedPixelRaster
            if name == "appearance", let appearanceTarget {
                var observedScreenshot: XCUIScreenshot?
                var observedRaster: RenderedPixelRaster?

                func sampleDifference(
                    comparedTo baseline: SettingsThemeLockRegionCapture
                ) -> Int? {
                    let candidateScreenshot = XCUIScreen.main.screenshot()
                    guard let candidateRaster = RenderedPixelRaster(
                        screenshot: candidateScreenshot,
                        appFrame: appFrame
                    ) else {
                        return nil
                    }
                    observedScreenshot = candidateScreenshot
                    observedRaster = candidateRaster
                    return candidateRaster.differingPixelCount(
                        comparedTo: baseline.raster,
                        in: comparisonFrame,
                        tolerance: 0
                    )
                }

                let transition: RenderedDifferenceMatch
                let failurePrefix: String
                switch appearanceTarget {
                case .matches(let baseline):
                    transition = RenderedDifferenceWaiter.wait(
                        atMost: 0,
                        attempts: 40,
                        interval: 0.25,
                        sample: { sampleDifference(comparedTo: baseline) }
                    )
                    failurePrefix = "legacy Light appearance target was not observed within 40 samples; expected 0 differing pixels"
                case .differs(let baseline):
                    // The smallest known-good legacy-Dark delta is 4,242 pixels; 100 stays
                    // comfortably below a real transition while excluding raster noise.
                    transition = RenderedDifferenceWaiter.wait(
                        exceeding: 100,
                        attempts: 40,
                        interval: 0.25,
                        sample: { sampleDifference(comparedTo: baseline) }
                    )
                    failurePrefix = "legacy Dark INJECTED appearance transition was not observed within 40 samples; expected >100 differing pixels"
                }
                guard transition.matched,
                      let observedScreenshot,
                      let observedRaster
                else {
                    let lastObserved = transition.observed.map(String.init) ?? "nil"
                    XCTFail(
                        "\(failurePrefix), last observed \(lastObserved)",
                        file: file,
                        line: line
                    )
                    return false
                }
                screenshot = observedScreenshot
                raster = observedRaster
                if exportsFrozenEvidence {
                    attachScreenshot(
                        screenshot,
                        named: "snow-theme-lock-\(name)-\(appearanceName)",
                        forceExport: true
                    )
                }
            } else {
                screenshot = exportsFrozenEvidence
                    ? attachScreenshot(
                        named: "snow-theme-lock-\(name)-\(appearanceName)",
                        forceExport: true
                    )
                    : XCUIScreen.main.screenshot()
                guard let decodedRaster = RenderedPixelRaster(
                    screenshot: screenshot,
                    appFrame: appFrame
                ) else {
                    XCTFail(
                        "Snow theme-lock \(appearanceName) \(name): screenshot could not be decoded",
                        file: file,
                        line: line
                    )
                    return false
                }
                raster = decodedRaster
            }
            regions[name] = SettingsThemeLockRegionCapture(
                raster: raster,
                comparisonFrame: comparisonFrame,
                primaryInkFrame: primaryInk?.frame,
                secondaryInkFrame: secondaryInk?.frame
            )
            return true
        }

        let appearanceRow = app.buttons["settings.group.appearance"]
        guard scrollSettingsRowToHittable(appearanceRow, in: app) else {
            XCTFail("Snow theme-lock \(appearanceName): Appearance row is not hittable", file: file, line: line)
            return nil
        }
        appearanceRow.tap()
        let themeRows = ["snow", "defined-paper", "street-contrast", "verdant-kl"].map {
            app.buttons["settings.theme.\($0)"]
        }
        guard capture(
            name: "appearance",
            comparisonElements: themeRows,
            primaryInk: app.staticTexts["Street Contrast"],
            secondaryInk: app.staticTexts["street-contrast"],
            exportsFrozenEvidence: true
        ) else { return nil }
        app.buttons["Back"].tap()
        guard app.staticTexts["Settings"].waitForExistence(timeout: 5) else { return nil }

        let offlineMapsRow = app.buttons["settings.storage.manage"]
        guard scrollSettingsRowToHittable(offlineMapsRow, in: app) else {
            XCTFail("Snow theme-lock \(appearanceName): Offline maps row is not hittable", file: file, line: line)
            return nil
        }
        offlineMapsRow.tap()
        let offlineMapsStorage = element(identifier: "offline-maps.storage.unavailable", in: app)
        guard capture(
            name: "offline-maps",
            comparisonElements: [offlineMapsStorage]
        ) else { return nil }
        app.buttons["Back"].tap()
        guard app.staticTexts["Settings"].waitForExistence(timeout: 5) else { return nil }

        let coverageRow = app.buttons["settings.group.coverage"]
        guard scrollSettingsRowToHittable(coverageRow, in: app) else {
            XCTFail("Snow theme-lock \(appearanceName): Coverage row is not hittable", file: file, line: line)
            return nil
        }
        coverageRow.tap()
        let coverageElements = [
            "settings.coverage.published-regions",
            "settings.coverage.sources",
            "settings.coverage.extents",
        ].map { element(identifier: $0, in: app) }
        guard capture(
            name: "coverage",
            comparisonElements: coverageElements
        ) else { return nil }
        app.buttons["Back"].tap()
        guard app.staticTexts["Settings"].waitForExistence(timeout: 5) else { return nil }

        let mapDataRow = app.buttons["settings.group.map-data"]
        guard scrollSettingsRowToHittable(mapDataRow, in: app) else {
            XCTFail("Snow theme-lock \(appearanceName): Map & data row is not hittable", file: file, line: line)
            return nil
        }
        mapDataRow.tap()
        let cellularToggle = app.switches["settings.downloads.allow-cellular"]
        let pinSizeLabel = app.staticTexts["Pin size"]
        let pinSizeValue = app.staticTexts["120%"]
        let pinSizeSlider = app.sliders["settings.pin-size"]
        guard capture(
            name: "map-data",
            comparisonElements: [cellularToggle, pinSizeLabel, pinSizeValue, pinSizeSlider],
            primaryInk: pinSizeLabel,
            secondaryInk: pinSizeValue,
            exportsFrozenEvidence: true
        ) else { return nil }
        app.buttons["Back"].tap()
        guard app.staticTexts["Settings"].waitForExistence(timeout: 5) else { return nil }

        let locationRow = app.buttons["settings.group.location"]
        guard scrollSettingsRowToHittable(locationRow, in: app) else {
            XCTFail("Snow theme-lock \(appearanceName): Location row is not hittable", file: file, line: line)
            return nil
        }
        locationRow.tap()
        let locationStatus = app.staticTexts["Location off"]
        let locationSettings = app.buttons["settings.location.open-system"]
        guard capture(
            name: "location",
            comparisonElements: [locationStatus, locationSettings],
            primaryInk: locationStatus,
            exportsFrozenEvidence: true
        ) else { return nil }
        app.buttons["Back"].tap()
        guard app.staticTexts["Settings"].waitForExistence(timeout: 5) else { return nil }

        let diagnosticsRow = app.buttons["settings.diagnostics.export"]
        guard scrollSettingsRowToHittable(diagnosticsRow, in: app) else {
            XCTFail("Snow theme-lock \(appearanceName): Diagnostics row is not hittable", file: file, line: line)
            return nil
        }
        diagnosticsRow.tap()
        let diagnosticsStatus = element(identifier: "settings.diagnostics.window-status", in: app)
        guard capture(
            name: "diagnostics",
            comparisonElements: [diagnosticsStatus]
        ) else { return nil }
        app.buttons["Back"].tap()
        guard app.staticTexts["Settings"].waitForExistence(timeout: 5) else { return nil }

        let replayWelcomeRow = app.buttons["settings.replay-onboarding"]
        guard scrollSettingsRowToHittable(replayWelcomeRow, in: app) else {
            XCTFail("Snow theme-lock \(appearanceName): Replay welcome row is not hittable", file: file, line: line)
            return nil
        }
        replayWelcomeRow.tap()
        let replayTitle = app.staticTexts["Interesting places around you"]
        let replayNext = app.buttons["onboarding.next"]
        guard capture(
            name: "replay-welcome",
            comparisonElements: [replayTitle, replayNext]
        ) else { return nil }

        app.terminate()
        return SettingsThemeLockCapture(regions: regions)
    }

    private func assertMyTracksRenderedPixelOracle(
        forceDarkAppearance: Bool,
        appearanceName: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> MyTracksAppearanceCapture? {
        let forcedAppearance: XCUIDevice.Appearance = forceDarkAppearance ? .dark : .light
        XCUIDevice.shared.appearance = forcedAppearance
        XCTAssertEqual(XCUIDevice.shared.appearance, forcedAppearance, file: file, line: line)
        defer { XCUIDevice.shared.appearance = .light }

        let app = launch(
            reset: true,
            seedVisitsEditorVisual: true,
            forceDarkAppearance: forceDarkAppearance,
            hideFixtureChrome: true
        )
        XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 10), file: file, line: line)
        let loading = app.otherElements["map.loading"]
        XCTAssertTrue(!loading.exists || loading.waitForNonExistence(timeout: 10), file: file, line: line)
        openJournalDoor(in: app)
        app.buttons["journal.row.my-tracks"].tap()

        let trackSurface = app.collectionViews["lists.detail.surface.track"]
        XCTAssertTrue(trackSurface.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertEqual(
            app.descendants(matching: .any)
                .matching(identifierPrefix: "lists.detail.track.row.date.").count,
            0,
            "Compact My tracks rows must not expose inline date controls",
            file: file,
            line: line
        )

        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "my-tracks-rendered-oracle-\(appearanceName)"
        attachment.lifetime = .keepAlways
        add(attachment)
        exportScreenshot(
            screenshot,
            named: "my-tracks-rendered-oracle-\(appearanceName)",
            force: true
        )

        let appFrame = app.windows.firstMatch.exists ? app.windows.firstMatch.frame : app.frame
        XCTAssertEqual(appFrame.width, 402, accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(appFrame.height, 874, accuracy: 0.5, file: file, line: line)
        guard let raster = RenderedPixelRaster(screenshot: screenshot, appFrame: appFrame) else {
            XCTFail("Could not decode My tracks rendered screenshot", file: file, line: line)
            return nil
        }

        let paper = RenderedRGB(241, 237, 223)
        let sheet = RenderedRGB(255, 253, 247)
        let ink = RenderedRGB(28, 28, 30)
        let dim = RenderedRGB(100, 99, 93)
        let accent = RenderedRGB(10, 107, 92)
        let danger = RenderedRGB(180, 35, 24)
        let reorderHandle = RenderedRGB(170, 168, 157)
        var failures: [String] = []

        func requireElement(_ element: XCUIElement, named name: String) -> Bool {
            guard element.exists else {
                failures.append("\(name): missing accessibility target")
                return false
            }
            return true
        }

        func requireText(
            _ element: XCUIElement,
            named name: String,
            foreground: RenderedRGB,
            background: RenderedRGB,
            minimumContrast: Double,
            foregroundInset: CGFloat = 0,
            minimumForegroundPixels: Int = 8
        ) {
            guard requireElement(element, named: name) else { return }
            let foregroundSample = raster.representativeToken(
                foreground,
                in: element.frame.insetBy(dx: foregroundInset, dy: foregroundInset)
            )
            let backgroundSample = raster.representativeToken(
                background,
                in: element.frame.insetBy(dx: -3, dy: -3)
            )
            if (foregroundSample?.count ?? 0) < minimumForegroundPixels {
                failures.append(
                    "\(name): expected rendered foreground \(foreground), found \(foregroundSample?.count ?? 0) interior pixels within ±5 RGB"
                )
            }
            if (backgroundSample?.count ?? 0) < 8 {
                failures.append(
                    "\(name): expected rendered background \(background), found \(backgroundSample?.count ?? 0) pixels within ±5 RGB"
                )
            }
            guard let foregroundSample, let backgroundSample else { return }
            let contrast = foregroundSample.color.contrastRatio(with: backgroundSample.color)
            if contrast < minimumContrast || contrast < 3 {
                failures.append(
                    "\(name): observed WCAG contrast \(String(format: "%.2f", contrast)):1, expected at least \(minimumContrast):1"
                )
            }
        }

        func requireFill(
            _ element: XCUIElement,
            named name: String,
            token: RenderedRGB,
            minimumCoverage: Double
        ) {
            guard requireElement(element, named: name) else { return }
            let coverage = raster.tokenCoverage(token, in: element.frame)
            if coverage < minimumCoverage {
                failures.append(
                    "\(name): token coverage \(String(format: "%.1f", coverage * 100))%, expected at least \(Int(minimumCoverage * 100))%"
                )
            }
        }

        let chrome = app.otherElements["lists.detail.track.chrome"]
        let back = app.buttons["lists.detail.track.back"]
        let title = app.staticTexts["lists.detail.track.title"]
        let done = app.buttons["lists.detail.track.done"]
        let summaryCard = app.otherElements["lists.detail.track.summary-card"]
        let sortDirection = app.staticTexts["lists.detail.track.sort-direction"]
        let summary = app.staticTexts["lists.detail.track.summary"]
        let explainer = app.staticTexts[
            "Your track is a sequence of visits you entered. Edit a row when the remembered day or order needs correcting."
        ]
        let dayHeader = app.staticTexts.matching(identifierPrefix: "lists.detail.track.day-header.").firstMatch
        let placeName = app.staticTexts.matching(identifierPrefix: "lists.detail.track.row.name.").firstMatch
        let metadata = app.staticTexts.matching(identifierPrefix: "lists.detail.track.row.metadata.").firstMatch
        let heart = app.buttons.matching(identifierPrefix: "lists.detail.track.row.loved.").firstMatch
        let firstRow = app.otherElements.matching(identifierPrefix: "lists.detail.track.row.card.").firstMatch
        let renderedRowCount = app.descendants(matching: .any)
            .matching(identifierPrefix: "lists.detail.track.row.card.").count
        let renderedHandleCount = app.descendants(matching: .any)
            .matching(identifierPrefix: "lists.detail.track.row.reorder.").count
        XCTAssertEqual(
            renderedHandleCount,
            renderedRowCount,
            "Every rendered visit row must expose exactly one app-drawn reorder handle",
            file: file,
            line: line
        )

        requireText(back, named: "Back", foreground: accent, background: paper, minimumContrast: 4.5)
        requireText(title, named: "My tracks title", foreground: ink, background: paper, minimumContrast: 3)
        requireText(done, named: "Done", foreground: accent, background: paper, minimumContrast: 4.5)
        requireText(sortDirection, named: "sort direction", foreground: ink, background: sheet, minimumContrast: 4.5)
        requireText(summary, named: "visit summary", foreground: ink, background: sheet, minimumContrast: 3)
        requireText(explainer, named: "summary explanation", foreground: dim, background: sheet, minimumContrast: 4.5)
        requireText(dayHeader, named: "day header", foreground: dim, background: paper, minimumContrast: 4.5)
        requireText(placeName, named: "place name", foreground: ink, background: sheet, minimumContrast: 4.5)
        if requireElement(placeName, named: "representative long Malaysian place name"),
           placeName.label != "Sultan Abdul Samad Building and Merdeka Square" {
            failures.append("place name: visual fixture is not the ratified long-name representative")
        }
        if requireElement(placeName, named: "compact representative place name"),
           placeName.frame.height > 26 {
            failures.append("place name: expected one compact line, got \(placeName.frame)")
        }
        requireText(metadata, named: "place metadata", foreground: dim, background: sheet, minimumContrast: 4.5)
        requireText(
            heart,
            named: "heart",
            foreground: danger,
            background: sheet,
            minimumContrast: 4.5,
            foregroundInset: 8
        )

        requireFill(chrome, named: "navigation chrome", token: paper, minimumCoverage: 0.65)
        requireFill(summaryCard, named: "summary card", token: sheet, minimumCoverage: 0.45)
        requireFill(firstRow, named: "visit row card", token: sheet, minimumCoverage: 0.45)
        requireFill(back, named: "flat Back control", token: paper, minimumCoverage: 0.45)
        requireFill(done, named: "flat Done control", token: paper, minimumCoverage: 0.45)
        requireFill(heart, named: "unfilled heart control", token: sheet, minimumCoverage: 0.35)

        if requireElement(chrome, named: "navigation chrome system-blue scan"),
           raster.systemBlueCount(in: chrome.frame) > 0 {
            failures.append("navigation chrome: found system-blue pixels")
        }
        if raster.systemBlueCount(in: trackSurface.frame) > 0 {
            failures.append("track surface: found system-blue pixels")
        }

        if requireElement(placeName, named: "place name ordering"),
           requireElement(metadata, named: "metadata ordering"),
           placeName.frame.maxY > metadata.frame.minY {
            failures.append("row anatomy: place name must render above metadata")
        }
        for (element, name) in [(back, "Back"), (done, "Done"), (heart, "heart")] {
            if requireElement(element, named: "\(name) touch target"),
               element.frame.width < 44 || element.frame.height < 44 {
                failures.append("\(name): expected at least a 44×44 touch target, got \(element.frame)")
            }
        }
        if requireElement(heart, named: "compact heart"),
           heart.frame.width > 72 || heart.frame.height > 46 {
            failures.append("heart: expected compact single-line hit target, got \(heart.frame)")
        }

        if raster.tokenCount(paper, in: trackSurface.frame) < 100 {
            failures.append("track surface: paper token is not visibly rendered")
        }
        if raster.tokenCount(sheet, in: trackSurface.frame) < 100 {
            failures.append("track surface: sheet token is not visibly rendered")
        }
        let reorderStrip = CGRect(
            // The amended row keeps the handle inside the card. Sample the
            // first row's trailing bounds, not the list gutter or full surface.
            x: firstRow.frame.maxX - 60,
            y: firstRow.frame.minY,
            width: 60,
            height: firstRow.frame.height
        )
        if raster.tokenCount(reorderHandle, in: reorderStrip) < 100 {
            failures.append("reorder handles: invariant token is not visibly rendered")
        }

        XCTAssertTrue(
            failures.isEmpty,
            "My tracks \(appearanceName) rendered-pixel oracle failed:\n- \(failures.joined(separator: "\n- "))",
            file: file,
            line: line
        )

        let expectedVisitDateChromeMinY = back.frame.minY
        firstRow.tap()
        let visitDateTitle = app.staticTexts["lists.detail.visit-date.title"]
        XCTAssertTrue(visitDateTitle.waitForExistence(timeout: 5), file: file, line: line)
        let visitDateSurface = app.otherElements["lists.detail.visit-date.surface"]
        XCTAssertTrue(visitDateSurface.exists, file: file, line: line)
        XCTAssertEqual(
            visitDateSurface.frame.minY,
            expectedVisitDateChromeMinY,
            accuracy: 20,
            "Visit date root frame must share the owning track page's origin",
            file: file,
            line: line
        )
        let visitDateScreenshot = XCUIScreen.main.screenshot()
        let visitDateAttachment = XCTAttachment(screenshot: visitDateScreenshot)
        visitDateAttachment.name = "my-tracks-visit-date-oracle-\(appearanceName)"
        visitDateAttachment.lifetime = .keepAlways
        add(visitDateAttachment)
        exportScreenshot(
            visitDateScreenshot,
            named: "my-tracks-visit-date-oracle-\(appearanceName)",
            force: true
        )
        guard let visitDateRaster = RenderedPixelRaster(
            screenshot: visitDateScreenshot,
            appFrame: appFrame
        ) else {
            XCTFail("Could not decode Visit date rendered screenshot", file: file, line: line)
            return nil
        }
        let visitDateBack = app.buttons["lists.detail.visit-date.back"]
        XCTAssertTrue(visitDateBack.exists, file: file, line: line)
        XCTAssertTrue(visitDateBack.isHittable, file: file, line: line)
        XCTAssertGreaterThanOrEqual(
            visitDateBack.frame.minY,
            appFrame.minY,
            "Visit date chrome must stay inside the device canvas",
            file: file,
            line: line
        )
        XCTAssertEqual(
            visitDateBack.frame.minY,
            expectedVisitDateChromeMinY,
            accuracy: 20,
            "Visit date chrome must align with the owning large sheet's ruled top",
            file: file,
            line: line
        )
        let visitDateSurfaceFrame = CGRect(
            x: appFrame.minX,
            y: visitDateBack.frame.minY,
            width: appFrame.width,
            height: appFrame.maxY - visitDateBack.frame.minY
                - MyTracksRenderedFrameGeometry.systemOwnedBottomInset
        )

        return MyTracksAppearanceCapture(
            raster: raster,
            trackSurfaceFrame: trackSurface.frame,
            visitDateRaster: visitDateRaster,
            visitDateSurfaceFrame: visitDateSurfaceFrame
        )
    }

    private func launch(
        reset: Bool,
        locationNotDetermined: Bool = false,
        locationDenied: Bool = false,
        simulatedLocationAuthorization: Bool = false,
        simulatedLatitude: Double? = nil,
        simulatedLongitude: Double? = nil,
        accessibilityTextSize: Bool = false,
        seedUserList: Bool = false,
        offlineProgress: Double? = nil,
        offlineWaiting: Bool = false,
        resetTheme: Bool = false,
        theme: String? = nil,
        pinSizeMultiplier: Double? = nil,
        pinDiagnostics: Bool = false,
        seedTrackVisits: Bool = false,
        seedVisitsEditorVisual: Bool = false,
        seedBurstTrackVisits: Bool = false,
        seedSpreadList: Bool = false,
        seedTrackList: Bool = false,
        seedMultiDayTrackList: Bool = false,
        seedTrackListLovedVisit: Bool = false,
        seedJournalDoorTextStress: Bool = false,
        seedFocusedTracksRoute: Bool = false,
        seedManagedPlaces: Bool = false,
        coverageBBoxes: [String] = [],
        resetOnboarding: Bool = false,
        forceDarkAppearance: Bool = false,
        disableMaterialModeLock: Bool = false,
        uiTestingColorScheme: String? = nil,
        forceTileNetworkOffline: Bool = false,
        densePins: Bool = false,
        startupViewport: String? = nil,
        trackReplayBeatDuration: Double? = nil,
        replayVisualSeed: Bool = false,
        hideFixtureChrome: Bool = false,
        placeCardPressEvidence: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-fixture-map"]
        app.launchArguments.append("--ui-testing-reset-pin-size")
        if hideFixtureChrome {
            app.launchArguments.append("--ui-testing-hide-fixture-chrome")
        }
        if placeCardPressEvidence {
            app.launchArguments.append("--ui-testing-place-card-press-evidence")
        }
        if densePins {
            app.launchArguments.append("--ui-testing-dense-pins")
        }
        if let startupViewport {
            app.launchArguments.append("--ui-testing-map-state")
            app.launchArguments.append(startupViewport)
        }
        if let trackReplayBeatDuration {
            app.launchArguments.append("--ui-testing-track-replay-beat-duration")
            app.launchArguments.append(String(trackReplayBeatDuration))
        }
        if replayVisualSeed {
            app.launchArguments.append("--ui-testing-replay-visual-seed")
        }
        if pinDiagnostics {
            app.launchArguments.append("--ui-testing-pin-diagnostics")
        }
        if reset {
            app.launchArguments.append("--ui-testing-reset-coverage-shading")
            app.launchArguments.append("--ui-testing-reset-database")
        }
        if locationNotDetermined {
            app.launchArguments.append("--ui-testing-location-not-determined")
        }
        if locationDenied {
            app.launchArguments.append("--ui-testing-location-denied")
        }
        if simulatedLocationAuthorization {
            app.launchArguments.append("--ui-testing-location-authorized")
        }
        if let simulatedLatitude {
            app.launchArguments.append("--ui-testing-location-latitude")
            app.launchArguments.append(String(simulatedLatitude))
        }
        if let simulatedLongitude {
            app.launchArguments.append("--ui-testing-location-longitude")
            app.launchArguments.append(String(simulatedLongitude))
        }
        if accessibilityTextSize {
            app.launchArguments.append("-UIPreferredContentSizeCategoryName")
            app.launchArguments.append("UICTContentSizeCategoryAccessibilityXXXL")
        }
        if forceDarkAppearance {
            app.launchArguments.append("-AppleInterfaceStyle")
            app.launchArguments.append("Dark")
        }
        if disableMaterialModeLock {
            app.launchArguments.append("--ui-testing-disable-material-mode-lock")
        }
        if let uiTestingColorScheme {
            app.launchArguments.append("--ui-testing-color-scheme")
            app.launchArguments.append(uiTestingColorScheme)
        }
        if forceTileNetworkOffline {
            app.launchArguments.append("--debug-force-tile-network-offline")
        }
        if seedUserList {
            app.launchArguments.append("--ui-testing-seed-user-list")
        }
        if seedTrackVisits {
            app.launchArguments.append("--ui-testing-seed-track-visits")
        }
        if seedVisitsEditorVisual {
            app.launchArguments.append("--ui-testing-seed-visits-editor-visual")
        }
        if seedBurstTrackVisits {
            app.launchArguments.append("--ui-testing-seed-burst-track-visits")
        }
        if seedSpreadList {
            app.launchArguments.append("--ui-testing-seed-spread-list")
        }
        if seedTrackList {
            app.launchArguments.append("--ui-testing-seed-track-list")
        }
        if seedMultiDayTrackList {
            app.launchArguments.append("--ui-testing-seed-multiday-track-list")
        }
        if seedTrackListLovedVisit {
            app.launchArguments.append("--ui-testing-seed-track-list-loved-visit")
        }
        if seedJournalDoorTextStress {
            app.launchArguments.append("--ui-testing-seed-journal-door-text-stress")
        }
        if seedFocusedTracksRoute {
            app.launchArguments.append("--ui-testing-seed-focused-tracks-route")
        }
        if seedManagedPlaces {
            app.launchArguments.append("--ui-testing-seed-managed-places")
        }
        if let offlineProgress {
            app.launchArguments.append("--ui-testing-offline-progress")
            app.launchArguments.append(String(offlineProgress))
        }
        if offlineWaiting {
            app.launchArguments.append("--ui-testing-offline-waiting")
        }
        if resetTheme {
            app.launchArguments.append("--ui-testing-reset-theme")
        }
        if let theme {
            app.launchArguments.append("--ui-testing-theme")
            app.launchArguments.append(theme)
        }
        if let pinSizeMultiplier {
            app.launchArguments.append("--ui-testing-pin-size-multiplier")
            app.launchArguments.append(String(pinSizeMultiplier))
        }
        for bbox in coverageBBoxes {
            app.launchArguments.append("--ui-testing-coverage-bbox")
            app.launchArguments.append(bbox)
        }
        if resetOnboarding {
            app.launchArguments.append("--ui-testing-reset-onboarding")
            app.launchArguments.append("-hasCompletedOnboarding")
            app.launchArguments.append("NO")
        } else {
            app.launchArguments.append("--ui-testing-complete-onboarding")
        }
        app.launch()
        return app
    }

    private func exercisePlaceCardPressInsetEvidence(
        accessibilityTextSize: Bool
    ) {
        let app = launch(
            reset: false,
            accessibilityTextSize: accessibilityTextSize,
            placeCardPressEvidence: true
        )
        let hide = app.buttons["place-card.press-evidence.hide"]
        let state = app.otherElements["place-card.press-evidence.state"]

        XCTAssertTrue(hide.waitForExistence(timeout: 5))
        XCTAssertTrue(hide.isHittable)
        XCTAssertTrue(state.waitForExistence(timeout: 5))
        XCTAssertEqual(state.value as? String, "rest")

        exportMeasurements(
            named: "place-card-press-inset-\(accessibilityTextSize ? "ax" : "default")-frame",
            elements: [("hide", hide), ("state", state)],
            notes: [String(format: "screen-scale: %.2f", UIScreen.main.scale)]
        )

        for _ in 0..<80 {
            hide.tap()
        }
    }

    private func selectMapTheme(_ themeID: String, in app: XCUIApplication) {
        openExploreDoor(in: app)
        app.buttons["explore.row.settings"].tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
        let appearance = app.buttons["settings.group.appearance"]
        XCTAssertTrue(appearance.waitForExistence(timeout: 5))
        appearance.tap()
        XCTAssertTrue(app.staticTexts["Appearance"].waitForExistence(timeout: 5))
        let themeButton = app.buttons["settings.theme.\(themeID)"]
        XCTAssertTrue(scrollToHittable(themeButton, in: app))
        themeButton.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertTrue(waitForElementValue("Selected", identifier: "settings.theme.\(themeID)", in: app))
        app.buttons["Close"].tap()
        XCTAssertTrue(waitForNonExistence(of: app.staticTexts["Settings"], timeout: 5))
        XCTAssertTrue(waitForMapTheme(themeID, in: app))
    }

    private func waitForMapTheme(_ themeID: String, in app: XCUIApplication) -> Bool {
        let loadedTheme = app.staticTexts["map.loaded-theme"]
        let predicate = NSPredicate(format: "exists == true AND label == %@", "Loaded theme: \(themeID)")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: loadedTheme)
        let result = XCTWaiter.wait(for: [expectation], timeout: 10)
        if result != .completed {
            XCTFail("Expected loaded theme \(themeID), got \(loadedTheme.exists ? loadedTheme.label : "missing loaded theme")")
            return false
        }
        let loading = app.otherElements["map.loading"]
        return !loading.exists || loading.waitForNonExistence(timeout: 10)
    }

    private func completeOnboardingSelectingUK(in app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["Interesting places around you"].waitForExistence(timeout: 5))
        app.buttons["onboarding.next"].tap()
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.buttons["onboarding.region.uk"].waitForExistence(timeout: 5))
        app.buttons["onboarding.region.uk"].tap()
        app.buttons["onboarding.next"].tap()
        app.buttons["onboarding.next"].tap()
        XCTAssertTrue(app.buttons["onboarding.location.skip"].waitForExistence(timeout: 5))
        app.buttons["onboarding.location.skip"].tap()
        XCTAssertTrue(app.buttons["onboarding.finish"].waitForExistence(timeout: 5))
        app.buttons["onboarding.finish"].tap()
        XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 10))
    }

    private func openExploreDoor(in app: XCUIApplication) {
        let door = app.buttons["map.door.explore"]
        XCTAssertTrue(door.waitForExistence(timeout: 5))
        door.tap()
    }

    private func assertSettingsRootRow(
        _ row: XCUIElement,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(scrollToHittable(row, in: app), row.identifier, file: file, line: line)
        XCTAssertGreaterThanOrEqual(row.frame.width, 44, row.identifier, file: file, line: line)
        XCTAssertGreaterThanOrEqual(row.frame.height, 44, row.identifier, file: file, line: line)
    }

    private func captureSettingsDestination(
        rowIdentifier: String,
        title: String,
        subtitle: String? = nil,
        screenshotName: String,
        accessibilityTextSize: Bool = false,
        minimumAXSubtitleHeight: CGFloat? = nil,
        interactiveIdentifiers: [String] = [],
        visibleIdentifiers: [String] = [],
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let row = app.buttons[rowIdentifier]
        XCTAssertTrue(
            scrollSettingsRowToHittable(row, in: app),
            rowIdentifier,
            file: file,
            line: line
        )
        row.tap()
        XCTAssertTrue(
            app.staticTexts[title].waitForExistence(timeout: 5),
            title,
            file: file,
            line: line
        )
        if let subtitle {
            let renderedSubtitle = app.staticTexts[subtitle]
            XCTAssertTrue(
                renderedSubtitle.waitForExistence(timeout: 5),
                "\(title): rendered subtitle",
                file: file,
                line: line
            )
            XCTAssertEqual(renderedSubtitle.label, subtitle, file: file, line: line)
            assertContainedInAppFrame(renderedSubtitle, in: app, file: file, line: line)
            if accessibilityTextSize, let minimumAXSubtitleHeight {
                XCTAssertGreaterThanOrEqual(
                    renderedSubtitle.frame.height,
                    minimumAXSubtitleHeight,
                    "\(title): the AX-XXXL subtitle must occupy multiple rendered lines",
                    file: file,
                    line: line
                )
            }
        }
        attachScreenshot(named: screenshotName)
        for identifier in visibleIdentifiers {
            let visibleElement = element(identifier: identifier, in: app)
            XCTAssertTrue(
                scrollToFullyContained(
                    visibleElement,
                    in: app,
                    requireHittable: false
                ),
                "\(title): \(identifier)",
                file: file,
                line: line
            )
            assertContainedInAppFrame(visibleElement, in: app, file: file, line: line)
        }
        for identifier in interactiveIdentifiers {
            let control = element(identifier: identifier, in: app)
            XCTAssertTrue(
                scrollToFullyContained(control, in: app),
                "\(title): \(identifier)",
                file: file,
                line: line
            )
            assertMinimumInteractiveTarget(control, file: file, line: line)
            assertContainedInAppFrame(control, in: app, file: file, line: line)
        }
        let back = app.buttons["Back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5), title, file: file, line: line)
        back.tap()
        XCTAssertTrue(
            app.staticTexts["Settings"].waitForExistence(timeout: 5),
            title,
            file: file,
            line: line
        )
    }

    private func assertSettingsRootRenderContract(
        in app: XCUIApplication,
        accessibilityTextSize: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let rows = [
            (
                identifier: "settings.group.appearance",
                label: "Appearance",
                value: "Snow selected. Four existing presets.",
                minimumAXHeight: CGFloat(350)
            ),
            (
                identifier: "settings.storage.manage",
                label: "Offline maps",
                value: "Packs · downloads · per-pack storage",
                minimumAXHeight: CGFloat(270)
            ),
            (
                identifier: "settings.group.coverage",
                label: "Coverage",
                value: "Published regions · sources · extents",
                minimumAXHeight: CGFloat(240)
            ),
            (
                identifier: "settings.group.map-data",
                label: "Map & data",
                value: "Cellular downloads · pin size",
                minimumAXHeight: CGFloat(290)
            ),
            (
                identifier: "settings.group.location",
                label: "Location",
                value: "Permission and system settings",
                minimumAXHeight: CGFloat(240)
            ),
            (
                identifier: "settings.diagnostics.export",
                label: "Diagnostic log",
                value: "Review, prepare, share, or delete local logs.",
                minimumAXHeight: CGFloat(245)
            ),
            (
                identifier: "settings.replay-onboarding",
                label: "Replay welcome",
                value: "Return to the existing welcome flow",
                minimumAXHeight: CGFloat(290)
            ),
        ]

        for expectation in rows {
            let row = app.buttons[expectation.identifier]
            XCTAssertTrue(
                scrollToFullyContained(row, in: app),
                expectation.identifier,
                file: file,
                line: line
            )
            XCTAssertEqual(row.label, expectation.label, file: file, line: line)
            XCTAssertEqual(
                row.value as? String,
                expectation.value,
                expectation.identifier,
                file: file,
                line: line
            )
            XCTAssertGreaterThanOrEqual(
                row.frame.height,
                (accessibilityTextSize ? expectation.minimumAXHeight : 75) - 0.5,
                accessibilityTextSize
                    ? "\(expectation.identifier): AX-XXXL copy must occupy its natural wrapped height"
                    : expectation.identifier,
                file: file,
                line: line
            )
            assertMinimumInteractiveTarget(row, file: file, line: line)
            assertContainedInAppFrame(row, in: app, file: file, line: line)
        }
    }

    private func scrollSettingsRowToHittable(
        _ row: XCUIElement,
        in app: XCUIApplication
    ) -> Bool {
        if row.waitForExistence(timeout: 2), row.isHittable {
            return true
        }

        for _ in 0..<5 {
            if row.exists, row.frame.midY < app.frame.midY {
                scrollTarget(in: app).swipeDown()
            } else {
                scrollTarget(in: app).swipeUp()
            }
            if row.waitForExistence(timeout: 1), row.isHittable {
                return true
            }
        }

        return row.exists && row.isHittable
    }

    private func openJournalDoor(in app: XCUIApplication) {
        let door = app.buttons["map.door.journal"]
        XCTAssertTrue(door.waitForExistence(timeout: 5))
        door.tap()
    }

    private func openListFromTracksRoot(
        named name: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let row = app.buttons.matching(identifierPrefix: "lists.row.").matching(
            NSPredicate(format: "label CONTAINS %@", name)
        ).firstMatch
        XCTAssertTrue(
            scrollToHittable(row, in: app),
            "Expected \(name) on the single Journal root",
            file: file,
            line: line
        )
        row.tap()
    }

    private func openScope(in app: XCUIApplication) {
        openExploreDoor(in: app)
        XCTAssertTrue(app.scrollViews["explore.root"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["explore.scope.include-hidden"].exists)
        XCTAssertTrue(app.switches["explore.scope.coverage-shading"].exists)
    }

    private func closePlaceCard(in app: XCUIApplication) {
        let sheet = app.scrollViews.matching(identifierPrefix: "place-card.instance.").firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        let start = sheet.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertTrue(waitForNonExistence(of: sheet, timeout: 5))
    }

    private func tapFixturePin(in map: XCUIElement, app: XCUIApplication) {
        openFixtureCard(in: map, app: app)
    }

    private func tapFixtureCoordinate(in map: XCUIElement) {
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    @discardableResult
    private func activateFixturePin(
        in map: XCUIElement,
        app: XCUIApplication,
        placeID: String,
        title: String,
        expectedLabel: String
    ) -> Bool {
        let marker = app.staticTexts["map.fixture-pin.\(placeID)"]
        guard marker.waitForExistence(timeout: 10),
              waitForFixturePinToBecomeHitTestable(marker)
        else {
            XCTFail("Rendered fixture pin \(placeID) did not become hit-testable")
            return false
        }
        guard waitForAccessibilityPin(in: app, placeID: placeID, label: expectedLabel) else { return false }
        let pin = app.buttons["map.pin.\(placeID)"]
        guard let projectedPoint = projectedScreenPoint(from: marker, through: map, in: app) else {
            XCTFail(
                "Could not resolve projected point for \(placeID); map frame \(map.frame); app frame \(app.frame); marker value \(marker.value ?? "nil")"
            )
            return false
        }
        XCTAssertTrue(
            pin.frame.insetBy(dx: -2, dy: -2).contains(projectedPoint),
            "Accessibility pin \(placeID) frame \(pin.frame) did not contain projected point \(projectedPoint); map frame \(map.frame); marker value \(marker.value ?? "nil")"
        )
        pin.tap()
        if app.staticTexts[title].waitForExistence(timeout: 5) {
            return true
        }
        let tapStatus = app.staticTexts["map.debug-tap-status"]
        let tap = tapStatus.exists ? tapStatus.label : "tap-status-missing"
        XCTFail("Activating accessibility pin \(placeID) did not open \(title); \(tap)")
        return false
    }

    @discardableResult
    private func waitForAccessibilityPin(in app: XCUIApplication, placeID: String, label: String) -> Bool {
        let identifier = "map.pin.\(placeID)"
        let pin = app.buttons[identifier]
        guard pin.waitForExistence(timeout: 10) else {
            XCTFail("Accessibility pin \(placeID) did not appear")
            return false
        }
        let predicate = NSPredicate(format: "label == %@", label)
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: pin)], timeout: 5)
        if result == .completed {
            return true
        }

        // Re-sample the AX tree after a predicate miss; this catches stale
        // XCUIElement snapshots without extending the wait budget.
        let resampled = AXResampler.matches(expected: label, attempts: 3, interval: 0.1) {
            AXElementReadback.label(for: identifier) {
                let pin = app.buttons[$0]
                return (exists: pin.exists, label: pin.label)
            }
        }
        if resampled.matched {
            return true
        }

        XCTFail("Accessibility pin \(placeID) label was \(resampled.observed ?? "missing"), expected \(label)")
        return false
    }

    @discardableResult
    private func tapProjectedFixturePin(
        in map: XCUIElement,
        app: XCUIApplication,
        placeID: String,
        title: String,
    ) -> Bool {
        let marker = app.staticTexts["map.fixture-pin.\(placeID)"]
        guard marker.waitForExistence(timeout: 10),
              waitForFixturePinToBecomeHitTestable(marker),
              tapProjectedFixtureMarker(marker, through: map, in: app)
        else { return false }
        waitForTapStatusToChange(in: app)
        if app.staticTexts[title].waitForExistence(timeout: 2) {
            return true
        }
        let tapStatus = app.staticTexts["map.debug-tap-status"]
        let tap = tapStatus.exists ? tapStatus.label : "tap-status-missing"
        XCTFail("Projected tap did not open \(title); \(tap)")
        return false
    }

    private func openFixtureCard(
        in map: XCUIElement,
        app: XCUIApplication,
        expectedHidden: Bool = false
    ) {
        let title = app.staticTexts["Ghost Sign"]
        let pin = app.buttons["map.pin.\(placeID)"]

        guard waitForFixtureHidden(expectedHidden, in: app) else {
            XCTFail(
                "Fixture reset did not reach hidden=\(expectedHidden) before opening map.pin.\(placeID)"
            )
            return
        }

        var observationTimeout: TimeInterval = 2
        let match = AXBoundedScroller.acquire(
            maxScrolls: 3,
            observe: {
                guard pin.waitForExistence(timeout: observationTimeout) else {
                    return .missing
                }
                return pin.isHittable ? .hittable : .presentNotHittable
            },
            scroll: {
                let start = map.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.08, dy: 0.58)
                )
                let end = map.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.08, dy: 0.25)
                )
                start.press(forDuration: 0.1, thenDragTo: end)
                observationTimeout = 1
            }
        )
        guard match.matched else {
            XCTFail(
                "Fixture accessibility pin map.pin.\(placeID) was not hittable after "
                    + "\(match.scrolls) bounded map repositions; final=\(match.observation), "
                    + "exists=\(pin.exists), frame=\(pin.frame), mapFrame=\(map.frame)"
            )
            return
        }

        pin.tap()
        XCTAssertTrue(
            title.waitForExistence(timeout: 5),
            "Fixture accessibility pin map.pin.\(placeID) did not open Ghost Sign; "
                + "exists=\(pin.exists), hittable=\(pin.isHittable), label=\(pin.label), "
                + "pinFrame=\(pin.frame), repositions=\(match.scrolls)"
        )
    }

    private func openSecondFixtureCard(in map: XCUIElement, app: XCUIApplication) {
        openCard(named: "Art Deco Cinema", in: map, app: app, tap: tapSecondFixturePin)
    }

    private func openCard(
        named name: String,
        in map: XCUIElement,
        app: XCUIApplication,
        tap: (XCUIElement) -> Void
    ) {
        let title = app.staticTexts[name]
        for _ in 0..<5 {
            tap(map)
            if title.waitForExistence(timeout: 1) {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        XCTAssertTrue(title.waitForExistence(timeout: 1))
    }

    private func tapSecondFixturePin(in map: XCUIElement) {
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.67, dy: 0.37)).tap()
    }

    private func waitForFixturePinToBecomeHitTestable(_ marker: XCUIElement) -> Bool {
        let predicate = NSPredicate(format: "label == %@", "hit")
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: marker)], timeout: 10) == .completed
    }

    @discardableResult
    private func waitForTapStatusToChange(in app: XCUIApplication) -> Bool {
        let tapStatus = app.staticTexts["map.debug-tap-status"]
        guard tapStatus.waitForExistence(timeout: 2) else { return false }
        let predicate = NSPredicate(format: "label != %@", "not-tapped")
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: tapStatus)], timeout: 3) == .completed
    }

    private func expandPlaceCardSheet(in app: XCUIApplication) -> Bool {
        let sheet = app.scrollViews.matching(identifierPrefix: "place-card.instance.").firstMatch
        guard sheet.waitForExistence(timeout: 5) else { return false }
        let initialHeight = sheet.frame.height
        let appHeight = app.frame.height
        guard appHeight > 0, initialHeight < appHeight * 0.85 else { return false }

        sheet.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08))
            .press(
                forDuration: 0.1,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
            )

        let targetHeight = min(initialHeight + 80, appHeight * 0.85)
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if sheet.frame.height > targetHeight {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return false
    }

    private func tapProjectedFixtureMarker(_ marker: XCUIElement, through map: XCUIElement, in app: XCUIApplication) -> Bool {
        guard let point = projectedScreenPoint(from: marker, through: map, in: app) else { return false }
        let appFrame = app.frame
        guard appFrame.width > 0, appFrame.height > 0 else { return false }
        app.coordinate(withNormalizedOffset: CGVector(
            dx: (point.x - appFrame.minX) / appFrame.width,
            dy: (point.y - appFrame.minY) / appFrame.height
        )).tap()
        return true
    }

    private func projectedScreenPoint(from marker: XCUIElement, through map: XCUIElement, in app: XCUIApplication) -> CGPoint? {
        guard let offset = projectedOffset(from: marker) else { return nil }
        let mapFrame = map.frame
        let appFrame = app.frame
        guard appFrame.width > 0, appFrame.height > 0 else { return nil }
        let referenceFrame = mapFrame.width.isFinite && mapFrame.height.isFinite && mapFrame.width > 0 && mapFrame.height > 0
            ? mapFrame
            : appFrame
        let point = CGPoint(
            x: referenceFrame.minX + (offset.dx * referenceFrame.width),
            y: referenceFrame.minY + (offset.dy * referenceFrame.height)
        )
        guard appFrame.contains(point) else { return nil }
        return point
    }

    private func projectedOffset(from marker: XCUIElement) -> CGVector? {
        guard let value = marker.value as? String else { return nil }
        let parts = value.split(separator: " ")
        guard parts.count == 2,
              let xPart = parts.first,
              let yPart = parts.last,
              xPart.hasPrefix("x:"),
              yPart.hasPrefix("y:"),
              let dx = Double(xPart.dropFirst(2)),
              let dy = Double(yPart.dropFirst(2)),
              (0...1).contains(dx),
              (0...1).contains(dy)
        else { return nil }
        return CGVector(dx: dx, dy: dy)
    }

    private func tapEmptyMap(in map: XCUIElement) {
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.20, dy: 0.30)).tap()
    }

    private func acquireKeyboardFocus(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maxAttempts: Int = 3,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        func observeFocus() -> KeyboardFocusObservation {
            KeyboardFocusProxySelector.observe(
                softwareKeyboardPresent: app.keyboards.firstMatch.exists,
                elementFocused: element.hasFocus
            )
        }

        var lastObservation = observeFocus()
        guard !lastObservation.focused else {
            XCTFail(
                "keyboard focus proxy \(lastObservation.proxy.rawValue) was already true on the fresh pre-tap field",
                file: file,
                line: line
            )
            return false
        }

        let result = AXFocusAcquirer.acquire(
            maxAttempts: maxAttempts,
            interval: 0.1,
            isFocused: {
                let predicate = NSPredicate { _, _ in
                    lastObservation = observeFocus()
                    return lastObservation.focused
                }
                let waitResult = XCTWaiter.wait(
                    for: [
                        XCTNSPredicateExpectation(
                            predicate: predicate,
                            object: element
                        ),
                    ],
                    timeout: 1
                )
                if waitResult == .completed {
                    return true
                }
                lastObservation = observeFocus()
                return lastObservation.focused
            },
            requestFocus: { element.tap() }
        )
        guard result.matched else {
            XCTFail(
                "keyboard focus not acquired within \(maxAttempts) attempts using \(lastObservation.proxy.rawValue) — known to amplify under concurrent-gate load, see #600 cap-3 rep1",
                file: file,
                line: line
            )
            return false
        }
        return true
    }

    private func tapSwitch(in app: XCUIApplication, identifier: String, expectedValue: String) {
        let switchElement = app.switches[identifier]
        guard scrollToHittable(switchElement, in: app) else {
            XCTFail("Switch \(identifier) did not appear")
            return
        }

        switchElement.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let result = AXValueWaiter.wait(expected: expectedValue, timeout: 5) {
            AXElementReadback.value(for: identifier) {
                let current = app.switches[$0]
                return (exists: current.exists, value: { current.value as? String })
            }
        }
        if result.matched {
            return
        }

        let finalElement = app.switches[identifier]
        let finalDescription = finalElement.exists ? finalElement.debugDescription : "missing switch"
        XCTFail(
            "Switch \(identifier) value was \(result.observed ?? "missing"), expected \(expectedValue); \(finalDescription)"
        )
    }

    private func tapCategoryChip(
        in app: XCUIApplication,
        identifier: String,
        expectedValue: String
    ) {
        let chip = app.buttons[identifier]
        guard scrollToHittable(chip, in: app) else {
            XCTFail("Category chip \(identifier) did not appear")
            return
        }

        chip.tap()
        let result = AXValueWaiter.wait(expected: expectedValue, timeout: 5) {
            AXElementReadback.value(for: identifier) {
                let current = app.buttons[$0]
                return (exists: current.exists, value: { current.value as? String })
            }
        }
        guard !result.matched else { return }

        let finalElement = app.buttons[identifier]
        let finalDescription = finalElement.exists ? finalElement.debugDescription : "missing chip"
        XCTFail(
            "Category chip \(identifier) value was \(result.observed ?? "missing"), expected \(expectedValue); \(finalDescription)"
        )
    }

    private func adjustSliderToTrueEdge(_ slider: XCUIElement, in app: XCUIApplication, identifier: String, expectedValue: String) {
        guard slider.waitForExistence(timeout: 5) else {
            XCTFail("Slider \(identifier) did not appear")
            return
        }
        let plan = AXSliderUpperEdgeAdjuster.upperEdgeDragPlan()
        for _ in 0..<3 {
            let currentSlider = app.sliders[identifier]
            guard currentSlider.waitForExistence(timeout: 2) else { continue }
            currentSlider
                .coordinate(withNormalizedOffset: plan.start)
                .press(
                    forDuration: plan.holdDuration,
                    thenDragTo: currentSlider.coordinate(withNormalizedOffset: plan.end)
                )
            let resampled = AXValueWaiter.wait(expected: expectedValue, attempts: 3, interval: 0.1) {
                AXElementReadback.value(for: identifier) {
                    let current = app.sliders[$0]
                    return (exists: current.exists, value: { current.value as? String })
                }
            }
            if resampled.matched {
                return
            }
        }
        for normalizedPosition in plan.fallbackNormalizedPositions {
            let currentSlider = app.sliders[identifier]
            guard currentSlider.waitForExistence(timeout: 2) else { continue }
            currentSlider.adjust(toNormalizedSliderPosition: normalizedPosition)
            let resampled = AXValueWaiter.wait(expected: expectedValue, attempts: 3, interval: 0.1) {
                AXElementReadback.value(for: identifier) {
                    let current = app.sliders[$0]
                    return (exists: current.exists, value: { current.value as? String })
                }
            }
            if resampled.matched {
                return
            }
        }
        let finalSlider = app.sliders[identifier]
        let finalValue = AXElementReadback.value(for: identifier) {
            let current = app.sliders[$0]
            return (exists: current.exists, value: { current.value as? String })
        }
        let finalDescription = finalSlider.exists ? finalSlider.debugDescription : "missing slider"
        XCTFail(
            "Slider \(identifier) value was \(finalValue ?? "missing"), expected \(expectedValue) after coordinate max-edge drag and normalized fallback; \(finalDescription)"
        )
    }

    private func waitForPinLayerSize(_ expectedPercent: Int, in app: XCUIApplication) -> Bool {
        let expected = "pin-layer-size:\(expectedPercent)%"
        // Re-sample the AX tree after a predicate miss; the target remains the true 1.6 far edge.
        let resampled = AXResampler.matches(expected: expected, attempts: 3, interval: 0.1) {
            let status = app.staticTexts["map.debug-pin-layer-size"]
            guard status.exists else { return nil }
            let label = status.label
            return label.hasPrefix(expected) ? expected : label
        }
        if resampled.matched {
            return true
        }

        XCTFail("Pin layer size was \(resampled.observed ?? "missing"), expected \(expectedPercent)%")
        return false
    }

    @discardableResult
    private func waitForMapToFinishLoading(in app: XCUIApplication) -> Bool {
        let loading = app.otherElements["map.loading"]
        let readiness = app.staticTexts["map.debug-readiness"]
        let sourceStatus = app.staticTexts["map.debug-source-status"]
        let featuresApplied = app.staticTexts["map.features-applied"]
        guard readiness.waitForExistence(timeout: 10) else {
            XCTFail("map.debug-readiness did not appear")
            return false
        }
        guard featuresApplied.waitForExistence(timeout: 10) else {
            let source = sourceStatus.exists ? sourceStatus.label : "source-status-missing"
            XCTFail("map.features-applied did not appear; \(readiness.label); \(source)")
            return false
        }
        return !loading.exists || loading.waitForNonExistence(timeout: 10)
    }

    private func waitForSourceFeatureCount(_ count: Int, in app: XCUIApplication) -> Bool {
        let expectedPrefix = "source applied features:\(count)"
        let result = AXValueWaiter.wait(
            matching: { $0.hasPrefix(expectedPrefix) },
            timeout: 20
        ) {
            AXElementReadback.label(for: "map.debug-source-status") {
                let current = app.staticTexts[$0]
                return (exists: current.exists, label: current.label)
            }
        }
        if !result.matched {
            XCTFail("Expected \(expectedPrefix), got \(result.observed ?? "missing source status")")
            return false
        }
        return true
    }

    private func confirmPromptRemainsAbsent(_ identifier: String, in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let result = AXExistenceWaiter.confirmContinuousAbsence(timeout: timeout, interval: 0.25) {
            app.otherElements[identifier].exists
        }
        if result.matched {
            return true
        }

        let prompt = app.otherElements[identifier]
        let description = prompt.exists ? prompt.debugDescription : "prompt was observed during polling but is no longer present"
        XCTFail("Expected \(identifier) to remain absent; observedExists=\(result.observedExists); \(description)")
        return false
    }

    private func waitForTrackSegmentCount(_ count: Int, in app: XCUIApplication) -> Bool {
        let sourceStatus = app.staticTexts["map.debug-track-source-status"]
        let expectedStatus = "track source applied segments:\(count) layer:true active-layer:true"
        let predicate = NSPredicate(format: "label == %@", expectedStatus)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: sourceStatus)
        let result = XCTWaiter.wait(for: [expectation], timeout: 10)
        if result != .completed {
            XCTFail("Expected \(expectedStatus), got \(sourceStatus.exists ? sourceStatus.label : "missing track source status")")
            return false
        }
        return true
    }

    private func waitForMapSurfaceToSettle(in app: XCUIApplication) -> Bool {
        let loading = app.otherElements["map.loading"]
        return !loading.exists || loading.waitForNonExistence(timeout: 10)
    }

    private func waitForTrackReplayCounter(
        _ label: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 10
    ) -> Bool {
        let counter = app.staticTexts["map.track-replay.counter"]
        let result = AXValueWaiter.wait(expected: label, timeout: timeout) {
            counter.exists ? counter.label : nil
        }
        if !result.matched {
            XCTFail("Expected replay counter \(label), got \(result.observed ?? "missing counter")")
            return false
        }
        return true
    }

    private func waitForTrackReplayArrival(
        prefix: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 10
    ) -> Bool {
        let arrival = element(identifier: "map.track-replay.arrival", in: app)
        let predicate = NSPredicate(format: "exists == true AND label BEGINSWITH %@", prefix)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: arrival)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        if result != .completed {
            XCTFail("Expected replay arrival starting \(prefix), got \(arrival.exists ? arrival.label : "missing arrival")")
            return false
        }
        return true
    }

    private func waitForButtonLabel(_ label: String, identifier: String, in app: XCUIApplication) -> Bool {
        let button = app.buttons[identifier]
        let predicate = NSPredicate(format: "exists == true AND label == %@", label)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: button)
        let result = XCTWaiter.wait(for: [expectation], timeout: 10)
        if result != .completed {
            XCTFail("Expected \(identifier) label \(label), got \(button.exists ? button.label : "missing button")")
            return false
        }
        return true
    }

    private func waitForButtonEnabled(_ enabled: Bool, identifier: String, in app: XCUIApplication) -> Bool {
        let button = app.buttons[identifier]
        let predicate = NSPredicate(format: "exists == true AND enabled == %@", NSNumber(value: enabled))
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: button)
        let result = XCTWaiter.wait(for: [expectation], timeout: 10)
        if result != .completed {
            XCTFail("Expected \(identifier) enabled \(enabled), got \(button.exists ? String(button.isEnabled) : "missing button")")
            return false
        }
        return true
    }

    private func waitForElementValue(_ value: String, identifier: String, in app: XCUIApplication) -> Bool {
        let result = AXValueWaiter.wait(expected: value, timeout: 10) {
            AXElementReadback.value(for: identifier) {
                let current = element(identifier: $0, in: app)
                return (exists: current.exists, value: { current.value as? String })
            }
        }
        if !result.matched {
            XCTFail("Expected \(identifier) value \(value), got \(result.observed ?? "missing element")")
            return false
        }
        return true
    }

    private func assertNoFrameIntersection(
        _ first: XCUIElement,
        _ second: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(
            first.frame.intersects(second.frame),
            "\(first.identifier) frame \(first.frame) intersects \(second.identifier) frame \(second.frame)",
            file: file,
            line: line
        )
    }

    private func assertVerticallyOrdered(
        _ upper: XCUIElement,
        _ lower: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertGreaterThanOrEqual(
            lower.frame.minY,
            upper.frame.maxY,
            "\(lower.identifier) frame \(lower.frame) must sit below \(upper.identifier) frame \(upper.frame)",
            file: file,
            line: line
        )
    }

    private func assertHorizontallyOrdered(
        _ leading: XCUIElement,
        _ trailing: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertGreaterThanOrEqual(
            trailing.frame.minX,
            leading.frame.maxX,
            "\(trailing.identifier) frame \(trailing.frame) must sit after \(leading.identifier) frame \(leading.frame)",
            file: file,
            line: line
        )
    }

    private func assertVerticalActionStack(
        _ buttons: [XCUIElement],
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for button in buttons {
            assertMinimumInteractiveTarget(button, file: file, line: line)
            assertContainedInAppFrame(button, in: app, file: file, line: line)
        }
        for (upper, lower) in zip(buttons, buttons.dropFirst()) {
            assertVerticallyOrdered(upper, lower, file: file, line: line)
        }
    }

    private func waitForProjectedFixturePinCount(_ count: Int, in app: XCUIApplication) -> Bool {
        let deadline = Date().addingTimeInterval(10)
        let pins = app.staticTexts.matching(identifierPrefix: "map.fixture-pin.")
        while Date() < deadline {
            if pins.count == count {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTFail("Expected \(count) projected fixture pins, got \(pins.count)")
        return false
    }

    private func waitForHitProjectedFixturePinCount(atLeast count: Int, in app: XCUIApplication) -> Bool {
        let deadline = Date().addingTimeInterval(10)
        let pins = app.staticTexts.matching(identifierPrefix: "map.fixture-pin.")
        while Date() < deadline {
            let hitCount = pins.allElementsBoundByIndex.filter { $0.label == "hit" }.count
            if hitCount >= count {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        let hitCount = pins.allElementsBoundByIndex.filter { $0.label == "hit" }.count
        XCTFail("Expected at least \(count) hit-testable projected fixture pins, got \(hitCount)")
        return false
    }

    private func waitForClusterCount(_ count: Int, in app: XCUIApplication) -> Bool {
        let deadline = Date().addingTimeInterval(10)
        let clusters = app.buttons.matching(identifierPrefix: "map.cluster.")
        while Date() < deadline {
            if clusters.count == count {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTFail("Expected \(count) clusters, got \(clusters.count)")
        return false
    }

    private func waitForClusterCount(atLeast count: Int, in app: XCUIApplication) -> Bool {
        let deadline = Date().addingTimeInterval(10)
        let clusters = app.buttons.matching(identifierPrefix: "map.cluster.")
        while Date() < deadline {
            if clusters.count >= count {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTFail("Expected at least \(count) clusters, got \(clusters.count)")
        return false
    }

    private func waitForBookmarkPixelCount(
        around pin: XCUIElement,
        in app: XCUIApplication,
        matching predicate: (Int) -> Bool,
        failure: String
    ) -> Int {
        let deadline = Date().addingTimeInterval(5)
        var observed = 0
        while Date() < deadline {
            observed = bookmarkDarkPixelCount(around: pin, in: app)
            if predicate(observed) {
                return observed
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }

        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "bookmark-pixel-miss"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTFail("\(failure); observed \(observed) dark pixels")
        return observed
    }

    private func bookmarkDarkPixelCount(around pin: XCUIElement, in app: XCUIApplication) -> Int {
        let screenshot = XCUIScreen.main.screenshot()
        guard let image = UIImage(data: screenshot.pngRepresentation)?.cgImage else { return 0 }

        let appFrame = app.windows.firstMatch.exists ? app.windows.firstMatch.frame : app.frame
        let sampleFrame = CGRect(
            x: pin.frame.midX + 1,
            y: pin.frame.minY + 1,
            width: max(1, (pin.frame.width / 2) - 2),
            height: max(1, (pin.frame.height / 2) - 2)
        ).intersection(appFrame)
        guard sampleFrame.width > 0, sampleFrame.height > 0, appFrame.width > 0, appFrame.height > 0 else {
            return 0
        }

        let width = image.width
        let height = image.height
        let scaleX = CGFloat(width) / appFrame.width
        let scaleY = CGFloat(height) / appFrame.height
        let minX = max(0, Int(((sampleFrame.minX - appFrame.minX) * scaleX).rounded(.down)))
        let maxX = min(width - 1, Int(((sampleFrame.maxX - appFrame.minX) * scaleX).rounded(.up)))
        let minY = max(0, Int(((sampleFrame.minY - appFrame.minY) * scaleY).rounded(.down)))
        let maxY = min(height - 1, Int(((sampleFrame.maxY - appFrame.minY) * scaleY).rounded(.up)))
        guard minX < maxX, minY < maxY else { return 0 }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            return 0
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var darkPixelCount = 0
        for y in minY...maxY {
            for x in minX...maxX {
                let index = y * bytesPerRow + x * bytesPerPixel
                let red = Int(pixels[index])
                let green = Int(pixels[index + 1])
                let blue = Int(pixels[index + 2])
                if red <= 80, green <= 80, blue <= 80 {
                    darkPixelCount += 1
                }
            }
        }
        return darkPixelCount
    }

    private func waitForClusterPinPixels(in app: XCUIApplication) -> Bool {
        let deadline = Date().addingTimeInterval(10)
        let clusters = app.buttons.matching(identifierPrefix: "map.cluster.")
        while Date() < deadline {
            let cluster = clusters.firstMatch
            if cluster.exists, screenshotContainsClusterPinPixels(around: cluster, in: app) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }

        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "cluster-pixel-miss"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTFail("Expected rendered orange cluster bubble pixels in the screenshot")
        return false
    }

    private func screenshotContainsClusterPinPixels(around cluster: XCUIElement, in app: XCUIApplication) -> Bool {
        let screenshot = XCUIScreen.main.screenshot()
        guard let image = UIImage(data: screenshot.pngRepresentation)?.cgImage else { return false }

        let appFrame = app.windows.firstMatch.exists ? app.windows.firstMatch.frame : app.frame
        let sampleFrame = cluster.frame.insetBy(dx: -12, dy: -12).intersection(appFrame)
        guard sampleFrame.width > 0, sampleFrame.height > 0, appFrame.width > 0, appFrame.height > 0 else {
            return false
        }

        let width = image.width
        let height = image.height
        let scaleX = CGFloat(width) / appFrame.width
        let scaleY = CGFloat(height) / appFrame.height
        let minX = max(0, Int(((sampleFrame.minX - appFrame.minX) * scaleX).rounded(.down)))
        let maxX = min(width - 1, Int(((sampleFrame.maxX - appFrame.minX) * scaleX).rounded(.up)))
        let minY = max(0, Int(((sampleFrame.minY - appFrame.minY) * scaleY).rounded(.down)))
        let maxY = min(height - 1, Int(((sampleFrame.maxY - appFrame.minY) * scaleY).rounded(.up)))
        guard minX < maxX, minY < maxY else { return false }

        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            return false
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var orangePixelCount = 0
        for y in minY...maxY {
            for x in minX...maxX {
                let index = y * bytesPerRow + x * bytesPerPixel
                let red = Int(pixels[index])
                let green = Int(pixels[index + 1])
                let blue = Int(pixels[index + 2])
                if red >= 175, green >= 45, green <= 130, blue <= 95, red - green >= 60 {
                    orangePixelCount += 1
                    if orangePixelCount >= 20 {
                        return true
                    }
                }
            }
        }
        return false
    }

    private func clusteredPlaceCount(in app: XCUIApplication) -> Int {
        app.buttons.matching(identifierPrefix: "map.cluster.").allElementsBoundByIndex.reduce(0) { total, element in
            total + (Int(element.label.split(separator: " ").first ?? "") ?? 0)
        }
    }

    private func normalizedPoint(from value: String) -> (x: Double, y: Double) {
        let parts = value.split(separator: " ")
        let values = Dictionary(uniqueKeysWithValues: parts.compactMap { part -> (String, Double)? in
            let pair = part.split(separator: ":")
            guard pair.count == 2, let value = Double(pair[1]) else { return nil }
            return (String(pair[0]), value)
        })
        return (values["x"] ?? -1, values["y"] ?? -1)
    }

    @discardableResult
    private func attachScreenshot(
        named name: String,
        forceExport: Bool = false
    ) -> XCUIScreenshot {
        let screenshot = XCUIScreen.main.screenshot()
        attachScreenshot(screenshot, named: name, forceExport: forceExport)
        return screenshot
    }

    private func attachScreenshot(
        _ screenshot: XCUIScreenshot,
        named name: String,
        forceExport: Bool = false
    ) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        exportScreenshot(screenshot, named: name, force: forceExport)
    }

    private func exportScreenshot(
        _ screenshot: XCUIScreenshot,
        named name: String,
        force: Bool = false
    ) {
        guard force || ProcessInfo.processInfo.environment["MAKING_TRACKS_EXPORT_UI_TEST_SCREENSHOTS"] == "1" else {
            return
        }
        guard let exportName = screenshotExportNames[name] else {
            XCTFail("No screenshot export name configured for \(name)")
            return
        }
        let directory = uiTestArtifactDirectory(for: name)
        let fileURL = directory.appendingPathComponent(exportName).appendingPathExtension("png")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try screenshot.pngRepresentation.write(to: fileURL)
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let byteCount = attributes[.size] as? UInt64 ?? 0
            XCTAssertGreaterThan(byteCount, 0, "Exported screenshot should not be empty: \(fileURL.path)")
        } catch {
            XCTFail("Failed to export screenshot \(name): \(error)")
        }
    }

    private func exportMeasurements(
        named name: String,
        elements: [(String, XCUIElement)],
        notes: [String] = []
    ) {
        let directory = uiTestArtifactDirectory(for: name)
        let fileURL = directory.appendingPathComponent(name).appendingPathExtension("txt")
        let frames = elements.map { label, element in
            let frame = element.frame
            return String(
                format: "%@: x=%.2f y=%.2f width=%.2f height=%.2f",
                label,
                frame.minX,
                frame.minY,
                frame.width,
                frame.height
            )
        }
        let contents = (["capture: \(name)"] + notes + frames).joined(separator: "\n") + "\n"
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            XCTFail("Failed to export measurements for \(name): \(error)")
        }
    }

    private func waitForFile(at url: URL, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: url.path) {
                return true
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private func exportTextArtifact(named name: String, contents: String) {
        let directory = uiTestArtifactDirectory(for: name)
        let fileURL = directory.appendingPathComponent(name).appendingPathExtension("txt")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try contents.write(to: fileURL, atomically: true, encoding: .utf8)
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let byteCount = attributes[.size] as? UInt64 ?? 0
            XCTAssertGreaterThan(byteCount, 0, "Exported text artifact should not be empty: \(fileURL.path)")
        } catch {
            XCTFail("Failed to export text artifact \(name): \(error)")
        }
    }

    private func uiTestArtifactDirectory(for _: String) -> URL {
        UITestArtifactDirectorySelector.directory(
            environment: ProcessInfo.processInfo.environment
        )
    }

    @discardableResult
    private func scrollToExistence(of element: XCUIElement, in app: XCUIApplication) -> Bool {
        var observationTimeout: TimeInterval = 2
        return AXBoundedScroller.acquire(
            maxScrolls: 5,
            observe: {
                element.waitForExistence(timeout: observationTimeout) ? .hittable : .missing
            },
            scroll: {
                scrollTarget(in: app).swipeUp()
                observationTimeout = 1
            }
        ).matched
    }

    @discardableResult
    private func scrollToHittable(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        scrollToHittableMatch(element, in: app, maxScrolls: 5).matched
    }

    private func scrollToHittableMatch(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maxScrolls: Int
    ) -> AXScrollMatch {
        var observationTimeout: TimeInterval = 2

        return AXBoundedScroller.acquire(
            maxScrolls: maxScrolls,
            observe: {
                guard element.waitForExistence(timeout: observationTimeout) else {
                    return .missing
                }
                return element.isHittable ? .hittable : .presentNotHittable
            },
            scroll: {
                scrollTarget(in: app).swipeUp()
                observationTimeout = 1
            }
        )
    }

    @discardableResult
    private func scrollToFullyContained(
        _ element: XCUIElement,
        in app: XCUIApplication,
        requireHittable: Bool = true,
        maxSwipes: Int = 5
    ) -> Bool {
        func isFullyContained() -> Bool {
            element.exists
                && (!requireHittable || element.isHittable)
                && app.frame.contains(element.frame)
        }

        if element.waitForExistence(timeout: 2), isFullyContained() {
            return true
        }

        for _ in 0..<maxSwipes {
            scrollTarget(in: app).swipeUp()
            if element.waitForExistence(timeout: 1), isFullyContained() {
                return true
            }
        }

        return isFullyContained()
    }

    private func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func scrollTarget(in app: XCUIApplication) -> XCUIElement {
        let scrollView = app.scrollViews.firstMatch
        if scrollView.exists {
            return scrollView
        }
        return app
    }

    private func pinSizeAccessibilityValue(for multiplier: Double) -> String {
        "\(Int((multiplier * 100).rounded()))%"
    }

    private func element(identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@", identifier))
            .firstMatch
    }

    private func assertDoesNotExposeURL(
        _ element: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let value = element.value as? String ?? ""
        XCTAssertFalse(element.label.localizedCaseInsensitiveContains("http"), file: file, line: line)
        XCTAssertFalse(value.localizedCaseInsensitiveContains("http"), file: file, line: line)
    }

    private func waitForNonExistence(of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForFixtureHidden(_ hidden: Bool, in app: XCUIApplication) -> Bool {
        let element = app.staticTexts["debug.fixture-hidden-state"]
        let predicate = NSPredicate(format: "exists == true AND label == %@", "Fixture hidden: \(hidden)")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }

    private func assertVerticallyOrdered(
        _ orderedElements: [(name: String, element: XCUIElement)],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for (previous, current) in zip(orderedElements, orderedElements.dropFirst()) {
            XCTAssertLessThan(
                previous.element.frame.minY,
                current.element.frame.minY,
                "\(previous.name) should appear above \(current.name)",
                file: file,
                line: line
            )
        }
    }

    private func buildCommitLabel(in app: XCUIApplication) throws -> String {
        let element = app.staticTexts["credits.build-commit"]
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        return element.label
    }

    private func currentGitCommit() throws -> String {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: "BuildInfo", withExtension: "plist"))
        let data = try Data(contentsOf: url)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
        )
        let commit = try XCTUnwrap(plist["GitCommit"])
        XCTAssertFalse(commit.isEmpty)
        return commit
    }

    private func expectedAppVersionLabel() throws -> String {
        let plistURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Info.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        let version = (plist["CFBundleShortVersionString"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let build = (plist["CFBundleVersion"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        switch (version, build) {
        case let (.some(version), .some(build)):
            return "Version \(version) (\(build))"
        case let (.some(version), nil):
            return "Version \(version)"
        case let (nil, .some(build)):
            return "Version \(build)"
        case (nil, nil):
            return "Version unknown"
        }
    }

    private let screenshotExportNames: [String: String] = [
        "card-open": "attribution-card-sheet",
        "nearby-prompt": "nearby-prompt",
        "locate-me-chrome": "locate-me-chrome",
        "map-home-chrome-defined-paper": "map-home-chrome-defined-paper",
        "map-home-chrome-snow": "map-home-chrome-snow",
        "map-home-chrome-street-contrast": "map-home-chrome-street-contrast",
        "map-home-chrome-verdant-kl": "map-home-chrome-verdant-kl",
        "map-home-chrome-snow-filtered": "map-home-chrome-snow-filtered",
        "map-location-off": "denied-settings",
        "place-card-a11y": "place-card-a11y",
        "place-card-r15-default-unsaved-unseen": "place-card-r15-default-unsaved-unseen",
        "place-card-r15-default-unsaved-seen": "place-card-r15-default-unsaved-seen",
        "place-card-r15-default-unsaved-loved": "place-card-r15-default-unsaved-loved",
        "place-card-r15-default-saved-unseen": "place-card-r15-default-saved-unseen",
        "place-card-r15-default-saved-seen": "place-card-r15-default-saved-seen",
        "place-card-r15-default-saved-loved": "place-card-r15-default-saved-loved",
        "place-card-r15-default-hidden-unseen": "place-card-r15-default-hidden-unseen",
        "place-card-r15-default-hidden-seen": "place-card-r15-default-hidden-seen",
        "place-card-r15-default-hidden-loved": "place-card-r15-default-hidden-loved",
        "place-card-r15-ax-unsaved-unseen": "place-card-r15-ax-unsaved-unseen",
        "place-card-r15-ax-unsaved-seen": "place-card-r15-ax-unsaved-seen",
        "place-card-r15-ax-unsaved-loved": "place-card-r15-ax-unsaved-loved",
        "place-card-r15-ax-saved-unseen": "place-card-r15-ax-saved-unseen",
        "place-card-r15-ax-saved-seen": "place-card-r15-ax-saved-seen",
        "place-card-r15-ax-saved-loved": "place-card-r15-ax-saved-loved",
        "place-card-r15-ax-hidden-unseen": "place-card-r15-ax-hidden-unseen",
        "place-card-r15-ax-hidden-seen": "place-card-r15-ax-hidden-seen",
        "place-card-r15-ax-hidden-loved": "place-card-r15-ax-hidden-loved",
        "credits-a11y": "credits-a11y",
        "t2.10-about": "t2.10-about",
        "t2.10-software-licences": "t2.10-software-licences",
        "t2.10-data-licences": "t2.10-data-licences",
        "t2.10-about-ax": "t2.10-about-ax",
        "t2.10-software-licences-ax": "t2.10-software-licences-ax",
        "t2.10-data-licences-ax": "t2.10-data-licences-ax",
        "t2.9-settings-root": "t2.9-settings-root",
        "t2.9-settings-root-ax": "t2.9-settings-root-ax",
        "snow-theme-lock-appearance-light": "snow-theme-lock-appearance-light",
        "snow-theme-lock-appearance-dark": "snow-theme-lock-appearance-dark",
        "snow-theme-lock-appearance-legacy-light": "snow-theme-lock-appearance-legacy-light",
        "snow-theme-lock-appearance-legacy-dark": "snow-theme-lock-appearance-legacy-dark",
        "snow-theme-lock-map-data-light": "snow-theme-lock-map-data-light",
        "snow-theme-lock-map-data-dark": "snow-theme-lock-map-data-dark",
        "snow-theme-lock-map-data-legacy-light": "snow-theme-lock-map-data-legacy-light",
        "snow-theme-lock-map-data-legacy-dark": "snow-theme-lock-map-data-legacy-dark",
        "snow-theme-lock-location-light": "snow-theme-lock-location-light",
        "snow-theme-lock-location-dark": "snow-theme-lock-location-dark",
        "snow-theme-lock-location-legacy-light": "snow-theme-lock-location-legacy-light",
        "snow-theme-lock-location-legacy-dark": "snow-theme-lock-location-legacy-dark",
        "diagnostics-preprepare-exclusions-dark": "diagnostics-preprepare-exclusions-dark",
        "tracks-static-geometry": "tracks-static-geometry",
        "explore-door-default": "explore-door-default",
        "t2.3-door-glyph-before-default": "t2.3-door-glyph-before-default",
        "t2.3-door-glyph-after-default": "t2.3-door-glyph-after-default",
        "t2.3-door-glyph-before-ax": "t2.3-door-glyph-before-ax",
        "t2.3-door-glyph-after-ax": "t2.3-door-glyph-after-ax",
        "explore-door-ax": "explore-door-ax",
        "explore-door-scope-default": "explore-door-scope-default",
        "explore-door-scope-adjusted": "explore-door-scope-adjusted",
        "journal-door-default": "journal-door-default",
        "journal-door-ax": "journal-door-ax",
        "loved-hidden-door": "loved-hidden-door",
        "loved-places": "loved-places",
        "hidden-places": "hidden-places",
        "loved-hidden-ax": "loved-hidden-ax",
        "a6-hidden-actions": "a6-hidden-actions",
        "a6-hidden-actions-ax": "a6-hidden-actions-ax",
        "tracks-unified-visit-editing": "tracks-unified-visit-editing",
        "my-tracks-rendered-oracle-light": "my-tracks-rendered-oracle-light",
        "my-tracks-rendered-oracle-dark": "my-tracks-rendered-oracle-dark",
        "my-tracks-visit-date-oracle-light": "my-tracks-visit-date-oracle-light",
        "my-tracks-visit-date-oracle-dark": "my-tracks-visit-date-oracle-dark",
        "list-map-polished-chrome": "list-map-polished-chrome",
        "list-map-spread-fit": "list-map-spread-fit",
        "my-tracks-burst-readout": "my-tracks-burst-readout",
        "explore-scope-list-open": "explore-scope-list-open",
        "explore-scope-other-lists": "explore-scope-other-lists",
        "explore-scope-other-lists-ax": "explore-scope-other-lists-ax",
        "explore-scope-other-lists-empty": "explore-scope-other-lists-empty",
        "track-replay-pin-arrival": "track-replay-pin-arrival",
        "track-replay-scrub-frame-00": "track-replay-scrub-frame-00",
        "track-replay-scrub-frame-01": "track-replay-scrub-frame-01",
        "track-replay-scrub-frame-02": "track-replay-scrub-frame-02",
        "track-replay-scrub-frame-03": "track-replay-scrub-frame-03",
        "track-replay-scrub-frame-04": "track-replay-scrub-frame-04",
        "track-replay-scrub-frame-05": "track-replay-scrub-frame-05",
        "pin-defined-paper-min": "pin-defined-paper-min",
        "pin-defined-paper-default": "pin-defined-paper-default",
        "pin-defined-paper-max": "pin-defined-paper-max",
        "pin-snow-min": "pin-snow-min",
        "pin-snow-default": "pin-snow-default",
        "pin-snow-max": "pin-snow-max",
        "pin-clustering-city": "pin-clustering-city",
        "pin-clustering-expanded": "pin-clustering-expanded",
        "pin-clustering-street": "pin-clustering-street",
        "coverage-edge-defined-paper": "coverage-edge-defined-paper",
        "coverage-edge-snow": "coverage-edge-snow",
        "coverage-edge-street-contrast": "coverage-edge-street-contrast",
        "coverage-edge-verdant-kl": "coverage-edge-verdant-kl",
    ]
}

private extension XCUIElementQuery {
    func matching(identifierPrefix prefix: String) -> XCUIElementQuery {
        matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
    }
}
