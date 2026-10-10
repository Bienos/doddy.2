import Foundation

/// Spots a note the user already saved with the same words, before saving it again (ADR-141).
/// "Same words" means the same letters and numbers in the same order, ignoring case, accents,
/// punctuation and spacing, so "Gate code: 4821." matches "gate code 4821". It only warns: the
/// user can still save it.
public enum DuplicateNote {
    static func key(_ text: String) -> String {
        SearchFolding.tokens(text).joined(separator: " ")
    }

    /// The newest saved note whose current or original text has the same words, if any.
    /// Sample notes are ignored. Text with no letters or numbers never matches.
    public static func existing(for text: String, in records: [MemoryRecord]) -> MemoryRecord? {
        let wanted = key(text)
        guard !wanted.isEmpty else { return nil }
        return records
            .filter { $0.source != .sampleFixture }
            .sorted { ($0.capturedAt ?? .distantPast) > ($1.capturedAt ?? .distantPast) }
            .first { key($0.currentText) == wanted || key($0.rawText) == wanted }
    }
}
