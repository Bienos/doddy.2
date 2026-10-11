import Foundation

// Undo in "What Doddy did" (ADR-268). For a day after Doddy added or changed an event or a
// reminder, its row offers Undo. Undo only ever reverses what Doddy itself did:
//  - an event or reminder Doddy added is removed, and only if it still looks exactly as Doddy
//    left it (same title and time; a reminder still open and carrying Doddy's marker);
//  - an event Doddy moved or renamed goes back to how it was, only if it still looks as Doddy left it;
//  - a reminder Doddy re-timed gets its old due back, and one Doddy ticked off is opened again.
// Anything changed since, by the user or another app, is left alone and the row says so. The user
// confirms on a sheet that names exactly what will happen. Afterwards Calendar or Reminders is read
// back; "Undone" is shown only when the read-back agrees, otherwise "not sure". Nothing here runs
// from the voice agent: Undo is a button the user taps.

/// What Doddy needs to put things back. Kept with the activity entry on this iPhone only.
public enum ActivityUndo: Codable, Equatable, Sendable {
    /// `eventID` is the event's identifier on this iPhone, read back right after Doddy saved it.
    case addedEvent(eventID: String, event: CalendarEventSummary)
    /// Found again by Doddy's marker key, among open reminders only.
    case addedReminder(key: String, title: String, due: ReminderDue?)
    case changedEvent(EventChangePlan)
    /// `oldDue` is the due before Doddy's change. `markedDone` is true when Doddy ticked it off
    /// (then the due was not changed).
    case changedReminder(id: String, title: String, oldDue: ReminderDue?, newDue: ReminderDue?, markedDone: Bool)
    /// List changes by voice (ADR-276): the exact items as Doddy left them, and the list's name
    /// at the time (for the sheet only; the list is found by its id).
    case listAdded(listID: UUID, list: String, items: [ListItem])
    case listTicked(listID: UUID, list: String, items: [ListItem])
    case listRemoved(listID: UUID, list: String, items: [ListItem])
    /// A note saved by voice (ADR-277): deleted only if nothing about it changed since.
    case savedNote(id: UUID, text: String)

    /// Undo is offered for this long after the change.
    public static let window: TimeInterval = 24 * 3_600

    public var app: ActivityApp {
        switch self {
        case .addedEvent, .changedEvent: .calendar
        case .addedReminder, .changedReminder: .reminders
        case .listAdded, .listTicked, .listRemoved, .savedNote: .memories
        }
    }

    /// Where it is checked, for the row's note: "Calendar", "Reminders" or "the list".
    public var placeName: String {
        switch self {
        case .addedEvent, .changedEvent: "Calendar"
        case .addedReminder, .changedReminder: "Reminders"
        case .listAdded, .listTicked, .listRemoved: "the list"
        case .savedNote: "your notes"
        }
    }

    /// The switch in Settings, Connections that Undo needs, like the change it reverses. Nil for
    /// lists: they are Doddy's own, need no switch and aren't stopped by Pause all.
    public var connection: VoiceConnection? {
        switch self {
        case .addedEvent, .changedEvent: .calendar
        case .addedReminder, .changedReminder: .reminders
        case .listAdded, .listTicked, .listRemoved, .savedNote: nil
        }
    }

    /// Why Undo can't run now, checked at the tap before anything is read or written. Nil when it can.
    public func blocked(pauseAll: Bool, connectionOn: Bool) -> String? {
        guard let connection else { return nil }
        if pauseAll { return "Connections are paused in Settings." }
        if !connectionOn { return "\(connection.title) is off in Settings, Connections." }
        return nil
    }

