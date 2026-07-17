import SwiftUI
import MakingTracksData

@main
struct MakingTracksApp: App {
    private static let rawArguments = CommandLine.arguments
    private static let arguments = Set(rawArguments)
    private static let isFixtureMap = arguments.contains("--ui-testing-fixture-map")
    private static let startupViewport = ViewportSeed.selected(argumentValue("--ui-testing-map-state"))
    private static let debugInstallOfflineRegion = argumentValue("--debug-install-offline-region")
    private static let debugForceTileNetworkOffline = arguments.contains("--debug-force-tile-network-offline")
    private let database: AppDatabase = {
        try! resetUITestingDatabaseIfNeeded()
        if isFixtureMap {
            return try! AppDatabase.uiTesting()
        }
        return try! AppDatabase.live()
    }()

    var body: some Scene {
        WindowGroup {
            MapScreen(
                database: database,
                startupViewport: Self.startupViewport,
                isFixtureMap: Self.isFixtureMap,
                debugInstallOfflineRegion: Self.debugInstallOfflineRegion,
                debugForceTileNetworkOffline: Self.debugForceTileNetworkOffline
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
}
