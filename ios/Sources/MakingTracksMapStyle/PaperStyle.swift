public let MUTED_MAX = 0.25

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
    public var roadWidth: Double
    public var boundaryWidth: Double
    public var showsParks: Bool

    public init(
        id: String,
        displayName: String,
        background: String,
        land: String,
        parks: String,
        water: String,
        roads: String,
        boundaries: String,
        roadWidth: Double,
        boundaryWidth: Double,
        showsParks: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.background = background
        self.land = land
        self.parks = parks
        self.water = water
        self.roads = roads
        self.boundaries = boundaries
        self.roadWidth = roadWidth
        self.boundaryWidth = boundaryWidth
        self.showsParks = showsParks
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
        roadWidth: 0.6,
        boundaryWidth: 0.5,
        showsParks: false
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
        roadWidth: 0.9,
        boundaryWidth: 0.7,
        showsParks: true
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
        roadWidth: 1.15,
        boundaryWidth: 0.8,
        showsParks: true
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
        roadWidth: 0.95,
        boundaryWidth: 0.75,
        showsParks: true
    )

    public static let allCandidates: [MapTheme] = [.snow, .definedPaper, .streetContrast, .verdantKL]

    public static func named(_ id: String?) -> MapTheme {
        allCandidates.first { $0.id == id } ?? .definedPaper
    }
}

private func layer(
    _ id: String,
    _ type: String,
    source: String? = nil,
    sourceLayer: String? = nil,
    filter: JSONValue? = nil,
    paint: [String: JSONValue]
) -> JSONValue {
    var object: [String: JSONValue] = [
        "id": .string(id),
        "type": .string(type),
        "paint": .object(paint),
    ]
    if let source {
        object["source"] = .string(source)
    }
    if let sourceLayer {
        object["source-layer"] = .string(sourceLayer)
    }
    if let filter {
        object["filter"] = filter
    }
    return .object(object)
}

public func paperBasemapStyle(pmtilesURL: String, theme: MapTheme = .definedPaper) -> JSONValue {
    var layers: [JSONValue] = [
        layer("background", "background", paint: ["background-color": .string(theme.background)]),
        layer("earth", "fill", source: "basemap", sourceLayer: "earth", paint: ["fill-color": .string(theme.land)]),
    ]

    if theme.showsParks {
        layers.append(layer("parks", "fill", source: "basemap", sourceLayer: "landuse", filter: .array([
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
        ]), paint: ["fill-color": .string(theme.parks)]))
    }

    layers.append(contentsOf: [
        layer("water", "fill", source: "basemap", sourceLayer: "water", paint: ["fill-color": .string(theme.water)]),
        layer("roads", "line", source: "basemap", sourceLayer: "roads", paint: [
            "line-color": .string(theme.roads),
            "line-width": .double(theme.roadWidth),
        ]),
        layer("boundaries", "line", source: "basemap", sourceLayer: "boundaries", paint: [
            "line-color": .string(theme.boundaries),
            "line-width": .double(theme.boundaryWidth),
        ]),
    ])

    return .object([
        "version": .double(8),
        "sources": .object([
            "basemap": .object([
                "type": .string("vector"),
                "url": .string(pmtilesURL),
            ]),
        ]),
        "layers": .array(layers),
    ])
}