    /// The question on the confirmation sheet, in the iPhone's language (Polish or English).
    public func question(_ language: NotificationLanguage = .english) -> String {
        switch (self, language) {
        case (.addedEvent(_, let event), .english): "Remove “\(event.title)” from Calendar?"
        case (.addedEvent(_, let event), .polish): "Usunąć „\(event.title)” z Kalendarza?"
        case (.addedReminder(_, let title, _), .english): "Remove “\(title)” from Reminders?"
        case (.addedReminder(_, let title, _), .polish): "Usunąć „\(title)” z Przypomnień?"
        case (.changedEvent(let plan), .english): "Put “\(plan.before.title)” back?"
        case (.changedEvent(let plan), .polish): "Przywrócić „\(plan.before.title)”?"
        case (.changedReminder(_, let title, _, _, let markedDone), .english):
            markedDone ? "Mark “\(title)” not done?" : "Put back the due of “\(title)”?"
        case (.changedReminder(_, let title, _, _, let markedDone), .polish):
            markedDone ? "Oznaczyć „\(title)” jako niezrobione?" : "Przywrócić poprzedni termin „\(title)”?"
        case (.listAdded(_, let list, let items), .english): "Remove \(Self.names(items, .english)) from “\(list)”?"
        case (.listAdded(_, let list, let items), .polish): "Usunąć \(Self.names(items, .polish)) z listy „\(list)”?"
        case (.listTicked(_, let list, let items), .english): "Untick \(Self.names(items, .english)) on “\(list)”?"
        case (.listTicked(_, let list, let items), .polish): "Odznaczyć \(Self.names(items, .polish)) na liście „\(list)”?"
        case (.listRemoved(_, let list, let items), .english): "Put \(Self.names(items, .english)) back on “\(list)”?"
        case (.listRemoved(_, let list, let items), .polish): "Przywrócić \(Self.names(items, .polish)) na listę „\(list)”?"
        case (.savedNote(_, let text), .english): "Delete the note “\(Self.short(text))”?"
        case (.savedNote(_, let text), .polish): "Usunąć notatkę „\(Self.short(text))”?"
        }
    }

    /// A note's words, cut for the sheet's question.
    static func short(_ text: String) -> String {
        text.count <= 80 ? text : String(text.prefix(79)) + "…"
    }

    /// "“milk”, “eggs” and 2 more", in the sheet's language.
    static func names(_ items: [ListItem], _ language: NotificationLanguage) -> String {
        let (open, close) = language == .polish ? ("„", "”") : ("“", "”")
        let shown = items.prefix(3).map { "\(open)\($0.text)\(close)" }.joined(separator: ", ")
        let more = items.count - min(items.count, 3)
        guard more > 0 else { return shown }
        return language == .polish ? "\(shown) i \(more) więcej" : "\(shown) and \(more) more"
    }

