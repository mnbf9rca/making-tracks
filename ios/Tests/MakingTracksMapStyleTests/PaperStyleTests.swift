import XCTest
@testable import MakingTracksMapStyle

final class PaperStyleTests: XCTestCase {
    func testStyleIsV8WithPmtilesVectorSource() throws {
        let style = paperBasemapStyle(pmtilesURL: "pmtiles://https://tiles.making-tracks.app/malaysia/20260716T155409Z/malaysia.pmtiles")
        guard case let .object(root) = style else { return XCTFail("root not object") }
        XCTAssertEqual(root["version"], .double(8))
        XCTAssertNil(root["glyphs"])
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
        XCTAssertEqual(paintValue("background-color", in: layer(id: "background", in: layers)), .string(MapTheme.definedPaper.background))
        XCTAssertEqual(paintValue("fill-color", in: layer(id: "earth", in: layers)), .string(MapTheme.definedPaper.land))
        XCTAssertEqual(paintValue("fill-color", in: layer(id: "parks", in: layers)), .string(MapTheme.definedPaper.parks))
        XCTAssertEqual(paintValue("fill-color", in: layer(id: "water", in: layers)), .string(MapTheme.definedPaper.water))
        XCTAssertEqual(paintValue("line-color", in: layer(id: "roads", in: layers)), .string(MapTheme.definedPaper.roads))
        XCTAssertEqual(paintValue("line-color", in: layer(id: "boundaries", in: layers)), .string(MapTheme.definedPaper.boundaries))
        XCTAssertEqual(layer(id: "earth", in: layers)?["source-layer"], .string("earth"))
        XCTAssertEqual(layer(id: "parks", in: layers)?["source-layer"], .string("landuse"))
        XCTAssertEqual(layer(id: "water", in: layers)?["source-layer"], .string("water"))
        XCTAssertEqual(layer(id: "roads", in: layers)?["source-layer"], .string("roads"))
        XCTAssertEqual(layer(id: "boundaries", in: layers)?["source-layer"], .string("boundaries"))
        XCTAssertNil(layer(id: "places-label", in: layers))
        XCTAssertNoThrow(try style.jsonString())
    }

    func testSnowThemeRetainsOriginalLayerShape() throws {
        let style = paperBasemapStyle(pmtilesURL: "pmtiles://https://tiles.making-tracks.app/malaysia/current.pmtiles", theme: .snow)
        guard case let .object(root) = style,
              case let .array(layers) = root["layers"]
        else { return XCTFail("no layers") }
        XCTAssertEqual(layerIDs(in: layers), ["background", "earth", "water", "roads", "boundaries"])
        XCTAssertEqual(paintValue("background-color", in: layer(id: "background", in: layers)), .string(MapTheme.snow.background))
        XCTAssertEqual(paintValue("fill-color", in: layer(id: "earth", in: layers)), .string(MapTheme.snow.land))
        XCTAssertEqual(paintValue("fill-color", in: layer(id: "water", in: layers)), .string(MapTheme.snow.water))
        XCTAssertEqual(paintValue("line-color", in: layer(id: "roads", in: layers)), .string(MapTheme.snow.roads))
        XCTAssertEqual(paintValue("line-width", in: layer(id: "roads", in: layers)), .double(MapTheme.snow.roadWidth))
        XCTAssertEqual(paintValue("line-color", in: layer(id: "boundaries", in: layers)), .string(MapTheme.snow.boundaries))
        XCTAssertEqual(paintValue("line-width", in: layer(id: "boundaries", in: layers)), .double(MapTheme.snow.boundaryWidth))
        XCTAssertNil(layer(id: "parks", in: layers))
        XCTAssertNil(layer(id: "places-label", in: layers))
    }

