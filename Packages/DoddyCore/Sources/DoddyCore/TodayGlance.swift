import Foundation

// Home → Today at a glance (decision docs/decisions/2026-11-10-today-at-a-glance.md): one line about
// the day, what's on now and next, the rest of today with the free time between events, reminders
// due, and the first few things tomorrow. Worked out by code from what Calendar and Reminders hold on
// this iPhone (`TodayAgenda`'s rules for what is left of today); no model writes any of it, and
// nothing here leaves the phone. Clock times are written by the screen with the iPhone's formatter.

/// Where an event stands at a moment.
public enum NextUpStatus: Equatable, Sendable {
    /// Starts in this many minutes (rounded up, so never 0 before it starts).
    case startsIn(minutes: Int)
    /// On now, until its end.
    case now(until: Date)
    case over

    public static func of(_ event: CalendarEventSummary, at now: Date) -> NextUpStatus {
        if event.start > now {
            return .startsIn(minutes: max(1, Int((event.start.timeIntervalSince(now) / 60).rounded(.up))))
        }
        return event.end > now ? .now(until: event.end) : .over
    }
}

extension FreeDay.Slot {
    public var minutes: Int { Int(end.timeIntervalSince(start) / 60) }
}

public enum TodayTimelineItem: Equatable, Sendable {
    case event(CalendarEventSummary)
    /// Free time between two events, from `FreeTime.days` (ADR-332).
    case free(FreeDay.Slot)
}

public enum TomorrowItem: Equatable, Sendable {
    case event(CalendarEventSummary)
    case reminder(ReminderSummary)
}

/// What Today shows, chosen and ordered deterministically from the events and reminders read.
public struct TodayGlance: Equatable, Sendable {
    /// Shorter gaps between events aren't worth a line.
    public static let minimumFreeMinutes = 30
    /// Timed events listed after the next one; the rest are counted.
    public static let laterLimit = 6
    public static let tomorrowLimit = 3

    public let calendarOn: Bool
    public let remindersOn: Bool
    /// Today's all-day events, by title.
    public let allDay: [CalendarEventSummary]
    /// Timed events that have started and not ended, by start.
    public let onNow: [CalendarEventSummary]
    /// The first timed event that hasn't started yet.
    public let nextUp: CalendarEventSummary?
    /// Free time between what's on now and `nextUp`.
    public let freeBeforeNext: FreeDay.Slot?
    /// The timed events after `nextUp` (at most `laterLimit`), with the free time between them.
    public let later: [TodayTimelineItem]
    public let moreLater: Int
    /// Incomplete reminders due today or overdue, oldest due first (at most `TodayAgenda.limit`).
    public let reminders: [ReminderSummary]
    public let moreReminders: Int
    /// Counts over everything read, not only what is listed.
    public let eventsLeft: Int
    public let remindersDue: Int
    public let overdue: Int
    /// Tomorrow's first few things: all-day events, then events and timed reminders by time, then
    /// reminders due that day without a time.
    public let tomorrow: [TomorrowItem]
    public let moreTomorrow: Int

