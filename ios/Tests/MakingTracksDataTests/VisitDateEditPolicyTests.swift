import Foundation
import XCTest
@testable import MakingTracksData

final class VisitDateEditPolicyTests: XCTestCase {
    func testTodayEndsAtLastSecondAndClampsTomorrowBackToToday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Kuala_Lumpur"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 6,
            hour: 9
        )))
        let laterToday = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 6,
            hour: 22
        )))
        let tomorrow = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 7,
            hour: 9
        )))

        let policy = VisitDateEditPolicy(now: now, calendar: calendar)

        XCTAssertEqual(
            calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: policy.latestSelectableDate
            ),
            DateComponents(
                year: 2026,
                month: 8,
                day: 6,
                hour: 23,
                minute: 59,
                second: 59
            )
        )
        XCTAssertTrue(policy.contains(laterToday))
        XCTAssertFalse(policy.contains(tomorrow))
        XCTAssertEqual(policy.clamped(tomorrow), policy.today)
    }

    func testCalendarDayFollowsSuppliedTimeZoneWhenUTCDateDiffers() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Pacific/Kiritimati"))
        let now = Date(timeIntervalSince1970: 1_775_565_000)
        let laterLocalToday = Date(timeIntervalSince1970: 1_775_608_200)

        let policy = VisitDateEditPolicy(now: now, calendar: calendar)

        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day], from: policy.today),
            DateComponents(year: 2026, month: 4, day: 8)
        )
        XCTAssertTrue(policy.contains(laterLocalToday))
    }
}
