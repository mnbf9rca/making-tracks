public struct PinSize: Equatable, Sendable {
    public static let minimumMultiplier = 0.8
    public static let defaultMultiplier = 1.2
    public static let maximumMultiplier = 1.6

    public var multiplier: Double

    public init(multiplier: Double = Self.defaultMultiplier) {
        self.multiplier = min(Self.maximumMultiplier, max(Self.minimumMultiplier, multiplier))
    }

    public var circleRadius: Double {
        PinLayers.baseCircleRadius * multiplier
    }

    public var categoryIconScale: Double {
        PinLayers.baseCategoryIconScale * multiplier
    }

    public var badgeIconScale: Double {
        PinLayers.baseBadgeIconScale * multiplier
    }

    public var circleRadiusExpression: JSONValue {
        Self.zoomInterpolated(base: circleRadius)
    }

    public var categoryIconScaleExpression: JSONValue {
        Self.zoomInterpolated(base: categoryIconScale)
    }

    public var badgeIconScaleExpression: JSONValue {
        Self.zoomInterpolated(base: badgeIconScale)
    }

    public var bookmarkOffset: JSONValue {
        .array([
            .double(PinLayers.baseBadgeOffset * multiplier),
            .double(-PinLayers.baseBadgeOffset * multiplier),
        ])
    }

    public var heartOffset: JSONValue {
        .array([
            .double(-PinLayers.baseBadgeOffset * multiplier),
            .double(-PinLayers.baseBadgeOffset * multiplier),
        ])
    }

    public var accessibilityValue: String {
        "\(Int((multiplier * 100).rounded()))%"
    }

    private static func zoomInterpolated(base: Double) -> JSONValue {
        // Visual tuning constants: keep pins quieter at overview zooms and more legible when zoomed in.
        .array([
            .string("interpolate"),
            .array([.string("linear")]),
            .array([.string("zoom")]),
            .double(10), .double(base * 0.85),
            .double(14), .double(base),
            .double(16), .double(base * 1.2),
        ])
    }
}
