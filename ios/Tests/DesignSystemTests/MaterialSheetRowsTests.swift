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

    private func color(
        _ red: UInt8,
        _ green: UInt8,
        _ blue: UInt8,
        opacity: Double = 1
    ) -> MaterialColor {
        MaterialColor(red: red, green: green, blue: blue, opacity: opacity)
    }
}
