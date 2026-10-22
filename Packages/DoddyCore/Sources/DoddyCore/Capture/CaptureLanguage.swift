import Foundation

/// Which language a recording is written out in (ADR-588). One per recording: the on-device
/// recognizer takes one locale at a time and does not detect the language, so a mixed-language
/// recording is written out once per language the user asks for, never guessed.
public enum CaptureLanguage {
    /// A recognizer locale for a two-letter code, preferring what the iPhone itself lists
    /// ("en" with an iPhone set to British English gives "en-GB"). Polish is "pl-PL".
    public static func localeIdentifier(code: String, preferredLanguages: [String]) -> String {
        let code = code.lowercased()
        if let match = preferredLanguages.first(where: { $0.lowercased() == code || $0.lowercased().hasPrefix(code + "-") }) {
            return match.contains("-") ? match : fallbackRegion(code)
        }
        return fallbackRegion(code)
    }

    private static func fallbackRegion(_ code: String) -> String {
        switch code {
        case "pl": "pl-PL"
        case "en": "en-GB"
        case "de": "de-DE"
        case "fr": "fr-FR"
        case "es": "es-ES"
        case "it": "it-IT"
        case "pt": "pt-PT"
        default: code
        }
    }

    /// The code to start from: the language the user chose for conversations, or else the iPhone's.
    public static func code(conversationOverride: String?, preferredLanguages: [String]) -> String {
        if let conversationOverride, !conversationOverride.isEmpty { return conversationOverride }
        return preferredLanguages.first.map { String($0.prefix(2)) } ?? "en"
    }

    /// "pl-PL" and "en-GB" for a person: "Polski", "English".
    public static func displayName(_ localeIdentifier: String) -> String {
        switch localeIdentifier.lowercased().prefix(2) {
        case "pl": "Polski"
        case "en": "English"
        case "de": "Deutsch"
        case "fr": "Français"
        case "es": "Español"
        case "it": "Italiano"
        case "pt": "Português"
        default: localeIdentifier
        }
    }
}
