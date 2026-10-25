import Foundation
import SwiftUI

/// The island's and the Lock Screen's words in the language Doddy's screens use (owner, 24 Oct
/// 2026: "zrób też opcję Polska", ADR-617). The widget extension is its own process and doesn't
/// see the language the app set for itself (Polish by default, ADR-573), so the app sends its
/// language with each update (`ContentState.language`) and these views look every English word
/// up in that language's table of the string catalog (`<code>.lproj`). A word with no line there
/// stays English; the scene logic itself is English throughout.
enum IslandLanguage {
    /// Words with numbers in them, as the catalogs hold them: "Step 2 of 3" is looked up as
    /// "Step %lld of %lld".
    static let formats: [String] = [
        islandWord("Doddy isn't listening · %lld notes saved"),
        islandWord("Step %lld of %lld"),
        islandWord("%lld steps"),
    ]

    /// `english` in `language` (an `.lproj` name such as "pl"), or in this process's own language
    /// when `language` is nil or the app has no table for it.
    static func text(_ english: String, _ language: String?) -> String {
        guard !english.isEmpty else { return english }
        let bundle = language.flatMap(bundle(for:)) ?? .main
        let missing = "\u{1}"
        let found = bundle.localizedString(forKey: english, value: missing, table: nil)
        if found != missing { return found }
        // Numbers: each run of digits becomes %lld in the key, then goes back into the words.
        var key = "", digits = ""
        var numbers: [Int64] = []
        for character in english {
            if character.isASCII, character.isNumber {
                digits.append(character)
                continue
            }
            if !digits.isEmpty {
                numbers.append(Int64(digits) ?? 0)
                key += "%lld"
                digits = ""
            }
            key.append(character)
        }
        if !digits.isEmpty {
            numbers.append(Int64(digits) ?? 0)
            key += "%lld"
        }
        guard !numbers.isEmpty, numbers.count <= 3 else { return english }
        let format = bundle.localizedString(forKey: key, value: missing, table: nil)
        // A line must have as many numbers as the English, or it isn't used.
        guard format != missing, format.components(separatedBy: "%lld").count == numbers.count + 1 else { return english }
        return String(format: format, arguments: numbers.map { $0 as CVarArg })
    }

    private static func bundle(for language: String) -> Bundle? {
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }
}

private struct IslandLanguageKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    /// The language the app's screens are in, for the island's words (ADR-617). Nil: this
    /// process's own language (the app's screens in the app, the iPhone's in the widget).
    var islandLanguage: String? {
        get { self[IslandLanguageKey.self] }
        set { self[IslandLanguageKey.self] = newValue }
    }
}

/// An island or Lock Screen word in Doddy's language (`IslandLanguage`).
struct IslandText: View {
    let english: String
    @Environment(\.islandLanguage) private var language

    init(_ english: String) {
        self.english = english
    }

    var body: some View {
        Text(verbatim: IslandLanguage.text(english, language))
    }
}
