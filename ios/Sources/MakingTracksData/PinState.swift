public enum VisitState: Sendable, Equatable {
    case none
    case visited
    case loved
}

public struct PinState: Sendable, Equatable {
    public var saved: Bool
    public var visit: VisitState

    public init(saved: Bool, visit: VisitState) {
        self.saved = saved
        self.visit = visit
    }
}
