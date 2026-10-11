import Foundation

// Tags in notes (ADR-333). A tag is a word the user writes with "#" in the note itself, e.g.
// "Gate code 4512 #home". Nothing is added or guessed: the tags are read from the note's current
// words, so editing the note changes its tags. Memories can show one tag's notes, and the voice
// agent can ask for them by searching "#home".

public enum NoteTags {
    static let maxLength = 30

    /// The note's tags, lowercased, in the order written, without repeats. "#" counts only at the
    /// start or after a space or an opening bracket ("C#", "a#b" and "site.com/#top" aren't tags),
    /// and the tag must have a letter ("#1" isn't one).
    public static func tags(in text: String) -> [String] {
        words(in: text, marker: "#").map { $0.lowercased() }.reduce(into: []) { found, tag in
            if !found.contains(tag) { found.append(tag) }
        }
    }

    /// The words written right after `marker`, as written, in order (repeats kept). Shared with
    /// people (`@Marta`, ADR-341): the marker counts only at the start or after a space or an
    /// opening bracket, so "C#" and "anna@example.com" don't count, and the word needs a letter.
    static func words(in text: String, marker: Character) -> [String] {
        var found: [String] = []
        let characters = Array(text)
        var index = 0
        while index < characters.count {
            defer { index += 1 }
            guard characters[index] == marker else { continue }
            if index > 0 {
                let before = characters[index - 1]
                guard before.isWhitespace || before == "(" || before == "[" else { continue }
            }
            var end = index + 1
            while end < characters.count, isTagCharacter(characters[end]) { end += 1 }
            var word = String(characters[(index + 1)..<end])
            while let last = word.last, last == "-" || last == "_" { word.removeLast() }
            index = end - 1
            guard !word.isEmpty, word.count <= maxLength, word.contains(where: \.isLetter) else { continue }
            found.append(word)
        }
        return found
    }

    static func isTagCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_" || character == "-"
    }

    /// Tags in use across `records`, most used first, then by name.
    public static func counts(_ records: [MemoryRecord]) -> [(tag: String, count: Int)] {
        var counts: [String: Int] = [:]
        for record in records {
            for tag in tags(in: record.currentText) { counts[tag, default: 0] += 1 }
        }
        return counts.map { (tag: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.tag < $1.tag }
    }

    /// `records` in their order, keeping those that carry `tag`; all of them for nil.
    public static func filter(_ records: [MemoryRecord], tag: String?) -> [MemoryRecord] {
        guard let tag = tag.map({ normalized($0) }), !tag.isEmpty else { return records }
        return records.filter { tags(in: $0.currentText).contains(tag) }
    }

    /// The tag a voice search asks for: a query that is exactly one "#word". Nil otherwise, and
    /// the search is the usual word search.
    public static func tagQuery(_ query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("#"), !trimmed.contains(where: \.isWhitespace) else { return nil }
        let found = tags(in: trimmed)
        guard found.count == 1, "#" + found[0] == trimmed.lowercased() else { return nil }
        return found[0]
    }

    static func normalized(_ tag: String) -> String {
        var word = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if word.hasPrefix("#") { word.removeFirst() }
        return word
    }
}

extension VoiceToolReply {
    /// The notes carrying one tag, newest first, in their exact words. Never guesses.
    public static func taggedNotes(_ tag: String, notes: [MemoryRecord], limit: Int = 8) -> String {
        let sorted = notes.sorted { ($0.capturedAt ?? .distantPast) > ($1.capturedAt ?? .distantPast) }
        guard !sorted.isEmpty else {
            return "No saved note has the tag #\(tag). Tell the user; do not guess. Tags are words they wrote with # in a note."
        }
        var lines = ["Found \(sorted.count) saved note\(sorted.count == 1 ? "" : "s") with #\(tag) (exact text, newest first):"]
        for record in sorted.prefix(limit) {
            lines.append("- \"\(record.currentText)\" (saved \(timestamp(record.capturedAt)))")
        }
        if sorted.count > limit {
            lines.append("…and \(sorted.count - limit) more. Ask the user to narrow it down if needed.")
        }
        return lines.joined(separator: "\n")
    }
}