    /// Exactly what will happen, shown under the question.
    public func explanation(calendar: Calendar, language: NotificationLanguage = .english) -> String {
        let polish = language == .polish
        switch self {
        case .addedEvent(_, let event):
            let when = Self.when(event, calendar: calendar, language: language)
            return polish
                ? "Doddy dodał to wydarzenie na \(when). Usunięte zostanie tylko to wydarzenie i tylko wtedy, gdy od tamtej pory się nie zmieniło."
                : "Doddy added this event for \(when). Only this event is removed, and only if it hasn't changed since."
        case .addedReminder(_, _, let due):
            let due = Self.due(due, language: language)
            return polish
                ? "Doddy dodał to przypomnienie (termin: \(due)). Usunięte zostanie tylko to przypomnienie i tylko wtedy, gdy jest nadal otwarte i od tamtej pory się nie zmieniło."
                : "Doddy added this reminder (due: \(due)). Only this reminder is removed, and only if it is still open and hasn't changed since."
        case .changedEvent(let plan):
            let back = Self.when(plan.before, calendar: calendar, language: language)
            let now = Self.when(plan.after, calendar: calendar, language: language)
            let renamed = plan.before.title != plan.after.title
            if polish {
                let rename = renamed ? ", a jego nazwa wróci z „\(plan.after.title)”" : ""
                return "Wróci na \(back) z \(now)\(rename). Tylko jeśli od tamtej pory się nie zmieniło."
            }
            let rename = renamed ? " and its name goes back from “\(plan.after.title)”" : ""
            return "It moves back to \(back) from \(now)\(rename). Only if it hasn't changed since."
        case .changedReminder(_, _, let oldDue, let newDue, let markedDone):
            if markedDone {
                return polish
                    ? "Doddy oznaczył je jako zrobione. Znowu będzie otwarte, jeśli nic innego go w międzyczasie nie zmieniło."
                    : "Doddy marked it done. It becomes an open reminder again, only if nothing else changed it since."
            }
            let old = Self.due(oldDue, language: language), new = Self.due(newDue, language: language)
            if polish, oldDue == nil {
                return "Termin zostanie usunięty, jak było przed zmianą (teraz: \(new)). Tylko jeśli od tamtej pory się nie zmienił."
            }
            return polish
                ? "Termin wróci na \(old) z \(new). Tylko jeśli od tamtej pory się nie zmienił."
                : "Due goes back to \(old) from \(new). Only if it hasn't changed since."
        case .listAdded:
            return polish
                ? "Doddy dodał je głosem. Usunięte zostaną tylko te, które nadal są na liście i nie są odhaczone."
                : "Doddy added these by voice. Only the ones still on the list and not ticked are removed."
        case .listTicked:
            return polish
                ? "Doddy odhaczył je głosem. Odznaczone zostaną tylko te, które nadal są odhaczone."
                : "Doddy ticked these by voice. Only the ones still ticked are unticked."
        case .listRemoved:
            return polish
                ? "Doddy usunął je głosem. Wrócą dokładnie takie, jakie były, jeśli lista nadal istnieje."
                : "Doddy removed these by voice. They go back exactly as they were, if the list still exists."
        case .savedNote:
            return polish
                ? "Doddy zapisał tę notatkę głosem. Zostanie usunięta tylko wtedy, gdy nic się w niej nie zmieniło: te same słowa, bez poprawek, zdjęcia, nagrania ani przypomnienia."
                : "Doddy saved this note by voice. It is deleted only if nothing about it changed since: the same words, and no edits, photo, recording or reminder."
        }
    }

    /// The confirming button.
    public func buttonTitle(_ language: NotificationLanguage = .english) -> String {
        let polish = language == .polish
        switch self {
        case .addedEvent, .addedReminder: return polish ? "Usuń" : "Remove"
        case .changedEvent: return polish ? "Przywróć" : "Put back"
        case .changedReminder(_, _, _, _, let markedDone):
            if markedDone { return polish ? "Oznacz jako niezrobione" : "Mark not done" }
            return polish ? "Przywróć" : "Put back"
        case .listAdded: return polish ? "Usuń" : "Remove"
        case .listTicked: return polish ? "Odznacz" : "Untick"
        case .listRemoved: return polish ? "Przywróć" : "Put back"
        case .savedNote: return polish ? "Usuń" : "Delete"
        }
    }

    /// A due as on the sheet: English as Reminders writes it; Polish with the same numeric day
    /// and time the rest of the sheet uses.
    static func due(_ due: ReminderDue?, language: NotificationLanguage) -> String {
        guard language == .polish else { return ReminderText.due(due) }
        guard let due else { return "bez terminu" }
        return due.localText.replacingOccurrences(of: "T", with: " ")
    }

    /// Undo for a reminder Doddy just added: only when Doddy wrote it and read it back, never
    /// when it was already there (then it is the user's) or Doddy isn't sure.
    public static func addedReminder(_ outcome: ReminderOutcome, draft: ReminderDraft) -> ActivityUndo? {
        guard case .added = outcome else { return nil }
        return .addedReminder(key: ReminderWrite(draft).key, title: draft.title, due: draft.due)
    }

