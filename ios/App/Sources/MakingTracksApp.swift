import CoreLocation
import SwiftUI
import MakingTracksData
import MakingTracksMapStyle
import MakingTracksTiles
import UIKit

@main
struct MakingTracksApp: App {
    @UIApplicationDelegateAdaptor(MakingTracksAppDelegate.self) private var appDelegate

    private static let rawArguments = CommandLine.arguments
    private static let arguments = Set(rawArguments)
    private static let isFixtureMap = arguments.contains("--ui-testing-fixture-map")
    private static let seedFixtureUserList = arguments.contains("--ui-testing-seed-user-list")
    private static let startupViewportArgument = argumentValue("--ui-testing-map-state")
    private static let uiTestingThemeID = argumentValue("--ui-testing-theme")
    private static let uiTestingPinSizeMultiplier = argumentValue("--ui-testing-pin-size-multiplier").flatMap(Double.init)
    private static let debugInstallOfflineRegion = argumentValue("--debug-install-offline-region")
    private static let debugForceTileNetworkOffline = arguments.contains("--debug-force-tile-network-offline")
#if DEBUG
    private static let forceFirstRunOnboarding = isFixtureMap && arguments.contains("--ui-testing-reset-onboarding")
    private static let isLocationNotDeterminedFixture = arguments.contains("--ui-testing-location-not-determined")
    private static let isLocationDeniedFixture = arguments.contains("--ui-testing-location-denied")
    private static let isLocationAuthorizedFixture = arguments.contains("--ui-testing-location-authorized")
    private static let debugExposeFixturePinDiagnostics = arguments.contains("--ui-testing-pin-diagnostics")
    private static let seedFixtureTrackVisits = arguments.contains("--ui-testing-seed-track-visits")
    private static let seedFixtureBurstTrackVisits = arguments.contains("--ui-testing-seed-burst-track-visits")
    private static let seedFixtureTrackList = arguments.contains("--ui-testing-seed-track-list")
    private static let seedFixtureMultiDayTrackList = arguments.contains("--ui-testing-seed-multiday-track-list")
    private static let seedFixtureSpreadList = arguments.contains("--ui-testing-seed-spread-list")
    private static let simulatedLatitude = argumentValue("--ui-testing-location-latitude").flatMap(Double.init)
    private static let simulatedLongitude = argumentValue("--ui-testing-location-longitude").flatMap(Double.init)
    private static let uiTestingOfflineProgress = argumentValue("--ui-testing-offline-progress").flatMap(Double.init)
    private static let uiTestingCoverageBBoxes = coverageBBoxArguments()
    private static let debugUseDenseFixturePins = arguments.contains("--ui-testing-dense-pins")
    private static let primaryFixturePlaceID = "mt1_00000000000000000000000000"
#else
    private static let forceFirstRunOnboarding = false
    private static let isLocationNotDeterminedFixture = false
    private static let isLocationDeniedFixture = false
    private static let isLocationAuthorizedFixture = false
    private static let debugExposeFixturePinDiagnostics = false
    private static let seedFixtureTrackVisits = false
    private static let seedFixtureBurstTrackVisits = false
    private static let seedFixtureTrackList = false
    private static let seedFixtureMultiDayTrackList = false
    private static let seedFixtureSpreadList = false
    private static let simulatedLatitude: Double? = nil
    private static let simulatedLongitude: Double? = nil
    private static let uiTestingOfflineProgress: Double? = nil
    private static let uiTestingCoverageBBoxes: [CoverageBBox] = []
    private static let debugUseDenseFixturePins = false
#endif

    init() {
        Self.configureDiagnosticLogging()
        let fixture = Self.isFixtureMap
        MakingTracksLog.startup.info("app init started fixture=\(fixture, privacy: .public)")
        Self.resetUITestingThemeIfNeeded()
        Self.resetUITestingPinSizeIfNeeded()
        Self.resetUITestingCoverageShadingIfNeeded()
        Self.applyUITestingThemeIfNeeded()
        Self.applyUITestingPinSizeIfNeeded()
        Self.resetUITestingOnboardingIfNeeded()
        Self.completeUITestingOnboardingIfNeeded()
        MakingTracksLog.startup.info("app init finished fixture=\(fixture, privacy: .public)")
    }

