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
    public static let setTimer = "set_timer"
    public static let openMap = "open_map"
    public static let runShortcut = "run_shortcut"
    public static let draftMessage = "draft_message"
}

/// The functions a user turns on in Settings, Connections. All start off, and each one may also
/// need an iOS permission of its own.
public enum VoiceConnection: String, CaseIterable, Sendable {
    case calendar, reminders, contacts, timers, maps, shortcuts, messages

    /// The name shown in Settings and in the agent's replies.
    public var title: String {
        switch self {
        case .calendar: "Calendar"
        case .reminders: "Reminders"
        case .contacts: "Contacts"
        case .timers: "Timers"
        case .maps: "Maps"
        case .shortcuts: "Shortcuts"
        case .messages: "Messages and email"
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
        case VoiceToolName.setTimer: .timers
        case VoiceToolName.openMap: .maps
        case VoiceToolName.runShortcut: .shortcuts
        case VoiceToolName.draftMessage: .messages
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

    /// Nil while the event is still ahead (an all-day event counts until its day ends). Checked
    /// when the card is shown and again when the user taps Add, as for reminders (ADR-128).
    public func passed(now: Date, calendar: Calendar) -> ReminderClarification? {
        let gregorian = ReminderDueRules.gregorian(calendar)
        let fields = gregorian.dateComponents([.year, .month, .day, .hour, .minute], from: start)
        guard let year = fields.year, let month = fields.month, let day = fields.day else { return nil }
        let due = ReminderDue(
            year: year, month: month, day: day,
            hour: allDay ? nil : fields.hour, minute: allDay ? nil : fields.minute,
            timeZoneID: gregorian.timeZone.identifier)
        return ReminderDueRules.passed(due, now: now)
    }
}

/// A reminder the agent proposed. Nothing is added until the user taps Add on the card.
/// `due` is local wall-clock time in a named zone, already checked by `ReminderDueRules`.
public struct ReminderDraft: Equatable, Sendable {
    public let title: String
    public let due: ReminderDue?
    public let notes: String?

    public init(title: String, due: ReminderDue?, notes: String?) {
        self.title = title
        self.due = due
        self.notes = notes
    }

    public var dueHasTime: Bool { due?.hasTime ?? false }
}

/// A countdown the agent proposed. Nothing starts until the user taps Start on the card.
public struct TimerDraft: Equatable, Sendable {
    public let seconds: Int
    public let label: String?
}

public enum MessageChannel: String, Equatable, Sendable {
    case text, email
}

/// A text or email the agent drafted. Doddy never sends it: the user sends it in Messages or Mail.
public struct MessageDraft: Equatable, Sendable {
    public let recipientName: String
    public let channel: MessageChannel
    public let body: String
}

/// What the agent is allowed to hear about an event: title and time only.
public struct CalendarEventSummary: Equatable, Sendable {
    /// This occurrence of the event on this iPhone (event identifier + start), for nudges.
    /// Never sent to the voice agent.
    public let id: String?
    public let title: String
    public let start: Date
    public let end: Date
    public let allDay: Bool

    public init(id: String? = nil, title: String, start: Date, end: Date, allDay: Bool) {
        self.id = id
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
    /// The request can't be shown as a card yet (unclear, past or skipped time). The agent gets a
    /// question to ask the user instead. `name` is the tool to call again (reminder or event).
    case needsClarification(name: String, ReminderClarification)
    /// Only names go back to the agent; details stay on the user's screen.
    case lookupContact(name: String)
    case setTimer(TimerDraft)
    case openMap(place: String)
    case runShortcut(name: String)
    case draftMessage(MessageDraft)
    /// Gmail, Google Drive, Notion or Todoist through the Doddy server (see OnlineAccounts).
    case cloudTool(CloudToolCall)
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
            return parseEvent(args, name: name, now: now, calendar: calendar)
        case VoiceToolName.createReminder:
            return parseReminder(args, name: name, now: now, calendar: calendar)
        case VoiceToolName.lookupContact:
            guard let person = args.text("name") else { return .invalid(name: name, reason: "missing name") }
            return .lookupContact(name: person)
        case VoiceToolName.setTimer:
            return parseTimer(args, name: name)
        case VoiceToolName.openMap:
            guard let place = args.text("place") else { return .invalid(name: name, reason: "missing place") }
            return .openMap(place: place)
        case VoiceToolName.runShortcut:
            guard let shortcut = args.text("name") else { return .invalid(name: name, reason: "missing name") }
            return .runShortcut(name: shortcut)
        case VoiceToolName.draftMessage:
            return parseMessage(args, name: name)
        default:
            return parseCloud(name: name, parametersJSON: parametersJSON) ?? .unsupported(name: name)
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
        guard let fromText = args.text("from"), case .due(let from) = ReminderDueRules.wallClock(fromText, calendar: calendar),
              let start = from.date(in: calendar) else {
            return .invalid(name: name, reason: "missing range or from")
        }
        let end: Date
        if let toText = args.text("to") {
            guard case .due(let to) = ReminderDueRules.wallClock(toText, calendar: calendar), let toDate = to.date(in: calendar) else {
                return .invalid(name: name, reason: "to is not a date")
            }
            end = toDate
        } else {
            end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        }
        guard end > start else { return .invalid(name: name, reason: "to must be after from") }
        guard end.timeIntervalSince(start) <= 31 * 86_400 else { return .invalid(name: name, reason: "range is longer than 31 days") }
        return .readCalendar(VoiceTimeRange(start: start, end: end))
    }

    /// Strict like reminders (ADR-127, ADR-128): start and end are local wall-clock times the agent
    /// wrote out, in the phone's zone, not a time the clocks skip or repeat, and not already passed.
    /// Anything else goes back to the agent as a question rather than being shifted.
    private static func parseEvent(_ args: Arguments, name: String, now: Date, calendar: Calendar) -> VoiceToolRequest {
        guard let title = args.text("title") else { return .invalid(name: name, reason: "missing title") }
        guard let startText = args.text("start") else { return .invalid(name: name, reason: "missing start") }
        let startDue: ReminderDue
        switch ReminderDueRules.wallClock(startText, calendar: calendar) {
        case .due(let checked): startDue = checked
        case .clarify(let clarification): return .needsClarification(name: name, clarification)
        }
        guard let start = startDue.date(in: calendar) else { return .invalid(name: name, reason: "missing start") }
        if args.flag("all_day") {
            let dayStart = calendar.startOfDay(for: start)
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            return proposeEvent(CalendarEventDraft(
                title: title, start: dayStart, end: dayEnd, allDay: true,
                location: args.text("location"), notes: args.text("notes")), name: name, now: now, calendar: calendar)
        }
        guard startDue.hasTime else { return .invalid(name: name, reason: "start needs a time unless all_day is true") }
        let end: Date
        if let endText = args.text("end") {
            let endDue: ReminderDue
            switch ReminderDueRules.wallClock(endText, calendar: calendar) {
            case .due(let checked): endDue = checked
            case .clarify(let clarification): return .needsClarification(name: name, clarification)
            }
            guard endDue.hasTime, let parsed = endDue.date(in: calendar), parsed > start else {
                return .invalid(name: name, reason: "end must be a time after start")
            }
            end = parsed
        } else {
            end = start.addingTimeInterval(3600)
        }
        return proposeEvent(CalendarEventDraft(
            title: title, start: start, end: end, allDay: false,
            location: args.text("location"), notes: args.text("notes")), name: name, now: now, calendar: calendar)
    }

    private static func proposeEvent(_ draft: CalendarEventDraft, name: String, now: Date, calendar: Calendar) -> VoiceToolRequest {
        if let late = draft.passed(now: now, calendar: calendar) { return .needsClarification(name: name, late) }
        return .createCalendarEvent(draft)
    }

    /// Strict (M4): the due is a day the agent wrote out, local time in the phone's zone, still
    /// ahead and not skipped or repeated by a clock change. Otherwise the agent is asked to clarify.
    private static func parseReminder(_ args: Arguments, name: String, now: Date, calendar: Calendar) -> VoiceToolRequest {
        guard let title = args.text("title")?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return .invalid(name: name, reason: "missing title")
        }
        var due: ReminderDue?
        if let dueText = args.text("due") {
            switch ReminderDueRules.check(dueText, now: now, calendar: calendar) {
            case .due(let checked): due = checked
            case .clarify(let clarification): return .needsClarification(name: name, clarification)
            }
        }
        return .createReminder(ReminderDraft(title: title, due: due, notes: args.text("notes")))
    }

    private static func parseTimer(_ args: Arguments, name: String) -> VoiceToolRequest {
        let minutes = args.number("minutes") ?? 0
        let seconds = args.number("seconds") ?? 0
        guard minutes >= 0, seconds >= 0 else { return .invalid(name: name, reason: "negative duration") }
        let total = Int((minutes * 60 + seconds).rounded())
        guard total >= 1 else { return .invalid(name: name, reason: "missing duration") }
        guard total <= 86_400 else { return .invalid(name: name, reason: "timer is longer than 24 hours") }
        return .setTimer(TimerDraft(seconds: total, label: args.text("label")))
    }

    private static func parseMessage(_ args: Arguments, name: String) -> VoiceToolRequest {
        guard let recipient = args.text("to") else { return .invalid(name: name, reason: "missing to") }
        guard let body = args.text("body") else { return .invalid(name: name, reason: "missing body") }
        guard let channel = MessageChannel(rawValue: (args.text("channel") ?? "text").lowercased()) else {
            return .invalid(name: name, reason: "channel must be text or email")
        }
        return .draftMessage(MessageDraft(recipientName: recipient, channel: channel, body: body))
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

    func number(_ key: String) -> Double? {
        values[key] as? Double
    }
}

/// Links that open other apps. The user always taps; Doddy never sends a message or places a call.
public enum OpenLinks {
    public static func map(place: String) -> URL? {
        URL(string: "https://maps.apple.com/?q=\(encode(place))")
    }

    public static func shortcut(name: String) -> URL? {
        URL(string: "shortcuts://run-shortcut?name=\(encode(name))")
    }

    /// Digits and a leading plus sign only. Nil when nothing dialable is left.
    public static func call(number: String) -> URL? {
        let digits = dialable(number)
        guard !digits.isEmpty else { return nil }
        return URL(string: "tel:\(digits)")
    }

    public static func text(number: String, body: String) -> URL? {
        let digits = dialable(number)
        guard !digits.isEmpty else { return nil }
        return URL(string: "sms:\(digits)&body=\(encode(body))")
    }

    public static func email(address: String, body: String) -> URL? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
        return URL(string: "mailto:\(trimmed)?body=\(encode(body))")
    }

    private static func dialable(_ number: String) -> String {
        String(number.enumerated().compactMap { index, character in
            character.isNumber || (index == 0 && character == "+") ? character : nil
        })
    }

    /// Encodes everything except letters and digits, so "+", "&" and spaces survive the trip.
    private static func encode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? text
    }
}

