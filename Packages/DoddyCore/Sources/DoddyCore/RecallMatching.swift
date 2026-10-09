import Foundation

/// How a query word may match a word in a saved note. Deterministic word rules, no model:
/// a match only ever points at a real stored note, which recall then returns verbatim.
///
/// A query word matches a note word when one of its forms
/// - is a prefix of it (the original rule: "klucz" finds "klucze"),
/// - is, once its ending is dropped, a prefix of it (Polish endings: "urodziny" finds "urodzin"),
/// - is the same number ("pięć" or "five" finds "5"; "5678" finds a note saying "pięć sześć siedem osiem"),
/// - is its Polish/English counterpart from a small fixed list ("code" finds "kod"),
/// - is one typo away (5+ letters), or two (8+ letters).
public enum RecallMatching {
    /// One word of the question, with every form it may match as.
    public struct Term: Equatable, Sendable {
        /// The folded query word; what "Matched:" shows.
        public let word: String
        /// Forms tried by prefix (the word, its counterparts, number digits, stems).
        public let forms: [String]
        /// Forms allowed a typo (letters only, 5+ characters).
        public let fuzzyForms: [String]
    }

    public static func terms(_ query: String) -> [Term] {
        SearchFolding.queryTerms(query).map { word in
            var forms = [word]
            if let digits = numberWords[word] { forms.append(digits) }
            for group in bilingual where group.contains(word) { forms += group }
            forms += forms.compactMap(stem)
            forms = unique(forms)
            let fuzzy = forms.filter { $0.count >= 5 && $0.allSatisfy(\.isLetter) }
            return Term(word: word, forms: forms, fuzzyForms: fuzzy)
        }
    }

    /// Words of a note as matching sees them: folded tokens, number words also as digits, and
    /// each run of single numbers also joined ("5 6 7 8" → "5678"), so a spoken code is findable.
    public static func noteWords(_ text: String) -> [String] {
        noteWords(foldedTokens: SearchFolding.tokens(text))
    }

    static func noteWords(foldedTokens: [String]) -> [String] {
        var words: [String] = []
        var run = ""
        func closeRun() {
            if run.count > 1 { words.append(run) }
            run = ""
        }
        for token in foldedTokens {
            if let digits = numberWords[token] ?? (token.allSatisfy(\.isNumber) ? token : nil) {
                if digits != token { words.append(token) }
                words.append(digits)
                run += digits
            } else {
                closeRun()
                words.append(token)
            }
        }
        closeRun()
        return words
    }

    public static func matches(_ term: Term, _ noteWords: [String]) -> Bool {
        noteWords.contains { noteWord in
            term.forms.contains { noteWord.hasPrefix($0) }
                || term.fuzzyForms.contains { isTypo($0, of: noteWord) }
        }
    }

    /// Query words found in `text`, in query order.
    public static func matchedWords(_ terms: [Term], in text: String) -> [String] {
        Matcher(terms).matchedWords(in: text)
    }

    /// One search over many notes. Notes share most of their words, so each distinct word is
    /// checked against the query once and the answer reused (the typo check is the costly part).
    public final class Matcher {
        public let terms: [Term]
        private var known: [String: [Bool]] = [:]

        public init(_ terms: [Term]) {
            self.terms = terms
        }

        public func matchedWords(in text: String) -> [String] {
            matched(noteWords(text))
        }

        /// For text already folded by `SearchFolding.fold` (the stored `search_text`).
        public func matchedWords(inFolded text: String) -> [String] {
            matched(noteWords(foldedTokens: SearchFolding.tokens(folded: text)))
        }

        private func matched(_ words: [String]) -> [String] {
            var found = [Bool](repeating: false, count: terms.count)
            for word in words {
                let hits = known[word] ?? remember(word)
                for index in hits.indices where hits[index] { found[index] = true }
            }
            return terms.indices.filter { found[$0] }.map { terms[$0].word }
        }

        private func remember(_ word: String) -> [Bool] {
            let hits = terms.map { matches($0, [word]) }
            known[word] = hits
            return hits
        }
    }

    /// FTS5 pattern: every form as a prefix term, OR-ed. Forms are letters/digits only after
    /// folding, so quoting is safe. Typos and joined number runs are left to the scan.
    public static func ftsPattern(_ terms: [Term]) -> String? {
        let forms = unique(terms.flatMap(\.forms))
        return forms.isEmpty ? nil : forms.map { "\"\($0)\"*" }.joined(separator: " OR ")
    }

    // MARK: Rules

    /// Drops a likely inflection ending so other endings of the same word still prefix-match
    /// ("urodziny" → "urodzin", "paczkomat" → "paczkom"). One letter below 9 letters, two from
    /// 9, so short English words keep enough to stay specific ("dentist" never finds "density").
    static func stem(_ word: String) -> String? {
        guard word.count >= 6, word.allSatisfy(\.isLetter) else { return nil }
        return String(word.prefix(word.count - (word.count >= 9 ? 2 : 1)))
    }

