import DoddyCore
import UIKit
import UserNotifications

/// Doddy's own "it's in Messages" notice for a finished task (owner, 12 Nov 2026), shown only when the rules in
/// DoddyCore `ResultNotice` say so: while the app is open, Messages isn't on screen, and neither the server's push nor
/// an earlier notice said it in the last ten minutes. It says only that a task finished or couldn't, in the server's
/// push's own words, and a
/// tap opens Messages the same way (`TimerBanners.didReceive`). If notifications are off, iOS drops it: nothing more
/// to do, the message is in Messages and Home's "Done" card either way.
@MainActor
enum ResultNoticePoster {
    /// - Parameter done: the task finished with a result (else it couldn't be finished); the words match the server's push.
    static func postIfUseful(errandID: UUID, done: Bool, now: Date = Date()) async {
        let active = UIApplication.shared.applicationState == .active
        guard active, !ThreadInbox.isOnScreen else { return }
        let center = UNUserNotificationCenter.current()
        let inCenter = await center.deliveredNotifications().map(Self.delivered)
        guard ResultNotice.shouldPost(appActive: active, threadVisible: ThreadInbox.isOnScreen, delivered: inCenter, now: now) else { return }
        let content = UNMutableNotificationContent()
        content.title = "Doddy"
        content.body = done
            ? NSLocalizedString("Done. The result is waiting in Messages.", comment: "The notice when a task Doddy worked on in the background is done")
            : NSLocalizedString("Doddy couldn't finish a task.", comment: "The notice when a task Doddy worked on in the background failed")
        content.sound = .default
        content.userInfo = ResultNotice.userInfo
        try? await center.add(UNNotificationRequest(identifier: ResultNotice.identifier(for: errandID), content: content, trigger: nil))
    }

    /// A notification in Notification Center as the rules read it.
    nonisolated static func delivered(_ notification: UNNotification) -> ResultNotice.Delivered {
        ResultNotice.Delivered(identifier: notification.request.identifier,
                               kind: ServerPushKind.parse(notification.request.content.userInfo),
                               date: notification.date)
    }
}
