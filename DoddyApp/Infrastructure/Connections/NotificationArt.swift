import UIKit
import UserNotifications

/// Doddy's picture on a notification (ADR-313, ADR-323, ADR-546): a pose from the owner's pack, as
/// the notification's thumbnail. It adds no words: the title and body are unchanged. Which pose a
/// notification gets is `DoddyNotificationKind.pose`, checked on Linux by scripts/check_island_art.sh.
enum NotificationArt {
    /// The picture for one kind of notification; see `attachment(_:defaults:)`.
    static func attachment(for kind: DoddyNotificationKind, defaults: UserDefaults = .standard) -> UNNotificationAttachment? {
        attachment(kind.pose, defaults: defaults)
    }

    /// A fresh copy of the pose's picture for one notification. iOS moves the file into its own
    /// store when the request is added, so each request needs its own copy. Nil (no picture)
    /// when "Hide Doddy's pictures" is on or the copy can't be made: a reminder is never held up
    /// by its picture.
    private static func attachment(_ pose: IslandPose, defaults: UserDefaults) -> UNNotificationAttachment? {
        guard !defaults.bool(forKey: PreferenceKey.hideCharacterArt),
              let data = UIImage(named: pose.assetName)?.pngData() else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("doddy-\(UUID().uuidString).png")
        do {
            try data.write(to: url)
            return try UNNotificationAttachment(identifier: "doddy-pose", url: url, options: nil)
        } catch {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }
}
