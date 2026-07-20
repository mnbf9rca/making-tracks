import Foundation
import MakingTracksData

public enum PinPresentation: String, Sendable {
    case discovery
    case tracks
    case trackReplay
}

public struct TrackSegmentSummary: Sendable, Equatable {
    /// Drawn connector features. Current continuity rules connect every valid consecutive visit.
    public let features: [JSONValue]
    /// Compatibility field for pre-continuity callers. Burst connectors are no longer suppressed, so this is fixed at 0.
    public let suppressedBurstConnectorCount: Int
    /// Count of visits participating in at least one drawable connector.
    public let connectableVisitCount: Int
}

public enum FeatureEncoding {
    static func visitTag(_ visit: VisitState) -> String {
        switch visit {
        case .none:
            return "none"
        case .visited:
            return "visited"
        case .loved:
            return "loved"
        }
    }

    public static func featureProperties(
        _ state: PinState,
        pinPresentation: PinPresentation = .discovery,
        trackReplayPulse: Bool = false
    ) -> [String: JSONValue] {
        [
            "visit": .string(visitTag(state.visit)),
            "saved": .bool(state.saved),
            "hidden": .bool(state.hidden),
            "pin_presentation": .string(pinPresentation.rawValue),
            "track_replay_pulse": .bool(trackReplayPulse),
        ]
    }

    public static func feature(
        _ place: MapPlace,
        _ state: PinState,
        pinPresentation: PinPresentation = .discovery,
        trackReplayPulse: Bool = false
    ) -> JSONValue {
        var props = featureProperties(
            state,
            pinPresentation: pinPresentation,
            trackReplayPulse: trackReplayPulse
        )
        props["place_id"] = .string(place.id)
        props["tier"] = .double(Double(place.tier))
        props["category"] = .string(place.category)
        return .object([
            "type": .string("Feature"),
            "geometry": .object([
                "type": .string("Point"),
                "coordinates": .array([.double(place.lon), .double(place.lat)]),
            ]),
            "properties": .object(props),
        ])
    }

    public static func featureCollection(_ features: [JSONValue]) -> JSONValue {
        .object([
            "type": .string("FeatureCollection"),
            "features": .array(features),
        ])
    }

    /// Encodes abstract track connector features using the current continuity rule.
    /// `maxConnectorGap` and `burstWindow` are retained for source compatibility
    /// with older callers and do not affect connector suppression.
    public static func trackSegmentFeatures(
        _ visits: [TrackVisit],
        maxConnectorGap: TimeInterval = TrackLayers.defaultMaxConnectorGap,
        burstWindow: TimeInterval = TrackLayers.defaultBurstWindow
    ) -> [JSONValue] {
        trackSegmentSummary(
            visits,
            maxConnectorGap: maxConnectorGap,
            burstWindow: burstWindow
        ).features
    }

    /// Summarizes abstract track connectors using the current continuity rule:
    /// every valid consecutive visit pair is connected. `maxConnectorGap` and
    /// `burstWindow` are retained for source compatibility with older callers
    /// and do not affect connector suppression.
    public static func trackSegmentSummary(
        _ visits: [TrackVisit],
        maxConnectorGap: TimeInterval = TrackLayers.defaultMaxConnectorGap,
        burstWindow: TimeInterval = TrackLayers.defaultBurstWindow
    ) -> TrackSegmentSummary {
        // Gap and burst thresholds are retained for callers while continuity now connects every valid consecutive visit.
        _ = maxConnectorGap
        _ = burstWindow
        guard visits.count >= 2 else {
            return TrackSegmentSummary(
                features: [],
                suppressedBurstConnectorCount: 0,
                connectableVisitCount: visits.count
            )
        }
        var features: [JSONValue] = []
        let suppressedBurstConnectorCount = 0
        var connectableVisitIDs = Set<Int64>()
        for (from, to) in zip(visits, visits.dropFirst()) {
            guard let gap = connectorGap(from: from, to: to),
                  isValidCoordinate(from),
                  isValidCoordinate(to),
                  from.lat != to.lat || from.lon != to.lon
            else { continue }
            connectableVisitIDs.insert(from.id)
            connectableVisitIDs.insert(to.id)
            features.append(trackSegmentFeature(from: from, to: to, gap: gap))
        }
        return TrackSegmentSummary(
            features: features,
            suppressedBurstConnectorCount: suppressedBurstConnectorCount,
            connectableVisitCount: connectableVisitIDs.count
        )
    }

