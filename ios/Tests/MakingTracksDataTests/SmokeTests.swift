import XCTest
import GRDB
@testable import MakingTracksData

final class SmokeTests: XCTestCase {
    func testInMemoryDatabaseOpens() throws {
        let db = try AppDatabase.inMemory()
        XCTAssertNotNil(db)
    }
}
