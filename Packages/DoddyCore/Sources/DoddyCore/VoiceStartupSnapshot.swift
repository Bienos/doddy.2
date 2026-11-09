import Foundation

/// A bounded, fresh read for connecting voice. Never loads corrections, media or list item bodies.
public struct VoiceStartupSnapshot: Equatable, Sendable {
    public static let notesLimit = 24
    public static let listsLimit = 30
    public let notes: [MemoryRecord]
    public let lists: [ListSummary]
    public let notesTruncated: Bool
    public let listsTruncated: Bool

    public struct ListSummary: Equatable, Sendable {
        public let id: UUID
        public let name: String
        public let open: Int
        public let done: Int

        public init(id: UUID, name: String, open: Int, done: Int) {
            self.id = id; self.name = name; self.open = open; self.done = done
        }
    }

    public init(notes: [MemoryRecord], lists: [ListSummary], notesTruncated: Bool, listsTruncated: Bool) {
        self.notes = notes; self.lists = lists
        self.notesTruncated = notesTruncated; self.listsTruncated = listsTruncated
    }

    /// Recheck privacy after the awaited read: a note may have been made private meanwhile.
    public func notesContext(excluding privateIDs: Set<UUID>) -> VoiceContext.Rendered {
        let rendered = VoiceContext.savedNotes(notes.filter { !privateIDs.contains($0.id) })
        return .init(text: rendered.text, includedCount: rendered.includedCount,
                     truncated: rendered.truncated || notesTruncated)
    }

    public func listsContext(excluding privateIDs: Set<UUID>) -> String {
        let visible = lists.filter { !privateIDs.contains($0.id) }
        let text = visible.isEmpty ? "(no lists yet)" : visible.map {
            "- \(ToolData.clean($0.name)) (\($0.open) open, \($0.done) ticked)"
        }.joined(separator: "\n")
        return text + (listsTruncated ? "\n(The list index is incomplete; use read_list for the requested list.)" : "")
    }

    public static let unavailableNotes = VoiceContext.Rendered(
        text: "(Saved notes could not be read at startup. This is not an empty memory. Use search_memories when asked; do not guess.)",
        includedCount: 0, truncated: true)
    public static let unavailableLists = "(The list index could not be read at startup. Use read_list when asked; do not claim there are no lists.)"
}
