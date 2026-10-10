import XCTest
@testable import DoddyCore

final class ReminderTests: XCTestCase {
    private let tz = "Europe/Warsaw"
    // 2026-10-10 10:00 in Warsaw (UTC+2)
    private let now = Date(timeIntervalSince1970: 1_791_619_200)

    // MARK: A-20: never silently schedule a wrong date or time zone

    func testDueParsingAcceptsOnlyUnambiguousLocalDates() {
        XCTAssertEqual(ReminderDueInput.parse(nil, timeZoneID: tz, now: now), .none)
        XCTAssertEqual(ReminderDueInput.parse("2026-10-11", timeZoneID: tz, now: now),
                       .due(ReminderDue(year: 2026, month: 10, day: 11, timeZoneID: tz)))
        XCTAssertEqual(ReminderDueInput.parse("2026-10-11T17:30", timeZoneID: tz, now: now),
                       .due(ReminderDue(year: 2026, month: 10, day: 11, hour: 17, minute: 30, timeZoneID: tz)))
        XCTAssertEqual(ReminderDueInput.parse("2026-10-10", timeZoneID: tz, now: now),
                       .due(ReminderDue(year: 2026, month: 10, day: 10, timeZoneID: tz)), "today without a time is fine")
        for unclear in ["tomorrow at 5", "2026-10-11T17:30Z", "2026-10-11T17:30+01:00", "2026-02-30", "11/10/2026",
                        "2026-10-10T09:00", "2026-03-29T02:30"] {
            guard case .needsClarification = ReminderDueInput.parse(unclear, timeZoneID: tz, now: now) else {
                return XCTFail("\(unclear) must need clarification")
            }
        }
    }

    func testDueComparisonToleratesStorageDifferences() {
        let warsaw = ReminderDue(year: 2026, month: 10, day: 11, hour: 17, minute: 0, timeZoneID: "Europe/Warsaw")
        let utc = ReminderDue(year: 2026, month: 10, day: 11, hour: 15, minute: 0, timeZoneID: "UTC")
        XCTAssertTrue(ReminderDue.same(warsaw, utc), "same instant written in another zone")
        XCTAssertFalse(ReminderDue.same(warsaw, ReminderDue(year: 2026, month: 10, day: 11, hour: 17, minute: 0, timeZoneID: "UTC")))
        XCTAssertTrue(ReminderDue.same(ReminderDue(year: 2026, month: 10, day: 11, timeZoneID: tz),
                                       ReminderDue(year: 2026, month: 10, day: 11, timeZoneID: "UTC")))
        XCTAssertFalse(ReminderDue.same(warsaw, nil))
    }

    func testStateMachineRefusesShortcuts() {
        XCTAssertFalse(ActionState.readyForConfirmation.canMove(to: .pendingExternalWrite), "no write without confirmation")
        XCTAssertFalse(ActionState.drafted.canMove(to: .verifiedSucceeded))
        XCTAssertFalse(ActionState.verifiedSucceeded.canMove(to: .pendingExternalWrite), "never write twice")
        XCTAssertTrue(ActionState.userConfirmed.canMove(to: .pendingExternalWrite))
    }

    // MARK: A-21: verified write with external id

    func testConfirmedReminderIsWrittenOnceAndVerified() async throws {
        let (exec, gateway, store) = make()
        let id = UUID()
        let payload = ReminderPayload(title: "Call Anna", due: ReminderDue(year: 2026, month: 10, day: 11, hour: 17, minute: 0, timeZoneID: tz))
        let action = try await exec.confirmAndCreate(payload, operationID: id)
        XCTAssertEqual(action.state, .verifiedSucceeded)
        XCTAssertEqual(action.externalID, "ext-1")
        XCTAssertNotNil(action.verifiedAt)
        let again = try await exec.confirmAndCreate(payload, operationID: id)
        XCTAssertEqual(again.state, .verifiedSucceeded)
        let created = await gateway.created
        XCTAssertEqual(created.count, 1, "confirming twice never writes twice")
        XCTAssertEqual(created.first?.marker, action.marker)
        let states = await store.history[id]
        XCTAssertEqual(states, [.userConfirmed, .pendingExternalWrite, .verifiedSucceeded], "pending is stored before the write")
    }

    func testEmptyTitleAndPastTimeAreRejectedBeforeAnythingIsStored() async throws {
        let (exec, gateway, store) = make()
        await assertThrows(ReminderError.emptyTitle) { _ = try await exec.confirmAndCreate(ReminderPayload(title: "  "), operationID: UUID()) }
        let past = ReminderPayload(title: "x", due: ReminderDue(year: 2026, month: 10, day: 10, hour: 9, minute: 0, timeZoneID: tz))
        await assertThrows(ReminderError.dueInvalid("That time has already passed.")) { _ = try await exec.confirmAndCreate(past, operationID: UUID()) }
        let created = await gateway.created
        let stored = await store.history
        XCTAssertTrue(created.isEmpty)
        XCTAssertTrue(stored.isEmpty)
    }

