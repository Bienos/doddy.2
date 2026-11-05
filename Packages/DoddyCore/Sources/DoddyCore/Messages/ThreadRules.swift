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
                return message.document == nil ? ConversationTurn(role: .assistant, text: message.text) : nil
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
        message.sender == .user && message.delivery == .failed && !message.hasPhoto
    }

    /// The line under a user bubble, or nil when there is nothing to say (answered).
    public enum DeliveryLine: Equatable, Sendable {
        case sending, notDelivered
        /// Not delivered, and it had a photo that was not kept: add the photo again to ask.
        case notDeliveredPhoto
    }

    public static func deliveryLine(for message: ThreadMessage) -> DeliveryLine? {
        guard message.sender == .user else { return nil }
        switch message.delivery {
        case .sending: return .sending
        case .failed: return message.hasPhoto ? .notDeliveredPhoto : .notDelivered
        case .sent: return nil
        }
    }
}
