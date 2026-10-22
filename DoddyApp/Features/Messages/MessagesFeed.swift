import DoddyCore
import Foundation

/// What a voice conversation puts in the Messages thread (owner, 22 Oct 2026, ADR-594): a file
/// Doddy made, a link to a document Claude is making, a day's steps, a reminder that Reminders
/// confirmed. Each is added only from a result that really happened, in the words of that result,
/// and never from a private conversation (ADR-170: nothing of it is kept on this iPhone).
/// The voice screen's own cards stay as they were; this is the copy that stays.
@MainActor
enum MessagesFeed {
    /// The presentation written on this iPhone (ADR-567): a copy goes into the thread, so it is
    /// still there after the voice screen is gone. A copy that can't be proved is reported in the
    /// thread and the voice screen's share sheet keeps working with the original.
    static func presentationMade(at url: URL, title: String, isPrivate: Bool) {
        guard !isPrivate else { return }
        MessagesController.shared.keep(fileAt: url, named: url.lastPathComponent, from: .doddy)
    }

    /// A document Claude is making (ADR-564): only its link is kept; nothing is downloaded.
    static func document(_ document: RunDocument, isPrivate: Bool) {
        guard !isPrivate else { return }
        let title = document.name
        MessagesController.shared.receive(ChatMessage(
            sender: .doddy, content: .link(ChatLink(title: title, kind: document.kind, url: document.url))))
    }

    /// One day's steps as the iPhone reported them (ADR-568), as a card.
    static func steps(_ totals: StepTotals, day: StepDay, isPrivate: Bool) {
        guard !isPrivate else { return }
        let card = ChatInfographic.steps(
            totals,
            dayName: dayName(day),
            stepsWord: NSLocalizedString("steps", comment: ""),
            distanceLabel: NSLocalizedString("Walking distance", comment: ""),
            floorsLabel: NSLocalizedString("Floors climbed", comment: ""),
            source: NSLocalizedString("From Motion & Fitness on this iPhone", comment: ""))
        MessagesController.shared.receive(ChatMessage(sender: .doddy, content: .infographic(card)))
    }

    /// A reminder Reminders confirmed (ADR-240): its title and time as Reminders read them back.
    static func reminderSet(_ receipt: ReminderReceipt, isPrivate: Bool) {
        guard !isPrivate else { return }
        let when = receipt.due?.localText.replacingOccurrences(of: "T", with: " ") ?? ""
        let line = when.isEmpty
            ? String(format: NSLocalizedString("Reminder set: %@", comment: ""), receipt.title)
            : String(format: NSLocalizedString("Reminder set: %@ · %@", comment: ""), receipt.title, when)
        MessagesController.shared.receive(ChatMessage(sender: .doddy, content: .text(line)))
    }

    private static func dayName(_ day: StepDay) -> String {
        switch day.daysAgo {
        case 0: NSLocalizedString("Today", comment: "")
        case 1: NSLocalizedString("Yesterday", comment: "")
        default: String(format: NSLocalizedString("%lld days ago", comment: ""), day.daysAgo)
        }
    }
}
