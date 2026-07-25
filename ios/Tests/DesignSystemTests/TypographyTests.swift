@testable import DesignSystem
import SwiftUI
import XCTest

final class TypographyTests: XCTestCase {
    func testEveryRatifiedRoleIsAvailableThroughTheRoleOnlyAPI() {
        let contractRoles: [TypographyRole] = [
            .display,
            .sheetTitle,
            .placeName,
            .listRowTitle,
            .evocativeSubline,
            .button,
            .label,
            .metadata,
            .body,
            .data,
        ]

        XCTAssertEqual(Set(TypographyRole.allCases), Set(contractRoles))

        for role in contractRoles {
            let font: Font = Typography.font(for: role)
            _ = font
        }
    }
}
