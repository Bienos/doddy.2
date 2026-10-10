import Foundation

// Meaning search (ADR-210): finds saved notes that are about the question without sharing its
// words ("sushi place Kasia liked" → "Kasia: the Japanese spot on Mokotowska is great").
//
// It never makes anything up: it only ranks notes that are really stored, returns them verbatim,
// and marks them as "may be related" so neither the screen nor the voice agent presents them as
// a word match. Vectors are computed on the iPhone by a `TextEmbedder` and cached in the same
// SQLite file as the notes; deleting a note deletes its vector. Nothing here touches the network.

/// Turns text into a vector on the device. Vectors from different `modelID`s are never compared.
public protocol TextEmbedder: Sendable {
    /// Changes whenever vectors would change (model, revision, pooling). Stored with each vector.
    var modelID: String { get }
    func embed(_ text: String) async throws -> [Float]
}

public enum MeaningSearchError: Error, Equatable, Sendable {
    /// The on-device language model is missing or could not be loaded. Word search still works.
    case modelUnavailable
    /// The model returned no usable vector for this text.
    case emptyVector
}

/// One note's cached vector. `textHash` is of the exact text that was embedded, so a corrected
/// note is embedded again instead of being ranked by its old words.
public struct MeaningVector: Equatable, Sendable {
    public let memoryID: UUID
    public let textHash: String
    public let values: [Float]

    public init(memoryID: UUID, textHash: String, values: [Float]) {
        self.memoryID = memoryID
        self.textHash = textHash
        self.values = values
    }
}

/// Where note vectors are kept. Derived data: never exported, removed with its note.
public protocol MemoryVectorStore: Sendable {
    /// Vectors made by `modelID` only.
    func vectors(modelID: String) async throws -> [MeaningVector]
    /// Adds or replaces the vector of each note (one per note; a new model's vector replaces the old).
    func store(_ vectors: [MeaningVector], modelID: String) async throws
    /// Deletes every vector (meaning search turned off).
    func removeAll() async throws
}

/// The fixed rules for what meaning search may return. Deterministic for a given set of vectors.
public struct MeaningPolicy: Equatable, Sendable {
    /// Most notes meaning search adds to one answer, on top of the word matches.
    public var maxResults: Int
    /// Below this many embedded notes nothing is returned: the "stands out from the rest" test
    /// below needs a crowd, and a short list is quicker to read than to search.
    public var minimumNotes: Int
    /// How far above the average note a match must be, in standard deviations of all the notes'
    /// scores. Relative, so it doesn't depend on the model's raw similarity range.
    public var minimumStandardScore: Double
    /// And it must be at least this close in absolute terms (cosine after centring).
    public var minimumSimilarity: Double
    /// Only the start of a long note is embedded.
    public var maxEmbeddedCharacters: Int
    /// Notes embedded during one search at most; the rest are embedded on later searches, so the
    /// first search after many new notes stays quick.
    public var maxNewVectorsPerSearch: Int

    public init(
        maxResults: Int = 3, minimumNotes: Int = 8, minimumStandardScore: Double = 1.5,
        minimumSimilarity: Double = 0.2, maxEmbeddedCharacters: Int = 1_000, maxNewVectorsPerSearch: Int = 200
    ) {
        self.maxResults = maxResults
        self.minimumNotes = minimumNotes
        self.minimumStandardScore = minimumStandardScore
        self.minimumSimilarity = minimumSimilarity
        self.maxEmbeddedCharacters = maxEmbeddedCharacters
        self.maxNewVectorsPerSearch = maxNewVectorsPerSearch
    }

    public static let standard = MeaningPolicy()
}

/// Pure maths and text rules, kept apart so they are tested without a model.
public enum MeaningRanking {
    /// The text that is embedded for a note: trimmed, at most `maxCharacters` characters.
    public static func embeddedText(_ text: String, maxCharacters: Int) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(max(0, maxCharacters)))
    }

    /// FNV-1a 64 of the embedded text: stable across runs and platforms (Swift's Hasher is not).
    public static func textHash(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return "v1-" + String(format: "%016llx", hash)
    }

    /// Whether a question has anything to search by meaning: at least one word that isn't a
    /// question or filler word ("what was that?" has none).
    public static func isSearchable(_ question: String) -> Bool {
        !SearchFolding.queryTerms(question).isEmpty
    }

    /// Cosine similarity; 0 for mismatched or zero-length vectors.
    public static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in a.indices {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        guard na > 0, nb > 0 else { return 0 }
        return dot / (na.squareRoot() * nb.squareRoot())
    }

    /// Scores every note against the question after subtracting the notes' average vector.
    /// Sentence vectors from general models all point roughly the same way; centring removes that
    /// shared direction so what is left is what makes a note different. Vectors whose length
    /// differs from the question's are skipped.
    public static func scores(question: [Float], notes: [MeaningVector]) -> [(id: UUID, score: Double)] {
        let usable = notes.filter { $0.values.count == question.count && !question.isEmpty }
        guard !usable.isEmpty else { return [] }
        var mean = [Double](repeating: 0, count: question.count)
        for note in usable {
            for i in mean.indices { mean[i] += Double(note.values[i]) }
        }
        for i in mean.indices { mean[i] /= Double(usable.count) }
        let q = question.indices.map { Double(question[$0]) - mean[$0] }
        return usable.map { note in
            (note.memoryID, cosine(q, note.values.indices.map { Double(note.values[$0]) - mean[$0] }))
        }
    }

    /// The notes that stand out: well above the average score of all notes, above the absolute
    /// floor, not excluded, best first (ties by id so the order is stable), at most `maxResults`.
    public static func select(
        _ scored: [(id: UUID, score: Double)], excluding: Set<UUID>, policy: MeaningPolicy
    ) -> [(id: UUID, score: Double)] {
        guard scored.count >= policy.minimumNotes, policy.maxResults > 0 else { return [] }
        let mean = scored.map(\.score).reduce(0, +) / Double(scored.count)
        let variance = scored.map { ($0.score - mean) * ($0.score - mean) }.reduce(0, +) / Double(scored.count)
        let deviation = variance.squareRoot()
        guard deviation > 1e-9 else { return [] } // every note equally close: nothing stands out
        return Array(scored
            .filter { !excluding.contains($0.id) }
            .filter { $0.score >= policy.minimumSimilarity && ($0.score - mean) / deviation >= policy.minimumStandardScore }
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.id.uuidString < $1.id.uuidString }
            .prefix(policy.maxResults))
    }
}

