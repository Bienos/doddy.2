import Foundation

// The opening line Doddy speaks first and the island shows ("Hey Pat, what's up?"). It began with
// the "Hey Doddy" wake word (ADR-254); the wake word and its Picovoice listener were removed in
// ADR-549, and this stays because the Talk to Doddy shortcut and Back Tap greet the same way.

/// What the island says and Doddy speaks first.
public enum WakeGreeting {
    /// The voice agent's first message is `{{opening_line}}` (voice-agent/session.json).
    public static let variableName = "opening_line"

    /// The name to greet with: the nickname from Doddy's personality settings, else the first
    /// word of the approved name from About you, else nil. Both are cleaned like a nickname.
    public static func name(nickname: String?, profileName: String?) -> String? {
        if let nickname = Nickname.clean(nickname) { return nickname }
        let first = profileName?
            .split(whereSeparator: { $0 == " " || $0.isNewline })
            .first
            .map(String.init)
        return Nickname.clean(first)
    }

    /// "Hey Pat, what's up?" — "Hey, what's up?" without a name (no "bud" tic, ADR-556).
    /// Polish: "Hej Pat, co słychać?" or "Hej, co słychać?".
    public static func line(name: String?, polish: Bool = false) -> String {
        let name = Nickname.clean(name)
        if polish {
            return name.map { "Hej \($0), co słychać?" } ?? "Hej, co słychać?"
        }
        return name.map { "Hey \($0), what's up?" } ?? "Hey, what's up?"
    }

    /// What Doddy says first (Brand Guidelines V2.2 p.53, ADR-556). After the wake word: the
    /// greeting. The user's very first conversation: "Hi, I'm Doddy. What's on your mind?".
    /// Otherwise the familiar return, "I'm here. What's up?", the same words as Home.
    /// The Polish lines are drafts until a Polish speaker has read them (l10n/REVIEW_NOTES.md).
    public static func openingLine(afterWakeWord: Bool, name: String?, polish: Bool,
                                   firstConversation: Bool = false) -> String {
        if afterWakeWord { return line(name: name, polish: polish) }
        if firstConversation {
            return polish ? "Cześć, tu Doddy. Co ci chodzi po głowie?" : "Hi, I'm Doddy. What's on your mind?"
        }
        return polish ? "Jestem. Co słychać?" : "I'm here. What's up?"
    }
}
