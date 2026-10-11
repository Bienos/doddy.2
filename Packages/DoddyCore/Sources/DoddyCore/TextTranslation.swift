import Foundation

// Translate text without internet (ADR-346). Apple's on-device translation (iOS 18) turns typed
// text from one language into another on this iPhone. The first time a pair is used, iOS asks to
// download its languages; after that it works offline. Doddy's voice translator still needs the
// internet. Only languages Apple supports work; the screen checks with iOS before translating.

public enum TextTranslation {
    public static let maxLength = 2000

    public enum Problem: Error, Equatable, Sendable { case empty, tooLong, sameLanguage }

    /// The text as typed, trimmed, or why it can't be translated.
    public static func check(_ text: String, from source: String, to target: String) -> Result<String, Problem> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        guard trimmed.count <= maxLength else { return .failure(.tooLong) }
        guard source != target else { return .failure(.sameLanguage) }
        return .success(trimmed)
    }

    /// Doddy's languages, by their own name, the user's language first.
    public static func languages(first owner: String) -> [TranslatorLanguage] {
        let all = TranslatorLanguages.all
        let mine = all.filter { $0.code == owner }
        return mine + all.filter { $0.code != owner }.sorted { $0.nativeName < $1.nativeName }
    }

    /// The other language a new screen starts with: English, or Polish for an English speaker.
    public static func defaultTarget(for owner: String) -> String { owner == "en" ? "pl" : "en" }
}
