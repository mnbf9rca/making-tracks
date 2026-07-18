import CoreLocation
@preconcurrency import MapLibre

final class AppLocationManager: NSObject, MLNLocationManager {
    private let locationManager: CLLocationManager
    private let simulatedAuthorizationStatus: CLAuthorizationStatus?
    private let simulatedLocation: CLLocationCoordinate2D?

    weak var permissionDelegate: CLLocationManagerDelegate?
    weak var delegate: MLNLocationManagerDelegate?

    init(
        simulatedAuthorizationStatus: CLAuthorizationStatus? = nil,
        simulatedLocation: CLLocationCoordinate2D? = nil
    ) {
        self.locationManager = CLLocationManager()
        self.simulatedAuthorizationStatus = simulatedAuthorizationStatus
        self.simulatedLocation = simulatedLocation
        super.init()
        self.locationManager.delegate = self
    }

    var authorizationStatus: CLAuthorizationStatus {
        simulatedAuthorizationStatus ?? locationManager.authorizationStatus
    }

    func requestAlwaysAuthorization() {
        guard simulatedAuthorizationStatus == nil else { return }
        locationManager.requestAlwaysAuthorization()
    }

    func requestWhenInUseAuthorization() {
        guard simulatedAuthorizationStatus == nil else { return }
        locationManager.requestWhenInUseAuthorization()
    }

    func requestLocation() {
        guard !emitSimulatedLocationIfNeeded() else { return }
        locationManager.requestLocation()
    }

    func startUpdatingLocation() {
        guard !emitSimulatedLocationIfNeeded() else { return }
        locationManager.startUpdatingLocation()
    }

    func stopUpdatingLocation() {
        guard simulatedAuthorizationStatus == nil else { return }
        locationManager.stopUpdatingLocation()
    }

    var headingOrientation: CLDeviceOrientation {
        get { locationManager.headingOrientation }
        set { locationManager.headingOrientation = newValue }
    }

    func startUpdatingHeading() {
        guard !emitSimulatedLocationIfNeeded() else { return }
        locationManager.startUpdatingHeading()
    }

    func stopUpdatingHeading() {
        guard simulatedAuthorizationStatus == nil else { return }
        locationManager.stopUpdatingHeading()
    }

    func dismissHeadingCalibrationDisplay() {
        guard simulatedAuthorizationStatus == nil else { return }
        locationManager.dismissHeadingCalibrationDisplay()
    }

    var distanceFilter: CLLocationDistance {
        get { locationManager.distanceFilter }
        set { locationManager.distanceFilter = newValue }
    }

    var desiredAccuracy: CLLocationAccuracy {
        get { locationManager.desiredAccuracy }
        set { locationManager.desiredAccuracy = newValue }
    }

    var accuracyAuthorization: CLAccuracyAuthorization {
        locationManager.accuracyAuthorization
    }

    var activityType: CLActivityType {
        get { locationManager.activityType }
        set { locationManager.activityType = newValue }
    }

    func requestTemporaryFullAccuracyAuthorization(withPurposeKey purposeKey: String) {
        guard simulatedAuthorizationStatus == nil else { return }
        locationManager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: purposeKey)
    }

    private func emitSimulatedLocationIfNeeded() -> Bool {
        guard let simulatedAuthorizationStatus,
              simulatedAuthorizationStatus == .authorizedWhenInUse || simulatedAuthorizationStatus == .authorizedAlways,
              let simulatedLocation
        else { return false }
        let location = CLLocation(
            coordinate: simulatedLocation,
            altitude: 0,
            horizontalAccuracy: 10,
            verticalAccuracy: 10,
            course: -1,
            courseAccuracy: -1,
            speed: -1,
            speedAccuracy: -1,
            timestamp: Date()
        )
        notifyLocationUpdate([location])
        return true
    }

    private func notifyLocationUpdate(_ locations: [CLLocation]) {
        permissionDelegate?.locationManager?(locationManager, didUpdateLocations: locations)
        delegate?.locationManager(self, didUpdate: locations)
    }

}

extension AppLocationManager: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        permissionDelegate?.locationManagerDidChangeAuthorization?(locationManager)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        notifyLocationUpdate(locations)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        delegate?.locationManager(self, didUpdate: newHeading)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        permissionDelegate?.locationManager?(locationManager, didFailWithError: error)
        delegate?.locationManager(self, didFailWithError: error)
    }
}