    func testEveryThemeEmitsExpectedLayerStructure() throws {
        for theme in MapTheme.allCandidates {
            let style = paperBasemapStyle(pmtilesURL: "pmtiles://https://tiles.making-tracks.app/malaysia/current.pmtiles", theme: theme)
            guard case let .object(root) = style,
                  case let .object(sources) = root["sources"],
                  case let .object(base) = sources["basemap"],
                  case let .array(layers) = root["layers"]
            else { return XCTFail("invalid root for theme \(theme.id)") }

            XCTAssertNil(root["glyphs"], theme.id)
            XCTAssertEqual(base["type"], .string("vector"), theme.id)
            XCTAssertEqual(base["url"], .string("pmtiles://https://tiles.making-tracks.app/malaysia/current.pmtiles"), theme.id)

            var expectedLayerIDs = ["background", "earth"]
            if theme.showsParks {
                expectedLayerIDs.append("parks")
            }
            expectedLayerIDs += ["water", "roads", "boundaries"]
            XCTAssertEqual(layerIDs(in: layers), expectedLayerIDs, theme.id)

            XCTAssertEqual(layer(id: "background", in: layers)?["type"], .string("background"), theme.id)
            XCTAssertNil(layer(id: "background", in: layers)?["source"], theme.id)
            XCTAssertNil(layer(id: "background", in: layers)?["source-layer"], theme.id)

            XCTAssertEqual(layer(id: "earth", in: layers)?["source"], .string("basemap"), theme.id)
            XCTAssertEqual(layer(id: "earth", in: layers)?["source-layer"], .string("earth"), theme.id)
            XCTAssertEqual(layer(id: "water", in: layers)?["source"], .string("basemap"), theme.id)
            XCTAssertEqual(layer(id: "water", in: layers)?["source-layer"], .string("water"), theme.id)
            XCTAssertEqual(layer(id: "roads", in: layers)?["source"], .string("basemap"), theme.id)
            XCTAssertEqual(layer(id: "roads", in: layers)?["source-layer"], .string("roads"), theme.id)
            XCTAssertEqual(layer(id: "boundaries", in: layers)?["source"], .string("basemap"), theme.id)
            XCTAssertEqual(layer(id: "boundaries", in: layers)?["source-layer"], .string("boundaries"), theme.id)
            XCTAssertEqual(paintValue("line-width", in: layer(id: "roads", in: layers)), .double(theme.roadWidth), theme.id)
            XCTAssertEqual(paintValue("line-width", in: layer(id: "boundaries", in: layers)), .double(theme.boundaryWidth), theme.id)

            if theme.showsParks {
                XCTAssertEqual(layer(id: "parks", in: layers)?["source"], .string("basemap"), theme.id)
                XCTAssertEqual(layer(id: "parks", in: layers)?["source-layer"], .string("landuse"), theme.id)
                XCTAssertEqual(layer(id: "parks", in: layers)?["filter"], expectedParksFilter, theme.id)
            } else {
                XCTAssertNil(layer(id: "parks", in: layers), theme.id)
            }

            XCTAssertNil(layer(id: "places-label", in: layers), theme.id)
            XCTAssertNoThrow(try style.jsonString(), theme.id)
        }
    }

    func testEveryPaletteColourIsMutedAndPinIsSaturated() {
        for theme in MapTheme.allCandidates {
            for hex in [theme.background, theme.land, theme.parks, theme.water, theme.roads, theme.boundaries] {
                XCTAssertLessThan(saturation(hex: hex), MUTED_MAX, "basemap colour \(hex) is not muted in theme \(theme.id)")
            }
        }
        XCTAssertGreaterThanOrEqual(saturation(hex: PinLayers.pinColor), MUTED_MAX, "pin colour must be saturated")
    }

    func testThemesAreNamedTokenSets() {
        XCTAssertEqual(MapTheme.named(nil).id, "defined-paper")
        XCTAssertEqual(MapTheme.named("defined-paper").displayName, "Defined Paper")
        XCTAssertEqual(Set(MapTheme.allCandidates.map(\.id)).count, MapTheme.allCandidates.count)
    }

    private func layer(id: String, in layers: [JSONValue]) -> [String: JSONValue]? {
        for case let .object(layer) in layers where layer["id"] == .string(id) {
            return layer
        }
        return nil
    }

    private func layerIDs(in layers: [JSONValue]) -> [String] {
        layers.compactMap { value in
            guard case let .object(layer) = value,
                  case let .string(id)? = layer["id"]
            else { return nil }
            return id
        }
    }

    private func paintValue(_ key: String, in layer: [String: JSONValue]?) -> JSONValue? {
        guard case let .object(paint)? = layer?["paint"] else { return nil }
        return paint[key]
    }

    private var expectedParksFilter: JSONValue {
        .array([
            .string("in"),
            .array([.string("get"), .string("kind")]),
            .array([.string("literal"), .array([
                .string("park"),
                .string("nature_reserve"),
                .string("forest"),
                .string("wood"),
                .string("grass"),
                .string("garden"),
                .string("cemetery"),
            ])]),
        ])
    }
}
