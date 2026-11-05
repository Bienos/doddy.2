import DoddyCore
@testable import DoddyPersistence
import Foundation
import GRDB
import XCTest

/// M4a reminder rules against real SQLite and a fake iOS notification center that behaves like
/// UNUserNotificationCenter (same identifier replaces; requests can be refused or silently lost).
/// IDs refer to docs/design/NOTIFICATIONS.md.
final class NoteReminderCoordinatorTests: XCTestCase {
    // Sat 10 Oct 2026, 13:02 in Warsaw (11:02 UTC).
    private let now = Date(timeIntervalSince1970: 1_791_630_120)
    private let warsaw = TimeZone(identifier: "Europe/Warsaw")!

    /// Memories and note reminders share one database, as in the app.
    private struct Repo {
        let memories: SQLiteMemoryRepository
        let reminders: SQLiteNoteReminderRepository
        init(_ database: DoddyDatabase) {
            memories = SQLiteMemoryRepository(database: database)
            reminders = SQLiteNoteReminderRepository(database: database)
        }
        func save(_ draft: NewMemory) async throws -> MemoryRecord { try await memories.save(draft) }
        func update(id: UUID, currentText: String) async throws -> MemoryRecord { try await memories.update(id: id, currentText: currentText) }
        func delete(id: UUID) async throws { try await memories.delete(id: id) }
        func deleteAll() async throws { try await memories.deleteAll() }
        func list(limit: Int?) async throws -> [MemoryRecord] { try await memories.list(limit: limit) }
        func allReminders() async throws -> [MemoryReminder] { try await reminders.allReminders() }
        func reminder(forMemory id: UUID) async throws -> MemoryReminder? { try await reminders.reminder(forMemory: id) }
        func reminderCount() async throws -> Int { try await reminders.reminderCount() }
    }

    private func make(
        _ database: DoddyDatabase? = nil, auth: NotificationAuthorization = .allowed, showText: Bool = false
    ) throws -> (Repo, FakeCenter, NoteReminderCoordinator, Flag) {
        let repo = Repo(try database ?? DoddyDatabase.inMemory())
        let center = FakeCenter(auth: auth)
        let flag = Flag(showText)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = warsaw
        let cal = calendar
        let fixedNow = now
        let coordinator = NoteReminderCoordinator(
            repository: repo.reminders, center: center, now: { fixedNow }, showNoteText: { flag.value }, calendar: { cal })
        return (repo, center, coordinator, flag)
    }

    private func note(_ repo: Repo, _ text: String = "Borrow \"Klara and the Sun\" before the trip.") async throws -> MemoryRecord {
        try await repo.save(NewMemory(text: text, capturedAt: now))
    }

    // N-01, N-04
    func testScheduleIsVerifiedAndHidesNoteTextByDefault() async throws {
        let (repo, center, coordinator, _) = try make()
        let memory = try await note(repo)
        let outcome = try await coordinator.schedule(memoryID: memory.id, at: now.addingTimeInterval(3600), timeZone: warsaw)

        guard case .scheduled(let reminder) = outcome else { return XCTFail("expected .scheduled, got \(outcome)") }
        let pending = await center.pending
        XCTAssertEqual(Array(pending.keys), [reminder.notificationID])
        XCTAssertEqual(pending[reminder.notificationID]?.title, "Reminder")
        XCTAssertEqual(pending[reminder.notificationID]?.body, NoteReminderCopy.privateBody)
        XCTAssertFalse(pending[reminder.notificationID]!.body.contains("Klara"), "note text must not reach iOS by default")
        XCTAssertEqual(pending[reminder.notificationID]?.trigger, .time(fireAt: now.addingTimeInterval(3600), timeZoneID: "Europe/Warsaw"))
        let stored = try await repo.reminder(forMemory: memory.id)
        XCTAssertEqual(stored, reminder)
    }

    // N-03
    func testNotificationsOffKeepsTheReminderInsideDoddyOnly() async throws {
        let (repo, center, coordinator, _) = try make(auth: .denied)
        let memory = try await note(repo)
        let outcome = try await coordinator.schedule(memoryID: memory.id, at: now.addingTimeInterval(3600), timeZone: warsaw)

        guard case .savedInAppOnly(let reminder) = outcome else { return XCTFail("expected .savedInAppOnly") }
        let pendingCount = await center.pending.count
        XCTAssertEqual(pendingCount, 0)
        let stored = try await repo.allReminders()
        XCTAssertEqual(stored, [reminder])
    }

