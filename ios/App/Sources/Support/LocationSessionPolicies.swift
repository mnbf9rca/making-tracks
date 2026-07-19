import CoreLocation
import SwiftUI
@preconcurrency import MapLibre

@MainActor
struct LocationSessionPolicies {
    static func shouldShowUserLocation(
        authorizationStatus: CLAuthorizationStatus
    ) -> Bool {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        case .denied, .restricted, .notDetermined:
            return false
        @unknown default:
            return false
        }
    }

    static func handleScenePhaseChange(
        _ newPhase: ScenePhase,
        userTrackingMode: inout MLNUserTrackingMode,
        stopUpdatingLocation: () -> Void,
        stopUpdatingHeading: () -> Void
    ) {
        guard newPhase != .active else { return }
        userTrackingMode = .none
        stopUpdatingLocation()
        stopUpdatingHeading()
    }

    static func handleAuthorizationStatusChange(
        _ newStatus: CLAuthorizationStatus,
        userTrackingMode: inout MLNUserTrackingMode,
        pendingLocateMeActivation: inout Bool
    ) {
        switch newStatus {
        case .denied, .restricted:
            pendingLocateMeActivation = false
            userTrackingMode = .none
        case .authorizedAlways, .authorizedWhenInUse:
            guard pendingLocateMeActivation else { return }
            pendingLocateMeActivation = false
            userTrackingMode = .follow
        case .notDetermined:
            return
        @unknown default:
            return
        }
    }

    static func handleLocateMeTap(
        authorizationStatus: CLAuthorizationStatus,
        userTrackingMode: inout MLNUserTrackingMode,
        requestCurrentLocation: () -> Void,
        openSettings: () -> Void,
        deferFollowUntilAuthorized: () -> Void
    ) {
        switch authorizationStatus {
        case .denied, .restricted:
            userTrackingMode = .none
            openSettings()
        case .notDetermined:
            userTrackingMode = .none
            deferFollowUntilAuthorized()
            requestCurrentLocation()
        case .authorizedAlways, .authorizedWhenInUse:
            let nextTrackingMode = nextTrackingMode(afterLocateMeTap: userTrackingMode)
            userTrackingMode = nextTrackingMode
            guard nextTrackingMode != .none else { return }
            requestCurrentLocation()
        @unknown default:
            let nextTrackingMode = nextTrackingMode(afterLocateMeTap: userTrackingMode)
            userTrackingMode = nextTrackingMode
            guard nextTrackingMode != .none else { return }
            requestCurrentLocation()
        }
    }

    static func nextTrackingMode(afterLocateMeTap current: MLNUserTrackingMode) -> MLNUserTrackingMode {
        switch current {
        case .none:
            return .follow
        case .follow:
            return .followWithHeading
        case .followWithHeading, .followWithCourse:
            return .none
        @unknown default:
            return .none
        }
    }
}

@MainActor
final class ViewportRefreshDebouncer {
    private var refreshTask: Task<Void, Never>?
    private let delayNanoseconds: UInt64

    init(delayNanoseconds: UInt64 = 350_000_000) {
        self.delayNanoseconds = delayNanoseconds
    }

    func schedule(action: @escaping @Sendable () async -> Void) {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [delayNanoseconds] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }
            await action()
        }
    }

    func cancel() {
        refreshTask?.cancel()
        refreshTask = nil
    }
}
