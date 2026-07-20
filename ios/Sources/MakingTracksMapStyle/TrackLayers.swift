import Foundation

public enum TrackLayers {
    public static let sourceID = "tracks"
    public static let lineLayerID = "tracks-line"
    public static let lineColor = "#2d8c83"
    public static let lineCap = "round"
    public static let lineJoin = "round"
    // Tunable per #257; line weight is the legibility dial for dotted abstract connectors.
    public static let lineWidth = 6.2
    public static let lineOpacity = 1.00
    // Tunable per #257; MapLibre dash patterns are line-width units, so convert the render's point units here.
    public static let lineDotLength = 1.0
    public static let lineDotGap = 9.0
    public static let lineDashPatternValues = [lineDotLength / lineWidth, lineDotGap / lineWidth]
    public static let lineStyle = TrackLineStyle(
        cap: lineCap,
        join: lineJoin,
        color: lineColor,
        opacity: lineOpacity,
        width: lineWidth,
        dashPattern: lineDashPatternValues
    )
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
                    "line-cap": .string(lineStyle.cap),
                    "line-join": .string(lineStyle.join),
                ]),
                "paint": .object([
                    "line-color": .string(lineStyle.color),
                    "line-opacity": .double(lineStyle.opacity),
                    "line-width": .double(lineStyle.width),
                    "line-dasharray": .array(lineStyle.dashPattern.map(JSONValue.double)),
                ]),
            ]),
        ]
    }
}
