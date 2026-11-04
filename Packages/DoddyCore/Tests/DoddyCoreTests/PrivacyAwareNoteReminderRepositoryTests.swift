import XCTest
@testable import DoddyCore

/// ADR-722: "Show note text in notifications" must not put a Private note's words on the Lock Screen.
final class PrivacyAwareNoteReminderRepositoryTests: XCTestCase {
    // Sat 10 Oct 2026, 13:02 in Warsaw (11:02 UTC).
    private let now = Date(timeIntervalSince1970: 1_791_630_120)
    private let warsaw = TimeZone(identifier: "Europe/Warsaw")!

    private let secretID = UUID()
    private let plainID = UUID()
    private let secretWords = "Bank PIN 4417 for the safe"
    private let plainWords = "Borrow the ladder from Anna"

    private func stub() -> StubReminderRepository {
        StubReminderRepository(texts: [secretID: secretWords, plainID: plainWords])
    }

    // MARK: the wrapper alone

    func testAPrivateNotesWordsAreReplacedByTheGenericBannerWords() async throws {
        let secretID = secretID
        let repository = PrivacyAwareNoteReminderRepository(base: stub(), privateIDs: { [secretID] })
        let secret = try await repository.currentText(ofMemory: secretID)
        let plain = try await repository.currentText(ofMemory: plainID)
        XCTAssertEqual(secret, NoteReminderCopy.privateBody)
        XCTAssertEqual(plain, plainWords, "a note that isn't private is untouched")
        let missing = try await repository.currentText(ofMemory: UUID())
        XCTAssertNil(missing, "a note that doesn't exist is still reported as missing")
    }

    func testTheGenericWordsFollowTheNotificationLanguage() async throws {
        let secretID = secretID
        let repository = PrivacyAwareNoteReminderRepository(base: stub(), privateIDs: { [secretID] }, language: { .polish })
        let secret = try await repository.currentText(ofMemory: secretID)
        XCTAssertEqual(secret, "Notatka, którą chcesz zobaczyć ponownie.")
    }

    /// Making a note Private takes effect at the next refresh without building anything again.
    func testThePrivateSetIsReadEveryTime() async throws {
        let box = IDBox([])
        let repository = PrivacyAwareNoteReminderRepository(base: stub(), privateIDs: { box.value })
        let before = try await repository.currentText(ofMemory: secretID)
        XCTAssertEqual(before, secretWords)
        box.value = [secretID]
        let after = try await repository.currentText(ofMemory: secretID)
        XCTAssertEqual(after, NoteReminderCopy.privateBody)
    }

    func testEverythingElseIsPassedThrough() async throws {
        let base = stub()
        let reminder = MemoryReminder(id: UUID(), memoryID: plainID, fireAt: now.addingTimeInterval(3600), timeZoneID: "Europe/Warsaw", createdAt: now)
        base.set(listIDs: [plainID], openItems: [plainID: 4])
        let secretID = secretID
        let repository = PrivacyAwareNoteReminderRepository(base: base, privateIDs: { [secretID] })
        _ = try await repository.upsertReminder(reminder)
        let all = try await repository.allReminders()
        let count = try await repository.reminderCount()
        let byID = try await repository.reminder(id: reminder.id)
        let byMemory = try await repository.reminder(forMemory: plainID)
        let isList = await repository.isList(memoryID: plainID)
        let open = await repository.openItemCount(listID: plainID)
        XCTAssertEqual(all, [reminder])
        XCTAssertEqual(count, 1)
        XCTAssertEqual(byID, reminder)
        XCTAssertEqual(byMemory, reminder)
        XCTAssertTrue(isList)
        XCTAssertEqual(open, 4, "a list's open-item count is not lost behind the wrapper")
        let deleted = try await repository.deleteReminder(id: reminder.id)
        XCTAssertTrue(deleted)
        let left = try await repository.allReminders()
        XCTAssertEqual(left, [])
    }

    // MARK: through the coordinator, which is what builds the notification

    private func coordinator(
        _ repository: any NoteReminderRepository, center: RecordingCenter, showText: Bool
    ) -> NoteReminderCoordinator {
        let fixedNow = now
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = warsaw
        let cal = calendar
        return NoteReminderCoordinator(repository: repository, center: center, now: { fixedNow }, showNoteText: { showText }, calendar: { cal })
    }

    /// The control: without the wrapper the setting puts the words of a Private note in the banner.
    /// This is the behaviour the finding describes, kept so the test below can't pass by accident.
    func testWithoutTheWrapperTheWordsWouldBeInTheBanner() async throws {
        let center = RecordingCenter()
        let coordinator = coordinator(stub(), center: center, showText: true)
        _ = try await coordinator.schedule(memoryID: secretID, at: now.addingTimeInterval(3600), timeZone: warsaw)
        let bodies = await center.bodies
        XCTAssertEqual(bodies, [secretWords])
    }

