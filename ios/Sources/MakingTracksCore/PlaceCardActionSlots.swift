import MakingTracksData

public enum PlaceCardAction: Sendable, Equatable {
    case save
    case seen
    case love
    case unlove
    case hide
    case unsee(isEnabled: Bool)
    case seenDisabled
    case unhide

    public var title: String {
        switch self {
        case .save:
            return "Save"
        case .seen, .seenDisabled:
            return "Seen"
        case .love:
            return "Love"
        case .unlove:
            return "Unlove"
        case .hide:
            return "Hide"
        case .unsee:
            return "Un-see"
        case .unhide:
            return "Unhide"
        }
    }

    public var isEnabled: Bool {
        switch self {
        case .unsee(isEnabled: let isEnabled):
            return isEnabled
        case .seenDisabled:
            return false
        case .save, .seen, .love, .unlove, .hide, .unhide:
            return true
        }
    }

    public func accessibilityHint(isSaved: Bool = false) -> String? {
        switch self {
        case .save:
            return isSaved
                ? "Double-tap to unsave, double-tap and hold to choose list."
                : "Double-tap to choose list."
        case .seen, .love, .unlove, .hide, .unsee, .seenDisabled, .unhide:
            return nil
        }
    }
}

public struct PlaceCardActionSlots: Sendable, Equatable {
    public let actions: [PlaceCardAction]

    public init(pinState: PinState) {
        if pinState.hidden {
            actions = [.save, .seenDisabled, .unhide]
            return
        }

        switch pinState.visit {
        case .none:
            actions = [.save, .seen, .hide]
        case .visited:
            actions = [.save, .love, .unsee(isEnabled: true)]
        case .loved:
            actions = [.save, .unlove, .unsee(isEnabled: false)]
        }
    }

}

public enum PlaceCardOverlayMetrics {
    public static let fadeHeight: Double = 24

    public static func contentBottomPadding(actionBarHeight: Double) -> Double {
        actionBarHeight + fadeHeight
    }
}