    /// `events` and `reminders` may run to the end of tomorrow; what each part shows is chosen here.
    public init(events: [CalendarEventSummary], reminders: [ReminderSummary], now: Date, calendar: Calendar,
                calendarOn: Bool = true, remindersOn: Bool = true) {
        let readEvents = calendarOn ? events : []
        let readReminders = remindersOn ? reminders : []
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let endOfTomorrow = calendar.date(byAdding: .day, value: 1, to: endOfToday) ?? endOfToday
        let today = TodayAgenda(events: readEvents, reminders: readReminders, now: now, calendar: calendar, limit: .max)
        let timed = today.events.filter { !$0.allDay }
        let upcoming = timed.filter { $0.start > now }
        let free = Self.freeBetweenEvents(timed, now: now, calendar: calendar)

        self.calendarOn = calendarOn
        self.remindersOn = remindersOn
        allDay = today.events.filter(\.allDay).sorted { $0.title < $1.title }
        onNow = timed.filter { $0.start <= now }
        let next = upcoming.first
        nextUp = next
        freeBeforeNext = next.flatMap { next in free.first { $0.end == next.start } }

        let shownLater = Array(upcoming.dropFirst().prefix(Self.laterLimit))
        moreLater = max(0, upcoming.count - 1 - Self.laterLimit)
        var gaps = free.filter { gap in next.map { gap.start >= $0.start } ?? false }
        var items: [TodayTimelineItem] = []
        for event in shownLater {
            while let gap = gaps.first, gap.end <= event.start {
                items.append(.free(gap))
                gaps.removeFirst()
            }
            items.append(.event(event))
        }
        later = items

        self.reminders = Array(today.reminders.prefix(TodayAgenda.limit))
        moreReminders = max(0, today.reminders.count - TodayAgenda.limit)
        eventsLeft = today.events.count
        remindersDue = today.reminders.count
        overdue = today.reminders.filter { TodayAgenda.isOverdue($0, now: now, calendar: calendar) }.count

        let tomorrowEvents = readEvents
            .filter { $0.start >= endOfToday && $0.start < endOfTomorrow }
            .map { (rank: $0.allDay ? 0 : 1, time: $0.start, title: $0.title, item: TomorrowItem.event($0)) }
        let tomorrowReminders = readReminders
            .filter { reminder in reminder.due.map { $0 >= endOfToday && $0 < endOfTomorrow } ?? false }
            .map { (rank: $0.dueHasTime ? 1 : 2, time: $0.due ?? endOfToday, title: $0.title, item: TomorrowItem.reminder($0)) }
        let all = (tomorrowEvents + tomorrowReminders).sorted { ($0.rank, $0.time, $0.title) < ($1.rank, $1.time, $1.title) }
        tomorrow = all.prefix(Self.tomorrowLimit).map(\.item)
        moreTomorrow = max(0, all.count - Self.tomorrowLimit)
    }

    /// Nothing left today in what is switched on.
    public var isEmpty: Bool { eventsLeft == 0 && remindersDue == 0 }

    /// The rest of today's free time of at least `minimumFreeMinutes` (as "When am I free?" works it
    /// out, ADR-332, over the whole day) that has an event on both sides: the time before the first
    /// event is what "in 2 h" already says, and the evening after the last one isn't a gap.
    public static func freeBetweenEvents(_ events: [CalendarEventSummary], now: Date, calendar: Calendar) -> [FreeDay.Slot] {
        let today = calendar.startOfDay(for: now)
        let wholeDay = FreeTimeRequest(firstDay: today, days: 1, minMinutes: minimumFreeMinutes, earliest: 0, latest: 24 * 60)
        guard let day = FreeTime.days(wholeDay, events: events, now: now, calendar: calendar).first,
              let dayEnd = calendar.date(byAdding: .minute, value: 24 * 60, to: today) else { return [] }
        return day.slots.filter { $0.start > now && $0.end < dayEnd }
    }

    /// The event's location as a place Maps can look up: trimmed, on one line, and nil for nothing
    /// or a web address (an online meeting has no place to go to).
    public static func mapsPlace(_ location: String?) -> String? {
        guard let location else { return nil }
        let place = location
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        guard !place.isEmpty else { return nil }
        let lower = place.lowercased()
        if lower.contains("://") || lower.hasPrefix("www.") { return nil }
        return place
    }
}

/// Ticking off a reminder from Today goes ahead only for the reminder the row showed: Reminders is
/// read again just before the write, and it must still be open, with the same title and due.
public enum ReminderTick {
    public static func stillAsShown(_ shown: ReminderSummary, now current: ReminderSnapshot, local: Calendar) -> Bool {
        // Reminders without a title are listed as "Untitled" (DeviceConnections.remindersDue).
        let title = current.title.isEmpty ? "Untitled" : current.title
        guard current.id == shown.id, !current.isCompleted, title == shown.title || current.title == shown.title else { return false }
        switch (shown.due, current.due) {
        case (nil, nil):
            return true
        case let (shownDue?, due?):
            guard due.hasTime == shown.dueHasTime, let moment = EventChange.moment(due, local: local) else { return false }
            return abs(moment.timeIntervalSince(shownDue)) < 60
        default:
            return false
        }
    }
}

