import DoddyCore
import Foundation
import Observation

/// What the memory screen says after the user confirmed a reminder. Only built from a real outcome.
enum NoteReminderReceipt: Equatable {
    case scheduled(MemoryReminder)
    case inAppOnly(MemoryReminder)
    case failed(String)
    /// Failed because a permission is off; the receipt offers Open Settings.
    case needsSettings(String)
}

/// Main-actor view state over `NoteReminderCoordinator` (note reminders, M4a; not Apple Reminders). The list is only ever what the database holds.
@MainActor
@Observable
final class NoteReminderStore {
    private let coordinator: NoteReminderCoordinator?
    private(set) var reminders: [MemoryReminder] = []
    private(set) var authorization: NotificationAuthorization = .notDetermined
    private(set) var locationReadiness: LocationReadiness = .unavailable
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
        locationReadiness = await coordinator.locationReadiness()
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

    /// Asks for "While Using" location (never "Always") the first time; returns the readiness after.
    @discardableResult
    func requestLocation() async -> LocationReadiness {
        guard isAvailable else { return .unavailable }
        locationReadiness = await PlaceLocation.shared.requestWhenInUse()
        return locationReadiness
    }

    /// Place reminder (ADR-194). Nothing is stored unless notifications and precise location are on.
    func set(memoryID: UUID, place: ReminderPlace) async {
        guard let coordinator else { return }
        do {
            switch try await coordinator.schedule(memoryID: memoryID, place: place) {
            case .scheduled(let reminder): receipts[memoryID] = .scheduled(reminder)
            case .savedInAppOnly(let reminder): receipts[memoryID] = .inAppOnly(reminder)
            }
        } catch {
            switch error as? NoteReminderError {
            case .placeNeedsNotifications?, .placeNeedsLocation?:
                receipts[memoryID] = .needsSettings(Self.message(for: error))
            default:
                receipts[memoryID] = .failed(Self.message(for: error))
            }
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
        case .invalidPlace:
            return "That place can't be used. Pick it again or try another one. Nothing was set."
        case .placeLimitReached(let maximum):
            return "You have \(maximum) place reminders, the most iOS lets Doddy watch. Finish or cancel one to add another."
        case .placeNeedsNotifications:
            return "Notifications are off for Doddy, so it can't remind you at a place. Nothing was set. Turn them on in Settings."
        case .placeNeedsLocation(let readiness):
            switch readiness {
            case .approximateOnly:
                return "Precise Location is off for Doddy, so iOS can't tell when you get there. Nothing was set. Turn on Precise Location in Settings."
            case .unavailable:
                return "Location Services are off on this iPhone. Nothing was set. Turn them on in Settings, Privacy & Security."
            case .notDetermined, .denied, .ready:
                return "Doddy needs your location while you use the app to remind you at a place. Nothing was set. Allow it in Settings."
            }
        case .notScheduled, .none:
            return "Couldn't set the reminder. Nothing was scheduled, and your note is unchanged."
        }
    }
}
