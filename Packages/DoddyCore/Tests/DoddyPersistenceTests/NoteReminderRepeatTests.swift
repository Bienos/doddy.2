import DoddyCore
@testable import DoddyPersistence
import Foundation
import GRDB
import XCTest

/// Repeating note reminders and snooze (ADR-200, owner-approved design screens 15–21) against real
/// SQLite and a fake iOS notification center. Times are in Warsaw; 25 Oct 2026 is a clock change.
final class NoteReminderRepeatTests: XCTestCase {
    // Sat 10 Oct 2026, 13:02 in Warsaw.
    private let now = Date(timeIntervalSince1970: 1_791_630_120)
    private let warsaw = TimeZone(identifier: "Europe/Warsaw")!
    private let zone = "Europe/Warsaw"
    private let monday20 = Date(timeIntervalSince1970: 1_791_828_000)  // Mon 12 Oct, 20:00

    private func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

    // MARK: Schedule arithmetic (pure)

    func testMatchesAndNextOccurrencesKeepTheClockTimeAcrossTheClockChange() {
        let sat24 = at(1_792_821_600)  // Sat 24 Oct, 08:00 (summer time)
        XCTAssertEqual(ReminderSchedule.matches(.daily, anchor: sat24, timeZoneID: zone).count, 1)
        XCTAssertEqual(ReminderSchedule.matches(.weekdays, anchor: sat24, timeZoneID: zone).map(\.weekday), [2, 3, 4, 5, 6])
        XCTAssertEqual(ReminderSchedule.matches(.weekly, anchor: monday20, timeZoneID: zone).first?.weekday, 2)
        XCTAssertEqual(ReminderSchedule.matches(.monthly, anchor: monday20, timeZoneID: zone).first?.day, 12)

        // Daily at 08:00: Sun 25 Oct is 25 hours later (clocks go back), still 08:00 Warsaw time.
        XCTAssertEqual(ReminderSchedule.next(after: sat24, .daily, anchor: sat24, timeZoneID: zone), at(1_792_911_600))
        XCTAssertEqual(ReminderSchedule.next(after: at(1_792_911_600), .daily, anchor: sat24, timeZoneID: zone), at(1_792_998_000))
        // Weekdays from Saturday skips to Monday.
        XCTAssertEqual(ReminderSchedule.next(after: sat24, .weekdays, anchor: sat24, timeZoneID: zone), at(1_792_998_000))
        // Weekly and monthly.
        XCTAssertEqual(ReminderSchedule.next(after: monday20, .weekly, anchor: monday20, timeZoneID: zone), at(1_792_432_800))
        XCTAssertEqual(ReminderSchedule.next(after: monday20, .monthly, anchor: monday20, timeZoneID: zone), at(1_794_510_000))
        // Previous: the latest at or before, never before the anchor.
        XCTAssertNil(ReminderSchedule.previous(atOrBefore: now, .weekly, anchor: monday20, timeZoneID: zone))
        XCTAssertEqual(ReminderSchedule.previous(atOrBefore: monday20, .weekly, anchor: monday20, timeZoneID: zone), monday20)
        XCTAssertEqual(
            ReminderSchedule.previous(atOrBefore: at(1_793_646_000 - 60), .weekly, anchor: monday20, timeZoneID: zone),
            at(1_792_432_800 + 7 * 86_400 + 3_600), "Mon 26 Oct 20:00 is one hour more after the clock change")
    }

    func testARepeatStartsAtItsNextMatchingTimeAndMonthlyStopsAtThe28th() {
        // Picked "every week" on Mon 2 Nov at 20:00 on Sat 10 Oct: iOS starts at the next Monday.
        let first = ReminderSchedule.firstOccurrence(.weekly, picked: at(1_793_646_000), timeZoneID: zone, now: now, lead: 60)
        XCTAssertEqual(first, monday20)
        // Daily at 13:02 picked now: too close, so tomorrow.
        XCTAssertEqual(
            ReminderSchedule.firstOccurrence(.daily, picked: now, timeZoneID: zone, now: now, lead: 60),
            now.addingTimeInterval(86_400))
        XCTAssertTrue(ReminderSchedule.allows(.monthly, picked: monday20, timeZoneID: zone))
        XCTAssertFalse(ReminderSchedule.allows(.monthly, picked: at(1_793_347_200), timeZoneID: zone), "the 30th")
        XCTAssertTrue(ReminderSchedule.allows(.weekly, picked: at(1_793_347_200), timeZoneID: zone))
    }

