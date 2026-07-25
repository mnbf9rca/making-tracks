import SwiftUI
import XCTest
@testable import DesignSystem

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

    private func color(
        _ red: UInt8,
        _ green: UInt8,
        _ blue: UInt8,
        opacity: Double = 1
    ) -> MaterialColor {
        MaterialColor(red: red, green: green, blue: blue, opacity: opacity)
    }
}
