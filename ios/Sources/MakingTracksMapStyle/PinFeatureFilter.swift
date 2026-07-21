import MakingTracksData

public enum PinFeatureFilter {
    public static let streetZoom = 14

    public static func nearbyPromptFeatures(
        _ features: [(MapPlace, PinState)]
    ) -> [(MapPlace, PinState)] {
        features.filter { _, state in
            !state.hidden
        }
    }

    public static func discoveryFeatures(
        _ features: [(MapPlace, PinState)],
        showHidden: Bool
    ) -> [(MapPlace, PinState)] {
        features.filter { _, state in
            showHidden || !state.hidden
        }
    }
}
