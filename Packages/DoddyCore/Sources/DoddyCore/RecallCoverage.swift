import Foundation

/// How much of a question the found notes cover (ADR-213). Recall lists every note that shares
/// a word with the question, so "netflix password" lists the wifi passwords. Those notes are
/// real and stay listed, but when no note covers the whole question the answer says so, and
/// names the words no note has, instead of presenting them as the answer.
///
/// A question is split into *ideas*: its search words, with words that are each other's
/// translation or number form joined ("kod" and "code", "five" and "5"), because the voice agent
/// searches in both languages at once. A note covers an idea when it matched any word of it.
public struct RecallCoverage: Equatable, Sendable {
    /// One idea of the question: its words as the user wrote them (lowercased), in order.
    public struct Idea: Equatable, Sendable {
        public let words: [String]
        /// "netflix", or "kod / code" for an idea asked in two languages.
        public var label: String { words.joined(separator: " / ") }
    }

    public let ideas: [Idea]
    /// Ideas that no found note covers.
    public let missing: [Idea]
    /// Notes that cover every idea.
    public let completeMatches: Set<UUID>

    /// Matches were found, but none covers the whole question.
    public var isPartial: Bool { completeMatches.isEmpty }

    public init(question: String, candidates: [MemoryCandidate]) {
        let terms = RecallMatching.terms(question)
        let ideas = Self.ideas(terms)
        let surface = Self.surfaceWords(question)
        let labelled = ideas.map { Idea(words: $0.map { surface[terms[$0].word] ?? terms[$0].word }) }
        let ideaWords = ideas.map { Set($0.map { terms[$0].word }) }
        func covers(_ candidate: MemoryCandidate, _ idea: Int) -> Bool {
            !ideaWords[idea].isDisjoint(with: candidate.matchedTerms)
        }
        self.ideas = labelled
        missing = ideas.indices.filter { idea in !candidates.contains { covers($0, idea) } }.map { labelled[$0] }
        completeMatches = Set(candidates.filter { candidate in ideas.indices.allSatisfy { covers(candidate, $0) } }
            .map(\.memoryID))
    }

    /// Indices into `terms`, grouped: two terms are one idea when one's forms include the other's
    /// word (counterparts from the fixed word list, number words and digits). Kept in question order.
    static func ideas(_ terms: [RecallMatching.Term]) -> [[Int]] {
        var groups: [[Int]] = []
        for index in terms.indices {
            let term = terms[index]
            let related = groups.indices.filter { group in
                groups[group].contains { terms[$0].forms.contains(term.word) || term.forms.contains(terms[$0].word) }
            }
            guard let first = related.first else { groups.append([index]); continue }
            // A word can join two ideas together; merge them, keeping question order.
            for group in related.dropFirst().reversed() { groups[first] += groups.remove(at: group) }
            groups[first] = (groups[first] + [index]).sorted()
        }
        return groups
    }

    /// Folded search word → the word as typed, lowercased ("wywoz" → "wywóz").
    static func surfaceWords(_ question: String) -> [String: String] {
        var words: [String: String] = [:]
        for token in question.split(whereSeparator: { !($0.isLetter || $0.isNumber) }) {
            let folded = SearchFolding.fold(String(token))
            if words[folded] == nil { words[folded] = token.lowercased() }
        }
        return words
    }
}

extension RecallCopy {
    /// Headline and explanation for matches that cover only part of the question.
    public static func partial(_ coverage: RecallCoverage) -> (headline: String, detail: String) {
        let quoted = { (ideas: [RecallCoverage.Idea]) in ideas.map { "“\($0.label)”" }.joined(separator: ", ") }
        let found = coverage.ideas.filter { !coverage.missing.contains($0) }
        guard !coverage.missing.isEmpty else {
            return ("No single note has all of that.",
                    "Each note below matches only part of what you asked. Check them before relying on one.")
        }
        let detail = found.isEmpty
            ? "Check them before relying on one."
            : "The notes below match only \(quoted(found)). Check them before relying on one."
        return ("No saved note mentions \(quoted(coverage.missing)).", detail)
    }
}
