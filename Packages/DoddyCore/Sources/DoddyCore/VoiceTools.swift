import Foundation

/// Client tools the voice agent may call. Names must match the tools configured on the
/// ElevenLabs agent (see docs/implementation/V1_VOICE_STATUS.md and V4A_CONNECTIONS_STATUS.md).
public enum VoiceToolName {
    public static let searchMemories = "search_memories"
    public static let saveMemory = "save_memory"
    public static let readCalendar = "read_calendar"
    public static let createCalendarEvent = "create_calendar_event"
    public static let createReminder = "create_reminder"
    public static let lookupContact = "lookup_contact"
}

/// A parsed tool call. The model only proposes; the app decides what actually happens.
public enum VoiceToolRequest: Equatable, Sendable {
    case searchMemories(query: String)
    /// Never saved directly: the app shows it and waits for the user's confirmation.
    case saveMemory(text: String)
    /// Read-only; runs automatically when Calendar is connected.
    case readCalendar(from: Date, to: Date)
    /// Shown on a confirmation card; nothing is written until the user taps Add.
    case createCalendarEvent(EventDraft)
    /// Shown on a confirmation card; nothing is written until the user taps Add.
    case createReminder(ReminderDraft)
    /// Read-only; the match is shown on screen, details never go to the agent.
    case lookupContact(name: String)
    case unsupported(name: String)
    case invalid(name: String, reason: String)

    public static func parse(
        name: String, parametersJSON: Data, now: Date = Date(), timeZone: TimeZone = .current
    ) -> VoiceToolRequest {
        let parameters = (try? JSONSerialization.jsonObject(with: parametersJSON)) as? [String: Any] ?? [:]
        func nonEmpty(_ key: String) -> String? {
            guard let value = parameters[key] as? String, !value.allSatisfy(\.isWhitespace) else { return nil }
            return value
        }
        func date(_ key: String) -> Date?? {
            guard let raw = nonEmpty(key) else { return .some(nil) }
            guard let parsed = ToolDateParser.parse(raw, timeZone: timeZone) else { return .none }
            return .some(parsed)
        }
        func isDateOnly(_ key: String) -> Bool {
            nonEmpty(key).map(ToolDateParser.isDateOnly) ?? false
        }
        switch name {
        case VoiceToolName.searchMemories:
            guard let query = nonEmpty("query") else { return .invalid(name: name, reason: "missing query") }
            return .searchMemories(query: query)
        case VoiceToolName.saveMemory:
            guard let text = nonEmpty("text") else { return .invalid(name: name, reason: "missing text") }
            return .saveMemory(text: text)
        case VoiceToolName.readCalendar:
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            if let range = nonEmpty("range")?.lowercased() {
                let today = calendar.startOfDay(for: now)
                switch range {
                case "today":
                    return .readCalendar(from: today, to: calendar.date(byAdding: .day, value: 1, to: today) ?? today)
                case "tomorrow":
                    let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
                    return .readCalendar(from: tomorrow, to: calendar.date(byAdding: .day, value: 1, to: tomorrow) ?? tomorrow)
                case "week":
                    return .readCalendar(from: today, to: calendar.date(byAdding: .day, value: 7, to: today) ?? today)
                default:
                    return .invalid(name: name, reason: "unknown range \"\(range)\"")
                }
            }
            guard case .some(.some(let from)) = date("from") else { return .invalid(name: name, reason: "missing or unreadable from") }
            guard case .some(let toValue) = date("to") else { return .invalid(name: name, reason: "unreadable to") }
            let to = toValue ?? calendar.date(byAdding: .day, value: 1, to: from) ?? from
            guard to > from else { return .invalid(name: name, reason: "to must be after from") }
            return .readCalendar(from: from, to: to)
        case VoiceToolName.createCalendarEvent:
            guard let title = nonEmpty("title") else { return .invalid(name: name, reason: "missing title") }
            guard case .some(.some(let start)) = date("start") else { return .invalid(name: name, reason: "missing or unreadable start") }
            guard case .some(let end) = date("end") else { return .invalid(name: name, reason: "unreadable end") }
            let allDay = parameters["all_day"] as? Bool ?? isDateOnly("start")
            do {
                return .createCalendarEvent(try EventDraft(
                    title: title, start: start, end: end, isAllDay: allDay, location: nonEmpty("location"), notes: nonEmpty("notes")))
            } catch {
                return .invalid(name: name, reason: Self.describe(error))
            }
        case VoiceToolName.createReminder:
            guard let title = nonEmpty("title") else { return .invalid(name: name, reason: "missing title") }
            guard case .some(let due) = date("due") else { return .invalid(name: name, reason: "unreadable due") }
            do {
                return .createReminder(try ReminderDraft(
                    title: title, due: due, dueIncludesTime: !isDateOnly("due"), notes: nonEmpty("notes")))
            } catch {
                return .invalid(name: name, reason: Self.describe(error))
            }
        case VoiceToolName.lookupContact:
            guard let contactName = nonEmpty("name") else { return .invalid(name: name, reason: "missing name") }
            return .lookupContact(name: contactName)
        default:
            return .unsupported(name: name)
        }
    }

    private static func describe(_ error: ConnectionDraftError) -> String {
        switch error {
        case .emptyTitle: "empty title"
        case .endBeforeStart: "end is before start"
        }
    }
}

