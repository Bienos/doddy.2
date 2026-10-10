@testable import DoddyCore
import Foundation
import XCTest

/// Stand-in for the on-device model: each known word adds to one "topic" dimension, any other
/// word to one of four filler dimensions chosen by a stable hash. It makes the plumbing and the
/// selection rules testable on Linux; it says nothing about the real model's quality (that is
/// `DoddyTests/MeaningSearchCalibrationTests.swift`, Mac only).
final class TopicEmbedder: TextEmbedder, @unchecked Sendable {
    static let topics: [[String]] = [
        ["sushi", "japanese", "eat", "ramen", "dinner", "restaurant", "spot", "food"],
        ["car", "parked", "parking", "level", "garage"],
        ["dentist", "doctor", "allergy", "penicillin", "medicine", "allergic"],
        ["flight", "passport", "hotel", "trip", "fly"],
        ["wifi", "router", "internet"],
        ["birthday", "gift", "present", "wants"],
        ["boss", "meeting", "report", "deadline"],
    ]
    let modelID: String
    private let lock = NSLock()
    private var _calls: [String] = []
    var failing = false
    var calls: [String] { lock.withLock { _calls } }

    init(modelID: String = "test.topics.v1") { self.modelID = modelID }

    func embed(_ text: String) async throws -> [Float] {
        lock.withLock { _calls.append(text) }
        if failing { throw MeaningSearchError.modelUnavailable }
        var vector = [Float](repeating: 0, count: Self.topics.count + 4)
        for word in SearchFolding.tokens(text) {
            if let topic = Self.topics.firstIndex(where: { $0.contains(word) }) {
                vector[topic] += 1
            } else {
                vector[Self.topics.count + Int(word.utf8.reduce(0) { ($0 &* 31 &+ Int($1)) & 0xffff } % 4)] += 0.2
            }
        }
        return vector
    }
}

actor InMemoryVectorStore: MemoryVectorStore {
    private var rows: [UUID: (model: String, vector: MeaningVector)] = [:]
    private(set) var storeCalls = 0

    func vectors(modelID: String) -> [MeaningVector] {
        rows.values.filter { $0.model == modelID }.map(\.vector)
    }

    func store(_ vectors: [MeaningVector], modelID: String) {
        storeCalls += 1
        for vector in vectors { rows[vector.memoryID] = (modelID, vector) }
    }

    func removeAll() { rows = [:] }
    var count: Int { rows.count }
}

/// A repository over fixed records; `query` uses the real word rules so hybrid tests see the
/// same word matches the SQLite store would give.
actor FixedRepository: MemoryRepository {
    var records: [MemoryRecord]
    init(_ records: [MemoryRecord]) { self.records = records }

    func replace(_ record: MemoryRecord) {
        records = records.map { $0.id == record.id ? record : $0 }
    }

    func list(limit: Int?) -> [MemoryRecord] { limit.map { Array(records.prefix($0)) } ?? records }
    func query(_ query: String, limit: Int) -> [MemoryCandidate] {
        let matcher = RecallMatching.Matcher(RecallMatching.terms(query))
        return Array(records.compactMap { record in
            let words = matcher.matchedWords(in: record.currentText)
            return words.isEmpty ? nil : MemoryCandidate(record: record, matchedTerms: words)
        }.prefix(limit))
    }
    func save(_ draft: NewMemory) throws -> MemoryRecord { throw MemoryStoreError.verificationFailed }
    func update(id: UUID, currentText: String) throws -> MemoryRecord { throw MemoryStoreError.verificationFailed }
    func setCategory(id: UUID, to category: MemoryCategory) throws -> MemoryRecord { throw MemoryStoreError.verificationFailed }
    func delete(id: UUID) throws { throw MemoryStoreError.verificationFailed }
    func deleteAll() throws { throw MemoryStoreError.verificationFailed }
    func export() throws -> Data { Data() }
    func restore(_ records: [MemoryRecord]) throws -> [MemoryRecord] { [] }
}

