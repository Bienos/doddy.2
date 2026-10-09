import Foundation

/// Client tools the voice agent may call. Names must match the tools configured on the
/// ElevenLabs agent (see docs/implementation/V1_VOICE_STATUS.md).
public enum VoiceToolName {
    public static let searchMemories = "search_memories"
    public static let saveMemory = "save_memory"
    public static let readCalendar = "read_calendar"
    public static let createCalendarEvent = "create_calendar_event"
    public static let createReminder = "create_reminder"
    public static let lookupContact = "lookup_contact"
}

/// The phone connections the user turns on in Settings, Connections. All are off until the
/// user turns them on, and each also needs the matching iOS permission.
public enum VoiceConnection: String, CaseIterable, Sendable {
    case calendar, reminders, contacts

    /// The name shown in Settings and in the agent's replies.
    public var title: String {
        switch self {
        case .calendar: "Calendar"
        case .reminders: "Reminders"
        case .contacts: "Contacts"
        }
    }

    /// Per-device preference key for @AppStorage.
    public var preferenceKey: String { "voiceConnection.\(rawValue)" }

    /// The connection that serves a client tool. Memory tools are not listed: they are always on.
    public static func serving(_ toolName: String) -> VoiceConnection? {
        switch toolName {
        case VoiceToolName.readCalendar, VoiceToolName.createCalendarEvent: .calendar
        case VoiceToolName.createReminder: .reminders
        case VoiceToolName.lookupContact: .contacts
        default: nil
        }
    }
}

extension VoiceConnection: Identifiable {
    public var id: String { rawValue }
}

/// A window of time the agent asked about, resolved to absolute dates.
public struct VoiceTimeRange: Equatable, Sendable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }
}

/// An event the agent proposed. Nothing is added until the user taps Add on the card.
public struct CalendarEventDraft: Equatable, Sendable {
    public let title: String
    public let start: Date
    public let end: Date
    public let allDay: Bool
    public let location: String?
    public let notes: String?
}

/// A reminder the agent proposed. Nothing is added until the user taps Add on the card.
public struct ReminderDraft: Equatable, Sendable {
    public let title: String
    public let due: Date?
    public let dueHasTime: Bool
    public let notes: String?
}

/// What the agent is allowed to hear about an event: title and time only.
public struct CalendarEventSummary: Equatable, Sendable {
    public let title: String
    public let start: Date
    public let end: Date
    public let allDay: Bool

    public init(title: String, start: Date, end: Date, allDay: Bool) {
        self.title = title
        self.start = start
        self.end = end
        self.allDay = allDay
    }
}

/// A parsed tool call. The model only proposes; the app decides what actually happens.
public enum VoiceToolRequest: Equatable, Sendable {
    case searchMemories(query: String)
    /// Never saved directly: the app shows it and waits for the user's confirmation.
    case saveMemory(text: String)
    case readCalendar(VoiceTimeRange)
    /// Shown to the user for confirmation before anything is added.
    case createCalendarEvent(CalendarEventDraft)
    case createReminder(ReminderDraft)
    /// Only names go back to the agent; details stay on the user's screen.
    case lookupContact(name: String)
    case unsupported(name: String)
    case invalid(name: String, reason: String)

    public static func parse(name: String, parametersJSON: Data, now: Date = Date(), calendar: Calendar = .current) -> VoiceToolRequest {
        let args = Arguments(parametersJSON)
        switch name {
        case VoiceToolName.searchMemories:
            guard let query = args.text("query") else { return .invalid(name: name, reason: "missing query") }
            return .searchMemories(query: query)
        case VoiceToolName.saveMemory:
            guard let text = args.text("text") else { return .invalid(name: name, reason: "missing text") }
            return .saveMemory(text: text)
        case VoiceToolName.readCalendar:
            return parseRead(args, name: name, now: now, calendar: calendar)
        case VoiceToolName.createCalendarEvent:
            return parseEvent(args, name: name, calendar: calendar)
        case VoiceToolName.createReminder:
            return parseReminder(args, name: name, calendar: calendar)
        case VoiceToolName.lookupContact:
            guard let person = args.text("name") else { return .invalid(name: name, reason: "missing name") }
            return .lookupContact(name: person)
        default:
            return .unsupported(name: name)
        }
    }

