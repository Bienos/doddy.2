import Foundation

// A page per person (ADR-341). A person is a name the user writes with "@" in a note, e.g.
// "@Marta wants the blue scarf". Like tags (ADR-333), nothing is added or guessed: the people
// come from the note's current words. A person's page lists the notes that mention them, and,
// only when Contacts is on, the birthday on the contact card with the same name. The agent asks
// for one person's notes by searching "@Marta".

public struct NotePerson: Equatable, Sendable, Identifiable {
    /// Lowercased name, the key that groups "@Marta" and "@marta".
    public let id: String
    /// The name as the user first wrote it in the newest note that mentions them.
    public let name: String
    public let count: Int
}

public enum NotePeople {
    /// The names mentioned in `text`, as written, without repeats (case-insensitive).
    public static func names(in text: String) -> [String] {
        var seen: Set<String> = []
        return NoteTags.words(in: text, marker: "@").filter { seen.insert(key($0)).inserted }
    }

    /// Everyone mentioned across `records`, most mentioned first, then by name. The shown name is
    /// the spelling in the newest note.
    public static func people(_ records: [MemoryRecord]) -> [NotePerson] {
        var counts: [String: Int] = [:]
        var shown: [String: (name: String, at: Date)] = [:]
        for record in records {
            let at = record.capturedAt ?? .distantPast
            for name in names(in: record.currentText) {
                let id = key(name)
                counts[id, default: 0] += 1
                if let current = shown[id], current.at > at { continue }
                shown[id] = (name, at)
            }
        }
        return counts.map { NotePerson(id: $0.key, name: shown[$0.key]?.name ?? $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.id < $1.id }
    }

    /// The notes that mention `person` (any spelling of case), newest first.
    public static func notes(_ records: [MemoryRecord], about person: String) -> [MemoryRecord] {
        let id = key(person.hasPrefix("@") ? String(person.dropFirst()) : person)
        guard !id.isEmpty else { return [] }
        return records
            .filter { names(in: $0.currentText).contains { key($0) == id } }
            .sorted { ($0.capturedAt ?? .distantPast) > ($1.capturedAt ?? .distantPast) }
    }

    /// The person a voice search asks for: a query that is exactly one "@Name". Nil otherwise.
    public static func personQuery(_ query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("@"), !trimmed.contains(where: \.isWhitespace) else { return nil }
        let found = names(in: trimmed)
        guard found.count == 1, "@" + found[0] == trimmed else { return nil }
        return found[0]
    }

    /// The text a new note about `person` starts with.
    public static func newNoteText(about person: String) -> String { "@\(person) " }

    /// The contact birthday shown on the page: only a card whose full name or first word is the
    /// person's name (case and accents ignored), and only when exactly one card matches. Two
    /// Martas means no birthday is shown rather than the wrong one.
    public static func birthday(for person: String, in contacts: [BirthdayContact]) -> BirthdayContact? {
        let id = folded(person)
        let matches = contacts.filter { contact in
            let full = folded(contact.name)
            let first = full.split(separator: " ").first.map(String.init) ?? full
            return full == id || first == id
        }
        return matches.count == 1 ? matches[0] : nil
    }

    static func key(_ name: String) -> String { name.lowercased() }

    static func folded(_ text: String) -> String {
        // Letters that are their own letter, not a letter plus an accent, so folding keeps them.
        let plain = text.replacingOccurrences(of: "ł", with: "l").replacingOccurrences(of: "Ł", with: "L")
            .replacingOccurrences(of: "ø", with: "o").replacingOccurrences(of: "Ø", with: "O")
            .replacingOccurrences(of: "đ", with: "d").replacingOccurrences(of: "Đ", with: "D")
        return plain.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension VoiceToolReply {
    /// The notes that mention one person, newest first, in their exact words. Never guesses.
    public static func personNotes(_ person: String, notes: [MemoryRecord], limit: Int = 8) -> String {
        guard !notes.isEmpty else {
            return "No saved note mentions @\(person). Tell the user; do not guess. People are names they wrote with @ in a note; you can also search their name as a plain word."
        }
        var lines = ["Found \(notes.count) saved note\(notes.count == 1 ? "" : "s") about @\(person) (exact text, newest first):"]
        for record in notes.prefix(limit) {
            lines.append("- \"\(record.currentText)\" (saved \(timestamp(record.capturedAt)))")
        }
        if notes.count > limit {
            lines.append("…and \(notes.count - limit) more. Ask the user to narrow it down if needed.")
        }
        return lines.joined(separator: "\n")
    }
}
