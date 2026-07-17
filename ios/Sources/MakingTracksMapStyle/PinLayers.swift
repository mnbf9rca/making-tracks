import MakingTracksData

public enum PinLayers {
    public static let pinColor = "#E4572E"
    public static let sourceID = "pins"
    public static let bookmarkOffset: JSONValue = .array([.double(8), .double(-8)])
    public static let heartOffset: JSONValue = .array([.double(-8), .double(-8)])

    public static func fadeOpacityExpression() -> JSONValue {
        var expression: [JSONValue] = [
            .string("match"),
            .array([.string("get"), .string("visit")]),
        ]
        for visit in [VisitState.none, .visited, .loved] {
            expression.append(.string(FeatureEncoding.visitTag(visit)))
            expression.append(.double(pinAppearance(PinState(saved: false, visit: visit)).opacity))
        }
        expression.append(.double(FULL_OPACITY))
        return .array(expression)
    }

    public static func bookmarkFilter() -> JSONValue {
        .array([.string("=="), .array([.string("get"), .string("saved")]), .bool(true)])
    }

    public static func heartFilter() -> JSONValue {
        .array([.string("=="), .array([.string("get"), .string("visit")]), .string("loved")])
    }

    public static func pinLayers() -> [JSONValue] {
        [
            .object([
                "id": .string("pins-circle"),
                "type": .string("circle"),
                "source": .string(sourceID),
                "paint": .object([
                    "circle-color": .string(pinColor),
                    "circle-opacity": fadeOpacityExpression(),
                    "circle-radius": .double(6),
                ]),
            ]),
            .object([
                "id": .string("pins-bookmark"),
                "type": .string("symbol"),
                "source": .string(sourceID),
                "filter": bookmarkFilter(),
                "layout": .object([
                    "icon-image": .string("badge-bookmark"),
                    "icon-allow-overlap": .bool(true),
                    "icon-offset": bookmarkOffset,
                ]),
            ]),
            .object([
                "id": .string("pins-heart"),
                "type": .string("symbol"),
                "source": .string(sourceID),
                "filter": heartFilter(),
                "layout": .object([
                    "icon-image": .string("badge-heart"),
                    "icon-allow-overlap": .bool(true),
                    "icon-offset": heartOffset,
                ]),
            ]),
        ]
    }
}
