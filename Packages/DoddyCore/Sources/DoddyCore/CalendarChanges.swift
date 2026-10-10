import Foundation

// Moving and renaming calendar events, and changing or completing Apple reminders, by voice
// (ADR-229). The agent names the event exactly as read_calendar returned it (title and start), or
// the reminder by its exact title. The app finds exactly one match on the iPhone, shows a card
// with the change ("Before → After"), and changes it only after the user taps Change. The write
// is read back from Calendar or Reminders before Doddy says it's done. Deleting is still not
// offered, and a repeating event changes only this occurrence.

extension VoiceToolName {
    public static let changeCalendarEvent = "change_calendar_event"
    public static let changeReminder = "change_reminder"
}

public struct EventChangeDraft: Equatable, Sendable {
    /// The event as the agent read it: exact title and its current start.
    public let title: String
    public let currentStart: Date
    /// Only this date counts (an all-day event named by its day).
    public let currentIsDayOnly: Bool
    public let newStart: Date?
    public let newEnd: Date?
    public let newTitle: String?

    public init(title: String, currentStart: Date, currentIsDayOnly: Bool, newStart: Date?, newEnd: Date?, newTitle: String?) {
        self.title = title
        self.currentStart = currentStart
        self.currentIsDayOnly = currentIsDayOnly
        self.newStart = newStart
        self.newEnd = newEnd
        self.newTitle = newTitle
    }
}

public struct ReminderChangeDraft: Equatable, Sendable {
    public let title: String
    public let newDue: ReminderDue?
    public let markDone: Bool

    public init(title: String, newDue: ReminderDue?, markDone: Bool) {
        self.title = title
        self.newDue = newDue
        self.markDone = markDone
    }
}

/// What the card shows and what is written: the event as it is now and as it will be.
public struct EventChangePlan: Equatable, Sendable {
    public let before: CalendarEventSummary
    public let after: CalendarEventSummary
}

public enum EventChange {
    public static let maxTitleLength = 200

    /// Exactly one event with this title (ignoring case, accents and punctuation) starting at the
    /// same minute (or on the same day, for a day-only name). Otherwise nothing is guessed.
    public static func match(_ draft: EventChangeDraft, in events: [CalendarEventSummary], calendar: Calendar) -> ListMatchResult<CalendarEventSummary> {
        let wanted = SearchFolding.tokens(draft.title).joined(separator: " ")
        guard !wanted.isEmpty else { return .none }
        let found = events.filter { event in
            guard SearchFolding.tokens(event.title).joined(separator: " ") == wanted else { return false }
            if draft.currentIsDayOnly { return calendar.isDate(event.start, inSameDayAs: draft.currentStart) }
            return abs(event.start.timeIntervalSince(draft.currentStart)) < 60
        }
        switch found.count {
        case 0: return .none
        case 1: return .one(found[0])
        default: return .several(found)
        }
    }

    /// The new event. A new start alone keeps the length; a new end alone keeps the start. An
    /// all-day event moved to a day stays all day. Nil when the result makes no sense.
    public static func plan(_ draft: EventChangeDraft, for event: CalendarEventSummary, calendar: Calendar) -> EventChangePlan? {
        var start = event.start, end = event.end
        let length = event.end.timeIntervalSince(event.start)
        if let newStart = draft.newStart {
            if event.allDay {
                start = calendar.startOfDay(for: newStart)
                end = calendar.date(byAdding: .day, value: max(1, Int((length / 86_400).rounded())), to: start) ?? start
            } else {
                start = newStart
                end = newStart.addingTimeInterval(length)
            }
        }
        if let newEnd = draft.newEnd, !event.allDay { end = newEnd }
        guard end > start else { return nil }
        let title = draft.newTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? event.title
        guard title.count <= maxTitleLength else { return nil }
        let after = CalendarEventSummary(id: event.id, title: title, start: start, end: end, allDay: event.allDay)
        guard after != event else { return nil }
        return EventChangePlan(before: event, after: after)
    }

