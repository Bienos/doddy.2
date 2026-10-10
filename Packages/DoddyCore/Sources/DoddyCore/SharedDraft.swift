import Foundation

/// Text handed to Doddy by the "Save to Doddy" shortcut (Siri, Shortcuts, Action Button, a
/// personal Share Sheet shortcut). It only ever opens the capture screen with the text filled
/// in: nothing is saved until the user taps Save (ADR-136).
public struct SharedDraft: Identifiable, Equatable, Sendable {
    public let id: UUID
    /// Exactly as received, unless it was only whitespace (then empty). Not trimmed or cut:
    /// the capture screen's own validation reports an over-long text, as for typed notes.
    public let text: String
    /// True when the text came from a shortcut (saved as `shared_content`); false for the
    /// "New note" control, which opens an empty capture screen the user types into (ADR-137).
    public let isSharedText: Bool

    public init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text.allSatisfy(\.isWhitespace) ? "" : text
        self.isSharedText = true
    }

    private init(id: UUID, blank: Void) {
        self.id = id
        self.text = ""
        self.isSharedText = false
    }

    /// An empty capture screen, as if the user tapped "Save a detail".
    public static func newNote(id: UUID = UUID()) -> SharedDraft {
        SharedDraft(id: id, blank: ())
    }
}

/// Decides when a shared draft can be shown. The capture sheet can't appear over an open voice
/// conversation or another capture screen, so the draft waits until those close. Only the
/// newest draft waits; nothing is ever saved from here.
public struct SharedDraftQueue: Equatable, Sendable {
    /// The draft the capture sheet is showing now.
    public private(set) var shown: SharedDraft?
    /// The newest draft that arrived while something else was on screen.
    public private(set) var waiting: SharedDraft?

    public init() {}

    /// `blocked` is true while a voice conversation or another capture screen is open.
    public mutating func receive(_ draft: SharedDraft, blocked: Bool) {
        if blocked || shown != nil {
            waiting = draft
        } else {
            shown = draft
        }
    }

    /// The capture sheet for `shown` closed (saved, cancelled or swiped away).
    public mutating func shownClosed() {
        shown = nil
    }

    /// Call whenever something that blocks the sheet closes. Moves the waiting draft on screen
    /// if nothing blocks it any more.
    public mutating func unblocked(stillBlocked: Bool) {
        guard !stillBlocked, shown == nil, let next = waiting else { return }
        waiting = nil
        shown = next
    }
}