    /// One edit (two for 8+ letters) between the query form and the note word, or the note
    /// word's beginning of the same length (so a typo plus a different ending still matches).
    static func isTypo(_ form: String, of noteWord: String) -> Bool {
        guard noteWord.allSatisfy(\.isLetter), abs(noteWord.count - form.count) <= 4 else { return false }
        let allowed = form.count >= 8 ? 2 : 1
        if editDistance(form, noteWord) <= allowed { return true }
        return noteWord.count > form.count && editDistance(form, String(noteWord.prefix(form.count))) <= allowed
    }

    /// Optimal string alignment distance (insert, delete, substitute, swap neighbours).
    /// Three rolling rows: the scan calls this for many word pairs.
    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var before = [Int](repeating: 0, count: b.count + 1)
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    current[j] = min(current[j], before[j - 2] + 1)
                }
            }
            (before, previous, current) = (previous, current, before)
        }
        return previous[b.count]
    }

    private static func unique(_ words: [String]) -> [String] {
        var seen = Set<String>()
        return words.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    // MARK: Word lists (folded: lowercase, no diacritics, ł → l)

    /// Spoken numbers 0–20 and tens, English and Polish (common case forms).
    static let numberWords: [String: String] = {
        let groups: [(String, [String])] = [
            ("0", ["zero"]),
            ("1", ["one", "jeden", "jedna", "jedno"]),
            ("2", ["two", "dwa", "dwie"]),
            ("3", ["three", "trzy"]),
            ("4", ["four", "cztery"]),
            ("5", ["five", "piec"]),
            ("6", ["six", "szesc"]),
            ("7", ["seven", "siedem"]),
            ("8", ["eight", "osiem"]),
            ("9", ["nine", "dziewiec"]),
            ("10", ["ten", "dziesiec"]),
            ("11", ["eleven", "jedenascie"]),
            ("12", ["twelve", "dwanascie"]),
            ("13", ["thirteen", "trzynascie"]),
            ("14", ["fourteen", "czternascie"]),
            ("15", ["fifteen", "pietnascie"]),
            ("16", ["sixteen", "szesnascie"]),
            ("17", ["seventeen", "siedemnascie"]),
            ("18", ["eighteen", "osiemnascie"]),
            ("19", ["nineteen", "dziewietnascie"]),
            ("20", ["twenty", "dwadziescia"]),
            ("30", ["thirty", "trzydziesci"]),
            ("40", ["forty", "czterdziesci"]),
            ("50", ["fifty", "piecdziesiat"]),
            ("60", ["sixty", "szescdziesiat"]),
            ("70", ["seventy", "siedemdziesiat"]),
            ("80", ["eighty", "osiemdziesiat"]),
            ("90", ["ninety", "dziewiecdziesiat"]),
            ("100", ["hundred", "sto"]),
        ]
        var map: [String: String] = [:]
        for (digits, words) in groups { for word in words { map[word] = digits } }
        return map
    }()

    /// English ↔ Polish words for things people typically save. A query word in a group also
    /// searches the rest of its group. Polish entries are base forms; stems cover the endings.
    static let bilingual: [[String]] = [
        ["code", "kod", "pin"],
        ["parcel", "package", "paczka", "przesylka", "paczkomat", "locker"],
        ["birthday", "urodziny"],
        ["anniversary", "rocznica"],
        ["key", "keys", "klucz", "klucze"],
        ["door", "drzwi"],
        ["gate", "brama", "furtka"],
        ["car", "samochod", "auto"],
        ["parking", "parked", "parkowanie", "zaparkowalem", "zaparkowalam"],
        ["address", "adres"],
        ["phone", "telefon", "numer", "number"],
        ["doctor", "lekarz", "doktor"],
        ["dentist", "dentysta"],
        ["appointment", "wizyta", "termin"],
        ["medicine", "medication", "lek", "leki", "tabletki"],
        ["flight", "lot"],
        ["passport", "paszport"],
        ["ticket", "bilet"],
        ["booking", "reservation", "rezerwacja"],
        ["hotel", "nocleg"],
        ["train", "pociag"],
        ["wifi", "internet", "siec"],
        ["bank", "konto", "account"],
        ["insurance", "ubezpieczenie", "polisa"],
        ["bill", "rachunek", "faktura", "invoice"],
        ["rent", "czynsz", "najem"],
        ["mother", "mom", "mum", "mama", "matka"],
        ["father", "dad", "tata", "ojciec"],
        ["wife", "zona"],
        ["husband", "maz"],
        ["son", "syn"],
        ["daughter", "corka"],
        ["brother", "brat"],
        ["sister", "siostra"],
        ["friend", "przyjaciel", "przyjaciolka", "kolega", "kolezanka"],
        ["boss", "szef", "szefowa"],
        ["work", "praca", "biuro", "office"],
        ["school", "szkola"],
        ["gift", "present", "prezent"],
        ["size", "rozmiar"],
        ["shoes", "buty"],
        ["allergy", "allergic", "alergia", "uczulenie"],
        ["recipe", "przepis"],
        ["book", "ksiazka"],
        ["film", "movie", "film"],
        ["restaurant", "restauracja"],
        ["shopping", "zakupy"],
        ["password", "haslo"],
    ]
}
