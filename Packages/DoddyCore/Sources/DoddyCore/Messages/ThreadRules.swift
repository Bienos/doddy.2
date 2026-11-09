import Foundation

/// How the thread behaves (ADR-585). The screen only draws what these decide.
public enum ThreadRules {
    /// How many messages the screen loads. Older ones stay saved; this is a bound, not a deletion.
    public static let displayLimit = 200

    /// Only messages this recent go to the model as earlier turns. The thread is kept for the user,
    /// not sent in bulk: a question tomorrow does not carry yesterday's chat to the model provider.
    public static let contextWindow: TimeInterval = 12 * 3_600

    /// A heading with the date and time shows when this long has passed since the previous message.
    public static let headingGap: TimeInterval = 3_600

    /// What the model sees in place of an action card's offer or result (`ThreadMessage.isLocalAction`).
    public static let localActionStandIn =
        "(An action card was shown on the phone. Its contents and result stay on the phone and are not shared here. "
        + "Do not assume what it said or whether it was done.)"

    /// The earlier turns for a question, from the thread as it was before that question:
    /// delivered messages only (a failed or still-sending one never reached Doddy), recent ones only.
    /// `AssistantService` then keeps the last few of these.
    public static func history(from messages: [ThreadMessage], before date: Date) -> [ConversationTurn] {
        messages.compactMap { message in
            guard message.createdAt < date, date.timeIntervalSince(message.createdAt) <= contextWindow else { return nil }
            switch message.sender {
            case .user:
                // A user message counts once it was answered: only then did the question go through.
                return message.delivery == .sent ? ConversationTurn(role: .user, text: message.text) : nil
            case .doddy:
                // A file bubble is a name, not something Doddy said: it is not sent as conversation.
                guard message.document == nil else { return nil }
                // An action card's offer or result can hold note text or a whole list read on the phone. It stays
                // on the phone: the model gets only that a card was shown, even with "Use my notes" off.
                return ConversationTurn(role: .assistant, text: message.isLocalAction ? localActionStandIn : message.text)
            }
        }
    }

    /// Whether `message` starts with a date heading, given the one before it.
    public static func showsHeading(_ message: ThreadMessage, after previous: ThreadMessage?) -> Bool {
        guard let previous else { return true }
        return message.createdAt.timeIntervalSince(previous.createdAt) >= headingGap
    }

    /// What the box can send: not while another is on its way, and not blank.
    public static func canSend(draft: String, isSending: Bool, hasPhoto: Bool = false) -> Bool {
        !isSending && (hasPhoto || !draft.allSatisfy(\.isWhitespace))
    }

    /// The words sent with a photo when the box is empty, so the question is never blank.
    public static func photoQuestion(draft: String, fallback: String) -> String {
        let words = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return words.isEmpty ? fallback : words
    }

    /// A message that did not get through can be sent again; one that is answered or on its way cannot. One sent with a
    /// photo cannot: the photo was not kept, and sending the words alone would ask a different question.
    public static func canRetry(_ message: ThreadMessage) -> Bool {
        message.sender == .user && message.delivery == .failed && !message.hasPhoto && message.attachedFileName == nil
    }

    /// The line under a user bubble, or nil when there is nothing to say (answered).
    public enum DeliveryLine: Equatable, Sendable {
        case sending, notDelivered
        /// Not delivered, and it had a photo that was not kept: add the photo again to ask.
        case notDeliveredPhoto
        /// Not delivered, and it had a file that was not kept: attach it again to ask.
        case notDeliveredFile
    }

    public static func deliveryLine(for message: ThreadMessage) -> DeliveryLine? {
        guard message.sender == .user else { return nil }
        switch message.delivery {
        case .sending: return .sending
        case .failed:
            if message.hasPhoto { return .notDeliveredPhoto }
            return message.attachedFileName == nil ? .notDelivered : .notDeliveredFile
        case .sent: return nil
        }
    }
}
