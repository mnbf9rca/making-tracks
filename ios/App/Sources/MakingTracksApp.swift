import SwiftUI
import MakingTracksData

@main
struct MakingTracksApp: App {
    private let database = try! AppDatabase.live()

    var body: some Scene {
        WindowGroup {
            MapScreen(database: database)
        }
    }
}
