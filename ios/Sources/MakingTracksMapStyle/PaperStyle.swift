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

public struct PaperPalette: Sendable {
    public var background: String
    public var land: String
    public var water: String
    public var roads: String
    public var boundaries: String

    public init(background: String, land: String, water: String, roads: String, boundaries: String) {
        self.background = background
        self.land = land
        self.water = water
        self.roads = roads
        self.boundaries = boundaries
    }

    public static let `default` = PaperPalette(
        background: "#F4F1EA",
        land: "#ECE8DD",
        water: "#DCE3E5",
        roads: "#E3DED2",
        boundaries: "#CDC7B8"
    )
}

private func layer(
    _ id: String,
    _ type: String,
    source: String? = nil,
    sourceLayer: String? = nil,
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
    return .object(object)
}

public func paperBasemapStyle(pmtilesURL: String, palette: PaperPalette = .default) -> JSONValue {
    .object([
        "version": .double(8),
        "sources": .object([
            "basemap": .object([
                "type": .string("vector"),
                "url": .string(pmtilesURL),
            ]),
        ]),
        "layers": .array([
            layer("background", "background", paint: ["background-color": .string(palette.background)]),
            layer("earth", "fill", source: "basemap", sourceLayer: "earth", paint: ["fill-color": .string(palette.land)]),
            layer("water", "fill", source: "basemap", sourceLayer: "water", paint: ["fill-color": .string(palette.water)]),
            layer("roads", "line", source: "basemap", sourceLayer: "roads", paint: [
                "line-color": .string(palette.roads),
                "line-width": .double(0.6),
            ]),
            layer("boundaries", "line", source: "basemap", sourceLayer: "boundaries", paint: [
                "line-color": .string(palette.boundaries),
                "line-width": .double(0.5),
            ]),
        ]),
    ])
}