    // 3c: iOS accepted the call but did not list the request -> nothing kept, earlier reminder restored.
    func testRefusedRequestRollsBackAndKeepsThePreviousReminder() async throws {
        let (repo, center, coordinator, _) = try make()
        let memory = try await note(repo)
        let first = try await coordinator.schedule(memoryID: memory.id, at: now.addingTimeInterval(3600), timeZone: warsaw).reminder

        await center.setDropsRequests(true)
        do {
            _ = try await coordinator.schedule(memoryID: memory.id, at: now.addingTimeInterval(7200), timeZone: warsaw)
            XCTFail("expected notScheduled")
        } catch {
            XCTAssertEqual(error as? NoteReminderError, .notScheduled)
        }
        let stored = try await repo.allReminders()
        XCTAssertEqual(stored, [first])
        let pendingIDs = await Set(center.pending.keys)
        XCTAssertEqual(pendingIDs, [first.notificationID])
    }

    func testChangingAReminderReplacesItWithoutDuplicates() async throws {
        let (repo, center, coordinator, _) = try make()
        let memory = try await note(repo)
        _ = try await coordinator.schedule(memoryID: memory.id, at: now.addingTimeInterval(3600), timeZone: warsaw)
        let second = try await coordinator.schedule(memoryID: memory.id, at: now.addingTimeInterval(7200), timeZone: warsaw).reminder

        let stored = try await repo.allReminders()
        XCTAssertEqual(stored, [second])
        let pendingIDs = await Set(center.pending.keys)
        XCTAssertEqual(pendingIDs, [second.notificationID])
    }

    // N-12
    func testPastTimesUnknownMemoriesAndTheLimitAreRejected() async throws {
        let (repo, _, coordinator, _) = try make()
        let memory = try await note(repo)
        await assertThrows(.timeInPast) {
            _ = try await coordinator.schedule(memoryID: memory.id, at: self.now.addingTimeInterval(30), timeZone: self.warsaw)
        }
        await assertThrows(.memoryNotFound) {
            _ = try await coordinator.schedule(memoryID: UUID(), at: self.now.addingTimeInterval(3600), timeZone: self.warsaw)
        }
        for index in 0..<NoteReminderLimits.maxActive {
            let other = try await note(repo, "note \(index)")
            _ = try await coordinator.schedule(memoryID: other.id, at: now.addingTimeInterval(3600), timeZone: warsaw)
        }
        let extra = try await note(repo, "one too many")
        await assertThrows(.limitReached(maximum: NoteReminderLimits.maxActive)) {
            _ = try await coordinator.schedule(memoryID: extra.id, at: self.now.addingTimeInterval(3600), timeZone: self.warsaw)
        }
        let count = try await repo.reminderCount()
        XCTAssertEqual(count, NoteReminderLimits.maxActive)
        let stored = try await repo.allReminders()
        XCTAssertEqual(Set(stored.map(\.memoryID)).contains(memory.id), false, "rejected requests store nothing")
    }

    // ADR-523: birthdays and Doddy's own notifications share iOS's 64, so the note reminder
    // limit shrinks with them instead of iOS dropping one quietly.
    func testTheLimitLeavesRoomForBirthdaysAndDoddysOwnNotifications() async throws {
        let (repo, center, coordinator, _) = try make()
        for index in 0..<20 { await center.injectOrphan(Birthdays.notificationID(for: "contact-\(index)")) }
        for index in 0..<20 { await center.injectOrphan("doddy.timer.\(index)") }
        let expected = NotificationBudget.systemLimit - 20 - 20
        XCTAssertEqual(expected, 24)
        for index in 0..<expected {
            let other = try await note(repo, "note \(index)")
            _ = try await coordinator.schedule(memoryID: other.id, at: now.addingTimeInterval(3600), timeZone: warsaw)
        }
        let extra = try await note(repo, "one too many")
        await assertThrows(.limitReached(maximum: expected)) {
            _ = try await coordinator.schedule(memoryID: extra.id, at: self.now.addingTimeInterval(3600), timeZone: self.warsaw)
        }
        let pending = await center.pending
        XCTAssertEqual(pending.count, NotificationBudget.systemLimit, "full, never over")
        let count = try await repo.reminderCount()
        XCTAssertEqual(count, expected)
    }

