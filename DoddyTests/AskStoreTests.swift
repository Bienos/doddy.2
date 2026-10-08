import XCTest
import DoddyAssistant
import DoddyCore
@testable import Doddy

/// App-target tests. NOT RUN in the authoring environment (no Xcode); see BUILD_AND_TEST.md.
@MainActor
final class AskStoreTests: XCTestCase {
    private struct StubRecall: RecallService {
        let candidates: [MemoryCandidate]
        func recall(_ question: String, limit: Int) async throws -> RecallOutcome {
            candidates.isEmpty ? .noMatch : .matches(candidates)
        }
    }

    private struct StubAssistant: AssistantClient {
        let result: Result<AssistantReply, AssistantError>
        func respond(_ request: AssistantRequest) async throws -> AssistantReply { try result.get() }
    }

    private func environment(candidates: [MemoryCandidate], result: Result<AssistantReply, AssistantError>) -> AppEnvironment {
        AppEnvironment(
            memoryRepository: UnavailableMemoryRepository(),
            recallService: StubRecall(candidates: candidates),
            assistantClient: StubAssistant(result: result),
            toolExecutor: UnavailableToolExecutor(),
            capabilities: .m1, privacy: .m0, storageProblem: nil)
    }

    private func candidate() throws -> MemoryCandidate {
        MemoryCandidate(
            record: try MemoryRecord(id: UUID(), rawText: "Charger is in the kitchen drawer.", source: .explicitText, capturedAt: Date(timeIntervalSince1970: 0)),
            matchedTerms: ["charger"])
    }

    private func finished(_ store: AskStore) async {
        for _ in 0..<200 where store.isSending { try? await Task.sleep(for: .milliseconds(10)) }
    }

    func testAnswerShowsOnlyCitedNotesThatWereSent() async throws {
        let c = try candidate()
        let store = AskStore(environment: environment(candidates: [c], result: .success(AssistantReply(text: "Kitchen drawer.", citedMemoryIDs: [c.memoryID]))))
        store.ask("Where is my charger?")
        await finished(store)
        XCTAssertEqual(store.phase, .answered(.init(text: "Kitchen drawer.", sources: [c.record])))
        XCTAssertEqual(store.notesSent, 1)
    }

    func testFailureShowsHonestMessageAndNoAnswer() async throws {
        let store = AskStore(environment: environment(candidates: [], result: .failure(.offline)))
        store.ask("hi")
        await finished(store)
        XCTAssertEqual(store.phase, .failed("You seem to be offline. Nothing was sent."))
    }

    func testUnavailableAssistantSaysSo() async {
        let store = AskStore(environment: .unavailable)
        store.ask("hi")
        await finished(store)
        XCTAssertEqual(store.phase, .failed("AI answers aren't available in this build."))
    }
}
