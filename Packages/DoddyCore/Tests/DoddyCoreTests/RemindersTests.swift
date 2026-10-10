import Foundation
import XCTest
@testable import DoddyCore

/// Apple Reminders through the ledger (M4), against a fake EventKit client. The real
/// EventKit client is app code and needs a device (docs/implementation/M4_REMINDERS_STATUS.md).
final class RemindersTests: XCTestCase {
    private let warsaw = TimeZone(identifier: "Europe/Warsaw")!
    private let list = ReminderList(id: "list-1", title: "Reminders")
    /// 2026-10-11 18:00 in Warsaw (UTC+2).
    private let due = Date(timeIntervalSince1970: 1_791_734_400)

    private func spec(title: String = "Call the dentist", due: Date? = nil, zone: TimeZone? = nil) -> ReminderSpec {
        ReminderSpec(title: title, due: due ?? self.due, timeZone: zone ?? warsaw, list: list)
    }

    private func setup(_ client: FakeRemindersClient) -> ActionLedger {
        ActionLedger(adapters: [SimulatedActionAdapter(), RemindersActionAdapter(client: client)])
    }

    private func approved(_ ledger: ActionLedger, _ spec: ReminderSpec? = nil) async throws -> ActionRecord {
        let payload = try ActionPayload.reminder(spec ?? self.spec())
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

    // MARK: Payload: the exact moment, its zone and the list are what gets approved

    func testPayloadShowsOffsetZoneAndListAndRoundTrips() throws {
        let payload = try ActionPayload.reminder(spec())
        XCTAssertEqual(payload.type, .createReminder)
        XCTAssertEqual(payload.target, "Reminders")
        XCTAssertEqual(payload.value(for: "title"), "Call the dentist")
        XCTAssertEqual(payload.value(for: "due"), "2026-10-11T18:00:00+02:00")
        XCTAssertEqual(payload.value(for: "timeZone"), "Europe/Warsaw")
        XCTAssertEqual(try ReminderSpec(payload: payload), spec())
    }

    func testSameMomentInAnotherZoneIsADifferentPayload() throws {
        let other = try ActionPayload.reminder(spec(zone: TimeZone(identifier: "Europe/London")!))
        XCTAssertEqual(other.value(for: "due"), "2026-10-11T17:00:00+01:00")
        XCTAssertNotEqual(other, try ActionPayload.reminder(spec()))
    }

    func testNoDueDateHasNoTimeFields() throws {
        let payload = try ActionPayload.reminder(ReminderSpec(title: "Buy milk", due: nil, timeZone: warsaw, list: list))
        XCTAssertNil(payload.value(for: "due"))
        XCTAssertNil(payload.value(for: "timeZone"))
        XCTAssertNil(try ReminderSpec(payload: payload).due)
    }

    func testBlankTitleIsRefused() {
        XCTAssertThrowsError(try ActionPayload.reminder(spec(title: "  "))) {
            XCTAssertEqual($0 as? ActionPayloadError, .missingField("title"))
        }
    }

    // MARK: Permission (checked before and at execution)

    func testNoAccessLeavesDraftAndApprovalUntouched() async throws {
        let client = FakeRemindersClient(authorization: .denied)
        let ledger = setup(client)
        let record = try await approved(ledger)
        do {
            _ = try await ledger.execute(record.id)
            XCTFail("expected notReady")
        } catch let ActionPolicyError.notReady(reason) {
            XCTAssertTrue(reason.contains("Reminders access is off"))
            XCTAssertTrue(reason.contains("Nothing was added"))
        }
        let after = try await ledger.record(record.id)
        XCTAssertEqual(after.status, .needsApproval)
        XCTAssertNotNil(after.approval)
        let writes = await client.createCount
        XCTAssertEqual(writes, 0)

        await client.setAuthorization(.granted)
        let done = try await ledger.execute(record.id)
        XCTAssertEqual(done.status, .confirmed)
    }

    func testAccessRevokedBetweenCheckAndWriteFailsWithoutWriting() async throws {
        let client = FakeRemindersClient(authorization: .granted)
        await client.revokeAfterChecks(1)
        let ledger = setup(client)
        let done = try await ledger.execute(try await approved(ledger).id)
        XCTAssertEqual(done.status, .failed)
        let writes = await client.createCount
        XCTAssertEqual(writes, 0)
    }

    // MARK: Verified write

    func testConfirmedOnlyAfterTheReminderIsFoundAgain() async throws {
        let client = FakeRemindersClient(authorization: .granted)
        let ledger = setup(client)
        let done = try await ledger.execute(try await approved(ledger).id)
        XCTAssertEqual(done.status, .confirmed)
        XCTAssertFalse(done.isSimulation)
        XCTAssertEqual(done.connectorID, "apple-reminders")
        let stored = await client.reminders
        XCTAssertEqual(stored.count, 1)
        let write = try XCTUnwrap(stored[done.providerReference ?? ""])
        XCTAssertEqual(write.title, "Call the dentist")
        XCTAssertEqual(write.due, due)
        XCTAssertEqual(write.timeZone, warsaw)
        XCTAssertEqual(write.listID, "list-1")
        XCTAssertEqual(write.markerURL, RemindersMarker.url(for: try XCTUnwrap(done.idempotencyKey)))
        XCTAssertTrue(ActionStatusCopy.summary(done).contains("Doddy found it there"))
    }

    func testSavedButNotFoundAgainIsUnknown() async throws {
        let client = FakeRemindersClient(authorization: .granted)
        await client.setHideWrites(true)
        let ledger = setup(client)
        let done = try await ledger.execute(try await approved(ledger).id)
        XCTAssertEqual(done.status, .unknown)
        XCTAssertNil(done.providerReference)
    }

    func testFailedSaveThatActuallyWroteIsConfirmed() async throws {
        let client = FakeRemindersClient(authorization: .granted)
        await client.setCreateFailure(.throwAfterWriting)
        let ledger = setup(client)
        let done = try await ledger.execute(try await approved(ledger).id)
        XCTAssertEqual(done.status, .confirmed, "looked before calling it failed")
    }

    func testFailedSaveWithNothingWrittenIsFailed() async throws {
        let client = FakeRemindersClient(authorization: .granted)
        await client.setCreateFailure(.throwWithoutWriting)
        let ledger = setup(client)
        let done = try await ledger.execute(try await approved(ledger).id)
        XCTAssertEqual(done.status, .failed)
        XCTAssertEqual(ActionStatusCopy.summary(done), "Not added to Reminders.")
    }

    func testFailedSaveAndFailedLookupIsUnknownAndNotRetried() async throws {
        let client = FakeRemindersClient(authorization: .granted)
        await client.setCreateFailure(.throwWithoutWriting)
        await client.setLookupFails(afterCalls: 1)
        let ledger = setup(client)
        let record = try await approved(ledger)
        let done = try await ledger.execute(record.id)
        XCTAssertEqual(done.status, .unknown)
        await assertThrows(.reconcileFirst) { _ = try await ledger.execute(record.id) }
        let writes = await client.createCount
        XCTAssertEqual(writes, 1)
    }

    func testMissingListFailsWithoutWriting() async throws {
        let client = FakeRemindersClient(authorization: .granted)
        let ledger = setup(client)
        let record = try await approved(ledger)
        await client.removeList("list-1")
        let done = try await ledger.execute(record.id)
        XCTAssertEqual(done.status, .failed)
        XCTAssertTrue(done.failureReason?.contains("no longer exists") ?? false)
        let writes = await client.createCount
        XCTAssertEqual(writes, 0)
    }

    func testExistingReminderWithSameKeyIsNotWrittenTwice() async throws {
        let client = FakeRemindersClient(authorization: .granted)
        let adapter = RemindersActionAdapter(client: client)
        let key = UUID()
        let request = ActionExecutionRequest(actionID: UUID(), payload: try .reminder(spec()), idempotencyKey: key)
        let first = try await adapter.execute(request)
        let second = try await adapter.execute(request)
        XCTAssertEqual(first, second)
        let writes = await client.createCount
        XCTAssertEqual(writes, 1)
    }

    // MARK: Reconcile (status check only)

    func testReconcileFindsTheReminderOrReportsItMissing() async throws {
        let client = FakeRemindersClient(authorization: .granted)
        await client.setHideWrites(true)
        let ledger = setup(client)
        let record = try await approved(ledger)
        _ = try await ledger.execute(record.id)
        await client.setHideWrites(false)
        let reconciled = try await ledger.reconcile(record.id)
        XCTAssertEqual(reconciled.status, .confirmed)
        let writes = await client.createCount
        XCTAssertEqual(writes, 1)

        let adapter = RemindersActionAdapter(client: client)
        let missing = try await adapter.status(idempotencyKey: UUID())
        guard case .failed = missing else { return XCTFail("expected failed, got \(missing)") }
        await client.setAuthorization(.denied)
        let noAccess = try await adapter.status(idempotencyKey: UUID())
        guard case .unknown = noAccess else { return XCTFail("expected unknown, got \(noAccess)") }
    }

    // MARK: Ledger readiness is race-safe

    func testSecondExecuteDuringReadinessCheckIsRefused() async throws {
        let client = FakeRemindersClient(authorization: .granted)
        await client.setAuthorizationDelay(nanoseconds: 50_000_000)
        let ledger = setup(client)
        let record = try await approved(ledger)
        async let a = Result { try await ledger.execute(record.id) }
        async let b = Result { try await ledger.execute(record.id) }
        let results = await [a, b]
        XCTAssertEqual(results.filter { (try? $0.get())?.status == .confirmed }.count, 1)
        let writes = await client.createCount
        XCTAssertEqual(writes, 1)
    }

    func testCancelDuringReadinessCheckStopsTheWrite() async throws {
        let client = FakeRemindersClient(authorization: .granted)
        await client.setAuthorizationDelay(nanoseconds: 50_000_000)
        let ledger = setup(client)
        let record = try await approved(ledger)
        let execution = Task { try await ledger.execute(record.id) }
        try await Task.sleep(nanoseconds: 10_000_000)
        _ = try await ledger.cancel(record.id)
        do {
            _ = try await execution.value
            XCTFail("expected the execution to be refused")
        } catch {
            XCTAssertEqual(error as? ActionPolicyError, .alreadyFinished(.cancelled))
        }
        let writes = await client.createCount
        XCTAssertEqual(writes, 0)
    }

    func testMarkerMatchesURLOrNote() {
        let key = UUID()
        XCTAssertTrue(RemindersMarker.matches(url: RemindersMarker.url(for: key), notes: nil, reference: key))
        XCTAssertTrue(RemindersMarker.matches(url: nil, notes: "my edit\n" + RemindersMarker.note(for: key), reference: key))
        XCTAssertFalse(RemindersMarker.matches(url: RemindersMarker.url(for: UUID()), notes: "Ref: other", reference: key))
    }

    func testRemindersCatalogAndPrivacy() {
        XCTAssertTrue(CapabilityCatalog.m4Reminders.isAvailable(.reminders))
        XCTAssertTrue(CapabilityCatalog.m4Reminders.isAvailable(.actionSimulation))
        XCTAssertFalse(CapabilityCatalog.m4Reminders.isAvailable(.connectedAccounts))
        XCTAssertTrue(PrivacyDefaults.m4Reminders.remindersUsed)
        XCTAssertFalse(PrivacyDefaults.v1Voice.remindersUsed)
        XCTAssertEqual(PrivacyDefaults.m4Reminders.networkRequestsMade, PrivacyDefaults.v1Voice.networkRequestsMade)
    }
}

/// In-memory stand-in for EventKit with switches for each failure the adapter must handle.
actor FakeRemindersClient: RemindersClient {
    enum CreateFailure { case throwAfterWriting, throwWithoutWriting }
    struct Failure: Error {}

    private var auth: RemindersAuthorization
    private var lists: [String: ReminderList] = ["list-1": ReminderList(id: "list-1", title: "Reminders")]
    private(set) var reminders: [String: ReminderWrite] = [:]
    private(set) var createCount = 0
    private var createFailure: CreateFailure?
    private var hideWrites = false
    private var lookupFailsAfter: Int?
    private var lookups = 0
    private var revokeAfter: Int?
    private var authChecks = 0
    private var authDelay: UInt64 = 0

    init(authorization: RemindersAuthorization) { self.auth = authorization }

    func setAuthorization(_ value: RemindersAuthorization) { auth = value }
    func setCreateFailure(_ value: CreateFailure?) { createFailure = value }
    func setHideWrites(_ value: Bool) { hideWrites = value }
    func setLookupFails(afterCalls: Int) { lookupFailsAfter = afterCalls }
    func revokeAfterChecks(_ count: Int) { revokeAfter = count }
    func setAuthorizationDelay(nanoseconds: UInt64) { authDelay = nanoseconds }
    func removeList(_ id: String) { lists[id] = nil }

    func authorization() async -> RemindersAuthorization {
        if authDelay > 0 { try? await Task.sleep(nanoseconds: authDelay) }
        authChecks += 1
        if let revokeAfter, authChecks > revokeAfter { return .denied }
        return auth
    }

    func requestAccess() async throws -> Bool { auth == .granted }
    func defaultList() async -> ReminderList? { lists.values.first }
    func list(id: String) async -> ReminderList? { lists[id] }

    func create(_ write: ReminderWrite) async throws -> String {
        createCount += 1
        if createFailure == .throwWithoutWriting { throw Failure() }
        let id = "ek-\(createCount)"
        reminders[id] = write
        if createFailure == .throwAfterWriting { throw Failure() }
        return id
    }

    func findReminder(reference: UUID) async throws -> String? {
        lookups += 1
        if let lookupFailsAfter, lookups > lookupFailsAfter { throw Failure() }
        if hideWrites { return nil }
        return reminders.first { RemindersMarker.matches(url: $0.value.markerURL, notes: $0.value.markerNote, reference: reference) }?.key
    }
}

private extension Result where Failure == Error {
    init(catching body: () async throws -> Success) async {
        do { self = .success(try await body()) } catch { self = .failure(error) }
    }
}
