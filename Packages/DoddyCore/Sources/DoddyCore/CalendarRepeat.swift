import Foundation

// Repeating events and reminders by voice (ADR-282). "Gym every Monday at 7" becomes one Calendar
// event or Apple reminder with a repeat rule, shown on the card ("Repeats every week on Monday,
// until 31 Dec") and added only on Add. The weekday comes from the first date, as Calendar does
// it; "weekdays" is Monday to Friday. The rule is read back with the event or reminder, so
// "added" means the repeat is there too. This is Apple's own repeat, not Doddy's note reminders
// (ADR-200), which keep their own rules.

public struct CalendarRepeat: Equatable, Sendable {
    public enum Frequency: String, CaseIterable, Equatable, Sendable {
        case daily
        case weekdays
        case weekly
        case everyTwoWeeks = "every_two_weeks"
        case monthly
        case yearly
    }

    public let frequency: Frequency
    /// The last day it can happen, as a day (no time). Nil: no end.
    public let until: ReminderDue?

    public init(frequency: Frequency, until: ReminderDue? = nil) {
        self.frequency = frequency
        self.until = until.map { ReminderDue(year: $0.year, month: $0.month, day: $0.day, timeZoneID: $0.timeZoneID) }
    }

    /// "every week", "every weekday (Monday to Friday)", … for the agent and the log.
    public var text: String {
        let base = switch frequency {
        case .daily: "every day"
        case .weekdays: "every weekday (Monday to Friday)"
        case .weekly: "every week"
        case .everyTwoWeeks: "every two weeks"
        case .monthly: "every month"
        case .yearly: "every year"
        }
        guard let until else { return base }
        return base + " until \(until.localText)"
    }

    /// Gregorian weekdays (1 = Sunday) the rule names, for "weekdays" only; the others repeat on
    /// the first date's own weekday or day.
    public var weekdays: [Int]? { frequency == .weekdays ? [2, 3, 4, 5, 6] : nil }

    /// The rule as Calendar keeps it: unit and interval. Used to read a rule back.
    public var interval: Int { frequency == .everyTwoWeeks ? 2 : 1 }

    /// Reads a rule back from its parts (EventKit's frequency, interval, weekdays and end day).
    /// Nil for anything Doddy doesn't write, so a read-back never "confirms" a different rule.
    public static func from(unit: Unit, interval: Int, weekdays: [Int]?, until: ReminderDue?) -> CalendarRepeat? {
        let days = weekdays.map { Set($0) }
        let frequency: Frequency?
        switch (unit, interval) {
        case (.daily, 1) where days == nil: frequency = .daily
        case (.weekly, 1) where days == Set([2, 3, 4, 5, 6]): frequency = .weekdays
        case (.weekly, 1) where days == nil || days?.count == 1: frequency = .weekly
        case (.weekly, 2) where days == nil || days?.count == 1: frequency = .everyTwoWeeks
        case (.monthly, 1) where days == nil: frequency = .monthly
        case (.yearly, 1) where days == nil: frequency = .yearly
        default: frequency = nil
        }
        return frequency.map { CalendarRepeat(frequency: $0, until: until) }
    }

    public enum Unit: Equatable, Sendable { case daily, weekly, monthly, yearly }

    public var unit: Unit {
        switch frequency {
        case .daily: .daily
        case .weekdays, .weekly, .everyTwoWeeks: .weekly
        case .monthly: .monthly
        case .yearly: .yearly
        }
    }

    /// Same rule, comparing the end by its day only (Calendar may store the end as a moment).
    public func sameRule(as other: CalendarRepeat?) -> Bool {
        guard let other, frequency == other.frequency else { return false }
        switch (until, other.until) {
        case (nil, nil): return true
        case let (a?, b?): return a.year == b.year && a.month == b.month && a.day == b.day
        default: return false
        }
    }

    /// Both nil, or the same rule.
    public static func same(_ a: CalendarRepeat?, _ b: CalendarRepeat?) -> Bool {
        switch (a, b) {
        case (nil, nil): true
        case let (a?, b?): a.sameRule(as: b)
        default: false
        }
    }
}

extension VoiceToolRequest {
    /// `repeat` and `repeat_until` (YYYY-MM-DD, on or after the first date). Nil result and nil
    /// failure: no repeat asked for.
    static func parseRepeat(_ args: Arguments, name: String, first: ReminderDue?, calendar: Calendar) -> Result<CalendarRepeat?, RepeatProblem> {
        guard let text = args.text("repeat") else {
            return args.text("repeat_until") == nil ? .success(nil) : .failure(.invalid("repeat_until needs repeat"))
        }
        guard let frequency = CalendarRepeat.Frequency(rawValue: text) else {
            return .failure(.invalid("repeat must be one of: \(CalendarRepeat.Frequency.allCases.map(\.rawValue).joined(separator: ", "))"))
        }
        guard let first else { return .failure(.invalid("a repeat needs a first date (start or due)")) }
        var until: ReminderDue?
        if let untilText = args.text("repeat_until") {
            switch ReminderDueRules.wallClock(untilText, calendar: calendar) {
            case .clarify(let clarification): return .failure(.clarify(clarification))
            case .due(let day):
                guard !day.hasTime else { return .failure(.invalid("repeat_until is a day (YYYY-MM-DD), without a time")) }
                let firstDay = first.year * 10_000 + first.month * 100 + first.day
                guard day.year * 10_000 + day.month * 100 + day.day >= firstDay else {
                    return .failure(.invalid("repeat_until is before the first date"))
                }
                until = day
            }
        }
        return .success(CalendarRepeat(frequency: frequency, until: until))
    }

    enum RepeatProblem: Error {
        case invalid(String)
        case clarify(ReminderClarification)
    }
}
