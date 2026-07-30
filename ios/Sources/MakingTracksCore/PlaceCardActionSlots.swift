import MakingTracksData

public enum PlaceCardAction: Sendable, Equatable {
    case save
    case seen
    case love
    case unlove
    case hide
    case unsee(isEnabled: Bool)
    case unhide

    public var title: String {
        switch self {
        case .save:
            return "Save"
        case .seen:
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
        case .save, .seen, .love, .unlove, .hide, .unhide:
            return true
        }
    }

    public func accessibilityHint(isSaved: Bool = false) -> String? {
        switch self {
        case .save:
            return isSaved
                ? "Double-tap to choose lists."
                : "Double-tap to choose list."
        case .seen, .love, .unlove, .hide, .unsee, .unhide:
            return nil
        }
    }
}

public enum NearbyPromptSuppressionPolicy {
    public static func suppressesPromptImmediately(for action: PlaceCardAction) -> Bool {
        switch action {
        case .seen, .love, .unlove, .hide:
            return true
        case .save, .unsee, .unhide:
            return false
        }
    }

    public static func clearsPromptSuppressionOnSuccess(for action: PlaceCardAction) -> Bool {
        switch action {
        case .unsee(isEnabled: true), .unhide:
            return true
        case .save, .seen, .love, .unlove, .hide, .unsee(isEnabled: false):
            return false
        }
    }
}

public struct PlaceCardActionSlots: Sendable, Equatable {
    public let actions: [PlaceCardAction]

    public init(pinState: PinState) {
        var next: [PlaceCardAction] = [.save]
        switch pinState.visit {
        case .none:
            next.append(.seen)
        case .visited:
            next.append(contentsOf: [.love, .unsee(isEnabled: true)])
        case .loved:
            next.append(contentsOf: [.unlove, .unsee(isEnabled: false)])
        }

        if pinState.hidden {
            next.append(.unhide)
        } else if !pinState.saved {
            next.append(.hide)
        }
        actions = next
    }

}

public enum PlaceCardOverlayMetrics {
    public static let fadeHeight: Double = 24

    public static func contentBottomPadding(actionBarHeight: Double) -> Double {
        actionBarHeight + fadeHeight
    }
}
