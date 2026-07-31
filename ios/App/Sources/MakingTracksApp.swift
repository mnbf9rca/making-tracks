import CoreLocation
import DesignSystem
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
    private static let seedFixtureVisitsEditorVisual = arguments.contains("--ui-testing-seed-visits-editor-visual")
    private static let seedFixtureBurstTrackVisits = arguments.contains("--ui-testing-seed-burst-track-visits")
    private static let seedFixtureTrackList = arguments.contains("--ui-testing-seed-track-list")
    private static let seedFixtureMultiDayTrackList = arguments.contains("--ui-testing-seed-multiday-track-list")
    private static let seedFixtureTrackListLovedVisit = arguments.contains("--ui-testing-seed-track-list-loved-visit")
    private static let seedFixtureSpreadList = arguments.contains("--ui-testing-seed-spread-list")
    private static let seedFixtureJournalDoorTextStress = arguments.contains("--ui-testing-seed-journal-door-text-stress")
    private static let seedFixtureFocusedTracksRoute = arguments.contains("--ui-testing-seed-focused-tracks-route")
    private static let seedFixtureManagedPlaces = arguments.contains("--ui-testing-seed-managed-places")
    private static let simulatedLatitude = argumentValue("--ui-testing-location-latitude").flatMap(Double.init)
    private static let simulatedLongitude = argumentValue("--ui-testing-location-longitude").flatMap(Double.init)
    private static let uiTestingOfflineProgress = argumentValue("--ui-testing-offline-progress").flatMap(Double.init)
    private static let uiTestingOfflineWaiting = arguments.contains("--ui-testing-offline-waiting")
    private static let uiTestingCoverageBBoxes = coverageBBoxArguments()
    private static let debugHideFixtureChrome = arguments.contains("--ui-testing-hide-fixture-chrome")
    private static let debugUseDenseFixturePins = arguments.contains("--ui-testing-dense-pins")
    private static let debugUseReplayVisualFixture = arguments.contains("--ui-testing-replay-visual-seed")
    private static let debugShowChipTargetFixture = arguments.contains("--ui-testing-chip-target")
    private static let primaryFixturePlaceID = "mt1_00000000000000000000000000"
