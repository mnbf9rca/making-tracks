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

    func testNonFiniteDatesAreRejectedAndClampToToday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Kuala_Lumpur"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 6,
            hour: 9
        )))
        let policy = VisitDateEditPolicy(now: now, calendar: calendar)
        let malformedDates = [
            Date(timeIntervalSinceReferenceDate: .nan),
            Date(timeIntervalSinceReferenceDate: .infinity),
            Date(timeIntervalSinceReferenceDate: -.infinity),
        ]

        for malformedDate in malformedDates {
            XCTAssertFalse(policy.contains(malformedDate))
            XCTAssertEqual(policy.clamped(malformedDate), policy.today)
        }
    }

    func testLatestSelectableDateIncludesEverySubsecondBeforeTomorrow() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Kuala_Lumpur"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 6,
            hour: 9
        )))
        let tomorrow = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 8,
            day: 7
        )))
        let finalHalfSecond = tomorrow.addingTimeInterval(-0.5)
        let policy = VisitDateEditPolicy(now: now, calendar: calendar)

        XCTAssertTrue(policy.contains(finalHalfSecond))
        XCTAssertGreaterThanOrEqual(policy.latestSelectableDate, finalHalfSecond)
        XCTAssertEqual(policy.clamped(finalHalfSecond), finalHalfSecond)
    }

    func testLatestSelectableDateUsesCalendarArithmeticAcrossDSTStart() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 3,
            day: 8,
            hour: 12
        )))
        let expectedToday = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 3,
            day: 8
        )))
        let expectedTomorrow = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026,
            month: 3,
            day: 9
        )))
        let policy = VisitDateEditPolicy(now: now, calendar: calendar)

        XCTAssertEqual(expectedTomorrow.timeIntervalSince(expectedToday), 23 * 60 * 60)
        XCTAssertEqual(
            policy.latestSelectableDate.timeIntervalSinceReferenceDate,
            expectedTomorrow.timeIntervalSinceReferenceDate.nextDown
        )
    }
}