    /// Where to look for the event: the whole day it starts on.
    public static func searchRange(_ draft: EventChangeDraft, calendar: Calendar) -> VoiceTimeRange {
        let day = calendar.startOfDay(for: draft.currentStart)
        return VoiceTimeRange(start: day, end: calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400))
    }

    /// The new start passed while the card waited: nothing is moved into the past.
    public static func startPassed(_ plan: EventChangePlan, now: Date, calendar: Calendar) -> Bool {
        guard plan.after.start != plan.before.start else { return false }
        return plan.after.allDay ? plan.after.start < calendar.startOfDay(for: now) : plan.after.start <= now
    }

    /// Read-back for a reminder's due: the same day and wall-clock time (the zone may come back
    /// spelled differently).
    public static func sameDue(_ a: ReminderDue?, _ b: ReminderDue?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (a?, b?): return a.year == b.year && a.month == b.month && a.day == b.day && a.hour == b.hour && (a.minute ?? 0) == (b.minute ?? 0)
        default: return false
        }
    }

    /// The moment a due stands for: in its own time zone when it has one, else on this iPhone's
    /// clock (a floating day or time, as Reminders keeps it).
    public static func moment(_ due: ReminderDue, local: Calendar) -> Date? {
        due.date(in: due.timeZoneID == nil ? local : due.calendar)
    }

    /// A new timed due passed while the card waited.
    public static func duePassed(_ due: ReminderDue?, now: Date, local: Calendar) -> Bool {
        guard let due, due.hasTime, let date = moment(due, local: local) else { return false }
        return date <= now
    }

    /// Exactly one open reminder with this title.
    public static func matchReminder(_ title: String, in reminders: [ReminderSnapshot]) -> ListMatchResult<ReminderSnapshot> {
        let wanted = SearchFolding.tokens(title).joined(separator: " ")
        guard !wanted.isEmpty else { return .none }
        let found = reminders.filter { !$0.isCompleted && SearchFolding.tokens($0.title).joined(separator: " ") == wanted }
        switch found.count {
        case 0: return .none
        case 1: return .one(found[0])
        default: return .several(found)
        }
    }
}

extension String {
    fileprivate var nonEmpty: String? { isEmpty ? nil : self }
}

extension VoiceToolReply {
    public static func eventNotFound(_ title: String) -> String {
        "not found: no event called \"\(title)\" at that time on the user's calendar. Nothing changed. Call read_calendar for that day and use the exact title and start it returns."
    }

    public static func eventAmbiguous(_ events: [CalendarEventSummary], calendar: Calendar) -> String {
        let times = events.prefix(4).map { "\"\($0.title)\" \(localText($0.start, hasTime: !$0.allDay, calendar: calendar))" }
        return "not changed: more than one event matches (\(times.joined(separator: "; "))). Ask the user which one."
    }

    public static let eventChangeInvalid = "failed: that change doesn't make sense (the end would be before the start, or nothing would change). Nothing changed. Ask the user what they want."

    public static func eventChanged(_ after: CalendarEventSummary, calendar: Calendar) -> String {
        let when = after.allDay
            ? "\(localText(after.start, hasTime: false, calendar: calendar)) (all day)"
            : "\(localText(after.start, hasTime: true, calendar: calendar))–\(localText(after.end, hasTime: true, calendar: calendar))"
        return "changed: \"\(after.title)\" is now \(when). Checked in Calendar."
    }

    public static let eventChangeTimePassed = "failed: the new time passed while the card was waiting. Nothing changed. Ask the user for a new time."
    public static let eventChangedElsewhere = "failed: the event changed or disappeared in Calendar since the card was shown. Nothing was changed by Doddy. Ask the user to check Calendar."
    public static let eventChangeUnconfirmed = "unknown: Calendar didn't confirm the change. Ask the user to check Calendar before trying again."
    public static let changeNothingNew = "not changed: it already looks like that. Nothing changed."
    public static let changeDeclined = "declined: the user chose not to make this change. Nothing changed."

    public static func reminderNotFound(_ title: String) -> String {
        "not found: no open reminder called \"\(title)\" in Reminders. Nothing changed. Ask the user for its exact name."
    }

