import SwiftUI
import XCTest
import DesignSystem

#if canImport(AppKit)
import AppKit
#endif

@MainActor
final class IconRoleTests: XCTestCase {
    func testContractIsClosedToTheThreeRatifiedSemanticRoles() {
        let expected: [IconRole: (pointSize: CGFloat, typographyRole: TypographyRole)] = [
            .hero: (22, .heroTitle),
            .inline: (15, .button),
            .accessory: (11, .label),
        ]

        XCTAssertEqual(Set(IconRole.allCases), Set(expected.keys))

        for (role, contract) in expected {
            XCTAssertEqual(role.pointSize, contract.pointSize)
            XCTAssertEqual(role.typographyRole, contract.typographyRole)
        }
    }

#if canImport(AppKit)
    func testRoleOwnsScaleWeightAndMonochromeRenderingAgainstAnAmbientFont() throws {
        let contracts: [(IconRole, CGFloat, Font.TextStyle)] = [
            (.hero, 22, .headline),
            (.inline, 15, .subheadline),
            (.accessory, 11, .caption2),
        ]

        for dynamicTypeSize in [DynamicTypeSize.large, .accessibility5] {
            for (role, pointSize, textStyle) in contracts {
                let actual = try renderedGlyph(
                    Image(systemName: "figure.walk")
                        .iconRole(role)
                        .font(.largeTitle),
                    dynamicTypeSize: dynamicTypeSize
                )
                let expected = try renderedGlyph(
                    RatifiedIconGlyph(
                        pointSize: pointSize,
                        relativeTo: textStyle
                    ),
                    dynamicTypeSize: dynamicTypeSize
                )

                XCTAssertEqual(actual.width, expected.width)
                XCTAssertEqual(actual.height, expected.height)
                XCTAssertEqual(actual.opaquePixelCount, expected.opaquePixelCount)
            }
        }
    }

    func testRoleOverridesAmbientPaletteRenderingWithMonochrome() throws {
        let rendered = try renderedGlyph(
            Image(systemName: "person.crop.circle.badge.checkmark")
                .iconRole(.inline)
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.red, Color.blue),
            dynamicTypeSize: .large
        )

        XCTAssertGreaterThan(rendered.redPixelCount, 0)
        XCTAssertEqual(rendered.bluePixelCount, 0)
    }

    private func renderedGlyph<Content: View>(
        _ content: Content,
        dynamicTypeSize: DynamicTypeSize
    ) throws -> RenderedGlyph {
        let renderer = ImageRenderer(
            content: content
                .environment(\.dynamicTypeSize, dynamicTypeSize)
        )
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        let bitmap = NSBitmapImageRep(cgImage: image)
        var opaquePixelCount = 0
        var redPixelCount = 0
        var bluePixelCount = 0

        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard
                    let color = bitmap.colorAt(x: x, y: y)?
                        .usingColorSpace(.sRGB),
                    color.alphaComponent > 0.05
                else {
                    continue
                }
                opaquePixelCount += 1

                if color.redComponent > color.blueComponent + 0.2 {
                    redPixelCount += 1
                } else if color.blueComponent > color.redComponent + 0.2 {
                    bluePixelCount += 1
                }
            }
        }

        return RenderedGlyph(
            width: image.width,
            height: image.height,
            opaquePixelCount: opaquePixelCount,
            redPixelCount: redPixelCount,
            bluePixelCount: bluePixelCount
        )
    }
#endif
}

#if canImport(AppKit)
private struct RenderedGlyph: Equatable {
    let width: Int
    let height: Int
    let opaquePixelCount: Int
    let redPixelCount: Int
    let bluePixelCount: Int
}

private struct RatifiedIconGlyph: View {
    @ScaledMetric private var pointSize: CGFloat

    init(
        pointSize: CGFloat,
        relativeTo textStyle: Font.TextStyle
    ) {
        _pointSize = ScaledMetric(
            wrappedValue: pointSize,
            relativeTo: textStyle
        )
    }

    var body: some View {
        Image(systemName: "figure.walk")
            .font(.system(size: pointSize, weight: .medium))
            .symbolRenderingMode(.monochrome)
    }
}
#endif
