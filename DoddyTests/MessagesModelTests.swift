import DoddyCore
import Foundation
import XCTest
#if canImport(Doddy)
@testable import Doddy
#endif

// The thread with Doddy (ADR-585): a message is saved before it is sent, an answer is saved only when it
// arrived, a message nobody answered stays in the thread and can be sent again, nothing is saved or sent
// while Ask Doddy is off, and deleting is claimed only when it read back. Fakes stand in for the store and
// the server. Also run on Linux by scripts/test_messages_model.sh.

final class MessagesModelTests: XCTestCase {
    private let on = AssistantPolicy(consentGranted: true, includeNotes: false)
    private let t0 = Date(timeIntervalSince1970: 1_792_000_000)

    @MainActor
    private func loaded(_ repository: FakeThread = FakeThread(), client: ScriptedClient = ScriptedClient(), clock: TickingClock = TickingClock()) async -> (MessagesModel, FakeThread, ScriptedClient, AssistantService) {
        let model = MessagesModel(repository: repository, now: { clock.tick() })
        await model.load()
        let service = AssistantService(recall: NoNotes(), client: client, backoff: [], sleep: { _ in })
        return (model, repository, client, service)
    }

    @MainActor
    private func settle(_ model: MessagesModel) async {
        for _ in 0..<400 where model.isSending { try? await Task.sleep(for: .milliseconds(10)) }
    }

    @MainActor
    func testASentMessageIsSavedThenAnswered() async throws {
        let (model, repository, client, service) = await loaded(client: ScriptedClient([.reply("Piątek, 9:00.")]))
        model.draft = "  Kiedy dentysta?  "
        model.send(using: service, policy: on, locale: "pl")
        XCTAssertEqual(model.draft, "", "the box is emptied once the message is in the thread")
        XCTAssertEqual(model.messages.map(\.text), ["Kiedy dentysta?"], "trimmed")
        XCTAssertEqual(model.messages.first?.delivery, .sending)
        XCTAssertTrue(model.isSending)
        XCTAssertFalse(model.canSend, "one message at a time")

        await settle(model)
        XCTAssertEqual(model.messages.map(\.sender), [.user, .doddy])
        XCTAssertEqual(model.messages.map(\.delivery), [.sent, .sent])
        XCTAssertEqual(model.messages.last?.basis, .general)
        let saved = await repository.all()
        XCTAssertEqual(saved, model.messages, "what is on screen is what was saved")
        let requests = await client.requests
        XCTAssertEqual(requests.map(\.userText), ["Kiedy dentysta?"])
        XCTAssertEqual(model.storage, .saving)
    }

    @MainActor
    func testNothingIsSavedOrSentWhileAskDoddyIsOffOrNotSetUp() async {
        let (model, repository, client, service) = await loaded()
        model.draft = "Co mam jutro?"
        model.send(using: service, policy: AssistantPolicy(consentGranted: false, includeNotes: true), locale: "pl")
        XCTAssertEqual(model.error, .consentRequired)
        XCTAssertEqual(model.draft, "Co mam jutro?", "the words stay in the box")
        XCTAssertTrue(model.messages.isEmpty)

        model.send(using: nil, policy: on, locale: "pl")
        XCTAssertEqual(model.error, .notConfigured)
        XCTAssertEqual(model.draft, "Co mam jutro?")

        model.draft = String(repeating: "a", count: AssistantLimits.maxQuestionLength + 1)
        model.send(using: service, policy: on, locale: "pl")
        XCTAssertEqual(model.error, .invalidRequest)
        XCTAssertEqual(model.draft.count, AssistantLimits.maxQuestionLength + 1)

        let saved = await repository.all()
        let requests = await client.requests
        XCTAssertTrue(saved.isEmpty)
        XCTAssertTrue(requests.isEmpty)
    }

    @MainActor
    func testAMessageWithNoAnswerStaysInTheThreadAndCanBeSentAgainAtTheEnd() async throws {
        let (model, repository, _, service) = await loaded(client: ScriptedClient([.fail(.offline), .reply("Jest.")]))
        model.draft = "Czy działa?"
        model.send(using: service, policy: on, locale: "pl")
        await settle(model)
        XCTAssertEqual(model.error, .offline)
        XCTAssertEqual(model.messages.map(\.delivery), [.failed])
        var saved = await repository.all()
        XCTAssertEqual(saved.map(\.delivery), [.failed], "kept as not answered, not dropped")
        XCTAssertTrue(ThreadRules.canRetry(model.messages[0]))

        let failedID = model.messages[0].id
        model.retry(failedID, using: service, policy: on, locale: "pl")
        await settle(model)
        XCTAssertEqual(model.messages.map(\.text), ["Czy działa?", "Jest."])
        XCTAssertNotEqual(model.messages[0].id, failedID, "sent again as a new message")
        XCTAssertNil(model.error)
        saved = await repository.all()
        XCTAssertEqual(saved, model.messages)
        XCTAssertEqual(saved.filter { $0.delivery == .failed }.count, 0)
    }

