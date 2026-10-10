import Foundation

// End-of-conversation save suggestions (ADR-229). After a voice conversation ends, Doddy offers
// up to three things the user said that look worth keeping: "Marta's birthday is 12 May", "the
// plumber Adam comes on Tuesday". Rules, not a model, on the iPhone:
//  - only the user's own transcribed sentences are used, never Doddy's lines or tool results;
//  - the words are the user's (fillers like "oh, by the way" trimmed); nothing is rewritten or added;
//  - questions, requests to Doddy, small talk and secrets (passwords, card or account numbers) are
//    never offered; neither is anything already proposed in the conversation or already saved;
//  - every suggestion starts unticked and nothing is saved until the user ticks it and taps Save.

/// One sentence the user said that may be worth keeping.
public struct SaveSuggestion: Equatable, Sendable, Identifiable {
    public enum Reason: String, Equatable, Sendable {
        /// The user said "remember…" or "don't forget…" and nothing was saved for it.
        case askedToRemember
        case dateOrNumber
        case recommendation
        case personalFact
        case plan
        case preference
    }

    public let id: Int
    /// The user's words, as they will be saved if ticked and not changed.
    public let text: String
    public let reason: Reason

    public init(id: Int, text: String, reason: Reason) {
        self.id = id
        self.text = text
        self.reason = reason
    }
}

public enum SaveSuggestions {
    public static let maxSuggestions = 3
    static let minWords = 4
    static let maxWords = 40