    /// The plan that moves an event back. The event is found by its current occurrence (Doddy's
    /// "after"), which must still look exactly like that; it then becomes Doddy's "before".
    public static func reversed(_ plan: EventChangePlan) -> EventChangePlan {
        // The same backwards change as Undo on the voice screen (ADR-258 on the default line).
        EventChange.reversed(plan)
    }

    /// An event Doddy added still looks exactly as Doddy left it (title, times, all-day).
    public static func unchanged(_ found: CalendarEventSummary, since added: CalendarEventSummary) -> Bool {
        found.title == added.title && found.start == added.start && found.end == added.end && found.allDay == added.allDay
    }

    /// A reminder Doddy added is still open, still carries Doddy's marker, and has the same title and due.
    public static func unchanged(_ found: ReminderSnapshot, key: String, title: String, due: ReminderDue?) -> Bool {
        !found.isCompleted && ReminderIdempotency.key(fromMarker: found.markerURL) == key
            && found.title == title && EventChange.sameDue(found.due, due)
    }

    /// The one open reminder carrying Doddy's marker for `key`. Nil when there is none or several.
    public static func addedReminder(key: String, in reminders: [ReminderSnapshot]) -> ReminderSnapshot? {
        let found = reminders.filter { !$0.isCompleted && ReminderIdempotency.key(fromMarker: $0.markerURL) == key }
        return found.count == 1 ? found[0] : nil
    }

    /// A reminder Doddy changed still looks exactly as Doddy left it.
    public static func unchangedSinceChange(_ found: ReminderSnapshot, title: String, newDue: ReminderDue?, oldDue: ReminderDue?, markedDone: Bool) -> Bool {
        guard found.title == title else { return false }
        if markedDone { return found.isCompleted && EventChange.sameDue(found.due, oldDue) }
        return !found.isCompleted && EventChange.sameDue(found.due, newDue)
    }

    private static func when(_ event: CalendarEventSummary, calendar: Calendar, language: NotificationLanguage = .english) -> String {
        event.allDay
            ? "\(VoiceToolReply.localText(event.start, hasTime: false, calendar: calendar)) (\(language == .polish ? "cały dzień" : "all day"))"
            : VoiceToolReply.localText(event.start, hasTime: true, calendar: calendar)
    }
}

// MARK: Lists (ADR-276)

extension ActivityUndo {
    /// The list a list undo works on.
    public var listID: UUID? {
        switch self {
        case .listAdded(let id, _, _), .listTicked(let id, _, _), .listRemoved(let id, _, _): id
        default: nil
        }
    }

    /// The items Undo would act on now, given the list as it is: added items still open with the
    /// same words, ticked items still ticked, removed items not back on the list. Empty means it
    /// all changed since (or the list is gone), so nothing is written. Nil for a non-list undo.
    public func listItemsToUndo(in current: DoddyList?) -> [ListItem]? {
        switch self {
        case .listAdded(_, _, let items):
            let open = Dictionary((current?.open ?? []).map { ($0.id, $0.text) }, uniquingKeysWith: { a, _ in a })
            return items.filter { open[$0.id] == $0.text }
        case .listTicked(_, _, let items):
            let done = Dictionary((current?.done ?? []).map { ($0.id, $0.text) }, uniquingKeysWith: { a, _ in a })
            return items.filter { done[$0.id] == $0.text }
        case .listRemoved(_, _, let items):
            guard let current else { return [] }
            let there = Set(current.items.map(\.id))
            return items.filter { !there.contains($0.id) }
        default:
            return nil
        }
    }

    /// Read back after the write: the items Undo acted on are gone, open again, or back.
    public func listUndoChecks(_ acted: [ListItem], after list: DoddyList?) -> Bool {
        let ids = Set(acted.map(\.id))
        switch self {
        case .listAdded:
            return !(list?.items ?? []).contains { ids.contains($0.id) }
        case .listTicked:
            return ids.isSubset(of: Set((list?.open ?? []).map(\.id)))
        case .listRemoved:
            return ids.isSubset(of: Set((list?.items ?? []).map(\.id)))
        default:
            return false
        }
    }
}

