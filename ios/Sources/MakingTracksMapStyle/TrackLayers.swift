import Foundation

public enum TrackLayers {
    public static let sourceID = "tracks"
    public static let lineLayerID = "tracks-line"
    public static let lineColor = "#315149"
    // Tunable per #257; line weight is a legibility dial for dashed abstract connectors.
    public static let lineWidth = 3.0
    public static let lineOpacity = 0.82
    public static let lineDashPatternValues = [1.6, 1.2]
    public static let lineDashPattern: JSONValue = .array(lineDashPatternValues.map(JSONValue.double))
    // Retained for slice-3 animation pacing; drawn track lines connect every consecutive visit by Rob's ruling.
    public static let defaultMaxConnectorGap: TimeInterval = 12 * 60 * 60
    // Retained for slice-3 animation pacing; not used to suppress drawn connectors.
    public static let defaultBurstWindow: TimeInterval = 5 * 60
    // Tunable per B6 §7.3; fixed bend ratio keeps every connector visibly abstract without encoding route knowledge.
    public static let arcBendRatio = 0.12
    // Tunable per #257; enough samples to read as an arc rather than a round-joined angle.
    public static let arcInterpolationPointCount = 9

    public static func trackLayers() -> [JSONValue] {
        [
            .object([
                "id": .string(lineLayerID),
                "type": .string("line"),
                "source": .string(sourceID),
                "layout": .object([
                    "line-cap": .string("round"),
                    "line-join": .string("round"),
                ]),
                "paint": .object([
                    "line-color": .string(lineColor),
                    "line-opacity": .double(lineOpacity),
                    "line-width": .double(lineWidth),
                    "line-dasharray": lineDashPattern,
                ]),
            ]),
        ]
    }
}
