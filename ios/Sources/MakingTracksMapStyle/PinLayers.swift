import MakingTracksData

public enum PinLayers {
    public static let pinColor = "#E4572E"
    public static let hiddenPinColor = "#767B82"
    public static let sourceID = "pins"
    public static let bookmarkOffset: JSONValue = .array([.double(8), .double(-8)])
    public static let heartOffset: JSONValue = .array([.double(-8), .double(-8)])
    public static let categoryIconScale = 0.62
    public static let fallbackCategoryID = "__other__"
    public static let fallbackCategoryIconName = "pin-category-uncategorized"
    public static let hiddenIconName = "pin-hidden"
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
        hiddenIconName: "eye.slash.fill",
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
        return .array([
            .string("case"),
            hiddenFilter(),
            .double(FULL_OPACITY),
            .array(expression),
        ])
    }

    public static func pinColorExpression() -> JSONValue {
        .array([
            .string("case"),
            .array([.string("=="), .array([.string("get"), .string("hidden")]), .bool(true)]),
            .string(hiddenPinColor),
            .string(pinColor),
        ])
    }

    public static func notHiddenFilter() -> JSONValue {
        .array([.string("!"), .array([.string("=="), .array([.string("get"), .string("hidden")]), .bool(true)])])
    }

    public static func hiddenFilter() -> JSONValue {
        .array([.string("=="), .array([.string("get"), .string("hidden")]), .bool(true)])
    }

    public static func bookmarkFilter() -> JSONValue {
        .array([.string("all"), notHiddenFilter(), .array([.string("=="), .array([.string("get"), .string("saved")]), .bool(true)])])
    }

    public static func heartFilter() -> JSONValue {
        .array([.string("all"), notHiddenFilter(), .array([.string("=="), .array([.string("get"), .string("visit")]), .string("loved")])])
    }

    public static func categoryIconExpression() -> JSONValue {
        var categoryExpression: [JSONValue] = [
            .string("match"),
            .array([.string("get"), .string("category")]),
        ]
        for category in categoryIconNames.keys.sorted() {
            categoryExpression.append(.string(category))
            categoryExpression.append(.string(categoryIconNames[category]!))
        }
        categoryExpression.append(.string(fallbackCategoryIconName))
        return .array([
            .string("case"),
            .array([.string("=="), .array([.string("get"), .string("hidden")]), .bool(true)]),
            .string(hiddenIconName),
            .array(categoryExpression),
        ])
    }

    public static func categoryVisibilityFilter(visibleCategories: Set<String>?) -> JSONValue? {
        guard let visibleCategories else { return nil }
        let category = JSONValue.array([.string("get"), .string("category")])
        let knownCategories = JSONValue.array([.string("literal"), .array(categoryIconNames.keys.sorted().map(JSONValue.string))])
        let visibleKnownCategories = JSONValue.array([.string("literal"), .array(visibleCategories.subtracting([fallbackCategoryID]).sorted().map(JSONValue.string))])
        let knownCategoryFilter: JSONValue = .array([.string("in"), category, visibleKnownCategories])
        let categoryFilter: JSONValue
        if visibleCategories.contains(fallbackCategoryID) {
            let fallbackFilter: JSONValue = .array([.string("!"), .array([.string("in"), category, knownCategories])])
            categoryFilter = .array([.string("any"), knownCategoryFilter, fallbackFilter])
        } else {
            categoryFilter = knownCategoryFilter
        }
        return categoryFilter
    }

    public static func combinedFilter(_ filters: [JSONValue?]) -> JSONValue? {
        let activeFilters = filters.compactMap { $0 }
        guard !activeFilters.isEmpty else { return nil }
        guard activeFilters.count > 1 else { return activeFilters[0] }
        return .array([.string("all")] + activeFilters)
    }

    public static func pinLayers() -> [JSONValue] {
        [
            .object([
                "id": .string("pins-circle"),
                "type": .string("circle"),
                "source": .string(sourceID),
                "paint": .object([
                    "circle-color": pinColorExpression(),
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
