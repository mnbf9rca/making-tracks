import MakingTracksData

public enum PinLayers {
    public static let pinColor = "#E4572E"
    public static let hiddenPinColor = "#767B82"
    public static let sourceID = "pins"
    public static let baseBadgeOffset = 8.0
    public static let bookmarkOffset: JSONValue = .array([.double(baseBadgeOffset), .double(-baseBadgeOffset)])
    public static let heartOffset: JSONValue = .array([.double(-baseBadgeOffset), .double(-baseBadgeOffset)])
    // Tuned from device-representative fixture screenshots so category glyphs stay legible.
    public static let baseCircleRadius = 6.5
    // Tunable fallback-clustering radius: scaled with pin size so larger pins also get wider decluttering.
    public static let baseClusterRadiusPoints = 44.0
    public static let minimumClusterPointCount = 2
    public static let maximumClusterZoom = PinFeatureFilter.streetZoom - 1
    public static let baseClusterBubbleRadius = 14.0
    public static let baseClusterCountTextSize = 12.0
    public static let baseCategoryIconScale = 0.72
    public static let baseBadgeIconScale = 1.0
    public static let trackReplayPulseProperty = "track_replay_pulse"
    // Tunable per B6 replay; enough enlargement to read as an arrival ping without covering neighbors.
    public static let trackReplayPulseScale = 1.28
    public static let categorySymbolPointSize = 17.0
    public static let fallbackCategoryID = "uncategorized"
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
            .array([.string("=="), .array([.string("get"), .string("pin_presentation")]), .string(PinPresentation.tracks.rawValue)]),
            .double(FULL_OPACITY),
            .array([.string("=="), .array([.string("get"), .string("pin_presentation")]), .string(PinPresentation.trackReplay.rawValue)]),
            .array([
                .string("case"),
                .array([.string("=="), .array([.string("get"), .string("visit")]), .string(FeatureEncoding.visitTag(.none))]),
                .double(FADED_OPACITY),
                .double(FULL_OPACITY),
            ]),
            .array(expression),
        ])
    }

    public static func trackReplayPulseExpression(base: JSONValue) -> JSONValue {
        if case let .array(items) = base,
           items.count >= 5,
           case .string("interpolate") = items[0],
           items.count.isMultiple(of: 2) == false {
            var pulsedItems = Array(items.prefix(3))
            var index = 3
            while index + 1 < items.count {
                pulsedItems.append(items[index])
                pulsedItems.append(trackReplayPulseValueExpression(base: items[index + 1]))
                index += 2
            }
            return .array(pulsedItems)
        }
        return trackReplayPulseValueExpression(base: base)
    }

    private static func trackReplayPulseValueExpression(base: JSONValue) -> JSONValue {
        .array([
            .string("*"),
            base,
            .array([
                .string("case"),
                .array([.string("=="), .array([.string("get"), .string(trackReplayPulseProperty)]), .bool(true)]),
                .double(trackReplayPulseScale),
                .double(1.0),
            ]),
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

    public static func clusterFilter() -> JSONValue {
        .array([.string("=="), .array([.string("get"), .string("cluster")]), .bool(true)])
    }

    public static func singlePinFilter() -> JSONValue {
        .array([.string("!"), clusterFilter()])
    }

    public static func bookmarkFilter() -> JSONValue {
        .array([.string("all"), singlePinFilter(), notHiddenFilter(), .array([.string("=="), .array([.string("get"), .string("saved")]), .bool(true)])])
    }

    public static func heartFilter() -> JSONValue {
        .array([.string("all"), singlePinFilter(), notHiddenFilter(), .array([.string("=="), .array([.string("get"), .string("visit")]), .string("loved")])])
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

    public static func isCategoryVisible(_ category: String, visibleCategories: Set<String>?) -> Bool {
        guard let visibleCategories else { return true }
        if categoryIconNames.keys.contains(category) {
            return visibleCategories.contains(category)
        }
        return visibleCategories.contains(fallbackCategoryID)
    }

    public static func combinedFilter(_ filters: [JSONValue?]) -> JSONValue? {
        let activeFilters = filters.compactMap { $0 }
        guard !activeFilters.isEmpty else { return nil }
        guard activeFilters.count > 1 else { return activeFilters[0] }
        return .array([.string("all")] + activeFilters)
    }

    public static func clusterRadius(pinSize: PinSize) -> Double {
        baseClusterRadiusPoints * pinSize.multiplier / PinSize.defaultMultiplier
    }

    public static func clusterBubbleRadius(pinSize: PinSize) -> Double {
        baseClusterBubbleRadius * pinSize.multiplier / PinSize.defaultMultiplier
    }

    public static func clusterCountTextSize(pinSize: PinSize) -> Double {
        baseClusterCountTextSize * pinSize.multiplier / PinSize.defaultMultiplier
    }

    public static func pinLayers(pinSize: PinSize = PinSize()) -> [JSONValue] {
        [
            .object([
                "id": .string("pin-clusters-circle"),
                "type": .string("circle"),
                "source": .string(sourceID),
                "filter": clusterFilter(),
                "paint": .object([
                    "circle-color": .string(pinColor),
                    "circle-opacity": .double(0.92),
                    "circle-radius": .double(clusterBubbleRadius(pinSize: pinSize)),
                ]),
            ]),
            .object([
                "id": .string("pin-clusters-count"),
                "type": .string("symbol"),
                "source": .string(sourceID),
                "filter": clusterFilter(),
                "layout": .object([
                    "text-field": .array([.string("get"), .string("point_count_abbreviated")]),
                    "text-size": .double(clusterCountTextSize(pinSize: pinSize)),
                    "text-allow-overlap": .bool(true),
                    "text-ignore-placement": .bool(true),
                ]),
                "paint": .object([
                    "text-color": .string("#FFFFFF"),
                ]),
            ]),
            .object([
                "id": .string("pins-circle"),
                "type": .string("circle"),
                "source": .string(sourceID),
                "filter": singlePinFilter(),
                "paint": .object([
                    "circle-color": pinColorExpression(),
                    "circle-opacity": fadeOpacityExpression(),
                    "circle-radius": trackReplayPulseExpression(base: pinSize.circleRadiusExpression),
                ]),
            ]),
            .object([
                "id": .string("pins-icon"),
                "type": .string("symbol"),
                "source": .string(sourceID),
                "filter": singlePinFilter(),
                "paint": .object([
                    "icon-opacity": fadeOpacityExpression(),
                ]),
                "layout": .object([
                    "icon-image": categoryIconExpression(),
                    "icon-allow-overlap": .bool(true),
                    "icon-ignore-placement": .bool(true),
                    "icon-size": trackReplayPulseExpression(base: pinSize.categoryIconScaleExpression),
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
                    "icon-size": pinSize.badgeIconScaleExpression,
                    "icon-offset": pinSize.bookmarkOffset,
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
                    "icon-size": pinSize.badgeIconScaleExpression,
                    "icon-offset": pinSize.heartOffset,
                ]),
            ]),
        ]
    }
}
