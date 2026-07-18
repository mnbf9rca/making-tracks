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
}
