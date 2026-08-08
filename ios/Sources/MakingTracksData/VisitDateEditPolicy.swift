import Foundation

public struct VisitDateEditPolicy: Sendable {
    public let today: Date
    public let latestSelectableDate: Date

    private let calendar: Calendar

    public init(
        now: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) {
        self.calendar = calendar
        today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        latestSelectableDate = Date(
            timeIntervalSinceReferenceDate: tomorrow.timeIntervalSinceReferenceDate.nextDown
        )
    }

    public func contains(_ date: Date) -> Bool {
        guard date.timeIntervalSinceReferenceDate.isFinite else { return false }
        return calendar.startOfDay(for: date) <= today
    }

    public func clamped(_ date: Date) -> Date {
        contains(date) ? date : today
    }
}
