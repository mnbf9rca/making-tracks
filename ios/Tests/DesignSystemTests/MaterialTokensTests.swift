import SwiftUI
import XCTest
@testable import DesignSystem

final class MaterialTokensTests: XCTestCase {
    func testSnowPinsItsIntrinsicLightColorScheme() {
        XCTAssertEqual(MaterialTheme.snow.colorScheme, .light)
    }

    func testSnowMatchesEveryRatifiedSemanticColor() {
        let expected: [SemanticColorToken: MaterialColor] = [
            .ground: color(0xF4, 0xF1, 0xEA),
            .water: color(0xC9, 0xDB, 0xE2),
            .park: color(0xDC, 0xE5, 0xD4),
            .road: color(0xC9, 0xBF, 0xA8),
            .roadMinor: color(0xDD, 0xD5, 0xC2),
            .surface: color(0xFB, 0xFA, 0xF2),
            .surfaceRaised: color(0xFF, 0xFF, 0xFF),
            .ink: color(0x2B, 0x28, 0x23),
            .muted: color(0x6B, 0x67, 0x5F),
            .accent: color(0x0A, 0x6B, 0x5C),
            .accentContrast: color(0xFB, 0xFA, 0xF2),
            .eyebrow: color(0x8A, 0x5A, 0x2B),
            .hairline: color(0x2B, 0x28, 0x23, opacity: 0.14),
            .scrim: color(0x2B, 0x28, 0x23, opacity: 0.35),
            // The prose table is qualitative; 0.10 selects the frozen render's --shadow-soft recipe.
            // Its --shadow-sheet 0.12 alpha remains component-specific.
            .shadow: color(0x2B, 0x28, 0x23, opacity: 0.10),
            .background: color(0xF4, 0xF1, 0xEA),
            .labels: color(0x6B, 0x67, 0x5F),
            .labelHalo: color(0xF4, 0xF1, 0xEA),
            .boundaries: color(0x2B, 0x28, 0x23, opacity: 0.14),
            .trackLine: color(0x2D, 0x8C, 0x83),
        ]

        XCTAssertEqual(Set(expected.keys), Set(SemanticColorToken.allCases))

        let sheet = MaterialTheme.snow.tokens
        for (token, expectedColor) in expected {
            XCTAssertEqual(sheet[token], expectedColor, "\(token) drifted from the ratified snow column")
        }
    }

    func testPinsAreTheOnlyConstantBlockOutsideMaterialColumns() {
        let pins = MaterialTheme.snow.tokens.pins

        XCTAssertEqual(pins, .constant)
        XCTAssertEqual(pins.pin, color(0xE4, 0x57, 0x2E))
        XCTAssertEqual(pins.pinFaded, color(0xE4, 0x57, 0x2E, opacity: 0.35))
    }

    func testMapRowsCanVaryWithoutChangingTheirInitialSourceTokens() {
        let sheet = makeSheet(
            background: color(0x01, 0x02, 0x03),
            labels: color(0x04, 0x05, 0x06),
            labelHalo: color(0x07, 0x08, 0x09),
            boundaries: color(0x0A, 0x0B, 0x0C),
            trackLine: color(0x0D, 0x0E, 0x0F)
        )

        XCTAssertNotEqual(sheet.background, sheet.ground)
        XCTAssertNotEqual(sheet.labels, sheet.muted)
        XCTAssertNotEqual(sheet.labelHalo, sheet.ground)
        XCTAssertNotEqual(sheet.boundaries, sheet.hairline)
        XCTAssertNotEqual(sheet.trackLine, MaterialTheme.snow.tokens.trackLine)
    }

    func testMapStyleStringUsesUppercaseHexForOpaqueColors() {
        XCTAssertEqual(color(0x2B, 0x28, 0x23).mapStyleString, "#2B2823")
    }

    func testMapStyleStringPreservesOpacityForTranslucentColors() {
        XCTAssertEqual(color(0x2B, 0x28, 0x23, opacity: 0.35).mapStyleString, "rgba(43, 40, 35, 0.35)")
    }

    @MainActor
    func testSnowResolvesIdenticallyInLightAndDarkSystemAppearances() {
        let sheet = MaterialTheme.snow.tokens

        for token in SemanticColorToken.allCases {
            assertStaticAcrossSystemAppearances(sheet[token], label: "\(token)")
        }
        assertStaticAcrossSystemAppearances(sheet.pins.pin, label: "pin")
        assertStaticAcrossSystemAppearances(sheet.pins.pinFaded, label: "pinFaded")
        assertStaticAcrossSystemAppearances(sheet.trackLine, label: "trackLine")
    }

    func testContrastGateRejectsTranslucentOperands() {
        XCTAssertNil(
            contrastRatio(
                color(0x00, 0x00, 0x00, opacity: 0),
                color(0xFF, 0xFF, 0xFF)
            )
        )
        XCTAssertNil(
            contrastRatio(
                color(0x00, 0x00, 0x00, opacity: 0.5),
                color(0xFF, 0xFF, 0xFF)
            )
        )
        XCTAssertNil(
            contrastRatio(
                color(0x00, 0x00, 0x00),
                color(0xFF, 0xFF, 0xFF, opacity: 0.5)
            )
        )
    }

