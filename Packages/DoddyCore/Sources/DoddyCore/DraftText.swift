import Foundation

/// How pasted text joins what is already in the capture editor (ADR-146). Nothing is trimmed or
/// cut: the pasted words go in exactly as copied, and the editor's own length check reports a
/// note that is too long, as for typed text.
public enum DraftText {
    /// `current` when `pasted` is empty. If the editor has nothing but whitespace, the pasted
    /// text replaces it. Otherwise it goes on a new line after what is there.
    public static func pasting(_ pasted: String, into current: String) -> String {
        guard !pasted.isEmpty else { return current }
        if current.allSatisfy(\.isWhitespace) { return pasted }
        return current + (current.last?.isNewline == true ? "" : "\n") + pasted
    }

    /// Several items from the clipboard (e.g. a multi-item copy) become one paste, one per line.
    public static func pasting(_ items: [String], into current: String) -> String {
        pasting(items.filter { !$0.isEmpty }.joined(separator: "\n"), into: current)
    }
}
