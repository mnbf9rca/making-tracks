import MakingTracksData

public enum PinFeatureFilter {
    public static func discoveryFeatures(
        _ features: [(MapPlace, PinState)],
        showHidden: Bool
    ) -> [(MapPlace, PinState)] {
        guard !showHidden else { return features }
        return features.filter { !$0.1.hidden }
    }
}
