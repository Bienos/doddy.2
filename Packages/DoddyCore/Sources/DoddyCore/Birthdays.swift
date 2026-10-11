import Foundation

// "Whose birthday is coming up?" (ADR-266). A read-only look at the birthdays saved in the
// iPhone's Contacts, for the next few days. Nothing is written anywhere and no reminder is set;
// the agent can offer one, which goes through the usual create_reminder card. The agent hears
// each person's name and the day and month only: never the birth year, an age, or any other
// contact detail. Uses the Contacts switch in Settings, Connections, like lookup_contact.

extension VoiceToolName {
    public static let upcomingBirthdays = "upcoming_birthdays"
}

/// A birthday as saved in Contacts. `year` is nil when the card has only a day and month; it is
/// only used to tell real dates from impossible ones and is never sent to the agent.
public struct ContactBirthday: Equatable, Sendable {
    public let name: String
    public let month: Int
    public let day: Int
    public let year: Int?

    public init(name: String, month: Int, day: Int, year: Int? = nil) {
        self.name = name
        self.month = month
        self.day = day
        self.year = year
    }
}

/// One birthday on its next date.
public struct UpcomingBirthday: Equatable, Sendable {
    public let name: String
    /// Start of the day it falls on this year (or next), in the user's calendar.
    public let date: Date
    /// 0 for today, 1 for tomorrow.
    public let daysAway: Int
    /// A 29 February birthday shown on 28 February in a year without one.
    public let movedFromLeapDay: Bool
}

public enum Birthdays {
    public static let defaultDays = 7
    public static let maxDays = 60
    /// The agent hears at most this many; the rest are counted.
    public static let maxListed = 15

    /// Every birthday from today through the next `days - 1` days, soonest first, then by name.
    /// A 29 February birthday falls on 28 February in other years. Impossible dates are skipped.
    public static func upcoming(_ birthdays: [ContactBirthday], now: Date, days: Int, calendar: Calendar) -> [UpcomingBirthday] {
        let today = calendar.startOfDay(for: now)
        let thisYear = calendar.component(.year, from: today)
        let span = min(max(days, 1), maxDays)
        var found: [UpcomingBirthday] = []
        for birthday in birthdays {
            guard (1...12).contains(birthday.month), (1...31).contains(birthday.day) else { continue }
            if let year = birthday.year, !isRealDate(year: year, month: birthday.month, day: birthday.day, calendar: calendar) { continue }
            for year in [thisYear, thisYear + 1] {
                guard let (date, moved) = occurrence(birthday, in: year, calendar: calendar), date >= today else { continue }
                let away = calendar.dateComponents([.day], from: today, to: date).day ?? Int.max
                if away < span {
                    found.append(UpcomingBirthday(name: birthday.name, date: date, daysAway: away, movedFromLeapDay: moved))
                }
                break
            }
        }
        return found.sorted { ($0.daysAway, $0.name) < ($1.daysAway, $1.name) }
    }

    /// The day in `year`, or 28 February for a 29 February birthday in a year without one.
    private static func occurrence(_ birthday: ContactBirthday, in year: Int, calendar: Calendar) -> (Date, Bool)? {
        if isRealDate(year: year, month: birthday.month, day: birthday.day, calendar: calendar) {
            return calendar.date(from: DateComponents(year: year, month: birthday.month, day: birthday.day)).map { ($0, false) }
        }
        guard birthday.month == 2, birthday.day == 29 else { return nil }
        return calendar.date(from: DateComponents(year: year, month: 2, day: 28)).map { ($0, true) }
    }

    private static func isRealDate(year: Int, month: Int, day: Int, calendar: Calendar) -> Bool {
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return false }
        let back = calendar.dateComponents([.year, .month, .day], from: date)
        return back.year == year && back.month == month && back.day == day
    }
}

extension VoiceToolRequest {
    /// `days`: optional, a whole number from 1 to 60; the next 7 days when missing.
    static func parseBirthdays(_ args: Arguments, name: String) -> VoiceToolRequest {
        let given = args.number("days") ?? args.text("days").flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard let given else {
            if args.has("days") { return .invalid(name: name, reason: "days must be a whole number from 1 to \(Birthdays.maxDays)") }
            return .upcomingBirthdays(days: Birthdays.defaultDays)
        }
        guard given == given.rounded(), let days = Int(exactly: given), (1...Birthdays.maxDays).contains(days) else {
            return .invalid(name: name, reason: "days must be a whole number from 1 to \(Birthdays.maxDays)")
        }
        return .upcomingBirthdays(days: days)
    }
}

extension VoiceToolReply {
    /// Names with the day and month only. Never a year or an age.
    public static func birthdays(_ found: [UpcomingBirthday], days: Int, calendar: Calendar) -> String {
        let period = days == 1 ? "today" : "in the next \(days) days (today included)"
        guard !found.isEmpty else {
            return "birthdays: no birthdays saved in the user's Contacts \(period). Only birthdays saved on contact cards are known; don't guess others."
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEE d MMM"
        let listed = found.prefix(Birthdays.maxListed).map { birthday -> String in
            let when: String
            switch birthday.daysAway {
            case 0: when = "today"
            case 1: when = "tomorrow"
            default: when = formatter.string(from: birthday.date)
            }
            let leap = birthday.movedFromLeapDay ? " (born 29 Feb)" : ""
            return "\"\(birthday.name)\" \(when)\(leap)"
        }
        let more = found.count > Birthdays.maxListed ? "; and \(found.count - Birthdays.maxListed) more" : ""
        return "birthdays: from the user's Contacts \(period): \(listed.joined(separator: "; "))\(more). Ages and years are not shared with you; don't guess them."
    }
}
