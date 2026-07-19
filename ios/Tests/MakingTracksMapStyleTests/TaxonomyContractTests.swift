import Foundation
import XCTest
@testable import MakingTracksMapStyle

final class TaxonomyContractTests: XCTestCase {
    func testPinCategoryTaxonomyMatchesPipelineConfig() throws {
        let taxonomy = try loadPipelineTaxonomy()

        XCTAssertEqual(taxonomy.categories.count, Set(taxonomy.categories).count)
        XCTAssertEqual(Set(PinLayers.categoryIconNames.keys), Set(taxonomy.categories))
        XCTAssertEqual(PinLayers.fallbackCategoryID, taxonomy.uncovered)
        XCTAssertFalse(PinLayers.categoryIconNames.keys.contains(taxonomy.uncovered))
        XCTAssertNotNil(PinLayers.categorySymbolNames[PinLayers.fallbackCategoryIconName])
    }

    private func loadPipelineTaxonomy() throws -> PipelineTaxonomy {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let repoRoot = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let taxonomyURL = repoRoot.appendingPathComponent("pipeline/config/taxonomy.json")
        let data = try Data(contentsOf: taxonomyURL)
        return try JSONDecoder().decode(PipelineTaxonomy.self, from: data)
    }

    private struct PipelineTaxonomy: Decodable {
        let categories: [String]
        let uncovered: String
    }
}