    func testWordsForRepeatsAndNotificationIDs() {
        XCTAssertEqual(ReminderFormat.repeatPhrase(.weekly, anchor: monday20, timeZoneID: zone), "Every Monday at 20:00")
        XCTAssertEqual(ReminderFormat.repeatPhrase(.weekdays, anchor: monday20, timeZoneID: zone), "Weekdays at 20:00")
        XCTAssertEqual(ReminderFormat.repeatPhrase(.monthly, anchor: monday20, timeZoneID: zone), "Every month on the 12th at 20:00")
        XCTAssertEqual(ReminderFormat.cadence(.daily, anchor: monday20, timeZoneID: zone), "every day")
        XCTAssertEqual(["1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", "22nd", "23rd"],
                       [1, 2, 3, 4, 11, 12, 13, 21, 22, 23].map(ReminderFormat.ordinal))
        XCTAssertEqual(NoteReminderCopy.title(repeating: .weekly, anchor: monday20, timeZoneID: zone), "Reminder · every Monday")

        let id = UUID()
        XCTAssertEqual(MemoryReminder.reminderID(fromNotificationID: MemoryReminder.notificationID(for: id)), id)
        XCTAssertEqual(MemoryReminder.reminderID(fromNotificationID: MemoryReminder.snoozeNotificationID(for: id)), id)
        XCTAssertEqual(MemoryReminder.reminderID(fromNotificationID: MemoryReminder.weekdayNotificationID(for: id, weekday: 3)), id)
        XCTAssertNil(MemoryReminder.reminderID(fromNotificationID: MemoryReminder.notificationID(for: id) + "x"))
        XCTAssertNil(MemoryReminder.reminderID(fromNotificationID: "doddy.timer." + id.uuidString))
    }

    // MARK: Coordinator against SQLite

    private struct Setup {
        let memories: SQLiteMemoryRepository
        let reminders: SQLiteNoteReminderRepository
        let center: RepeatFakeCenter
        let coordinator: NoteReminderCoordinator
        let clock: Clock
    }

    private func make(auth: NotificationAuthorization = .allowed) throws -> Setup {
        let database = try DoddyDatabase.inMemory()
        let memories = SQLiteMemoryRepository(database: database)
        let reminders = SQLiteNoteReminderRepository(database: database)
        let center = RepeatFakeCenter(auth: auth)
        let clock = Clock(now)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = warsaw
        let cal = calendar
        let coordinator = NoteReminderCoordinator(
            repository: reminders, center: center, now: { clock.value }, showNoteText: { false }, calendar: { cal })
        return Setup(memories: memories, reminders: reminders, center: center, coordinator: coordinator, clock: clock)
    }

    private func note(_ setup: Setup, _ text: String = "Bins go out Monday night. Code for the bin shed: 4412.") async throws -> MemoryRecord {
        try await setup.memories.save(NewMemory(text: text, capturedAt: now))
    }

