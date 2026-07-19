import MakingTracksData

public enum PinFeatureFilter {
    // Presentation tunables: city zoom keeps landmarks, neighborhood zoom adds highlights,
    // close zoom adds notable local places, and street zoom reveals all tiers.
    public static let cityZoom = 10
    public static let neighborhoodZoom = 13
    public static let streetZoom = 14

    public static func maximumVisibleTier(at zoom: Int?) -> Int {
        guard let zoom else { return 4 }
        if zoom >= streetZoom { return 4 }
        if zoom >= neighborhoodZoom { return 3 }
        if zoom >= cityZoom { return 2 }
        return 1
    }

    public static func nearbyPromptFeatures(
        _ features: [(MapPlace, PinState)]
    ) -> [(MapPlace, PinState)] {
        features.filter { _, state in
            !state.hidden
        }
    }

    public static func discoveryFeatures(
        _ features: [(MapPlace, PinState)],
        showHidden: Bool,
        zoom: Int? = nil
    ) -> [(MapPlace, PinState)] {
        let maximumTier = maximumVisibleTier(at: zoom)
        return features.filter { _, state in
            showHidden || !state.hidden
        }.filter { place, state in
            place.tier <= maximumTier
        }
    }
}
