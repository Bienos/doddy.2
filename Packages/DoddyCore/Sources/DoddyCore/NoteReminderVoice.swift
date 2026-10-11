import Foundation

// Voice note reminders (ADR-198): the agent proposes "remind me about this note" at a time or at a
// place; the app finds the note, shows a card, and sets nothing until the user taps Set reminder.
// The agent never names a memory by id: it quotes the note's text from search_memories or
// save_memory, and the app matches that quote against the user's saved notes. A list (ADR-256)
// is named instead, exactly as under "The user's lists"; the app matches it like the list tools.

/// When a voice note reminder should fire, as the agent asked for it.
public enum NoteReminderVoiceTarget: Equatable, Sendable {
    /// A checked local moment (same rules as Apple Reminders: written-out day and time, still ahead,
    /// not skipped or repeated by a clock change).
    case time(Date, timeZoneID: String)
    /// Looked up in Apple Maps on the phone; the user picks the result on the card.
    case place(query: String, onArrival: Bool)
}

public struct NoteReminderVoiceDraft: Equatable, Sendable {
    /// The note's text as the agent quoted it, or the list's name when `isList`.
    public let noteText: String
    /// The reminder is about a list, named by `noteText` (ADR-256).
    public let isList: Bool
    public let target: NoteReminderVoiceTarget
    /// A time reminder that repeats (ADR-211): the weekday, day and clock time come from the time.
    public let repeats: ReminderRepeat?

    public init(noteText: String, target: NoteReminderVoiceTarget, repeats: ReminderRepeat? = nil, isList: Bool = false) {
        self.noteText = noteText
        self.isList = isList
        self.target = target
        self.repeats = repeats
    }
}

extension VoiceToolRequest {
    static func parseNoteReminder(_ args: Arguments, name: String, now: Date, calendar: Calendar) -> VoiceToolRequest {
        let noteArg = args.text("note")?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyText
        let listArg = args.text("list")?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyText
        guard noteArg == nil || listArg == nil else { return .invalid(name: name, reason: "give note or list, not both") }
        guard let note = noteArg ?? listArg else { return .invalid(name: name, reason: "missing note or list") }
        let isList = listArg != nil
        var repeats: ReminderRepeat?
        if let raw = args.text("repeat")?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !raw.isEmpty, raw != "never" {
            guard let rule = ReminderRepeat(rawValue: raw) else {
                return .invalid(name: name, reason: "repeat must be daily, weekdays, weekly or monthly")
            }
            guard args.text("place") == nil else { return .invalid(name: name, reason: "a place reminder can't repeat") }
            repeats = rule
        }
        switch (args.text("due"), args.text("place")) {
        case (nil, nil):
            return .invalid(name: name, reason: "give either due or place")
        case (.some, .some):
            return .invalid(name: name, reason: "give due or place, not both")
        case (let dueText?, nil):
            switch ReminderDueRules.check(dueText, now: now, calendar: calendar) {
            case .clarify(let clarification):
                return .needsClarification(name: name, clarification)
            case .due(let due):
                guard due.hour != nil, let date = due.date else {
                    return .needsClarification(name: name, ReminderClarification(
                        kind: .unreadable, problem: "a note reminder needs a time of day, not only a day",
                        question: "what time"))
                }
                // The user's own words for when, if the agent passed them (ADR-253).
                if let said = args.text("said_time"), let question = SaidTime.check(said, due: due, now: now, timeRequired: true) {
                    return .needsClarification(name: name, question)
                }
                let zone = due.timeZoneID ?? calendar.timeZone.identifier
                if let repeats, !ReminderSchedule.allows(repeats, picked: date, timeZoneID: zone) {
                    return .needsClarification(name: name, ReminderClarification(
                        kind: .unreadable, problem: "a monthly reminder can be on days 1 to 28 only",
                        question: "which day of the month, from 1 to 28"))
                }
                return .remindAboutNote(NoteReminderVoiceDraft(
                    noteText: note, target: .time(date, timeZoneID: zone), repeats: repeats, isList: isList))
            }
        case (nil, let placeText?):
            let query = placeText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return .invalid(name: name, reason: "missing place") }
            return .remindAboutNote(NoteReminderVoiceDraft(
                noteText: note, target: .place(query: query, onArrival: !args.flag("when_leaving")), isList: isList))
        }
    }
}

/// Finds the saved note the agent quoted. Exact text first; then the same text ignoring case,
/// surrounding quotes and repeated spaces. Several matches: the most recently saved. No match: nil,
/// never a "closest" note.
public enum NoteQuoteMatch {
    public static func find(_ quote: String, in records: [MemoryRecord]) -> MemoryRecord? {
        let newestFirst = records.sorted { ($0.capturedAt ?? .distantPast) > ($1.capturedAt ?? .distantPast) }
        if let exact = newestFirst.first(where: { $0.currentText == quote }) { return exact }
        let wanted = normalized(quote)
        guard !wanted.isEmpty else { return nil }
        return newestFirst.first { normalized($0.currentText) == wanted }
    }

    static func normalized(_ text: String) -> String {
        let quotes = CharacterSet(charactersIn: "\"'“”„‘’«»")
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines.union(quotes))
        return trimmed.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }
}

extension VoiceToolReply {
    public static let declinedNoteReminder = "declined: the user chose not to set this reminder. Nothing was set."

    public static func noteNotFound() -> String {
        "failed: no saved note has exactly that text. Call search_memories, then pass one note's text exactly as the result quotes it. Nothing was set."
    }

    public static func placeNotFound(_ query: String) -> String {
        "failed: Apple Maps found no place for \"\(query)\". Ask the user for a more specific place, e.g. with a street or town. Nothing was set."
    }

    /// `summary` is `ReminderFormat.summary` of the stored reminder.
    public static func noteReminderSet(_ reminder: MemoryReminder, note: String) -> String {
        "added: a reminder about \"\(note)\": \(phrase(reminder)). It is a notification on this iPhone."
    }

    public static func noteReminderInDoddyOnly(_ reminder: MemoryReminder, note: String) -> String {
        "added: a reminder about \"\(note)\": \(phrase(reminder)), kept in Doddy only. Notifications are off for Doddy, so the iPhone won't alert; it shows on Doddy's Home when due. Tell the user this."
    }

    public static func noteReminderFailed(_ reason: String) -> String {
        let reason = reason.hasSuffix("Nothing was set.") || reason.hasSuffix("Nothing was scheduled, and your note is unchanged.")
            ? reason : reason + " Nothing was set."
        return "failed: \(reason)"
    }

    private static func phrase(_ reminder: MemoryReminder) -> String {
        switch reminder.trigger {
        case .time(let fireAt, let zone):
            if reminder.repeats != nil {
                "\(ReminderFormat.short(reminder)) (\(ReminderFormat.zoneName(zone))), first on "
                    + "\(ReminderFormat.dateTime(fireAt, timeZoneID: zone, locale: Locale(identifier: "en_GB"))), until the user stops it on the note"
            } else {
                "at \(ReminderFormat.dateTime(fireAt, timeZoneID: zone, locale: Locale(identifier: "en_GB"))) (\(ReminderFormat.zoneName(zone)))"
            }
        case .place(let place):
            "\(ReminderFormat.place(place).lowercased()) (within \(place.radiusMeters) m, each time until the user marks it Done)"
        }
    }
}

extension String {
    fileprivate var nonEmptyText: String? { isEmpty ? nil : self }
}
