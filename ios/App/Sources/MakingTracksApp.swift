import CoreLocation
import SwiftUI
import MakingTracksData

@main
struct MakingTracksApp: App {
    private static let rawArguments = CommandLine.arguments
    private static let arguments = Set(rawArguments)
    private static let isFixtureMap = arguments.contains("--ui-testing-fixture-map")
    private static let seedFixtureUserList = arguments.contains("--ui-testing-seed-user-list")
    private static let startupViewportArgument = argumentValue("--ui-testing-map-state")
    private static let debugInstallOfflineRegion = argumentValue("--debug-install-offline-region")
    private static let debugForceTileNetworkOffline = arguments.contains("--debug-force-tile-network-offline")
#if DEBUG
    private static let isLocationNotDeterminedFixture = arguments.contains("--ui-testing-location-not-determined")
    private static let isLocationDeniedFixture = arguments.contains("--ui-testing-location-denied")
    private static let isLocationAuthorizedFixture = arguments.contains("--ui-testing-location-authorized")
    private static let debugExposeFixturePinDiagnostics = arguments.contains("--ui-testing-pin-diagnostics")
    private static let simulatedLatitude = argumentValue("--ui-testing-location-latitude").flatMap(Double.init)
    private static let simulatedLongitude = argumentValue("--ui-testing-location-longitude").flatMap(Double.init)
    private static let uiTestingOfflineProgress = argumentValue("--ui-testing-offline-progress").flatMap(Double.init)
    private static let primaryFixturePlaceID = "mt1_00000000000000000000000000"
#else
    private static let isLocationNotDeterminedFixture = false
    private static let isLocationDeniedFixture = false
    private static let isLocationAuthorizedFixture = false
    private static let debugExposeFixturePinDiagnostics = false
    private static let simulatedLatitude: Double? = nil
    private static let simulatedLongitude: Double? = nil
    private static let uiTestingOfflineProgress: Double? = nil
#endif

    init() {
        Self.resetUITestingThemeIfNeeded()
        Self.resetUITestingOnboardingIfNeeded()
        Self.completeUITestingOnboardingIfNeeded()
    }

    private let database: AppDatabase = {
        try! resetUITestingDatabaseIfNeeded()
        if isFixtureMap {
            let database = try! AppDatabase.uiTesting()
#if DEBUG
            if seedFixtureUserList {
                try! database.seedUITestingUserList(named: "Date night", containingPlaceID: Self.primaryFixturePlaceID)
            }
#endif
            return database
        }
        return try! AppDatabase.live()
    }()

    private let locationManager: AppLocationManager = {
        if isLocationNotDeterminedFixture {
            return AppLocationManager(simulatedAuthorizationStatus: .notDetermined)
        }
        if isLocationDeniedFixture {
            return AppLocationManager(simulatedAuthorizationStatus: .denied)
        }
        if isLocationAuthorizedFixture,
           let simulatedLatitude,
           let simulatedLongitude {
            return AppLocationManager(
                simulatedAuthorizationStatus: .authorizedWhenInUse,
                simulatedLocation: CLLocationCoordinate2D(latitude: simulatedLatitude, longitude: simulatedLongitude)
            )
        }
        return AppLocationManager()
    }()

    var body: some Scene {
        WindowGroup {
            MakingTracksRootView(
                database: database,
                startupViewportArgument: Self.startupViewportArgument,
                isFixtureMap: Self.isFixtureMap,
                debugInstallOfflineRegion: Self.debugInstallOfflineRegion,
                debugForceTileNetworkOffline: Self.debugForceTileNetworkOffline,
                offlineDownloadProgress: Self.offlineDownloadProgress,
                debugExposeFixturePinDiagnostics: Self.debugExposeFixturePinDiagnostics,
                locationManager: locationManager
            )
        }
    }

    private static func argumentValue(_ flag: String) -> String? {
        guard let index = rawArguments.firstIndex(of: flag),
              rawArguments.index(after: index) < rawArguments.endIndex
        else { return nil }
        return rawArguments[rawArguments.index(after: index)]
    }

    private static func resetUITestingDatabaseIfNeeded() throws {
        guard isFixtureMap, arguments.contains("--ui-testing-reset-database") else { return }
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("MakingTracksUITests", isDirectory: true)
        let dbURL = support.appendingPathComponent("user.sqlite")
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: dbURL.path + suffix))
        }
    }

    private static var offlineDownloadProgress: OfflineDownloadProgress? {
        guard isFixtureMap, let uiTestingOfflineProgress else { return nil }
        return OfflineDownloadProgress(fractionComplete: uiTestingOfflineProgress)
    }

    private static func resetUITestingThemeIfNeeded() {
        guard isFixtureMap, arguments.contains("--ui-testing-reset-theme") else { return }
        UserDefaults.standard.removeObject(forKey: MapScreen.themeStorageKey)
    }

    private static func resetUITestingOnboardingIfNeeded() {
        guard isFixtureMap, arguments.contains("--ui-testing-reset-onboarding") else { return }
        UserDefaults.standard.removeObject(forKey: OnboardingStorage.hasCompletedOnboardingKey)
        UserDefaults.standard.removeObject(forKey: OnboardingStorage.chosenRegionKey)
    }

    private static func completeUITestingOnboardingIfNeeded() {
        guard isFixtureMap, arguments.contains("--ui-testing-complete-onboarding") else { return }
        UserDefaults.standard.set(true, forKey: OnboardingStorage.hasCompletedOnboardingKey)
        if arguments.contains("--ui-testing-reset-database")
            || UserDefaults.standard.string(forKey: OnboardingStorage.chosenRegionKey) == nil {
            UserDefaults.standard.set(OnboardingRegionChoice.malaysia.rawValue, forKey: OnboardingStorage.chosenRegionKey)
        }
    }
}
