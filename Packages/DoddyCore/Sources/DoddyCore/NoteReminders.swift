import Foundation

// M4a — note reminders (docs/design/NOTIFICATIONS.md). A note reminder is a local notification the
// user asked for, about one saved memory, at one moment they confirmed on screen. Nothing here
// decides on its own to notify, and nothing is sent off the device. It sits next to, not instead of,
// M4's Apple Reminders (`ReminderAction`): those live in the Reminders app; these stay in Doddy and
// open the exact note. Other local notifications (timers, event nudges) and server pushes share the
// iOS queue, so everything here touches only identifiers with `MemoryReminder.notificationPrefix`.

/// One active reminder for one memory. Done and cancelled reminders are deleted, not kept.
public struct MemoryReminder: Hashable, Sendable, Identifiable {
    public let id: UUID
    public let memoryID: UUID
    /// The absolute moment it fires. Travelling does not move it (owner decision D3).
    public let fireAt: Date
    /// The zone it was set in; shown next to the time so the moment is never ambiguous.
    public let timeZoneID: String
    public let createdAt: Date

    public init(id: UUID, memoryID: UUID, fireAt: Date, timeZoneID: String, createdAt: Date) {
        self.id = id
        self.memoryID = memoryID
        self.fireAt = fireAt
        self.timeZoneID = timeZoneID
        self.createdAt = createdAt
    }

    /// Every note-reminder request identifier starts with this; nothing else Doddy schedules does.
    public static let notificationPrefix = "doddy.note."

    /// The local notification request identifier.
    public var notificationID: String { Self.notificationID(for: id) }

    public static func notificationID(for reminderID: UUID) -> String { notificationPrefix + reminderID.uuidString }

    /// The reminder behind a notification, or `nil` for timers, nudges and server pushes.
    public static func reminderID(fromNotificationID identifier: String) -> UUID? {
        guard identifier.hasPrefix(notificationPrefix) else { return nil }
        return UUID(uuidString: String(identifier.dropFirst(notificationPrefix.count)))
    }

    public func isDue(at date: Date) -> Bool { fireAt <= date }
}

public enum NoteReminderLimits {
    /// iOS keeps at most 64 pending local notifications per app, shared with timers and event
    /// nudges; note reminders stay well below that.
    public static let maxActive = 50
    /// A reminder must be at least this far in the future when it is set.
    public static let minimumLead: TimeInterval = 60
    /// Longest note excerpt shown in a notification when the user turned note text on.
    public static let maxBodyLength = 140
}

public enum NoteReminderError: Error, Equatable, Sendable {
    case timeInPast
    case limitReached(maximum: Int)
    case memoryNotFound
    /// iOS did not confirm the request; nothing was kept.
    case notScheduled
}

/// What happened after the user confirmed a reminder. Never claims an alert that iOS did not accept.
public enum NoteReminderOutcome: Equatable, Sendable {
    /// Stored and read back from the iOS pending notifications.
    case scheduled(MemoryReminder)
    /// Stored in Doddy only: notifications are off, so it shows on Home when due.
    case savedInAppOnly(MemoryReminder)

    public var reminder: MemoryReminder {
        switch self {
        case .scheduled(let reminder), .savedInAppOnly(let reminder): reminder
        }
    }
}

public enum NoteReminderCopy {
    public static let title = "Reminder"
    /// Default notification body: the note text never enters the iOS notification store.
    public static let privateBody = "A note you asked to see again."

    public static func body(noteText: String, showNoteText: Bool) -> String {
        guard showNoteText else { return privateBody }
        let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > NoteReminderLimits.maxBodyLength else { return trimmed }
        return String(trimmed.prefix(NoteReminderLimits.maxBodyLength - 1)) + "…"
    }
}

/// Everything a notification adapter needs; built only from a stored reminder.
public struct NoteReminderNotification: Equatable, Sendable {
    public let identifier: String
    public let memoryID: UUID
    public let title: String
    public let body: String
    public let fireAt: Date
    public let timeZoneID: String

