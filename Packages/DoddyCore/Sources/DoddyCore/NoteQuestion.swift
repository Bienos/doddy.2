import Foundation

// "Ask me about it" on Home's recently saved notes (ADR-403). Tapping it opens a conversation
// about that one note: after Doddy's greeting the app tells the agent which note, and Doddy says
// in one line what it says and asks what the user wants to do with it. The note's words go to the
// voice agent as part of the conversation, as every saved note already does (`saved_notes`);
// a private note (ADR-310) never gets the button and is never sent.

public enum NoteQuestion {
    /// Longest stretch of the note put into the app message; the rest is still in `saved_notes`.
    public static let maxCharacters = 300

    /// Only notes that may go to the voice agent at all.
    public static func canAsk(about record: MemoryRecord, privateNotes: PrivateNotes) -> Bool {
        !privateNotes.contains(record.id) && !record.currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The app's message after the greeting (sent with the "(app)" prefix).
    public static func appMessage(for record: MemoryRecord) -> String {
        let text = record.currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        let quoted = text.count > maxCharacters ? String(text.prefix(maxCharacters)) + "…" : text
        return "The user tapped Ask me about it on this saved note: \u{201C}\(quoted)\u{201D}. "
            + "Do what the note question section says now."
    }
}
