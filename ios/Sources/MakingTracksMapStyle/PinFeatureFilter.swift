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
        zoom: Int? = nil,
        allowSparseTierFallback: Bool = false
    ) -> [(MapPlace, PinState)] {
        let maximumTier = maximumVisibleTier(at: zoom)
        let hiddenFiltered = features.filter { _, state in
            showHidden || !state.hidden
        }
        let tierFiltered = hiddenFiltered.filter { place, _ in
            place.tier <= maximumTier
        }
        guard allowSparseTierFallback, tierFiltered.isEmpty, hiddenFiltered.isEmpty == false else {
            return tierFiltered
        }
        guard let zoom, zoom >= cityZoom else {
            return tierFiltered
        }
        guard let fallbackTier = hiddenFiltered.map(\.0.tier).min() else {
            return tierFiltered
        }
        return hiddenFiltered.filter { place, _ in
            place.tier == fallbackTier
        }
    }
}
