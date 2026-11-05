import DoddyCore
import Foundation
import XCTest
#if canImport(Doddy)
@testable import Doddy
#endif

// The call screens' state (ADR-500): nothing is sent with a known problem, an answer is saved on
// the iPhone before the server is told to delete its copy, an unconfirmed approval is never
// retried, and retry times stay inside the hours and the server's window. Fakes stand in for the
// server and the store. Also run on Linux by scripts/test_call_cases_model.sh.

final class CallCasesModelTests: XCTestCase {
    @MainActor
    func testABriefWithAProblemIsNeverSent() async {
        let backend = FakeCallBackend()
        let model = CallCasesModel(backend: backend, repository: MemoryCallCases(), describe: { "\($0)" })
        let saved = await model.prepare(CallBriefDraft(calleeName: "Serwis", phone: "112", principalName: "Anna", goal: "Cel rozmowy", question: "Czy gotowe?"))
        XCTAssertNil(saved)
        let created = await backend.created
        XCTAssertEqual(created, 0, "a refused number never reaches the server")
        XCTAssertNotNil(model.message)
    }

    @MainActor
    func testTheServersCardIsKeptWithTheWholeBrief() async throws {
        let backend = FakeCallBackend()
        let repository = MemoryCallCases()
        let model = CallCasesModel(backend: backend, repository: repository, describe: { "\($0)" })
        let draft = CallBriefDraft(calleeName: "Serwis Bajt", phone: "221234567", principalName: "Anna", goal: "Odbiór laptopa",
                                   question: "Czy laptop jest gotowy do odbioru?",
                                   facts: [CallFactDraft(text: "Zlecenie 12345", ticked: true), CallFactDraft(kind: .pesel, text: CallFixtures.pesel, ticked: false)])
        let prepared = await model.prepare(draft)
        let saved = try XCTUnwrap(prepared)
        XCTAssertEqual(saved.preview?.digest, CallFixtures.digest)
        XCTAssertEqual(saved.state, "awaiting_approval")
        let lastDraft = await backend.lastDraft
        let sent = try XCTUnwrap(lastDraft)
        XCTAssertEqual(sent.requestBody().facts.map(\.text), ["Zlecenie 12345"], "only ticked facts are sent")
        let stored = try await repository.get(saved.id)
        XCTAssertEqual(stored?.brief.facts.count, 2, "the unticked PESEL stays on the iPhone")
    }

    @MainActor
    func testAnApprovedCallIsWatchedAndItsAnswerSavedBeforeTheServerDeletesIt() async throws {
        let backend = FakeCallBackend()
        let repository = MemoryCallCases()
        await backend.setRepository(repository)
        await backend.setLive([CallFixtures.live(phase: "talking", lines: [("doddy", "Dzień dobry"), ("callee", "Tak, gotowy.")]),
                               CallFixtures.live(phase: "ended", lines: [])])
        await backend.setSnapshots([CallFixtures.snapshot(ready: true)])
        let list = CallCasesModel(backend: backend, repository: repository, describe: { "\($0)" })
        let record = try await repository.save(CallFixtures.record())
        let model = list.caseModel(for: record, activity: nil)

        await model.approve()
        try await waitUntil { model.record.result != nil && !model.waitingForResult && model.record.deletions.contains { $0.item == "call_result" } }

        XCTAssertEqual(model.lines.map(\.text), ["Dzień dobry", "Tak, gotowy."])
        XCTAssertEqual(model.record.result?.quote?.text, "Tak, gotowy.")
        XCTAssertEqual(model.record.cost?.totalMicros, 117_000)
        let savedFirst = await backend.resultWasStoredWhenAcked
        XCTAssertEqual(savedFirst, true, "the answer is saved on the iPhone before the server deletes its copy")
        let stored = try await repository.get(record.id)
        XCTAssertEqual(stored?.result?.transcript.last?.text, "Tak, gotowy.")
        XCTAssertTrue(stored?.deletions.contains { $0.item == "call_result" && $0.result == "deleted" } ?? false)
        let approvals = await backend.approvals
        XCTAssertEqual(approvals, [CallFixtures.digest], "approval is bound to the card's digest")
    }

