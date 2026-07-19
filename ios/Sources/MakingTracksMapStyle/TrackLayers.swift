import Foundation

public enum TrackLayers {
    public static let sourceID = "tracks"
    public static let lineLayerID = "tracks-line"
    public static let lineColor = "#315149"
    public static let lineWidth = 2.0
    public static let lineOpacity = 0.82
    public static let lineDashPatternValues = [1.6, 1.2]
    public static let lineDashPattern: JSONValue = .array(lineDashPatternValues.map(JSONValue.double))
    // Tunable per B6 §7.3; suppresses connectors where the log has too large a time hole to imply continuity.
    public static let defaultMaxConnectorGap: TimeInterval = 12 * 60 * 60
    // Tunable per B6 §7.3; short-window batch entries are clusters, not directed travel order.
    public static let defaultBurstWindow: TimeInterval = 5 * 60
    // Tunable per B6 §7.3; fixed bend ratio keeps every connector visibly abstract without encoding route knowledge.
    public static let arcBendRatio = 0.12

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
