import Foundation
import XCTest
@testable import DoddyCore

/// ADR-322: online-account writes in the action status model. The server side (one run per
/// confirmation, repeats answered from the first run, the look for a Todoist task) is tested in
/// backend/test/tools.test.ts; this covers the phone: the contract, the one safe repeat, the log.
final class CloudActionsTests: XCTestCase {
    private func fixture<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: root.appendingPathComponent("contracts/online-accounts/\(name).json")))
    }

    private let task = CloudToolCall(name: CloudToolName.addTodoistTask, arguments: ["content": .string("Pay rent"), "due": .string("tomorrow")])

    // MARK: Contract

    func testTheServersNewFieldsDecodeAndOldAnswersStillDo() throws {
        let draft = try fixture(RunResult.self, "run-result-draft")
        XCTAssertEqual(draft.externalId, "draft_demo_1")
        XCTAssertNil(draft.replayed)
        let replayed = try fixture(RunResult.self, "run-result-draft-replayed")
        XCTAssertEqual(replayed.replayed, true)
        XCTAssertEqual(replayed.text, draft.text, "a repeat gets the first answer")

        let again = try fixture(PrepareResult.self, "prepare-result-draft-again")
        XCTAssertEqual(again.earlier?.status, .succeeded)
        XCTAssertEqual(again.preview.lines.last, "Doddy already did exactly this once in the last day.")
        XCTAssertNil(try fixture(PrepareResult.self, "prepare-result-draft").earlier)
        // Answers from a server before ADR-322 have neither field.
        XCTAssertNil(try fixture(RunResult.self, "run-result-email").externalId)
    }

    // MARK: Keys

    func testTheSameWriteHasTheSameKeyAndReadsHaveNone() {
        let reordered = CloudToolCall(name: CloudToolName.addTodoistTask, arguments: ["due": .string("tomorrow"), "content": .string("Pay rent")])
        XCTAssertEqual(CloudIdempotency.key(task), CloudIdempotency.key(reordered))
        XCTAssertNotEqual(CloudIdempotency.key(task), CloudIdempotency.key(CloudToolCall(name: CloudToolName.addTodoistTask, arguments: ["content": .string("Pay gas")])))
        XCTAssertNil(CloudIdempotency.key(CloudToolCall(name: CloudToolName.checkEmail, arguments: [:])))

        let request = ActivityRequest.describe(.cloudTool(task), calendar: Calendar(identifier: .gregorian))
        XCTAssertEqual(request?.operationKey, CloudIdempotency.key(task))
        XCTAssertEqual(request?.app, .todoist)
        XCTAssertNil(request?.detail, "still no task text in the log")
        XCTAssertNil(ActivityRequest.describe(.cloudTool(CloudToolCall(name: CloudToolName.checkEmail, arguments: [:])), calendar: .current)?.operationKey)
    }

    // MARK: The one safe repeat

    func testALostAnswerIsAskedForOnceMoreWithTheSameConfirmation() async throws {
        let done = try fixture(RunResult.self, "run-result-draft")
        let client = FakeClient([.failure(.transport("URLError")), .success(done)])
        let approval = UUID()
        let outcome = await CloudRun.confirmed(task, approvalId: approval, timeZone: "Europe/Warsaw", client: client, pause: {})
        XCTAssertEqual(try outcome.get(), done)
        let used = await client.approvals
        XCTAssertEqual(used, [approval, approval], "the same confirmation both times, never a new one")
    }

    func testStillLostIsUnknownAndAnythingElseIsNotRepeated() async throws {
        let lost = FakeClient([.failure(.transport("URLError")), .failure(.unreadableResponse)])
        let twice = await CloudRun.confirmed(task, approvalId: UUID(), timeZone: "UTC", client: lost, pause: {})
        XCTAssertTrue(VoiceToolReply.cloudFailed(try XCTUnwrap(twice.failureValue), tool: task.name).hasPrefix("unknown:"))

        let refused = FakeClient([.failure(.server(code: "rate_limited", message: "", retryAfterSeconds: nil, receipt: nil))])
        _ = await CloudRun.confirmed(task, approvalId: UUID(), timeZone: "UTC", client: refused, pause: {})
        let refusedRuns = await refused.approvals.count
        XCTAssertEqual(refusedRuns, 1, "the server answered: nothing to repeat")

        let read = CloudToolCall(name: CloudToolName.checkEmail, arguments: [:])
        let readClient = FakeClient([.failure(.transport("URLError"))])
        _ = await CloudRun.confirmed(read, approvalId: UUID(), timeZone: "UTC", client: readClient, pause: {})
        let readRuns = await readClient.approvals.count
        XCTAssertEqual(readRuns, 1, "only writes are asked for again")
    }

    private func receipt(_ status: ReceiptStatus, _ errorCode: String?) -> OnlineToolReceipt {
        OnlineToolReceipt(
            operationId: UUID(), operation: .write, toolkit: "todoist", tool: task.name, timestamp: "2026-10-10T10:00:00.000Z",
            mode: .mock, status: status, summary: "Not done.", errorCode: errorCode, providerReference: nil)
    }

    /// The repeat meets the first try still running, or is itself refused: none of that says what the first try did.
    func testARepeatThatIsNotTheFirstTrysOutcomeLeavesItUnknown() async throws {
        let lost = OnlineAccountsError.transport("URLError")
        let seconds: [OnlineAccountsError] = [
            .server(code: "busy", message: "Busy.", retryAfterSeconds: 2, receipt: nil),
            .server(code: "rate_limited", message: "Wait.", retryAfterSeconds: nil, receipt: receipt(.blocked, "rate_limited")),
            .server(code: "capability_disabled", message: "", retryAfterSeconds: nil, receipt: receipt(.blocked, "confirmation_required")),
            .server(code: "capability_disabled", message: "", retryAfterSeconds: nil, receipt: receipt(.blocked, "capability_disabled")),
            .server(code: "capability_disabled", message: "", retryAfterSeconds: nil, receipt: receipt(.outcomeUnknown, "earlier_outcome_unknown")),
            .server(code: "not_connected", message: "", retryAfterSeconds: nil, receipt: receipt(.blocked, "not_connected")),
            .server(code: "capability_disabled", message: "", retryAfterSeconds: nil, receipt: nil),
            .unauthenticated, .notConfigured, .transport("again"), .unreadableResponse,
        ]
        for second in seconds {
            let client = FakeClient([.failure(lost), .failure(second)])
            let outcome = await CloudRun.confirmed(task, approvalId: UUID(), timeZone: "UTC", client: client, pause: {})
            XCTAssertEqual(outcome.failureValue, lost, "\(second)")
            let record = CloudWriteRecord(outcome, tool: task.name, app: .todoist, readAt: Date())
            XCTAssertTrue(record.reply.hasPrefix("unknown:"), "\(second): \(record.reply)")
            XCTAssertFalse(record.reply.contains("Nothing was done"), "\(second)")
            XCTAssertTrue(record.attempted, "still counts as a try that may have run: \(second)")
            XCTAssertEqual(ActivityEntry.outcome(of: record.reply, isLookup: false).0, .notSure, "\(second)")
        }
    }

    func testOnlyTheFirstTrysOwnOutcomeReplacesTheUnknown() async throws {
        let lost = OnlineAccountsError.unreadableResponse
        // A result: the first request never arrived and this one ran it, or the server answered from the first try.
        let replayed = try fixture(RunResult.self, "run-result-draft-replayed")
        let done = await CloudRun.confirmed(task, approvalId: UUID(), timeZone: "UTC", client: FakeClient([.failure(lost), .success(replayed)]), pause: {})
        XCTAssertEqual(try done.get(), replayed)
        let doneRecord = CloudWriteRecord(done, tool: CloudToolName.draftEmail, app: .gmail, readAt: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(doneRecord.attempted)
        XCTAssertEqual(doneRecord.receipt?.externalID, replayed.externalId)

        // The server's record that the first try never ran: needs a fresh confirmation, with the first try's `failed` receipt.
        let firstFailed = OnlineAccountsError.server(code: "capability_disabled", message: "", retryAfterSeconds: nil, receipt: receipt(.failed, "confirmation_required"))
        let failed = await CloudRun.confirmed(task, approvalId: UUID(), timeZone: "UTC", client: FakeClient([.failure(lost), .failure(firstFailed)]), pause: {})
        XCTAssertEqual(failed.failureValue, firstFailed)
        let failedRecord = CloudWriteRecord(failed, tool: task.name, app: .todoist, readAt: Date())
        XCTAssertEqual(failedRecord.reply, "failed: the first try didn't go through, so nothing was done. Offer to try again.")
        XCTAssertFalse(failedRecord.attempted, "provably never ran")
        XCTAssertNil(failedRecord.receipt)
    }

    func testTheDecisionAfterALostAnswerIsAPureFunction() throws {
        let lost = OnlineAccountsError.transport("URLError")
        let busy = OnlineAccountsError.server(code: "busy", message: "", retryAfterSeconds: 2, receipt: nil)
        XCTAssertEqual(CloudRun.afterLostAnswer(first: lost, second: .failure(busy)).failureValue, lost)
        let firstFailed = OnlineAccountsError.server(code: "capability_disabled", message: "", retryAfterSeconds: nil, receipt: receipt(.failed, "confirmation_required"))
        XCTAssertEqual(CloudRun.afterLostAnswer(first: lost, second: .failure(firstFailed)).failureValue, firstFailed)
        // The same code and words with a `blocked` receipt is a refusal of the repeat, not the first try's record.
        XCTAssertFalse(CloudRun.isFirstTryFailure(.server(code: "capability_disabled", message: "", retryAfterSeconds: nil, receipt: receipt(.blocked, "confirmation_required"))))
        XCTAssertFalse(CloudRun.isFirstTryFailure(.server(code: "rate_limited", message: "", retryAfterSeconds: nil, receipt: receipt(.failed, "confirmation_required"))))
        let draft = try fixture(RunResult.self, "run-result-draft")
        XCTAssertEqual(try CloudRun.afterLostAnswer(first: lost, second: .success(draft)).get(), draft)
    }

    func testARepeatOfAnUnsureFirstRunIsUnknownNeverExpired() throws {
        let receipt = OnlineToolReceipt(
            operationId: UUID(), operation: .write, toolkit: "todoist", tool: task.name, timestamp: "2026-10-10T10:00:00.000Z",
            mode: .mock, status: .outcomeUnknown, summary: "Todoist didn't confirm the first try.", errorCode: "earlier_outcome_unknown",
            providerReference: nil)
        let reply = VoiceToolReply.cloudFailed(.server(code: "capability_disabled", message: "", retryAfterSeconds: nil, receipt: receipt), tool: task.name)
        XCTAssertTrue(reply.hasPrefix("unknown:"), reply)
        XCTAssertFalse(reply.contains("expired"))
    }

    // MARK: What "What Doddy did" keeps

    func testTheLogKeepsTheProvidersIdAndKnowsWhatWasTried() throws {
        let done = try fixture(RunResult.self, "run-result-draft")
        let record = CloudWriteRecord(.success(done), tool: CloudToolName.draftEmail, app: .gmail, readAt: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(record.attempted)
        XCTAssertEqual(record.receipt?.externalID, "draft_demo_1")
        XCTAssertEqual(record.receipt?.lines, ["Gmail draft created (not sent)."])
        XCTAssertFalse(record.reply.contains("draft_demo_1"), "the agent never hears the id")

        let expired = try fixture(OnlineErrorBody.self, "error-confirmation-expired")
        let refused = CloudWriteRecord(
            .failure(.server(code: expired.error.code, message: expired.error.message, retryAfterSeconds: nil, receipt: expired.error.receipt)),
            tool: CloudToolName.draftEmail, app: .gmail, readAt: Date())
        XCTAssertFalse(refused.attempted, "provably not run: doesn't count as a try")
        XCTAssertNil(refused.receipt)
        XCTAssertTrue(CloudWriteRecord(.failure(.transport("x")), tool: CloudToolName.draftEmail, app: .gmail, readAt: Date()).attempted)
    }

    func testAlreadyThereFromTheEarlierTryIsLoggedAsAlreadyThere() {
        let reply = VoiceToolReply.cloudAlreadyThere(CloudToolName.addTodoistTask)
        XCTAssertEqual(ActivityEntry.outcome(of: reply, isLookup: false).0, .alreadyThere)
        XCTAssertEqual(reply, "added: \"Add a task\" was already in Todoist from the earlier try, so Doddy did not do it a second time. Tell the user it is already there.")
    }
}

private actor FakeClient: OnlineAccountsClient {
    private var answers: [Result<RunResult, OnlineAccountsError>]
    private(set) var approvals: [UUID?] = []

    init(_ answers: [Result<RunResult, OnlineAccountsError>]) { self.answers = answers }

    func run(_ call: CloudToolCall, timeZone: String, approvalId: UUID?) async throws(OnlineAccountsError) -> RunResult {
        approvals.append(approvalId)
        guard !answers.isEmpty else { throw .unreadableResponse }
        return try answers.removeFirst().get()
    }

    func catalog() async throws(OnlineAccountsError) -> ToolsCatalog { throw .notConfigured }
    func connect(toolkit: String) async throws(OnlineAccountsError) -> ConnectResponse { throw .notConfigured }
    func complete(toolkit: String, _ request: CompleteRequest) async throws(OnlineAccountsError) -> ToolkitResult { throw .notConfigured }
    func disconnect(toolkit: String) async throws(OnlineAccountsError) -> ToolkitResult { throw .notConfigured }
    func setSwitch(tool: String, enabled: Bool) async throws(OnlineAccountsError) -> ToolkitResult { throw .notConfigured }
    func prepare(_ call: CloudToolCall) async throws(OnlineAccountsError) -> PrepareResult { throw .notConfigured }
    func receipts() async throws(OnlineAccountsError) -> [OnlineToolReceipt] { throw .notConfigured }
}

private extension Result {
    var failureValue: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
