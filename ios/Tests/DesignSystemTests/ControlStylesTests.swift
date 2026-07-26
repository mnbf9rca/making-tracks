#if canImport(AppKit)
import AppKit
#endif
import SwiftUI
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
        let buttonValues: [(Bool) -> String?] = [
            MaterialFilledButtonStyle().accessibilityValue,
            MaterialTonalButtonStyle().accessibilityValue,
            MaterialQuietButtonStyle().accessibilityValue,
        ]
        for value in buttonValues {
            XCTAssertNil(value(true))
            XCTAssertEqual(value(false), "Unavailable")
        }

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

#if canImport(AppKit)
    func testMaterialChipRendersActiveFilledAndAvailableTonal() throws {
        let active = try renderChip(state: .active)
        let available = try renderChip(state: .available)

        let activeAccentPixels = solidAccentPixelCount(in: active)
        let availableAccentPixels = solidAccentPixelCount(in: available)

        XCTAssertGreaterThan(activeAccentPixels, availableAccentPixels + 500)
    }

    func testMaterialChipTitleUsesRatifiedCaptionSizeAndSemiboldWeight() throws {
        let shortTitle = "Map"
        let longTitle = "Map places"

        XCTAssertEqual(
            MaterialChip.titleFont,
            Font.caption.weight(.semibold)
        )

        let styledWidthDelta = try renderedWidth(
            MaterialChip(shortTitle, state: .active, action: {})
        ) - renderedWidth(
            MaterialChip(longTitle, state: .active, action: {})
        )
        let expectedWidthDelta = try renderedWidth(
            Text(shortTitle)
                .font(.caption.weight(.semibold))
        ) - renderedWidth(
            Text(longTitle)
                .font(.caption.weight(.semibold))
        )

        XCTAssertEqual(styledWidthDelta, expectedWidthDelta, accuracy: 1)
    }

    func testMaterialChipIconUsesTypographyLabelSizeAndMediumWeight() throws {
        let title = "Map"
        let textOnlyWidth = try renderedWidth(
            MaterialChip(title, state: .active, action: {})
                .dynamicTypeSize(.accessibility5)
        )
        let iconAndTextWidth = try renderedWidth(
            MaterialChip(
                title,
                systemImage: "map",
                state: .active,
                action: {}
            )
            .dynamicTypeSize(.accessibility5)
        )
        let expectedIconWidth = try renderedWidth(
            Image(systemName: "map")
                .font(Typography.font(for: .label).weight(.medium))
                .dynamicTypeSize(.accessibility5)
        )

        XCTAssertEqual(
            iconAndTextWidth - textOnlyWidth,
            expectedIconWidth + 5,
            accuracy: 1
        )
    }
#endif

    func testMaterialFilledButtonPlainTextUsesTypographyButtonRole() throws {
        let shortTitle = "Save"
        let longTitle = "Save place"

        let styledWidthDelta = try renderedWidth(
            Button(shortTitle, action: {})
                .buttonStyle(MaterialFilledButtonStyle())
        ) - renderedWidth(
            Button(longTitle, action: {})
                .buttonStyle(MaterialFilledButtonStyle())
        )
        let expectedWidthDelta = try renderedWidth(
            Text(shortTitle).font(Typography.font(for: .button))
        ) - renderedWidth(
            Text(longTitle).font(Typography.font(for: .button))
        )

        XCTAssertEqual(styledWidthDelta, expectedWidthDelta, accuracy: 1)
    }

    func testMaterialFilledButtonLabelTitleUsesTypographyButtonRole() throws {
        let shortTitle = "Save"
        let longTitle = "Save place"

        let styledWidthDelta = try renderedWidth(
            Button(action: {}) {
                Label(shortTitle, systemImage: "bookmark")
            }
            .buttonStyle(MaterialFilledButtonStyle())
        ) - renderedWidth(
            Button(action: {}) {
                Label(longTitle, systemImage: "bookmark")
            }
            .buttonStyle(MaterialFilledButtonStyle())
        )
        let expectedWidthDelta = try renderedWidth(
            Text(shortTitle).font(Typography.font(for: .button))
        ) - renderedWidth(
            Text(longTitle).font(Typography.font(for: .button))
        )

        XCTAssertEqual(styledWidthDelta, expectedWidthDelta, accuracy: 1)
    }

    func testMaterialControlsGrowVerticallyForMultilineLabels() throws {
        let shortChip = try renderedHeight(
            MaterialChip("Saved", state: .active, action: {})
                .frame(width: 108)
        )
        let longChip = try renderedHeight(
            MaterialChip(
                "Saved for a long weekend adventure in the mountains",
                state: .active,
                action: {}
            )
            .frame(width: 108)
        )

        XCTAssertGreaterThan(longChip, shortChip + 10)

        let shortButton = try renderedHeight(
            Button("Save", action: {})
                .buttonStyle(MaterialFilledButtonStyle())
                .frame(width: 108)
        )
        let longButton = try renderedHeight(
            Button(
                "Save for a long weekend adventure in the mountains",
                action: {}
            )
                .buttonStyle(MaterialFilledButtonStyle())
                .frame(width: 108)
        )

        XCTAssertGreaterThan(longButton, shortButton + 10)
    }

    private func renderChip(state: MaterialChipState) throws -> CGImage {
        try render(
            MaterialChip("Trail", state: state, action: {})
                .padding(8)
                .background(Color.white)
        )
    }

    private func render<Content: View>(_ content: Content) throws -> CGImage {
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        return try XCTUnwrap(renderer.cgImage)
    }

    private func renderedHeight<Content: View>(_ content: Content) throws -> Int {
        try render(content).height
    }

    private func renderedWidth<Content: View>(_ content: Content) throws -> Int {
        try render(content).width
    }

#if canImport(AppKit)
    private func solidAccentPixelCount(in image: CGImage) -> Int {
        let bitmap = NSBitmapImageRep(cgImage: image)

        return (0..<bitmap.pixelsHigh).reduce(into: 0) { count, y in
            for x in 0..<bitmap.pixelsWide {
                guard
                    let color = bitmap.colorAt(x: x, y: y)?
                        .usingColorSpace(.sRGB)
                else {
                    continue
                }
                if color.greenComponent > color.redComponent + 0.2,
                   color.blueComponent > color.redComponent + 0.2,
                   color.greenComponent > color.blueComponent + 0.03,
                   color.alphaComponent > 0.98 {
                    count += 1
                }
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
