import Foundation
import MakingTracksData

public enum PinPresentation: String, Sendable {
    case discovery
    case tracks
}

public struct TrackSegmentSummary: Sendable, Equatable {
    public let features: [JSONValue]
    public let suppressedBurstConnectorCount: Int
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
        pinPresentation: PinPresentation = .discovery
    ) -> [String: JSONValue] {
        [
            "visit": .string(visitTag(state.visit)),
            "saved": .bool(state.saved),
            "hidden": .bool(state.hidden),
            "pin_presentation": .string(pinPresentation.rawValue),
        ]
    }

    public static func feature(
        _ place: MapPlace,
        _ state: PinState,
        pinPresentation: PinPresentation = .discovery
    ) -> JSONValue {
        var props = featureProperties(state, pinPresentation: pinPresentation)
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

    public static func trackSegmentSummary(
        _ visits: [TrackVisit],
        maxConnectorGap: TimeInterval = TrackLayers.defaultMaxConnectorGap,
        burstWindow: TimeInterval = TrackLayers.defaultBurstWindow
    ) -> TrackSegmentSummary {
        guard visits.count >= 2 else {
            return TrackSegmentSummary(
                features: [],
                suppressedBurstConnectorCount: 0,
                connectableVisitCount: visits.count
            )
        }
        var features: [JSONValue] = []
        var suppressedBurstConnectorCount = 0
        var connectableVisitIDs = Set<Int64>()
        for (from, to) in zip(visits, visits.dropFirst()) {
            guard let gap = connectorGap(from: from, to: to),
                  isValidCoordinate(from),
                  isValidCoordinate(to),
                  from.lat != to.lat || from.lon != to.lon
            else { continue }
            if gap <= burstWindow {
                suppressedBurstConnectorCount += 1
                connectableVisitIDs.insert(from.id)
                connectableVisitIDs.insert(to.id)
                continue
            }
            guard gap <= maxConnectorGap else { continue }
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
        let dx = to.lon - from.lon
        let dy = to.lat - from.lat
        let distance = max((dx * dx + dy * dy).squareRoot(), 0.000_001)
        let midpointLon = (from.lon + to.lon) / 2
        let midpointLat = (from.lat + to.lat) / 2
        let normalLon = -dy / distance
        let normalLat = dx / distance
        let offset = distance * TrackLayers.arcBendRatio
        return [
            coordinate(lon: from.lon, lat: from.lat),
            coordinate(
                lon: clamped(midpointLon + normalLon * offset, to: -180.0...180.0),
                lat: clamped(midpointLat + normalLat * offset, to: -90.0...90.0)
            ),
            coordinate(lon: to.lon, lat: to.lat),
        ]
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