    private static func configureDiagnosticLogging() {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "app.making-tracks.MakingTracks"
        do {
            let root = try DiagnosticLogStore.defaultRoot(bundleIdentifier: bundleIdentifier)
            MakingTracksLog.configureDiagnosticLogStore(DiagnosticLogStore(root: root))
        } catch {
            MakingTracksLog.configureDiagnosticLogStore(nil)
        }
    }

    private let databaseStartup: DatabaseStartup = {
        let fixture = isFixtureMap
        MakingTracksLog.startup.info("store init started fixture=\(fixture, privacy: .public)")
        let startup = DatabaseStartupPolicy.open(
            fixture: isFixtureMap,
            resetFixtureStore: {
                try resetUITestingDatabaseIfNeeded()
            },
            openFixtureStore: {
                try AppDatabase.uiTesting()
            },
            openLiveStore: {
                try AppDatabase.live()
            },
            seedFixtureUserList: { database in
#if DEBUG
                if seedFixtureUserList {
                    try database.seedUITestingUserList(named: "Date night", containingPlaceID: Self.primaryFixturePlaceID)
                }
                let fixturePlaces = MapScreen.uiTestingFixturePlaces(dense: Self.debugUseDenseFixturePins)
                if seedFixtureMultiDayTrackList {
                    try database.seedUITestingMultiDayTrackList(named: "Replay week", places: fixturePlaces)
                } else if seedFixtureTrackList {
                    try database.seedUITestingTrackList(named: "Track pair", places: fixturePlaces)
                } else if seedFixtureSpreadList {
                    try database.seedUITestingTrackList(named: "Spread walk", places: MapScreen.spreadFixturePlaces)
                } else if seedFixtureBurstTrackVisits {
                    try database.seedUITestingBurstTrackVisits(fixturePlaces)
                } else if seedFixtureTrackVisits {
                    try database.seedUITestingTrackVisits(fixturePlaces)
                }
#endif
            }
        )
        switch startup {
        case .available:
            if isFixtureMap {
                MakingTracksLog.startup.info("store init finished fixture=true")
            } else {
                MakingTracksLog.startup.info("store init finished fixture=false")
            }
        case .failed(let surface):
            MakingTracksLog.startup.error("store init failed fixture=\(fixture, privacy: .public) reason=\(surface.reasonLabel, privacy: .public)")
        }
        return startup
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
            switch databaseStartup {
            case .available(let database):
                MakingTracksRootView(
                    database: database,
                    startupViewportArgument: Self.startupViewportArgument,
                    isFixtureMap: Self.isFixtureMap,
                    debugInstallOfflineRegion: Self.debugInstallOfflineRegion,
                    debugForceTileNetworkOffline: Self.debugForceTileNetworkOffline,
                    offlineDownloadProgress: Self.offlineDownloadProgress,
                    debugCoverageBBoxes: Self.uiTestingCoverageBBoxes,
                    debugExposeFixturePinDiagnostics: Self.debugExposeFixturePinDiagnostics,
                    debugUseDenseFixturePins: Self.debugUseDenseFixturePins,
                    forceFirstRunOnboarding: Self.forceFirstRunOnboarding,
                    locationManager: locationManager
                )
            case .failed(let surface):
                DatabaseRecoveryView(surface: surface)
            }
        }
    }

    private static func argumentValue(_ flag: String) -> String? {
        guard let index = rawArguments.firstIndex(of: flag),
              rawArguments.index(after: index) < rawArguments.endIndex
        else { return nil }
        return rawArguments[rawArguments.index(after: index)]
    }

#if DEBUG
    private static func coverageBBoxArguments() -> [CoverageBBox] {
        var values: [CoverageBBox] = []
        var index = rawArguments.startIndex
        while index < rawArguments.endIndex {
            defer { index = rawArguments.index(after: index) }
            guard rawArguments[index] == "--ui-testing-coverage-bbox" else { continue }
            let valueIndex = rawArguments.index(after: index)
            guard valueIndex < rawArguments.endIndex else { continue }
            let components = rawArguments[valueIndex].split(separator: ",")
            guard components.count == 4,
                  let minLon = Double(components[0]),
                  let minLat = Double(components[1]),
                  let maxLon = Double(components[2]),
                  let maxLat = Double(components[3])
            else { continue }
            let bbox = CoverageBBox(minLon: minLon, minLat: minLat, maxLon: maxLon, maxLat: maxLat)
            guard bbox.isValid else { continue }
            values.append(bbox)
        }
        return values
    }
