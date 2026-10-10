import Foundation

// Home Screen and Lock Screen widgets (ADR-233). The widget extension can't open the notes
// database, so the app writes this small snapshot to a file shared only with its own widgets
// (an App Group), and asks WidgetKit to redraw. It holds only what the widgets show: up to 3
// pinned notes and the next few time reminders, with their words only if the user allows it.

public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public static let formatVersion = 1
    public static let maxPinned = 3
    public static let maxUpcoming = 5
    /// Note words are cut to this for the widget only; the note itself is never changed.
    public static let maxTextLength = 140

    public struct Note: Codable, Equatable, Sendable, Identifiable {
        public let id: UUID
        /// nil when the user turned off note words in widgets.
        public let text: String?
        public let savedAt: Date?
    }

    public struct Reminder: Codable, Equatable, Sendable {
        public let memoryID: UUID
        public let fireAt: Date
        /// nil when the user turned off note words in widgets.
        public let text: String?
    }

    public let version: Int
    public let generatedAt: Date
    public let showsNoteWords: Bool
    /// Pinned notes, newest pin first, as the Memories list shows them.
    public let pinned: [Note]
    /// Time reminders still to come when the snapshot was made, soonest first.
    public let upcoming: [Reminder]
    /// Place reminders have no time, so they are only counted.
    public let placeReminders: Int

    public init(version: Int = WidgetSnapshot.formatVersion, generatedAt: Date, showsNoteWords: Bool,
                pinned: [Note], upcoming: [Reminder], placeReminders: Int) {
        self.version = version
        self.generatedAt = generatedAt
        self.showsNoteWords = showsNoteWords
        self.pinned = pinned
        self.upcoming = upcoming
        self.placeReminders = placeReminders
    }

    /// Built from the stored notes, the pin preference and the note reminders. Sample notes and
    /// pins of deleted notes are left out; nothing else about the notes is copied.
    public static func make(
        memories: [MemoryRecord], pins: PinnedNotes, reminders: [MemoryReminder],
        showsNoteWords: Bool, now: Date
    ) -> WidgetSnapshot {
        let byID = Dictionary(memories.filter { $0.source != .sampleFixture }.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let words = { (record: MemoryRecord) in showsNoteWords ? clip(record.currentText) : nil }
        // Most recently pinned first, as on the Memories list (`PinnedNotes` stores oldest first).
        let pinned = pins.ids.reversed().compactMap { byID[$0] }.prefix(maxPinned).map {
            Note(id: $0.id, text: words($0), savedAt: $0.capturedAt)
        }
        let upcoming = reminders
            .compactMap { reminder -> Reminder? in
                guard let fireAt = reminder.fireAt, fireAt > now, let record = byID[reminder.memoryID] else { return nil }
                return Reminder(memoryID: record.id, fireAt: fireAt, text: words(record))
            }
            .sorted { ($0.fireAt, $0.memoryID.uuidString) < ($1.fireAt, $1.memoryID.uuidString) }
            .prefix(maxUpcoming)
        let places = reminders.filter { $0.fireAt == nil && byID[$0.memoryID] != nil }.count
        return WidgetSnapshot(generatedAt: now, showsNoteWords: showsNoteWords, pinned: Array(pinned),
                              upcoming: Array(upcoming), placeReminders: places)
    }

    /// The next reminder still to come at `now` (the widget moves on by itself as times pass).
    public func next(after now: Date) -> Reminder? {
        upcoming.first { $0.fireAt > now }
    }

    /// When the widget should redraw: at each reminder time still to come.
    public func redrawTimes(after now: Date) -> [Date] {
        upcoming.map(\.fireAt).filter { $0 > now }
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    /// nil for unreadable data or another format version (the widget then asks to open Doddy).
    public static func decode(_ data: Data) -> WidgetSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        guard let snapshot = try? decoder.decode(WidgetSnapshot.self, from: data), snapshot.version == formatVersion else { return nil }
        return snapshot
    }

    static func clip(_ text: String) -> String {
        let flat = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " · ")
        return flat.count > maxTextLength ? String(flat.prefix(maxTextLength - 1)) + "…" : flat
    }
}

/// `doddy://note/<id>`: opens one saved note (widgets). Navigation only; a missing note opens
/// nothing. Separate from `DeepLink`, whose places have no id.
public enum NoteLink {
    public static func url(for id: UUID) -> URL {
        URL(string: "\(DeepLink.scheme)://note/\(id.uuidString.lowercased())")!
    }

    public static func id(from url: URL) -> UUID? {
        guard url.scheme?.lowercased() == DeepLink.scheme, url.host?.lowercased() == "note" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 1 else { return nil }
        return UUID(uuidString: parts[0])
    }
}
