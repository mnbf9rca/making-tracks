import Foundation
import GRDB

/// The on-device user-data store. `Sendable`: a `DatabaseQueue` serializes all
/// access, and `now` is a Sendable clock injected for deterministic tests.
public final class AppDatabase: Sendable {
    let dbQueue: DatabaseQueue
    let now: @Sendable () -> Date

    public init(_ dbQueue: DatabaseQueue, now: @escaping @Sendable () -> Date) throws {
        self.dbQueue = dbQueue
        self.now = now
        try open()
    }

    public static func inMemory(
        now: @escaping @Sendable () -> Date = { Date() }
    ) throws -> AppDatabase {
        try AppDatabase(try DatabaseQueue(), now: now)
    }

    private func open() throws {
        try migrate()
    }

    func migrate() throws {}
}