    // N-06, N-07: the reminder row goes with the memory, also after reopening the file.
    func testDeletingAMemoryDeletesItsReminder() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("doddy-\(UUID()).sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let (repo, center, coordinator, _) = try make(try DoddyDatabase(path: path))
        let keep = try await note(repo, "keep me")
        let gone = try await note(repo, "delete me")
        let keepReminder = try await coordinator.schedule(memoryID: keep.id, at: now.addingTimeInterval(3600), timeZone: warsaw).reminder
        let goneReminder = try await coordinator.schedule(memoryID: gone.id, at: now.addingTimeInterval(3600), timeZone: warsaw).reminder

        try await repo.delete(id: gone.id)
        await coordinator.memoryDeleted(reminderID: goneReminder.id)

        let reopened = Repo(try DoddyDatabase(path: path))
        let stored = try await reopened.allReminders()
        XCTAssertEqual(stored, [keepReminder])
        let pendingIDs = await Set(center.pending.keys)
        XCTAssertEqual(pendingIDs, [keepReminder.notificationID])

        try await reopened.deleteAll()
        await coordinator.allMemoriesDeleted()
        let remaining = try await reopened.reminderCount()
        XCTAssertEqual(remaining, 0)
        let pendingCount = await center.pending.count
        XCTAssertEqual(pendingCount, 0)
    }

    // N-05: with note text on, an edit replaces the pending content; turning it off hides it again.
    func testNoteTextFollowsEditsAndTheSetting() async throws {
        let (repo, center, coordinator, flag) = try make(showText: true)
        let memory = try await note(repo, "Old text")
        let reminder = try await coordinator.schedule(memoryID: memory.id, at: now.addingTimeInterval(3600), timeZone: warsaw).reminder
        var body = await center.pending[reminder.notificationID]?.body
        XCTAssertEqual(body, "Old text")

        _ = try await repo.update(id: memory.id, currentText: "New text")
        await coordinator.refreshContent(forMemory: memory.id)
        body = await center.pending[reminder.notificationID]?.body
        XCTAssertEqual(body, "New text")

        flag.value = false
        await coordinator.refreshContent()
        body = await center.pending[reminder.notificationID]?.body
        XCTAssertEqual(body, NoteReminderCopy.privateBody)
    }

    // N-09 and Done.
    func testSnoozeMovesToTomorrowMorningAndDoneKeepsTheMemory() async throws {
        let (repo, center, coordinator, _) = try make()
        let memory = try await note(repo)
        let reminder = try await coordinator.schedule(memoryID: memory.id, at: now.addingTimeInterval(3600), timeZone: warsaw).reminder

        let snoozed = try await coordinator.snoozeUntilTomorrowMorning(reminderID: reminder.id)?.reminder
        // Sun 11 Oct 2026, 09:00 Warsaw = 07:00 UTC.
        XCTAssertEqual(snoozed?.fireAt, Date(timeIntervalSince1970: 1_791_702_000))
        let pendingIDs = await Set(center.pending.keys)
        XCTAssertEqual(pendingIDs, [snoozed!.notificationID])

        try await coordinator.remove(reminderID: snoozed!.id)
        let count = try await repo.reminderCount()
        XCTAssertEqual(count, 0)
        let pendingCount = await center.pending.count
        XCTAssertEqual(pendingCount, 0)
        let memories = try await repo.list(limit: nil)
        XCTAssertEqual(memories.map(\.id), [memory.id])
    }

    // N-13: iOS lost its requests (restore) and holds one Doddy no longer knows.
    func testReconcileRepairsPendingRequests() async throws {
        let (repo, center, coordinator, _) = try make(auth: .denied)
        let memory = try await note(repo)
        let reminder = try await coordinator.schedule(memoryID: memory.id, at: now.addingTimeInterval(3600), timeZone: warsaw).reminder
        await center.setAuth(.allowed)
        await center.injectOrphan(MemoryReminder.notificationPrefix + UUID().uuidString)

        await coordinator.reconcile()

        let pendingIDs = await Set(center.pending.keys)
        XCTAssertEqual(pendingIDs, [reminder.notificationID])
    }

