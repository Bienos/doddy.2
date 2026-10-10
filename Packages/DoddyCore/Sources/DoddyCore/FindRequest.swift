import Foundation

/// A search handed to Doddy by the "Find in Doddy" shortcut (ADR-138). It only opens Find with
/// the words filled in; the search itself is the same local lookup as typing them.
public struct FindRequest: Identifiable, Equatable, Sendable {
    /// Longer than any useful search; spoken or pasted text past this is cut at a word break.
    public static let maxLength = 200

    public let id: UUID
    public let query: String

    /// One line: surrounding space trimmed, line breaks and runs of spaces collapsed.
    public init(id: UUID = UUID(), query: String) {
        self.id = id
        let oneLine = query.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard oneLine.count > Self.maxLength else {
            self.query = oneLine
            return
        }
        let head = oneLine.prefix(Self.maxLength)
        self.query = head.lastIndex(of: " ").map { String(head[..<$0]) } ?? String(head)
    }
}