    // MARK: A-23: permission denied keeps the draft and says so

    func testPermissionDeniedCreatesNothingAndCanBeRetried() async throws {
        let (exec, gateway, _) = make(access: .denied)
        let id = UUID()
        let failed = try await exec.confirmAndCreate(ReminderPayload(title: "Buy milk"), operationID: id)
        XCTAssertEqual(failed.state, .verifiedFailed)
        XCTAssertEqual(failed.errorCode, "permission_denied")
        XCTAssertTrue(ReminderCopy.status(failed).hasPrefix("Not added"))
        let created = await gateway.created
        XCTAssertTrue(created.isEmpty)
        await gateway.setAccess(.granted)
        let ok = try await exec.confirmAndCreate(ReminderPayload(title: "Buy milk"), operationID: id)
        XCTAssertEqual(ok.state, .verifiedSucceeded)
    }

    func testFirstUseAsksForAccess() async throws {
        let (exec, gateway, _) = make(access: .notDetermined)
        let action = try await exec.confirmAndCreate(ReminderPayload(title: "x"), operationID: UUID())
        let asked = await gateway.accessRequests
        XCTAssertEqual(asked, 1)
        XCTAssertEqual(action.state, .verifiedSucceeded)
    }

    // MARK: A-22: unknown outcome is reconciled, never blindly retried

    func testWriteErrorIsCheckedBeforeCallingItFailed() async throws {
        let (exec, gateway, _) = make()
        await gateway.failNextCreate(butWriteAnyway: true)
        let action = try await exec.confirmAndCreate(ReminderPayload(title: "x"), operationID: UUID())
        XCTAssertEqual(action.state, .verifiedSucceeded, "found by its marker")

        await gateway.failNextCreate(butWriteAnyway: false)
        let id = UUID()
        let unknown = try await exec.confirmAndCreate(ReminderPayload(title: "y"), operationID: id)
        XCTAssertEqual(unknown.state, .unknownOutcome)
        let retried = try await exec.confirmAndCreate(ReminderPayload(title: "y"), operationID: id)
        XCTAssertEqual(retried.state, .verifiedSucceeded)
        let titles = await gateway.created.map(\.payload.title)
        XCTAssertEqual(titles.filter { $0 == "y" }.count, 1, "retry after a confirmed miss writes exactly once")
    }

    func testReadBackMismatchIsNotSuccess() async throws {
        let (exec, gateway, _) = make()
        await gateway.corruptNextReadBack()
        let action = try await exec.confirmAndCreate(ReminderPayload(title: "x"), operationID: UUID())
        XCTAssertEqual(action.state, .unknownOutcome)
        XCTAssertEqual(action.errorCode, "mismatch_after_write")
    }

    func testRecoveryAfterInterruption() async throws {
        let (exec, gateway, store) = make()
        let date = now
        var written = ReminderAction(operationID: UUID(), state: .userConfirmed, payload: ReminderPayload(title: "a"), createdAt: date, updatedAt: date)
        try written.move(to: .pendingExternalWrite, at: date)
        _ = try await gateway.create(written.payload, marker: written.marker) // the app was killed right after this
        var lost = ReminderAction(operationID: UUID(), state: .userConfirmed, payload: ReminderPayload(title: "b"), createdAt: date, updatedAt: date)
        try lost.move(to: .pendingExternalWrite, at: date)
        let notStarted = ReminderAction(operationID: UUID(), state: .userConfirmed, payload: ReminderPayload(title: "c"), createdAt: date, updatedAt: date)
        for a in [written, lost, notStarted] { try await store.put(a) }

        let recovered = Dictionary(uniqueKeysWithValues: try await exec.recoverInterrupted().map { ($0.payload.title, $0) })
        XCTAssertEqual(recovered["a"]?.state, .verifiedSucceeded)
        XCTAssertEqual(recovered["b"]?.state, .unknownOutcome)
        XCTAssertEqual(recovered["c"]?.state, .verifiedFailed)
        XCTAssertEqual(recovered["c"]?.errorCode, "interrupted_before_write")
        let created = await gateway.created
        XCTAssertEqual(created.count, 1, "recovery never creates reminders on its own")
    }

    // MARK: Helpers

    private func make(access: RemindersAccess = .granted) -> (ReminderExecutor, FakeGateway, MemoryActionStore) {
        let gateway = FakeGateway(access: access)
        let store = MemoryActionStore()
        let fixed = now
        return (ReminderExecutor(store: store, gateway: gateway, now: { fixed }), gateway, store)
    }