// MARK: Notes saved by voice (ADR-277)

extension ActivityUndo {
    /// A note Doddy saved is still exactly as saved: the same words, never corrected or edited,
    /// and nothing added to it since (photo, recording or reminder). Anything else is the user's
    /// now, so Undo leaves it alone.
    public static func noteUnchanged(
        _ record: MemoryRecord, savedText: String, corrections: Int, hasPhoto: Bool, hasRecording: Bool, hasReminder: Bool
    ) -> Bool {
        record.rawText == savedText && record.currentText == savedText && !record.userEdited
            && corrections == 0 && !hasPhoto && !hasRecording && !hasReminder
    }
}

/// What happened when the user tapped Undo.
public enum UndoResult: Equatable, Sendable {
    /// Reversed, and the read-back agrees.
    case undone
    /// It no longer looks as Doddy left it. Nothing was written.
    case leftAlone
    /// Nothing was written (no permission, the switch is off, Pause all, or the write failed and a
    /// fresh look shows it unchanged). The user can try again.
    case notDone(String)
    /// Written, or maybe written, but the read-back didn't agree. Not offered again.
    case notSure
}

/// Recorded on the entry after the user tapped Undo.
public enum UndoState: Codable, Equatable, Sendable {
    case undone(Date)
    case leftAlone(Date)
    case notDone(Date)
    case notSure(Date)

    public var at: Date {
        switch self {
        case .undone(let date), .leftAlone(let date), .notDone(let date), .notSure(let date): date
        }
    }
}

extension CalendarEventSummary {
    /// One id per occurrence: repeating events share one item identifier, so the start time is
    /// added. The iPhone's `DeviceConnections` builds every id with this, so they always agree.
    public static func occurrenceID(itemID: String, start: Date) -> String {
        "\(itemID)@\(Int(start.timeIntervalSince1970))"
    }

    /// The item identifier inside an occurrence id. Nil when the id isn't one.
    public static func itemID(fromOccurrence id: String) -> String? {
        guard let at = id.lastIndex(of: "@"), at != id.startIndex,
              Int(id[id.index(after: at)...]) != nil else { return nil }
        return String(id[..<at])
    }
}

extension ActivityEntry {
    /// The row offers Undo: Doddy did it and checked, it can be put back, the user hasn't
    /// already undone it (or Doddy isn't unsure about an earlier try), and it was within a day.
    public func canUndo(now: Date) -> Bool {
        guard outcome == .done, undo != nil else { return false }
        switch undoState {
        case nil, .notDone?: break
        case .undone?, .leftAlone?, .notSure?: return false
        }
        let age = now.timeIntervalSince(at)
        return age >= 0 && age < ActivityUndo.window
    }

    /// "Calendar · Done", or "Calendar · Undone" once the user has undone it.
    public var statusText: String {
        if case .undone? = undoState { return "\(app.title) · Undone" }
        return "\(app.title) · \(outcome.text)"
    }
}

extension ActivityLog {
    /// The entry after the user tapped Undo. "Undone" only when the read-back agreed.
    public static func undid(_ entry: ActivityEntry, result: UndoResult, at date: Date) -> ActivityEntry {
        var updated = entry
        let where_ = entry.undo?.placeName ?? entry.app.title
        switch result {
        case .undone:
            updated.undoState = .undone(date)
            updated.note = "You undid this. Checked in \(where_)."
        case .leftAlone:
            updated.undoState = .leftAlone(date)
            updated.note = "Not undone: it changed in \(where_) since Doddy did this, so Doddy left it alone."
        case .notDone(let reason):
            updated.undoState = .notDone(date)
            updated.note = "Not undone: \(reason) Nothing changed."
        case .notSure:
            updated.undoState = .notSure(date)
            updated.note = "Doddy couldn't confirm the undo. Check \(where_) before trying again."
        }
        return updated
    }
}

