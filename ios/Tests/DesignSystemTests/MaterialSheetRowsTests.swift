#if canImport(AppKit)
import AppKit
#endif
import SwiftUI
import XCTest
@testable import DesignSystem

@MainActor
final class MaterialSheetRowsTests: XCTestCase {
    func testSheetOwnsTheSingleRatifiedPresentation() {
        let appearance = MaterialSheet { EmptyView() }.appearance

        XCTAssertEqual(appearance.background, .solid(color(0xFB, 0xFA, 0xF2)))
        XCTAssertEqual(appearance.topCornerRadius, 22)
        XCTAssertEqual(appearance.detents, [.medium, .large])
        XCTAssertEqual(appearance.closeAccessibilityLabel, "Close")
        XCTAssertEqual(appearance.grabberColor, MaterialTheme.snow.tokens.hairline)
        XCTAssertEqual(appearance.closeForeground, color(0x6B, 0x67, 0x5F))
        XCTAssertNotEqual(appearance.grabberColor, appearance.background.color)
    }

    func testRaisedCardRowResolvesRaisedSurfaceWithoutDivider() {
        let appearance = MaterialRaisedCardRow { EmptyView() }.appearance

        XCTAssertEqual(appearance.background, MaterialTheme.snow.tokens.surfaceRaised)
        XCTAssertEqual(appearance.cornerRadius, 14)
        XCTAssertNil(appearance.divider)
    }

    func testHairlineRowResolvesHairlineDividerWithoutRaisedSurface() {
        let appearance = MaterialHairlineRow { EmptyView() }.appearance

        XCTAssertNil(appearance.background)
        XCTAssertNil(appearance.cornerRadius)
        XCTAssertEqual(appearance.divider, MaterialTheme.snow.tokens.hairline)
    }

#if canImport(AppKit)
    func testRenderedSheetCloseGlyphUsesResolvedMutedToken() throws {
        let renderer = ImageRenderer(
            content: MaterialSheet {
                EmptyView()
            }
        )
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)

        XCTAssertGreaterThan(mutedPixelCount(in: image), 0)
    }

    func testRenderedCloseButtonHasMinimumInteractiveTargetInBothDimensions() {
        let closeButton = MaterialSheetCloseButton(
            action: {},
            accessibilityLabel: "Close",
            foreground: MaterialTheme.snow.tokens.muted
        )
        let hostingController = NSHostingController(rootView: closeButton)

        let renderedSize = hostingController.view.fittingSize

        XCTAssertGreaterThanOrEqual(renderedSize.width, 44)
        XCTAssertGreaterThanOrEqual(renderedSize.height, 44)
    }

    private func mutedPixelCount(in image: CGImage) -> Int {
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
