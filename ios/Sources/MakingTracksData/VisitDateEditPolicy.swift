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
        latestSelectableDate = calendar.date(byAdding: .second, value: -1, to: tomorrow) ?? now
    }

    public func contains(_ date: Date) -> Bool {
        calendar.startOfDay(for: date) <= today
    }

    public func clamped(_ date: Date) -> Date {
        contains(date) ? date : today
    }
}
