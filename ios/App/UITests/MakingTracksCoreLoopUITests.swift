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

@MainActor
private struct MyTracksAppearanceCapture {
    let raster: RenderedPixelRaster
    let trackSurfaceFrame: CGRect
    let visitDateRaster: RenderedPixelRaster
    let visitDateSurfaceFrame: CGRect
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

    func testCardTogglesPersistAndRestyleMapPin() {
        let app = launch(reset: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))

        tapFixturePin(in: map)
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
        XCTAssertTrue(waitForButtonLabel("Unlove", identifier: "place-card.loved", in: app))
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
        tapFixturePin(in: relaunchedMap)
        XCTAssertTrue(relaunched.staticTexts["Ghost Sign"].waitForExistence(timeout: 5))
        XCTAssertEqual(relaunched.buttons["place-card.save"].label, "Saved")
        XCTAssertTrue(waitForButtonLabel("Unlove", identifier: "place-card.loved", in: relaunched))
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

        openAppMenu(in: app)
        app.buttons["menu.row.settings"].tap()
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

    func testPlaceCardOverhaulRendersHierarchyAndHideAction() {
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
        let hideButton = actionBar.buttons["place-card.hide"]
        XCTAssertTrue(actionBar.waitForExistence(timeout: 5))
        XCTAssertEqual(actionBar.buttons.count, 3)
        XCTAssertTrue(saveButton.exists)
        XCTAssertTrue(seenButton.exists)
        XCTAssertTrue(hideButton.exists)
        XCTAssertTrue(app.buttons["place-card.more"].exists)
        app.buttons["place-card.more"].tap()
        let addToListButton = app.buttons["place-card.add-to-list"]
        XCTAssertTrue(addToListButton.waitForExistence(timeout: 5))
        addToListButton.tap()
        XCTAssertTrue(app.navigationBars["Add to list"].waitForExistence(timeout: 5))
        app.buttons["list-picker.done"].tap()
        XCTAssertFalse(app.buttons["place-card.add-to-list"].exists)
        XCTAssertEqual(seenButton.label, "Seen")
        XCTAssertEqual(hideButton.label, "Hide")
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

        hideButton.tap()
        XCTAssertTrue(app.staticTexts["Hidden — Undo"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Ghost Sign"].waitForExistence(timeout: 2))

        tapFixturePin(in: map)
        XCTAssertFalse(app.staticTexts["Ghost Sign"].waitForExistence(timeout: 2))
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

        openAppMenu(in: app)
        app.buttons["menu.row.lists"].tap()
        XCTAssertTrue(app.staticTexts["Lists"].waitForExistence(timeout: 5))
        let dateNight = app.staticTexts["Date night"]
        XCTAssertTrue(dateNight.waitForExistence(timeout: 5))
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
        XCTAssertTrue(waitForNonExistence(of: dateNight, timeout: 5))
        app.buttons["menu.done"].tap()

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
        app.textFields["list-picker.new-name"].tap()
        app.textFields["list-picker.new-name"].typeText("KL walk")
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

        openAppMenu(in: app)
        app.buttons["menu.row.lists"].tap()
        XCTAssertTrue(app.staticTexts["Lists"].waitForExistence(timeout: 5))
        app.buttons["lists.create"].tap()
        let listsError = app.staticTexts["lists.error"]
        XCTAssertTrue(listsError.waitForExistence(timeout: 5))
        XCTAssertEqual(listsError.label, "Enter a list name.")
        XCTAssertTrue(app.staticTexts["KL walk"].waitForExistence(timeout: 5))
        app.staticTexts["KL walk"].tap()

        XCTAssertTrue(app.staticTexts["lists.detail.progress"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["lists.detail.progress"].label, "you've been to 1 of these · all seen")
        XCTAssertTrue(app.buttons["lists.detail.show-map"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Ghost Sign"].waitForExistence(timeout: 5))
        app.buttons["lists.detail.show-map"].tap()

        XCTAssertTrue(app.staticTexts["map.list-mode.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["map.list-mode.title"].label, "KL walk")
        XCTAssertTrue(app.buttons["map.list-mode.back"].exists)
        XCTAssertFalse(app.buttons["map.list-mode.close"].exists)
        XCTAssertFalse(app.buttons["map.menu"].exists)
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
        let layersButton = app.buttons["map.layers"]
        XCTAssertTrue(layersButton.waitForExistence(timeout: 5))
        layersButton.tap()
        XCTAssertTrue(app.navigationBars["Layers"].waitForExistence(timeout: 5))
        app.buttons["map.layers.done"].tap()
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

    func testTracksMenuOpensUnifiedMyTracksVisitEditor() {
        let app = launch(reset: true, pinDiagnostics: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMapToFinishLoading(in: app))
        openFixtureCard(in: map, app: app)

        app.buttons["place-card.visited"].tap()
        closePlaceCard(in: app)

        openAppMenu(in: app)
        XCTAssertTrue(app.buttons["menu.row.tracks"].waitForExistence(timeout: 5))
        app.buttons["menu.row.tracks"].tap()

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
        openAppMenu(in: app)
        app.buttons["menu.row.tracks"].tap()

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
        openAppMenu(in: app)
        app.buttons["menu.row.tracks"].tap()

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
        openAppMenu(in: app)
        app.buttons["menu.row.tracks"].tap()

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
        openAppMenu(in: app)
        app.buttons["menu.row.tracks"].tap()

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
        let comparisonFrame = light.trackSurfaceFrame
            .intersection(dark.trackSurfaceFrame)
            .insetBy(dx: 1, dy: 1)
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
        openAppMenu(in: app)
        app.buttons["menu.row.lists"].tap()
        XCTAssertTrue(app.staticTexts["Lists"].waitForExistence(timeout: 5))
        app.staticTexts["My tracks"].tap()

        let trackSurface = app.collectionViews["lists.detail.surface.track"]
        XCTAssertTrue(trackSurface.waitForExistence(timeout: 5))
        app.buttons["lists.detail.show-map"].tap()
        XCTAssertTrue(app.staticTexts["map.list-mode.title"].waitForExistence(timeout: 5))

        let filter = element(identifier: "map.list-mode.filter.loved", in: app)
        XCTAssertTrue(filter.waitForExistence(timeout: 5))
        filter.tap()
        XCTAssertTrue(app.otherElements["track-filter-picker.sheet"].waitForExistence(timeout: 5))
        let category = app.buttons["track-filter-picker.category.historic_building"]
        XCTAssertTrue(scrollToHittable(category, in: app))
        category.tap()
        let apply = app.buttons["track-filter-picker.apply"]
        XCTAssertTrue(apply.waitForExistence(timeout: 5))
        apply.tap()

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
        openAppMenu(in: app)
        app.buttons["menu.row.tracks"].tap()
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

    func testTracksMenuAndListsMyTracksReachSameScreenIdentity() {
        let fromMenu = launch(reset: true, pinDiagnostics: true)
        XCTAssertTrue(fromMenu.otherElements["map.surface"].waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMapToFinishLoading(in: fromMenu))
        openAppMenu(in: fromMenu)
        fromMenu.buttons["menu.row.tracks"].tap()
        XCTAssertTrue(fromMenu.collectionViews["lists.detail.surface.track"].waitForExistence(timeout: 5))
        fromMenu.buttons["lists.detail.track.back"].tap()
        XCTAssertTrue(fromMenu.navigationBars["Menu"].waitForExistence(timeout: 5))
        fromMenu.buttons["menu.row.tracks"].tap()
        XCTAssertTrue(fromMenu.collectionViews["lists.detail.surface.track"].waitForExistence(timeout: 5))
        fromMenu.buttons["lists.detail.track.done"].tap()
        XCTAssertTrue(fromMenu.otherElements["map.surface"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            waitForNonExistence(
                of: fromMenu.collectionViews["lists.detail.surface.track"],
                timeout: 5
            )
        )

        let fromLists = launch(reset: true, pinDiagnostics: true)
        XCTAssertTrue(fromLists.otherElements["map.surface"].waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMapToFinishLoading(in: fromLists))
        openAppMenu(in: fromLists)
        fromLists.buttons["menu.row.lists"].tap()
        XCTAssertTrue(fromLists.staticTexts["Lists"].waitForExistence(timeout: 5))
        fromLists.staticTexts["My tracks"].tap()
        XCTAssertTrue(fromLists.collectionViews["lists.detail.surface.track"].waitForExistence(timeout: 5))
        fromLists.buttons["lists.detail.track.back"].tap()
        XCTAssertTrue(fromLists.navigationBars["Lists"].waitForExistence(timeout: 5))
        XCTAssertTrue(fromLists.buttons["lists.create"].exists)
        fromLists.staticTexts["My tracks"].tap()
        XCTAssertTrue(fromLists.collectionViews["lists.detail.surface.track"].waitForExistence(timeout: 5))
        fromLists.buttons["lists.detail.track.done"].tap()
        XCTAssertTrue(fromLists.otherElements["map.surface"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            waitForNonExistence(
                of: fromLists.collectionViews["lists.detail.surface.track"],
                timeout: 5
            )
        )
    }

    func testTrackGeometryDrawsConnectorFromSeededFixtureVisits() {
        let app = launch(reset: true, pinDiagnostics: true, seedTrackList: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMapToFinishLoading(in: app))
        XCTAssertTrue(waitForTrackSegmentCount(0, in: app))

        openAppMenu(in: app)
        app.buttons["menu.row.lists"].tap()
        XCTAssertTrue(app.staticTexts["Lists"].waitForExistence(timeout: 5))
        app.staticTexts["Track pair"].tap()
        XCTAssertTrue(app.buttons["lists.detail.show-map"].waitForExistence(timeout: 5))
        app.buttons["lists.detail.show-map"].tap()
        XCTAssertTrue(app.staticTexts["map.list-mode.title"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForSourceFeatureCount(2, in: app))
        XCTAssertTrue(waitForTrackSegmentCount(1, in: app))
        attachScreenshot(named: "tracks-static-geometry")
    }

    func testOpeningMenuDismissesOpenPlaceCardBeforeReplayEntry() {
        let app = launch(reset: true, pinDiagnostics: true, seedMultiDayTrackList: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForMapToFinishLoading(in: app))

        openFixtureCard(in: map, app: app)
        let card = app.scrollViews.matching(identifierPrefix: "place-card.instance.").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))

        openAppMenu(in: app)
        XCTAssertTrue(waitForNonExistence(of: card, timeout: 5), card.debugDescription)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifierPrefix: "place-card.").firstMatch.exists)

        app.buttons["menu.row.lists"].tap()
        XCTAssertTrue(app.staticTexts["Lists"].waitForExistence(timeout: 5))
        app.staticTexts["Replay week"].tap()
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

        openAppMenu(in: app)
        app.buttons["menu.row.lists"].tap()
        XCTAssertTrue(app.staticTexts["Lists"].waitForExistence(timeout: 5))
        app.staticTexts["Replay week"].tap()
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

        openAppMenu(in: app)
        app.buttons["menu.row.lists"].tap()
        XCTAssertTrue(app.staticTexts["Lists"].waitForExistence(timeout: 5))
        app.staticTexts["Replay week"].tap()
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

        openAppMenu(in: app)
        app.buttons["menu.row.lists"].tap()
        XCTAssertTrue(app.staticTexts["Lists"].waitForExistence(timeout: 5))
        app.staticTexts["Replay week"].tap()

        XCTAssertTrue(app.buttons["lists.detail.show-map"].waitForExistence(timeout: 5))
        app.buttons["lists.detail.show-map"].tap()
        XCTAssertTrue(app.staticTexts["map.list-mode.title"].waitForExistence(timeout: 5))

        var lovedFilter = element(identifier: "map.list-mode.filter.loved", in: app)
        XCTAssertTrue(lovedFilter.waitForExistence(timeout: 5))
        XCTAssertEqual(lovedFilter.value as? String, "Not selected")
        lovedFilter.tap()
        XCTAssertTrue(app.otherElements["track-filter-picker.sheet"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForElementValue("Not selected", identifier: "track-filter-picker.loved", in: app))
        app.buttons["track-filter-picker.loved"].tap()
        XCTAssertTrue(waitForElementValue("Selected", identifier: "track-filter-picker.loved", in: app))
        XCTAssertTrue(waitForButtonLabel("Show 0 visits", identifier: "track-filter-picker.apply", in: app))
        app.buttons["track-filter-picker.apply"].tap()
        XCTAssertTrue(waitForElementValue("Selected", identifier: "map.list-mode.filter.loved", in: app))
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

        openAppMenu(in: lovedApp)
        lovedApp.buttons["menu.row.lists"].tap()
        XCTAssertTrue(lovedApp.staticTexts["Lists"].waitForExistence(timeout: 5))
        lovedApp.staticTexts["Replay week"].tap()
        XCTAssertTrue(lovedApp.buttons["lists.detail.show-map"].waitForExistence(timeout: 5))
        lovedApp.buttons["lists.detail.show-map"].tap()

        XCTAssertTrue(lovedApp.staticTexts["map.list-mode.title"].waitForExistence(timeout: 5))
        lovedFilter = element(identifier: "map.list-mode.filter.loved", in: lovedApp)
        XCTAssertTrue(lovedFilter.waitForExistence(timeout: 5))
        assertListMapFilterChromePlacement(lovedFilter, in: lovedApp)
        lovedFilter.tap()
        XCTAssertTrue(lovedApp.otherElements["track-filter-picker.sheet"].waitForExistence(timeout: 5))
        attachScreenshot(named: "track-filter-picker-open")
        XCTAssertTrue(waitForElementValue("Not selected", identifier: "track-filter-picker.loved", in: lovedApp))
        lovedApp.buttons["track-filter-picker.loved"].tap()
        XCTAssertTrue(waitForElementValue("Selected", identifier: "track-filter-picker.loved", in: lovedApp))
        XCTAssertTrue(waitForButtonLabel("Show 1 visit", identifier: "track-filter-picker.apply", in: lovedApp))
        lovedApp.buttons["track-filter-picker.apply"].tap()
        XCTAssertTrue(waitForSourceFeatureCount(1, in: lovedApp))
        XCTAssertTrue(waitForTrackSegmentCount(0, in: lovedApp))
        attachScreenshot(named: "track-loved-filter-map-source")
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

        openAppMenu(in: app)
        app.buttons["menu.row.lists"].tap()
        XCTAssertTrue(app.staticTexts["Lists"].waitForExistence(timeout: 5))
        app.staticTexts["Replay week"].tap()
        XCTAssertTrue(app.buttons["lists.detail.show-map"].waitForExistence(timeout: 5))
        app.buttons["lists.detail.show-map"].tap()
        XCTAssertTrue(app.staticTexts["map.list-mode.title"].waitForExistence(timeout: 5))

        let filter = element(identifier: "map.list-mode.filter.loved", in: app)
        XCTAssertTrue(filter.waitForExistence(timeout: 5))
        assertListMapFilterChromePlacement(filter, in: app)
        filter.tap()
        XCTAssertTrue(app.otherElements["track-filter-picker.sheet"].waitForExistence(timeout: 5))
        XCTAssertTrue(scrollToHittable(app.buttons["track-filter-picker.category.attraction"], in: app))
        app.buttons["track-filter-picker.category.attraction"].tap()
        XCTAssertTrue(waitForButtonLabel("Show 1 visit", identifier: "track-filter-picker.apply", in: app))
        app.buttons["track-filter-picker.apply"].tap()

        XCTAssertTrue(waitForElementValue("Selected", identifier: "map.list-mode.filter.category.attraction", in: app))
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
        assertListMapFilterChromePlacement(element(identifier: "map.list-mode.filter.category.attraction", in: app), in: app)
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
        let activeFilter = element(identifier: "map.list-mode.filter.category.attraction", in: app)
        XCTAssertTrue(activeFilter.waitForExistence(timeout: 5))
        activeFilter.tap()
        XCTAssertTrue(app.otherElements["track-filter-picker.sheet"].waitForExistence(timeout: 5))
        XCTAssertTrue(scrollToHittable(app.buttons["track-filter-picker.category.attraction"], in: app))
        app.buttons["track-filter-picker.category.attraction"].tap()
        XCTAssertTrue(waitForButtonLabel("Show 6 visits", identifier: "track-filter-picker.apply", in: app))
        app.buttons["track-filter-picker.apply"].tap()

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
        openAppMenu(in: app)
        app.buttons["menu.row.lists"].tap()
        XCTAssertTrue(app.staticTexts["Lists"].waitForExistence(timeout: 5))
        app.staticTexts["My tracks"].tap()
        XCTAssertTrue(app.collectionViews["lists.detail.surface.track"].waitForExistence(timeout: 5))
        app.buttons["lists.detail.show-map"].tap()
        XCTAssertTrue(app.staticTexts["map.list-mode.title"].waitForExistence(timeout: 5))

        let filter = element(identifier: "map.list-mode.filter.loved", in: app)
        XCTAssertTrue(filter.waitForExistence(timeout: 5))
        filter.tap()
        XCTAssertTrue(app.otherElements["track-filter-picker.sheet"].waitForExistence(timeout: 5))
        let attraction = app.buttons["track-filter-picker.category.attraction"]
        XCTAssertTrue(scrollToHittable(attraction, in: app))
        attraction.tap()
        XCTAssertTrue(waitForButtonLabel("Show 2 visits", identifier: "track-filter-picker.apply", in: app))
        app.buttons["track-filter-picker.apply"].tap()

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

    func testLayersCategoryFilterScopesReplayTimelineAndAutoplay() {
        let app = launch(
            reset: true,
            seedVisitsEditorVisual: true,
            trackReplayBeatDuration: 5
        )

        XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 10))
        openAppMenu(in: app)
        app.buttons["menu.row.lists"].tap()
        XCTAssertTrue(app.staticTexts["Lists"].waitForExistence(timeout: 5))
        app.staticTexts["My tracks"].tap()
        XCTAssertTrue(app.collectionViews["lists.detail.surface.track"].waitForExistence(timeout: 5))
        app.buttons["lists.detail.show-map"].tap()
        XCTAssertTrue(app.staticTexts["map.list-mode.title"].waitForExistence(timeout: 5))

        openLayers(in: app)
        let toggleAll = app.buttons["map.layers.show-all-categories"]
        XCTAssertTrue(scrollToHittable(toggleAll, in: app))
        XCTAssertEqual(toggleAll.label, "Hide all categories")
        toggleAll.tap()
        XCTAssertTrue(waitForButtonLabel(
            "Show all categories",
            identifier: "map.layers.show-all-categories",
            in: app
        ))

        let attraction = "map.layers.category.attraction"
        XCTAssertTrue(scrollToHittable(app.switches[attraction], in: app))
        tapSwitch(in: app, identifier: attraction, expectedValue: "1")
        app.buttons["map.layers.done"].tap()

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

    func testLayersOtherCategoryScopesReplayToFallbackVisits() {
        let app = launch(
            reset: true,
            seedVisitsEditorVisual: true,
            trackReplayBeatDuration: 5
        )

        XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 10))
        openAppMenu(in: app)
        app.buttons["menu.row.lists"].tap()
        XCTAssertTrue(app.staticTexts["Lists"].waitForExistence(timeout: 5))
        app.staticTexts["My tracks"].tap()
        XCTAssertTrue(app.collectionViews["lists.detail.surface.track"].waitForExistence(timeout: 5))
        app.buttons["lists.detail.show-map"].tap()
        XCTAssertTrue(app.staticTexts["map.list-mode.title"].waitForExistence(timeout: 5))

        openLayers(in: app)
        let toggleAll = app.buttons["map.layers.show-all-categories"]
        XCTAssertTrue(scrollToHittable(toggleAll, in: app))
        toggleAll.tap()

        let other = "map.layers.category.uncategorized"
        XCTAssertTrue(scrollToHittable(app.switches[other], in: app))
        tapSwitch(in: app, identifier: other, expectedValue: "1")
        app.buttons["map.layers.done"].tap()

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

    func testFilterTracksExplicitlyReturnsFromNoCategoriesToAll() {
        let app = launch(reset: true, seedVisitsEditorVisual: true)

        XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 10))
        openAppMenu(in: app)
        app.buttons["menu.row.lists"].tap()
        XCTAssertTrue(app.staticTexts["Lists"].waitForExistence(timeout: 5))
        app.staticTexts["My tracks"].tap()
        XCTAssertTrue(app.collectionViews["lists.detail.surface.track"].waitForExistence(timeout: 5))
        app.buttons["lists.detail.show-map"].tap()
        XCTAssertTrue(app.staticTexts["map.list-mode.title"].waitForExistence(timeout: 5))

        openLayers(in: app)
        let toggleAll = app.buttons["map.layers.show-all-categories"]
        XCTAssertTrue(scrollToHittable(toggleAll, in: app))
        toggleAll.tap()
        app.buttons["map.layers.done"].tap()

        let filter = element(identifier: "map.list-mode.filter.loved", in: app)
        XCTAssertTrue(filter.waitForExistence(timeout: 5))
        filter.tap()
        XCTAssertTrue(app.otherElements["track-filter-picker.sheet"].waitForExistence(timeout: 5))

        let allTypes = app.buttons["track-filter-picker.category.all"]
        XCTAssertTrue(scrollToHittable(allTypes, in: app))
        XCTAssertEqual(allTypes.value as? String, "Not selected")
        XCTAssertTrue(waitForButtonLabel("Show 0 visits", identifier: "track-filter-picker.apply", in: app))
        allTypes.tap()
        XCTAssertTrue(waitForElementValue(
            "Selected",
            identifier: "track-filter-picker.category.all",
            in: app
        ))
        XCTAssertTrue(waitForButtonLabel("Show 8 visits", identifier: "track-filter-picker.apply", in: app))
        app.buttons["track-filter-picker.apply"].tap()

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

        openAppMenu(in: app)
        app.buttons["menu.row.lists"].tap()
        XCTAssertTrue(app.staticTexts["Lists"].waitForExistence(timeout: 5))
        app.staticTexts["Track pair"].tap()
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

        openAppMenu(in: app)
        app.buttons["menu.row.lists"].tap()
        XCTAssertTrue(app.staticTexts["Lists"].waitForExistence(timeout: 5))
        app.staticTexts["My tracks"].tap()
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

        openAppMenu(in: app)
        app.buttons["menu.row.lists"].tap()
        XCTAssertTrue(app.staticTexts["Lists"].waitForExistence(timeout: 5))
        app.staticTexts["Spread walk"].tap()
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
        tapFixturePin(in: map)
        XCTAssertFalse(app.staticTexts["Ghost Sign"].waitForExistence(timeout: 2))
    }

    func testHiddenToastUndoRestoresHiddenPlace() {
        let app = launch(reset: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))

        openFixtureCard(in: map, app: app)
        app.buttons["place-card.hide"].tap()
        XCTAssertTrue(app.staticTexts["Hidden — Undo"].waitForExistence(timeout: 5))

        app.buttons["place-card.hide.undo"].tap()
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

        tapFixturePin(in: map)
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

    func testLayersCanHideCategoryPins() {
        let app = launch(reset: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))

        openLayers(in: app)
        let historicBuildings = "map.layers.category.historic_building"
        XCTAssertTrue(app.switches[historicBuildings].waitForExistence(timeout: 5))
        tapSwitch(in: app, identifier: historicBuildings, expectedValue: "0")
        app.buttons["map.layers.done"].tap()

        XCTAssertTrue(waitForNonExistence(
            of: app.buttons["map.pin.mt1_00000000000000000000000001"],
            timeout: 5
        ))
        tapSecondFixturePin(in: map)
        XCTAssertFalse(app.staticTexts["Art Deco Cinema"].waitForExistence(timeout: 2))

        openLayers(in: app)
        XCTAssertTrue(app.switches[historicBuildings].waitForExistence(timeout: 5))
        tapSwitch(in: app, identifier: historicBuildings, expectedValue: "1")
        app.buttons["map.layers.done"].tap()
        XCTAssertTrue(waitForAccessibilityPin(
            in: app,
            placeID: "mt1_00000000000000000000000001",
            label: "Art Deco Cinema, Historic Building, not visited"
        ))

        openSecondFixtureCard(in: map, app: app)
        closePlaceCard(in: app)

        openFixtureCard(in: map, app: app)
    }

    func testLayersToggleAllCategoriesHidesAndRestoresPins() {
        let app = launch(reset: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))

        openLayers(in: app)
        let toggleAll = app.buttons["map.layers.show-all-categories"]
        XCTAssertTrue(scrollToHittable(toggleAll, in: app))
        XCTAssertEqual(toggleAll.label, "Hide all categories")
        toggleAll.tap()
        XCTAssertTrue(waitForButtonLabel("Show all categories", identifier: "map.layers.show-all-categories", in: app))
        app.buttons["map.layers.done"].tap()

        tapFixturePin(in: map)
        XCTAssertFalse(app.staticTexts["Ghost Sign"].waitForExistence(timeout: 2))
        tapSecondFixturePin(in: map)
        XCTAssertFalse(app.staticTexts["Art Deco Cinema"].waitForExistence(timeout: 2))

        openLayers(in: app)
        XCTAssertTrue(scrollToHittable(toggleAll, in: app))
        XCTAssertTrue(waitForButtonLabel("Show all categories", identifier: "map.layers.show-all-categories", in: app))
        toggleAll.tap()
        XCTAssertTrue(waitForButtonLabel("Hide all categories", identifier: "map.layers.show-all-categories", in: app))
        app.buttons["map.layers.done"].tap()

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
        tapFixturePin(in: map)
        XCTAssertFalse(app.staticTexts["Ghost Sign"].waitForExistence(timeout: 2))

        openLayers(in: app)
        let showHidden = "map.layers.show-hidden"
        XCTAssertTrue(app.switches[showHidden].waitForExistence(timeout: 5))
        tapSwitch(in: app, identifier: showHidden, expectedValue: "1")
        app.buttons["map.layers.done"].tap()

        openFixtureCard(in: map, app: app)
        XCTAssertTrue(app.buttons["place-card.unhide"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["place-card.hide"].exists)

        app.buttons["place-card.unhide"].tap()
        XCTAssertFalse(app.buttons["place-card.unhide"].waitForExistence(timeout: 2))
        closePlaceCard(in: app)
        openFixtureCard(in: map, app: app)
    }

    func testMenuAboutCarriesCreditsAndMapAttributionIsInert() throws {
        let app = launch(reset: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))

        XCTAssertFalse(app.buttons["map.openstreetmap-attribution"].exists)
        XCTAssertTrue(app.staticTexts["map.openstreetmap-attribution"].waitForExistence(timeout: 5))

        openAppMenu(in: app)
        XCTAssertTrue(app.staticTexts["Menu"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["menu.row.lists"].exists)
        XCTAssertTrue(app.buttons["menu.row.offline-maps"].exists)
        XCTAssertTrue(app.buttons["menu.row.settings"].exists)

        app.buttons["menu.row.about"].tap()
        XCTAssertTrue(app.staticTexts["About"].waitForExistence(timeout: 5))
        let versionLabel = app.staticTexts["about.app-version"]
        XCTAssertTrue(versionLabel.waitForExistence(timeout: 5))
        XCTAssertEqual(versionLabel.label, try expectedAppVersionLabel())
        let expectedBuildLabel = "Build \(try currentGitCommit())"
        XCTAssertTrue(app.staticTexts[expectedBuildLabel].waitForExistence(timeout: 5))
        let privacyPolicy = app.buttons["about.privacy-policy"]
        XCTAssertTrue(privacyPolicy.waitForExistence(timeout: 5))
        XCTAssertEqual(privacyPolicy.label, "Privacy policy")
        XCTAssertEqual(privacyPolicy.value as? String, "https://making-tracks.app/privacy")
        XCTAssertTrue(app.staticTexts["Open source acknowledgements"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["about.openstreetmap-copyright"].waitForExistence(timeout: 5))
        app.buttons["menu.done"].tap()
    }

    func testOfflineProgressChipDeepLinksToOfflineMaps() {
        let activeDownloadApp = launch(reset: true, offlineProgress: 0.42)
        let activeMap = activeDownloadApp.otherElements["map.surface"]
        XCTAssertTrue(activeMap.waitForExistence(timeout: 10))

        let progressChip = activeDownloadApp.buttons["map.download-progress"]
        XCTAssertTrue(progressChip.waitForExistence(timeout: 5))
        XCTAssertTrue(progressChip.label.contains("42%"))
        progressChip.tap()

        XCTAssertTrue(activeDownloadApp.staticTexts["Offline maps"].waitForExistence(timeout: 5))
        activeDownloadApp.buttons["menu.done"].tap()

        XCTAssertTrue(activeMap.waitForExistence(timeout: 5))
        openAppMenu(in: activeDownloadApp)
        XCTAssertTrue(activeDownloadApp.staticTexts["Menu"].waitForExistence(timeout: 5))
        XCTAssertTrue(activeDownloadApp.buttons["menu.row.lists"].exists)
        XCTAssertTrue(activeDownloadApp.buttons["menu.row.settings"].exists)
        activeDownloadApp.buttons["menu.done"].tap()
    }

    func testSettingsThemePickerSelectsRealTheme() {
        let app = launch(reset: true, resetTheme: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))

        openAppMenu(in: app)
        app.buttons["menu.row.settings"].tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["settings.theme.selected"].exists)
        XCTAssertTrue(app.buttons["settings.theme.defined-paper"].exists)
        XCTAssertTrue(waitForElementValue("Selected", identifier: "settings.theme.defined-paper", in: app))
        XCTAssertTrue(waitForElementValue("Not selected", identifier: "settings.theme.snow", in: app))

        let snowThemeButton = app.buttons["settings.theme.snow"]
        XCTAssertTrue(scrollToHittable(snowThemeButton, in: app))
        snowThemeButton.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertTrue(waitForElementValue("Selected", identifier: "settings.theme.snow", in: app))
        XCTAssertTrue(waitForElementValue("Not selected", identifier: "settings.theme.defined-paper", in: app))
        app.buttons["menu.done"].tap()
    }

    func testSettingsStorageRowNavigatesToOfflineMaps() {
        let app = launch(reset: true)

        XCTAssertTrue(app.otherElements["map.surface"].waitForExistence(timeout: 10))

        openAppMenu(in: app)
        app.buttons["menu.row.settings"].tap()
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
        openAppMenu(in: app)
        app.buttons["menu.row.settings"].tap()
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
        XCTAssertTrue(app.buttons["map.menu"].waitForExistence(timeout: 5))
        app.buttons["map.menu"].tap()
        app.buttons["menu.row.settings"].tap()
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
        openAppMenu(in: app)
        app.buttons["menu.row.settings"].tap()
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

        let close = app.buttons["Close"]
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

        let menuButton = app.buttons["map.menu"]
        let layersButton = app.buttons["map.layers"]
        XCTAssertTrue(menuButton.waitForExistence(timeout: 5))
        XCTAssertTrue(layersButton.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(menuButton.frame.width, 44)
        XCTAssertGreaterThanOrEqual(menuButton.frame.height, 44)
        XCTAssertGreaterThanOrEqual(layersButton.frame.width, 44)
        XCTAssertGreaterThanOrEqual(layersButton.frame.height, 44)
        XCTAssertGreaterThan(menuButton.frame.minY, 50)
        XCTAssertLessThan(menuButton.frame.minY, 120)
        XCTAssertLessThan(layersButton.frame.minY, 180)
        XCTAssertGreaterThan(layersButton.frame.minY, menuButton.frame.maxY)
        attachScreenshot(named: "map-home-chrome-defined-paper")

        for themeID in ["snow", "street-contrast", "verdant-kl"] {
            selectMapTheme(themeID, in: app)
            attachScreenshot(named: "map-home-chrome-\(themeID)")
        }

        openLayers(in: app)
        let historicBuildings = "map.layers.category.historic_building"
        XCTAssertTrue(app.switches[historicBuildings].waitForExistence(timeout: 5))
        tapSwitch(in: app, identifier: historicBuildings, expectedValue: "0")
        app.buttons["map.layers.done"].tap()
        XCTAssertEqual(layersButton.value as? String, "Custom")

        selectMapTheme("snow", in: app)

        XCTAssertTrue(map.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForMapTheme("snow", in: app))
        attachScreenshot(named: "map-home-chrome-snow-filtered")
    }

    func testCoverageShadingToggleIsDisplayOnlyLayerState() {
        let app = launch(reset: true, coverageBBoxes: ["101.640,3.090,101.690,3.190"])

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        let layersButton = app.buttons["map.layers"]
        XCTAssertTrue(layersButton.waitForExistence(timeout: 5))
        XCTAssertEqual(layersButton.value as? String, "Default")

        openLayers(in: app)
        let coverageShading = "map.layers.coverage-shading"
        XCTAssertTrue(app.switches[coverageShading].waitForExistence(timeout: 5))
        tapSwitch(in: app, identifier: coverageShading, expectedValue: "0")
        app.buttons["map.layers.done"].tap()

        XCTAssertEqual(layersButton.value as? String, "Default")

        openLayers(in: app)
        XCTAssertTrue(app.switches[coverageShading].waitForExistence(timeout: 5))
        tapSwitch(in: app, identifier: coverageShading, expectedValue: "1")
        app.buttons["map.layers.done"].tap()
        XCTAssertEqual(layersButton.value as? String, "Default")
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

        openAppMenu(in: app)
        app.buttons["menu.row.settings"].tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
        let slider = app.sliders["settings.pin-size"]
        XCTAssertTrue(scrollToHittable(slider, in: app))
        adjustSliderToTrueEdge(slider, in: app, identifier: "settings.pin-size", expectedValue: "160%")
        app.buttons["menu.done"].tap()

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
        XCTAssertGreaterThan(visitedButton.frame.minY, saveButton.frame.minY)
        XCTAssertGreaterThan(hideButton.frame.minY, visitedButton.frame.minY)

        visitedButton.tap()
        let lovedButton = actionBar.buttons["place-card.loved"]
        let unseeButton = actionBar.buttons["place-card.unsee"]
        XCTAssertTrue(lovedButton.waitForExistence(timeout: 5))
        XCTAssertTrue(unseeButton.waitForExistence(timeout: 5))
        XCTAssertEqual(actionBar.buttons.count, 3)
        XCTAssertTrue(waitForButtonLabel("Love", identifier: "place-card.loved", in: app))
        XCTAssertTrue(waitForButtonLabel("Un-see", identifier: "place-card.unsee", in: app))
        XCTAssertTrue(waitForButtonEnabled(true, identifier: "place-card.unsee", in: app))

        lovedButton.tap()
        XCTAssertEqual(actionBar.buttons.count, 3)
        XCTAssertTrue(waitForButtonLabel("Unlove", identifier: "place-card.loved", in: app))
        XCTAssertTrue(waitForButtonEnabled(false, identifier: "place-card.unsee", in: app))
        XCTAssertFalse(actionBar.buttons["place-card.hide"].exists)
    }

    func testLocateMeChromeExplainsWhenLocationIsDenied() throws {
        let app = launch(reset: true, locationDenied: true)

        let map = app.otherElements["map.surface"]
        XCTAssertTrue(map.waitForExistence(timeout: 10))

        XCTAssertEqual(app.buttons["map.locate-me"].label, "Locate me")
        XCTAssertTrue(app.staticTexts["Location is off"].waitForExistence(timeout: 5))
        let locationSettings = app.buttons["map.location-settings"]
        if !locationSettings.waitForExistence(timeout: 5) {
            XCTAssertTrue(app.otherElements["map.location-settings"].waitForExistence(timeout: 5))
        }
        attachScreenshot(named: "map-location-off")
    }

    func testLocateMeShowsNearbyPromptForFixturePlace() {
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
        XCTAssertTrue(app.staticTexts["You're near Ghost Sign — seen it?"].waitForExistence(timeout: 5))
        attachScreenshot(named: "nearby-prompt")

        let seenButton = app.buttons["map.nearby-prompt.seen"]
        XCTAssertTrue(seenButton.waitForExistence(timeout: 5))
        seenButton.tap()

        XCTAssertFalse(nearbyPrompt.waitForExistence(timeout: 2))
        XCTAssertEqual(app.staticTexts["tracks.visit-count.\(placeID)"].label, "Tracks visits: 1")
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

        openAppMenu(in: app)
        app.buttons["menu.row.about"].tap()
        XCTAssertTrue(app.staticTexts["About"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Build"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Open source acknowledgements"].waitForExistence(timeout: 5))
        XCTAssertEqual(try buildCommitLabel(in: app), "Build \(try currentGitCommit())")
        let grdbCredit = element(identifier: "credits.oss.GRDB.swift|7.11.1", in: app)
        XCTAssertTrue(scrollToExistence(of: grdbCredit, in: app))

        let mapLibreCredit = element(
            identifier: "credits.oss.MapLibre Native iOS / maplibre-gl-native-distribution|6.27.0",
            in: app
        )
        XCTAssertTrue(scrollToExistence(of: mapLibreCredit, in: app))
        let mapLibreLicense = element(
            identifier: "credits.oss.MapLibre Native iOS / maplibre-gl-native-distribution|6.27.0.license",
            in: app
        )
        XCTAssertTrue(scrollToExistence(of: mapLibreLicense, in: app))
        XCTAssertEqual(mapLibreLicense.elementType, .button)
        XCTAssertTrue(mapLibreLicense.isEnabled)
        attachScreenshot(named: "credits-a11y")
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
        openAppMenu(in: app)
        app.buttons["menu.row.tracks"].tap()

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
            height: appFrame.maxY - visitDateBack.frame.minY - 34
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
        coverageBBoxes: [String] = [],
        resetOnboarding: Bool = false,
        forceDarkAppearance: Bool = false,
        densePins: Bool = false,
        startupViewport: String? = nil,
        trackReplayBeatDuration: Double? = nil,
        replayVisualSeed: Bool = false,
        hideFixtureChrome: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing-fixture-map"]
        app.launchArguments.append("--ui-testing-reset-pin-size")
        app.launchArguments.append("--ui-testing-reset-coverage-shading")
        if hideFixtureChrome {
            app.launchArguments.append("--ui-testing-hide-fixture-chrome")
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
        if let offlineProgress {
            app.launchArguments.append("--ui-testing-offline-progress")
            app.launchArguments.append(String(offlineProgress))
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

    private func selectMapTheme(_ themeID: String, in app: XCUIApplication) {
        openAppMenu(in: app)
        app.buttons["menu.row.settings"].tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
        let themeButton = app.buttons["settings.theme.\(themeID)"]
        XCTAssertTrue(scrollToHittable(themeButton, in: app))
        themeButton.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertTrue(waitForElementValue("Selected", identifier: "settings.theme.\(themeID)", in: app))
        app.buttons["menu.done"].tap()
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

    private func openAppMenu(in app: XCUIApplication) {
        let menuButton = app.buttons["map.menu"]
        XCTAssertTrue(menuButton.waitForExistence(timeout: 5))
        XCTAssertEqual(menuButton.label, "Menu")
        menuButton.tap()
    }

    private func closePlaceCard(in app: XCUIApplication) {
        let sheet = app.scrollViews.matching(identifierPrefix: "place-card.instance.").firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        let start = sheet.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertTrue(waitForNonExistence(of: sheet, timeout: 5))
    }

    private func tapFixturePin(in map: XCUIElement) {
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

    private func openFixtureCard(in map: XCUIElement, app: XCUIApplication) {
        openCard(named: "Ghost Sign", in: map, app: app, tap: tapFixturePin)
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

    private func openLayers(in app: XCUIApplication) {
        let layers = app.buttons["map.layers"]
        XCTAssertTrue(layers.waitForExistence(timeout: 5))
        layers.tap()
        XCTAssertTrue(app.navigationBars["Layers"].waitForExistence(timeout: 5))
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

    private func assertListMapFilterChromePlacement(
        _ filter: XCUIElement,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let map = app.otherElements["map.surface"]
        let title = app.staticTexts["map.list-mode.title"]
        let back = app.buttons["map.list-mode.back"]
        let layers = app.buttons["map.layers"]
        XCTAssertTrue(map.exists, "map.surface missing before list-map chrome placement assertion", file: file, line: line)
        XCTAssertTrue(filter.exists, file: file, line: line)
        XCTAssertTrue(title.exists, file: file, line: line)
        XCTAssertTrue(back.exists, file: file, line: line)
        XCTAssertTrue(layers.exists, file: file, line: line)
        XCTAssertLessThan(filter.frame.midX, map.frame.midX, file: file, line: line)
        XCTAssertGreaterThan(layers.frame.minY, title.frame.minY, file: file, line: line)
        XCTAssertGreaterThan(filter.frame.minY, layers.frame.maxY, file: file, line: line)
        assertNoFrameIntersection(filter, title, file: file, line: line)
        assertNoFrameIntersection(filter, back, file: file, line: line)
        assertNoFrameIntersection(filter, layers, file: file, line: line)
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

    private func attachScreenshot(named name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        exportScreenshot(screenshot, named: name)
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
        let directory = URL(fileURLWithPath: "/private/tmp/making-tracks-artifacts", isDirectory: true)
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

    @discardableResult
    private func scrollToExistence(of element: XCUIElement, in app: XCUIApplication) -> Bool {
        if element.waitForExistence(timeout: 2) {
            return true
        }

        for _ in 0..<5 {
            scrollTarget(in: app).swipeUp()
            if element.waitForExistence(timeout: 1) {
                return true
            }
        }

        return element.exists
    }

    @discardableResult
    private func scrollToHittable(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        if element.waitForExistence(timeout: 2), element.isHittable {
            return true
        }

        for _ in 0..<5 {
            scrollTarget(in: app).swipeUp()
            if element.waitForExistence(timeout: 1), element.isHittable {
                return true
            }
        }

        return element.exists && element.isHittable
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
        "credits-a11y": "credits-a11y",
        "diagnostics-preprepare-exclusions-dark": "diagnostics-preprepare-exclusions-dark",
        "tracks-static-geometry": "tracks-static-geometry",
        "tracks-unified-visit-editing": "tracks-unified-visit-editing",
        "my-tracks-rendered-oracle-light": "my-tracks-rendered-oracle-light",
        "my-tracks-rendered-oracle-dark": "my-tracks-rendered-oracle-dark",
        "my-tracks-visit-date-oracle-light": "my-tracks-visit-date-oracle-light",
        "my-tracks-visit-date-oracle-dark": "my-tracks-visit-date-oracle-dark",
        "list-map-polished-chrome": "list-map-polished-chrome",
        "list-map-spread-fit": "list-map-spread-fit",
        "my-tracks-burst-readout": "my-tracks-burst-readout",
        "track-filter-picker-open": "track-filter-picker-open",
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