    public static func reminderAmbiguous(_ reminders: [ReminderSnapshot]) -> String {
        let lists = reminders.prefix(4).map { "\"\($0.title)\" in \($0.listTitle)\($0.due.map { ", due \(ReminderText.due($0))" } ?? "")" }
        return "not changed: more than one open reminder matches (\(lists.joined(separator: "; "))). Ask the user which one."
    }

    public static func reminderChanged(_ title: String, due: ReminderDue?) -> String {
        "changed: the reminder \"\(title)\" is now due \(due.map(ReminderText.due) ?? "with no date"). Checked in Reminders."
    }

    public static func reminderCompleted(_ title: String) -> String {
        "completed: the reminder \"\(title)\" is marked done in Reminders. Checked."
    }

    public static let reminderChangedElsewhere = "failed: the reminder changed, was completed or disappeared in Reminders since the card was shown. Nothing was changed by Doddy. Ask the user to check Reminders."
    public static let reminderChangeUnconfirmed = "unknown: Reminders didn't confirm the change. Ask the user to check Reminders before trying again."
}

extension VoiceToolRequest {
    /// title + start (as read_calendar returned them), and at least one of new_start, new_end,
    /// new_title. New times follow the same strict rules as a new event: written out, local,
    /// not skipped or repeated by a clock change, not already passed.
    static func parseEventChange(_ args: Arguments, name: String, now: Date, calendar: Calendar) -> VoiceToolRequest {
        guard let title = args.text("title") else { return .invalid(name: name, reason: "missing title") }
        guard let startText = args.text("start") else { return .invalid(name: name, reason: "missing start (the event's current start, as read_calendar gave it)") }
        guard case .due(let current) = ReminderDueRules.wallClock(startText, calendar: calendar), let currentStart = current.date(in: calendar) else {
            return .invalid(name: name, reason: "start is not a date")
        }
        var newStart: Date?, newEnd: Date?
        if let text = args.text("new_start") {
            switch ReminderDueRules.check(text, now: now, calendar: calendar) {
            case .clarify(let clarification): return .needsClarification(name: name, clarification)
            case .due(let due):
                guard let date = due.date(in: calendar) else { return .invalid(name: name, reason: "new_start is not a date") }
                newStart = date
            }
        }
        if let text = args.text("new_end") {
            switch ReminderDueRules.wallClock(text, calendar: calendar) {
            case .clarify(let clarification): return .needsClarification(name: name, clarification)
            case .due(let due):
                guard due.hasTime, let date = due.date(in: calendar) else { return .invalid(name: name, reason: "new_end needs a time") }
                newEnd = date
            }
        }
        let newTitle = args.text("new_title")
        guard newStart != nil || newEnd != nil || newTitle != nil else {
            return .invalid(name: name, reason: "give new_start, new_end or new_title")
        }
        if let newTitle, newTitle.count > EventChange.maxTitleLength { return .invalid(name: name, reason: "new_title is too long") }
        return .changeCalendarEvent(EventChangeDraft(
            title: title, currentStart: currentStart, currentIsDayOnly: !current.hasTime,
            newStart: newStart, newEnd: newEnd, newTitle: newTitle))
    }

    /// title (exact), and new_due or done: true. Never both.
    static func parseReminderChange(_ args: Arguments, name: String, now: Date, calendar: Calendar) -> VoiceToolRequest {
        guard let title = args.text("title") else { return .invalid(name: name, reason: "missing title") }
        let done = args.flag("done")
        var newDue: ReminderDue?
        if let text = args.text("new_due") {
            switch ReminderDueRules.check(text, now: now, calendar: calendar) {
            case .clarify(let clarification): return .needsClarification(name: name, clarification)
            case .due(let due): newDue = due
            }
        }
        guard done != (newDue != nil) else { return .invalid(name: name, reason: "give either new_due or done: true") }
        return .changeReminder(ReminderChangeDraft(title: title, newDue: newDue, markDone: done))
    }
}
