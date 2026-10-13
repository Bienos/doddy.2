import Foundation

// The guided first conversation (ADR-401). In the user's very first voice conversation, after his
// opening line, Doddy says in two or three sentences what he can do here and offers one thing to
// try. Every later conversation is as before. "First" means no conversation has ever reached
// Listening on this iPhone (the same flag Home's first visit uses, ADR-326); a translator start or
// a morning check-in has its own job, so it never gets the tour.

/// The `{{first_conversation}}` variable: "yes" only for that one conversation, else "no".
public enum FirstConversationPrompt {
    public static let variableName = "first_conversation"

    /// What the app says to the agent after the greeting, so the tour comes without the user
    /// having to speak first. Sent only when the variable is "yes".
    public static let appMessage = "First conversation: give the short tour now, as the first conversation section says."

    public static func isFirst(hadConversationBefore: Bool, translator: Bool, morningCheckIn: Bool) -> Bool {
        !hadConversationBefore && !translator && !morningCheckIn
    }

    public static func render(isFirst: Bool) -> String { isFirst ? "yes" : "no" }
}