    private static func parseRead(_ args: Arguments, name: String, now: Date, calendar: Calendar) -> VoiceToolRequest {
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today) ?? today }

        if let range = args.text("range") {
            switch range.lowercased() {
            case "today": return .readCalendar(VoiceTimeRange(start: day(0), end: day(1)))
            case "tomorrow": return .readCalendar(VoiceTimeRange(start: day(1), end: day(2)))
            case "week": return .readCalendar(VoiceTimeRange(start: day(0), end: day(7)))
            default: return .invalid(name: name, reason: "range must be today, tomorrow or week")
            }
        }
        guard let fromText = args.text("from"), let from = VoiceLocalDate.parse(fromText, calendar: calendar) else {
            return .invalid(name: name, reason: "missing range or from")
        }
        let end: Date
        if let toText = args.text("to") {
            guard let to = VoiceLocalDate.parse(toText, calendar: calendar) else { return .invalid(name: name, reason: "to is not a date") }
            end = to.date
        } else {
            end = calendar.date(byAdding: .day, value: 1, to: from.date) ?? from.date
        }
        guard end > from.date else { return .invalid(name: name, reason: "to must be after from") }
        guard end.timeIntervalSince(from.date) <= 31 * 86_400 else { return .invalid(name: name, reason: "range is longer than 31 days") }
        return .readCalendar(VoiceTimeRange(start: from.date, end: end))
    }

    private static func parseEvent(_ args: Arguments, name: String, calendar: Calendar) -> VoiceToolRequest {
        guard let title = args.text("title") else { return .invalid(name: name, reason: "missing title") }
        guard let startText = args.text("start"), let start = VoiceLocalDate.parse(startText, calendar: calendar) else {
            return .invalid(name: name, reason: "missing or unreadable start")
        }
        if args.flag("all_day") {
            let dayStart = calendar.startOfDay(for: start.date)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            return .createCalendarEvent(CalendarEventDraft(
                title: title, start: dayStart, end: dayEnd, allDay: true,
                location: args.text("location"), notes: args.text("notes")))
        }
        guard start.hasTime else { return .invalid(name: name, reason: "start needs a time unless all_day is true") }
        let end: Date
        if let endText = args.text("end") {
            guard let parsed = VoiceLocalDate.parse(endText, calendar: calendar), parsed.hasTime, parsed.date > start.date else {
                return .invalid(name: name, reason: "end must be a time after start")
            }
            end = parsed.date
        } else {
            end = start.date.addingTimeInterval(3600)
        }
        return .createCalendarEvent(CalendarEventDraft(
            title: title, start: start.date, end: end, allDay: false,
            location: args.text("location"), notes: args.text("notes")))
    }

    private static func parseReminder(_ args: Arguments, name: String, calendar: Calendar) -> VoiceToolRequest {
        guard let title = args.text("title") else { return .invalid(name: name, reason: "missing title") }
        var due: Date?
        var dueHasTime = false
        if let dueText = args.text("due") {
            guard let parsed = VoiceLocalDate.parse(dueText, calendar: calendar) else {
                return .invalid(name: name, reason: "due is not a date")
            }
            due = parsed.date
            dueHasTime = parsed.hasTime
        }
        return .createReminder(ReminderDraft(title: title, due: due, dueHasTime: dueHasTime, notes: args.text("notes")))
    }
}

/// Tool arguments as the model sent them. Missing or blank values read as nil.
private struct Arguments {
    private let values: [String: Any]

    init(_ data: Data) {
        values = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    func text(_ key: String) -> String? {
        guard let value = values[key] as? String, !value.allSatisfy(\.isWhitespace) else { return nil }
        return value
    }

    func flag(_ key: String) -> Bool {
        values[key] as? Bool ?? false
    }
}

/// A date the agent wrote in local time: "YYYY-MM-DDTHH:MM" or "YYYY-MM-DD".
struct VoiceLocalDate: Equatable {
    let date: Date
    let hasTime: Bool

    /// Returns nil for anything that is not exactly one of those forms or that does not exist
    /// (for example February 31). Calendar would otherwise roll it over silently.
    static func parse(_ text: String, calendar: Calendar) -> VoiceLocalDate? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let halves = trimmed.split(separator: "T", maxSplits: 1).map(String.init)
        guard let dayPart = halves.first else { return nil }
        let ymd = dayPart.split(separator: "-").compactMap { Int($0) }
        guard ymd.count == 3 else { return nil }

        var components = DateComponents()
        components.year = ymd[0]
        components.month = ymd[1]
        components.day = ymd[2]

        var hm: [Int] = []
        if halves.count == 2 {
            hm = halves[1].split(separator: ":").compactMap { Int($0) }
            guard hm.count >= 2 else { return nil }
            components.hour = hm[0]
            components.minute = hm[1]
        }
        guard let date = calendar.date(from: components) else { return nil }

        let back = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        guard back.year == ymd[0], back.month == ymd[1], back.day == ymd[2] else { return nil }
        if halves.count == 2 {
            guard back.hour == hm[0], back.minute == hm[1] else { return nil }
        }
        return VoiceLocalDate(date: date, hasTime: halves.count == 2)
    }
}