    func testWeeklyRepeatIsOneVerifiedRepeatingRequestWithTheScheduleInTheTitle() async throws {
        let setup = try make()
        let memory = try await note(setup)
        let outcome = try await setup.coordinator.schedule(memoryID: memory.id, at: monday20, timeZone: warsaw, repeats: .weekly)
        guard case .scheduled(let reminder) = outcome else { return XCTFail("expected .scheduled, got \(outcome)") }

        XCTAssertEqual(reminder.repeats, .weekly)
        XCTAssertEqual(reminder.fireAt, monday20)
        let pending = await setup.center.pending
        XCTAssertEqual(Array(pending.keys), [reminder.notificationID])
        let request = try XCTUnwrap(pending[reminder.notificationID])
        XCTAssertEqual(request.repeatMatch, RepeatMatch(hour: 20, minute: 0, weekday: 2, day: nil, timeZoneID: zone))
        XCTAssertEqual(request.category, .repeating)
        XCTAssertEqual(request.title, "Reminder · every Monday")
        XCTAssertEqual(request.body, NoteReminderCopy.privateBody, "the note text stays hidden")
        let stored = try await setup.reminders.reminder(forMemory: memory.id)
        XCTAssertEqual(stored, reminder)
        XCTAssertEqual(ReminderFormat.summary(reminder), "Every Monday at 20:00 · Warsaw time")
    }

    func testWeekdaysUsesFiveSlotsAndTheLimitCountsSlots() async throws {
        let setup = try make()
        let memory = try await note(setup)
        guard case .scheduled(let reminder) = try await setup.coordinator.schedule(
            memoryID: memory.id, at: monday20, timeZone: warsaw, repeats: .weekdays) else { return XCTFail() }
        let ids = await setup.center.pending.keys.sorted()
        XCTAssertEqual(ids, (2...6).map { MemoryReminder.weekdayNotificationID(for: reminder.id, weekday: $0) }.sorted())
        XCTAssertEqual(reminder.requestSlots, 5)

        // 45 one-off reminders + this weekdays one = 50 slots: one more is refused.
        for index in 0..<45 {
            let other = try await note(setup, "Note \(index)")
            _ = try await setup.coordinator.schedule(memoryID: other.id, at: now.addingTimeInterval(3_600), timeZone: warsaw)
        }
        let extra = try await note(setup, "One too many")
        do {
            _ = try await setup.coordinator.schedule(memoryID: extra.id, at: now.addingTimeInterval(3_600), timeZone: warsaw)
            XCTFail("expected limitReached")
        } catch NoteReminderError.limitReached(let maximum) {
            XCTAssertEqual(maximum, 50)
        }
        // Switching the weekdays note to weekly frees four slots.
        _ = try await setup.coordinator.schedule(memoryID: memory.id, at: monday20, timeZone: warsaw, repeats: .weekly)
        _ = try await setup.coordinator.schedule(memoryID: extra.id, at: now.addingTimeInterval(3_600), timeZone: warsaw)
        let pendingCount = await setup.center.pending.count
        XCTAssertEqual(pendingCount, 47)
    }

    func testMonthlyAfterThe28thAndRepeatsTooSoonAreRefused() async throws {
        let setup = try make()
        let memory = try await note(setup)
        do {
            _ = try await setup.coordinator.schedule(memoryID: memory.id, at: at(1_793_347_200), timeZone: warsaw, repeats: .monthly)
            XCTFail("expected invalidRepeat")
        } catch NoteReminderError.invalidRepeat {}
        let stored = try await setup.reminders.reminder(forMemory: memory.id)
        XCTAssertNil(stored)
    }

    func testDoneThisTimeKeepsTheRepeatAndClearsDueUntilTheNextOccurrence() async throws {
        let setup = try make()
        let memory = try await note(setup)
        guard case .scheduled(let reminder) = try await setup.coordinator.schedule(
            memoryID: memory.id, at: monday20, timeZone: warsaw, repeats: .weekly) else { return XCTFail() }
        XCTAssertFalse(reminder.isDue(at: now))

        // Monday 20:30: due. Done this time: not due, still pending, next is the following Monday.
        setup.clock.value = monday20.addingTimeInterval(1_800)
        XCTAssertTrue(reminder.isDue(at: setup.clock.value))
        try await setup.coordinator.markDone(reminderID: reminder.id)
        let doneRow = try await setup.reminders.reminder(id: reminder.id)
        let done = try XCTUnwrap(doneRow)
        XCTAssertEqual(done.lastDoneAt, setup.clock.value)
        XCTAssertFalse(done.isDue(at: setup.clock.value))
        XCTAssertTrue(done.isDue(at: at(1_792_432_800)), "next Monday is due again")
        XCTAssertEqual(done.nextFire(after: setup.clock.value), at(1_792_432_800))
        let pending = await setup.center.pending.keys.sorted()
        XCTAssertEqual(pending, [reminder.notificationID])

        // A one-off's Done deletes it, as before.
        let other = try await note(setup, "One-off")
        guard case .scheduled(let once) = try await setup.coordinator.schedule(
            memoryID: other.id, at: setup.clock.value.addingTimeInterval(3_600), timeZone: warsaw) else { return XCTFail() }
        try await setup.coordinator.markDone(reminderID: once.id)
        let gone = try await setup.reminders.reminder(id: once.id)
        XCTAssertNil(gone)
    }

