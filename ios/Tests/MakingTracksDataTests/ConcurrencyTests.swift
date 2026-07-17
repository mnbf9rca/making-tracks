import XCTest
import GRDB
@testable import MakingTracksData

final class ConcurrencyTests: XCTestCase {
    func testConcurrentWritesAreSerializedAndConsistent() async throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 0) })

        func ref(_ index: Int) throws -> PlaceRef {
            try PlaceRef(
                placeID: "p\(index)",
                name: "Place \(index)",
                lat: 0,
                lon: 0,
                category: "test",
                tier: 1,
                schemaVersion: 1,
                fetchedAt: Date(timeIntervalSince1970: 0),
                rawJSON: "{\"place_id\":\"p\(index)\"}"
            )
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<50 {
                group.addTask {
                    _ = try db.recordVisit(try ref(index))
                }
            }

            for try await _ in group {}
        }

        let count = try await db.dbQueue.read {
            try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM visits")
        } ?? 0
        XCTAssertEqual(count, 50)
    }
}