    func testAPrivateNoteGetsTheGenericBannerEvenWithShowNoteTextOn() async throws {
        let center = RecordingCenter()
        let secretID = secretID
        let repository = PrivacyAwareNoteReminderRepository(base: stub(), privateIDs: { [secretID] })
        let coordinator = coordinator(repository, center: center, showText: true)
        _ = try await coordinator.schedule(memoryID: secretID, at: now.addingTimeInterval(3600), timeZone: warsaw)
        _ = try await coordinator.schedule(memoryID: plainID, at: now.addingTimeInterval(7200), timeZone: warsaw)
        let bodies = await center.bodies
        XCTAssertEqual(bodies.count, 2)
        XCTAssertTrue(bodies.contains(NoteReminderCopy.privateBody), "the private note says what a note without text says")
        XCTAssertTrue(bodies.contains(plainWords), "the other note shows its words, as the person asked")
        for body in bodies { XCTAssertFalse(body.contains("4417"), body) }
    }

    /// A banner that is already waiting is rewritten by the refresh that follows making a note Private.
    func testRefreshingContentRewritesAWaitingBannerOfANoteThatBecamePrivate() async throws {
        let center = RecordingCenter()
        let box = IDBox([])
        let repository = PrivacyAwareNoteReminderRepository(base: stub(), privateIDs: { box.value })
        let coordinator = coordinator(repository, center: center, showText: true)
        _ = try await coordinator.schedule(memoryID: secretID, at: now.addingTimeInterval(3600), timeZone: warsaw)
        var waiting = await center.bodies
        XCTAssertEqual(waiting, [secretWords], "before it is made private the setting shows the words")

        box.value = [secretID]
        await coordinator.refreshContent(forMemory: secretID)
        waiting = await center.bodies
        XCTAssertEqual(waiting, [NoteReminderCopy.privateBody])
    }
}

// MARK: - Doubles

private final class IDBox: @unchecked Sendable {
    private let lock = NSLock()
    private var ids: Set<UUID>
    init(_ ids: Set<UUID>) { self.ids = ids }
    var value: Set<UUID> {
        get { lock.lock(); defer { lock.unlock() }; return ids }
        set { lock.lock(); defer { lock.unlock() }; ids = newValue }
    }
}

/// A reminder store in memory: notes by id, and the reminders the coordinator saves.
private final class StubReminderRepository: NoteReminderRepository, @unchecked Sendable {
    private let lock = NSLock()
    private let texts: [UUID: String]
    private var reminders: [MemoryReminder] = []
    private var lists: Set<UUID> = []
    private var open: [UUID: Int] = [:]

    init(texts: [UUID: String]) { self.texts = texts }

    func set(listIDs: Set<UUID>, openItems: [UUID: Int]) {
        lock.lock(); defer { lock.unlock() }
        lists = listIDs
        open = openItems
    }

    func allReminders() async throws -> [MemoryReminder] { locked { reminders } }
    func reminder(id: UUID) async throws -> MemoryReminder? { locked { reminders.first { $0.id == id } } }
    func reminder(forMemory memoryID: UUID) async throws -> MemoryReminder? { locked { reminders.first { $0.memoryID == memoryID } } }
    func reminderCount() async throws -> Int { locked { reminders.count } }
    func currentText(ofMemory memoryID: UUID) async throws -> String? { texts[memoryID] }
    func isList(memoryID: UUID) async -> Bool { locked { lists.contains(memoryID) } }
    func openItemCount(listID: UUID) async -> Int? { locked { open[listID] } }

    func upsertReminder(_ reminder: MemoryReminder) async throws -> MemoryReminder {
        locked {
            reminders.removeAll { $0.memoryID == reminder.memoryID }
            reminders.append(reminder)
            return reminder
        }
    }

    func deleteReminder(id: UUID) async throws -> Bool {
        locked {
            let before = reminders.count
            reminders.removeAll { $0.id == id }
            return reminders.count < before
        }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }
}

/// An iOS notification centre that keeps what was added, by identifier (the same identifier replaces).
private actor RecordingCenter: NoteNotificationScheduling {
    private var pending: [String: NoteReminderNotification] = [:]

    var bodies: [String] { pending.values.sorted { $0.identifier < $1.identifier }.map(\.body) }

    func authorization() async -> NotificationAuthorization { .allowed }
    func requestAuthorization() async -> NotificationAuthorization { .allowed }
    func locationReadiness() async -> LocationReadiness { .unavailable }
    func add(_ notification: NoteReminderNotification) async throws { pending[notification.identifier] = notification }
    func pendingIdentifiers() async -> Set<String> { Set(pending.keys) }
    func deliveredIdentifiers() async -> Set<String> { [] }
    func remove(_ identifiers: [String]) async { for id in identifiers { pending[id] = nil } }
}
