import SwiftUI
import XCTest
@testable import DesignSystem

final class IconographyTests: XCTestCase {
    func testSharedIconRolesUseTheRatifiedMediumWeight() {
        XCTAssertEqual(
            Iconography.font(for: .standard),
            Font.body.weight(.medium)
        )
        XCTAssertEqual(
            Iconography.font(for: .compact),
            Font.caption.weight(.medium)
        )
    }
}
