import Foundation

struct HiddenMembershipRollback: Sendable {
    let placeID: String
    let wasHidden: Bool
    let hadPendingMarker: Bool
}

struct HiddenMembershipTracker: Sendable {
    private var hiddenPlaceIDs: Set<String>
    private var hiddenMembershipChangePlaceIDs: Set<String> = []

    init(hiddenPlaceIDs: Set<String>) {
        self.hiddenPlaceIDs = hiddenPlaceIDs
    }

    var hiddenIDs: Set<String> {
        hiddenPlaceIDs
    }

    mutating func beginSetHidden(placeID: String, hidden: Bool) -> HiddenMembershipRollback {
        let rollback = HiddenMembershipRollback(
            placeID: placeID,
            wasHidden: hiddenPlaceIDs.contains(placeID),
            hadPendingMarker: hiddenMembershipChangePlaceIDs.contains(placeID)
        )
        if hidden {
            hiddenPlaceIDs.insert(placeID)
        } else {
            hiddenPlaceIDs.remove(placeID)
        }
        hiddenMembershipChangePlaceIDs.insert(placeID)
        return rollback
    }

    mutating func rollback(_ rollback: HiddenMembershipRollback) {
        if rollback.wasHidden {
            hiddenPlaceIDs.insert(rollback.placeID)
        } else {
            hiddenPlaceIDs.remove(rollback.placeID)
        }
        if rollback.hadPendingMarker {
            hiddenMembershipChangePlaceIDs.insert(rollback.placeID)
        } else {
            hiddenMembershipChangePlaceIDs.remove(rollback.placeID)
        }
    }

    mutating func consumeHiddenMembershipChange(overlapping ids: Set<String>) -> Bool {
        let changed = hiddenMembershipChangePlaceIDs.intersection(ids)
        guard !changed.isEmpty else { return false }
        hiddenMembershipChangePlaceIDs.subtract(changed)
        return true
    }
}
