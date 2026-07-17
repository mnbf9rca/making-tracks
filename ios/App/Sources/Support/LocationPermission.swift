import CoreLocation
import SwiftUI

@MainActor
final class LocationPermission: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var currentCoordinate: CLLocationCoordinate2D?

    private let manager: LocationManaging
    private var didRequestAuthorization = false
    private var wantsCurrentLocation = false

    init(manager: LocationManaging = CLLocationManager()) {
        self.manager = manager
        self.authorizationStatus = manager.authorizationStatus
        super.init()
        self.manager.delegate = self
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
        let status = manager.authorizationStatus
        Task { @MainActor in
            applyAuthorizationStatus(status)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        Task { @MainActor in
            applyAuthorizationStatus(status)
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

protocol LocationManaging: AnyObject {
    var authorizationStatus: CLAuthorizationStatus { get }
    var delegate: CLLocationManagerDelegate? { get set }

    func requestWhenInUseAuthorization()
    func requestLocation()
}

extension CLLocationManager: LocationManaging {}