#else
    private static let forceFirstRunOnboarding = false
    private static let isLocationNotDeterminedFixture = false
    private static let isLocationDeniedFixture = false
    private static let isLocationAuthorizedFixture = false
    private static let debugExposeFixturePinDiagnostics = false
    private static let seedFixtureTrackVisits = false
    private static let seedFixtureVisitsEditorVisual = false
    private static let seedFixtureBurstTrackVisits = false
    private static let seedFixtureTrackList = false
    private static let seedFixtureMultiDayTrackList = false
    private static let seedFixtureTrackListLovedVisit = false
    private static let seedFixtureSpreadList = false
    private static let seedFixtureJournalDoorTextStress = false
    private static let seedFixtureFocusedTracksRoute = false
    private static let seedFixtureManagedPlaces = false
    private static let simulatedLatitude: Double? = nil
    private static let simulatedLongitude: Double? = nil
    private static let uiTestingOfflineProgress: Double? = nil
    private static let uiTestingOfflineWaiting = false
    private static let uiTestingCoverageBBoxes: [CoverageBBox] = []
    private static let debugHideFixtureChrome = false
    private static let debugUseDenseFixturePins = false
    private static let debugUseReplayVisualFixture = false
    private static let debugShowChipTargetFixture = false
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
                if seedFixtureManagedPlaces {
                    let hiddenOnly = MapScreen.spreadFixturePlaces[0]
                    let visibleOrdinary = MapScreen.spreadFixturePlaces[1]
                    let seedStart = Date(timeIntervalSince1970: 1_000)
                    try database.recordVisit(
                        fixturePlaces[0],
                        at: seedStart,
                        verdict: .loved
                    )
                    try database.recordVisit(
                        fixturePlaces[1],
                        at: seedStart.addingTimeInterval(60),
                        verdict: .loved
                    )
                    try database.recordVisit(
                        hiddenOnly,
                        at: seedStart.addingTimeInterval(120)
                    )
                    try database.recordVisit(
                        visibleOrdinary,
                        at: seedStart.addingTimeInterval(180)
                    )
                    try database.setHidden(fixturePlaces[1], true)
                    try database.setHidden(hiddenOnly, true)
                    try database.seedUITestingUserList(
                        named: "Date night",
                        containingPlaceID: Self.primaryFixturePlaceID
                    )
                } else if seedFixtureJournalDoorTextStress {
                    let longListName =
                        "Longest list **literal** 0123456789 0123456789 0123456789 "
                        + "0123456789 0123456789!"
                    try database.seedUITestingUserList(
                        named: longListName,
                        containingPlaceID: Self.primaryFixturePlaceID
                    )
                    try database.seedUITestingTrackVisits([
                        fixturePlaces[0],
                        Self.journalDoorTextStressPlace,
                    ])
                } else if seedFixtureFocusedTracksRoute {
                    try database.seedUITestingTrackVisits([
                        fixturePlaces[0],
                        fixturePlaces[0],
                        fixturePlaces[1],
                    ])
                } else if seedFixtureVisitsEditorVisual {
                    try database.seedUITestingTrackVisits(Self.visitsEditorVisualFixturePlaces, multiDay: true)
                } else if seedFixtureMultiDayTrackList {
                    let trackPlaces = Self.debugUseReplayVisualFixture ? Self.replayVisualFixturePlaces : fixturePlaces
                    try database.seedUITestingMultiDayTrackList(
                        named: "Replay week",
                        places: trackPlaces,
                        lovedVisitIndex: seedFixtureTrackListLovedVisit ? 0 : nil
                    )
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

    private static let replayVisualFixturePlaces: [PlaceRef] = {
        let fixtures: [(id: String, name: String, lat: Double, lon: Double, category: String, tier: Int)] = [
            ("mt1_D0000000000000000000000001", "Dense Pin 1", 3.148, 101.662, "attraction", 1),
            ("mt1_D0000000000000000000000002", "Dense Pin 2", 3.213, 101.760, "historic_building", 1),
            ("mt1_D0000000000000000000000003", "Dense Pin 3", 3.080, 101.724, "museum", 1),
            ("mt1_D0000000000000000000000004", "Dense Pin 4", 3.238, 101.682, "artwork", 1),
            ("mt1_D0000000000000000000000005", "Dense Pin 5", 3.116, 101.842, "memorial", 2),
        ]
        let places = fixtures.map { fixture in
            try! PlaceRef(
                placeID: fixture.id,
                name: fixture.name,
                lat: fixture.lat,
                lon: fixture.lon,
                category: fixture.category,
                tier: fixture.tier,
                schemaVersion: 1,
                fetchedAt: Date(timeIntervalSince1970: 0),
                rawJSON: """
                {"blurb":"Fixture pin for replay recording arc geometry.","category":"\(fixture.category)","lat":\(fixture.lat),"lon":\(fixture.lon),"name":"\(fixture.name)","place_id":"\(fixture.id)","score":0.5,"source_refs":["osm:node/\(fixture.id.suffix(1))"],"tier":\(fixture.tier)}
                """
            )
        }
        return [places[0], places[1], places[0], places[2], places[3], places[4]]
    }()

#if DEBUG
    private static let journalDoorTextStressPlace: PlaceRef = {
        let name =
            "[Riverside](https://example.com) **Plaques** "
            + String(repeating: "x", count: 155)
        return try! PlaceRef(
            placeID: "mt1_T0000000000000000000000001",
            name: name,
            lat: 3.151,
            lon: 101.695,
            category: "memorial",
            tier: 1,
            schemaVersion: 1,
            fetchedAt: Date(timeIntervalSince1970: 0),
            rawJSON: """
            {"category":"memorial","lat":3.151,"lon":101.695,"name":"\(name)","place_id":"mt1_T0000000000000000000000001","score":0.5,"source_refs":["osm:node/1"],"tier":1}
            """
        )
    }()

    private static let visitsEditorVisualFixturePlaces: [PlaceRef] = {
        let fixtures: [(id: String, name: String, lat: Double, lon: Double, category: String)] = [
            (
                "mt1_V0000000000000000000000001",
                "Sultan Abdul Samad Building and Merdeka Square",
                3.1487,
                101.6942,
                "historic_building"
            ),
            (
                "mt1_V0000000000000000000000002",
                "National Textile Museum and Historic Railway Offices",
                3.1478,
                101.6934,
                "museum"
            ),
            (
                "mt1_V0000000000000000000000003",
                "Ghost Sign",
                3.1491,
                101.6951,
                "attraction"
            ),
            (
                "mt1_V0000000000000000000000004",
                "Art Deco Cinema",
                3.1502,
                101.6960,
                "historic_building"
            ),
            (
                "mt1_V0000000000000000000000005",
                "Central Market",
                3.1437,
                101.6958,
                "market"
            ),
            (
                "mt1_V0000000000000000000000006",
                "Thean Hou Temple",
                3.1215,
                101.6865,
                "temple"
            ),
            (
                "mt1_V0000000000000000000000007",
                "Petronas Twin Towers Observation Deck",
                3.1579,
                101.7116,
                "attraction"
            ),
            (
                "mt1_V0000000000000000000000008",
                "Jalan Alor Night Market",
                3.1466,
                101.7008,
                "food"
            ),
        ]
        return fixtures.map { fixture in
            try! PlaceRef(
                placeID: fixture.id,
                name: fixture.name,
                lat: fixture.lat,
                lon: fixture.lon,
                category: fixture.category,
                tier: 1,
                schemaVersion: 1,
                fetchedAt: Date(timeIntervalSince1970: 0),
                rawJSON: """
                {"category":"\(fixture.category)","lat":\(fixture.lat),"lon":\(fixture.lon),"name":"\(fixture.name)","place_id":"\(fixture.id)","score":0.5,"source_refs":["osm:node/\(fixture.id.suffix(1))"],"tier":1}
                """
            )
        }
    }()
#endif

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
#if DEBUG
            if Self.debugShowChipTargetFixture {
                ChipHitTargetFixture()
            } else {
                rootView
            }
#else
            rootView
#endif
        }
    }

    @ViewBuilder
    private var rootView: some View {
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
                debugHideFixtureChrome: Self.debugHideFixtureChrome,
                debugUseDenseFixturePins: Self.debugUseDenseFixturePins,
                forceFirstRunOnboarding: Self.forceFirstRunOnboarding,
                locationManager: locationManager
            )
        case .failed(let surface):
            DatabaseRecoveryView(surface: surface)
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
        return OfflineDownloadProgress(
            fractionComplete: uiTestingOfflineProgress,
            isWaitingForConnectivity: uiTestingOfflineWaiting
        )
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
        DiscoveryScopeStore(userDefaults: .standard).reset()
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

#if DEBUG
private struct ChipHitTargetFixture: View {
    @State private var leftActivationCount = 0
    @State private var rightActivationCount = 0

    var body: some View {
        VStack(spacing: 80) {
            HStack(spacing: 6) {
                MaterialChip(
                    "Left chip",
                    state: .active,
                    neighborGaps: MaterialChipNeighborGaps(trailing: 6)
                ) {
                    leftActivationCount += 1
                }
                .accessibilityIdentifier("chip-target.left")

                MaterialChip(
                    "Right chip",
                    state: .available,
                    neighborGaps: MaterialChipNeighborGaps(leading: 6)
                ) {
                    rightActivationCount += 1
                }
                .accessibilityIdentifier("chip-target.right")
            }

            Text(verbatim: "\(leftActivationCount + rightActivationCount)")
                .accessibilityIdentifier("chip-target.activation-count")

            Text(verbatim: "\(leftActivationCount)")
                .accessibilityIdentifier("chip-target.left-count")

            Text(verbatim: "\(rightActivationCount)")
                .accessibilityIdentifier("chip-target.right-count")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MaterialTheme.snow.tokens.background.swiftUIColor)
    }
}
#endif

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