    // Timers, event nudges and server pushes share the iOS queue: never touched by note reminders.
    func testOtherNotificationsAreLeftAlone() async throws {
        let (repo, center, coordinator, _) = try make()
        await center.injectOrphan("doddy.timer.123")
        await center.injectOrphan("doddy.nudge.event-1")
        let memory = try await note(repo)
        let reminder = try await coordinator.schedule(memoryID: memory.id, at: now.addingTimeInterval(3600), timeZone: warsaw).reminder
        XCTAssertTrue(reminder.notificationID.hasPrefix(MemoryReminder.notificationPrefix))
        XCTAssertEqual(MemoryReminder.reminderID(fromNotificationID: reminder.notificationID), reminder.id)
        XCTAssertNil(MemoryReminder.reminderID(fromNotificationID: "doddy.timer.123"))

        await coordinator.reconcile()
        var pendingIDs = await Set(center.pending.keys)
        XCTAssertEqual(pendingIDs, ["doddy.timer.123", "doddy.nudge.event-1", reminder.notificationID])

        try await repo.deleteAll()
        await coordinator.allMemoriesDeleted()
        pendingIDs = await Set(center.pending.keys)
        XCTAssertEqual(pendingIDs, ["doddy.timer.123", "doddy.nudge.event-1"])
    }

    // MARK: Place reminders (ADR-196)

    private func postOffice(onArrival: Bool = true) throws -> ReminderPlace {
        try ReminderPlace(name: " Post office ", latitude: 52.2297, longitude: 21.0122, radiusMeters: 200, onArrival: onArrival)
    }

    func testPlaceReminderIsVerifiedPrivateAndStaysPending() async throws {
        let (repo, center, coordinator, _) = try make()
        let memory = try await note(repo)
        let outcome = try await coordinator.schedule(memoryID: memory.id, place: try postOffice())

        guard case .scheduled(let reminder) = outcome else { return XCTFail("expected .scheduled, got \(outcome)") }
        XCTAssertEqual(reminder.place?.name, "Post office")
        XCTAssertNil(reminder.fireAt)
        XCTAssertFalse(reminder.isDue(at: .distantFuture), "a place is never due by the clock")
        let sent = await center.pending[reminder.notificationID]
        XCTAssertEqual(sent?.trigger, .place(try postOffice()))
        XCTAssertEqual(sent?.body, NoteReminderCopy.privateBody, "no note text and no place name by default")
        let snoozed = try await coordinator.snoozeUntilTomorrowMorning(reminderID: reminder.id)
        XCTAssertNil(snoozed, "no time snooze for a place")

        // iOS lost it (restore): reconcile puts it back, even though no time is involved.
        await center.remove([reminder.notificationID])
        await coordinator.reconcile()
        let pendingIDs = await Set(center.pending.keys)
        XCTAssertEqual(pendingIDs, [reminder.notificationID])
        XCTAssertEqual(ReminderFormat.summary(reminder), "When you arrive at Post office")
        XCTAssertEqual(ReminderFormat.place(try postOffice(onArrival: false)), "When you leave Post office")
    }

    func testPlaceReminderNeedsNotificationsAndPreciseLocationAndStoresNothingOtherwise() async throws {
        let (repo, center, coordinator, _) = try make(auth: .denied)
        let memory = try await note(repo)
        await assertThrows(.placeNeedsNotifications) {
            _ = try await coordinator.schedule(memoryID: memory.id, place: try self.postOffice())
        }
        await center.setAuth(.allowed)
        for readiness in [LocationReadiness.notDetermined, .denied, .approximateOnly, .unavailable] {
            await center.setLocation(readiness)
            await assertThrows(.placeNeedsLocation(readiness)) {
                _ = try await coordinator.schedule(memoryID: memory.id, place: try self.postOffice())
            }
        }
        let count = try await repo.reminderCount()
        XCTAssertEqual(count, 0)
        let pendingCount = await center.pending.count
        XCTAssertEqual(pendingCount, 0)
    }

    func testPlaceLimitAndSwitchingANoteBetweenTimeAndPlace() async throws {
        let (repo, center, coordinator, _) = try make()
        let first = try await note(repo, "first")
        // Time first, then the same note moves to a place: one reminder, one request.
        _ = try await coordinator.schedule(memoryID: first.id, at: now.addingTimeInterval(3600), timeZone: warsaw)
        let placed = try await coordinator.schedule(memoryID: first.id, place: try postOffice()).reminder
        var pendingIDs = await Set(center.pending.keys)
        XCTAssertEqual(pendingIDs, [placed.notificationID])
        for index in 1..<NoteReminderLimits.maxPlaces {
            let other = try await note(repo, "place \(index)")
            _ = try await coordinator.schedule(memoryID: other.id, place: try postOffice())
        }
        let extra = try await note(repo, "one place too many")
        await assertThrows(.placeLimitReached(maximum: NoteReminderLimits.maxPlaces)) {
            _ = try await coordinator.schedule(memoryID: extra.id, place: try self.postOffice())
        }
        // Moving an existing place is not a new place.
        _ = try await coordinator.schedule(memoryID: first.id, place: try postOffice(onArrival: false))
        pendingIDs = await Set(center.pending.keys)
        XCTAssertEqual(pendingIDs.count, NoteReminderLimits.maxPlaces)
    }

