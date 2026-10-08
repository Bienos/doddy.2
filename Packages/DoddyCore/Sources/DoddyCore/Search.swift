import Foundation

/// Folding used for both indexing and querying, so "zolc" finds "żółć" and "Lodz" finds "Łódź".
public enum SearchFolding {
    /// Letters that Unicode does not decompose into base + diacritic.
    private static let extraFolds: [Character: String] = [
        "ł": "l", "đ": "d", "ø": "o", "ß": "ss", "æ": "ae", "œ": "oe", "ı": "i",
    ]

    private static let stopwords: Set<String> = [
        // English
        "a", "an", "the", "is", "was", "were", "what", "where", "when", "who", "how", "which",
        "that", "this", "it", "of", "to", "in", "on", "for", "and", "or", "my", "me", "i", "did",
        "do", "does", "with", "at", "be", "are", "from", "about", "again", "tell", "remind",
        // Polish
        "w", "z", "na", "do", "co", "to", "jak", "gdzie", "sie", "ze", "jest", "byl", "byla", "mi", "mnie",
    ]

    public static func fold(_ text: String) -> String {
        let base = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
        return String(base.flatMap { extraFolds[$0] ?? String($0) })
    }

    /// Folded word tokens, in order.
    public static func tokens(_ text: String) -> [String] {
        fold(text)
            .split(whereSeparator: { !($0.isLetter || $0.isNumber) })
            .map(String.init)
    }

    /// Distinct query terms with stopwords removed.
    public static func queryTerms(_ query: String) -> [String] {
        var seen = Set<String>()
        return tokens(query).filter { !stopwords.contains($0) && seen.insert($0).inserted }
    }

    /// Terms that prefix-match a word in `text` (same rule as the FTS `term*` query).
    public static func matchedTerms(_ terms: [String], in text: String) -> [String] {
        let words = tokens(text)
        return terms.filter { term in words.contains { $0.hasPrefix(term) } }
    }
}

/// Recall over the repository: returns real stored records or an explicit no-match.
/// Sample fixtures are never returned for personal recall.
public struct RepositoryRecallService: RecallService {
    private let repository: any MemoryRepository

    public init(repository: any MemoryRepository) {
        self.repository = repository
    }

    public func recall(_ question: String, limit: Int) async throws -> RecallOutcome {
        let candidates = try await repository.query(question, limit: limit)
            .filter { $0.record.source.isEligibleForPersonalRecall && !$0.matchedTerms.isEmpty }
        return candidates.isEmpty ? .noMatch : .matches(candidates)
    }
}

/// Export formats. JSON follows `schemas/memory.schema.json` per record.
public enum MemoryExport {
    public static let formatVersion = 1

    private struct Envelope: Encodable {
        let formatVersion: Int
        let exportedAtMs: Int64
        let memories: [MemoryRecord]
    }

    public static func json(_ records: [MemoryRecord], exportedAt: Date) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(Envelope(
            formatVersion: formatVersion,
            exportedAtMs: Int64((exportedAt.timeIntervalSince1970 * 1000).rounded()),
            memories: records))
    }

    public static func plainText(_ records: [MemoryRecord], exportedAt: Date) -> String {
        let iso = ISO8601DateFormatter()
        var lines = ["DODDY memories — exported \(iso.string(from: exportedAt))", "\(records.count) memories", ""]
        for record in records {
            lines.append("## \(record.currentText)")
            lines.append("Saved: \(record.capturedAt.map(iso.string(from:)) ?? "date unavailable")")
            lines.append("Source: \(record.source.rawValue) · Category: \(record.category.rawValue)")
            if record.userEdited {
                lines.append("Corrected: \(record.updatedAt.map(iso.string(from:)) ?? "date unavailable")")
                lines.append("Original: \(record.rawText)")
            }
            lines.append("ID: \(record.id.uuidString)")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
