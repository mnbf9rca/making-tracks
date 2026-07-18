import MakingTracksData

public enum PinLayers {
    public static let pinColor = "#E4572E"
    public static let sourceID = "pins"
    public static let bookmarkOffset: JSONValue = .array([.double(8), .double(-8)])
    public static let heartOffset: JSONValue = .array([.double(-8), .double(-8)])
    public static let categoryIconScale = 0.62
    public static let fallbackCategoryIconName = "pin-category-uncategorized"
    public static let categoryIconNames: [String: String] = [
        "religious": "pin-category-religious",
        "memorial": "pin-category-memorial",
        "archaeological": "pin-category-archaeological",
        "historic_building": "pin-category-historic-building",
        "museum": "pin-category-museum",
        "attraction": "pin-category-attraction",
        "artwork": "pin-category-artwork",
    ]
    public static let categorySymbolNames: [String: String] = [
        fallbackCategoryIconName: "questionmark.circle.fill",
        "pin-category-religious": "building.columns.fill",
        "pin-category-memorial": "flag.fill",
        "pin-category-archaeological": "hammer.fill",
        "pin-category-historic-building": "building.2.fill",
        "pin-category-museum": "camera.fill",
        "pin-category-attraction": "star.fill",
        "pin-category-artwork": "paintpalette.fill",
    ]

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

    public static func categoryIconExpression() -> JSONValue {
        var expression: [JSONValue] = [
            .string("match"),
            .array([.string("get"), .string("category")]),
        ]
        for category in categoryIconNames.keys.sorted() {
            expression.append(.string(category))
            expression.append(.string(categoryIconNames[category]!))
        }
        expression.append(.string(fallbackCategoryIconName))
        return .array(expression)
    }

    public static func categoryVisibilityFilter(visibleCategories: Set<String>?) -> JSONValue? {
        guard let visibleCategories else { return nil }
        guard !visibleCategories.isEmpty else {
            return .array([.string("=="), .bool(true), .bool(false)])
        }
        return .array([
            .string("in"),
            .array([.string("get"), .string("category")]),
            .array([.string("literal"), .array(visibleCategories.sorted().map(JSONValue.string))]),
        ])
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
                "id": .string("pins-icon"),
                "type": .string("symbol"),
                "source": .string(sourceID),
                "paint": .object([
                    "icon-opacity": fadeOpacityExpression(),
                ]),
                "layout": .object([
                    "icon-image": categoryIconExpression(),
                    "icon-allow-overlap": .bool(true),
                    "icon-ignore-placement": .bool(true),
                    "icon-size": .double(categoryIconScale),
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