    @MainActor
    func testAFailedAcknowledgementKeepsTheAnswerAndAsksAgainLater() async throws {
        let backend = FakeCallBackend()
        let repository = MemoryCallCases()
        await backend.setRepository(repository)
        await backend.setSnapshots([CallFixtures.snapshot(ready: true)])
        await backend.failAcks(true)
        let list = CallCasesModel(backend: backend, repository: repository, describe: { "\($0)" })
        let record = try await repository.save(CallFixtures.record(state: "active"))
        let model = list.caseModel(for: record, activity: nil)

        await model.refresh()
        let first = try await repository.get(record.id)
        XCTAssertEqual(first?.result?.quote?.text, "Tak, gotowy.", "kept on the iPhone even though the server's copy wasn't deleted")
        XCTAssertNotNil(model.message)

        await backend.failAcks(false)
        await model.syncOnce()
        let acks = await backend.acks
        XCTAssertEqual(acks, 2)
        let second = try await repository.get(record.id)
        XCTAssertTrue(second?.deletions.contains { $0.item == "call_result" } ?? false)
    }

    @MainActor
    func testAnUnconfirmedApprovalIsNeverSentAgain() async throws {
        let backend = FakeCallBackend()
        await backend.setApprovalState("unknown")
        await backend.setLive([CallFixtures.live(phase: "ended", lines: [])])
        let repository = MemoryCallCases()
        let list = CallCasesModel(backend: backend, repository: repository, describe: { "\($0)" })
        let record = try await repository.save(CallFixtures.record())
        let model = list.caseModel(for: record, activity: nil)

        await model.approve()
        try await Task.sleep(nanoseconds: 1_500_000_000)
        model.stopWatching()
        let approvals = await backend.approvals
        XCTAssertEqual(approvals.count, 1)
        XCTAssertEqual(model.message, NSLocalizedString("Couldn't confirm the call started. Doddy won't redial on its own; the line is checked now.", comment: ""))
    }

    @MainActor
    func testACaseTheServerNoLongerHasStaysOnTheIPhoneWithoutAnError() async throws {
        let backend = FakeCallBackend()
        await backend.setGone(true)
        let repository = MemoryCallCases()
        let list = CallCasesModel(backend: backend, repository: repository, describe: { "\($0)" })
        let record = try await repository.save(CallFixtures.record(state: "finished"))
        let model = list.caseModel(for: record, activity: nil)
        await model.refresh()
        XCTAssertNil(model.message)
        let kept = try await repository.get(record.id)
        XCTAssertEqual(kept, record)
    }

    @MainActor
    func testRetryTimesFitTheHoursAndTheServersWindow() async throws {
        let list = CallCasesModel(backend: FakeCallBackend(), repository: MemoryCallCases(), describe: { "\($0)" })
        let created = ISO8601DateFormatter().date(from: "2026-10-19T09:00:00Z")!
        let model = list.caseModel(for: CallFixtures.record(createdAt: created), activity: nil)
        let now = ISO8601DateFormatter().date(from: "2026-10-19T10:05:00Z")!
        let times = model.retryTimes(now: now)
        XCTAssertFalse(times.isEmpty)
        for time in times {
            XCTAssertTrue(CallHours.fits(time, maxDurationSecs: 240))
            XCTAssertLessThanOrEqual(time.timeIntervalSince(now), 86_400, "the server takes a time up to a day ahead")
            XCTAssertLessThanOrEqual(time, created.addingTimeInterval(2 * 86_400), "before the card's payload is dropped")
        }
    }

    @MainActor
    func testWithdrawingAnUnusedCardRemovesIt() async throws {
        let backend = FakeCallBackend()
        let repository = MemoryCallCases()
        let model = CallCasesModel(backend: backend, repository: repository, describe: { "\($0)" })
        let record = try await repository.save(CallFixtures.record())
        await model.load()
        await model.withdraw(record)
        let cancelled = await backend.cancelled
        XCTAssertEqual(cancelled, [record.id])
        let gone = try await repository.get(record.id)
        XCTAssertNil(gone)
    }

