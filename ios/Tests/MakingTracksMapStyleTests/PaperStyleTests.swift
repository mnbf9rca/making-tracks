import XCTest
import DesignSystem
@testable import MakingTracksMapStyle

final class PaperStyleTests: XCTestCase {
    func testSnowThemeUsesTheMaterialSheetMapRows() {
        let tokens = MaterialTheme.snow.tokens

        XCTAssertEqual(MapTheme.snow.background, tokens.background.mapStyleString)
        XCTAssertEqual(MapTheme.snow.land, tokens.ground.mapStyleString)
        XCTAssertEqual(MapTheme.snow.parks, tokens.park.mapStyleString)
        XCTAssertEqual(MapTheme.snow.water, tokens.water.mapStyleString)
        XCTAssertEqual(MapTheme.snow.roads, tokens.road.mapStyleString)
        XCTAssertEqual(MapTheme.snow.boundaries, tokens.boundaries.mapStyleString)
        XCTAssertEqual(MapTheme.snow.labels, tokens.labels.mapStyleString)
        XCTAssertEqual(MapTheme.snow.labelHalo, tokens.labelHalo.mapStyleString)
    }

    func testStyleIsV8WithPmtilesVectorSource() throws {
        let style = paperBasemapStyle(pmtilesURL: "pmtiles://https://tiles.making-tracks.app/malaysia/20260716T155409Z/malaysia.pmtiles")
        guard case let .object(root) = style else { return XCTFail("root not object") }
        XCTAssertEqual(root["version"], .double(8))
        XCTAssertEqual(paperBasemapGlyphsURL, "https://tiles.making-tracks.app/global/fonts/{fontstack}/{range}.pbf")
        XCTAssertEqual(root["glyphs"], .string(paperBasemapGlyphsURL))
        guard case let .object(sources) = root["sources"],
              case let .object(world) = sources["world"]
        else { return XCTFail("no world source") }
        XCTAssertEqual(world["type"], .string("vector"))
        if case let .string(url) = world["url"] {
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
        XCTAssertEqual(paintValue("fill-color", in: layer(id: "world-earth", in: layers)), .string(MapTheme.definedPaper.land))
        XCTAssertEqual(paintValue("fill-color", in: layer(id: "world-parks", in: layers)), .string(MapTheme.definedPaper.parks))
        XCTAssertEqual(paintValue("fill-color", in: layer(id: "world-water", in: layers)), .string(MapTheme.definedPaper.water))
        XCTAssertEqual(paintValue("line-color", in: layer(id: "world-roads", in: layers)), .string(MapTheme.definedPaper.roads))
        XCTAssertEqual(paintValue("line-color", in: layer(id: "world-boundaries", in: layers)), .string(MapTheme.definedPaper.boundaries))
        XCTAssertEqual(paintValue("text-color", in: layer(id: "world-places-label", in: layers)), .string(MapTheme.definedPaper.labels))
        XCTAssertEqual(paintValue("text-halo-color", in: layer(id: "world-places-label", in: layers)), .string(MapTheme.definedPaper.labelHalo))
        XCTAssertEqual(layer(id: "world-earth", in: layers)?["source-layer"], .string("earth"))
        XCTAssertEqual(layer(id: "world-parks", in: layers)?["source-layer"], .string("landuse"))
        XCTAssertEqual(layer(id: "world-water", in: layers)?["source-layer"], .string("water"))
        XCTAssertEqual(layer(id: "world-roads", in: layers)?["source-layer"], .string("roads"))
        XCTAssertEqual(layer(id: "world-boundaries", in: layers)?["source-layer"], .string("boundaries"))
        XCTAssertEqual(layer(id: "world-places-label", in: layers)?["source-layer"], .string("places"))
        XCTAssertEqual(layoutValue("text-font", in: layer(id: "world-places-label", in: layers)), .array([.string("Noto Sans Regular")]))
        XCTAssertNoThrow(try style.jsonString())
    }

    func testSnowThemeRetainsOriginalLayerShape() throws {
        let style = paperBasemapStyle(pmtilesURL: "pmtiles://https://tiles.making-tracks.app/malaysia/current.pmtiles", theme: .snow)
        guard case let .object(root) = style,
              case let .array(layers) = root["layers"]
        else { return XCTFail("no layers") }
        XCTAssertEqual(root["glyphs"], .string(paperBasemapGlyphsURL))
        XCTAssertEqual(layerIDs(in: layers), ["background", "world-earth", "world-water", "world-waterways", "world-roads", "world-boundaries"])
        XCTAssertEqual(paintValue("background-color", in: layer(id: "background", in: layers)), .string(MapTheme.snow.background))
        XCTAssertEqual(paintValue("fill-color", in: layer(id: "world-earth", in: layers)), .string(MapTheme.snow.land))
        XCTAssertEqual(paintValue("fill-color", in: layer(id: "world-water", in: layers)), .string(MapTheme.snow.water))
        XCTAssertEqual(layer(id: "world-water", in: layers)?["filter"], expectedWaterFillFilter)
        XCTAssertEqual(paintValue("line-color", in: layer(id: "world-waterways", in: layers)), .string(MapTheme.snow.water))
        XCTAssertEqual(paintValue("line-width", in: layer(id: "world-waterways", in: layers)), .double(0.8))
        XCTAssertEqual(layer(id: "world-waterways", in: layers)?["filter"], expectedWaterwayLineFilter)
        XCTAssertEqual(paintValue("line-color", in: layer(id: "world-roads", in: layers)), .string(MapTheme.snow.roads))
        XCTAssertEqual(paintValue("line-width", in: layer(id: "world-roads", in: layers)), .double(MapTheme.snow.roadWidth))
        XCTAssertEqual(paintValue("line-color", in: layer(id: "world-boundaries", in: layers)), .string(MapTheme.snow.boundaries))
        XCTAssertEqual(paintValue("line-width", in: layer(id: "world-boundaries", in: layers)), .double(MapTheme.snow.boundaryWidth))
        XCTAssertNil(layer(id: "world-parks", in: layers))
        XCTAssertNil(layer(id: "world-places-label", in: layers))
    }

    func testEveryThemeEmitsExpectedLayerStructure() throws {
        for theme in MapTheme.allCandidates {
            let style = paperBasemapStyle(pmtilesURL: "pmtiles://https://tiles.making-tracks.app/malaysia/current.pmtiles", theme: theme)
            guard case let .object(root) = style,
                  case let .object(sources) = root["sources"],
                  case let .object(world) = sources["world"],
                  case let .array(layers) = root["layers"]
            else { return XCTFail("invalid root for theme \(theme.id)") }

            XCTAssertEqual(root["glyphs"], .string(paperBasemapGlyphsURL), theme.id)
            XCTAssertEqual(world["type"], .string("vector"), theme.id)
            XCTAssertEqual(world["url"], .string("pmtiles://https://tiles.making-tracks.app/malaysia/current.pmtiles"), theme.id)

            var expectedLayerIDs = ["background", "world-earth"]
            if theme.showsParks {
                expectedLayerIDs.append("world-parks")
            }
            expectedLayerIDs += ["world-water", "world-waterways", "world-roads", "world-boundaries"]
            if theme.showsLabels {
                expectedLayerIDs.append("world-places-label")
            }
            XCTAssertEqual(layerIDs(in: layers), expectedLayerIDs, theme.id)

            XCTAssertEqual(layer(id: "background", in: layers)?["type"], .string("background"), theme.id)
            XCTAssertNil(layer(id: "background", in: layers)?["source"], theme.id)
            XCTAssertNil(layer(id: "background", in: layers)?["source-layer"], theme.id)

            XCTAssertEqual(layer(id: "world-earth", in: layers)?["source"], .string("world"), theme.id)
            XCTAssertEqual(layer(id: "world-earth", in: layers)?["source-layer"], .string("earth"), theme.id)
            XCTAssertEqual(layer(id: "world-water", in: layers)?["source"], .string("world"), theme.id)
            XCTAssertEqual(layer(id: "world-water", in: layers)?["source-layer"], .string("water"), theme.id)
            XCTAssertEqual(layer(id: "world-water", in: layers)?["filter"], expectedWaterFillFilter, theme.id)
            XCTAssertEqual(layer(id: "world-waterways", in: layers)?["type"], .string("line"), theme.id)
            XCTAssertEqual(layer(id: "world-waterways", in: layers)?["source"], .string("world"), theme.id)
            XCTAssertEqual(layer(id: "world-waterways", in: layers)?["source-layer"], .string("water"), theme.id)
            XCTAssertEqual(layer(id: "world-waterways", in: layers)?["filter"], expectedWaterwayLineFilter, theme.id)
            XCTAssertEqual(paintValue("line-color", in: layer(id: "world-waterways", in: layers)), .string(theme.water), theme.id)
            XCTAssertEqual(paintValue("line-width", in: layer(id: "world-waterways", in: layers)), .double(0.8), theme.id)
            XCTAssertEqual(layer(id: "world-roads", in: layers)?["source"], .string("world"), theme.id)
            XCTAssertEqual(layer(id: "world-roads", in: layers)?["source-layer"], .string("roads"), theme.id)
            XCTAssertEqual(layer(id: "world-boundaries", in: layers)?["source"], .string("world"), theme.id)
            XCTAssertEqual(layer(id: "world-boundaries", in: layers)?["source-layer"], .string("boundaries"), theme.id)
            XCTAssertEqual(paintValue("line-width", in: layer(id: "world-roads", in: layers)), .double(theme.roadWidth), theme.id)
            XCTAssertEqual(paintValue("line-width", in: layer(id: "world-boundaries", in: layers)), .double(theme.boundaryWidth), theme.id)

            if theme.showsParks {
                XCTAssertEqual(layer(id: "world-parks", in: layers)?["source"], .string("world"), theme.id)
                XCTAssertEqual(layer(id: "world-parks", in: layers)?["source-layer"], .string("landuse"), theme.id)
                XCTAssertEqual(layer(id: "world-parks", in: layers)?["filter"], expectedParksFilter, theme.id)
            } else {
                XCTAssertNil(layer(id: "world-parks", in: layers), theme.id)
            }

            if theme.showsLabels {
                XCTAssertEqual(layer(id: "world-places-label", in: layers)?["type"], .string("symbol"), theme.id)
                XCTAssertEqual(layer(id: "world-places-label", in: layers)?["source"], .string("world"), theme.id)
                XCTAssertEqual(layer(id: "world-places-label", in: layers)?["source-layer"], .string("places"), theme.id)
                XCTAssertEqual(layer(id: "world-places-label", in: layers)?["minzoom"], .double(8), theme.id)
                XCTAssertEqual(layoutValue("text-field", in: layer(id: "world-places-label", in: layers)), expectedLabelTextField, theme.id)
                XCTAssertEqual(layoutValue("text-font", in: layer(id: "world-places-label", in: layers)), .array([.string("Noto Sans Regular")]), theme.id)
                XCTAssertEqual(layoutValue("text-size", in: layer(id: "world-places-label", in: layers)), expectedLabelTextSize, theme.id)
                XCTAssertEqual(layoutValue("text-allow-overlap", in: layer(id: "world-places-label", in: layers)), .bool(false), theme.id)
                XCTAssertEqual(layoutValue("text-ignore-placement", in: layer(id: "world-places-label", in: layers)), .bool(false), theme.id)
                XCTAssertEqual(paintValue("text-color", in: layer(id: "world-places-label", in: layers)), .string(theme.labels), theme.id)
                XCTAssertEqual(paintValue("text-halo-color", in: layer(id: "world-places-label", in: layers)), .string(theme.labelHalo), theme.id)
                XCTAssertEqual(paintValue("text-halo-width", in: layer(id: "world-places-label", in: layers)), .double(1.25), theme.id)
            } else {
                XCTAssertNil(layer(id: "world-places-label", in: layers), theme.id)
            }
            XCTAssertNoThrow(try style.jsonString(), theme.id)
        }
    }

    func testStackedWorldAndRegionSourcesUseTheSameThemeTokens() throws {
        let style = paperBasemapStyle(
            worldPMTilesURL: "pmtiles://https://tiles.making-tracks.app/global/protomaps-20260714-z0-6.pmtiles",
            regionPMTilesURL: "pmtiles://https://tiles.making-tracks.app/malaysia/20260716T155409Z/malaysia.pmtiles"
        )
        guard case let .object(root) = style,
              case let .object(sources) = root["sources"],
              case let .object(world) = sources["world"],
              case let .object(region) = sources["region"],
              case let .array(layers) = root["layers"]
        else { return XCTFail("stacked style shape") }

        XCTAssertEqual(world["type"], .string("vector"))
        XCTAssertEqual(region["type"], .string("vector"))
        for id in [
            "background",
            "world-earth", "world-parks", "world-water", "world-waterways", "world-roads", "world-boundaries", "world-places-label",
            "region-earth", "region-parks", "region-water", "region-waterways", "region-roads", "region-boundaries", "region-places-label",
        ] {
            XCTAssertNotNil(layer(id: id, in: layers), id)
        }
        XCTAssertEqual(paintValue("fill-color", in: layer(id: "region-earth", in: layers)), .string(MapTheme.definedPaper.land))
        XCTAssertEqual(paintValue("fill-color", in: layer(id: "region-parks", in: layers)), .string(MapTheme.definedPaper.parks))
        XCTAssertEqual(paintValue("fill-color", in: layer(id: "region-water", in: layers)), .string(MapTheme.definedPaper.water))
        XCTAssertEqual(layer(id: "region-water", in: layers)?["filter"], expectedWaterFillFilter)
        XCTAssertEqual(layer(id: "region-waterways", in: layers)?["filter"], expectedWaterwayLineFilter)
        XCTAssertEqual(paintValue("line-color", in: layer(id: "region-waterways", in: layers)), .string(MapTheme.definedPaper.water))
        XCTAssertEqual(paintValue("line-color", in: layer(id: "region-roads", in: layers)), .string(MapTheme.definedPaper.roads))
        XCTAssertEqual(paintValue("line-color", in: layer(id: "region-boundaries", in: layers)), .string(MapTheme.definedPaper.boundaries))
    }

    func testCoverageMaskHolesOutEveryInstalledPackAboveWorldAndBelowRegionLayers() throws {
        for theme in MapTheme.allCandidates {
            let style = paperBasemapStyle(
                worldPMTilesURL: "pmtiles://https://tiles.making-tracks.app/global/protomaps-20260714-z0-6.pmtiles",
                regionPMTilesURL: "pmtiles://https://tiles.making-tracks.app/malaysia/20260716T155409Z/malaysia.pmtiles",
                coverageBBoxes: [
                    CoverageBBox(minLon: -8.65, minLat: 49.84, maxLon: 1.77, maxLat: 60.86),
                    CoverageBBox(minLon: 99.60, minLat: 0.80, maxLon: 119.30, maxLat: 7.60),
                ],
                theme: theme
            )
            guard case let .object(root) = style,
                  case let .object(sources) = root["sources"],
                  case let .object(maskSource) = sources["coverage-mask"],
                  case let .object(data) = maskSource["data"],
                  case let .array(features) = data["features"],
                  case let .object(feature) = features.first,
                  case let .object(geometry) = feature["geometry"],
                  case let .array(coordinates) = geometry["coordinates"],
                  case let .array(layers) = root["layers"]
            else { return XCTFail("coverage mask style shape for \(theme.id)") }

            XCTAssertEqual(maskSource["type"], .string("geojson"), theme.id)
            XCTAssertEqual(geometry["type"], .string("Polygon"), theme.id)
            XCTAssertEqual(coordinates.count, 3, theme.id)
            XCTAssertLessThan(
                layerIDs(in: layers).firstIndex(of: "coverage-mask-fill") ?? .max,
                layerIDs(in: layers).firstIndex(of: "region-earth") ?? .max,
                theme.id
            )
            XCTAssertGreaterThan(
                layerIDs(in: layers).firstIndex(of: "coverage-mask-fill") ?? .min,
                layerIDs(in: layers).firstIndex(of: "world-boundaries") ?? .min,
                theme.id
            )
            XCTAssertEqual(paintValue("fill-color", in: layer(id: "coverage-mask-fill", in: layers)), .string(theme.background), theme.id)
            XCTAssertEqual(paintValue("fill-opacity", in: layer(id: "coverage-mask-fill", in: layers)), .double(0.46), theme.id)
            XCTAssertEqual(paintValue("line-color", in: layer(id: "coverage-mask-edge", in: layers)), .string(theme.boundaries), theme.id)
            XCTAssertEqual(paintValue("line-opacity", in: layer(id: "coverage-mask-edge", in: layers)), .double(0.22), theme.id)
            XCTAssertEqual(layer(id: "coverage-mask-fill", in: layers)?["minzoom"], .double(7), theme.id)
            XCTAssertEqual(layer(id: "coverage-mask-edge", in: layers)?["minzoom"], .double(7), theme.id)
            XCTAssertNoThrow(try style.jsonString(), theme.id)
        }
    }

    func testEveryPaletteColourIsMutedAndPinIsSaturated() {
        for theme in MapTheme.allCandidates {
            for hex in [theme.background, theme.land, theme.parks, theme.water, theme.roads, theme.boundaries, theme.labels, theme.labelHalo] {
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

    private func layoutValue(_ key: String, in layer: [String: JSONValue]?) -> JSONValue? {
        guard case let .object(layout)? = layer?["layout"] else { return nil }
        return layout[key]
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

    private var expectedWaterFillFilter: JSONValue {
        .array([
            .string("=="),
            .array([.string("geometry-type")]),
            .string("Polygon"),
        ])
    }

    private var expectedWaterwayLineFilter: JSONValue {
        .array([
            .string("all"),
            .array([
                .string("=="),
                .array([.string("geometry-type")]),
                .string("LineString"),
            ]),
            .array([
                .string("any"),
                .array([
                    .string("in"),
                    .array([.string("get"), .string("kind")]),
                    .array([.string("literal"), expectedWaterwayKinds]),
                ]),
                .array([
                    .string("in"),
                    .array([.string("get"), .string("kind_detail")]),
                    .array([.string("literal"), expectedWaterwayKinds]),
                ]),
            ]),
            .array([
                .string("<="),
                .array([
                    .string("case"),
                    .array([.string("has"), .string("min_zoom")]),
                    .array([.string("to-number"), .array([.string("get"), .string("min_zoom")])]),
                    .double(14),
                ]),
                .array([.string("zoom")]),
            ]),
        ])
    }

    private var expectedWaterwayKinds: JSONValue {
        .array([
            .string("river"),
            .string("stream"),
            .string("canal"),
            .string("drain"),
        ])
    }

    private var expectedLabelTextField: JSONValue {
        .array([
            .string("coalesce"),
            .array([.string("get"), .string("name:en")]),
            .array([.string("get"), .string("name")]),
        ])
    }

    private var expectedLabelTextSize: JSONValue {
        .array([
            .string("interpolate"),
            .array([.string("linear")]),
            .array([.string("zoom")]),
            .double(8), .double(10),
            .double(14), .double(14),
        ])
    }
}
