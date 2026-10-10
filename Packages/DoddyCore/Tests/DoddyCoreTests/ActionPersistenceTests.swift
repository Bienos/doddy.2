import Foundation
import XCTest
@testable import DoddyCore

/// Ledger + store: what survives a restart, and what happens when storage fails (DOD-08, DOD-09).
final class ActionPersistenceTests: XCTestCase {
    private let day: TimeInterval = 24 * 60 * 60

    private func approvedRecord(_ ledger: ActionLedger, text: String = "See you at 7") async throws -> ActionRecord {
        let payload = try ActionPayload.message(to: "Alex", text: text)
        let record = try await ledger.propose(ActionProposal(payload: payload))
        _ = try await ledger.requestApproval(record.id)
        return try await ledger.approve(record.id, reviewedPayload: payload)
    }

    private func assertThrows(
        _ expected: ActionPolicyError, file: StaticString = #filePath, line: UInt = #line,
        _ body: () async throws -> Void
    ) async {
        do {
            try await body()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? ActionPolicyError, expected, file: file, line: line)
        }
    }

    func testEveryStepIsStoredBeforeItReturns() async throws {
        let store = InMemoryActionStore()
        let ledger = ActionLedger(adapters: [SimulatedActionAdapter()], store: store)
        let payload = try ActionPayload.message(to: "Alex", text: "hi")
        var record = try await ledger.propose(ActionProposal(payload: payload))
        XCTAssertEqual(try store.loadAll(), [record])
        record = try await ledger.requestApproval(record.id)
        XCTAssertEqual(try store.loadAll(), [record])
        record = try await ledger.approve(record.id, reviewedPayload: payload)
        XCTAssertNotNil(record.approval)
        XCTAssertEqual(try store.loadAll(), [record.storable], "approvals are never stored")
        record = try await ledger.execute(record.id)
        XCTAssertEqual(try store.loadAll(), [record])
        XCTAssertEqual(record.status, .confirmed)
    }

    func testExecutingIsStoredBeforeTheProviderIsCalled() async throws {
        let store = InMemoryActionStore()
        let probe = ProbeAdapter(store: store)
        let ledger = ActionLedger(adapters: [probe], store: store)
        let record = try await approvedRecord(ledger)
        _ = try await ledger.execute(record.id)
        let seen = await probe.storedDuringCall
        XCTAssertEqual(seen?.status, .executing)
        XCTAssertNotNil(seen?.idempotencyKey)
        XCTAssertNil(seen?.approval)
    }

    func testRestartAfterAnInterruptedSendShowsUnknownAndNeverResends() async throws {
        let store = InMemoryActionStore()
        let adapter = SimulatedActionAdapter()
        let key = UUID()
        let at = Date(timeIntervalSince1970: 1_800_000_000)
        let interrupted = try ActionRecord.restore(
            id: UUID(), payload: .message(to: "Alex", text: "hi"), status: .executing, idempotencyKey: key,
            providerReference: nil, failureReason: nil, connectorID: "simulation", isSimulation: true,
            history: [ActionEvent(status: .proposed, at: at, note: nil), ActionEvent(status: .executing, at: at, note: nil)])
        try store.save(interrupted)

        let relaunched = ActionLedger(adapters: [adapter], store: store)
        let recovered = try await relaunched.record(interrupted.id)
        XCTAssertEqual(recovered.status, .unknown)
        XCTAssertEqual(recovered.history.last?.note, "The app stopped before the provider answered")
        XCTAssertEqual(try store.loadAll().first?.status, .unknown, "recovery is stored too")
        await assertThrows(.reconcileFirst) { _ = try await relaunched.execute(interrupted.id) }

        let checked = try await relaunched.reconcile(interrupted.id)
        XCTAssertEqual(checked.status, .unknown, "the provider has no record, so it stays unknown")
        let sent = await adapter.executeCount
        let checks = await adapter.statusCheckCount
        XCTAssertEqual(sent, 0)
        XCTAssertEqual(checks, 1)
    }

    func testApprovalDoesNotSurviveARestart() async throws {
        let store = InMemoryActionStore()
        let adapter = SimulatedActionAdapter()
        let record = try await approvedRecord(ActionLedger(adapters: [adapter], store: store))

        let relaunched = ActionLedger(adapters: [adapter], store: store)
        let reloaded = try await relaunched.record(record.id)
        XCTAssertEqual(reloaded.status, .needsApproval)
        XCTAssertNil(reloaded.approval)
        await assertThrows(.notApproved) { _ = try await relaunched.execute(record.id) }
        _ = try await relaunched.approve(record.id, reviewedPayload: reloaded.payload)
        let done = try await relaunched.execute(record.id)
        XCTAssertEqual(done.status, .confirmed)
        let sent = await adapter.executeCount
        XCTAssertEqual(sent, 1)
    }

    func testFailedWriteChangesNothing() async throws {
        let store = FlakyStore()
        let ledger = ActionLedger(adapters: [SimulatedActionAdapter()], store: store)
        let payload = try ActionPayload.message(to: "Alex", text: "hi")
        store.failSaves = true
        await assertThrows(.storageFailed) { _ = try await ledger.propose(ActionProposal(payload: payload)) }
        let none = try await ledger.history()
        XCTAssertEqual(none, [])

        store.failSaves = false
        let record = try await ledger.propose(ActionProposal(payload: payload))
        _ = try await ledger.requestApproval(record.id)
        store.failSaves = true
        await assertThrows(.storageFailed) { _ = try await ledger.approve(record.id, reviewedPayload: payload) }
        let unchanged = try await ledger.record(record.id)
        XCTAssertNil(unchanged.approval)
        store.failSaves = false
        await assertThrows(.notApproved) { _ = try await ledger.execute(record.id) }
    }

    func testNoSendIfExecutingCannotBeStored() async throws {
        let store = FlakyStore()
        let adapter = SimulatedActionAdapter()
        let ledger = ActionLedger(adapters: [adapter], store: store)
        let record = try await approvedRecord(ledger)
        store.failSavesWithStatus = .executing
        await assertThrows(.storageFailed) { _ = try await ledger.execute(record.id) }
        let sent = await adapter.executeCount
        XCTAssertEqual(sent, 0)
        let after = try await ledger.record(record.id)
        XCTAssertEqual(after.status, .needsApproval)
        XCTAssertNotNil(after.approval, "nothing changed, so the approval still stands")
    }

    func testUnsavedResultIsShownNowAndRecheckedAfterRestart() async throws {
        let store = FlakyStore()
        let adapter = SimulatedActionAdapter()
        let ledger = ActionLedger(adapters: [adapter], store: store)
        let record = try await approvedRecord(ledger)
        store.failSavesWithStatus = .confirmed
        await assertThrows(.resultNotSaved(.confirmed)) { _ = try await ledger.execute(record.id) }
        let shown = try await ledger.record(record.id)
        XCTAssertEqual(shown.status, .confirmed, "the provider did confirm; the receipt says so")
        XCTAssertEqual(try store.loadAll().first?.status, .executing)

        store.failSavesWithStatus = nil
        let relaunched = ActionLedger(adapters: [adapter], store: store)
        let recovered = try await relaunched.record(record.id)
        XCTAssertEqual(recovered.status, .unknown)
        let reconciled = await relaunched.reconcileAllUnknown()
        XCTAssertEqual(reconciled.map(\.status), [.confirmed])
        let sent = await adapter.executeCount
        XCTAssertEqual(sent, 1)
    }

    func testUnreadableStoreSwitchesActionsOff() async throws {
        let store = FlakyStore()
        store.failLoad = true
        let ledger = ActionLedger(adapters: [SimulatedActionAdapter()], store: store)
        await assertThrows(.storageUnavailable) {
            _ = try await ledger.propose(ActionProposal(payload: try .message(to: "Alex", text: "hi")))
        }
        store.failLoad = false
        await assertThrows(.storageUnavailable) { _ = try await ledger.history() }
    }

    func testRetentionRemovesOnlyOldFinishedActions() async throws {
        let store = InMemoryActionStore()
        let clock = TestClock()
        func stored(_ status: ActionStatus, ageInDays: Double) throws -> ActionRecord {
            let at = clock.now - ageInDays * day
            let ran: Set<ActionStatus> = [.executing, .confirmed, .failed, .unknown]
            let record = try ActionRecord.restore(
                id: UUID(), payload: .message(to: "Alex", text: "hi"), status: status,
                idempotencyKey: ran.contains(status) ? UUID() : nil,
                providerReference: status == .confirmed ? "ref" : nil, failureReason: nil,
                connectorID: "simulation", isSimulation: true,
                history: [ActionEvent(status: status, at: at, note: nil)])
            try store.save(record)
            return record
        }
        let oldConfirmed = try stored(.confirmed, ageInDays: 31)
        let oldCancelled = try stored(.cancelled, ageInDays: 40)
        let recentConfirmed = try stored(.confirmed, ageInDays: 2)
        let oldUnknown = try stored(.unknown, ageInDays: 90)
        let oldDraft = try stored(.needsApproval, ageInDays: 90)

        let ledger = ActionLedger(adapters: [SimulatedActionAdapter()], store: store, now: { clock.now })
        let kept = Set(try await ledger.history().map(\.id))
        XCTAssertEqual(kept, [recentConfirmed.id, oldUnknown.id, oldDraft.id])
        XCTAssertEqual(Set(try store.loadAll().map(\.id)), kept)
        XCTAssertFalse(kept.contains(oldConfirmed.id) || kept.contains(oldCancelled.id))
    }

    func testHistoryIsNewestFirst() async throws {
        let clock = TestClock()
        let ledger = ActionLedger(adapters: [SimulatedActionAdapter()], now: { clock.now })
        let first = try await ledger.propose(ActionProposal(payload: .message(to: "A", text: "1")))
        clock.advance(by: 10)
        let second = try await ledger.propose(ActionProposal(payload: .message(to: "B", text: "2")))
        let history = try await ledger.history()
        XCTAssertEqual(history.map(\.id), [second.id, first.id])
        let limited = try await ledger.history(limit: 1)
        XCTAssertEqual(limited.map(\.id), [second.id])
    }

    func testDeleteHistoryRemovesEverythingButNotWhileSending() async throws {
        let store = InMemoryActionStore()
        let gate = GateAdapter()
        let ledger = ActionLedger(adapters: [gate], store: store)
        let record = try await approvedRecord(ledger)

        let sending = Task { try await ledger.execute(record.id) }
        await gate.waitUntilCalled()
        await assertThrows(.actionInProgress) { try await ledger.deleteHistory() }
        await gate.release()
        _ = try await sending.value

        _ = try await ledger.propose(ActionProposal(payload: .message(to: "B", text: "2")))
        try await ledger.deleteHistory()
        let history = try await ledger.history()
        XCTAssertEqual(history, [])
        XCTAssertEqual(try store.loadAll(), [])
    }

    func testRestoreRejectsRecordsThatBreakTheLifecycle() {
        let at = Date(timeIntervalSince1970: 0)
        func restore(_ status: ActionStatus, key: UUID?, reference: String?) throws -> ActionRecord {
            try ActionRecord.restore(
                id: UUID(), payload: .message(to: "A", text: "b"), status: status, idempotencyKey: key,
                providerReference: reference, failureReason: nil, connectorID: "c", isSimulation: true,
                history: [ActionEvent(status: status, at: at, note: nil)])
        }
        XCTAssertThrowsError(try restore(.confirmed, key: UUID(), reference: nil))
        XCTAssertThrowsError(try restore(.confirmed, key: UUID(), reference: "  "))
        XCTAssertThrowsError(try restore(.executing, key: nil, reference: nil))
        XCTAssertThrowsError(try restore(.failed, key: UUID(), reference: "ref"))
        XCTAssertNoThrow(try restore(.confirmed, key: UUID(), reference: "ref"))
        XCTAssertThrowsError(try ActionRecord.restore(
            id: UUID(), payload: .message(to: "A", text: "b"), status: .drafted, idempotencyKey: nil,
            providerReference: nil, failureReason: nil, connectorID: "c", isSimulation: true,
            history: [ActionEvent(status: .proposed, at: at, note: nil)]), "last event must match the status")
    }

    func testStorageCopyNeverClaimsASend() {
        for error: ActionPolicyError in [.storageFailed, .storageUnavailable] {
            XCTAssertTrue(ActionStatusCopy.problem(for: error).contains("Nothing was sent"), "\(error)")
        }
        XCTAssertTrue(ActionStatusCopy.problem(for: ActionPolicyError.resultNotSaved(.confirmed)).contains("checked again"))
    }
}