/// Text returned to the agent. Written for the model: it states only what the app verified.
/// Result prefixes ("added", "declined", "failed", "unknown", "saved", "opened") are what the
/// agent's prompt tells it to look for, so they must not change without changing the prompt.
public enum VoiceToolReply {
    public static let declined = "declined: the user chose not to save this note. Nothing was saved."
    public static let declinedEvent = "declined: the user chose not to add this event. Nothing was added."
    public static let declinedReminder = "declined: the user chose not to add this reminder. Nothing was added."
    public static let declinedTimer = "declined: the user chose not to start this timer. Nothing was set."
    public static let declinedMap = "declined: the user chose not to open the map. Nothing was opened."
    public static let declinedShortcut = "declined: the user chose not to run the shortcut. Nothing was run."
    public static let declinedMessage = "declined: the user chose not to open the draft. Nothing was sent."

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

    /// Used when a function is off or its iOS permission is not granted.
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

    /// The timer is scheduled and confirmed. The user hears it ring at `endsAt`.
    public static func timerAdded(_ draft: TimerDraft, endsAt: Date, calendar: Calendar) -> String {
        let what = draft.label.map { "\"\($0)\", " } ?? ""
        return "added: timer \(what)\(durationText(draft.seconds)), rings at \(localText(endsAt, hasTime: true, calendar: calendar))."
    }

