import DoddyCore
import Foundation
import GRDB
import XCTest
@testable import DoddyPersistence

/// Real SQLite, no mocks: round trip, reopen, schema rules, corruption, crash during a send.
final class SQLiteActionStoreTests: XCTestCase {
    private func tempPath() -> String {
        FileManager.default.temporaryDirectory.appendingPathComponent("doddy-actions-\(UUID()).sqlite").path
    }

    private func approve(_ ledger: ActionLedger, text: String) async throws -> ActionRecord {
        let payload = try ActionPayload.message(to: "Marta Łęcka", text: text)
        let record = try await ledger.propose(ActionProposal(payload: payload))
        _ = try await ledger.requestApproval(record.id)
        return try await ledger.approve(record.id, reviewedPayload: payload)
    }

    func testRecordsSurviveReopeningExactlyAndApprovalsAreNotStored() async throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let adapter = SimulatedActionAdapter()

        let ledger = ActionLedger(adapters: [adapter], store: try SQLiteActionStore(path: path))
        let confirmed = try await ledger.execute(try await approve(ledger, text: "Zażółć gęślą jaźń 🙂").id)
        let waiting = try await approve(ledger, text: "Second, still waiting")
        XCTAssertNotNil(waiting.approval)

        let reopened = try SQLiteActionStore(path: path)
        let loaded = Dictionary(uniqueKeysWithValues: try reopened.loadAll().map { ($0.id, $0) })
        XCTAssertEqual(loaded[confirmed.id], confirmed)
        XCTAssertEqual(loaded[waiting.id], waiting.storable)
        XCTAssertNil(loaded[waiting.id]?.approval)

        let relaunched = ActionLedger(adapters: [adapter], store: reopened)
        let history = try await relaunched.history()
        XCTAssertEqual(history.map(\.id), [waiting.id, confirmed.id])
    }

    func testCrashDuringSendIsUnknownAfterRelaunchAndReconciledWithoutResending() async throws {
        let path = tempPath()
        let snapshot = tempPath()
        defer {
            try? FileManager.default.removeItem(atPath: path)
            try? FileManager.default.removeItem(atPath: snapshot)
        }
        // Copies the database file while the provider call is in flight: that copy is what a
        // relaunch would find if the app had been killed at that moment.
        let crash = SnapshotAdapter(source: path, destination: snapshot, provider: SimulatedActionAdapter())
        let ledger = ActionLedger(adapters: [crash], store: try SQLiteActionStore(path: path))
        let record = try await approve(ledger, text: "Running late")
        let finished = try await ledger.execute(record.id)
        XCTAssertEqual(finished.status, .confirmed)

        let relaunched = ActionLedger(adapters: [crash], store: try SQLiteActionStore(path: snapshot))
        let recovered = try await relaunched.record(record.id)
        XCTAssertEqual(recovered.status, .unknown)
        XCTAssertEqual(recovered.idempotencyKey, finished.idempotencyKey)

        let reconciled = await relaunched.reconcileAllUnknown()
        XCTAssertEqual(reconciled.map(\.status), [.confirmed])
        XCTAssertEqual(reconciled.first?.providerReference, finished.providerReference)
        let sends = await crash.provider.executeCount
        XCTAssertEqual(sends, 1, "the relaunch only asked for status")
    }

    func testSchemaRefusesConfirmedWithoutReferenceAndSentWithoutKey() throws {
        let store = try SQLiteActionStore.inMemory()
        func insert(status: String, key: String?, reference: String?) throws {
            try store.dbQueue.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO actions (id, type, status, payload_json, idempotency_key, provider_reference,
                                             failure_reason, connector_id, is_simulation, history_json,
                                             created_at_ms, updated_at_ms)
                        VALUES (?, 'send_message', ?, '{}', ?, ?, NULL, 'c', 1, '[]', 0, 0)
                        """,
                    arguments: [UUID().uuidString, status, key, reference])
            }
        }
        XCTAssertThrowsError(try insert(status: "confirmed", key: UUID().uuidString, reference: nil))
        XCTAssertThrowsError(try insert(status: "confirmed", key: UUID().uuidString, reference: "  "))
        XCTAssertThrowsError(try insert(status: "executing", key: nil, reference: nil))
        XCTAssertThrowsError(try insert(status: "failed", key: UUID().uuidString, reference: "ref"))
        XCTAssertThrowsError(try insert(status: "approved", key: nil, reference: nil))
        XCTAssertNoThrow(try insert(status: "drafted", key: nil, reference: nil))
    }

    func testDamagedRowIsReportedNotTrusted() async throws {
        let store = try SQLiteActionStore.inMemory()
        let ledger = ActionLedger(adapters: [SimulatedActionAdapter()], store: store)
        let record = try await ledger.propose(ActionProposal(payload: .message(to: "A", text: "b")))
        try await store.dbQueue.write { db in
            try db.execute(sql: "UPDATE actions SET history_json = 'not json' WHERE id = ?", arguments: [record.id.uuidString])
        }
        XCTAssertThrowsError(try store.loadAll()) {
            XCTAssertEqual($0 as? ActionStoreError, .corruptRecord(record.id.uuidString))
        }
        let relaunched = ActionLedger(adapters: [SimulatedActionAdapter()], store: store)
        do {
            _ = try await relaunched.history()
            XCTFail("expected storageUnavailable")
        } catch {
            XCTAssertEqual(error as? ActionPolicyError, .storageUnavailable)
        }
    }

    func testDeleteHistoryRemovesRowsFromTheFile() async throws {
        let path = tempPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let ledger = ActionLedger(adapters: [SimulatedActionAdapter()], store: try SQLiteActionStore(path: path))
        _ = try await ledger.propose(ActionProposal(payload: .message(to: "A", text: "private text")))
        try await ledger.deleteHistory()
        XCTAssertEqual(try SQLiteActionStore(path: path).loadAll(), [])
    }
}

/// Copies the SQLite file during the provider call, then forwards to a simulated provider.
actor SnapshotAdapter: ActionAdapter {
    nonisolated let connectorID = "simulation"
    nonisolated let isSimulation = true
    nonisolated let provider: SimulatedActionAdapter
    private let source: String
    private let destination: String

    init(source: String, destination: String, provider: SimulatedActionAdapter) {
        self.source = source
        self.destination = destination
        self.provider = provider
    }

    nonisolated func supports(_ type: ActionType) -> Bool { type == .sendMessage }

    func execute(_ request: ActionExecutionRequest) async throws -> ActionProviderResult {
        try FileManager.default.copyItem(atPath: source, toPath: destination)
        return try await provider.execute(request)
    }

    func status(idempotencyKey: UUID) async throws -> ActionProviderResult {
        try await provider.status(idempotencyKey: idempotencyKey)
    }
}