    /// Up to `maxSuggestions` sentences from `userLines`, in the order they were said.
    /// `alreadyProposed` are note texts Doddy put on a save card in this conversation (saved or
    /// declined); `existingNotes` are the notes on the phone.
    public static func suggest(
        userLines: [String], alreadyProposed: [String], existingNotes: [MemoryRecord],
        max: Int = maxSuggestions
    ) -> [SaveSuggestion] {
        var scored: [(order: Int, text: String, reason: SaveSuggestion.Reason, score: Int)] = []
        var seen = Set<String>()
        let blocked = (alreadyProposed + existingNotes
            .filter { $0.source != .sampleFixture }
            .flatMap { [$0.currentText, $0.rawText] })
            .map { Set(SearchFolding.tokens($0)) }
        var order = 0
        for line in userLines {
            for sentence in sentences(line) {
                defer { order += 1 }
                guard let (text, reason, score) = evaluate(sentence) else { continue }
                let key = DuplicateNote.key(text)
                guard !key.isEmpty, seen.insert(key).inserted, !isCovered(text, by: blocked) else { continue }
                scored.append((order, text, reason, score))
            }
        }
        let best = scored
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.order < $1.order }
            .prefix(Swift.max(0, max))
            .sorted { $0.order < $1.order }
        return best.enumerated().map { SaveSuggestion(id: $0.offset, text: $0.element.text, reason: $0.element.reason) }
    }

    /// Already proposed or saved: some earlier text holds every number in `text` and at least 80% of
    /// its other meaningful words. "My gate code is 4821" is covered by a saved "Gate code 4821";
    /// "Gate code is 5555" is not (a different number is new information).
    static func isCovered(_ text: String, by blocked: [Set<String>]) -> Bool {
        let terms = SearchFolding.queryTerms(text).map(numberDigits)
        guard !terms.isEmpty else { return false }
        let numbers = terms.filter { $0.contains(where: \.isNumber) }
        return blocked.map { Set($0.map(numberDigits)) }.contains { words in
            numbers.allSatisfy(words.contains)
                && Double(terms.filter(words.contains).count) >= 0.8 * Double(terms.count)
        }
    }

    /// "12th" and "12" are the same number for the duplicate check.
    static func numberDigits(_ word: String) -> String {
        word.first?.isNumber == true ? String(word.filter(\.isNumber)) : word
    }

    // MARK: Sentences

    /// Splits at . ! ? … ; and line breaks followed by a space or the end, so "3.5" and "12.05" stay whole.
    static func sentences(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        let characters = Array(line)
        for (index, character) in characters.enumerated() {
            if character.isNewline {
                result.append(current)
                current = ""
                continue
            }
            current.append(character)
            if ".!?…;".contains(character) {
                let next = index + 1 < characters.count ? characters[index + 1] : nil
                if next == nil || next!.isWhitespace {
                    result.append(current)
                    current = ""
                }
            }
        }
        result.append(current)
        return result.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    // MARK: Rules

    /// The cleaned sentence with why it is worth keeping and how strongly, or nil.
    static func evaluate(_ raw: String) -> (String, SaveSuggestion.Reason, Int)? {
        var text = raw
        var askedToRemember = false
        text = stripLeading(text, phrases: fillers)
        if let rest = stripPrefix(text, of: rememberPrefixes) {
            text = stripLeading(rest, phrases: ["that", "ze", "że"])
            askedToRemember = true
        }
        text = stripTrailing(text, phrases: ["by the way", "btw", "anyway", "przy okazji", "w sumie"])
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-–—"))
        guard !text.isEmpty else { return nil }

        let folded = SearchFolding.fold(text)
        let words = SearchFolding.tokens(folded: folded)
        guard (minWords...maxWords).contains(words.count), text.count <= 300 else { return nil }
        guard !text.hasSuffix("?"), let first = words.first, !questionWords.contains(first) else { return nil }
        guard !requestStarts.contains(where: { startsWith(words, $0) }) else { return nil }
        guard !smallTalk.contains(where: { startsWith(words, $0) }) else { return nil }
        guard !containsSecret(folded: folded, words: words) else { return nil }

        var signals: [(SaveSuggestion.Reason, Int)] = []
        if askedToRemember { signals.append((.askedToRemember, 5)) }
        if words.contains(where: { $0.contains(where: \.isNumber) }) { signals.append((.dateOrNumber, 2)) }
        if words.contains(where: { months.contains($0) || weekdays.contains(where: $0.hasPrefix) }) { signals.append((.dateOrNumber, 2)) }
        if words.contains(where: { word in occasions.contains(where: word.hasPrefix) }) { signals.append((.personalFact, 3)) }
        if words.contains(where: { word in recommendationWords.contains(where: word.hasPrefix) }) { signals.append((.recommendation, 3)) }
        // "My …" and a family word are one signal, not two: "my boss is annoying" isn't a fact to keep.
        if possessiveFact(words, text: text) {
            signals.append((.personalFact, 2))
        } else if words.contains(where: familyWords.contains) {
            signals.append((.personalFact, 1))
        }
        if planPhrases.contains(where: { contains(words, $0) }) { signals.append((.plan, 2)) }
        if words.contains(where: { word in preferenceWords.contains(where: word.hasPrefix) }) { signals.append((.preference, 2)) }
        if hasName(text) { signals.append((.personalFact, 1)) }
        let score = signals.map(\.1).reduce(0, +)
        guard score >= 3, let strongest = signals.max(by: { $0.1 < $1.1 }) else { return nil }
        return (capitalizedFirst(text), strongest.0, score)
    }

    static func containsSecret(folded: String, words: [String]) -> Bool {
        if secretWords.contains(where: { contains(words, $0) }) { return true }
        // 11+ digits in a row (spaces and dashes allowed): card, bank account, PESEL, IBAN.
        var run = 0
        for character in folded {
            if character.isNumber { run += 1; if run >= 11 { return true } }
            else if character != " " && character != "-" { run = 0 }
        }
        return false
    }

    /// "my …", "our …", "mój/moja/moje …", or a capitalised name with 's ("Marta's"), but not
    /// "that's" or "it's".
    static func possessiveFact(_ words: [String], text: String) -> Bool {
        if words.contains(where: ["my", "our", "moj", "moja", "moje", "mojego", "mojej", "nasz", "nasza", "nasze"].contains) {
            return true
        }
        let parts = text.split(whereSeparator: { !($0.isLetter || $0 == "'" || $0 == "’") })
        return parts.contains { part in
            guard let first = part.first, first.isUppercase, part.hasSuffix("'s") || part.hasSuffix("’s") else { return false }
            return !["It's", "That's", "What's", "There's", "Here's", "He's", "She's", "Let's", "Who's", "Where's"]
                .contains(part.replacingOccurrences(of: "’", with: "'"))
        }
    }

    /// A capitalised word after the first one, other than "I": likely a person or place.
    static func hasName(_ text: String) -> Bool {
        let parts = text.split(whereSeparator: { !($0.isLetter || $0 == "'") }).dropFirst()
        return parts.contains { part in
            guard let first = part.first, first.isUppercase, part != "I", part != "Doddy", part.count > 1 else { return false }
            return !part.allSatisfy(\.isUppercase) // "ID", "PIN" are not names
        }
    }

    static func capitalizedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    // MARK: Phrase helpers (folded words)

    static func phraseWords(_ phrase: String) -> [String] { SearchFolding.tokens(phrase) }

    static func startsWith(_ words: [String], _ phrase: String) -> Bool {
        let p = phraseWords(phrase)
        return !p.isEmpty && words.count >= p.count && Array(words.prefix(p.count)) == p
    }

    static func contains(_ words: [String], _ phrase: String) -> Bool {
        let p = phraseWords(phrase)
        guard !p.isEmpty, words.count >= p.count else { return false }
        return (0...(words.count - p.count)).contains { Array(words[$0..<($0 + p.count)]) == p }
    }

    /// Drops any of `phrases` (and the punctuation after it) from the start, repeatedly.
    static func stripLeading(_ text: String, phrases: [String]) -> String {
        var text = text
        var changed = true
        while changed {
            changed = false
            if let rest = stripPrefix(text, of: phrases) {
                text = rest
                changed = true
            }
        }
        return text
    }

    /// `text` without the first matching phrase at its start (whole words, case- and accent-insensitive).
    static func stripPrefix(_ text: String, of phrases: [String]) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        for phrase in phrases {
            let wanted = phraseWords(phrase)
            var index = trimmed.startIndex
            var matched = 0
            while matched < wanted.count, index < trimmed.endIndex {
                while index < trimmed.endIndex, !(trimmed[index].isLetter || trimmed[index].isNumber) { index = trimmed.index(after: index) }
                var end = index
                while end < trimmed.endIndex, trimmed[end].isLetter || trimmed[end].isNumber { end = trimmed.index(after: end) }
                guard SearchFolding.fold(String(trimmed[index..<end])) == wanted[matched] else { break }
                matched += 1
                index = end
            }
            if matched == wanted.count, !wanted.isEmpty {
                let rest = trimmed[index...].drop { $0 == "," || $0 == ":" || $0 == "-" || $0.isWhitespace }
                return String(rest)
            }
        }
        return nil
    }

    static func stripTrailing(_ text: String, phrases: [String]) -> String {
        var text = text.trimmingCharacters(in: CharacterSet(charactersIn: " .!…"))
        for phrase in phrases {
            let folded = SearchFolding.fold(text)
            let suffix = SearchFolding.fold(phrase)
            if folded.hasSuffix(suffix), folded.count > suffix.count {
                let cut = text.dropLast(phrase.count)
                // Only when the phrase is its own word(s).
                if let last = cut.last, !last.isLetter {
                    text = String(cut).trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
                }
            }
        }
        return text
    }

    // MARK: Word lists (matched after folding: lowercase, no accents, ł → l)

    static let fillers = [
        "oh", "ok", "okay", "so", "and", "well", "um", "uh", "hmm", "yeah", "yes", "also", "by the way",
        "anyway", "actually", "right", "oh and", "no", "wiec", "dobra", "aha", "sluchaj", "wiesz", "aha i",
        "tak", "a wlasnie", "przy okazji", "btw",
    ]
    static let rememberPrefixes = [
        "please remember", "remember", "don't forget", "dont forget", "do not forget", "make a note",
        "note that", "zapamietaj", "nie zapomnij", "zanotuj",
    ]
    static let questionWords: Set<String> = [
        "what", "where", "when", "who", "whom", "whose", "why", "how", "which", "can", "could", "would", "will",
        "should", "do", "does", "did", "is", "are", "was", "were", "have", "has",
        "czy", "co", "gdzie", "kiedy", "kto", "jak", "dlaczego", "czemu", "ile", "jaki", "jaka", "jakie", "ktory", "ktora",
    ]
    /// Things said to Doddy, not about the user's life.
    static let requestStarts = [
        "remind", "set", "add", "call", "text", "send", "open", "play", "tell", "show", "find", "search", "check",
        "read", "save", "create", "make", "put", "start", "stop", "cancel", "turn", "help", "give", "look", "ask",
        "let's", "lets", "please", "go", "write", "draft", "book", "schedule", "you", "you're", "youre", "i want you",
        "przypomnij", "ustaw", "dodaj", "zadzwon", "wyslij", "napisz", "otworz", "powiedz", "pokaz", "znajdz",
        "sprawdz", "zapisz", "zrob", "wlacz", "wylacz", "daj", "pomoz", "przeczytaj", "poszukaj", "jestes", "ty",
    ]
    static let smallTalk = [
        "thanks", "thank you", "bye", "goodbye", "hello", "hi", "hey", "good morning", "good night", "i'm fine",
        "im fine", "i am fine", "not much", "nothing", "never mind", "that's all", "thats all", "that's it",
        "dzieki", "dziekuje", "czesc", "hej", "dzien dobry", "dobranoc", "na razie", "nic", "nie wazne", "niewazne", "to wszystko",
    ]
    static let secretWords = [
        "password", "passcode", "passwords", "login", "card number", "credit card", "debit card", "cvv", "cvc",
        "security code", "pin number", "card pin", "bank pin", "social security", "iban", "account number", "sort code", "seed phrase",
        "haslo", "hasla", "numer karty", "karta kredytowa", "numer konta", "pesel", "kod cvv", "pin karty", "pin do karty",
    ]
    static let months: Set<String> = [
        "january", "february", "march", "april", "may", "june", "july", "august", "september", "october",
        "november", "december", "jan", "feb", "mar", "apr", "jun", "jul", "aug", "sep", "sept", "oct", "nov", "dec",
        "styczen", "stycznia", "luty", "lutego", "marzec", "marca", "kwiecien", "kwietnia", "maj", "maja",
        "czerwiec", "czerwca", "lipiec", "lipca", "sierpien", "sierpnia", "wrzesien", "wrzesnia",
        "pazdziernik", "pazdziernika", "listopad", "listopada", "grudzien", "grudnia",
    ]
    /// Prefixes, so "mondays" and "poniedziałki" count too.
    static let weekdays = [
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "poniedzial", "wtor", "srod", "czwart", "piat", "sobot", "niedziel",
    ]
    static let occasions = ["birthday", "anniversary", "wedding", "urodzin", "imienin", "rocznic", "slub"]
    static let recommendationWords = ["recommend", "suggested", "worth", "polecil", "polecam", "polecan", "warto"]
    static let planPhrases = [
        "i need to", "i have to", "i must", "i promised", "i'm going to", "i will", "i'll",
        "we need to", "we're going to", "is coming", "comes on", "due on", "deadline",
        "musze", "musimy", "obiecalem", "obiecalam", "mam zamiar", "przyjdzie", "przychodzi", "termin",
    ]
    static let familyWords: Set<String> = [
        "mum", "mom", "mother", "dad", "father", "wife", "husband", "partner", "brother", "sister", "son", "daughter",
        "kids", "grandma", "grandpa", "boss", "friend", "neighbour", "neighbor",
        "mama", "mamy", "mamie", "tata", "taty", "zona", "maz", "brat", "siostra", "syn", "corka", "dzieci",
        "babcia", "dziadek", "szef", "szefowa", "sasiad", "sasiadka",
    ]
    static let preferenceWords = [
        "like", "likes", "love", "loves", "hate", "hates", "prefer", "favourite", "favorite", "allergic",
        "lubi", "lubie", "uwielbia", "nienawidzi", "woli", "wole", "ulubion", "uczulon", "alergi",
    ]
}

