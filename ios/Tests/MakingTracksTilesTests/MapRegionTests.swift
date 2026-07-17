import XCTest
@testable import MakingTracksTiles

final class MapRegionTests: XCTestCase {
    func testSelectsRegionByViewportIntersectionAndKeepsCurrentWhenMidOcean() {
        let malaysia = BBox(minLon: 101.64, minLat: 3.09, maxLon: 101.74, maxLat: 3.19)
        let uk = BBox(minLon: -0.13, minLat: 51.48, maxLon: -0.11, maxLat: 51.50)
        let ocean = BBox(minLon: -32.0, minLat: 22.0, maxLon: -20.0, maxLat: 28.0)

        XCTAssertEqual(MapRegion.select(for: malaysia), .malaysia)
        XCTAssertEqual(MapRegion.select(for: uk), .uk)
        XCTAssertEqual(MapRegion.select(for: ocean, current: .uk), .uk)
        XCTAssertEqual(MapRegion.select(for: ocean, current: nil), .uk)
    }
}