final class MeaningRecallTests: XCTestCase {
    /// Ten synthetic notes on different topics, newest first.
    private func corpus() throws -> [MemoryRecord] {
        try [
            "Kasia says the sushi spot on Mokotowska is great",
            "Parked on level 3 of the garage, row C",
            "Allergic to penicillin",
            "Passport expires in March 2027",
            "Router password is on the sticker under the box",
            "Marta wants a pottery class as a birthday present",
            "Boss moved the report deadline to Friday",
            "Spare keys in the blue tin above the fridge",
            "Plumber Adam, Tuesday morning",
            "Gym closes at 21 on Sundays",
        ].enumerated().map { index, text in
            try makeRecord(text, capturedAt: Date(timeIntervalSince1970: 1_790_000_000 - Double(index) * 3600))
        }
    }

    private func index(_ embedder: TopicEmbedder, _ store: InMemoryVectorStore = InMemoryVectorStore(),
                       policy: MeaningPolicy = .standard) -> MeaningIndex {
        MeaningIndex(embedder: embedder, store: store, policy: policy)
    }

    // MARK: Finding by meaning

    func testFindsANoteByMeaningWithoutASharedWord() async throws {
        let records = try corpus()
        let related = try await index(TopicEmbedder()).related(
            to: "where should we go for japanese food", among: records, excluding: [])
        XCTAssertEqual(related.map(\.record), [records[0]], "the real stored record, unchanged")
        XCTAssertTrue(related[0].isMeaningMatch)
        XCTAssertEqual(related[0].matchedTerms, [])
        XCTAssertNotNil(related[0].meaningScore)
    }

    func testQuestionWithOnlyFillerWordsSearchesNothing() async throws {
        let embedder = TopicEmbedder()
        let related = try await index(embedder).related(to: "what was that?", among: try corpus(), excluding: [])
        XCTAssertEqual(related, [])
        XCTAssertEqual(embedder.calls, [], "nothing is embedded for a question with no real word")
    }

    func testTooFewNotesReturnsNothing() async throws {
        let records = Array(try corpus().prefix(MeaningPolicy.standard.minimumNotes - 1))
        let related = try await index(TopicEmbedder()).related(to: "japanese food", among: records, excluding: [])
        XCTAssertEqual(related, [])
    }

    func testSampleFixturesAreNeverReturnedOrEmbedded() async throws {
        var records = try corpus()
        let sample = try makeRecord("Sample: the best ramen place is Ichiraku", source: .sampleFixture)
        records.insert(sample, at: 0)
        let embedder = TopicEmbedder()
        let related = try await index(embedder).related(to: "japanese food", among: records, excluding: [])
        XCTAssertFalse(related.contains { $0.memoryID == sample.id })
        XCTAssertFalse(embedder.calls.contains(sample.currentText))
    }

    func testExcludedNotesAreNotReturned() async throws {
        let records = try corpus()
        let related = try await index(TopicEmbedder()).related(
            to: "japanese food", among: records, excluding: [records[0].id])
        XCTAssertFalse(related.contains { $0.memoryID == records[0].id })
    }

    // MARK: The vector cache

    func testVectorsAreCachedAndOnlyNewOrCorrectedNotesAreEmbeddedAgain() async throws {
        var records = try corpus()
        let embedder = TopicEmbedder()
        let store = InMemoryVectorStore()
        let meaning = index(embedder, store)

        _ = try await meaning.related(to: "japanese food", among: records, excluding: [])
        XCTAssertEqual(embedder.calls.count, records.count + 1, "every note once, then the question")
        let storedCount = await store.count
        XCTAssertEqual(storedCount, records.count)

        _ = try await meaning.related(to: "car parking", among: records, excluding: [])
        XCTAssertEqual(embedder.calls.count, records.count + 2, "second search embeds only the question")

        records[1] = try records[1].correcting(to: "Parked on level 4 of the garage, row D", at: Date(timeIntervalSince1970: 1_790_100_000))
        let related = try await meaning.related(to: "where is my car", among: records, excluding: [])
        XCTAssertEqual(embedder.calls.count, records.count + 4, "the corrected note and the question")
        XCTAssertTrue(embedder.calls.contains("Parked on level 4 of the garage, row D"))
        XCTAssertEqual(related.first?.record.currentText, "Parked on level 4 of the garage, row D", "ranked by its new words")
    }

    func testVectorsFromAnotherModelAreIgnored() async throws {
        let records = try corpus()
        let store = InMemoryVectorStore()
        _ = try await index(TopicEmbedder(modelID: "old"), store).related(to: "japanese food", among: records, excluding: [])
        let newer = TopicEmbedder(modelID: "new")
        _ = try await index(newer, store).related(to: "japanese food", among: records, excluding: [])
        XCTAssertEqual(newer.calls.count, records.count + 1, "every note embedded again by the new model")
    }