    func testSnoozingARepeatAddsOneExtraRequestAndTheRepeatCarriesOn() async throws {
        let setup = try make()
        let memory = try await note(setup)
        guard case .scheduled(let reminder) = try await setup.coordinator.schedule(
            memoryID: memory.id, at: monday20, timeZone: warsaw, repeats: .weekly) else { return XCTFail() }
        setup.clock.value = monday20.addingTimeInterval(60)

        let outcome = try await setup.coordinator.snoozeForAnHour(reminderID: reminder.id)
        guard case .scheduled(let snoozed)? = outcome else { return XCTFail("expected .scheduled, got \(String(describing: outcome))") }
        XCTAssertEqual(snoozed.id, reminder.id)
        XCTAssertEqual(snoozed.snoozedUntil, monday20.addingTimeInterval(3_660))
        XCTAssertFalse(snoozed.isDue(at: setup.clock.value), "this occurrence is handled")
        XCTAssertTrue(snoozed.isDue(at: monday20.addingTimeInterval(3_660)))
        let snoozeID = MemoryReminder.snoozeNotificationID(for: reminder.id)
        let pending = await setup.center.pending
        XCTAssertEqual(Set(pending.keys), [reminder.notificationID, snoozeID])
        XCTAssertEqual(pending[snoozeID]?.trigger, .time(fireAt: monday20.addingTimeInterval(3_660), timeZoneID: zone))
        XCTAssertEqual(pending[snoozeID]?.category, .repeating)

        // Reconcile keeps both; once the snooze is past, it is no longer wanted.
        await setup.coordinator.reconcile()
        let afterReconcile = await setup.center.pending.count
        XCTAssertEqual(afterReconcile, 2)
        setup.clock.value = monday20.addingTimeInterval(4_000)
        try await setup.coordinator.markDone(reminderID: reminder.id)
        let finalPending = await setup.center.pending.keys.sorted()
        XCTAssertEqual(finalPending, [reminder.notificationID])
        let storedRow = try await setup.reminders.reminder(id: reminder.id)
        let stored = try XCTUnwrap(storedRow)
        XCTAssertNil(stored.snoozedUntil)

        // Stop repeating removes every request.
        try await setup.coordinator.remove(reminderID: reminder.id)
        let empty = await setup.center.pending.isEmpty
        XCTAssertTrue(empty)
    }

    func testSnoozingAOneOffMovesItAndRemembersTheFirstTime() async throws {
        let setup = try make()
        let memory = try await note(setup)
        let first = now.addingTimeInterval(1_800)
        guard case .scheduled(let reminder) = try await setup.coordinator.schedule(
            memoryID: memory.id, at: first, timeZone: warsaw) else { return XCTFail() }
        setup.clock.value = first.addingTimeInterval(60)

        guard case .scheduled(let moved)? = try await setup.coordinator.snoozeForAnHour(reminderID: reminder.id) else { return XCTFail() }
        XCTAssertEqual(moved.fireAt, first.addingTimeInterval(3_660))
        XCTAssertEqual(moved.firstSetFor, first)
        guard case .scheduled(let movedAgain)? = try await setup.coordinator.snoozeUntilTomorrowMorning(reminderID: moved.id) else { return XCTFail() }
        XCTAssertEqual(movedAgain.firstSetFor, first, "still the time it was first set for")
        XCTAssertEqual(movedAgain.fireAt, at(1_791_702_000), "Sun 11 Oct, 09:00")
        let pending = await setup.center.pending.keys.sorted()
        XCTAssertEqual(pending, [movedAgain.notificationID])
    }

