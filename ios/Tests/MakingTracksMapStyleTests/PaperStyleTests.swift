import XCTest
@testable import MakingTracksMapStyle

final class PaperStyleTests: XCTestCase {
    func testStyleIsV8WithPmtilesVectorSource() throws {
        let style = paperBasemapStyle(pmtilesURL: "pmtiles://https://tiles.making-tracks.app/malaysia/20260716T155409Z/malaysia.pmtiles")
        guard case let .object(root) = style else { return XCTFail("root not object") }
        XCTAssertEqual(root["version"], .double(8))
        guard case let .object(sources) = root["sources"],
              case let .object(base) = sources["basemap"]
        else { return XCTFail("no basemap source") }
        XCTAssertEqual(base["type"], .string("vector"))
        if case let .string(url) = base["url"] {
            XCTAssertTrue(url.hasPrefix("pmtiles://"))
        } else {
            XCTFail("url")
        }
        guard case let .array(layers) = root["layers"] else { return XCTFail("no layers") }
        XCTAssertTrue(layers.contains {
            if case let .object(layer) = $0 {
                return layer["type"] == .string("background")
            }
            return false
        })
        XCTAssertEqual(paintValue("background-color", in: layer(id: "background", in: layers)), .string(PaperPalette.default.background))
        XCTAssertEqual(paintValue("fill-color", in: layer(id: "earth", in: layers)), .string(PaperPalette.default.land))
        XCTAssertEqual(paintValue("fill-color", in: layer(id: "water", in: layers)), .string(PaperPalette.default.water))
        XCTAssertEqual(paintValue("line-color", in: layer(id: "roads", in: layers)), .string(PaperPalette.default.roads))
        XCTAssertEqual(paintValue("line-color", in: layer(id: "boundaries", in: layers)), .string(PaperPalette.default.boundaries))
        XCTAssertEqual(layer(id: "earth", in: layers)?["source-layer"], .string("earth"))
        XCTAssertEqual(layer(id: "water", in: layers)?["source-layer"], .string("water"))
        XCTAssertEqual(layer(id: "roads", in: layers)?["source-layer"], .string("roads"))
        XCTAssertEqual(layer(id: "boundaries", in: layers)?["source-layer"], .string("boundaries"))
        XCTAssertNoThrow(try style.jsonString())
    }

    func testEveryPaletteColourIsMutedAndPinIsSaturated() {
        let palette = PaperPalette.default
        for hex in [palette.background, palette.land, palette.water, palette.roads, palette.boundaries] {
            XCTAssertLessThan(saturation(hex: hex), MUTED_MAX, "basemap colour \(hex) is not muted")
        }
        XCTAssertGreaterThanOrEqual(saturation(hex: PinLayers.pinColor), MUTED_MAX, "pin colour must be saturated")
    }

    private func layer(id: String, in layers: [JSONValue]) -> [String: JSONValue]? {
        for case let .object(layer) in layers where layer["id"] == .string(id) {
            return layer
        }
        return nil
    }

    private func paintValue(_ key: String, in layer: [String: JSONValue]?) -> JSONValue? {
        guard case let .object(paint)? = layer?["paint"] else { return nil }
        return paint[key]
    }
}