/// Dates as the agent sends them: ISO 8601 with an offset, or a local date-time / date
/// interpreted in the user's time zone.
public enum ToolDateParser {
    public static func parse(_ raw: String, timeZone: TimeZone) -> Date? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: text) { return date }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: text) { return date }
        for pattern in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.dateFormat = pattern
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

    /// "2026-10-10": a day without a time.
    public static func isDateOnly(_ raw: String) -> Bool {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count == 10 && !text.contains("T") && !text.contains(":")
    }

    /// Stable, unambiguous rendering for the agent (local time in the user's zone).
    public static func render(_ date: Date, timeZone: TimeZone, dateOnly: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = dateOnly ? "EEE yyyy-MM-dd" : "EEE yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

/// Text returned to the agent. Written for the model: it states only what the app verified.
public enum VoiceToolReply {
    public static let declined = "declined: the user chose not to save this note. Nothing was saved."

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

    // MARK: Connections

    public static func notConnected(_ kind: ConnectionKind) -> String {
        let name = displayName(kind)
        return "\(name) isn't connected in Doddy, so nothing was read or changed. Tell the user they can connect \(name) in Settings → Connections. Do not guess."
    }

    public static func calendar(_ events: [CalendarEvent], from: Date, to: Date, timeZone: TimeZone, limit: Int = 12) -> String {
        let range = "\(ToolDateParser.render(from, timeZone: timeZone)) to \(ToolDateParser.render(to, timeZone: timeZone))"
        guard !events.isEmpty else {
            return "No calendar events between \(range). Tell the user their calendar is clear for that time; do not invent events."
        }
        var lines = ["Found \(events.count) calendar event\(events.count == 1 ? "" : "s") between \(range) (times in the user's time zone):"]
        for event in events.sorted(by: { $0.start < $1.start }).prefix(limit) {
            let when = event.isAllDay
                ? "\(ToolDateParser.render(event.start, timeZone: timeZone, dateOnly: true)) (all day)"
                : "\(ToolDateParser.render(event.start, timeZone: timeZone))–\(ToolDateParser.render(event.end, timeZone: timeZone).suffix(5))"
            var line = "- \(when): \"\(event.title)\" [\(event.calendarTitle)]"
            if let location = event.location { line += " at \(location)" }
            lines.append(line)
        }
        if events.count > limit { lines.append("…and \(events.count - limit) more.") }
        return lines.joined(separator: "\n")
    }

    public static func eventCreated(_ event: CalendarEvent, timeZone: TimeZone) -> String {
        let when = event.isAllDay
            ? "\(ToolDateParser.render(event.start, timeZone: timeZone, dateOnly: true)) (all day)"
            : "\(ToolDateParser.render(event.start, timeZone: timeZone))–\(ToolDateParser.render(event.end, timeZone: timeZone).suffix(5))"
        return "added: \"\(event.title)\" on \(when) in the calendar \"\(event.calendarTitle)\" (verified by reading it back)."
    }

    public static func reminderCreated(_ item: ReminderItem, timeZone: TimeZone) -> String {
        let due = item.due.map { " due \(ToolDateParser.render($0, timeZone: timeZone, dateOnly: !item.dueIncludesTime))" } ?? " with no due date"
        return "added: reminder \"\(item.title)\"\(due) in the list \"\(item.listTitle)\" (verified by reading it back)."
    }

    public static func actionDeclined(_ kind: ToolKind) -> String {
        switch kind {
        case .createCalendarEvent: "declined: the user chose not to add this event. Nothing was added."
        case .createReminder: "declined: the user chose not to add this reminder. Nothing was added."
        case .scheduleEventNudge: "declined: the user chose not to schedule this nudge. Nothing was scheduled."
        }
    }

    public static func actionUnverified(_ kind: ToolKind) -> String {
        "unknown: the request was sent to iOS but the result could not be confirmed. Tell the user to check the app before retrying; do not say it was added."
    }

    public static func actionFailed(_ reason: String) -> String {
        "failed: \(reason) Nothing was added."
    }

    public static func readFailed(_ reason: String) -> String {
        "failed: \(reason) Nothing was read. Tell the user it didn't work; do not guess."
    }

    public static let busy = "failed: another confirmation is already on the user's screen. Ask the user to answer it first. Nothing was added."

    /// Names only. Phone numbers and e-mail addresses are shown on the user's screen and are
    /// never sent to the agent.
    public static func contacts(_ matches: [ContactMatch], query: String) -> String {
        guard !matches.isEmpty else {
            return "No contact matched \"\(query)\". Tell the user you couldn't find that name in their contacts; do not guess."
        }
        var lines = ["Found \(matches.count) contact\(matches.count == 1 ? "" : "s") matching \"\(query)\". The details are shown on the user's screen; you do not have the numbers or addresses:"]
        for match in matches.prefix(5) {
            lines.append("- \(match.displayName) (\(match.phoneNumbers.count) phone number\(match.phoneNumbers.count == 1 ? "" : "s"), \(match.emailAddresses.count) e-mail address\(match.emailAddresses.count == 1 ? "" : "es"))")
        }
        return lines.joined(separator: "\n")
    }

    public static func displayName(_ kind: ConnectionKind) -> String {
        switch kind {
        case .calendar: "Calendar"
        case .reminders: "Reminders"
        case .contacts: "Contacts"
        }
    }

    private static func timestamp(_ date: Date?) -> String {
        guard let date else { return "date unavailable" }
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        return formatter.string(from: date)
    }
}