/// Today's words that depend on counts, in Polish and English like `OpenLoopsText`; the other
/// languages show English until the catalogs have them. They say what Calendar and Reminders hold
/// and nothing about how the person is doing.
public enum TodayGlanceText {
    /// "3 events left, the next at 14:00 · 2 reminders, 1 overdue". `nextTime` is the next event's
    /// start as the iPhone writes clock times.
    public static func summary(_ glance: TodayGlance, nextTime: String?, _ language: NotificationLanguage) -> String {
        let polish = language == .polish
        if glance.isEmpty {
            switch (glance.calendarOn, glance.remindersOn) {
            case (true, false): return polish ? "Dziś już bez wydarzeń" : "No more events today"
            case (false, true): return polish ? "Na dziś brak przypomnień" : "No reminders due today"
            default: return polish ? "Na dziś nic już nie zostało" : "Nothing left for today"
            }
        }
        var parts: [String] = []
        if glance.calendarOn {
            let n = glance.eventsLeft
            if n == 0 {
                parts.append(polish ? "Dziś już bez wydarzeń" : "No more events today")
            } else {
                var line = polish
                    ? "Jeszcze \(n) \(plural(n, "wydarzenie", "wydarzenia", "wydarzeń"))"
                    : "\(n) \(n == 1 ? "event" : "events") left"
                if glance.nextUp != nil, let nextTime {
                    line += polish ? ", następne o \(nextTime)" : ", the next at \(nextTime)"
                }
                parts.append(line)
            }
        }
        if glance.remindersOn {
            let n = glance.remindersDue, late = glance.overdue
            if n == 0 {
                parts.append(polish ? "Brak przypomnień na dziś" : "No reminders due")
            } else {
                var line = polish
                    ? "\(n) \(plural(n, "przypomnienie", "przypomnienia", "przypomnień"))"
                    : "\(n) \(n == 1 ? "reminder" : "reminders")"
                if late > 0 {
                    line += polish ? ", w tym \(late) \(plural(late, "zaległe", "zaległe", "zaległych"))" : ", \(late) overdue"
                }
                parts.append(line)
            }
        }
        return parts.joined(separator: " · ")
    }

    /// "in 25 min", "in 1 h 10 min"; "now, until 15:00". `endTime` is the event's end as the iPhone writes it.
    public static func status(_ status: NextUpStatus, endTime: String, _ language: NotificationLanguage) -> String {
        let polish = language == .polish
        switch status {
        case .startsIn(let minutes): return (polish ? "za " : "in ") + duration(minutes)
        case .now: return polish ? "teraz, do \(endTime)" : "now, until \(endTime)"
        case .over: return polish ? "zakończone" : "over"
        }
    }

    /// "Free 11:00–13:30 · 2 h 30 min".
    public static func free(_ free: FreeDay.Slot, start: String, end: String, _ language: NotificationLanguage) -> String {
        (language == .polish ? "Wolne \(start)–\(end)" : "Free \(start)–\(end)") + " · " + duration(free.minutes)
    }

    /// "25 min", "2 h", "1 h 10 min": short, so Polish needs no plural forms (as `RingingTimers`).
    public static func duration(_ minutes: Int) -> String {
        let minutes = max(0, minutes)
        let hours = minutes / 60, rest = minutes % 60
        switch (hours, rest) {
        case (0, _): return "\(rest) min"
        case (_, 0): return "\(hours) h"
        default: return "\(hours) h \(rest) min"
        }
    }

    private static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        if n == 1 { return one }
        let lastTwo = n % 100, last = n % 10
        return (2...4).contains(last) && !(12...14).contains(lastTwo) ? few : many
    }
}
