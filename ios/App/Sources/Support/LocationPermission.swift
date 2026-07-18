import CoreLocation
import SwiftUI

@MainActor
final class LocationPermission: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var currentCoordinate: CLLocationCoordinate2D?
    @Published private(set) var authorizationRequestCount: Int

    private let manager: AppLocationManager
    private var didRequestAuthorization = false
    private var wantsCurrentLocation = false

    init(manager: AppLocationManager = AppLocationManager()) {
        self.manager = manager
        self.authorizationStatus = manager.authorizationStatus
        self.authorizationRequestCount = manager.whenInUseAuthorizationRequestCount
        super.init()
        self.manager.permissionDelegate = self
    }

    var showsUserLocation: Bool {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        case .denied, .restricted, .notDetermined:
            return false
        @unknown default:
            return false
        }
    }

    var isLocationOff: Bool {
        switch authorizationStatus {
        case .denied, .restricted:
            return true
        case .authorizedAlways, .authorizedWhenInUse, .notDetermined:
            return false
        @unknown default:
            return false
        }
    }

    func requestWhenInUseIfNeeded() {
        guard authorizationStatus == .notDetermined, !didRequestAuthorization else { return }
        didRequestAuthorization = true
        manager.requestWhenInUseAuthorization()
        authorizationRequestCount = manager.whenInUseAuthorizationRequestCount
    }

    func requestCurrentLocation() {
        wantsCurrentLocation = true
        requestWhenInUseIfNeeded()
        requestCurrentLocationIfAuthorized()
    }

    private func requestCurrentLocationIfAuthorized() {
        guard wantsCurrentLocation, showsUserLocation else { return }
        wantsCurrentLocation = false
        manager.requestLocation()
    }
}

extension LocationPermission: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            applyAuthorizationStatus(self.manager.authorizationStatus)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coordinate = locations.last?.coordinate
        Task { @MainActor in
            currentCoordinate = coordinate
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            wantsCurrentLocation = false
        }
    }
}

private extension LocationPermission {
    func applyAuthorizationStatus(_ status: CLAuthorizationStatus) {
        authorizationStatus = status
        if showsUserLocation {
            requestCurrentLocationIfAuthorized()
        } else if isLocationOff {
            wantsCurrentLocation = false
        }
    }
}
