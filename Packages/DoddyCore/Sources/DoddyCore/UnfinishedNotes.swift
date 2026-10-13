import Foundation

// Unfinished notes (OP-042, ADR-362). While the user writes a note on the capture screen, what
// they have typed is kept in a small protected file on this iPhone, so it survives Doddy being
// closed, iOS ending it, or a crash. It is a draft, never a note: it isn't searched, sent to the
// voice agent, exported or backed up, and it becomes a note only when the user taps Save. Saving
// or discarding it removes it. Plain Swift for the Linux tests; UnfinishedNoteStore uses it.

/// One capture screen's unsaved words.
public struct UnfinishedNote: Codable, Equatable, Identifiable, Sendable {
    /// One per capture screen, so two screens never write over each other's draft.
    public let id: UUID
    public var text: String
    public var category: MemoryCategory
    /// The words came from a "Save to Doddy" shortcut (saved as shared content if kept as is).
    public var isSharedText: Bool
    /// A photo or recording was attached on the screen. Those aren't kept with the draft (their
    /// words are, once written into the text), so the resumed screen says to add them again.
    public var hadPhoto: Bool
    public var hadRecording: Bool
    public let startedAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), text: String, category: MemoryCategory = .other, isSharedText: Bool = false,
                hadPhoto: Bool = false, hadRecording: Bool = false, startedAt: Date, updatedAt: Date? = nil) {
        self.id = id
        self.text = text
        self.category = category
        self.isSharedText = isSharedText
        self.hadPhoto = hadPhoto
        self.hadRecording = hadRecording
        self.startedAt = startedAt
        self.updatedAt = updatedAt ?? startedAt
    }

    /// Only words are kept: a screen with nothing typed has no draft.
    public var hasWords: Bool { !text.allSatisfy(\.isWhitespace) }

    /// The first line, cut to `limit` characters, for the Home card.
    public func preview(limit: Int = 80) -> String {
        let first = text.split(whereSeparator: \.isNewline).first { !$0.allSatisfy(\.isWhitespace) }
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return first.count > limit ? String(first.prefix(limit - 1)) + "…" : first
    }
}

/// Every unfinished note kept on this iPhone, newest first.
public struct UnfinishedNoteBook: Codable, Equatable, Sendable {
    public static let version = 1
    /// More would be clutter; the oldest beyond this goes, and the screen says it might.
    public static let maxNotes = 5
    /// An unfinished note untouched this long is removed when Doddy next opens.
    public static let keepFor: TimeInterval = 30 * 86_400

    public private(set) var version: Int
    public private(set) var notes: [UnfinishedNote]

    public init(notes: [UnfinishedNote] = []) {
        self.version = Self.version
        self.notes = notes.sorted { $0.updatedAt > $1.updatedAt }
    }

    public var newest: UnfinishedNote? { notes.first }

    public func note(id: UUID) -> UnfinishedNote? { notes.first { $0.id == id } }

    /// Keeps the screen's current state. A note with no words is removed instead.
    public mutating func keep(_ note: UnfinishedNote) {
        notes.removeAll { $0.id == note.id }
        guard note.hasWords else { return }
        notes.insert(note, at: 0)
        notes.sort { $0.updatedAt > $1.updatedAt }
        if notes.count > Self.maxNotes { notes.removeLast(notes.count - Self.maxNotes) }
    }

    /// Saved as a note, or discarded.
    public mutating func remove(id: UUID) {
        notes.removeAll { $0.id == id }
    }

    /// Without the ones untouched for `keepFor`.
    public func pruned(now: Date) -> UnfinishedNoteBook {
        UnfinishedNoteBook(notes: notes.filter { now.timeIntervalSince($0.updatedAt) < Self.keepFor })
    }

    public func encoded() throws -> Data {
        // Dates as the default number, so they read back exactly and the write can be checked.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    /// Nil when the file isn't a book this version of Doddy can read. The caller keeps such a file
    /// aside instead of writing over it.
    public static func decoded(_ data: Data) -> UnfinishedNoteBook? {
        guard let book = try? JSONDecoder().decode(UnfinishedNoteBook.self, from: data), book.version == version else { return nil }
        return UnfinishedNoteBook(notes: book.notes)
    }
}

/// Which unfinished note a capture screen opens with.
public enum UnfinishedNoteResume {
    public enum Start: Equatable, Sendable {
        /// Empty, with a new draft id.
        case fresh
        /// The user's unfinished note, filled in, keeping its id.
        case resumed(UnfinishedNote)
        /// Shortcut text fills the screen; an unfinished note is kept and mentioned, not mixed in.
        case sharedWithOtherWaiting(UnfinishedNote)
    }

    /// An empty capture screen opens with the newest unfinished note; a screen opened with
    /// shortcut text keeps that text and only says another note is waiting.
    public static func start(sharedText: String?, book: UnfinishedNoteBook, asked: UUID? = nil) -> Start {
        if let asked, let note = book.note(id: asked) { return .resumed(note) }
        guard let newest = book.newest else { return .fresh }
        if let sharedText, !sharedText.allSatisfy(\.isWhitespace) { return .sharedWithOtherWaiting(newest) }
        return .resumed(newest)
    }
}
