import Foundation

// Voice note reminders (ADR-198): the agent proposes "remind me about this note" at a time or at a
// place; the app finds the note, shows a card, and sets nothing until the user taps Set reminder.
// The agent never names a memory by id: it quotes the note's text from search_memories or
// save_memory, and the app matches that quote against the user's saved notes.

/// When a voice note reminder should fire, as the agent asked for it.
public enum NoteReminderVoiceTarget: Equatable, Sendable {
    /// A checked local moment (same rules as Apple Reminders: written-out day and time, still ahead,
    /// not skipped or repeated by a clock change).
    case time(Date, timeZoneID: String)
    /// Looked up in Apple Maps on the phone; the user picks the result on the card.
    case place(query: String, onArrival: Bool)
}

public struct NoteReminderVoiceDraft: Equatable, Sendable {
    /// The note's text as the agent quoted it.
    public let noteText: String
    public let target: NoteReminderVoiceTarget

    public init(noteText: String, target: NoteReminderVoiceTarget) {
        self.noteText = noteText
        self.target = target
    }
}

extension VoiceToolRequest {
    static func parseNoteReminder(_ args: Arguments, name: String, now: Date, calendar: Calendar) -> VoiceToolRequest {
        guard let note = args.text("note")?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty else {
            return .invalid(name: name, reason: "missing note")
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
                return .remindAboutNote(NoteReminderVoiceDraft(
                    noteText: note, target: .time(date, timeZoneID: due.timeZoneID ?? calendar.timeZone.identifier)))
            }
        case (nil, let placeText?):
            let query = placeText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return .invalid(name: name, reason: "missing place") }
            return .remindAboutNote(NoteReminderVoiceDraft(
                noteText: note, target: .place(query: query, onArrival: !args.flag("when_leaving"))))
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
            "at \(ReminderFormat.dateTime(fireAt, timeZoneID: zone, locale: Locale(identifier: "en_GB"))) (\(ReminderFormat.zoneName(zone)))"
        case .place(let place):
            "\(ReminderFormat.place(place).lowercased()) (within \(place.radiusMeters) m, each time until the user marks it Done)"
        }
    }
}