    /// Maps opened on the user's tap. Nothing else is claimed.
    public static func mapOpened(_ place: String) -> String {
        "opened: Apple Maps opened for \"\(place)\"."
    }

    /// Shortcuts is asked to run; Doddy cannot see whether the shortcut finished.
    public static func shortcutRequested(_ name: String) -> String {
        "opened: asked Shortcuts to run \"\(name)\". Doddy can't see whether it finished."
    }

    /// The draft opened in Messages or Mail. Doddy did not send it.
    public static func messageOpened(_ draft: MessageDraft, recipient: String) -> String {
        let app = draft.channel == .text ? "Messages" : "Mail"
        return "opened: \(app) opened with the draft for \(recipient). Nothing was sent by Doddy; the user sends it there."
    }

    /// The contact has no phone number or email for the channel the agent asked for.
    public static func noAddress(_ recipient: String, channel: MessageChannel) -> String {
        let what = channel == .text ? "phone number" : "email address"
        return "failed: \(recipient) has no \(what) in Contacts. Nothing was opened."
    }

    /// The app could not open the other app.
    public static func notOpened(_ reason: String) -> String {
        "failed: \(reason) Nothing was opened."
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

    private static func durationText(_ seconds: Int) -> String {
        if seconds >= 60, seconds % 60 == 0 {
            let minutes = seconds / 60
            return "\(minutes) minute\(minutes == 1 ? "" : "s")"
        }
        return "\(seconds) second\(seconds == 1 ? "" : "s")"
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
