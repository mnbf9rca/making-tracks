import XCTest
@testable import DesignSystem

@MainActor
final class ControlStylesTests: XCTestCase {
    func testButtonStylesResolveTheThreeRatifiedSemanticPalettes() {
        let filled = MaterialFilledButtonStyle().appearance
        XCTAssertEqual(filled.foreground, color(0xFB, 0xFA, 0xF2))
        XCTAssertEqual(filled.background, color(0x0A, 0x6B, 0x5C))
        XCTAssertEqual(filled.backgroundOpacity, 1)

        let tonal = MaterialTonalButtonStyle().appearance
        XCTAssertEqual(tonal.foreground, color(0x0A, 0x6B, 0x5C))
        XCTAssertEqual(tonal.background, color(0x0A, 0x6B, 0x5C))
        XCTAssertEqual(tonal.backgroundOpacity, 0.12)

        let quiet = MaterialQuietButtonStyle().appearance
        XCTAssertEqual(quiet.foreground, color(0x6B, 0x67, 0x5F))
        XCTAssertNil(quiet.background)
        XCTAssertEqual(quiet.backgroundOpacity, 0)
    }

    func testChipStatesMapActiveToFilledAndAvailableToTonal() {
        let active = MaterialChipState.active.appearance
        XCTAssertEqual(active.foreground, color(0xFB, 0xFA, 0xF2))
        XCTAssertEqual(active.background, color(0x0A, 0x6B, 0x5C))
        XCTAssertEqual(active.backgroundOpacity, 1)

        let available = MaterialChipState.available.appearance
        XCTAssertEqual(available.foreground, color(0x0A, 0x6B, 0x5C))
        XCTAssertEqual(available.background, color(0x0A, 0x6B, 0x5C))
        XCTAssertEqual(available.backgroundOpacity, 0.12)
    }

    func testDisabledButtonsAndChipsExposeSpokenState() {
        XCTAssertNil(MaterialFilledButtonStyle().accessibilityValue(isEnabled: true))
        XCTAssertEqual(
            MaterialFilledButtonStyle().accessibilityValue(isEnabled: false),
            "Unavailable"
        )

        XCTAssertEqual(
            MaterialChipState.active.accessibilityValue(isEnabled: true),
            "Selected"
        )
        XCTAssertEqual(
            MaterialChipState.available.accessibilityValue(isEnabled: true),
            "Not selected"
        )
        XCTAssertEqual(
            MaterialChipState.active.accessibilityValue(isEnabled: false),
            "Unavailable"
        )
        XCTAssertEqual(
            MaterialChipState.available.accessibilityValue(isEnabled: false),
            "Unavailable"
        )
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
