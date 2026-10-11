import Foundation

// Find by meaning (ADR-227). Next to the word search, Find can show saved notes whose meaning is
// close to the question ("the place with good pierogi" → "Zapiecek, great dumplings"). The
// vectors come from Apple's on-device language model (NaturalLanguage); nothing is sent anywhere.
// Only saved notes are ranked, never lists or samples, and a hit is shown as "close in meaning,
// check it's the one", not as an answer.

/// Turns text into a vector on this iPhone. nil when the model isn't available for that text.
public protocol MeaningEmbedder: Sendable {
    func vector(for text: String) async -> [Float]?
}

public struct MeaningHit: Equatable, Sendable, Identifiable {
    public let record: MemoryRecord
    public let similarity: Float
    public var id: UUID { record.id }
}

public enum MeaningSearch {
    /// At most this many notes are shown.
    public static let maxHits = 5
    /// A hit must be at least this similar to the question…
    public static let minimumSimilarity: Float = 0.5
    /// …and stand out from the notes as a whole by this much, because sentence vectors from a
    /// contextual model sit close together even for unrelated text. Tuned on a device later.
    public static let marginOverAverage: Float = 0.08
    /// Notes this long or longer are cut before embedding (the model reads the start best).
    public static let maxCharacters = 1_000

    public static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in a.indices {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        guard na > 0, nb > 0 else { return 0 }
        return dot / (na.squareRoot() * nb.squareRoot())
    }

    /// Notes that may be eligible: saved notes only (no lists, no sample fixtures), with text.
    public static func eligible(_ records: [MemoryRecord]) -> [MemoryRecord] {
        records.filter {
            $0.category != .list && $0.source.isEligibleForPersonalRecall
                && !$0.currentText.allSatisfy(\.isWhitespace)
        }
    }

    /// The text that is embedded for a note.
    public static func text(of record: MemoryRecord) -> String {
        String(record.currentText.prefix(maxCharacters))
    }

    /// Ranks notes by meaning. `excluding` holds notes the word search already found, so the
    /// same note is never shown twice.
    public static func rank(
        query: [Float], notes: [(record: MemoryRecord, vector: [Float])], excluding: Set<UUID> = []
    ) -> [MeaningHit] {
        guard !notes.isEmpty else { return [] }
        let scored = notes.map { (record: $0.record, score: cosine(query, $0.vector)) }
        let average = scored.map(\.score).reduce(0, +) / Float(scored.count)
        return scored
            .filter { !excluding.contains($0.record.id) && $0.score >= minimumSimilarity && $0.score - average >= marginOverAverage }
            .sorted { $0.score > $1.score }
            .prefix(maxHits)
            .map { MeaningHit(record: $0.record, similarity: $0.score) }
    }
}

/// Vectors for saved notes, kept in memory and reused until a note's words change.
public actor MeaningIndex {
    private let embedder: any MeaningEmbedder
    private var cache: [UUID: (text: String, vector: [Float])] = [:]

    public init(embedder: any MeaningEmbedder) {
        self.embedder = embedder
    }

    /// Hits for the question among `records`, or [] when the model can't read the question.
    public func search(_ question: String, in records: [MemoryRecord], excluding: Set<UUID>) async -> [MeaningHit] {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3, let query = await embedder.vector(for: trimmed) else { return [] }
        let notes = MeaningSearch.eligible(records)
        let keep = Set(notes.map(\.id))
        cache = cache.filter { keep.contains($0.key) }
        var pairs: [(record: MemoryRecord, vector: [Float])] = []
        for note in notes {
            let text = MeaningSearch.text(of: note)
            if let cached = cache[note.id], cached.text == text {
                pairs.append((note, cached.vector))
            } else if let vector = await embedder.vector(for: text) {
                cache[note.id] = (text, vector)
                pairs.append((note, vector))
            }
        }
        return MeaningSearch.rank(query: query, notes: pairs, excluding: excluding)
    }

    /// Forgets every vector (Delete all, or the store reloaded from a backup).
    public func clear() { cache = [:] }
}
