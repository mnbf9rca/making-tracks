import Foundation

public struct PlaceCardPresentation: Sendable, Equatable {
    public struct Item: Identifiable, Sendable, Equatable {
        public let id: Int
        public let placeID: String
    }

    public private(set) var activePlaceID: String?
    public private(set) var presentationID: Int?
    private var nextPresentationID: Int

    public var isPresented: Bool {
        activePlaceID != nil
    }

    public var item: Item? {
        guard let activePlaceID, let presentationID else { return nil }
        return Item(id: presentationID, placeID: activePlaceID)
    }

    public init(activePlaceID: String? = nil) {
        self.activePlaceID = activePlaceID
        presentationID = activePlaceID == nil ? nil : 0
        nextPresentationID = activePlaceID == nil ? 0 : 1
    }

    public mutating func show(placeID: String) {
        if activePlaceID == nil {
            presentationID = nextPresentationID
            nextPresentationID += 1
        }
        activePlaceID = placeID
    }

    public mutating func dismiss() {
        activePlaceID = nil
        presentationID = nil
    }
}

public enum PlaceCardDetentPolicy {
    public static func identifiers(isAccessibilitySize: Bool) -> [String] {
        isAccessibilitySize ? ["large"] : ["medium", "large"]
    }
}
