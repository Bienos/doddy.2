import XCTest
@testable import DoddyCore

final class AssistantServiceTests: XCTestCase {
    private let allowed = AssistantPolicy(consentGranted: true, includeNotes: true)

    private func service(
        recall: FakeRecall = FakeRecall(.success(.noMatch)),
        client: FakeAssistantClient,
        sleeps: SleepRecorder = SleepRecorder()
    ) -> AssistantService {
        AssistantService(recall: recall, client: client, sleep: { await sleeps.record($0) })
    }

    // MARK: Consent and input (A-16)

    func testWithoutConsentNothingIsSearchedOrSent() async throws {
        let recalls = Counter()
        let client = FakeAssistantClient([.success(AssistantReply(text: "x"))])
        let sut = service(recall: FakeRecall(.success(.noMatch), onCall: { recalls.increment() }), client: client)

        do {
            _ = try await sut.ask("hello", sessionID: UUID(), policy: AssistantPolicy(consentGranted: false, includeNotes: true))
            XCTFail("expected consentRequired")
        } catch { XCTAssertEqual(error, .consentRequired) }
        let sent = await client.requests
        XCTAssertEqual(sent.count, 0)
        XCTAssertEqual(recalls.count, 0)
    }

    func testWithNotesSwitchedOffNoNoteIsSearchedOrSent() async throws {
        let recalls = Counter()
        let record = try makeRecord()
        let client = FakeAssistantClient([.success(AssistantReply(text: "General answer"))])
        let sut = service(
            recall: FakeRecall(.success(.matches([candidate(record)])), onCall: { recalls.increment() }), client: client)

        let answer = try await sut.ask("where is my car parked", sessionID: UUID(),
                                        policy: AssistantPolicy(consentGranted: true, includeNotes: false))
        XCTAssertEqual(recalls.count, 0)
        let sent = await client.requests
        XCTAssertTrue(sent[0].groundingMemories.isEmpty)
        XCTAssertTrue(answer.notesSent.isEmpty)
    }

    func testOnlyMatchedNotesAreSentAndShownBack() async throws {
        let record = try makeRecord()
        let client = FakeAssistantClient([.success(AssistantReply(text: "Level 3", citedMemoryIDs: [record.id]))])
        let sut = service(recall: FakeRecall(.success(.matches([candidate(record)]))), client: client)

        let answer = try await sut.ask("where is my car parked", sessionID: UUID(), policy: allowed)
        let sent = await client.requests
        XCTAssertEqual(sent[0].groundingMemories.map(\.memoryID), [record.id])
        XCTAssertEqual(answer.answer.sources, [record])
        XCTAssertEqual(answer.answer.basis, .savedNotes)
        XCTAssertEqual(answer.notesSent, [record])
    }

    func testBlankAndOversizedQuestionsAreRejectedBeforeAnyCall() async {
        let client = FakeAssistantClient([.success(AssistantReply(text: "x"))])
        let sut = service(client: client)
        for question in ["   ", "", String(repeating: "a", count: AssistantLimits.maxQuestionLength + 1)] {
            do {
                _ = try await sut.ask(question, sessionID: UUID(), policy: allowed)
                XCTFail("expected invalidRequest")
            } catch { XCTAssertEqual(error, .invalidRequest) }
        }
        let sent = await client.requests
        XCTAssertEqual(sent.count, 0)
    }

    func testNoteSearchFailureStillAsksAndSaysSo() async throws {
        struct Boom: Error {}
        let client = FakeAssistantClient([.success(AssistantReply(text: "General"))])
        let sut = service(recall: FakeRecall(.failure(Boom())), client: client)
        let answer = try await sut.ask("hi", sessionID: UUID(), policy: allowed)
        XCTAssertTrue(answer.notesSearchFailed)
        XCTAssertEqual(answer.answer.basis, .general)
    }

    // MARK: Citations (A-14)

    func testAnInvalidCitationDiscardsTheWholeAnswer() async throws {
        let record = try makeRecord()
        let client = FakeAssistantClient([.success(AssistantReply(text: "Made up", citedMemoryIDs: [UUID()]))])
        let sut = service(recall: FakeRecall(.success(.matches([candidate(record)]))), client: client)
        do {
            _ = try await sut.ask("where is my car parked", sessionID: UUID(), policy: allowed)
            XCTFail("expected invalidCitations")
        } catch { XCTAssertEqual(error, .invalidCitations) }
    }

    // MARK: Failures (A-15)

    func testTransientFailuresRetryWithBackoffThenSucceed() async throws {
        let client = FakeAssistantClient([
            .failure(AssistantError.providerUnavailable), .failure(AssistantError.timeout), .success(AssistantReply(text: "ok")),
        ])
        let sleeps = SleepRecorder()
        let answer = try await service(client: client, sleeps: sleeps).ask("hi", sessionID: UUID(), policy: allowed)
        XCTAssertEqual(answer.answer.text, "ok")
        let waits = await sleeps.waits
        XCTAssertEqual(waits, [.milliseconds(500), .milliseconds(1500)])
        let sent = await client.requests
        XCTAssertEqual(sent.count, 3)
        XCTAssertEqual(Set(sent.map(\.requestID)).count, 1, "retries reuse one request id")
    }

