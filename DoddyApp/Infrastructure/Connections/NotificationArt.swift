import UIKit
import UserNotifications

/// Doddy's picture on a note reminder (ADR-313): the reaching pose from the owner's pack, as the
/// notification's thumbnail. It adds no words: the title and body are unchanged.
enum NotificationArt {
    /// A fresh copy of the pose's picture for one notification. iOS moves the file into its own
    /// store when the request is added, so each request needs its own copy. Nil (no picture)
    /// when "Hide Doddy's pictures" is on or the copy can't be made: a reminder is never held up
    /// by its picture.
    static func attachment(_ pose: IslandPose, defaults: UserDefaults = .standard) -> UNNotificationAttachment? {
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