/// Text returned to the agent. Written for the model: it states only what the app verified.
/// Result prefixes ("added", "declined", "failed", "unknown", "saved") are what the agent's
/// prompt tells it to look for, so they must not change without changing the prompt.
public enum VoiceToolReply {
    public static let declined = "declined: the user chose not to save this note. Nothing was saved."
    public static let declinedEvent = "declined: the user chose not to add this event. Nothing was added."
    public static let declinedReminder = "declined: the user chose not to add this reminder. Nothing was added."

    public static func search(_ outcome: RecallOutcome, limit: Int = 5) -> String {
        guard case .matches(let candidates) = outcome, !candidates.isEmpty else {
            return "No saved note matched. Tell the user you couldn't find it in their saved memories. Do not guess."
        }
        let shown = candidates.prefix(limit)
        var lines = ["Found \(candidates.count) saved note\(candidates.count == 1 ? "" : "s") (exact text, newest wording):"]
        for candidate in shown {
            lines.append("- \"\(candidate.record.currentText)\" (saved \(timestamp(candidate.record.capturedAt)))")
        }
        if candidates.count > shown.count {
            lines.append("…and \(candidates.count - shown.count) more. Ask the user to narrow it down if needed.")
        }
        return lines.joined(separator: "\n")
    }

    public static func saved(_ record: MemoryRecord) -> String {
        "saved: \"\(record.currentText)\" (saved \(timestamp(record.capturedAt)))."
    }

    public static func failed(_ reason: String) -> String {
        "failed: \(reason) Nothing was saved."
    }

    public static func unsupported(_ name: String) -> String {
        "The app does not support the tool \"\(name)\". Tell the user this isn't available yet."
    }

    /// Used when a connection is off or its iOS permission is not granted.
    public static func notConnected(_ connection: VoiceConnection) -> String {
        "\(connection.title) isn't connected. Tell the user they can connect it in Settings, Connections."
    }

    public static func calendarEvents(_ events: [CalendarEventSummary], range: VoiceTimeRange, calendar: Calendar, limit: Int = 20) -> String {
        let window = "from \(localText(range.start, hasTime: false, calendar: calendar)) to \(localText(range.end, hasTime: false, calendar: calendar))"
        guard !events.isEmpty else {
            return "No calendar events \(window). Say so; do not guess."
        }
        var lines = ["Found \(events.count) calendar event\(events.count == 1 ? "" : "s") \(window) (exact titles and times):"]
        for event in events.prefix(limit) {
            let when = event.allDay
                ? "\(localText(event.start, hasTime: false, calendar: calendar)) (all day)"
                : "\(localText(event.start, hasTime: true, calendar: calendar))–\(localText(event.end, hasTime: true, calendar: calendar))"
            lines.append("- \"\(event.title)\" \(when)")
        }
        if events.count > limit {
            lines.append("…and \(events.count - limit) more.")
        }
        return lines.joined(separator: "\n")
    }

    public static func eventAdded(_ draft: CalendarEventDraft, calendar: Calendar) -> String {
        if draft.allDay {
            return "added: \"\(draft.title)\" on \(localText(draft.start, hasTime: false, calendar: calendar)) (all day)."
        }
        return "added: \"\(draft.title)\" on \(localText(draft.start, hasTime: true, calendar: calendar)) to \(localText(draft.end, hasTime: true, calendar: calendar))."
    }

    public static func reminderAdded(_ draft: ReminderDraft, calendar: Calendar) -> String {
        guard let due = draft.due else { return "added: reminder \"\(draft.title)\" with no due time." }
        return "added: reminder \"\(draft.title)\" due \(localText(due, hasTime: draft.dueHasTime, calendar: calendar))."
    }

    /// The app could not add the item.
    public static func notAdded(_ reason: String) -> String {
        "failed: \(reason) Nothing was added."
    }

    /// The app saved the item but could not read it back. The user must check before retrying.
    public static let addUnconfirmed = "unknown: the app could not confirm it was added. It may not have gone through; ask the user to check before trying again."

    /// Names only. Details stay on the user's screen.
    public static func contactMatches(_ names: [String], query: String) -> String {
        guard !names.isEmpty else {
            return "No contact matched \"\(query)\". Tell the user you couldn't find them in Contacts. Do not guess."
        }
        let list = names.joined(separator: ", ")
        return "Found \(names.count) contact\(names.count == 1 ? "" : "s") matching \"\(query)\": \(list). Their details are on the user's screen. Say you've put them on the screen; never read out or guess a number or address."
    }

    private static func timestamp(_ date: Date?) -> String {
        guard let date else { return "date unavailable" }
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    static func localText(_ date: Date, hasTime: Bool, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = hasTime ? "yyyy-MM-dd HH:mm" : "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
