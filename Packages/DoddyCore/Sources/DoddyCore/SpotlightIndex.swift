import Foundation

// Doddy's notes and lists in iPhone search (ADR-330). Off until the user turns on "Show in iPhone
// search". iOS keeps the index on this iPhone; a result opens the note or list in Doddy. Private
// notes (ADR-310) are never indexed, and turning the switch off removes everything Doddy indexed.

public struct SpotlightEntry: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case note, list }

    /// The note's or list's id; the result opens it.
    public let id: UUID
    public let kind: Kind
    public let title: String
    public let content: String
    public let keywords: [String]
}

public enum SpotlightIndex {
    public static let domain = "doddy.notes"
    public static let enabledKey = "spotlight.enabled"
    static let maxContent = 300
    static let maxListItems = 20

    /// What should be in the index now: every note but private ones (and lists, which are notes
    /// of type list), shortened; nothing when switched off.
    public static func entries(memories: [MemoryRecord], lists: [DoddyList], privateNotes: PrivateNotes, isOn: Bool) -> [SpotlightEntry] {
        guard isOn else { return [] }
        let listIDs = Set(lists.map(\.id))
        let notes = privateNotes.shareable(memories).filter { !listIDs.contains($0.id) && $0.category != .list }.map { record in
            SpotlightEntry(
                id: record.id, kind: .note,
                title: WidgetSnapshot.shortened(record.currentText),
                content: String(record.currentText.prefix(maxContent)),
                keywords: NoteTags.tags(in: record.currentText))
        }
        let listEntries = lists.filter { !privateNotes.contains($0.id) }.map { list in
            SpotlightEntry(
                id: list.id, kind: .list,
                title: WidgetSnapshot.shortened(list.name),
                content: String(list.open.prefix(maxListItems).map(\.text).joined(separator: ", ").prefix(maxContent)),
                keywords: [])
        }
        return notes + listEntries
    }

    /// A short fingerprint of the entries, so the index is rebuilt only when something changed.
    public static func signature(_ entries: [SpotlightEntry]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(entries) else { return "" }
        // FNV-1a, 64 bits: enough to notice a change; not a security measure.
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return "\(entries.count)-\(String(hash, radix: 16))"
    }
}
