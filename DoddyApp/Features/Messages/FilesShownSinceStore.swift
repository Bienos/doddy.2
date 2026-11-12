import DoddyCore
import Foundation

/// The two moments `FilesShownSince` needs, kept on this iPhone (decision 2026-11-12-deleted-files-stay-gone): a file
/// Doddy made before this install, or before the person deleted the conversation, is not offered again in Messages or
/// Files. The server keeps it until its own deletion date (a week, ADR-564); nothing is sent to the server.
enum FilesShownSinceStore {
    static let conversationDeletedKey = "messages.conversationDeletedAt"

    /// When this copy of the app was installed: the creation date of its Documents folder, which iOS makes at install
    /// and removes with the app (an update keeps it). Nil if iOS doesn't say; then only a deletion counts.
    static let installedAt: Date? = {
        guard let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              let attributes = try? FileManager.default.attributesOfItem(atPath: folder.path) else { return nil }
        return attributes[.creationDate] as? Date
    }()

    static var since: Date? {
        FilesShownSince.start(
            installedAt: installedAt,
            conversationDeletedAt: UserDefaults.standard.object(forKey: conversationDeletedKey) as? Date)
    }

    /// The conversation was deleted on this iPhone: the files made until now stop showing.
    static func conversationDeleted(at date: Date = Date()) {
        UserDefaults.standard.set(date, forKey: conversationDeletedKey)
    }
}
