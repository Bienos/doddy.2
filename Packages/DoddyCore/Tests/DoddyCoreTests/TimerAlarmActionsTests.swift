import XCTest
@testable import DoddyCore

/// ADR-320: timers and alarms in the action status model. A timer or alarm Doddy couldn't
/// confirm is checked before it is tried again; "set" only when the iPhone lists it.
/// Notifications and AlarmKit themselves are only exercised on a device.
final class TimerAlarmActionsTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }()

    /// Sat 10 Oct 2026, 12:00 in Warsaw.
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 12))! }

    private let eggs = TimerDraft(seconds: 600, label: "Eggs")

    private func alarm(_ day: Int = 12, _ hour: Int = 7, repeats: AlarmRepeat? = nil, label: String? = "Gym") -> AlarmDraft {
        AlarmDraft(first: ReminderDue(year: 2026, month: 10, day: day, hour: hour, minute: 0, timeZoneID: "Europe/Warsaw"), repeats: repeats, label: label)
    }

    // MARK: Keys

    func testTheSameTimerOrAlarmAskedAgainHasTheSameKey() {
        XCTAssertEqual(TimerIdempotency.key(eggs), TimerIdempotency.key(TimerDraft(seconds: 600, label: " eggs ")))
        XCTAssertNotEqual(TimerIdempotency.key(eggs), TimerIdempotency.key(TimerDraft(seconds: 300, label: "Eggs")))
        XCTAssertNotEqual(TimerIdempotency.key(eggs), TimerIdempotency.key(TimerDraft(seconds: 600, label: nil)))

        XCTAssertEqual(AlarmIdempotency.key(alarm()), AlarmIdempotency.key(alarm(label: "gym")))
        XCTAssertNotEqual(AlarmIdempotency.key(alarm()), AlarmIdempotency.key(alarm(13)))
        XCTAssertNotEqual(AlarmIdempotency.key(alarm()), AlarmIdempotency.key(alarm(8)))
        // A repeating alarm is the same whichever day it was first asked on.
        XCTAssertEqual(AlarmIdempotency.key(alarm(12, repeats: .weekdays)), AlarmIdempotency.key(alarm(13, repeats: .weekdays)))
        XCTAssertNotEqual(AlarmIdempotency.key(alarm(12, repeats: .weekdays)), AlarmIdempotency.key(alarm(12, repeats: .weekends)))

        let describe = { ActivityRequest.describe($0, calendar: self.calendar)?.operationKey }
        XCTAssertEqual(describe(.setTimer(eggs)), TimerIdempotency.key(eggs))
        XCTAssertEqual(describe(.setAlarm(alarm())), AlarmIdempotency.key(alarm()))
    }

    func testTheTimerKeyTravelsInItsIdentifier() {
        let key = TimerIdempotency.key(eggs)
        let identifier = TimerIdempotency.identifier(key: key, id: UUID())
        XCTAssertEqual(TimerIdempotency.key(fromIdentifier: identifier), key)
        XCTAssertNil(TimerIdempotency.key(fromIdentifier: "doddy.timer.\(UUID().uuidString)"), "timers set before ADR-320")
        XCTAssertNil(TimerIdempotency.key(fromIdentifier: "other.\(key).x"))
    }

    // MARK: Timers

    @MainActor
    func testATimerStartsAndReportsTheRingTimeTheIPhoneLists() async {
        let writer = FakeTimerWriter(now: now)
        let outcome = await TimerStartAction.start(eggs, with: writer, uncheckedSince: nil)
        guard case .started(let timer) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(timer.firesAt, now + 600)
        XCTAssertEqual(TimerIdempotency.key(fromIdentifier: timer.identifier), TimerIdempotency.key(eggs))
        XCTAssertTrue(outcome.attemptedWrite)
    }

    @MainActor
    func testTwoIdenticalTimersAskedOnPurposeBothRun() async {
        let writer = FakeTimerWriter(now: now)
        _ = await TimerStartAction.start(eggs, with: writer, uncheckedSince: nil)
        guard case .started = await TimerStartAction.start(eggs, with: writer, uncheckedSince: nil) else { return XCTFail() }
        XCTAssertEqual(writer.pending.count, 2, "no earlier try was unsure, so nothing is looked for")
    }

    @MainActor
    func testAfterAnUnconfirmedTryTheRunningTimerIsFoundNotDoubled() async {
        let writer = FakeTimerWriter(now: now)
        writer.hideNext = true
        let result1 = await TimerStartAction.start(eggs, with: writer, uncheckedSince: nil)
        XCTAssertEqual(result1, .unknown)
        XCTAssertEqual(writer.pending.count, 1, "it was set; the look just didn't show it")

        writer.now = now + 30
        let again = await TimerStartAction.start(eggs, with: writer, uncheckedSince: now)
        guard case .alreadyRunning(let running) = again else { return XCTFail("\(again)") }
        XCTAssertEqual(running.firesAt, now + 600)
        XCTAssertFalse(again.attemptedWrite)
        XCTAssertEqual(writer.schedules, 1)
    }

    @MainActor
    func testAnOlderTimerOrAnotherTimerIsNotMistakenForTheUnsureTry() async {
        let writer = FakeTimerWriter(now: now)
        // Started an hour before the unsure try: a different run of the same timer.
        writer.pending = [PendingTimer(identifier: TimerIdempotency.identifier(key: TimerIdempotency.key(eggs), id: UUID()), firesAt: now - 3_600 + 600 + 20)]
        // Same moment, but another timer.
        writer.pending.append(PendingTimer(identifier: TimerIdempotency.identifier(key: TimerIdempotency.key(TimerDraft(seconds: 600, label: "Tea")), id: UUID()), firesAt: now + 600))
        guard case .started = await TimerStartAction.start(eggs, with: writer, uncheckedSince: now) else { return XCTFail() }
        XCTAssertEqual(writer.schedules, 1)
    }

    @MainActor
    func testAFailedTimerIsLookedForBeforeAnswering() async {
        let writer = FakeTimerWriter(now: now)
        writer.behaviour = .writeThenThrow
        guard case .started = await TimerStartAction.start(eggs, with: writer, uncheckedSince: nil) else { return XCTFail("it went in") }
        writer.behaviour = .throwOnly
        let result2 = await TimerStartAction.start(eggs, with: writer, uncheckedSince: nil)
        XCTAssertEqual(result2, .notStarted("Notifications are full."))
    }

    // MARK: Alarms

    @MainActor
    func testAnAlarmIsSetOnceAndAskingAgainFindsIt() async {
        let writer = FakeAlarmWriter()
        let first = await AlarmSetAction.set(alarm(), with: writer, now: now)
        guard case .set(let set) = first else { return XCTFail("\(first)") }
        XCTAssertEqual(set.key, AlarmIdempotency.key(alarm()))
        XCTAssertEqual(set.summary, "07:00 on 2026-10-12")
        XCTAssertTrue(first.attemptedWrite)

        let again = await AlarmSetAction.set(alarm(label: "gym"), with: writer, now: now)
        XCTAssertEqual(again, .alreadySet(set))
        XCTAssertFalse(again.attemptedWrite)
        XCTAssertEqual(writer.schedules, 1)
    }

    @MainActor
    func testAnAlarmTheIPhoneListsLateIsFoundOnRetry() async {
        let writer = FakeAlarmWriter()
        writer.listLate = true
        let result3 = await AlarmSetAction.set(alarm(), with: writer, now: now)
        XCTAssertEqual(result3, .unknown)
        XCTAssertEqual(writer.book.count, 1, "the note is kept, so a retry can find it once it is listed")

        writer.listLate = false
        writer.publishLate()
        guard case .alreadySet = await AlarmSetAction.set(alarm(), with: writer, now: now) else { return XCTFail() }
        XCTAssertEqual(writer.schedules, 1)
    }

    @MainActor
    func testAnAlarmSetBeforeKeysIsMatchedByTimeDayAndLabel() async {
        let writer = FakeAlarmWriter()
        let old = AlarmEntry(id: UUID(), clock: "07:00", label: "Gym", summary: "07:00 on 2026-10-12")
        writer.book = [old]
        writer.ids = [old.id]
        let result4 = await AlarmSetAction.set(alarm(), with: writer, now: now)
        XCTAssertEqual(result4, .alreadySet(old))
        guard case .set = await AlarmSetAction.set(alarm(label: "Run"), with: writer, now: now) else { return XCTFail("another label is another alarm") }
    }

    @MainActor
    func testAFailedAlarmIsLookedForAndANoForgetsTheNote() async {
        let writer = FakeAlarmWriter()
        writer.behaviour = .writeThenThrow
        guard case .set = await AlarmSetAction.set(alarm(), with: writer, now: now) else { return XCTFail("it went in") }

        let refused = FakeAlarmWriter()
        refused.behaviour = .throwOnly
        let result5 = await AlarmSetAction.set(alarm(), with: refused, now: now)
        XCTAssertEqual(result5, .notSet("AlarmKit refused it."))
        XCTAssertTrue(refused.book.isEmpty, "nothing was set, so nothing is noted")

        let notAllowed = FakeAlarmWriter()
        notAllowed.attempt = .notAllowed
        let result6 = await AlarmSetAction.set(alarm(), with: notAllowed, now: now)
        XCTAssertEqual(result6, .notAllowed)
        XCTAssertTrue(notAllowed.book.isEmpty)
        XCTAssertFalse(AlarmSetOutcome.notAllowed.attemptedWrite)
    }

    @MainActor
    func testAPassedOneOffTimeSetsNothing() async {
        let writer = FakeAlarmWriter()
        guard case .needsClarification = await AlarmSetAction.set(alarm(10, 9), with: writer, now: now) else { return XCTFail() }
        XCTAssertEqual(writer.schedules, 0)
        // A repeating alarm first asked for a past moment still rings on its days.
        guard case .set = await AlarmSetAction.set(alarm(10, 9, repeats: .everyDay), with: writer, now: now) else { return XCTFail() }
    }

    // MARK: Replies, receipts and the log

    func testRepliesLandOnTheRightRowInWhatDoddyDid() {
        func outcome(_ reply: String) -> ActivityOutcome { ActivityEntry.outcome(of: reply, isLookup: false).0 }
        let timer = PendingTimer(identifier: "doddy.timer.t1-x.y", firesAt: now + 600)
        XCTAssertEqual(outcome(VoiceToolReply.timer(.started(timer), draft: eggs, calendar: calendar)), .done)
        let running = VoiceToolReply.timer(.alreadyRunning(timer), draft: eggs, calendar: calendar)
        XCTAssertEqual(outcome(running), .alreadyThere)
        XCTAssertEqual(running, "added: timer \"Eggs\", 10 minutes was already running from the earlier try and rings at 2026-10-10 12:10, so Doddy did not start a second one.")
        XCTAssertEqual(outcome(VoiceToolReply.timer(.unknown, draft: eggs, calendar: calendar)), .notSure)
        XCTAssertEqual(outcome(VoiceToolReply.timer(.notStarted("x."), draft: eggs, calendar: calendar)), .notDone)

        let entry = AlarmEntry(id: UUID(), clock: "07:00", label: "Gym", summary: "07:00 on 2026-10-12")
        XCTAssertEqual(VoiceToolReply.alarm(.set(entry)), VoiceToolReply.alarmSet(alarm()), "the same words as before for a new alarm")
        XCTAssertEqual(outcome(VoiceToolReply.alarm(.alreadySet(entry))), .alreadyThere)
        XCTAssertEqual(outcome(VoiceToolReply.alarm(.unknown)), .notSure)
        XCTAssertEqual(outcome(VoiceToolReply.alarm(.notSet("x."))), .notDone)
        XCTAssertEqual(outcome(VoiceToolReply.alarm(.notAllowed)), .notDone)
        XCTAssertFalse(VoiceToolReply.alarm(.set(entry)).contains(entry.id.uuidString), "the agent never hears AlarmKit's id")
        XCTAssertFalse(VoiceToolReply.timer(.started(timer), draft: eggs, calendar: calendar).contains("doddy.timer"))
    }

    func testReceiptsSayWhatTheIPhoneListed() {
        let timer = PendingTimer(identifier: "doddy.timer.t1-x.y", firesAt: now + 600)
        let receipt = ActivityReceipt(timer: timer, draft: eggs, calendar: calendar, readAt: now)
        XCTAssertEqual(receipt.lines, ["“Eggs”", "10 minutes", "Rings at 2026-10-10 12:10"])
        XCTAssertEqual(receipt.externalID, timer.identifier)
        let entry = AlarmEntry(id: UUID(), clock: "07:00", label: nil, summary: "07:00 on weekdays")
        XCTAssertEqual(ActivityReceipt(alarm: entry, readAt: now).lines, ["Alarm 07:00 on weekdays"])
    }

    func testAnUnsureTimerMakesTheNextTryCheckFirst() {
        let request = ActivityRequest.describe(.setTimer(eggs), calendar: calendar)!
        let unsure = ActivityEntry(request: request, reply: VoiceToolReply.timer(.unknown, draft: eggs, calendar: calendar), at: now, attempted: true)
        let decision = ActionRetry.decide(for: request, in: [unsure], now: now + 60)
        XCTAssertEqual(decision, .checkFirst(since: now))
        XCTAssertEqual(decision.uncheckedSince, now)
        XCTAssertNil(ActionRetryDecision.go.uncheckedSince)
    }
}