#endif

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

    private static func resetUITestingPinSizeIfNeeded() {
        guard isFixtureMap, arguments.contains("--ui-testing-reset-pin-size") else { return }
        UserDefaults.standard.removeObject(forKey: MapScreen.pinSizeMultiplierStorageKey)
    }

    private static func resetUITestingCoverageShadingIfNeeded() {
        guard isFixtureMap, arguments.contains("--ui-testing-reset-coverage-shading") else { return }
        UserDefaults.standard.removeObject(forKey: MapScreen.coverageShadingStorageKey)
    }

    private static func applyUITestingThemeIfNeeded() {
        guard isFixtureMap, let uiTestingThemeID else { return }
        UserDefaults.standard.set(uiTestingThemeID, forKey: MapScreen.themeStorageKey)
    }

    private static func applyUITestingPinSizeIfNeeded() {
        guard isFixtureMap, let uiTestingPinSizeMultiplier else { return }
        UserDefaults.standard.set(uiTestingPinSizeMultiplier, forKey: MapScreen.pinSizeMultiplierStorageKey)
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

enum DatabaseStartup {
    case available(AppDatabase)
    case failed(DatabaseStartupFailureSurface)
}

enum DatabaseStartupPolicy {
    static func open(
        fixture: Bool,
        resetFixtureStore: () throws -> Void,
        openFixtureStore: () throws -> AppDatabase,
        openLiveStore: () throws -> AppDatabase,
        seedFixtureUserList: ((AppDatabase) throws -> Void)?
    ) -> DatabaseStartup {
        do {
            if fixture {
                try resetFixtureStore()
                let database = try openFixtureStore()
                try seedFixtureUserList?(database)
                return .available(database)
            }
            return .available(try openLiveStore())
        } catch {
            return .failed(DatabaseStartupFailureSurface.resolve(error: error))
        }
    }
}

struct DatabaseStartupFailureSurface: Equatable {
    let reasonLabel: String
    let title: String
    let message: String
    let recoveryHint: String

    static func resolve(error: Error) -> DatabaseStartupFailureSurface {
        let reasonLabel: String
        let message: String
        let recoveryHint: String
        if case AppDatabaseError.databaseFromNewerAppVersion = error {
            reasonLabel = "database-from-newer-app-version"
            message = "Making Tracks could not open your on-device history because it was written by a newer app version. Your saved places, lists, and visits have not been erased."
            recoveryHint = "Do not delete or reinstall the app if you want to preserve your history. Update Making Tracks, then try opening it again."
        } else {
            reasonLabel = "database-unavailable"
            message = "Making Tracks could not open your on-device history. Your saved places, lists, and visits have not been erased."
            recoveryHint = "Do not delete or reinstall the app if you want to preserve your history. Try opening Making Tracks again later."
        }
        return DatabaseStartupFailureSurface(
            reasonLabel: reasonLabel,
            title: "History recovery needed",
            message: message,
            recoveryHint: recoveryHint
        )
    }
}

struct DatabaseRecoveryView: View {
    let surface: DatabaseStartupFailureSurface

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(surface.title)
                .font(.title2.weight(.semibold))
                .accessibilityIdentifier("database-recovery.title")
            Text(surface.message)
                .font(.body)
                .accessibilityIdentifier("database-recovery.message")
            Text(surface.recoveryHint)
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("database-recovery.hint")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(24)
        .background(Color(.systemBackground))
    }
}

final class MakingTracksAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        MakingTracksLog.downloads.info("app background events received identifier=\(identifier, privacy: .private(mask: .hash))")
        OfflineDownloadSession.handleEvents(
            for: identifier,
            allowsCellularDownloads: UserDefaults.standard.bool(
                forKey: OfflineDownloadSettings.allowsCellularDownloadsKey
            ),
            completionHandler: completionHandler
        )
    }
}