    private func assertThrows(_ expected: ReminderError, _ body: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            try await body()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? ReminderError, expected, file: file, line: line)
        }
    }
}

actor FakeGateway: ReminderGateway {
    struct Created { let id: String; let payload: ReminderPayload; let marker: URL }
    private(set) var created: [Created] = []
    private(set) var accessRequests = 0
    private var current: RemindersAccess
    private var failNext: Bool?
    private var corruptRead = false

    init(access: RemindersAccess) { current = access }

    func setAccess(_ a: RemindersAccess) { current = a }
    func failNextCreate(butWriteAnyway: Bool) { failNext = butWriteAnyway }
    func corruptNextReadBack() { corruptRead = true }

    func access() async -> RemindersAccess { current }
    func requestAccess() async throws -> Bool {
        accessRequests += 1
        current = .granted
        return true
    }
    func create(_ payload: ReminderPayload, marker: URL) async throws -> String {
        let id = "ext-\(created.count + 1)"
        if let writeAnyway = failNext {
            failNext = nil
            if writeAnyway { created.append(Created(id: id, payload: payload, marker: marker)) }
            throw URLError(.unknown)
        }
        created.append(Created(id: id, payload: payload, marker: marker))
        return id
    }
    func fetch(id: String) async throws -> ExternalReminder? {
        guard let c = created.first(where: { $0.id == id }) else { return nil }
        if corruptRead { corruptRead = false; return ExternalReminder(id: id, title: "changed", due: nil, listTitle: "Reminders") }
        return ExternalReminder(id: id, title: c.payload.title, due: c.payload.due, listTitle: "Reminders")
    }
    func find(marker: URL) async throws -> ExternalReminder? {
        guard let c = created.first(where: { $0.marker == marker }) else { return nil }
        return ExternalReminder(id: c.id, title: c.payload.title, due: c.payload.due, listTitle: "Reminders")
    }
}

actor MemoryActionStore: ReminderActionStore {
    private var rows: [UUID: ReminderAction] = [:]
    private(set) var history: [UUID: [ActionState]] = [:]

    func get(_ id: UUID) async throws -> ReminderAction? { rows[id] }
    func put(_ a: ReminderAction) async throws {
        rows[a.operationID] = a
        history[a.operationID, default: []].append(a.state)
    }
    func recent(limit: Int) async throws -> [ReminderAction] { Array(rows.values.sorted { $0.createdAt > $1.createdAt }.prefix(limit)) }
    func inStates(_ states: [ActionState]) async throws -> [ReminderAction] { rows.values.filter { states.contains($0.state) } }
}

final class ReminderVoiceToolTests: XCTestCase {
    func testCreateReminderToolParsesAndRepliesHonestly() throws {
        let json = Data(#"{"title":"Call Anna","due":"2026-10-11T17:30","notes":"about Friday"}"#.utf8)
        XCTAssertEqual(VoiceToolRequest.parse(name: "create_reminder", parametersJSON: json),
                       .createReminder(title: "Call Anna", due: "2026-10-11T17:30", notes: "about Friday"))
        XCTAssertEqual(VoiceToolRequest.parse(name: "create_reminder", parametersJSON: Data("{}".utf8)), .invalid(name: "create_reminder", reason: "missing title"))
        XCTAssertTrue(VoiceToolReply.reminder(nil).hasPrefix("declined"))
        let date = Date(timeIntervalSince1970: 1_791_619_200)
        var action = ReminderAction(operationID: UUID(), state: .userConfirmed, payload: ReminderPayload(
            title: "Call Anna", due: ReminderDue(year: 2026, month: 10, day: 11, hour: 17, minute: 30, timeZoneID: "Europe/Warsaw")),
            createdAt: date, updatedAt: date)
        try action.move(to: .pendingExternalWrite, at: date)
        let pending = action
        try action.move(to: .verifiedSucceeded, at: date, externalID: "x")
        // The live agent only says "added" when the reply starts with it.
        XCTAssertEqual(VoiceToolReply.reminder(action), "added: reminder \"Call Anna\" due 2026-10-11 17:30 (Europe/Warsaw).")
        var unknown = pending
        try unknown.move(to: .unknownOutcome, at: date)
        XCTAssertTrue(VoiceToolReply.reminder(unknown).hasPrefix("unknown:"))
        var failed = ReminderAction(operationID: UUID(), state: .userConfirmed, payload: ReminderPayload(title: "x"), createdAt: date, updatedAt: date)
        try failed.move(to: .verifiedFailed, at: date, errorCode: "permission_denied")
        XCTAssertTrue(VoiceToolReply.reminder(failed).hasPrefix("failed:"))
    }
}