@MainActor
private final class FakeTimerWriter: TimerWriter {
    enum Behaviour { case write, writeThenThrow, throwOnly }
    struct Full: LocalizedError { var errorDescription: String? { "Notifications are full." } }

    var now: Date
    var pending: [PendingTimer] = []
    var behaviour = Behaviour.write
    /// The next look after a schedule doesn't show it (then it shows again).
    var hideNext = false
    private(set) var schedules = 0
    private var hidden: String?

    init(now: Date) { self.now = now }

    func pendingTimers() async -> [PendingTimer] {
        defer { hidden = nil }
        return pending.filter { $0.identifier != hidden }
    }

    func scheduleTimer(_ draft: TimerDraft, identifier: String) async throws {
        if behaviour == .throwOnly { throw Full() }
        schedules += 1
        pending.append(PendingTimer(identifier: identifier, firesAt: now + TimeInterval(draft.seconds)))
        if hideNext { hidden = identifier; hideNext = false }
        if behaviour == .writeThenThrow { throw Full() }
    }
}

@MainActor
private final class FakeAlarmWriter: AlarmWriter {
    enum Behaviour { case write, writeThenThrow, throwOnly }
    struct Refused: LocalizedError { var errorDescription: String? { "AlarmKit refused it." } }

    var book: [AlarmEntry] = []
    var ids: Set<UUID> = []
    var behaviour = Behaviour.write
    var attempt = AlarmScheduleAttempt.scheduled
    /// Set alarms aren't listed until `publishLate`.
    var listLate = false
    private var late: Set<UUID> = []
    private(set) var schedules = 0

    func alarms() -> [AlarmEntry] { book.filter { ids.contains($0.id) } }
    func scheduledAlarmIDs() -> Set<UUID> { ids }

    func scheduleAlarm(_ draft: AlarmDraft, id: UUID) async throws -> AlarmScheduleAttempt {
        if behaviour == .throwOnly { throw Refused() }
        guard attempt == .scheduled else { return attempt }
        schedules += 1
        if listLate { late.insert(id) } else { ids.insert(id) }
        if behaviour == .writeThenThrow { throw Refused() }
        return .scheduled
    }

    func publishLate() { ids.formUnion(late); late = [] }
    func remember(_ alarm: AlarmEntry) { book.append(alarm) }
    func forget(_ id: UUID) { book.removeAll { $0.id == id } }
}