    public init(reminder: MemoryReminder, noteText: String, showNoteText: Bool) {
        identifier = reminder.notificationID
        memoryID = reminder.memoryID
        title = NoteReminderCopy.title
        body = NoteReminderCopy.body(noteText: noteText, showNoteText: showNoteText)
        fireAt = reminder.fireAt
        timeZoneID = reminder.timeZoneID
    }
}

public enum NotificationAuthorization: Equatable, Sendable {
    case notDetermined
    case denied
    case allowed
}

/// Local notifications only. The identifier lists include the app's other notifications (timers,
/// nudges, server pushes); the coordinator filters them by `MemoryReminder.notificationPrefix`.
public protocol NoteNotificationScheduling: Sendable {
    func authorization() async -> NotificationAuthorization
    /// Shows the iOS prompt when not determined. Returns the status afterwards.
    func requestAuthorization() async -> NotificationAuthorization
    func add(_ notification: NoteReminderNotification) async throws
    func pendingIdentifiers() async -> Set<String>
    func deliveredIdentifiers() async -> Set<String>
    /// Removes pending and delivered requests with these identifiers.
    func remove(_ identifiers: [String]) async
}

/// Notifications switched off (UI tests, environments without a notification center).
public struct DisabledNoteNotifications: NoteNotificationScheduling {
    public init() {}
    public func authorization() async -> NotificationAuthorization { .denied }
    public func requestAuthorization() async -> NotificationAuthorization { .denied }
    public func add(_ notification: NoteReminderNotification) async throws { throw NoteReminderError.notScheduled }
    public func pendingIdentifiers() async -> Set<String> { [] }
    public func deliveredIdentifiers() async -> Set<String> { [] }
    public func remove(_ identifiers: [String]) async {}
}

/// Durable reminder storage. Deleting a memory deletes its reminder in the same store.
public protocol NoteReminderRepository: Sendable {
    /// Soonest first.
    func allReminders() async throws -> [MemoryReminder]
    func reminder(id: UUID) async throws -> MemoryReminder?
    func reminder(forMemory memoryID: UUID) async throws -> MemoryReminder?
    func reminderCount() async throws -> Int
    func currentText(ofMemory memoryID: UUID) async throws -> String?
    /// Stores the memory's one reminder, replacing any earlier one; returns it read back.
    /// Throws `NoteReminderError.memoryNotFound` if the memory does not exist.
    func upsertReminder(_ reminder: MemoryReminder) async throws -> MemoryReminder
    @discardableResult
    func deleteReminder(id: UUID) async throws -> Bool
}

/// A quick pick resolved to a moment.
public struct ReminderOption: Hashable, Sendable {
    public let pick: ReminderQuickPick
    public let date: Date
}

/// Quick picks offered in the "When should I bring this back?" sheet (owner decision D5).
public enum ReminderQuickPick: String, CaseIterable, Sendable {
    case thisEvening, tomorrowMorning, mondayMorning

    public static let eveningHour = 18
    public static let morningHour = 9
    /// "This evening" is hidden when less than this remains before 18:00.
    public static let eveningCutoff: TimeInterval = 30 * 60

    /// The picks that make sense now, each with its resolved moment, in display order.
    public static func options(now: Date, calendar: Calendar) -> [ReminderOption] {
        var result: [ReminderOption] = []
        if let evening = calendar.date(bySettingHour: eveningHour, minute: 0, second: 0, of: now),
           evening.timeIntervalSince(now) >= eveningCutoff {
            result.append(ReminderOption(pick: .thisEvening, date: evening))
        }
        let tomorrow = tomorrowMorning(after: now, calendar: calendar)
        if let tomorrow { result.append(ReminderOption(pick: .tomorrowMorning, date: tomorrow)) }
        if let monday = nextMondayMorning(after: now, calendar: calendar), monday != tomorrow {
            result.append(ReminderOption(pick: .mondayMorning, date: monday))
        }
        return result
    }

    /// 09:00 on the next calendar day. Also the "Tomorrow 09:00" notification action.
    public static func tomorrowMorning(after now: Date, calendar: Calendar) -> Date? {
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return nil }
        return calendar.date(bySettingHour: morningHour, minute: 0, second: 0, of: nextDay)
    }

    /// 09:00 on the first Monday after today.
    public static func nextMondayMorning(after now: Date, calendar: Calendar) -> Date? {
        let monday = DateComponents(hour: morningHour, minute: 0, second: 0, weekday: 2)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return calendar.nextDate(
            after: startOfTomorrow.addingTimeInterval(-1), matching: monday, matchingPolicy: .nextTime)
    }
}

