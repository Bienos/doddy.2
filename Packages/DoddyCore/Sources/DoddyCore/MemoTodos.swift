import Foundation

// To-dos from a voice memo (ADR-311). After a memo is written out on the iPhone, Doddy offers the
// sentences that sound like things to do ("I need to call the plumber", "kup mleko") as list
// items. Rules, not a model, on the iPhone:
//  - only the memo's own words; the lead-in ("I need to", "muszę") is dropped and nothing else is
//    reworded or added;
//  - questions are never offered, nor anything too short or too long to be one item;
//  - every item starts unticked, and nothing is added until the user ticks it and taps Add.

public enum MemoTodos {
    public static let maxItems = 5
    static let minLength = 3
    static let maxLength = 120

    /// Lead-ins that are dropped; what follows is the to-do. Longest first, lowercased.
    static let leadIns: [String] = [
        // English
        "don't forget to", "dont forget to", "do not forget to", "remember to", "make sure to", "make sure i",
        "i need to", "i have to", "i've got to", "ive got to", "i must", "i should", "we need to", "we have to",
        "need to", "have to", "got to", "to do:", "todo:", "to-do:",
        // Polish
        "nie zapomnij", "nie zapomnieć", "pamiętaj, żeby", "pamiętaj żeby", "pamiętaj, aby", "pamiętaj aby", "pamiętaj o",
        "pamiętaj", "muszę", "musimy", "trzeba", "powinienem", "powinnam", "mam do zrobienia:", "do zrobienia:",
    ].sorted { $0.count > $1.count }

    /// Sentences that start with one of these are kept whole: they are already an instruction.
    static let actionVerbs: Set<String> = [
        "call", "buy", "email", "book", "pay", "send", "pick", "fix", "check", "cancel", "renew", "order",
        "ring", "text", "schedule", "write", "return", "collect", "clean", "print", "post", "reply", "sign",
        "zadzwoń", "kup", "zapłać", "wyślij", "odbierz", "zarezerwuj", "napisz", "sprawdź", "zamów", "oddaj",
        "odpisz", "wydrukuj", "posprzątaj", "umów", "przedłuż", "anuluj", "podpisz",
    ]

    /// Up to `maxItems` to-dos in the order they were said, without repeats.
    public static func suggest(_ transcript: String, max: Int = maxItems) -> [String] {
        var found: [String] = []
        var seen = Set<String>()
        for sentence in sentences(transcript) {
            guard found.count < max, let item = todo(in: sentence) else { continue }
            let key = SearchFolding.tokens(item).joined(separator: " ")
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            found.append(item)
        }
        return found
    }

    static func todo(in sentence: String) -> String? {
        var text = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.hasSuffix("?") else { return nil }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: ".!;:,").union(.whitespaces))
        // Spoken fillers before the lead-in.
        for filler in ["and ", "also ", "oh ", "so ", "then ", "i ", "a ", "i jeszcze ", "jeszcze ", "no i ", "no "] {
            if text.lowercased().hasPrefix(filler), leadIn(in: String(text.dropFirst(filler.count))) != nil {
                text = String(text.dropFirst(filler.count))
                break
            }
        }
        if let lead = leadIn(in: text) {
            text = String(text.dropFirst(lead.count)).trimmingCharacters(in: CharacterSet(charactersIn: ",:").union(.whitespaces))
            // "remember to call" → "call"; "pamiętaj, żeby kupić" → "kupić".
            for joiner in ["to ", "żeby ", "aby ", "o "] where text.lowercased().hasPrefix(joiner) {
                text = String(text.dropFirst(joiner.count))
            }
        } else {
            let first = text.split(separator: " ").first.map { $0.lowercased() } ?? ""
            guard actionVerbs.contains(first) else { return nil }
        }
        text = text.trimmingCharacters(in: .whitespaces)
        // At least a verb and what it's about ("call Adam"), and short enough for one list item.
        guard text.count >= minLength, text.count <= maxLength, text.split(separator: " ").count >= 2 else { return nil }
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    static func leadIn(in text: String) -> String? {
        let lower = text.lowercased()
        return leadIns.first { lead in
            guard lower.hasPrefix(lead) else { return false }
            // A whole word: "need to" but not "need tomatoes".
            let rest = lower.dropFirst(lead.count)
            return rest.isEmpty || rest.first == " " || rest.first == "," || lead.hasSuffix(":")
        }
    }

    /// Split on sentence ends and line breaks; speech-to-text puts full stops between sentences.
    static func sentences(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        for character in text {
            if ".!?\n;".contains(character) {
                if character == "?" { current.append(character) }
                if !current.trimmingCharacters(in: .whitespaces).isEmpty { result.append(current) }
                current = ""
            } else {
                current.append(character)
            }
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty { result.append(current) }
        return result
    }
}
