import CoreLocation
import MapLibre
import SwiftUI
import XCTest
@testable import MakingTracks

@MainActor
final class LocationSessionPoliciesTests: XCTestCase {
    func testShowsUserLocationRequiresAuthorizedStatusAndActiveTrackingMode() {
        XCTAssertFalse(LocationSessionPolicies.shouldShowUserLocation(authorizationStatus: .authorizedWhenInUse, userTrackingMode: .none))
        XCTAssertFalse(LocationSessionPolicies.shouldShowUserLocation(authorizationStatus: .notDetermined, userTrackingMode: .follow))
        XCTAssertTrue(LocationSessionPolicies.shouldShowUserLocation(authorizationStatus: .authorizedWhenInUse, userTrackingMode: .follow))
        XCTAssertTrue(LocationSessionPolicies.shouldShowUserLocation(authorizationStatus: .authorizedAlways, userTrackingMode: .followWithHeading))
    }

    func testScenePhaseBackgroundAndInactiveStopLocationUpdatesAndResetTrackingMode() {
        let phases: [ScenePhase] = [.background, .inactive]
        for phase in phases {
            var trackingMode: MLNUserTrackingMode = .followWithHeading
            var stoppedLocationUpdates = 0
            var stoppedHeadingUpdates = 0

            LocationSessionPolicies.handleScenePhaseChange(
                phase,
                userTrackingMode: &trackingMode,
                stopUpdatingLocation: { stoppedLocationUpdates += 1 },
                stopUpdatingHeading: { stoppedHeadingUpdates += 1 }
            )

            XCTAssertEqual(trackingMode, .none)
            XCTAssertEqual(stoppedLocationUpdates, 1)
            XCTAssertEqual(stoppedHeadingUpdates, 1)
        }
    }

    func testDeniedLocateMeTapOpensSettingsWithoutRequestingLocation() {
        var trackingMode: MLNUserTrackingMode = .follow
        var requestedLocationCount = 0
        var openedSettingsCount = 0

        LocationSessionPolicies.handleLocateMeTap(
            authorizationStatus: .denied,
            userTrackingMode: &trackingMode,
            requestCurrentLocation: { requestedLocationCount += 1 },
            openSettings: { openedSettingsCount += 1 },
            deferFollowUntilAuthorized: {}
        )

        XCTAssertEqual(trackingMode, .none)
        XCTAssertEqual(requestedLocationCount, 0)
        XCTAssertEqual(openedSettingsCount, 1)
    }

    func testNotDeterminedLocateMeTapDefersFollowUntilAuthorization() {
        var trackingMode: MLNUserTrackingMode = .none
        var requestedLocationCount = 0
        var openedSettingsCount = 0
        var pendingLocateMeActivation = false

        LocationSessionPolicies.handleLocateMeTap(
            authorizationStatus: .notDetermined,
            userTrackingMode: &trackingMode,
            requestCurrentLocation: { requestedLocationCount += 1 },
            openSettings: { openedSettingsCount += 1 },
            deferFollowUntilAuthorized: { pendingLocateMeActivation = true }
        )

        XCTAssertEqual(trackingMode, .none)
        XCTAssertEqual(requestedLocationCount, 1)
        XCTAssertEqual(openedSettingsCount, 0)
        XCTAssertTrue(pendingLocateMeActivation)

        LocationSessionPolicies.handleAuthorizationStatusChange(
            .authorizedWhenInUse,
            userTrackingMode: &trackingMode,
            pendingLocateMeActivation: &pendingLocateMeActivation
        )

        XCTAssertEqual(trackingMode, .follow)
        XCTAssertFalse(pendingLocateMeActivation)
    }

    func testDeniedAuthorizationClearsPendingLocateMeActivationAndStopsTracking() {
        var trackingMode: MLNUserTrackingMode = .followWithHeading
        var pendingLocateMeActivation = true

        LocationSessionPolicies.handleAuthorizationStatusChange(
            .denied,
            userTrackingMode: &trackingMode,
            pendingLocateMeActivation: &pendingLocateMeActivation
        )

        XCTAssertEqual(trackingMode, .none)
        XCTAssertFalse(pendingLocateMeActivation)
    }

    func testLocateMeTapDoesNotRequestLocationWhenTurningTrackingOff() {
        var trackingMode: MLNUserTrackingMode = .followWithHeading
        var requestedLocationCount = 0

        LocationSessionPolicies.handleLocateMeTap(
            authorizationStatus: .authorizedWhenInUse,
            userTrackingMode: &trackingMode,
            requestCurrentLocation: { requestedLocationCount += 1 },
            openSettings: {},
            deferFollowUntilAuthorized: {}
        )

        XCTAssertEqual(trackingMode, .none)
        XCTAssertEqual(requestedLocationCount, 0)
    }

    func testRapidViewportRefreshRequestsCollapseToOneExecution() async {
        let debouncer = ViewportRefreshDebouncer(delayNanoseconds: 20_000_000)
        let didRun = expectation(description: "debounced action ran once")
        didRun.expectedFulfillmentCount = 1
        didRun.assertForOverFulfill = true

        let counter = Counter()

        debouncer.schedule {
            await counter.increment()
            didRun.fulfill()
        }
        debouncer.schedule {
            await counter.increment()
            didRun.fulfill()
        }
        debouncer.schedule {
            await counter.increment()
            didRun.fulfill()
        }

        await fulfillment(of: [didRun], timeout: 1.0)
        let finalCount = await counter.currentValue()
        XCTAssertEqual(finalCount, 1)
    }
}

private actor Counter {
    private var storedValue = 0

    func increment() {
        storedValue += 1
    }

    func currentValue() -> Int {
        storedValue
    }
}
