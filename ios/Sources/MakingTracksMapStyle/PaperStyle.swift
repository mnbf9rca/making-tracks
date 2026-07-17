public let MUTED_MAX = 0.25
public let paperBasemapGlyphsURL = "https://tiles.making-tracks.app/global/fonts/{fontstack}/{range}.pbf"

public func saturation(hex: String) -> Double {
    var string = hex
    if string.hasPrefix("#") {
        string.removeFirst()
    }
    guard string.count == 6, let value = UInt32(string, radix: 16) else {
        return 0
    }
    let red = Double((value >> 16) & 0xFF) / 255.0
    let green = Double((value >> 8) & 0xFF) / 255.0
    let blue = Double(value & 0xFF) / 255.0
    let maximum = max(red, green, blue)
    let minimum = min(red, green, blue)
    return maximum == 0 ? 0 : (maximum - minimum) / maximum
}

/// Named basemap theme tokens. This is the deliberate tuning surface for
/// issue #128; style layers consume these tokens rather than baking colors.
public struct MapTheme: Sendable {
    public var id: String
    public var displayName: String
    public var background: String
    public var land: String
    public var parks: String
    public var water: String
    public var roads: String
    public var boundaries: String
    public var labels: String
    public var labelHalo: String
    public var roadWidth: Double
    public var boundaryWidth: Double
    public var showsParks: Bool
    public var showsLabels: Bool

    public init(
        id: String,
        displayName: String,
        background: String,
        land: String,
        parks: String,
        water: String,
        roads: String,
        boundaries: String,
        labels: String,
        labelHalo: String,
        roadWidth: Double,
        boundaryWidth: Double,
        showsParks: Bool,
        showsLabels: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.background = background
        self.land = land
        self.parks = parks
        self.water = water
        self.roads = roads
        self.boundaries = boundaries
        self.labels = labels
        self.labelHalo = labelHalo
        self.roadWidth = roadWidth
        self.boundaryWidth = boundaryWidth
        self.showsParks = showsParks
        self.showsLabels = showsLabels
    }

    public static let snow = MapTheme(
        id: "snow",
        displayName: "Snow",
        background: "#F4F1EA",
        land: "#ECE8DD",
        parks: "#E4E8D8",
        water: "#DCE3E5",
        roads: "#E3DED2",
        boundaries: "#CDC7B8",
        labels: "#676157",
        labelHalo: "#F4F1EA",
        roadWidth: 0.6,
        boundaryWidth: 0.5,
        showsParks: false,
        showsLabels: false
    )

    public static let definedPaper = MapTheme(
        id: "defined-paper",
        displayName: "Defined Paper",
        background: "#F3EFE5",
        land: "#EAE4D3",
        parks: "#DCE6CF",
        water: "#CADCE2",
        roads: "#CEC3AD",
        boundaries: "#AFA48F",
        labels: "#514D45",
        labelHalo: "#F3EFE5",
        roadWidth: 0.9,
        boundaryWidth: 0.7,
        showsParks: true,
        showsLabels: true
    )

    public static let streetContrast = MapTheme(
        id: "street-contrast",
        displayName: "Street Contrast",
        background: "#F2EEE6",
        land: "#EDE8DC",
        parks: "#D8E4C8",
        water: "#C3D9E3",
        roads: "#C4B7A0",
        boundaries: "#9E9482",
        labels: "#4A473F",
        labelHalo: "#F2EEE6",
        roadWidth: 1.15,
        boundaryWidth: 0.8,
        showsParks: true,
        showsLabels: true
    )

    public static let verdantKL = MapTheme(
        id: "verdant-kl",
        displayName: "Verdant KL",
        background: "#F1EDDF",
        land: "#ECE5D2",
        parks: "#CFE1BC",
        water: "#BCD6DE",
        roads: "#D0C0A5",
        boundaries: "#A79A82",
        labels: "#47443B",
        labelHalo: "#F1EDDF",
        roadWidth: 0.95,
        boundaryWidth: 0.75,
        showsParks: true,
        showsLabels: true
    )

    public static let allCandidates: [MapTheme] = [.snow, .definedPaper, .streetContrast, .verdantKL]

    public static func named(_ id: String?) -> MapTheme {
        allCandidates.first { $0.id == id } ?? .definedPaper
    }
}

private struct PaperPalette: Sendable {
    var background: String
    var land: String
    var parks: String
    var water: String
    var roads: String
    var boundaries: String
    var labels: String
    var labelHalo: String

    init(theme: MapTheme) {
        self.background = theme.background
        self.land = theme.land
        self.parks = theme.parks
        self.water = theme.water
        self.roads = theme.roads
        self.boundaries = theme.boundaries
        self.labels = theme.labels
        self.labelHalo = theme.labelHalo
    }
}

