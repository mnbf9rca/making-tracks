import Foundation
import GRDB

public extension AppDatabase {
    static func live() throws -> AppDatabase {
        try live(supportSubdirectory: "MakingTracks")
    }

    static func uiTesting() throws -> AppDatabase {
        try live(supportSubdirectory: "MakingTracksUITests")
    }

    private static func live(supportSubdirectory: String) throws -> AppDatabase {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent(supportSubdirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let queue = try DatabaseQueue(path: support.appendingPathComponent("user.sqlite").path)
        return try AppDatabase(queue, now: { Date() })
    }
}