    private static func trackSegmentFeature(from: TrackVisit, to: TrackVisit, gap: TimeInterval) -> JSONValue {
        .object([
            "type": .string("Feature"),
            "geometry": .object([
                "type": .string("LineString"),
                "coordinates": .array(trackArcCoordinates(from: from, to: to)),
            ]),
            "properties": .object([
                "from_visit_id": .double(Double(from.id)),
                "to_visit_id": .double(Double(to.id)),
                "gap_seconds": .double(gap),
            ]),
        ])
    }

    private static func trackArcCoordinates(from: TrackVisit, to: TrackVisit) -> [JSONValue] {
        let rawDX = to.lon - from.lon
        let wrapsAntimeridian = abs(rawDX) > 180.0
        let dx = wrapsAntimeridian ? shortestLongitudeDelta(from: from.lon, to: to.lon) : rawDX
        let renderedToLon = wrapsAntimeridian ? from.lon + dx : to.lon
        let referenceLatitude = clamped((from.lat + to.lat) / 2, to: -85.0...85.0)
        let lonScale = max(abs(cos(referenceLatitude * .pi / 180)), 0.000_001)
        let start = (x: from.lon * lonScale, y: from.lat)
        let end = (x: renderedToLon * lonScale, y: to.lat)
        let projectedDX = end.x - start.x
        let projectedDY = end.y - start.y
        let distance = max((projectedDX * projectedDX + projectedDY * projectedDY).squareRoot(), 0.000_001)
        let midpoint = (x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let offset = distance * TrackLayers.arcBendRatio * 2
        let control = (
            x: midpoint.x + (-projectedDY / distance) * offset,
            y: midpoint.y + (projectedDX / distance) * offset
        )
        let pointCount = max(TrackLayers.arcInterpolationPointCount, 3)
        return (0..<pointCount).map { index in
            if index == 0 {
                return coordinate(lon: from.lon, lat: from.lat)
            }
            if index == pointCount - 1 {
                return coordinate(lon: renderedToLon, lat: to.lat)
            }
            let t = Double(index) / Double(pointCount - 1)
            let oneMinusT = 1 - t
            let projectedX = (oneMinusT * oneMinusT * start.x)
                + (2 * oneMinusT * t * control.x)
                + (t * t * end.x)
            let projectedY = (oneMinusT * oneMinusT * start.y)
                + (2 * oneMinusT * t * control.y)
                + (t * t * end.y)
            let lon = projectedX / lonScale
            return coordinate(
                lon: wrapsAntimeridian ? lon : clamped(lon, to: -180.0...180.0),
                lat: clamped(projectedY, to: -90.0...90.0)
            )
        }
    }

    private static func shortestLongitudeDelta(from: Double, to: Double) -> Double {
        var delta = to - from
        if delta > 180.0 {
            delta -= 360.0
        } else if delta < -180.0 {
            delta += 360.0
        }
        return delta
    }

    private static func clamped(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private static func coordinate(lon: Double, lat: Double) -> JSONValue {
        .array([.double(lon), .double(lat)])
    }

    private static func connectorGap(from: TrackVisit, to: TrackVisit) -> TimeInterval? {
        let gap = to.visitedAt.timeIntervalSince(from.visitedAt)
        return gap >= 0 ? gap : nil
    }

    private static func isValidCoordinate(_ visit: TrackVisit) -> Bool {
        visit.lat.isFinite
            && visit.lon.isFinite
            && (-90.0...90.0).contains(visit.lat)
            && (-180.0...180.0).contains(visit.lon)
    }
}
