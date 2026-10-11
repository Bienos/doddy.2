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

    /// On launch and every return to the foreground: repair iOS requests, refresh status. If the
    /// iPhone's language changed, waiting notifications and their buttons are rewritten in it.
    func refreshOnForeground() async {
        let language = NotificationLanguage.current.rawValue
        let key = "noteReminders.notificationLanguage"
        if UserDefaults.standard.string(forKey: key) != language {
            await SystemNoteNotifications.registerCategory()
            await coordinator?.refreshContent()
            UserDefaults.standard.set(language, forKey: key)
        }
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

    /// iOS slots in use (a weekdays repeat uses five), out of `NoteReminderLimits.maxActive`.
    var slotsUsed: Int { reminders.reduce(0) { $0 + $1.requestSlots } }

    func set(memoryID: UUID, at date: Date, timeZone: TimeZone = .autoupdatingCurrent, repeats: ReminderRepeat? = nil) async {
        guard let coordinator else { return }
        do {
            switch try await coordinator.schedule(memoryID: memoryID, at: date, timeZone: timeZone, repeats: repeats) {
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

    /// Place reminder (ADR-196). Nothing is stored unless notifications and precise location are on.
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

    /// The receipt clears only when the delete was stored; otherwise it says nothing changed (review F8).
    func cancel(memoryID: UUID) async {
        guard let reminder = reminder(forMemory: memoryID) else { return }
        receipts[memoryID] = await remove(reminder) ? nil : .failed(Self.notTurnedOff)
    }

    /// Done: a one-off or place reminder ends; a repeating one is done for this time only.
    func done(reminderID: UUID) async {
        guard let coordinator else { return }
        await reload()
        guard let reminder = reminders.first(where: { $0.id == reminderID }) else { return }
        do {
            try await coordinator.markDone(reminderID: reminderID)
            receipts[reminder.memoryID] = nil
        } catch {
            receipts[reminder.memoryID] = .failed(NSLocalizedString("Couldn't mark it done. Your reminder is unchanged.", comment: ""))
        }
        await reload()
    }

    enum SnoozeChoice: Hashable {
        case inAnHour, thisEvening, tomorrowMorning
    }

    struct SnoozeOption: Hashable {
        let choice: SnoozeChoice
        let date: Date
    }

    /// Snooze choices in the app, which knows the time: "This evening" (18:00) only before 17:00.
    static func snoozeChoices(now: Date, calendar: Calendar = .autoupdatingCurrent) -> [SnoozeOption] {
        var result = [SnoozeOption(choice: .inAnHour, date: now.addingTimeInterval(3_600))]
        if calendar.component(.hour, from: now) < ReminderQuickPick.eveningHour - 1,
           let evening = calendar.date(bySettingHour: ReminderQuickPick.eveningHour, minute: 0, second: 0, of: now) {
            result.append(SnoozeOption(choice: .thisEvening, date: evening))
        }
        if let tomorrow = ReminderQuickPick.tomorrowMorning(after: now, calendar: calendar) {
            result.append(SnoozeOption(choice: .tomorrowMorning, date: tomorrow))
        }
        return result
    }

    /// Lock Screen "Tomorrow 09:00".
    func later(reminderID: UUID) async {
        guard let tomorrow = ReminderQuickPick.tomorrowMorning(after: .now, calendar: .autoupdatingCurrent) else { return }
        await snooze(reminderID: reminderID, until: tomorrow)
    }

    /// Lock Screen or Home "In 1 hour".
    func snoozeForAnHour(reminderID: UUID) async {
        await snooze(reminderID: reminderID, until: .now.addingTimeInterval(3_600))
    }

    /// Brings a time reminder back at `date`. The receipt shows on the note: moved (read back from
    /// iOS), kept in Doddy only, or "Couldn't move it" with the reminder unchanged.
    func snooze(reminderID: UUID, until date: Date) async {
        guard let coordinator else { return }
        await reload()
        guard let reminder = reminders.first(where: { $0.id == reminderID }) else { return }
        do {
            switch try await coordinator.snooze(reminderID: reminderID, until: date) {
            case .scheduled(let moved)?: receipts[reminder.memoryID] = .scheduled(moved)
            case .savedInAppOnly(let moved)?: receipts[reminder.memoryID] = .inAppOnly(moved)
            case nil: break
            }
        } catch {
            receipts[reminder.memoryID] = .failed("Couldn't move it. Your reminder is unchanged.")
        }
        await reload()
    }

    /// A reminder that couldn't be deleted keeps a "nothing changed" receipt (review F8).
    func cancelAll() async {
        var kept: [UUID: NoteReminderReceipt] = [:]
        for reminder in reminders {
            if await !remove(reminder) { kept[reminder.memoryID] = .failed(Self.notTurnedOff) }
        }
        receipts = kept
    }

    func noteTextSettingChanged() async {
        await coordinator?.refreshContent()
    }

    func clearReceipt(memoryID: UUID) {
        receipts[memoryID] = nil
    }

    /// True only when the database delete didn't throw; false means the reminder is unchanged.
    private func remove(_ reminder: MemoryReminder) async -> Bool {
        guard let coordinator else { return false }
        let removed: Bool
        do {
            try await coordinator.remove(reminderID: reminder.id)
            removed = true
        } catch {
            removed = false
        }
        await reload()
        return removed
    }

    private static let notTurnedOff = NSLocalizedString("Couldn't turn the reminder off. Nothing changed.", comment: "")

    static func message(for error: any Error) -> String {
        switch error as? NoteReminderError {
        case .timeInPast:
            return NSLocalizedString("That time has already passed. Pick a time at least a minute from now.", comment: "")
        case .invalidRepeat:
            return NSLocalizedString("Monthly reminders can be on days 1 to 28, so every month has the day. Nothing was set.", comment: "")
        case .limitReached(let maximum):
            return "Doddy can keep \(maximum) reminders on this iPhone, and weekdays counts as 5. Finish or cancel one to add another."
        case .memoryNotFound:
            return NSLocalizedString("That memory no longer exists, so no reminder was set.", comment: "")
        case .invalidPlace:
            return NSLocalizedString("That place can't be used. Pick it again or try another one. Nothing was set.", comment: "")
        case .placeLimitReached(let maximum):
            return "You have \(maximum) place reminders, the most iOS lets Doddy watch. Finish or cancel one to add another."
        case .placeNeedsNotifications:
            return NSLocalizedString("Notifications are off for Doddy, so it can't remind you at a place. Nothing was set. Turn them on in Settings.", comment: "")
        case .placeNeedsLocation(let readiness):
            switch readiness {
            case .approximateOnly:
                return NSLocalizedString("Precise Location is off for Doddy, so iOS can't tell when you get there. Nothing was set. Turn on Precise Location in Settings.", comment: "")
            case .unavailable:
                return NSLocalizedString("Location Services are off on this iPhone. Nothing was set. Turn them on in Settings, Privacy & Security.", comment: "")
            case .notDetermined, .denied, .ready:
                return NSLocalizedString("Doddy needs your location while you use the app to remind you at a place. Nothing was set. Allow it in Settings.", comment: "")
            }
        case .notScheduled, .none:
            return NSLocalizedString("Couldn't set the reminder. Nothing was scheduled, and your note is unchanged.", comment: "")
        }
    }
}
