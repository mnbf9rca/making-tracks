import XCTest
@testable import MakingTracksTiles

final class MapRegionTests: XCTestCase {
    func testSelectsRegionByViewportIntersectionAndKeepsCurrentWhenMidOcean() {
        let malaysia = BBox(minLon: 101.64, minLat: 3.09, maxLon: 101.74, maxLat: 3.19)
        let uk = BBox(minLon: -0.13, minLat: 51.48, maxLon: -0.11, maxLat: 51.50)
        let ocean = BBox(minLon: -32.0, minLat: 22.0, maxLon: -20.0, maxLat: 28.0)

        XCTAssertEqual(MapRegion.select(for: malaysia), .malaysiaSingaporeBrunei)
        XCTAssertEqual(MapRegion.select(for: uk), .unitedKingdom)
        XCTAssertEqual(MapRegion.select(for: ocean, current: .unitedKingdom), .unitedKingdom)
        XCTAssertEqual(MapRegion.select(for: ocean, current: nil), .unitedKingdom)
    }

    func testSupportedRegionReportsCoverageWithoutChangingSelectionFallback() {
        let malaysia = BBox(minLon: 101.64, minLat: 3.09, maxLon: 101.74, maxLat: 3.19)
        let uk = BBox(minLon: -0.13, minLat: 51.48, maxLon: -0.11, maxLat: 51.50)
        let ocean = BBox(minLon: -32.0, minLat: 22.0, maxLon: -20.0, maxLat: 28.0)
        let wideSupported = BBox(minLon: -8.65, minLat: 0.85, maxLon: 119.27, maxLat: 60.86)

        XCTAssertEqual(MapRegion.supportedRegion(for: malaysia), .malaysiaSingaporeBrunei)
        XCTAssertEqual(MapRegion.supportedRegion(for: uk), .unitedKingdom)
        XCTAssertNotNil(MapRegion.supportedRegion(for: wideSupported))
        XCTAssertNil(MapRegion.supportedRegion(for: ocean))
        XCTAssertEqual(MapRegion.select(for: ocean, current: nil), .unitedKingdom)
    }

    func testPublishedRegionIDsUseGeofabrikSlugs() {
        XCTAssertEqual(MapRegion.allCases.map(\.rawValue), [
            "malaysia-singapore-brunei",
            "united-kingdom",
        ])
    }
}