// MARK: "Undo that" by voice (ADR-271)

extension VoiceToolName {
    public static let undoLast = "undo_last"
}

extension ActivityUndo {
    /// The newest change from this conversation that can still be undone. Never one from an
    /// earlier conversation: "undo that" means what was just done.
    public static func latest(in entries: [ActivityEntry], since start: Date, now: Date) -> ActivityEntry? {
        // "Undo that" is for Calendar and Reminders only; list changes have their own receipt
        // and What Doddy did (ADR-276), and the agent is told so.
        entries.filter { $0.at >= start && $0.canUndo(now: now) && $0.undo?.connection != nil }.max { $0.at < $1.at }
    }
}

extension VoiceToolReply {
    public static let nothingToUndo = "nothing to undo: Doddy hasn't added or changed anything in Calendar or Reminders in this conversation that can still be undone. Nothing changed. Older changes can be undone in Settings, What Doddy did."
    public static let undoDeclined = "declined: the user chose to keep it. Nothing changed."

    /// What the agent hears after the user tapped the undo card. "undone" only after the read-back.
    public static func undo(_ result: UndoResult, _ undo: ActivityUndo) -> String {
        let place = undo.placeName
        switch result {
        case .undone:
            switch undo {
            case .addedEvent(_, let event): return "undone: \"\(event.title)\" was removed from Calendar. Checked."
            case .addedReminder(_, let title, _): return "undone: \"\(title)\" was removed from Reminders. Checked."
            case .changedEvent(let plan): return "undone: \"\(plan.before.title)\" is back as it was. Checked in Calendar."
            case .changedReminder(_, let title, _, _, let markedDone):
                return markedDone
                    ? "undone: \"\(title)\" is open again in Reminders. Checked."
                    : "undone: \"\(title)\" has its old due back. Checked in Reminders."
            case .listAdded(_, let list, _): return "undone: the items were removed from \"\(list)\". Checked."
            case .listTicked(_, let list, _): return "undone: the items are unticked on \"\(list)\". Checked."
            case .listRemoved(_, let list, _): return "undone: the items are back on \"\(list)\". Checked."
            case .savedNote: return "undone: the note was deleted. Checked."
            }
        case .leftAlone:
            return "not undone: it changed in \(place) since Doddy did it, so Doddy left it alone. Nothing changed."
        case .notDone(let reason):
            return "failed: not undone. \(reason) Nothing changed."
        case .notSure:
            return "unknown: Doddy couldn't confirm the undo. Ask the user to check \(place) before trying again."
        }
    }
}

// MARK: The two Undo buttons agree (ADR-268 merge)

extension ActivityUndo {
    /// The same change as an on-screen Undo receipt (ADR-258 on the default line): the same event
    /// plan, or the same reminder.
    public func isSameChange(event plan: EventChangePlan?, reminderID: String?) -> Bool {
        switch self {
        case .changedEvent(let mine): return plan == mine
        case .changedReminder(let id, _, _, _, _): return reminderID == id
        case .addedEvent, .addedReminder, .listAdded, .listTicked, .listRemoved, .savedNote: return false
        }
    }
}

extension ActivityLog {
    /// After Undo on the voice screen put a change back: the newest row still offering Undo for
    /// that same change, marked undone, so What Doddy did never offers to undo it again.
    public static func undoneOnScreen(_ entries: [ActivityEntry], event plan: EventChangePlan?, reminderID: String?, now: Date) -> ActivityEntry? {
        let row = entries
            .filter { $0.canUndo(now: now) && $0.undo?.isSameChange(event: plan, reminderID: reminderID) == true }
            .max { $0.at < $1.at }
        return row.map { undid($0, result: .undone, at: now) }
    }
}

