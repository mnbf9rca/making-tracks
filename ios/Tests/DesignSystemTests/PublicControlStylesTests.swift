import DesignSystem
import SwiftUI
import XCTest

@MainActor
final class PublicControlStylesTests: XCTestCase {
    func testLayoutsCanUsePublicChipGeometryAndSupplyNeighborGap() {
        XCTAssertEqual(MaterialChipGeometry.visualHeight, 22)
        XCTAssertEqual(MaterialChipGeometry.minimumHitTarget, 44)
        XCTAssertEqual(
            MaterialChipGeometry.hitOutset(for: 22, neighborGap: 8),
            4
        )

        _ = MaterialChip(
            "Nearby",
            state: .available,
            neighborGap: 8,
            action: {}
        )
    }
}
