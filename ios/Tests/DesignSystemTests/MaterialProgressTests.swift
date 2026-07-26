import SwiftUI
import XCTest
@testable import DesignSystem

#if canImport(AppKit)
import AppKit
#endif

@MainActor
final class MaterialProgressTests: XCTestCase {
    func testCountStateDerivesFractionVisibleCountAndAccessibilityValue() {
        XCTAssertEqual(
            MaterialProgressState.count(completed: 3, total: 8).presentation,
            .init(fraction: 0.375, visibleCount: "3 of 8", accessibilityValue: "3 of 8")
        )
    }

    func testPercentageStateDerivesFractionVisibleCountAndAccessibilityValue() {
        XCTAssertEqual(
            MaterialProgressState.percentage(42).presentation,
            .init(fraction: 0.42, visibleCount: "42%", accessibilityValue: "42%")
        )
    }

    func testIndeterminateStateHasNoVisibleCountAndSpeaksItsState() {
        XCTAssertEqual(
            MaterialProgressState.indeterminate.presentation,
            .init(fraction: nil, visibleCount: nil, accessibilityValue: "In progress")
        )
    }

    func testCountStateClampsCompletionToTheValidRange() {
        XCTAssertEqual(
            MaterialProgressState.count(completed: 12, total: 8).presentation,
            .init(fraction: 1, visibleCount: "8 of 8", accessibilityValue: "8 of 8")
        )
        XCTAssertEqual(
            MaterialProgressState.count(completed: -3, total: 8).presentation,
            .init(fraction: 0, visibleCount: "0 of 8", accessibilityValue: "0 of 8")
        )
    }

    func testCountStateTreatsNonPositiveTotalsAsZero() {
        XCTAssertEqual(
            MaterialProgressState.count(completed: 3, total: 0).presentation,
            .init(fraction: 0, visibleCount: "0 of 0", accessibilityValue: "0 of 0")
        )
        XCTAssertEqual(
            MaterialProgressState.count(completed: -3, total: -8).presentation,
            .init(fraction: 0, visibleCount: "0 of 0", accessibilityValue: "0 of 0")
        )
    }

    func testCountSuffixIsAppliedToVisibleAndAccessibilityValues() {
        let presentation = MaterialProgress(
            state: .count(completed: 3, total: 8, suffix: "seen")
        ).renderConfiguration.presentation

        XCTAssertEqual(presentation.fraction, 0.375)
        XCTAssertEqual(presentation.visibleCount, "3 of 8 seen")
        XCTAssertEqual(presentation.accessibilityValue, "3 of 8 seen")
    }

    func testCountSuffixIsAppliedAfterCountClamping() {
        let presentation = MaterialProgress(
            state: .count(completed: 12, total: 8, suffix: "seen")
        ).renderConfiguration.presentation

        XCTAssertEqual(presentation.fraction, 1)
        XCTAssertEqual(presentation.visibleCount, "8 of 8 seen")
        XCTAssertEqual(presentation.accessibilityValue, "8 of 8 seen")
    }

    func testPercentageStateClampsToZeroThroughOneHundred() {
        XCTAssertEqual(
            MaterialProgressState.percentage(-42).presentation,
            .init(fraction: 0, visibleCount: "0%", accessibilityValue: "0%")
        )
        XCTAssertEqual(
            MaterialProgressState.percentage(142).presentation,
            .init(fraction: 1, visibleCount: "100%", accessibilityValue: "100%")
        )
    }

    func testSemanticSuffixIsOwnedByCountStateOnly() {
        XCTAssertEqual(
            MaterialProgressState.percentage(42).presentation,
            .init(fraction: 0.42, visibleCount: "42%", accessibilityValue: "42%")
        )
        XCTAssertEqual(
            MaterialProgressState.indeterminate.presentation,
            .init(fraction: nil, visibleCount: nil, accessibilityValue: "In progress")
        )
        XCTAssertEqual(
            MaterialProgressState.count(
                completed: 3,
                total: 8,
                suffix: "seen"
            ).presentation,
            .init(
                fraction: 0.375,
                visibleCount: "3 of 8 seen",
                accessibilityValue: "3 of 8 seen"
            )
        )
    }