    func testEveryMaterialPassesBodyAndLargeUIContrastGates() {
        for material in MaterialTheme.allCases {
            let sheet = material.tokens
            let baseBackgrounds = [
                ("ground", sheet.ground),
                ("surface", sheet.surface),
                ("surfaceRaised", sheet.surfaceRaised),
            ]

            for (backgroundName, background) in baseBackgrounds {
                assertContrast(sheet.ink, background, minimum: 4.5, label: "ink/\(backgroundName)")
                assertContrast(sheet.muted, background, minimum: 4.5, label: "muted/\(backgroundName)")
                assertContrast(sheet.eyebrow, background, minimum: 4.5, label: "eyebrow/\(backgroundName)")
                assertContrast(sheet.accent, background, minimum: 4.5, label: "accent/\(backgroundName)")
            }

            assertContrast(
                sheet.accentContrast,
                sheet.accent,
                minimum: 3.0,
                label: "accentContrast/accent large text or UI"
            )
            assertContrast(
                // PaperStyle always renders the 1.25pt halo, so this proves that pair—not labels against every basemap fill.
                sheet.labels,
                sheet.labelHalo,
                minimum: 4.5,
                label: "labels/labelHalo map text"
            )
        }
    }

    private func color(
        _ red: UInt8,
        _ green: UInt8,
        _ blue: UInt8,
        opacity: Double = 1
    ) -> MaterialColor {
        MaterialColor(red: red, green: green, blue: blue, opacity: opacity)
    }

    private func makeSheet(
        background: MaterialColor,
        labels: MaterialColor,
        labelHalo: MaterialColor,
        boundaries: MaterialColor,
        trackLine: MaterialColor
    ) -> MaterialTokenSheet {
        let snow = MaterialTheme.snow.tokens
        return MaterialTokenSheet(
            ground: snow.ground,
            water: snow.water,
            park: snow.park,
            road: snow.road,
            roadMinor: snow.roadMinor,
            surface: snow.surface,
            surfaceRaised: snow.surfaceRaised,
            ink: snow.ink,
            muted: snow.muted,
            accent: snow.accent,
            accentContrast: snow.accentContrast,
            eyebrow: snow.eyebrow,
            hairline: snow.hairline,
            scrim: snow.scrim,
            shadow: snow.shadow,
            background: background,
            labels: labels,
            labelHalo: labelHalo,
            boundaries: boundaries,
            trackLine: trackLine
        )
    }

    @MainActor
    private func assertStaticAcrossSystemAppearances(
        _ color: MaterialColor,
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var light = EnvironmentValues()
        light.colorScheme = .light
        var dark = EnvironmentValues()
        dark.colorScheme = .dark

        let lightResolved = color.swiftUIColor.resolve(in: light)
        let darkResolved = color.swiftUIColor.resolve(in: dark)

        XCTAssertEqual(Double(lightResolved.red), color.red, accuracy: 0.000_001, label, file: file, line: line)
        XCTAssertEqual(Double(lightResolved.green), color.green, accuracy: 0.000_001, label, file: file, line: line)
        XCTAssertEqual(Double(lightResolved.blue), color.blue, accuracy: 0.000_001, label, file: file, line: line)
        XCTAssertEqual(
            Double(lightResolved.opacity),
            color.opacity,
            accuracy: 0.000_001,
            label,
            file: file,
            line: line
        )
        XCTAssertEqual(lightResolved.red, darkResolved.red, accuracy: 0.000_001, label, file: file, line: line)
        XCTAssertEqual(lightResolved.green, darkResolved.green, accuracy: 0.000_001, label, file: file, line: line)
        XCTAssertEqual(lightResolved.blue, darkResolved.blue, accuracy: 0.000_001, label, file: file, line: line)
        XCTAssertEqual(lightResolved.opacity, darkResolved.opacity, accuracy: 0.000_001, label, file: file, line: line)
    }

    private func assertContrast(
        _ foreground: MaterialColor,
        _ background: MaterialColor,
        minimum: Double,
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let ratio = contrastRatio(foreground, background) else {
            XCTFail(
                "\(label) contrast requires opaque foreground and background tokens",
                file: file,
                line: line
            )
            return
        }
        XCTAssertGreaterThanOrEqual(
            ratio,
            minimum,
            "\(label) contrast \(ratio) is below \(minimum):1",
            file: file,
            line: line
        )
    }

    private func contrastRatio(_ first: MaterialColor, _ second: MaterialColor) -> Double? {
        guard first.opacity == 1, second.opacity == 1 else {
            return nil
        }
        let lighter = max(relativeLuminance(first), relativeLuminance(second))
        let darker = min(relativeLuminance(first), relativeLuminance(second))
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func relativeLuminance(_ color: MaterialColor) -> Double {
        let components = [color.red, color.green, color.blue].map { component in
            component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }
        return (0.2126 * components[0]) + (0.7152 * components[1]) + (0.0722 * components[2])
    }
}
