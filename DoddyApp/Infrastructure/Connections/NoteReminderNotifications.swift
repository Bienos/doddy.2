import DoddyCore
import Foundation
import UserNotifications

/// Note reminders (M4a, ADR-190) as local notifications. Only identifiers starting with
/// `MemoryReminder.notificationPrefix` are scheduled here; timers and event nudges
/// (`DeviceConnections`) and server pushes share the same iOS queue and are never touched.
/// No badge, no remote registration. Time Sensitive since ADR-607: the user set it for a moment,
/// so a Focus lets it through where they allow Time Sensitive notifications.
struct SystemNoteNotifications: NoteNotificationScheduling {
    static let categoryID = "DODDY_NOTE_REMINDER"
    /// Repeating reminders (ADR-211): "In 1 hour" and "Done this time"; no "Tomorrow 09:00" (owner
    /// decision R4) and no Stop, which is on the note only.
    static let repeatingCategoryID = "DODDY_NOTE_REPEATING_REMINDER"
    /// Place reminders: no snooze (a place comes back on the next arrival).
    static let placeCategoryID = "DODDY_NOTE_PLACE_REMINDER"
    static let threadID = "doddy-note-reminders"
    static let openAction = "NOTE_OPEN"
    static let hourAction = "NOTE_IN_1_HOUR"
    static let tomorrowAction = "NOTE_TOMORROW_0900"
    static let doneAction = "NOTE_DONE"
    static let memoryIDKey = "memoryID"

    /// Long-press actions. Adds Doddy's category to any already registered (iOS replaces the set).
    static func registerCategory() async {
        // In the iPhone's language: Polish or English (ADR-213). Re-registered when it changes.
        let language = NotificationLanguage.current
        let title = { (action: NoteReminderCopy.Action) in NoteReminderCopy.action(action, language) }
        let open = UNNotificationAction(identifier: openAction, title: title(.openNote), options: [.foreground])
        let hour = UNNotificationAction(identifier: hourAction, title: title(.inAnHour), options: [])
        let tomorrow = UNNotificationAction(identifier: tomorrowAction, title: title(.tomorrowMorning), options: [])
        let done = UNNotificationAction(identifier: doneAction, title: title(.done), options: [])
        let doneThisTime = UNNotificationAction(identifier: doneAction, title: title(.doneThisTime), options: [])
        let category = UNNotificationCategory(
            identifier: categoryID, actions: [open, hour, tomorrow, done], intentIdentifiers: [], options: [])
        let repeatingCategory = UNNotificationCategory(
            identifier: repeatingCategoryID, actions: [open, hour, doneThisTime], intentIdentifiers: [], options: [])
        let placeCategory = UNNotificationCategory(
            identifier: placeCategoryID, actions: [open, done], intentIdentifiers: [], options: [])
        let ours: Set<String> = [categoryID, repeatingCategoryID, placeCategoryID]
        let center = UNUserNotificationCenter.current()
        let existing = await center.notificationCategories().filter { !ours.contains($0.identifier) }
        center.setNotificationCategories(existing.union([category, repeatingCategory, placeCategory]))
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
        content.interruptionLevel = DoddyNotificationKind.noteReminder.interruptionLevel
        content.userInfo = [Self.memoryIDKey: notification.memoryID.uuidString]
        // Doddy reaching for it (ADR-313), the pose for a reminder waiting; no extra words.
        if let art = NotificationArt.attachment(.reachingHigh) { content.attachments = [art] }

        switch notification.category {
        case .once: content.categoryIdentifier = Self.categoryID
        case .repeating: content.categoryIdentifier = Self.repeatingCategoryID
        case .place: content.categoryIdentifier = Self.placeCategoryID
        }

        let trigger: UNNotificationTrigger
        if let match = notification.repeatMatch {
            // Repeats at this clock time in the zone it was set in (ADR-211).
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: match.timeZoneID) ?? .current
            var components = DateComponents(day: match.day, hour: match.hour, minute: match.minute, second: 0, weekday: match.weekday)
            components.calendar = calendar
            components.timeZone = calendar.timeZone
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            try await UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: notification.identifier, content: content, trigger: trigger))
            return
        }
        switch notification.trigger {
        case .time(let fireAt, let timeZoneID):
            // Pinned to the zone the reminder was set in, so it fires at the confirmed moment even
            // if the iPhone's zone changes (owner decision D3).
            let zone = TimeZone(identifier: timeZoneID) ?? .current
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireAt)
            components.calendar = calendar
            components.timeZone = zone
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        case .place(let place):
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
        case SystemNoteNotifications.hourAction:
            await reminders.snoozeForAnHour(reminderID: reminderID)
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
        // The weekly tidy-up (ADR-228) opens its screen; nothing changes until the user taps.
        if TidyUp.isTidyUp(notificationID: requestID) {
            if action != UNNotificationDismissActionIdentifier {
                await MainActor.run { ShortcutRouter.shared.tidyUpOpened() }
            }
            return
        }
        // The weekly "Open Doddy faster" reminder (ADR-559) opens the ways to open Doddy.
        if OpenWaysReminder.isReminder(notificationID: requestID) {
            if action != UNNotificationDismissActionIdentifier {
                await MainActor.run { ShortcutRouter.shared.openWaysOpened() }
            }
            return
        }
        // A birthday (ADR-288) just opens Doddy; nothing else happens.
        if Birthdays.isBirthday(notificationID: requestID) { return }
        // The weekly plan (ADR-608) opens its screen.
        if WeeklyPlan.isPlan(notificationID: requestID) {
            if action != UNNotificationDismissActionIdentifier {
                await MainActor.run { ShortcutRouter.shared.weeklyPlanOpened() }
            }
            return
        }
        // The weekly look-back (ADR-306) opens its screen.
        if WeeklyLookBack.isLookBack(notificationID: requestID) {
            if action != UNNotificationDismissActionIdentifier {
                await MainActor.run { ShortcutRouter.shared.weeklyLookBackOpened() }
            }
            return
        }
        // The evening wrap-up (ADR-261) opens its screen; nothing moves until the user taps.
        if EveningWrapUp.isWrapUp(notificationID: requestID) {
            if action != UNNotificationDismissActionIdentifier {
                await MainActor.run { ShortcutRouter.shared.eveningWrapUpOpened() }
            }
            return
        }
        // The morning check-in (ADR-220) opens its screen; nothing else happens until the user taps.
        if MorningCheckIn.isCheckIn(notificationID: requestID) {
            if action != UNNotificationDismissActionIdentifier {
                await MainActor.run { ShortcutRouter.shared.morningCheckInOpened() }
            }
            return
        }
        let memoryString = response.notification.request.content.userInfo[SystemNoteNotifications.memoryIDKey] as? String
        await NoteReminderRouter.shared.handle(action: action, requestID: requestID, memoryString: memoryString)
    }
}
