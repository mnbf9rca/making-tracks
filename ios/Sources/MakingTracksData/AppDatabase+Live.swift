import Foundation
import GRDB

public extension AppDatabase {
    static func live() throws -> AppDatabase {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("MakingTracks", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let queue = try DatabaseQueue(path: support.appendingPathComponent("user.sqlite").path)
        return try AppDatabase(queue, now: { Date() })
    }
}
