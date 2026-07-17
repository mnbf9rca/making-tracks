import MakingTracksData

public let FULL_OPACITY = 1.0
public let FADED_OPACITY = 0.35

public struct PinAppearance: Equatable, Sendable {
    public var opacity: Double
    public var showBookmarkBadge: Bool
    public var showHeartBadge: Bool

    public init(opacity: Double, showBookmarkBadge: Bool, showHeartBadge: Bool) {
        self.opacity = opacity
        self.showBookmarkBadge = showBookmarkBadge
        self.showHeartBadge = showHeartBadge
    }
}

public func pinAppearance(_ state: PinState) -> PinAppearance {
    PinAppearance(
        opacity: state.visit == .none ? FULL_OPACITY : FADED_OPACITY,
        showBookmarkBadge: state.saved,
        showHeartBadge: state.visit == .loved
    )
}
