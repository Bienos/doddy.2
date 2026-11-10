import Foundation

// When search_memories finds no note with the user's words, voice also gets the newest few saved
// notes, read fresh from storage. "Did you get the note I just saved?" has no key words a note
// would contain ("note", "photo"), so a word search alone always answered "nothing found", even
// right after the user saved one during the call (owner report, 9 Nov 2026).
//
// The notes are real stored records in their exact words, labelled as "newest", never as a
// match. Private notes and lists are left out by the caller and again here.

/// The newest notes voice may see, and which of them carry a photo.
public struct NewestNotes: Equatable, Sendable {
    public static let limit = 3
    public let notes: [MemoryRecord]
    public let withPhoto: Set<UUID>

    public init(notes: [MemoryRecord], withPhoto: Set<UUID> = []) {
        self.notes = notes
        self.withPhoto = withPhoto
    }

    public static let none = NewestNotes(notes: [])

    /// Newest first, sample fixtures, lists and private notes removed before the limit.
    public static func pick(
        _ records: [MemoryRecord], excluding privateIDs: Set<UUID>, withPhoto: Set<UUID> = [], limit: Int = limit
    ) -> NewestNotes {
        let kept = records
            .filter { $0.category != .list && $0.source.isEligibleForPersonalRecall && !privateIDs.contains($0.id) }
            .sorted { ($0.capturedAt ?? .distantPast) > ($1.capturedAt ?? .distantPast) }
            .prefix(max(0, limit))
        return NewestNotes(notes: Array(kept), withPhoto: withPhoto.intersection(kept.map(\.id)))
    }
}

extension VoiceToolReply {
    /// `search(_:question:)`, and on no match the newest notes as a clearly labelled fallback.
    public static func search(_ outcome: RecallOutcome, question: String = "", newest: NewestNotes) -> String {
        if case .matches(let found) = outcome, !found.isEmpty { return search(outcome, question: question) }
        guard !newest.notes.isEmpty else { return search(.noMatch, question: question) }
        var lines = [
            "No saved note contains the words of this search.",
            "The user's newest saved notes follow (exact text, newest first). They did not match the search. Use one only if it is clearly the note the user means, for example one they just saved; then repeat it in their words and say when it was saved. Otherwise tell the user you couldn't find it. Do not guess.",
        ]
        lines.append(ToolData.block(newest.notes.map { record in
            let photo = newest.withPhoto.contains(record.id) ? " (has a photo)" : ""
            return "- \"\(ToolData.clean(record.currentText))\" (saved \(timestamp(record.capturedAt)))\(photo)"
        }))
        if !newest.withPhoto.isEmpty {
            lines.append("A photo stays on the user's iPhone and you can't see it; you have only the note's words.")
        }
        return lines.joined(separator: "\n")
    }
}