/// The "Worth keeping?" card after a conversation (ADR-229). All suggestions start unticked; the
/// user may change the words before saving. A suggestion counts as saved only when the memory
/// store returned the read-back record.
public struct SaveSuggestionCard: Equatable, Sendable {
    public enum ItemState: Equatable, Sendable {
        case offered
        case saving
        case saved(MemoryRecord)
        case failed(String)
    }

    public struct Item: Equatable, Sendable, Identifiable {
        public let suggestion: SaveSuggestion
        public var text: String
        public var isTicked = false
        public var state: ItemState = .offered
        public var id: Int { suggestion.id }
        public var isChanged: Bool { text != suggestion.text }
    }

    public private(set) var items: [Item]

    public init(_ suggestions: [SaveSuggestion]) {
        items = suggestions.map { Item(suggestion: $0, text: $0.text) }
    }

    public var tickedCount: Int { items.filter { $0.isTicked && $0.state == .offered }.count }
    public var isSaving: Bool { items.contains { $0.state == .saving } }
    /// The user tapped Save and every answer is in: the card shows results and an OK button.
    public var hasResults: Bool { !isSaving && items.contains { $0.state != .offered } }
    public var savedCount: Int { items.filter { if case .saved = $0.state { true } else { false } }.count }

    public mutating func toggle(_ id: Int) {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].state == .offered else { return }
        items[index].isTicked.toggle()
    }

    /// Changing the words ticks the item: the user clearly wants it.
    public mutating func setText(_ id: Int, _ text: String) {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].state == .offered else { return }
        items[index].text = text
        if items[index].isChanged { items[index].isTicked = true }
    }

    /// Ticked items to save now, marked `saving` so a second tap does nothing.
    public mutating func beginSaving() -> [(id: Int, text: String)] {
        var batch: [(Int, String)] = []
        for index in items.indices where items[index].isTicked && items[index].state == .offered {
            items[index].state = .saving
            batch.append((items[index].id, items[index].text))
        }
        return batch
    }

    public mutating func finish(_ id: Int, _ result: Result<MemoryRecord, SaveSuggestionFailure>) {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].state == .saving else { return }
        switch result {
        case .success(let record): items[index].state = .saved(record)
        case .failure(let failure): items[index].state = .failed(failure.message)
        }
    }
}

/// Why one suggestion wasn't saved, in words for the user.
public struct SaveSuggestionFailure: Error, Equatable, Sendable {
    public let message: String
    public init(message: String) { self.message = message }
}
