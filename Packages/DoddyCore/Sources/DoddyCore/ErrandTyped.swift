import Foundation

// A task typed on the Tasks screen (decision 2026-11-10-tasks-redesign). It is the same request as
// one handed over in a conversation (ADR-570): the same server route, the same digest over the words,
// the note and the title, and the same single tap on a card that shows all three (ADR-716). With no
// conversation, Doddy writes no note of its own, so the note is a fixed sentence that says exactly
// that, and the title is the start of the user's words. Nothing is invented: the screen shows the
// three texts before the tap, and the server gets nothing else.

extension ErrandDraft {
    /// The longest title cut from typed words, in UTF-16 units before the "…" (the server allows 80).
    public static let typedTitleLength = 60

    /// The draft for words typed on the Tasks screen: the words as typed (only trimmed, as every
    /// draft is), a title cut from their first line, the fixed note, and the app's language.
    public static func typed(_ words: String, language: String) -> ErrandDraft {
        let code = typedLanguage(language)
        return ErrandDraft(words: words, brief: typedNote(language: code), title: typedTitle(words), language: code)
    }

    /// The note sent with a typed task. Polish for `pl`, English otherwise. It is labelled as
    /// Doddy's note everywhere, so it says that Doddy didn't write one.
    public static func typedNote(language: String) -> String {
        language == "pl"
            ? "Wpisane przez użytkownika na ekranie Sprawy, nie powiedziane w rozmowie, więc Doddy nie dopisał własnej notatki. Zrób to, o co proszą słowa."
            : "Typed by the user on the Tasks screen, not said in a conversation, so Doddy added no note of its own. Do what the words ask."
    }

    /// The first line of the words, with runs of spaces made one. Longer than `typedTitleLength`, it
    /// is cut after the last whole word that fits and ends in "…"; one word longer than that is cut
    /// inside the word. Empty words give an empty title (the draft is then refused as missing words).
    public static func typedTitle(_ words: String) -> String {
        let firstLine = words.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let line = firstLine.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard line.utf16.count > typedTitleLength else { return line }
        var kept = ""
        for word in line.split(separator: " ") {
            let next = kept.isEmpty ? String(word) : kept + " " + word
            guard next.utf16.count <= typedTitleLength else { break }
            kept = next
        }
        if kept.isEmpty {
            // One very long word: whole characters, so an emoji or a letter with a mark is never split.
            for character in line {
                guard (kept + String(character)).utf16.count <= typedTitleLength else { break }
                kept.append(character)
            }
        }
        return kept + "\u{2026}"
    }

    /// The two-letter code the server writes the result in, from the app's language ("pl", "pt-BR",
    /// "zh-Hans", "en_GB"): the part before the first "-" or "_", lower case. Anything that isn't two
    /// letters is "en".
    public static func typedLanguage(_ localization: String) -> String {
        let code = localization.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map { $0.lowercased() } ?? ""
        return isLanguageCode(code) ? code : "en"
    }
}