private extension MapTheme {
    var paperPalette: PaperPalette {
        PaperPalette(theme: self)
    }
}

private func layer(
    _ id: String,
    _ type: String,
    source: String? = nil,
    sourceLayer: String? = nil,
    minzoom: Double? = nil,
    filter: JSONValue? = nil,
    layout: [String: JSONValue] = [:],
    paint: [String: JSONValue]
) -> JSONValue {
    var object: [String: JSONValue] = [
        "id": .string(id),
        "type": .string(type),
        "paint": .object(paint),
    ]
    if !layout.isEmpty {
        object["layout"] = .object(layout)
    }
    if let source {
        object["source"] = .string(source)
    }
    if let sourceLayer {
        object["source-layer"] = .string(sourceLayer)
    }
    if let minzoom {
        object["minzoom"] = .double(minzoom)
    }
    if let filter {
        object["filter"] = filter
    }
    return .object(object)
}

private func parksFilter() -> JSONValue {
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

private func labelTextField() -> JSONValue {
    .array([
        .string("coalesce"),
        .array([.string("get"), .string("name:en")]),
        .array([.string("get"), .string("name")]),
    ])
}

private func labelTextSize() -> JSONValue {
    .array([
        .string("interpolate"),
        .array([.string("linear")]),
        .array([.string("zoom")]),
        .double(8), .double(10),
        .double(14), .double(14),
    ])
}

private func basemapLayers(sourceID: String, prefix: String, theme: MapTheme) -> [JSONValue] {
    let palette = theme.paperPalette
    var layers: [JSONValue] = [
        layer("\(prefix)-earth", "fill", source: sourceID, sourceLayer: "earth", paint: ["fill-color": .string(palette.land)]),
    ]

    if theme.showsParks {
        layers.append(layer("\(prefix)-parks", "fill", source: sourceID, sourceLayer: "landuse", filter: parksFilter(), paint: [
            "fill-color": .string(palette.parks),
        ]))
    }

    layers.append(contentsOf: [
        layer("\(prefix)-water", "fill", source: sourceID, sourceLayer: "water", paint: ["fill-color": .string(palette.water)]),
        layer("\(prefix)-roads", "line", source: sourceID, sourceLayer: "roads", paint: [
            "line-color": .string(palette.roads),
            "line-width": .double(theme.roadWidth),
        ]),
        layer("\(prefix)-boundaries", "line", source: sourceID, sourceLayer: "boundaries", paint: [
            "line-color": .string(palette.boundaries),
            "line-width": .double(theme.boundaryWidth),
        ]),
    ])

    if theme.showsLabels {
        layers.append(layer("\(prefix)-places-label", "symbol", source: sourceID, sourceLayer: "places", minzoom: 8, layout: [
            "text-field": labelTextField(),
            "text-font": .array([.string("Noto Sans Regular")]),
            "text-size": labelTextSize(),
            "text-allow-overlap": .bool(false),
            "text-ignore-placement": .bool(false),
        ], paint: [
            "text-color": .string(palette.labels),
            "text-halo-color": .string(palette.labelHalo),
            "text-halo-width": .double(1.25),
        ]))
    }

    return layers
}

public func paperBasemapStyle(pmtilesURL: String, theme: MapTheme = .definedPaper) -> JSONValue {
    paperBasemapStyle(worldPMTilesURL: pmtilesURL, regionPMTilesURL: nil, theme: theme)
}

public func paperBasemapStyle(worldPMTilesURL: String?, regionPMTilesURL: String?, theme: MapTheme = .definedPaper) -> JSONValue {
    var sources: [String: JSONValue] = [:]
    if let worldPMTilesURL {
        sources["world"] = .object([
            "type": .string("vector"),
            "url": .string(worldPMTilesURL),
        ])
    }
    if let regionPMTilesURL {
        sources["region"] = .object([
            "type": .string("vector"),
            "url": .string(regionPMTilesURL),
        ])
    }

    var layers: [JSONValue] = [
        layer("background", "background", paint: ["background-color": .string(theme.background)]),
    ]
    if worldPMTilesURL != nil {
        layers.append(contentsOf: basemapLayers(sourceID: "world", prefix: "world", theme: theme))
    }
    if regionPMTilesURL != nil {
        layers.append(contentsOf: basemapLayers(sourceID: "region", prefix: "region", theme: theme))
    }

    var root: [String: JSONValue] = [
        "version": .double(8),
        "sources": .object(sources),
        "layers": .array(layers),
    ]
    if theme.showsLabels {
        root["glyphs"] = .string(paperBasemapGlyphsURL)
    }
    return .object(root)
}