/// Store that can be told to fail.
final class FlakyStore: ActionStore, @unchecked Sendable {
    private let inner = InMemoryActionStore()
    private let lock = NSLock()
    private var _failSaves = false
    private var _failSavesWithStatus: ActionStatus?
    private var _failLoad = false

    var failSaves: Bool { get { lock.withLock { _failSaves } } set { lock.withLock { _failSaves = newValue } } }
    var failSavesWithStatus: ActionStatus? {
        get { lock.withLock { _failSavesWithStatus } } set { lock.withLock { _failSavesWithStatus = newValue } }
    }
    var failLoad: Bool { get { lock.withLock { _failLoad } } set { lock.withLock { _failLoad = newValue } } }

    struct Failure: Error {}

    func loadAll() throws -> [ActionRecord] {
        if failLoad { throw Failure() }
        return try inner.loadAll()
    }

    func save(_ record: ActionRecord) throws {
        if failSaves || failSavesWithStatus == record.status { throw Failure() }
        try inner.save(record)
    }

    func delete(ids: [UUID]) throws {
        try inner.delete(ids: ids)
    }
}

/// Reads the store while the provider call is in progress.
actor ProbeAdapter: ActionAdapter {
    nonisolated let connectorID = "probe"
    nonisolated let isSimulation = true
    private let store: any ActionStore
    private(set) var storedDuringCall: ActionRecord?

    init(store: any ActionStore) { self.store = store }

    nonisolated func supports(_ type: ActionType) -> Bool { type == .sendMessage }

    func execute(_ request: ActionExecutionRequest) async throws -> ActionProviderResult {
        storedDuringCall = try store.loadAll().first { $0.id == request.actionID }
        return .confirmed(providerReference: "probe-1")
    }

    func status(idempotencyKey: UUID) async throws -> ActionProviderResult { .unknown(reason: "n/a") }
}

/// Holds the provider call open until the test releases it.
actor GateAdapter: ActionAdapter {
    nonisolated let connectorID = "gate"
    nonisolated let isSimulation = true
    private var called = false
    private var calledWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    private var released = false

    nonisolated func supports(_ type: ActionType) -> Bool { type == .sendMessage }

    func execute(_ request: ActionExecutionRequest) async throws -> ActionProviderResult {
        called = true
        calledWaiters.forEach { $0.resume() }
        calledWaiters = []
        if !released {
            await withCheckedContinuation { releaseWaiter = $0 }
        }
        return .confirmed(providerReference: "gate-1")
    }

    func status(idempotencyKey: UUID) async throws -> ActionProviderResult { .unknown(reason: "n/a") }

    func waitUntilCalled() async {
        if called { return }
        await withCheckedContinuation { calledWaiters.append($0) }
    }

    func release() {
        released = true
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}