    @MainActor
    func testStoppingLeavesTheMessageNotAnsweredWithoutAnErrorCard() async {
        let (model, repository, _, service) = await loaded(client: ScriptedClient([.hang]))
        model.draft = "Długie pytanie"
        model.send(using: service, policy: on, locale: "pl")
        try? await Task.sleep(for: .milliseconds(50))
        model.cancel()
        await settle(model)
        XCTAssertNil(model.error)
        XCTAssertEqual(model.messages.map(\.delivery), [.failed])
        let saved = await repository.all()
        XCTAssertEqual(saved.map(\.delivery), [.failed], "the bookkeeping finishes even though the question was stopped")
    }

    @MainActor
    func testEarlierTurnsGoWithTheNextQuestionButNeverAMessageNobodyAnswered() async {
        let (model, _, client, service) = await loaded(client: ScriptedClient([.fail(.timeout), .reply("Pierwsza."), .reply("Druga.")]))
        model.draft = "Zgubione"
        model.send(using: service, policy: on, locale: "pl")
        await settle(model)
        model.draft = "Pierwsze"
        model.send(using: service, policy: on, locale: "pl")
        await settle(model)
        model.draft = "Drugie"
        model.send(using: service, policy: on, locale: "pl")
        await settle(model)

        let requests = await client.requests
        XCTAssertEqual(requests.map(\.userText), ["Zgubione", "Pierwsze", "Drugie"])
        XCTAssertEqual(requests[1].recentTurns, [], "the lost one never reached Doddy")
        XCTAssertEqual(requests[2].recentTurns.map(\.text), ["Pierwsze", "Pierwsza."])
    }

    @MainActor
    func testWhatWasSavedIsLoadedAndAMessageLeftSendingIsNotDelivered() async throws {
        let repository = FakeThread()
        try await repository.append(ThreadMessage(id: UUID(), sender: .user, text: "Stare", createdAt: t0, delivery: .sent))
        try await repository.append(ThreadMessage(id: UUID(), sender: .doddy, text: "Odpowiedź", createdAt: t0.addingTimeInterval(1), delivery: .sent, basis: .general))
        try await repository.append(ThreadMessage(id: UUID(), sender: .user, text: "Zawieszone", createdAt: t0.addingTimeInterval(60), delivery: .sending))

        let model = MessagesModel(repository: repository)
        XCTAssertEqual(model.storage, .loading)
        model.draft = "Za wcześnie"
        XCTAssertFalse(model.canSend, "sending waits for the saved thread, so the order holds")
        await model.load()
        XCTAssertEqual(model.storage, .saving)
        XCTAssertEqual(model.messages.map(\.text), ["Stare", "Odpowiedź", "Zawieszone"])
        XCTAssertEqual(model.messages.last?.delivery, .failed)
        XCTAssertTrue(model.canSend)
    }

    @MainActor
    func testWhenSavingFailsTheAnswerStillShowsAndTheScreenSaysItIsNotKept() async {
        let repository = FakeThread()
        await repository.setFailing(true)
        let (model, _, _, service) = await loaded(repository, client: ScriptedClient([.reply("Tak.")]))
        XCTAssertEqual(model.storage, .notSaved, "reading failed")
        model.draft = "Pytanie"
        XCTAssertTrue(model.canSend, "a broken store does not stop the conversation, it only changes what is promised")
        model.send(using: service, policy: on, locale: "pl")
        await settle(model)
        XCTAssertEqual(model.messages.map(\.text), ["Pytanie", "Tak."])
        XCTAssertEqual(model.storage, .notSaved)
    }

    @MainActor
    func testDeletingEmptiesTheScreenOnlyAfterTheStoreReadBackEmpty() async {
        let (model, repository, _, service) = await loaded(client: ScriptedClient([.reply("Ok.")]))
        model.draft = "Cześć"
        model.send(using: service, policy: on, locale: "pl")
        await settle(model)

        await repository.setFailing(true)
        await model.deleteConversation()
        XCTAssertTrue(model.deleteFailed)
        XCTAssertEqual(model.messages.count, 2, "nothing is claimed gone")

        await repository.setFailing(false)
        await model.deleteConversation()
        XCTAssertFalse(model.deleteFailed)
        XCTAssertTrue(model.messages.isEmpty)
        let saved = await repository.all()
        XCTAssertTrue(saved.isEmpty)
    }

