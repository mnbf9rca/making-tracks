import AppKit
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

    func testMaterialChipKeepsTheNativeButtonAccessibilityElement() throws {
        let source = try controlStylesSource()
        let chipSource = try XCTUnwrap(
            source
                .components(separatedBy: "public struct MaterialChip: View")
                .last?
                .components(separatedBy: "private struct MaterialButtonStyleBody")
                .first
        )

        XCTAssertTrue(chipSource.contains("Button(action: action)"))
        XCTAssertTrue(chipSource.contains(".accessibilityLabel"))
        XCTAssertTrue(chipSource.contains(".accessibilityValue"))
        XCTAssertFalse(
            chipSource.contains(".accessibilityElement(children: .ignore)"),
            "Replacing the native Button element discards semantics that the chip should inherit."
        )
    }

    func testMaterialChipRendersActiveFilledAndAvailableTonal() throws {
        let active = try renderChip(state: .active)
        let available = try renderChip(state: .available)

        let activeAccentPixels = solidAccentPixelCount(in: active)
        let availableAccentPixels = solidAccentPixelCount(in: available)

        XCTAssertGreaterThan(activeAccentPixels, availableAccentPixels + 500)
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

    private func controlStylesSource() throws -> String {
        let testsDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = testsDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/DesignSystem/ControlStyles.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
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
