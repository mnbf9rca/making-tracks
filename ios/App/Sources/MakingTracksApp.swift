import SwiftUI
import MakingTracksData

@main
struct MakingTracksApp: App {
    private static let arguments = Set(CommandLine.arguments)
    private static let isFixtureMap = arguments.contains("--ui-testing-fixture-map")
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
                isFixtureMap: Self.isFixtureMap
            )
        }
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
