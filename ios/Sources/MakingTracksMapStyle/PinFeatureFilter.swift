import MakingTracksData

public enum PinFeatureFilter {
    public static func discoveryFeatures(
        _ features: [(MapPlace, PinState)],
        showHidden: Bool
    ) -> [(MapPlace, PinState)] {
        features.filter { _, state in
            showHidden || !state.hidden
        }
    }
}