/// Fixed, literal date text for receipts: "Sun 11 Oct, 09:00 · Warsaw time".
public enum ReminderFormat {
    public static func dateTime(_ date: Date, timeZoneID: String, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = TimeZone(identifier: timeZoneID) ?? .current
        formatter.dateFormat = "EEE d MMM, HH:mm"
        return formatter.string(from: date)
    }

    public static func zoneName(_ timeZoneID: String) -> String {
        if ["GMT", "UTC", "Etc/UTC", "Etc/GMT"].contains(timeZoneID) { return "UTC" }
        let city = timeZoneID.split(separator: "/").last.map(String.init) ?? timeZoneID
        return city.replacingOccurrences(of: "_", with: " ") + " time"
    }

    public static func full(_ date: Date, timeZoneID: String, locale: Locale = .current) -> String {
        "\(dateTime(date, timeZoneID: timeZoneID, locale: locale)) · \(zoneName(timeZoneID))"
    }
}

/// The only code path that schedules, moves or removes a reminder. The database is the source of
/// truth; iOS pending requests are a projection that `reconcile()` repairs.
public actor NoteReminderCoordinator {
    private let repository: any NoteReminderRepository
    private let center: any NoteNotificationScheduling
    private let now: @Sendable () -> Date
    private let showNoteText: @Sendable () -> Bool
    private let calendar: @Sendable () -> Calendar

    public init(
        repository: any NoteReminderRepository,
        center: any NoteNotificationScheduling,
        now: @escaping @Sendable () -> Date = Date.init,
        showNoteText: @escaping @Sendable () -> Bool,
        calendar: @escaping @Sendable () -> Calendar = { Calendar.autoupdatingCurrent }
    ) {
        self.repository = repository
        self.center = center
        self.now = now
        self.showNoteText = showNoteText
        self.calendar = calendar
    }

    public func reminders() async throws -> [MemoryReminder] { try await repository.allReminders() }
    public func reminder(forMemory memoryID: UUID) async throws -> MemoryReminder? {
        try await repository.reminder(forMemory: memoryID)
    }
    public func authorization() async -> NotificationAuthorization { await center.authorization() }
    public func requestAuthorization() async -> NotificationAuthorization { await center.requestAuthorization() }

    /// Sets (or replaces) the memory's reminder. Returns `.scheduled` only after iOS lists the
    /// request as pending. If iOS refuses, nothing is kept and any earlier reminder is restored.
    public func schedule(memoryID: UUID, at fireAt: Date, timeZone: TimeZone) async throws -> NoteReminderOutcome {
        let current = now()
        guard fireAt.timeIntervalSince(current) >= NoteReminderLimits.minimumLead else { throw NoteReminderError.timeInPast }
        let previous = try await repository.reminder(forMemory: memoryID)
        if previous == nil, try await repository.reminderCount() >= NoteReminderLimits.maxActive {
            throw NoteReminderError.limitReached(maximum: NoteReminderLimits.maxActive)
        }
        guard let text = try await repository.currentText(ofMemory: memoryID) else { throw NoteReminderError.memoryNotFound }
        let reminder = try await repository.upsertReminder(MemoryReminder(
            id: UUID(), memoryID: memoryID, fireAt: Self.wholeSeconds(fireAt),
            timeZoneID: timeZone.identifier, createdAt: Self.wholeSeconds(current)))

        guard await center.authorization() == .allowed else {
            if let previous { await center.remove([previous.notificationID]) }
            return .savedInAppOnly(reminder)
        }
        do {
            try await center.add(NoteReminderNotification(reminder: reminder, noteText: text, showNoteText: showNoteText()))
            guard await center.pendingIdentifiers().contains(reminder.notificationID) else {
                throw NoteReminderError.notScheduled
            }
        } catch {
            await center.remove([reminder.notificationID])
            _ = try? await repository.deleteReminder(id: reminder.id)
            if let previous { _ = try? await repository.upsertReminder(previous) }
            throw NoteReminderError.notScheduled
        }
        if let previous { await center.remove([previous.notificationID]) }
        return .scheduled(reminder)
    }

    /// "Tomorrow 09:00" (notification action) or "Later" (Home): same memory, new moment.
    public func snoozeUntilTomorrowMorning(reminderID: UUID) async throws -> NoteReminderOutcome? {
        guard let reminder = try await repository.reminder(id: reminderID) else { return nil }
        let cal = calendar()
        guard let tomorrow = ReminderQuickPick.tomorrowMorning(after: now(), calendar: cal) else { return nil }
        return try await schedule(memoryID: reminder.memoryID, at: tomorrow, timeZone: cal.timeZone)
    }

    /// Done or Cancel: the reminder is deleted and its notification removed. The memory stays.
    public func remove(reminderID: UUID) async throws {
        try await repository.deleteReminder(id: reminderID)
        await center.remove([MemoryReminder.notificationID(for: reminderID)])
    }

    /// Call after the memory was deleted (its reminder row is deleted with it).
    public func memoryDeleted(reminderID: UUID) async {
        await center.remove([MemoryReminder.notificationID(for: reminderID)])
    }

    /// Call after every memory was deleted. Timers, nudges and server pushes are left alone.
    public func allMemoriesDeleted() async {
        let ours = await center.pendingIdentifiers().union(await center.deliveredIdentifiers())
            .filter { $0.hasPrefix(MemoryReminder.notificationPrefix) }
        if !ours.isEmpty { await center.remove(Array(ours)) }
    }

    /// Note text or the "Show note text" setting changed: replace pending content.
    public func refreshContent(forMemory memoryID: UUID? = nil) async {
        guard await center.authorization() == .allowed,
              let reminders = try? await repository.allReminders() else { return }
        let current = now()
        for reminder in reminders where !reminder.isDue(at: current) && (memoryID == nil || reminder.memoryID == memoryID) {
            await addIfPossible(reminder)
        }
    }

    /// Makes iOS match the database: re-adds missing future requests (e.g. after a restore or after
    /// notifications were turned on) and removes requests that have no reminder.
    public func reconcile() async {
        guard await center.authorization() == .allowed,
              let reminders = try? await repository.allReminders() else { return }
        let current = now()
        let pending = await center.pendingIdentifiers().filter { $0.hasPrefix(MemoryReminder.notificationPrefix) }
        let wanted = Set(reminders.filter { !$0.isDue(at: current) }.map(\.notificationID))
        let orphans = pending.subtracting(wanted)
        if !orphans.isEmpty { await center.remove(Array(orphans)) }
        for reminder in reminders where wanted.contains(reminder.notificationID) && !pending.contains(reminder.notificationID) {
            await addIfPossible(reminder)
        }
    }

    private func addIfPossible(_ reminder: MemoryReminder) async {
        guard let text = try? await repository.currentText(ofMemory: reminder.memoryID) else { return }
        try? await center.add(NoteReminderNotification(reminder: reminder, noteText: text, showNoteText: showNoteText()))
    }

    private static func wholeSeconds(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }
}

public struct UnavailableNoteReminderRepository: NoteReminderRepository {
    public init() {}
    public func allReminders() async throws -> [MemoryReminder] { throw DoddyError.capabilityUnavailable(.noteReminders) }
    public func reminder(id: UUID) async throws -> MemoryReminder? { throw DoddyError.capabilityUnavailable(.noteReminders) }
    public func reminder(forMemory memoryID: UUID) async throws -> MemoryReminder? { throw DoddyError.capabilityUnavailable(.noteReminders) }
    public func reminderCount() async throws -> Int { throw DoddyError.capabilityUnavailable(.noteReminders) }
    public func currentText(ofMemory memoryID: UUID) async throws -> String? { throw DoddyError.capabilityUnavailable(.noteReminders) }
    public func upsertReminder(_ reminder: MemoryReminder) async throws -> MemoryReminder { throw DoddyError.capabilityUnavailable(.noteReminders) }
    public func deleteReminder(id: UUID) async throws -> Bool { throw DoddyError.capabilityUnavailable(.noteReminders) }
}