    @MainActor
    func testDeletingWaitsWhileAMessageIsOnItsWay() async {
        let (model, _, _, service) = await loaded(client: ScriptedClient([.hang]))
        model.draft = "Czekam"
        model.send(using: service, policy: on, locale: "pl")
        await model.deleteConversation()
        XCTAssertEqual(model.messages.count, 1)
        model.cancel()
        await settle(model)
    }

    // MARK: Files from Doddy (ADR-606)

    private let deck = AssistantProposal.make(kind: "deck", title: "Plan bety", request: "Dziesięć slajdów o becie.")!
    private let link = URL(string: "https://doddy.example.com/d/abc")!

    @MainActor
    private func askedForAFile() async -> (MessagesModel, FakeThread, UUID) {
        let (model, repository, _, service) = await loaded(client: ScriptedClient([.offer("Mogę to zrobić jako prezentację.", deck)]))
        model.draft = "Zrób mi prezentację o becie"
        model.send(using: service, policy: on, locale: "pl")
        await settle(model)
        return (model, repository, model.messages.last!.id)
    }

    @MainActor
    private func settleMaking(_ model: MessagesModel) async {
        for _ in 0..<400 where model.making != nil { try? await Task.sleep(for: .milliseconds(10)) }
    }

    @MainActor
    func testAnOfferIsOnlyAnOfferNothingIsMadeUntilTheTap() async {
        let maker = FakeMaker()
        let (model, repository, answer) = await askedForAFile()
        XCTAssertEqual(model.proposals[answer], deck)
        XCTAssertEqual(model.messages.map(\.sender), [.user, .doddy])
        XCTAssertNil(model.messages.last?.document)
        let calls = await maker.calls
        let saved = await repository.all()
        XCTAssertTrue(calls.isEmpty, "the model proposed; no tool ran")
        XCTAssertEqual(saved.count, 2, "only the question and the answer are saved")
    }

    @MainActor
    func testTappingMakeAddsAFileBubbleAfterItIsSavedAndUsesUpTheOffer() async {
        let maker = FakeMaker(.make(ThreadDocument(url: link, name: "Plan bety.pptx", kind: "deck")))
        let (model, repository, answer) = await askedForAFile()
        model.makeDocument(for: answer, using: maker)
        XCTAssertEqual(model.making, answer)
        await settleMaking(model)
        XCTAssertNil(model.making)
        XCTAssertNil(model.proposals[answer], "an offer is used once")
        XCTAssertEqual(model.messages.last?.document, ThreadDocument(url: link, name: "Plan bety.pptx", kind: "deck"))
        XCTAssertEqual(model.messages.last?.sender, .doddy)
        let calls = await maker.calls
        let saved = await repository.all()
        XCTAssertEqual(calls, [deck], "exactly the words on the card")
        XCTAssertEqual(saved, model.messages, "the file bubble is saved like any message")
    }

    @MainActor
    func testAFailedMakeKeepsTheOfferSaysWhyAndCanBeTriedAgain() async {
        let maker = FakeMaker(.fail(.offline), .make(ThreadDocument(url: link, name: "Plan bety.pptx", kind: "deck")))
        let (model, _, answer) = await askedForAFile()
        model.makeDocument(for: answer, using: maker)
        await settleMaking(model)
        XCTAssertEqual(model.makeFailure, .offline)
        XCTAssertEqual(model.proposals[answer], deck, "nothing was made, so the offer stays")
        XCTAssertEqual(model.messages.count, 2)

        model.makeDocument(for: answer, using: maker)
        XCTAssertNil(model.makeFailure, "a new try clears the old failure")
        await settleMaking(model)
        XCTAssertNotNil(model.messages.last?.document)
    }

    @MainActor
    func testASecondTapWhileMakingMakesNothingTwiceAndNoServerMeansNotConfigured() async {
        let maker = FakeMaker(.hang)
        let (model, _, answer) = await askedForAFile()
        model.makeDocument(for: answer, using: maker)
        model.makeDocument(for: answer, using: maker)
        try? await Task.sleep(for: .milliseconds(50))
        let calls = await maker.calls
        XCTAssertEqual(calls.count, 1)
        model.dismissProposal(answer)
        XCTAssertEqual(model.proposals[answer], deck, "cannot decline while it is being made")

        let (other, _, again) = await askedForAFile()
        other.makeDocument(for: again, using: nil)
        XCTAssertEqual(other.makeFailure, .notConfigured)
        XCTAssertNil(other.making)
    }