    func testTypedLeadingHeaderRequiresAndCarriesItsAccessibilityLabel() {
        let progress: MaterialProgress<Text> = MaterialProgress(
            state: .count(completed: 3, total: 8, suffix: "seen"),
            accessibilityLabel: "Ghost signs"
        ) {
            Text("Ghost signs")
        }

        let configuration = progress.renderConfiguration

        XCTAssertEqual(configuration.accessibilityLabel, "Ghost signs")
        XCTAssertEqual(configuration.presentation.visibleCount, "3 of 8 seen")
        XCTAssertEqual(configuration.presentation.accessibilityValue, "3 of 8 seen")
    }

#if canImport(AppKit)
    func testDeterminateViewRendersCountGlyphPixelsAboveTheBar() throws {
        let image = try render(
            MaterialProgress(
                state: .count(completed: 3, total: 8)
            )
            .frame(width: 200)
        )

        XCTAssertGreaterThan(
            glyphPixelCountAboveProgressBar(in: image),
            20
        )
    }

    func testProgressCountOwnsTypographyMetadataRole() throws {
        let count = "3 of 8"
        let progressImage = try render(
            MaterialProgress(
                state: .count(completed: 3, total: 8)
            )
            .frame(width: 200)
            .dynamicTypeSize(.accessibility5)
        )
        let expectedCountImage = try render(
            Text(verbatim: count)
                .font(Typography.font(for: .metadata))
                .foregroundStyle(MaterialTheme.snow.tokens.muted.swiftUIColor)
                .fixedSize(horizontal: true, vertical: true)
                .dynamicTypeSize(.accessibility5)
        )

        XCTAssertEqual(
            mutedGlyphPixelCount(in: progressImage),
            mutedGlyphPixelCount(in: expectedCountImage),
            accuracy: 8
        )
    }

    func testProgressLeadingHeaderKeepsCallerOwnedAmbientTypography() throws {
        let progressImage = try render(
            MaterialProgress(
                state: .count(completed: 3, total: 8),
                accessibilityLabel: "Ghost signs"
            ) {
                Text("Ghost signs")
            }
            .font(.largeTitle)
            .frame(width: 390)
        )
        let callerHeaderImage = try render(
            Text("Ghost signs")
                .font(.largeTitle)
        )

        XCTAssertGreaterThanOrEqual(
            progressImage.height,
            callerHeaderImage.height + 7
        )
    }

    func testProgressCountMetadataRoleDoesNotLeakToLeadingHeader() throws {
        let progressWithLargeCallerHeader = try render(
            MaterialProgress(
                state: .count(completed: 3, total: 8),
                accessibilityLabel: "Ghost signs"
            ) {
                Text("Ghost signs")
            }
            .font(.largeTitle)
            .frame(width: 390)
        )
        let progressWithMetadataCallerHeader = try render(
            MaterialProgress(
                state: .count(completed: 3, total: 8),
                accessibilityLabel: "Ghost signs"
            ) {
                Text("Ghost signs")
            }
            .font(Typography.font(for: .metadata))
            .frame(width: 390)
        )

        XCTAssertGreaterThan(
            progressWithLargeCallerHeader.height,
            progressWithMetadataCallerHeader.height + 8
        )
    }

