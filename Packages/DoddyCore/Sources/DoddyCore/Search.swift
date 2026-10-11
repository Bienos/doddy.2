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
        "have", "has", "had", "you", "your", "know", "any", "some", "there", "can", "could", "please",
        // Polish
        "w", "z", "na", "do", "co", "to", "jak", "gdzie", "sie", "ze", "jest", "byl", "byla", "mi", "mnie",
        "kiedy", "jaki", "jaka", "jakie", "jakiego", "mam", "moj", "moja", "moje", "mojej", "mojego",
        "czy", "ten", "ta", "tego", "o", "od", "po", "dla", "ile", "sa", "juz", "jeszcze", "pamietasz",
        // Question filler: how people ask about a note, not what the note says (ADR-235).
        // Left in, a note never contains them, so every answer would look partial.
        "say", "said", "says", "told", "anything", "something", "put", "leave", "save", "saved",
        "remember", "find",
        "ma", "mial", "miala", "przez", "cos", "czegos", "gdzies", "ktory", "ktora", "ktore",
        "powiedzial", "powiedziala", "mowil", "mowila", "zapisalem", "zapisalam",
        "zostawilem", "zostawilam", "polozylem", "polozylam",
    ]

    public static func fold(_ text: String) -> String {
        let base = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
        return String(base.flatMap { extraFolds[$0] ?? String($0) })
    }

    /// Folded word tokens, in order.
    public static func tokens(_ text: String) -> [String] {
        tokens(folded: fold(text))
    }

    /// Tokens of text that is already folded (the stored `search_text` column).
    public static func tokens(folded text: String) -> [String] {
        text.split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map(String.init)
    }

    /// Distinct query terms with stopwords and single letters removed. A lone letter is almost
    /// always the "s" of "what's"/"Jake's" or an initial, and as a prefix it matches nearly every
    /// note (ADR-234). Single digits stay: "5" can be part of a code.
    public static func queryTerms(_ query: String) -> [String] {
        var seen = Set<String>()
        return tokens(query).filter { token in
            !stopwords.contains(token) && !(token.count == 1 && token.allSatisfy(\.isLetter))
                && seen.insert(token).inserted
        }
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
            .filter { $0.record.source.isEligibleForPersonalRecall && !$0.matchedTerms.isEmpty && $0.record.category != .list }
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
        /// Items of the `list` records (ADR-216); left out when there are none.
        let listItems: [ListItem]?
        /// Every correction of the exported notes (ADR-236); left out when there are none. Added
        /// within format 1: older readers ignore it and restore the notes without their history.
        let corrections: [MemoryCorrection]?
    }

    public static func json(
        _ records: [MemoryRecord], listItems: [ListItem] = [], corrections: [MemoryCorrection] = [], exportedAt: Date
    ) throws -> Data {
        let ids = Set(records.map(\.id))
        let history = corrections.filter { ids.contains($0.memoryID) }
            .sorted { ($0.memoryID.uuidString, $0.number) < ($1.memoryID.uuidString, $1.number) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(Envelope(
            formatVersion: formatVersion,
            exportedAtMs: Int64((exportedAt.timeIntervalSince1970 * 1000).rounded()),
            memories: records,
            listItems: listItems.isEmpty ? nil : listItems,
            corrections: history.isEmpty ? nil : history))
    }

    /// Wordings between the original and the current one, oldest first (ADR-236).
    static func inBetween(_ record: MemoryRecord, _ byNote: [UUID: [MemoryCorrection]]) -> [MemoryVersion] {
        MemoryHistory(record: record, corrections: byNote[record.id] ?? []).versions.filter { !$0.isOriginal && !$0.isCurrent }
    }

    public static func plainText(
        _ records: [MemoryRecord], lists: [DoddyList] = [], corrections: [MemoryCorrection] = [], exportedAt: Date
    ) -> String {
        let byNote = Dictionary(grouping: corrections, by: \.memoryID)
        let iso = ISO8601DateFormatter()
        var lines = ["DODDY memories — exported \(iso.string(from: exportedAt))", "\(records.count) memories", ""]
        for record in records {
            lines.append("## \(record.currentText)")
            lines.append("Saved: \(record.capturedAt.map(iso.string(from:)) ?? "date unavailable")")
            lines.append("Source: \(record.source.rawValue) · Category: \(record.category.rawValue)")
            if record.userEdited {
                lines.append("Corrected: \(record.updatedAt.map(iso.string(from:)) ?? "date unavailable")")
                for version in inBetween(record, byNote).reversed() {
                    lines.append("Earlier (\(version.savedAt.map(iso.string(from:)) ?? "date unavailable")): \(version.text)")
                }
                lines.append("Original: \(record.rawText)")
            }
            lines.append("ID: \(record.id.uuidString)")
            lines.append("")
        }
        if !lists.isEmpty {
            lines.append("# Lists (\(lists.count))")
            lines.append("")
            for list in lists {
                lines.append("## \(list.name)")
                lines.append(contentsOf: list.open.map { "[ ] \($0.text)" })
                lines.append(contentsOf: list.done.map { "[x] \($0.text)" })
                lines.append("ID: \(list.id.uuidString)")
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }
}