    func testRefusedSnoozeLeavesTheRepeatUnchanged() async throws {
        let setup = try make()
        let memory = try await note(setup)
        guard case .scheduled(let reminder) = try await setup.coordinator.schedule(
            memoryID: memory.id, at: monday20, timeZone: warsaw, repeats: .daily) else { return XCTFail() }
        setup.clock.value = monday20.addingTimeInterval(60)
        await setup.center.setDropsRequests(true)
        do {
            _ = try await setup.coordinator.snoozeForAnHour(reminderID: reminder.id)
            XCTFail("expected notScheduled")
        } catch NoteReminderError.notScheduled {}
        let stored = try await setup.reminders.reminder(id: reminder.id)
        XCTAssertEqual(stored, reminder)
        let pending = await setup.center.pending.keys.sorted()
        XCTAssertEqual(pending, [reminder.notificationID])
    }

    func testPlacesHaveNoSnoozeAndTheDatabaseRefusesARepeatOnAPlace() async throws {
        let setup = try make()
        let memory = try await note(setup)
        let place = try ReminderPlace(name: "Post office", latitude: 52.2, longitude: 21.0, radiusMeters: 200, onArrival: true)
        guard case .scheduled(let reminder) = try await setup.coordinator.schedule(memoryID: memory.id, place: place) else { return XCTFail() }
        let snoozed = try await setup.coordinator.snoozeForAnHour(reminderID: reminder.id)
        XCTAssertNil(snoozed)
        let request = await setup.center.pending[reminder.notificationID]
        XCTAssertEqual(request?.category, .place)

        let invalid = MemoryReminder(id: UUID(), memoryID: memory.id, trigger: .place(place), createdAt: now, repeats: .weekly)
        do {
            _ = try await setup.reminders.upsertReminder(invalid)
            XCTFail("a repeat on a place must not be stored")
        } catch {}
    }

    func testRepeatFieldsRoundTripThroughSQLite() async throws {
        let setup = try make()
        let memory = try await note(setup)
        let reminder = MemoryReminder(
            id: UUID(), memoryID: memory.id, trigger: .time(fireAt: monday20, timeZoneID: zone), createdAt: now,
            repeats: .monthly, lastDoneAt: monday20, snoozedUntil: monday20.addingTimeInterval(3_600))
        let stored = try await setup.reminders.upsertReminder(reminder)
        XCTAssertEqual(stored, reminder)
        let once = MemoryReminder(
            id: UUID(), memoryID: memory.id, trigger: .time(fireAt: monday20, timeZoneID: zone), createdAt: now,
            firstSetFor: now.addingTimeInterval(600))
        let storedOnce = try await setup.reminders.upsertReminder(once)
        XCTAssertEqual(storedOnce, once)
    }
}

private actor RepeatFakeCenter: NoteNotificationScheduling {
    private(set) var pending: [String: NoteReminderNotification] = [:]
    private var auth: NotificationAuthorization
    private var dropsRequests = false

    init(auth: NotificationAuthorization) { self.auth = auth }

    func setDropsRequests(_ value: Bool) { dropsRequests = value }

    func authorization() async -> NotificationAuthorization { auth }
    func requestAuthorization() async -> NotificationAuthorization { auth }
    func locationReadiness() async -> LocationReadiness { .ready }
    func add(_ notification: NoteReminderNotification) async throws {
        guard auth == .allowed else { throw NoteReminderError.notScheduled }
        if !dropsRequests { pending[notification.identifier] = notification }
    }
    func pendingIdentifiers() async -> Set<String> { Set(pending.keys) }
    func deliveredIdentifiers() async -> Set<String> { [] }
    func remove(_ identifiers: [String]) async { identifiers.forEach { pending[$0] = nil } }
}

private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Date
    init(_ value: Date) { stored = value }
    var value: Date {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