    func testAccessibilityHeaderFitsAtPhoneWidthWithoutCompressingCount() throws {
        let count = "8 of 8 landmarks seen"
        let progress = try render(
            MaterialProgress(
                state: .count(
                    completed: 12,
                    total: 8,
                    suffix: "landmarks seen"
                ),
                accessibilityLabel: "Ghost signs"
            ) {
                Text(
                    "Ghost signs and painted advertisements preserved across the city"
                )
            }
            .frame(width: 390)
            .dynamicTypeSize(.accessibility5)
        )
        let standaloneCount = try render(
            Text(verbatim: count)
                .font(Typography.font(for: .metadata))
                .foregroundStyle(MaterialTheme.snow.tokens.muted.swiftUIColor)
                .fixedSize(horizontal: true, vertical: true)
                .dynamicTypeSize(.accessibility5)
        )

        XCTAssertEqual(progress.width, 390)
        XCTAssertGreaterThan(progress.height, standaloneCount.height)
        XCTAssertGreaterThanOrEqual(
            mutedGlyphPixelCount(in: progress),
            Int(Double(mutedGlyphPixelCount(in: standaloneCount)) * 0.95)
        )
        XCTAssertLessThanOrEqual(
            mutedGlyphPixelCount(in: progress),
            Int(Double(mutedGlyphPixelCount(in: standaloneCount)) * 1.05)
        )
    }
#endif

    func testRenderedProgressConfigurationUsesResolvedSnowTokensAndBarHeight() {
        let configuration = MaterialProgress(
            state: .count(completed: 3, total: 8)
        ).renderConfiguration

        XCTAssertEqual(configuration.appearance.fill, color(0x0A, 0x6B, 0x5C))
        XCTAssertEqual(
            configuration.appearance.track,
            color(0x2B, 0x28, 0x23, opacity: 0.14)
        )
        XCTAssertEqual(configuration.appearance.count, color(0x6B, 0x67, 0x5F))
        XCTAssertEqual(configuration.appearance.barHeight, 3)
        XCTAssertEqual(configuration.presentation.fraction, 0.375)
        XCTAssertEqual(configuration.presentation.visibleCount, "3 of 8")
        XCTAssertEqual(configuration.accessibilityLabel, "Progress")
    }

    func testIndeterminateProgressConfigurationCarriesSpokenStateWithoutCountText() {
        let configuration = MaterialProgress(state: .indeterminate).renderConfiguration

        XCTAssertNil(configuration.presentation.fraction)
        XCTAssertNil(configuration.presentation.visibleCount)
        XCTAssertEqual(configuration.presentation.accessibilityValue, "In progress")
    }

#if canImport(AppKit)
    private func render<Content: View>(_ content: Content) throws -> CGImage {
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        return try XCTUnwrap(renderer.cgImage)
    }

    private func glyphPixelCountAboveProgressBar(in image: CGImage) -> Int {
        let bitmap = NSBitmapImageRep(cgImage: image)
        let maximumGlyphRowWidth = bitmap.pixelsWide / 2

        return (0..<bitmap.pixelsHigh).reduce(into: 0) { count, y in
            let nontransparentPixels = (0..<bitmap.pixelsWide).reduce(into: 0) {
                rowCount,
                x in
                if (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.01 {
                    rowCount += 1
                }
            }

            if nontransparentPixels > 0,
               nontransparentPixels < maximumGlyphRowWidth {
                count += nontransparentPixels
            }
        }
    }

    private func mutedGlyphPixelCount(in image: CGImage) -> Int {
        let bitmap = NSBitmapImageRep(cgImage: image)
        let muted = MaterialTheme.snow.tokens.muted

        return (0..<bitmap.pixelsHigh).reduce(into: 0) { count, y in
            for x in 0..<bitmap.pixelsWide {
                guard
                    let color = bitmap.colorAt(x: x, y: y)?
                        .usingColorSpace(.sRGB),
                    color.alphaComponent > 0.05,
                    abs(color.redComponent - muted.red) < 0.08,
                    abs(color.greenComponent - muted.green) < 0.08,
                    abs(color.blueComponent - muted.blue) < 0.08
                else {
                    continue
                }
                count += 1
            }
        }
    }
#endif

    private func color(
        _ red: UInt8,
        _ green: UInt8,
        _ blue: UInt8,
        opacity: Double = 1
    ) -> MaterialColor {
        MaterialColor(red: red, green: green, blue: blue, opacity: opacity)
    }
}
