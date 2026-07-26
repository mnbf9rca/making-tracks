import DesignSystem
import Foundation

public enum TrackLayers {
    public static let sourceID = "tracks"
    public static let lineLayerID = "tracks-line"
    public static let activeLineLayerID = "tracks-line-active"
    public static let activeArcPhase = "active"
    public static let trackSegmentPhaseProperty = "track_segment_phase"
    public static let lineColor = MaterialTheme.snow.tokens.trackLine.mapStyleString.lowercased()
    public static let activeLineColor = "#db5344"
    public static let lineCap = "round"
    public static let lineJoin = "round"
    // Tunable per #257; line weight is the legibility dial for dotted abstract connectors.
    public static let lineWidth = 6.2
    public static let activeLineWidth = 7.2
    public static let lineOpacity = 1.00
    public static let activeLineOpacity = 0.90
    // Tunable per #257; MapLibre dash patterns are line-width units, so convert the render's point units here.
    public static let lineDotLength = 1.0
    public static let lineDotGap = 9.0
    public static let lineDashPatternValues = [lineDotLength / lineWidth, lineDotGap / lineWidth]
    public static let activeLineDashPatternValues = [lineDotLength / activeLineWidth, lineDotGap / activeLineWidth]
    public static let lineStyle = TrackLineStyle(
        cap: lineCap,
        join: lineJoin,
        color: lineColor,
        opacity: lineOpacity,
        width: lineWidth,
        dashPattern: lineDashPatternValues
    )
    public static let activeLineStyle = TrackLineStyle(
        cap: lineCap,
        join: lineJoin,
        color: activeLineColor,
        opacity: activeLineOpacity,
        width: activeLineWidth,
        dashPattern: activeLineDashPatternValues
    )
    // Retained for slice-3 animation pacing; drawn track lines connect every consecutive visit by Rob's ruling.
    public static let defaultMaxConnectorGap: TimeInterval = 12 * 60 * 60
    // Retained for slice-3 animation pacing; not used to suppress drawn connectors.
    public static let defaultBurstWindow: TimeInterval = 5 * 60
    // Tunable per B6 §7.3; fixed bend ratio keeps every connector visibly abstract without encoding route knowledge.
    public static let arcBendRatio = 0.18
    // Tunable per #257; enough samples to read as an arc rather than a round-joined angle.
    public static let arcInterpolationPointCount = 9

    public static func trackLayers() -> [JSONValue] {
        [
            lineLayer(id: lineLayerID, style: lineStyle, filter: nil),
            lineLayer(id: activeLineLayerID, style: activeLineStyle, filter: activeArcFilter()),
        ]
    }

    public static func activeArcFilter() -> JSONValue {
        .array([
            .string("=="),
            .array([.string("get"), .string(trackSegmentPhaseProperty)]),
            .string(activeArcPhase),
        ])
    }

    private static func lineLayer(
        id: String,
        style: TrackLineStyle,
        filter: JSONValue?
    ) -> JSONValue {
        var layer: [String: JSONValue] = [
            "id": .string(id),
            "type": .string("line"),
            "source": .string(sourceID),
            "layout": .object([
                "line-cap": .string(style.cap),
                "line-join": .string(style.join),
            ]),
            "paint": .object([
                "line-color": .string(style.color),
                "line-opacity": .double(style.opacity),
                "line-width": .double(style.width),
                "line-dasharray": .array(style.dashPattern.map(JSONValue.double)),
            ]),
        ]
        layer["filter"] = filter
        return .object(layer)
    }
}
