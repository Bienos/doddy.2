import DoddyCore
import Foundation

/// Puts what Doddy finished in the background into Messages as his own message (owner, 10 Nov 2026): a task he
/// researched (`ErrandsModel`, when it sees the task finish) or a file he started making in a voice conversation.
/// The words come from `ThreadDelivery`, which says only what the server reported. The message is saved and read
/// back before anything shows it; an open Messages screen is told, and shows it once.
@MainActor
enum ThreadInbox {
    /// Posted with the saved `ThreadMessage` as the object.
    static let delivered = Notification.Name("ThreadInbox.delivered")

    private static var repository: any MessageThreadRepository { AppEnvironment.shared.messageThreadRepository }

    /// A task that has just finished. Its message has the task's id, so it is saved once even if this runs twice.
    static func deliver(errand: StoredErrand, now: Date = Date()) async {
        guard let message = ThreadDelivery.errand(errand, now: now) else { return }
        if let recent = try? await repository.recent(limit: ThreadRules.displayLimit), recent.contains(where: { $0.id == message.id }) {
            return
        }
        await save(message)
    }

    /// A file a voice conversation started. Not for a private conversation: nothing of it is kept on this iPhone.
    static func deliver(document: RunDocument, polish: Bool, now: Date = Date()) async {
        guard let message = ThreadDelivery.document(document, polish: polish, now: now) else { return }
        guard let recent = try? await repository.recent(limit: ThreadRules.displayLimit),
              !ThreadDelivery.hasDocument(document, in: recent) else { return }
        await save(message)
    }

    private static func save(_ message: ThreadMessage) async {
        do {
            try await repository.append(message)
            NotificationCenter.default.post(name: delivered, object: message)
        } catch {
            // Not saved: nothing claims it arrived. A task's result stays under Tasks, a file in Files.
        }
    }
}