    func testRetriesStopAfterThreeAttempts() async {
        let client = FakeAssistantClient([.failure(AssistantError.providerUnavailable)])
        do {
            _ = try await service(client: client).ask("hi", sessionID: UUID(), policy: allowed)
            XCTFail("expected providerUnavailable")
        } catch { XCTAssertEqual(error, .providerUnavailable) }
        let sent = await client.requests
        XCTAssertEqual(sent.count, 3)
    }

    func testOfflineRateLimitRefusalAndAuthFailuresAreNotRetried() async {
        let cases: [AssistantError] = [.offline, .rateLimited(retryAfterSeconds: 12), .refused, .notAuthorized, .notConfigured]
        for expected in cases {
            let client = FakeAssistantClient([.failure(expected)])
            do {
                _ = try await service(client: client).ask("hi", sessionID: UUID(), policy: allowed)
                XCTFail("expected \(expected)")
            } catch { XCTAssertEqual(error, expected) }
            let sent = await client.requests
            XCTAssertEqual(sent.count, 1, "\(expected) must not be retried")
        }
    }

    func testUnknownErrorsBecomeProviderUnavailableAndUnavailableCapabilityBecomesNotConfigured() async {
        struct Strange: Error {}
        let unknown = FakeAssistantClient([.failure(Strange())])
        do { _ = try await service(client: unknown).ask("hi", sessionID: UUID(), policy: allowed) } catch {
            XCTAssertEqual(error, .providerUnavailable)
        }
        do { _ = try await service(client: FakeAssistantClient([.failure(DoddyError.capabilityUnavailable(.cloudAssistant))]))
            .ask("hi", sessionID: UUID(), policy: allowed) } catch { XCTAssertEqual(error, .notConfigured) }
    }

    func testCancellationIsReportedAsCancelled() async {
        let client = FakeAssistantClient([.failure(CancellationError())])
        do { _ = try await service(client: client).ask("hi", sessionID: UUID(), policy: allowed) } catch {
            XCTAssertEqual(error, .cancelled)
        }
    }

    func testAFailureNeverTouchesLocalMemory() async throws {
        // The service only reads through RecallService and has no write path at all (compile-time fact);
        // this documents it: after a failed ask the same notes are still recallable.
        let record = try makeRecord()
        let repository = try InMemoryRepositoryForTests(records: [record])
        let sut = AssistantService(
            recall: RepositoryRecallService(repository: repository),
            client: FakeAssistantClient([.failure(AssistantError.offline)]))
        do { _ = try await sut.ask("parked", sessionID: UUID(), policy: allowed) } catch { XCTAssertEqual(error, .offline) }
        let outcome = try await RepositoryRecallService(repository: repository).recall("parked", limit: 5)
        guard case .matches(let found) = outcome else { return XCTFail("notes must still be there") }
        XCTAssertEqual(found.map(\.memoryID), [record.id])
    }

    // MARK: Request shaping

    func testHistoryIsLimitedToTheLastSixNonBlankTurnsAndLongTurnsAreCut() async throws {
        let turns = (0..<10).map { ConversationTurn(role: $0.isMultiple(of: 2) ? .user : .assistant, text: "turn \($0)") }
            + [ConversationTurn(role: .assistant, text: "   ")]
        let long = ConversationTurn(role: .assistant, text: String(repeating: "é", count: 5_000))
        let client = FakeAssistantClient([.success(AssistantReply(text: "ok"))])
        _ = try await service(client: client).ask("hi", sessionID: UUID(), history: turns + [long], policy: allowed)
        let sent = await client.requests[0].recentTurns
        XCTAssertEqual(sent.count, AssistantLimits.maxTurns)
        XCTAssertEqual(sent.last?.text.unicodeScalars.count, AssistantLimits.maxQuestionLength)
        XCTAssertFalse(sent.contains { $0.text.allSatisfy(\.isWhitespace) })
    }

    func testLocaleIsSanitised() {
        XCTAssertEqual(AssistantService.safeLocale("pl"), "pl")
        XCTAssertEqual(AssistantService.safeLocale("pl-PL"), "pl-PL")
        for bad in ["", "English", "EN", "en_US", "e", "en-", "en-US-x-twain", "en\nUS"] {
            XCTAssertEqual(AssistantService.safeLocale(bad), "en", bad)
        }
    }
}

/// Minimal repository for the "failure leaves memory alone" check.
private struct InMemoryRepositoryForTests: MemoryRepository {
    let records: [MemoryRecord]
    init(records: [MemoryRecord]) throws { self.records = records }
    func save(_ draft: NewMemory) async throws -> MemoryRecord { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    func list(limit: Int?) async throws -> [MemoryRecord] { records }
    func query(_ query: String, limit: Int) async throws -> [MemoryCandidate] {
        let terms = SearchFolding.queryTerms(query)
        return records.compactMap { r in
            // Prefix match, the same simple rule the app's search used when this fake was written.
            let words = SearchFolding.tokens(r.currentText)
            let matched = terms.filter { term in words.contains { $0.hasPrefix(term) } }
            return matched.isEmpty ? nil : MemoryCandidate(record: r, matchedTerms: matched)
        }
    }
    func update(id: UUID, currentText: String) async throws -> MemoryRecord { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    func delete(id: UUID) async throws {}
    func deleteAll() async throws {}
    func export() async throws -> Data { Data() }
}
