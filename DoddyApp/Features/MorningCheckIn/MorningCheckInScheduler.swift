import DoddyCore
import Foundation
import UserNotifications

/// Puts the morning check-in's repeating notification in iOS (ADR-220) and reads it back. The
/// notification carries only "Good morning · A quick look at your day?", never a note.
@MainActor
enum MorningCheckInScheduler {
    enum Outcome: Equatable {
        /// Read back from iOS's pending list: this many requests (1, or 5 on weekdays only).
        case scheduled(Int)
        case off
        /// iOS notifications are off for Doddy; nothing was scheduled.
        case needsPermission
        case failed
    }

    /// The apply still running, if any. Each apply waits for the one before it, so quick changes
    /// can't interleave their remove and add steps and leave duplicate or stale notifications.
    private static var running: Task<Outcome, Never>?

    /// Replaces whatever check-in requests are pending with the ones `settings` asks for.
    static func apply(_ settings: MorningCheckInSettings) async -> Outcome {
        let previous = running
        let task = Task {
            _ = await previous?.value
            return await replace(with: settings)
        }
        running = task
        return await task.value
    }

    private static func replace(with settings: MorningCheckInSettings) async -> Outcome {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: pending.filter(MorningCheckIn.isCheckIn(notificationID:)))
        let requests = MorningCheckIn.requests(settings)
        guard !requests.isEmpty else { return .off }

        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            status = await center.notificationSettings().authorizationStatus
        }
        guard status == .authorized || status == .provisional || status == .ephemeral else { return .needsPermission }

        let language = NotificationLanguage.current
        for request in requests {
            let content = UNMutableNotificationContent()
            content.title = MorningCheckIn.title(language)
            content.body = MorningCheckIn.body(language)
            // Doddy stretching awake (ADR-323); the words are unchanged.
            if let art = NotificationArt.attachment(.yawnStretch) { content.attachments = [art] }
            content.sound = .default
            // A routine: never through a Focus (ADR-607).
            content.interruptionLevel = DoddyNotificationKind.morningCheckIn.interruptionLevel
            var when = DateComponents()
            when.hour = request.hour
            when.minute = request.minute
            when.weekday = request.weekday
            let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
            do {
                try await center.add(UNNotificationRequest(identifier: request.id, content: content, trigger: trigger))
            } catch {
                return .failed
            }
        }
        // Read back from iOS: every wanted request at the wanted time, and no other check-in.
        let checkIns = await center.pendingNotificationRequests().filter { MorningCheckIn.isCheckIn(notificationID: $0.identifier) }
        let stale = checkIns.map(\.identifier).filter { id in !requests.contains { $0.id == id } }
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: stale)
            let left = Set(await center.pendingNotificationRequests().map(\.identifier))
            guard left.isDisjoint(with: stale) else { return .failed }
        }
        let allThere = requests.allSatisfy { wanted in
            checkIns.contains { request in
                guard request.identifier == wanted.id,
                      let when = (request.trigger as? UNCalendarNotificationTrigger)?.dateComponents else { return false }
                return when.hour == wanted.hour && when.minute == wanted.minute && when.weekday == wanted.weekday
            }
        }
        return allThere ? .scheduled(requests.count) : .failed
    }
}