    @MainActor
    func testNotNowRemovesTheOfferAndMakesNothing() async {
        let maker = FakeMaker()
        let (model, repository, answer) = await askedForAFile()
        model.dismissProposal(answer)
        XCTAssertNil(model.proposals[answer])
        model.makeDocument(for: answer, using: maker)
        let calls = await maker.calls
        let saved = await repository.all()
        XCTAssertNil(model.making)
        XCTAssertTrue(calls.isEmpty)
        XCTAssertEqual(saved.count, 2)
    }

    @MainActor
    func testDeletingTheConversationAlsoDropsTheOffers() async {
        let (model, _, answer) = await askedForAFile()
        await model.deleteConversation()
        XCTAssertNil(model.proposals[answer])
        XCTAssertTrue(model.messages.isEmpty)
    }
}

// MARK: Fakes

private actor FakeMaker: ThreadDocumentMaker {
    enum Step {
        case make(ThreadDocument)
        case fail(ThreadDocumentError)
        /// Waits until cancelled.
        case hang
    }

    private var steps: [Step]
    private(set) var calls: [AssistantProposal] = []

    init(_ steps: Step...) { self.steps = steps }

    func make(_ proposal: AssistantProposal) async throws -> ThreadDocument {
        calls.append(proposal)
        guard !steps.isEmpty else { throw ThreadDocumentError.failed }
        switch steps.removeFirst() {
        case .make(let document): return document
        case .fail(let error): throw error
        case .hang:
            try await Task.sleep(for: .seconds(60))
            throw ThreadDocumentError.failed
        }
    }
}

private final class TickingClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_792_000_000)
    /// Every call is one second later, so messages keep their order.
    func tick() -> Date {
        lock.lock()
        defer { lock.unlock() }
        current = current.addingTimeInterval(1)
        return current
    }
}

private struct NoNotes: RecallService {
    func recall(_ question: String, limit: Int) async throws -> RecallOutcome { .noMatch }
}

private actor ScriptedClient: AssistantClient {
    enum Step {
        case reply(String)
        /// An answer that also offers a file (ADR-606).
        case offer(String, AssistantProposal)
        case fail(AssistantError)
        /// Waits until the request is cancelled.
        case hang
    }

    private var steps: [Step]
    private(set) var requests: [AssistantRequest] = []

    init(_ steps: [Step] = []) { self.steps = steps }

    func respond(_ request: AssistantRequest) async throws -> AssistantReply {
        requests.append(request)
        guard !steps.isEmpty else { throw AssistantError.providerUnavailable }
        switch steps.removeFirst() {
        case .reply(let text): return AssistantReply(text: text)
        case .offer(let text, let proposal): return AssistantReply(text: text, proposal: proposal)
        case .fail(let error): throw error
        case .hang:
            try await Task.sleep(for: .seconds(60))
            throw AssistantError.timeout
        }
    }
}

private actor FakeThread: MessageThreadRepository {
    private var rows: [ThreadMessage] = []
    private var failing = false

    struct Down: Error {}

    func setFailing(_ value: Bool) { failing = value }
    func all() -> [ThreadMessage] { rows }

    func recent(limit: Int) async throws -> [ThreadMessage] {
        if failing { throw Down() }
        return Array(rows.suffix(max(0, limit)))
    }

    func append(_ message: ThreadMessage) async throws {
        if failing { throw Down() }
        rows.append(message)
    }

    func setDelivery(id: UUID, _ delivery: ThreadMessage.Delivery) async throws {
        if failing { throw Down() }
        guard let index = rows.firstIndex(where: { $0.id == id }) else { throw MessageThreadError.notFound }
        rows[index].delivery = delivery
    }

    func failUnfinished() async throws -> Int {
        if failing { throw Down() }
        var changed = 0
        for index in rows.indices where rows[index].delivery == .sending {
            rows[index].delivery = .failed
            changed += 1
        }
        return changed
    }

    func delete(id: UUID) async throws {
        if failing { throw Down() }
        rows.removeAll { $0.id == id }
    }

    func deleteAll() async throws {
        if failing { throw Down() }
        rows = []
    }

    func export() async throws -> Data { Data() }
}
