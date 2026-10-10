import DoddyCore
import Foundation
import Observation

/// What the memory screen says after the user confirmed a reminder. Only built from a real outcome.
enum NoteReminderReceipt: Equatable {
    case scheduled(MemoryReminder)
    case inAppOnly(MemoryReminder)
    case failed(String)
}

/// Main-actor view state over `NoteReminderCoordinator` (note reminders, M4a; not Apple Reminders). The list is only ever what the database holds.
@MainActor
@Observable
final class NoteReminderStore {
    private let coordinator: NoteReminderCoordinator?
    private(set) var reminders: [MemoryReminder] = []
    private(set) var authorization: NotificationAuthorization = .notDetermined
    private(set) var receipts: [UUID: NoteReminderReceipt] = [:]
    /// Set by a notification tap; RootView opens that memory and clears it.
    var pendingOpenMemoryID: UUID?

    init(coordinator: NoteReminderCoordinator?) {
        self.coordinator = coordinator
    }

    var isAvailable: Bool { coordinator != nil }

    func reminder(forMemory memoryID: UUID) -> MemoryReminder? {
        reminders.first { $0.memoryID == memoryID }
    }

    func due(at date: Date) -> [MemoryReminder] {
        reminders.filter { $0.isDue(at: date) }
    }

    func reload() async {
        guard let coordinator else { return }
        if let stored = try? await coordinator.reminders() { reminders = stored }
        authorization = await coordinator.authorization()
    }

    /// On launch and every return to the foreground: repair iOS requests, refresh status.
    func refreshOnForeground() async {
        await coordinator?.reconcile()
        await reload()
    }

    @discardableResult
    func requestAuthorization() async -> NotificationAuthorization {
        guard let coordinator else { return .denied }
        authorization = await coordinator.requestAuthorization()
        await coordinator.reconcile()
        return authorization
    }

    func set(memoryID: UUID, at date: Date, timeZone: TimeZone = .autoupdatingCurrent) async {
        guard let coordinator else { return }
        do {
            switch try await coordinator.schedule(memoryID: memoryID, at: date, timeZone: timeZone) {
            case .scheduled(let reminder): receipts[memoryID] = .scheduled(reminder)
            case .savedInAppOnly(let reminder): receipts[memoryID] = .inAppOnly(reminder)
            }
        } catch {
            receipts[memoryID] = .failed(Self.message(for: error))
        }
        await reload()
    }

    func cancel(memoryID: UUID) async {
        guard let reminder = reminder(forMemory: memoryID) else { return }
        await remove(reminder)
        receipts[memoryID] = nil
    }

    func done(reminderID: UUID) async {
        await reload()
        guard let reminder = reminders.first(where: { $0.id == reminderID }) else { return }
        await remove(reminder)
    }

    func later(reminderID: UUID) async {
        guard let coordinator else { return }
        _ = try? await coordinator.snoozeUntilTomorrowMorning(reminderID: reminderID)
        await reload()
    }

    func cancelAll() async {
        for reminder in reminders { await remove(reminder) }
        receipts = [:]
    }

    func noteTextSettingChanged() async {
        await coordinator?.refreshContent()
    }

    func clearReceipt(memoryID: UUID) {
        receipts[memoryID] = nil
    }

    private func remove(_ reminder: MemoryReminder) async {
        try? await coordinator?.remove(reminderID: reminder.id)
        await reload()
    }

    static func message(for error: any Error) -> String {
        switch error as? NoteReminderError {
        case .timeInPast:
            return "That time has already passed. Pick a time at least a minute from now."
        case .limitReached(let maximum):
            return "You have \(maximum) reminders set, the most Doddy can schedule. Finish or cancel one to add another."
        case .memoryNotFound:
            return "That memory no longer exists, so no reminder was set."
        case .notScheduled, .none:
            return "Couldn't set the reminder. Nothing was scheduled, and your note is unchanged."
        }
    }
}
