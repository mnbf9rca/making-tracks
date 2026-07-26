import DesignSystem
import SwiftUI
import XCTest

@MainActor
final class PublicControlStylesTests: XCTestCase {
    func testLayoutsCanUsePublicChipGeometryAndSupplyPerEdgeNeighborGaps() {
        XCTAssertEqual(MaterialChipGeometry.visualHeight, 22)
        XCTAssertEqual(MaterialChipGeometry.minimumHitTarget, 44)
        XCTAssertEqual(
            MaterialChipGeometry.tiledHitOutset(neighborGap: 8),
            4
        )

        _ = MaterialChip(
            "Nearby",
            state: .available,
            neighborGaps: MaterialChipNeighborGaps(
                leading: 8,
                trailing: 8
            ),
            action: {}
        )
    }
}
