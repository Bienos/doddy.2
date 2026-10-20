import Foundation

// The opening line Doddy speaks first and the island shows ("Hey Pat, what's up?"). It began with
// the "Hey Doddy" wake word (ADR-254); the wake word and its Picovoice listener were removed in
// ADR-549, and this stays because the Talk to Doddy shortcut and Back Tap greet the same way.

/// What the island says and Doddy speaks first.
public enum WakeGreeting {
    /// Used when the user hasn't given Doddy a name to call them.
    public static let fallbackName = "bud"
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

    /// "Hey Pat, what's up?" — "Hey bud, what's up?" without a name. Polish has no "bud":
    /// "Hej Pat, co słychać?" or "Hej, co słychać?".
    public static func line(name: String?, polish: Bool = false) -> String {
        let name = Nickname.clean(name)
        if polish {
            return name.map { "Hej \($0), co słychać?" } ?? "Hej, co słychać?"
        }
        return "Hey \(name ?? fallbackName), what's up?"
    }

    /// What Doddy says first. After the wake word: the greeting. Otherwise the live agent's own
    /// opening (as read from ElevenLabs on 2026-10-11), so a tap conversation sounds as it did.
    public static func openingLine(afterWakeWord: Bool, name: String?, polish: Bool) -> String {
        if afterWakeWord { return line(name: name, polish: polish) }
        return polish ? "Hej, tu Doddy. Co słychać?" : "Hey, it's Doddy. What's up?"
    }
}
