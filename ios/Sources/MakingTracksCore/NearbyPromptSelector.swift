import Foundation
import MakingTracksData

public struct NearbyPromptSelection: Sendable, Equatable {
    public let placeID: String
    public let name: String
    public let distanceMeters: Double

    public init(placeID: String, name: String, distanceMeters: Double) {
        self.placeID = placeID
        self.name = name
        self.distanceMeters = distanceMeters
    }
}

public enum NearbyPromptSelector {
    public static func candidate(
        features: [(MapPlace, PinState)],
        names: [String: String],
        userLatitude: Double,
        userLongitude: Double,
        maxDistanceMeters: Double,
        suppressedPlaceIDs: Set<String>,
        hiddenPlaceIDs: Set<String>
    ) -> NearbyPromptSelection? {
        features
            .compactMap { place, pinState -> NearbyPromptSelection? in
                guard pinState.visit == .none,
                      !pinState.hidden,
                      !hiddenPlaceIDs.contains(place.id),
                      !suppressedPlaceIDs.contains(place.id),
                      let name = names[place.id]
                else { return nil }

                let distance = haversineMeters(
                    lat1: userLatitude,
                    lon1: userLongitude,
                    lat2: place.lat,
                    lon2: place.lon
                )
                guard distance <= maxDistanceMeters else { return nil }
                return NearbyPromptSelection(
                    placeID: place.id,
                    name: name,
                    distanceMeters: distance
                )
            }
            .sorted { lhs, rhs in
                if lhs.distanceMeters == rhs.distanceMeters {
                    return lhs.placeID < rhs.placeID
                }
                return lhs.distanceMeters < rhs.distanceMeters
            }
            .first
    }

    private static func haversineMeters(
        lat1: Double,
        lon1: Double,
        lat2: Double,
        lon2: Double
    ) -> Double {
        let radiusMeters = 6_371_000.0
        let dLat = radians(lat2 - lat1)
        let dLon = radians(lon2 - lon1)
        let rLat1 = radians(lat1)
        let rLat2 = radians(lat2)
        let a = sin(dLat / 2) * sin(dLat / 2) +
            cos(rLat1) * cos(rLat2) * sin(dLon / 2) * sin(dLon / 2)
        return radiusMeters * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    private static func radians(_ degrees: Double) -> Double {
        degrees * .pi / 180
    }
}