    @MainActor
    private func waitUntil(timeout: TimeInterval = 20, _ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { XCTFail("timed out"); return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }
}

// MARK: - Fakes

private actor MemoryCallCases: CallCaseRepository {
    private var rows: [UUID: StoredCallCase] = [:]

    func save(_ record: StoredCallCase) async throws -> StoredCallCase {
        rows[record.id] = record
        return record
    }
    func list() async throws -> [StoredCallCase] { rows.values.sorted { $0.createdAt > $1.createdAt } }
    func get(_ id: UUID) async throws -> StoredCallCase? { rows[id] }
    func delete(_ id: UUID) async throws { rows[id] = nil }
    func deleteAll() async throws { rows = [:] }
    func export() async throws -> Data { try JSONEncoder().encode(Array(rows.values)) }
}

private actor FakeCallBackend: CallCasesBackend {
    private(set) var created = 0
    private(set) var lastDraft: CallBriefDraft?
    private(set) var approvals: [String] = []
    private(set) var acks = 0
    private(set) var cancelled: [UUID] = []
    private(set) var resultWasStoredWhenAcked: Bool?
    private var approvalState = "dialing"
    private var live: [CallLiveView] = []
    private var snapshots: [CallCaseSnapshot] = []
    private var ackFails = false
    private var repository: MemoryCallCases?
    private var gone = false

    func setRepository(_ repository: MemoryCallCases) { self.repository = repository }
    func setLive(_ views: [CallLiveView]) { live = views }
    func setSnapshots(_ list: [CallCaseSnapshot]) { snapshots = list }
    func setApprovalState(_ state: String) { approvalState = state }
    func failAcks(_ on: Bool) { ackFails = on }
    func setGone(_ on: Bool) { gone = on }

    func callCaseAvailability() async throws -> CallCaseAvailability {
        try CallFixtures.decode(#"{"available":true,"configured":true,"killSwitch":false,"phoneVerified":true,"recordingNotice":"off","recordsAudio":false,"maxDurationSecs":300,"agentProblems":[]}"#)
    }

    func createCallCase(_ draft: CallBriefDraft) async throws -> CallPreview {
        created += 1
        lastDraft = draft
        return try CallFixtures.preview()
    }

    func approveCallCase(_ caseId: UUID, digest: String, at: Date?) async throws -> CallApproval {
        approvals.append(digest)
        return CallApproval(attemptId: CallFixtures.attemptId, state: approvalState)
    }

    func callCaseLive(_ caseId: UUID, after cursor: String?) async throws -> CallLiveView {
        live.count > 1 ? live.removeFirst() : (live.first ?? CallFixtures.live(phase: "ended", lines: []))
    }

    func endCallCase(_ caseId: UUID) async throws {}
    func takeOverCallCase(_ caseId: UUID) async throws -> String { "ringing" }

    func callCase(_ caseId: UUID) async throws -> CallCaseSnapshot {
        // What DoddyServerClient throws for a 404 from GET /v1/call-cases/:id.
        if gone { throw ServerError.unexpected(status: 404) }
        guard let first = snapshots.first else { return CallFixtures.snapshot(ready: false) }
        return first
    }

    func acknowledgeCallResult(_ caseId: UUID, attemptId: UUID, resultDigest: String) async throws -> [DeletionReceipt] {
        acks += 1
        if let repository { resultWasStoredWhenAcked = try await repository.get(caseId)?.result != nil }
        if ackFails { throw CallCaseError.server(.offline) }
        // The server no longer holds a ready result after the acknowledgement.
        snapshots = [CallFixtures.snapshot(ready: false, acked: true)]
        return [try CallFixtures.decode(#"{"item":"call_result","location":"doddy_server","reason":"acked","result":"deleted","requestedAt":"2026-10-19T09:31:00.000Z","settledAt":"2026-10-19T09:31:00.000Z","rows":1}"#)]
    }

    func cancelCallCase(_ caseId: UUID) async throws { cancelled.append(caseId) }
}

private enum CallFixtures {
    static let caseId = UUID(uuidString: "11111111-2222-4333-8444-555555555555")!
    static let attemptId = UUID(uuidString: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")!
    static let digest = String(repeating: "ab", count: 32)
    static let pesel = "44051401359"

    static func decode<T: Decodable>(_ json: String) throws -> T { try JSONDecoder().decode(T.self, from: Data(json.utf8)) }

    static func preview() throws -> CallPreview {
        let until = ISO8601DateFormatter().string(from: Date().addingTimeInterval(1800))
        return try decode("""
        {"caseId":"\(caseId.uuidString)","digest":"\(digest)","approvableUntil":"\(until)",
         "callee":{"name":"Serwis Bajt","phone":"+48 22 123 45 67","destinationKind":"geographic","source":"typed","sourceLabel":null},
         "principal":{"name":"Anna","genitive":"Anny"},"goal":"Odbiór laptopa",
         "openingLine":"Dzień dobry, mówi Doddy, asystent AI, dzwonię w imieniu Anny. Chciałbym zapytać: Czy laptop jest gotowy do odbioru?",
         "question":"Czy laptop jest gotowy do odbioru?","facts":[{"kind":"reference","text":"Zlecenie 12345"}],
         "forbidden":["Nie zgadza się na nic"],"callbackLine":"Sprawdzę to u Anny i oddzwonię.","maxDurationSecs":240,
         "notice":"off","recordsAudio":false,"callableNow":true}
        """)
    }

    static func record(state: String = "awaiting_approval", createdAt: Date = Date()) -> StoredCallCase {
        StoredCallCase(id: caseId, createdAt: createdAt, state: state,
                       brief: CallBriefDraft(calleeName: "Serwis Bajt", phone: "221234567", principalName: "Anna", goal: "Odbiór laptopa",
                                             question: "Czy laptop jest gotowy do odbioru?"),
                       preview: try? preview())
    }

    static func live(phase: String, lines: [(String, String)]) -> CallLiveView {
        let rendered = lines.enumerated().map { #"{"key":"k\#($0.offset)-\#(phase)","speaker":"\#($0.element.0)","text":"\#($0.element.1)"}"# }
        let ended = phase == "ended" ? #""2026-10-19T09:30:40.000Z""# : "null"
        return try! decode("""
        {"attempt":{"id":"\(attemptId.uuidString)","attemptNo":1,"phase":"\(phase)","answeredAt":"2026-10-19T09:30:05.000Z",
                    "hangupDueAt":null,"endedAt":\(ended),"endReason":null,"takenOverAt":null,"takeover":null},
         "lines":[\(rendered.joined(separator: ","))],"cursor":"c-\(phase)"}
        """)
    }

    static func snapshot(ready: Bool, acked: Bool = false) -> CallCaseSnapshot {
        let card = #"""
        {"outcome":"answered","source":"elevenlabs","confidence":"high","confidenceReasons":[],"summary":"Odpowiedź: „Tak, gotowy.”",
         "summaryBy":"rules","quote":{"text":"Tak, gotowy.","line":1},
         "transcript":[{"speaker":"doddy","text":"Dzień dobry","atSecs":0},{"speaker":"callee","text":"Tak, gotowy.","atSecs":4.5}],
         "nextStep":{"kind":"save_note","text":"Zapisz odpowiedź w notatkach."},"warnings":[],"callbackPromised":false,"durationSecs":35}
        """#
        let result = ready
            ? #"{"attemptId":"\#(attemptId.uuidString)","state":"ready","outcome":"answered","confidence":"high","resultDigest":"\#(String(repeating: "cd", count: 32))","result":\#(card)}"#
            : #"{"attemptId":"\#(attemptId.uuidString)","state":"\#(acked ? "acked" : "waiting")","outcome":null,"confidence":null,"resultDigest":null,"result":null}"#
        let receipts = acked
            ? #"[{"item":"call_result","location":"doddy_server","reason":"acked","result":"deleted","requestedAt":"2026-10-19T09:31:00.000Z","settledAt":"2026-10-19T09:31:00.000Z","rows":1}]"#
            : "[]"
        return try! decode("""
        {"caseId":"\(caseId.uuidString)","state":"finished","approvableUntil":"2026-10-19T10:40:00.000Z","preview":null,
         "attempts":[{"id":"\(attemptId.uuidString)","attemptNo":1,"state":"ended","phase":"ended","endReason":"completed"}],
         "results":[\(result)],
         "cost":{"currency":"USD","totalMicros":117000,"complete":true,"approximate":true,"pending":false,"unknownParts":[],
                 "items":[{"component":"twilio_call","ref":"","status":"reported","amountMicros":27000,"currency":"USD","quantity":0.6,"unit":"minute"}]},
         "deletions":\(receipts)}
        """)
    }
}
