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
                return ConversationTurn(role: .assistant, text: message.text)
            }
        }
    }

    /// Whether `message` starts with a date heading, given the one before it.
    public static func showsHeading(_ message: ThreadMessage, after previous: ThreadMessage?) -> Bool {
        guard let previous else { return true }
        return message.createdAt.timeIntervalSince(previous.createdAt) >= headingGap
    }

    /// What the box can send: not while another is on its way, and not blank.
    public static func canSend(draft: String, isSending: Bool) -> Bool {
        !isSending && !draft.allSatisfy(\.isWhitespace)
    }

    /// A message that did not get through can be sent again; one that is answered or on its way cannot.
    public static func canRetry(_ message: ThreadMessage) -> Bool {
        message.sender == .user && message.delivery == .failed
    }

    /// The line under a user bubble, or nil when there is nothing to say (answered).
    public enum DeliveryLine: Equatable, Sendable {
        case sending, notDelivered
    }

    public static func deliveryLine(for message: ThreadMessage) -> DeliveryLine? {
        guard message.sender == .user else { return nil }
        switch message.delivery {
        case .sending: return .sending
        case .failed: return .notDelivered
        case .sent: return nil
        }
    }

    // MARK: Bubbles (owner, 23 Oct 2026: the thread looks like iMessage)

    /// Messages from the same sender, with no date heading between them, are one group: they sit close
    /// together and only the last has a tail.
    public static func endsGroup(_ message: ThreadMessage, before next: ThreadMessage?) -> Bool {
        guard let next else { return true }
        return next.sender != message.sender || showsHeading(next, after: message)
    }

    /// The user message that gets "Delivered" under it: the newest one Doddy answered, and only when
    /// nothing the user sent after it is still waiting. Never "Read": nothing here can know that.
    public static func deliveredMarker(in messages: [ThreadMessage]) -> UUID? {
        guard let last = messages.last(where: { $0.sender == .user }), last.delivery == .sent else { return nil }
        return last.id
    }

    /// Only Doddy's messages take a tapback.
    public static func canReact(to message: ThreadMessage) -> Bool {
        message.sender == .doddy
    }

    /// Tapping the tapback a message already has takes it off, as in iMessage; another one replaces it.
    public static func reaction(after tapped: ThreadMessage.Reaction, on message: ThreadMessage) -> ThreadMessage.Reaction? {
        message.reaction == tapped ? nil : tapped
    }
}
