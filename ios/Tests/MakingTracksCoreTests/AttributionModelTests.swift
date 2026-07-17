import XCTest
import MakingTracksTiles
@testable import MakingTracksCore

final class AttributionModelTests: XCTestCase {
    func testCreditsRenderManifestAttributionVerbatim() {
        let attribution = [
            Attribution(source: "osm", license: "ODbL-1.0", text: "Place data © OpenStreetMap contributors, licensed under ODbL."),
            Attribution(source: "historic_england", license: "OGL-UK-3.0", text: "Contains Historic England data under the Open Government Licence v3.0."),
            Attribution(source: "open_plaques", license: "PDDL-1.0", text: "[Open Plaques](https://evil.example) %@"),
        ]

        let model = AttributionModel(attribution)

        XCTAssertEqual(model.credits.map(\.text), attribution.map(\.text))
        XCTAssertEqual(model.credits.map(\.license), ["ODbL-1.0", "OGL-UK-3.0", "PDDL-1.0"])
    }

    func testPerPlaceSourceNamesUseAllowlistAndDropMalformedRefs() {
        let model = AttributionModel([])

        XCTAssertEqual(
            model.sourceNames(for: [
                "Historic England:1",
                "colonless",
                "evil:payload",
                "wd:Q42",
                "wp:Big_Ben",
                "osm:node/1",
                "open_plaques:123",
                "historic_england:abc",
            ]),
            ["Historic England", "Open Plaques", "OpenStreetMap", "Wikidata", "Wikipedia"]
        )
    }
}
