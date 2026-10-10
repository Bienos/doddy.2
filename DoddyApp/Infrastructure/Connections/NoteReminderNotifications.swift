import DoddyCore
import Foundation
import UserNotifications

/// Note reminders (M4a, ADR-190) as local notifications. Only identifiers starting with
/// `MemoryReminder.notificationPrefix` are scheduled here; timers and event nudges
/// (`DeviceConnections`) and server pushes share the same iOS queue and are never touched.
/// No badge, no remote registration, interruption level `.active`.
struct SystemNoteNotifications: NoteNotificationScheduling {
    static let categoryID = "DODDY_NOTE_REMINDER"
    /// Place reminders: no "Tomorrow 09:00" (a place has no time to move).
    static let placeCategoryID = "DODDY_NOTE_PLACE_REMINDER"
    static let threadID = "doddy-note-reminders"
    static let openAction = "NOTE_OPEN"
    static let tomorrowAction = "NOTE_TOMORROW_0900"
    static let doneAction = "NOTE_DONE"
    static let memoryIDKey = "memoryID"

    /// Long-press actions. Adds Doddy's category to any already registered (iOS replaces the set).
    static func registerCategory() async {
        let open = UNNotificationAction(identifier: openAction, title: "Open note", options: [.foreground])
        let tomorrow = UNNotificationAction(identifier: tomorrowAction, title: "Tomorrow 09:00", options: [])
        let done = UNNotificationAction(identifier: doneAction, title: "Done", options: [])
        let category = UNNotificationCategory(
            identifier: categoryID, actions: [open, tomorrow, done], intentIdentifiers: [], options: [])
        let placeCategory = UNNotificationCategory(
            identifier: placeCategoryID, actions: [open, done], intentIdentifiers: [], options: [])
        let center = UNUserNotificationCenter.current()
        let existing = await center.notificationCategories()
            .filter { $0.identifier != categoryID && $0.identifier != placeCategoryID }
        center.setNotificationCategories(existing.union([category, placeCategory]))
    }

    func authorization() async -> NotificationAuthorization {
        Self.map(await UNUserNotificationCenter.current().notificationSettings().authorizationStatus)
    }

    func requestAuthorization() async -> NotificationAuthorization {
        // Same options as timers and Doddy's updates; no badge, no provisional delivery.
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        return await authorization()
    }

    func locationReadiness() async -> LocationReadiness {
        await PlaceLocation.shared.readiness()
    }

    func add(_ notification: NoteReminderNotification) async throws {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        content.threadIdentifier = Self.threadID
        content.interruptionLevel = .active
        content.userInfo = [Self.memoryIDKey: notification.memoryID.uuidString]

        let trigger: UNNotificationTrigger
        switch notification.trigger {
        case .time(let fireAt, let timeZoneID):
            // Pinned to the zone the reminder was set in, so it fires at the confirmed moment even
            // if the iPhone's zone changes (owner decision D3).
            content.categoryIdentifier = Self.categoryID
            let zone = TimeZone(identifier: timeZoneID) ?? .current
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireAt)
            components.calendar = calendar
            components.timeZone = zone
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        case .place(let place):
            content.categoryIdentifier = Self.placeCategoryID
            trigger = PlaceLocation.trigger(for: place, identifier: notification.identifier)
        }

        try await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: notification.identifier, content: content, trigger: trigger))
    }

    func pendingIdentifiers() async -> Set<String> {
        Set(await UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier))
    }

    func deliveredIdentifiers() async -> Set<String> {
        Set(await UNUserNotificationCenter.current().deliveredNotifications().map(\.request.identifier))
    }

    func remove(_ identifiers: [String]) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private static func map(_ status: UNAuthorizationStatus) -> NotificationAuthorization {
        switch status {
        case .authorized, .provisional, .ephemeral: .allowed
        case .denied: .denied
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }
}

/// Handles taps and actions on note reminders. `TimerBanners` (the app's one notification
/// delegate) forwards responses here; responses for other notifications are ignored.
@MainActor
final class NoteReminderRouter {
    static let shared = NoteReminderRouter()

    /// Set at launch, before a background action can arrive.
    var reminders: NoteReminderStore?

    func handle(action: String, requestID: String, memoryString: String?) async {
        guard let reminderID = MemoryReminder.reminderID(fromNotificationID: requestID), let reminders else { return }
        switch action {
        case SystemNoteNotifications.tomorrowAction:
            await reminders.later(reminderID: reminderID)
        case SystemNoteNotifications.doneAction:
            await reminders.done(reminderID: reminderID)
        case UNNotificationDismissActionIdentifier:
            break
        default:  // tap or "Open note"
            if let memoryString, let memoryID = UUID(uuidString: memoryString) {
                reminders.pendingOpenMemoryID = memoryID
            }
        }
    }
}

extension TimerBanners {
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        let requestID = response.notification.request.identifier
        let memoryString = response.notification.request.content.userInfo[SystemNoteNotifications.memoryIDKey] as? String
        await NoteReminderRouter.shared.handle(action: action, requestID: requestID, memoryString: memoryString)
    }
}
