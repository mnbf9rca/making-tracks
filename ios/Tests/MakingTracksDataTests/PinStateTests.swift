import XCTest
@testable import MakingTracksData

final class PinStateTests: XCTestCase {
    func testViewportResolvesEveryCellOfThePinMatrix() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 0) })

        func pid(_ n: Int) -> String {
            "mt1_" + String(repeating: String(n % 10), count: 26)
        }

        try db.dbQueue.write { d in
            for n in [1, 3, 5] {
                try d.execute(
                    sql: "INSERT INTO list_items (list_id, place_id, added_at) VALUES (1, ?, ?)",
                    arguments: [pid(n), Date(timeIntervalSince1970: 0)]
                )
            }
            for n in [2, 3] {
                try d.execute(
                    sql: "INSERT INTO visits (place_id, visited_at, created_at) VALUES (?, ?, ?)",
                    arguments: [
                        pid(n),
                        Date(timeIntervalSince1970: 1),
                        Date(timeIntervalSince1970: 1),
                    ]
                )
            }
            for n in [4, 5] {
                try d.execute(
                    sql: "INSERT INTO visits (place_id, visited_at, verdict, created_at) VALUES (?, ?, 'loved', ?)",
                    arguments: [
                        pid(n),
                        Date(timeIntervalSince1970: 1),
                        Date(timeIntervalSince1970: 1),
                    ]
                )
            }
        }
        let all = (0...5).map(pid)
        let state = try db.viewportState(all)
        XCTAssertEqual(state[pid(0)], PinState(saved: false, visit: .none))
        XCTAssertEqual(state[pid(1)], PinState(saved: true, visit: .none))
        XCTAssertEqual(state[pid(2)], PinState(saved: false, visit: .visited))
        XCTAssertEqual(state[pid(3)], PinState(saved: true, visit: .visited))
        XCTAssertEqual(state[pid(4)], PinState(saved: false, visit: .loved))
        XCTAssertEqual(state[pid(5)], PinState(saved: true, visit: .loved))
    }

    func testLovedWinsOverACoexistingPlainVisitInEitherOrder() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 0) })
        try db.dbQueue.write { d in
            try d.execute(sql: "INSERT INTO visits (place_id, visited_at, created_at) VALUES ('pA', 1, 1)")
            try d.execute(sql: "INSERT INTO visits (place_id, visited_at, verdict, created_at) VALUES ('pA', 2, 'loved', 2)")
            try d.execute(sql: "INSERT INTO visits (place_id, visited_at, verdict, created_at) VALUES ('pB', 1, 'loved', 1)")
            try d.execute(sql: "INSERT INTO visits (place_id, visited_at, created_at) VALUES ('pB', 2, 2)")
        }
        let state = try db.viewportState(["pA", "pB"])
        XCTAssertEqual(state["pA"], PinState(saved: false, visit: .loved))
        XCTAssertEqual(state["pB"], PinState(saved: false, visit: .loved))
    }

    func testSavedStateReflectsMembershipInAnyList() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 0) })
        try db.dbQueue.write { d in
            try d.execute(
                sql: "INSERT INTO lists (id, name, is_system, created_at) VALUES (10, 'Date night', 0, 0)"
            )
            try d.execute(
                sql: "INSERT INTO list_items (list_id, place_id, added_at) VALUES (1, 'p_want', 0)"
            )
            try d.execute(
                sql: "INSERT INTO list_items (list_id, place_id, added_at) VALUES (10, 'p_user_list_only', 0)"
            )
        }

        let state = try db.viewportState(["p_want", "p_user_list_only"])

        XCTAssertEqual(state["p_want"], PinState(saved: true, visit: .none))
        XCTAssertEqual(state["p_user_list_only"], PinState(saved: true, visit: .none))
    }

    func testUserListNamesExcludeSystemListAndDeduplicateNames() throws {
        let db = try AppDatabase.inMemory(now: { Date(timeIntervalSince1970: 0) })
        try db.dbQueue.write { d in
            try d.execute(
                sql: "INSERT INTO lists (id, name, is_system, created_at) VALUES (10, 'Date night', 0, 0)"
            )
            try d.execute(
                sql: "INSERT INTO lists (id, name, is_system, created_at) VALUES (11, 'Date night', 0, 0)"
            )
            try d.execute(
                sql: "INSERT INTO lists (id, name, is_system, created_at) VALUES (12, 'Architecture', 0, 0)"
            )
            for listID in [1, 10, 11, 12] {
                try d.execute(
                    sql: "INSERT INTO list_items (list_id, place_id, added_at) VALUES (?, 'p_listed', 0)",
                    arguments: [listID]
                )
            }
        }

        XCTAssertEqual(try db.userListNames(containing: "p_listed"), ["Architecture", "Date night"])
    }
}