    func testNewVectorsPerSearchAreCapped() async throws {
        let records = try corpus()
        var policy = MeaningPolicy.standard
        policy.maxNewVectorsPerSearch = 4
        let embedder = TopicEmbedder()
        let store = InMemoryVectorStore()
        let meaning = index(embedder, store, policy: policy)
        let first = try await meaning.related(to: "japanese food", among: records, excluding: [])
        XCTAssertEqual(first, [], "4 of 10 notes embedded is below the minimum, so nothing is returned yet")
        XCTAssertEqual(embedder.calls.count, 4, "no question embedded when too few notes are ready")
        for _ in 0..<2 { _ = try await meaning.related(to: "japanese food", among: records, excluding: []) }
        let storedCount = await store.count
        XCTAssertEqual(storedCount, records.count, "later searches finish the job")
    }

    func testForgetAllEmptiesTheStore() async throws {
        let store = InMemoryVectorStore()
        let meaning = index(TopicEmbedder(), store)
        _ = try await meaning.related(to: "japanese food", among: try corpus(), excluding: [])
        try await meaning.forgetAll()
        let storedCount = await store.count
        XCTAssertEqual(storedCount, 0)
    }

    // MARK: Hybrid recall

    func testWordMatchesComeFirstAndMeaningAddsOthers() async throws {
        let records = try corpus()
        let service = HybridRecallService(
            repository: FixedRepository(records), meaning: index(TopicEmbedder()), isMeaningEnabled: { true })
        guard case .matches(let found) = try await service.recall("Kasia japanese food", limit: 20) else {
            return XCTFail("expected matches")
        }
        XCTAssertEqual(found.first?.memoryID, records[0].id)
        XCTAssertEqual(found.first?.matchedTerms, ["kasia"], "a word match stays a word match")
        XCTAssertFalse(found.first?.isMeaningMatch ?? true)
        XCTAssertEqual(Set(found.map(\.memoryID)).count, found.count, "no note twice")
    }

    func testMeaningOnlyMatchesAreReturnedWhenNoWordMatches() async throws {
        let records = try corpus()
        let service = HybridRecallService(
            repository: FixedRepository(records), meaning: index(TopicEmbedder()), isMeaningEnabled: { true })
        guard case .matches(let found) = try await service.recall("japanese food", limit: 20) else {
            return XCTFail("expected a meaning match")
        }
        XCTAssertEqual(found.map(\.memoryID), [records[0].id])
        XCTAssertTrue(found.allSatisfy(\.isMeaningMatch))
    }

    func testMeaningSearchOffNeverEmbeds() async throws {
        let embedder = TopicEmbedder()
        let service = HybridRecallService(
            repository: FixedRepository(try corpus()), meaning: index(embedder), isMeaningEnabled: { false })
        let outcome = try await service.recall("japanese food", limit: 20)
        XCTAssertEqual(outcome, .noMatch)
        XCTAssertEqual(embedder.calls, [])
    }

    func testModelFailureFallsBackToWordSearch() async throws {
        let records = try corpus()
        let embedder = TopicEmbedder()
        embedder.failing = true
        let service = HybridRecallService(
            repository: FixedRepository(records), meaning: index(embedder), isMeaningEnabled: { true })
        let words = try await service.recall("Kasia", limit: 20)
        guard case .matches(let found) = words else { return XCTFail("word match expected") }
        XCTAssertEqual(found.map(\.memoryID), [records[0].id])
        let none = try await service.recall("japanese food", limit: 20)
        XCTAssertEqual(none, .noMatch, "no guess when the model is missing")
    }

    // MARK: Ranking rules

    func testSelectNeedsToStandOutFromTheCrowd() {
        let ids = (0..<10).map { _ in UUID() }
        let flat = ids.map { (id: $0, score: 0.5) }
        XCTAssertEqual(MeaningRanking.select(flat, excluding: [], policy: .standard).count, 0, "all equal: nothing stands out")

        var scored = ids.map { (id: $0, score: 0.1) }
        scored[3].score = 0.9
        let chosen = MeaningRanking.select(scored, excluding: [], policy: .standard)
        XCTAssertEqual(chosen.map(\.id), [ids[3]])

        var lowFloor = scored
        lowFloor[3].score = 0.15
        for index in lowFloor.indices where index != 3 { lowFloor[index].score = 0.01 }
        XCTAssertEqual(MeaningRanking.select(lowFloor, excluding: [], policy: .standard).count, 0,
                       "standing out isn't enough below the absolute floor")
    }

