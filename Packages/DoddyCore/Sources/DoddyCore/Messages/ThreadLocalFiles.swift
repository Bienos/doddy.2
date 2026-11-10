import Foundation

/// A file Doddy made on this iPhone during a voice conversation (today: the PowerPoint deck from
/// `make_presentation`, ADR-567), kept for a week so it can be found again in Messages, under "Files
/// Doddy made for you". The file's own bytes live in the app's folder; this is only the list entry.
/// Nothing here goes to a server and nothing is added to the saved thread. Plain Swift for the Linux tests.
public struct LocalMadeFile: Equatable, Sendable, Identifiable, Codable {
    public let id: UUID
    /// The file's name with its extension, as the file is saved ("Date ideas.pptx").
    public let name: String
    /// What it is called on the card.
    public let title: String
    /// deck, doc, spreadsheet, pdf or text (the same words as `ThreadDocument.kind`).
    public let kind: String
    public let createdAt: Date

    public init(id: UUID = UUID(), name: String, title: String, kind: String, createdAt: Date) {
        self.id = id
        self.name = name
        self.title = title
        self.kind = kind
        self.createdAt = createdAt
    }

    /// For the card: "Deck", "Document", …
    public var label: String {
        switch kind {
        case "deck": "Deck"
        case "doc": "Document"
        case "spreadsheet": "Spreadsheet"
        case "pdf": "PDF"
        default: "Text"
        }
    }
}

public enum LocalMadeFiles {
    /// How long a file stays in the list, like the files Doddy's server keeps (ADR-564).
    public static let keepFor: TimeInterval = 7 * 24 * 3600
    /// At most this many cards, the newest ones.
    public static let limit = 6

    public static func isExpired(_ file: LocalMadeFile, now: Date) -> Bool {
        now.timeIntervalSince(file.createdAt) > keepFor
    }

    /// The files to show as cards, oldest first: not expired, the newest `limit`.
    public static func shown(_ files: [LocalMadeFile], now: Date) -> [LocalMadeFile] {
        let newest = files
            .filter { !isExpired($0, now: now) }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit)
        return newest.sorted { $0.createdAt < $1.createdAt }
    }

    /// The files whose week is over: their bytes are deleted and they leave the list.
    public static func expired(_ files: [LocalMadeFile], now: Date) -> [LocalMadeFile] {
        files.filter { isExpired($0, now: now) }
    }

    /// What Doddy hears after a file was kept for Messages, so he can say where it is. Said only when the copy was
    /// read back as complete.
    public static let inMessagesNote = "It is also under \"Files Doddy made for you\" in Messages for a week."
}