/// Keeps note vectors up to date and finds the notes closest in meaning to a question.
public actor MeaningIndex {
    private let embedder: any TextEmbedder
    private let store: any MemoryVectorStore
    public let policy: MeaningPolicy

    public init(embedder: any TextEmbedder, store: any MemoryVectorStore, policy: MeaningPolicy = .standard) {
        self.embedder = embedder
        self.store = store
        self.policy = policy
    }

    /// Notes from `records` related in meaning to `question`, best first, never one in `excluding`.
    /// Only real records are returned, unchanged; sample fixtures are never considered.
    public func related(to question: String, among records: [MemoryRecord], excluding: Set<UUID>) async throws -> [MemoryCandidate] {
        guard MeaningRanking.isSearchable(question) else { return [] }
        let eligible = records.filter { $0.source.isEligibleForPersonalRecall }
        guard eligible.count >= policy.minimumNotes else { return [] }

        let modelID = embedder.modelID
        var vectors = Dictionary(
            try await store.vectors(modelID: modelID).map { ($0.memoryID, $0) }, uniquingKeysWith: { first, _ in first })
        // Embed notes that are new or were corrected since, newest first (records arrive newest first).
        var fresh: [MeaningVector] = []
        for record in eligible {
            if fresh.count >= policy.maxNewVectorsPerSearch { break }
            let text = MeaningRanking.embeddedText(record.currentText, maxCharacters: policy.maxEmbeddedCharacters)
            let hash = MeaningRanking.textHash(text)
            guard vectors[record.id]?.textHash != hash else { continue }
            try Task.checkCancellation()
            let values = try await embedder.embed(text)
            guard !values.isEmpty else { throw MeaningSearchError.emptyVector }
            fresh.append(MeaningVector(memoryID: record.id, textHash: hash, values: values))
        }
        if !fresh.isEmpty {
            try await store.store(fresh, modelID: modelID)
            for vector in fresh { vectors[vector.memoryID] = vector }
        }

        // Only vectors that match the note's current text take part.
        var current: [MeaningVector] = []
        var byID: [UUID: MemoryRecord] = [:]
        for record in eligible {
            let text = MeaningRanking.embeddedText(record.currentText, maxCharacters: policy.maxEmbeddedCharacters)
            guard let vector = vectors[record.id], vector.textHash == MeaningRanking.textHash(text) else { continue }
            current.append(vector)
            byID[record.id] = record
        }
        guard current.count >= policy.minimumNotes else { return [] }

        try Task.checkCancellation()
        let questionVector = try await embedder.embed(
            MeaningRanking.embeddedText(question, maxCharacters: policy.maxEmbeddedCharacters))
        guard !questionVector.isEmpty else { throw MeaningSearchError.emptyVector }
        let chosen = MeaningRanking.select(
            MeaningRanking.scores(question: questionVector, notes: current), excluding: excluding, policy: policy)
        return chosen.compactMap { hit in
            byID[hit.id].map { MemoryCandidate(record: $0, matchedTerms: [], meaningScore: hit.score) }
        }
    }

    /// Deletes every cached vector (the user turned meaning search off).
    public func forgetAll() async throws {
        try await store.removeAll()
    }
}

/// Word search first, exactly as before; then, when meaning search is on, up to
/// `policy.maxResults` notes related in meaning that word search didn't find. A meaning-search
/// failure never fails recall: the word matches are returned on their own.
public struct HybridRecallService: RecallService {
    private let repository: any MemoryRepository
    private let words: RepositoryRecallService
    private let meaning: MeaningIndex?
    private let isMeaningEnabled: @Sendable () -> Bool

    public init(repository: any MemoryRepository, meaning: MeaningIndex?, isMeaningEnabled: @escaping @Sendable () -> Bool) {
        self.repository = repository
        self.words = RepositoryRecallService(repository: repository)
        self.meaning = meaning
        self.isMeaningEnabled = isMeaningEnabled
    }

    public func recall(_ question: String, limit: Int) async throws -> RecallOutcome {
        let wordOutcome = try await words.recall(question, limit: limit)
        var found: [MemoryCandidate] = []
        if case .matches(let matches) = wordOutcome { found = matches }
        guard let meaning, isMeaningEnabled(), limit > 0 else { return wordOutcome }
        do {
            let records = try await repository.list(limit: nil)
            let related = try await meaning.related(to: question, among: records, excluding: Set(found.map(\.memoryID)))
            found += related
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Model missing, vector store unreadable: word search alone answers.
            return wordOutcome
        }
        return found.isEmpty ? .noMatch : .matches(found)
    }
}