    /// A database written by the previous version (v3: time reminders only) keeps its reminders.
    func testUpgradeFromTimeOnlyTableKeepsReminders() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("doddy-\(UUID()).sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let memoryID = UUID(), reminderID = UUID()
        do {
            let queue = try DatabaseQueue(path: path)
            try DoddyDatabase.migrator.migrate(queue, upTo: "v3_note_reminders")
            try await queue.write { db in
                try db.execute(sql: """
                    INSERT INTO memories (id, raw_text, current_text, source, captured_at_ms, search_text)
                    VALUES (?, 'Old note', 'Old note', 'explicit_text', 1791630120000, 'old note');
                    INSERT INTO note_reminders (id, memory_id, fire_at_ms, time_zone_id, created_at_ms)
                    VALUES (?, ?, 1791702000000, 'Europe/Warsaw', 1791630120000);
                    """, arguments: [memoryID.uuidString, reminderID.uuidString, memoryID.uuidString])
            }
        }
        let upgraded = Repo(try DoddyDatabase(path: path))
        let stored = try await upgraded.allReminders()
        XCTAssertEqual(stored, [MemoryReminder(
            id: reminderID, memoryID: memoryID, fireAt: Date(timeIntervalSince1970: 1_791_702_000),
            timeZoneID: "Europe/Warsaw", createdAt: Date(timeIntervalSince1970: 1_791_630_120))])

        // The rebuilt table still enforces one reminder per note and cascades on delete.
        let place = try postOffice()
        let moved = try await upgraded.reminders.upsertReminder(MemoryReminder(
            id: UUID(), memoryID: memoryID, trigger: .place(place), createdAt: Date(timeIntervalSince1970: 1_791_630_200)))
        let afterMove = try await upgraded.allReminders()
        XCTAssertEqual(afterMove, [moved])
        try await upgraded.delete(id: memoryID)
        let afterDelete = try await upgraded.reminderCount()
        XCTAssertEqual(afterDelete, 0)
    }

    private func assertThrows(
        _ expected: NoteReminderError, _ body: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            try await body()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? NoteReminderError, expected, file: file, line: line)
        }
    }
}

private actor FakeCenter: NoteNotificationScheduling {
    private(set) var pending: [String: NoteReminderNotification] = [:]
    private var auth: NotificationAuthorization
    private var location: LocationReadiness = .ready
    private var dropsRequests = false

    init(auth: NotificationAuthorization) { self.auth = auth }

    func setAuth(_ value: NotificationAuthorization) { auth = value }
    func setLocation(_ value: LocationReadiness) { location = value }
    func setDropsRequests(_ value: Bool) { dropsRequests = value }
    func injectOrphan(_ id: String) {
        let stray = MemoryReminder(
            id: UUID(), memoryID: UUID(), fireAt: Date(timeIntervalSince1970: 0), timeZoneID: "UTC",
            createdAt: Date(timeIntervalSince1970: 0))
        pending[id] = NoteReminderNotification(reminder: stray, noteText: "", showNoteText: false)
    }

    func authorization() async -> NotificationAuthorization { auth }
    func requestAuthorization() async -> NotificationAuthorization { auth }
    func locationReadiness() async -> LocationReadiness { location }
    func add(_ notification: NoteReminderNotification) async throws {
        guard auth == .allowed else { throw NoteReminderError.notScheduled }
        if !dropsRequests { pending[notification.identifier] = notification }
    }
    func pendingIdentifiers() async -> Set<String> { Set(pending.keys) }
    func deliveredIdentifiers() async -> Set<String> { [] }
    func remove(_ identifiers: [String]) async { identifiers.forEach { pending[$0] = nil } }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Bool
    init(_ value: Bool) { stored = value }
    var value: Bool {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