    func testSelectCapsAndOrdersResultsStably() {
        let ids = (0..<20).map { _ in UUID() }
        var scored = ids.map { (id: $0, score: 0.0) }
        for index in 0..<4 { scored[index].score = 0.9 }
        let chosen = MeaningRanking.select(scored, excluding: [], policy: .standard)
        XCTAssertEqual(chosen.count, 3)
        XCTAssertEqual(chosen.map(\.id), ids.prefix(4).sorted { $0.uuidString < $1.uuidString }.prefix(3).map { $0 })

        var crowded = ids.map { (id: $0, score: 0.0) }
        for index in 0..<8 { crowded[index].score = 0.9 }
        XCTAssertEqual(MeaningRanking.select(crowded, excluding: [], policy: .standard).count, 0,
                       "when many notes are equally close, none stands out and nothing is offered")
    }

    func testCosineAndCentring() {
        XCTAssertEqual(MeaningRanking.cosine([1, 0], [1, 0]), 1, accuracy: 1e-12)
        XCTAssertEqual(MeaningRanking.cosine([1, 0], [0, 1]), 0, accuracy: 1e-12)
        XCTAssertEqual(MeaningRanking.cosine([1, 0], [1, 0, 0]), 0, "different lengths never compare")
        XCTAssertEqual(MeaningRanking.cosine([0, 0], [1, 0]), 0)
        // Both notes share a large common direction; after centring the question picks the right one.
        let a = MeaningVector(memoryID: UUID(), textHash: "a", values: [10, 1, 0])
        let b = MeaningVector(memoryID: UUID(), textHash: "b", values: [10, 0, 1])
        let scores = MeaningRanking.scores(question: [10, 1, 0], notes: [a, b])
        XCTAssertGreaterThan(scores[0].score, 0.99)
        XCTAssertLessThan(scores[1].score, -0.99)
        XCTAssertEqual(MeaningRanking.scores(question: [1, 2], notes: [a]).count, 0, "wrong dimension skipped")
    }

    func testEmbeddedTextAndHash() {
        XCTAssertEqual(MeaningRanking.embeddedText("  hello \n", maxCharacters: 1000), "hello")
        XCTAssertEqual(MeaningRanking.embeddedText("żółć abc", maxCharacters: 4), "żółć")
        XCTAssertEqual(MeaningRanking.textHash("Parked on level 3"), MeaningRanking.textHash("Parked on level 3"))
        XCTAssertNotEqual(MeaningRanking.textHash("Parked on level 3"), MeaningRanking.textHash("Parked on level 4"))
        XCTAssertEqual(MeaningRanking.textHash(""), "v1-cbf29ce484222325", "FNV-1a offset basis: stable across platforms")
        XCTAssertFalse(MeaningRanking.isSearchable("what was that?"))
        XCTAssertFalse(MeaningRanking.isSearchable("co to jest?"), "Polish filler words too")
        XCTAssertTrue(MeaningRanking.isSearchable("gdzie zaparkowałem?"))
    }

    // MARK: What leaves the recall layer

    func testMeaningMatchesNeverGoToTheTypedAssistant() throws {
        let word = candidate(try makeRecord("Parked on level 3"))
        let meaning = MemoryCandidate(record: try makeRecord("Garage row C"), matchedTerms: [], meaningScore: 0.8)
        XCTAssertEqual(GroundingSelector.select(from: [meaning, word]).map(\.memoryID), [word.memoryID],
                       "only word matches are sent to the gateway; meaning search adds no egress")
    }

    func testMeaningMatchesAreNotCheckedForConflicts() throws {
        let a = MemoryCandidate(record: try makeRecord("Gate code 1234"), matchedTerms: [], meaningScore: 0.9)
        let b = MemoryCandidate(record: try makeRecord("Gate code 5678"), matchedTerms: [], meaningScore: 0.8)
        XCTAssertEqual(RecallConflicts.flagged([a, b]), [])
    }
}
