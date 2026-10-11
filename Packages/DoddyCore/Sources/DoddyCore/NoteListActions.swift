import Foundation

// Notes and lists in the action status model (ADR-302, extends ADR-300 and ADR-301). Notes and
// lists live in Doddy's own database on this iPhone, which is the truth about them. So an entry
// Doddy wasn't sure about (cut off mid-way) is settled by Doddy itself: it looks in its own
// notes and lists and the entry becomes confirmed or "didn't happen", never guessed. Lists were
// already safe to ask again: adding an item that is there says so, and ticking or removing twice
// changes nothing. Plain Swift for the Linux tests; the app calls `LocalCheck` only once its
// notes and lists have loaded.

/// What Doddy needs to look for one note or list change in its own database. Kept with the
/// entry in the activity file on this iPhone; the words are the same ones the entry shows.
public enum ActivityCheck: Codable, Equatable, Sendable {
    /// `key` is `NoteIdempotency.key` of the note's words.
    case note(key: String)
    case listAdd(list: String, items: [String])
    case listTick(list: String, items: [String])
    case listRemove(list: String, items: [String])
    case listCreate(name: String)

    /// "your notes" or "the list “Shopping”".
    var place: String {
        switch self {
        case .note: "your notes"
        case .listAdd(let list, _), .listTick(let list, _), .listRemove(let list, _): "the list “\(list)”"
        case .listCreate: "your lists"
        }
    }
}

public enum NoteIdempotency {
    /// Same words (ignoring case, accents, punctuation, spacing): the same note (DuplicateNote's rule).
    public static func key(_ text: String) -> String { "n1-" + ReminderIdempotency.fnv(DuplicateNote.key(text)) }

    /// After an unconfirmed try: a note with the same words saved since that try (a minute's
    /// slack), so it isn't saved twice. Without an unconfirmed try nothing is looked for: the
    /// same words saved on purpose twice are two notes (DuplicateNote only warns).
    public static func savedSince(_ since: Date, text: String, in notes: [MemoryRecord]) -> MemoryRecord? {
        let key = key(text)
        let earliest = since.addingTimeInterval(-60)
        return notes
            .filter { $0.source != .sampleFixture && ($0.capturedAt ?? .distantPast) >= earliest }
            .sorted { ($0.capturedAt ?? .distantPast) > ($1.capturedAt ?? .distantPast) }
            .first { Self.key($0.currentText) == key || Self.key($0.rawText) == key }
    }
}

public enum ListOpIdempotency {
    /// Same kind of change, same list ("the shopping list" is "Shopping", as ListMatch reads it),
    /// same items in any order: the same change.
    public static func key(_ kind: String, list: String, items: [String]) -> String {
        let words = items.map(ListMatch.key).sorted().joined(separator: "\u{1E}")
        return "l1-" + ReminderIdempotency.fnv([kind, ListMatch.nameKey(list), words].joined(separator: "\u{1F}"))
    }
}

public enum LocalCheck {
    /// Settles an unsure note or list entry from Doddy's own notes and lists. Anything else, or
    /// an entry that isn't unsure, comes back unchanged. Only call with the database loaded:
    /// an empty list here means "nothing there", not "not read yet".
    public static func settled(_ entry: ActivityEntry, notes: [MemoryRecord], lists: [DoddyList], at date: Date) -> ActivityEntry {
        guard entry.status == .unknown, let check = entry.check, let found = found(check, since: entry.at, notes: notes, lists: lists) else {
            return entry
        }
        var updated = entry
        updated.checkedAt = date
        if found {
            updated.move(to: .done, at: date, note: "Found in \(check.place) when Doddy checked.")
        } else {
            updated.move(to: .notDone, at: date, note: "Not in \(check.place) when Doddy checked, so it didn't happen. You can ask again.")
        }
        return updated
    }

    public static func settledAll(_ entries: [ActivityEntry], notes: [MemoryRecord], lists: [DoddyList], at date: Date) -> [ActivityEntry] {
        entries.map { settled($0, notes: notes, lists: lists, at: date) }
    }

    /// Nil when Doddy can't tell from its own data (a list that is gone, for a remove).
    static func found(_ check: ActivityCheck, since: Date, notes: [MemoryRecord], lists: [DoddyList]) -> Bool? {
        // The list as a voice request finds it; two that match count as none, as there.
        func list(_ name: String) -> DoddyList? {
            if case .one(let found) = ListMatch.list(named: name, in: lists) { return found }
            return nil
        }
        func on(_ phrase: String, _ items: [ListItem]) -> Bool { ListMatch.item(phrase, in: items) != .none }
        switch check {
        case .note(let key):
            let earliest = since.addingTimeInterval(-60)
            return notes.contains { note in
                note.source != .sampleFixture && (note.capturedAt ?? .distantPast) >= earliest
                    && (NoteIdempotency.key(note.currentText) == key || NoteIdempotency.key(note.rawText) == key)
            }
        case .listAdd(let name, let items):
            guard let found = list(name) else { return false }
            return items.allSatisfy { on($0, found.items) }
        case .listTick(let name, let items):
            guard let found = list(name) else { return false }
            return items.allSatisfy { on($0, found.items.filter(\.isDone)) && !on($0, found.open) }
        case .listRemove(let name, let items):
            guard let found = list(name) else { return nil }
            return items.allSatisfy { !on($0, found.items) }
        case .listCreate(let name):
            return list(name) != nil
        }
    }
}

extension VoiceToolReply {
    /// After an unconfirmed try, the same note was found already saved: nothing new was written.
    public static func noteAlreadySaved(_ record: MemoryRecord) -> String {
        "saved: \"\(record.currentText)\" was already saved from the earlier try (saved \(timestamp(record.capturedAt))), so Doddy did not save it a second time."
    }
}

extension ActivityReceipt {
    /// A note as the database returned it after saving.
    public init(note: MemoryRecord, readAt: Date) {
        self.init(app: .memories, externalID: note.id.uuidString, lines: ["“\(note.currentText)”"], readAt: readAt)
    }

    /// A list change as the database returned it.
    public init(list: String, listID: UUID, lines: [String], readAt: Date) {
        self.init(app: .memories, externalID: listID.uuidString, lines: ["List: \(list)"] + lines, readAt: readAt)
    }
}
