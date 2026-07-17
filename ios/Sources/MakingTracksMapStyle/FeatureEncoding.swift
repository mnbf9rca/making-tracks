import MakingTracksData

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

    public static func featureProperties(_ state: PinState) -> [String: JSONValue] {
        [
            "visit": .string(visitTag(state.visit)),
            "saved": .bool(state.saved),
            "hidden": .bool(state.hidden),
        ]
    }

    public static func feature(_ place: MapPlace, _ state: PinState) -> JSONValue {
        var props = featureProperties(state)
        props["place_id"] = .string(place.id)
        props["tier"] = .double(Double(place.tier))
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
}
