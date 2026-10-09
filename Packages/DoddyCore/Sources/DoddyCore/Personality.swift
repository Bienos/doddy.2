import Foundation

/// How much humour Doddy uses. Values and default come from the persona draft
/// (`reference/character_evals/doddy_persona_v1.yaml`, `settings.humor_level`).
public enum HumourLevel: String, CaseIterable, Sendable, Codable {
    case off, subtle, playful
}

/// How long replies are (`settings.verbosity`).
public enum ReplyLength: String, CaseIterable, Sendable, Codable {
    case brief, balanced, detailed
}

/// How Doddy addresses the user (`settings.formality`).
public enum Formality: String, CaseIterable, Sendable, Codable {
    case casual, neutral, formal
}

/// Doddy's energy in conversation. The persona's trait is "grounded with contextual bursts";
/// this lets the user turn that down or up. It changes delivery only: Doddy does not have or
/// claim real moods.
public enum Mood: String, CaseIterable, Sendable, Codable {
    case calm, grounded, lively
}

/// The user's personality choices for Doddy. Stored on the phone and sent to the voice agent
/// as one dynamic variable (`doddy_personality`) when a conversation starts. Every value comes
/// from a fixed list, so the text the app sends is always one of a known set of instructions.
public struct PersonalitySettings: Equatable, Sendable, Codable {
    public var humour: HumourLevel
    public var length: ReplyLength
    public var formality: Formality
    public var mood: Mood

    public init(humour: HumourLevel, length: ReplyLength, formality: Formality, mood: Mood) {
        self.humour = humour
        self.length = length
        self.formality = formality
        self.mood = mood
    }

    /// Persona defaults: subtle humour, brief, casual, grounded.
    public static let doddyDefault = PersonalitySettings(humour: .subtle, length: .brief, formality: .casual, mood: .grounded)
    /// The persona's "focused" style: no jokes, straight to the point.
    public static let focused = PersonalitySettings(humour: .off, length: .brief, formality: .neutral, mood: .calm)
    /// The persona's "playful" style. Safety rules still apply.
    public static let playful = PersonalitySettings(humour: .playful, length: .balanced, formality: .casual, mood: .lively)

    /// Builds settings from stored raw strings. Anything missing or unknown falls back to the
    /// default for that one setting, so an old or damaged value never blocks a conversation.
    public init(humour: String?, length: String?, formality: String?, mood: String?) {
        let fallback = Self.doddyDefault
        self.init(
            humour: humour.flatMap(HumourLevel.init(rawValue:)) ?? fallback.humour,
            length: length.flatMap(ReplyLength.init(rawValue:)) ?? fallback.length,
            formality: formality.flatMap(Formality.init(rawValue:)) ?? fallback.formality,
            mood: mood.flatMap(Mood.init(rawValue:)) ?? fallback.mood)
    }
}

/// Text for the voice agent's `{{doddy_personality}}` placeholder.
public enum PersonalityPrompt {
    public static let variableName = "doddy_personality"

    /// Always appended: the dials change style, never the rules.
    public static let unchangedRules = "These are style preferences only. Whatever they say: answer the question first, stay honest about being an AI, follow the memory and tool rules exactly, never joke about anything serious (health, money, legal, grief, distress), and never use sarcasm at the user, guilt, flattery or clinginess."

    public static func render(_ settings: PersonalitySettings) -> String {
        [
            "The user chose these settings in the app:",
            "- Humour: " + humour(settings.humour),
            "- Reply length: " + length(settings.length),
            "- Tone: " + formality(settings.formality),
            "- Energy: " + mood(settings.mood),
            unchangedRules,
        ].joined(separator: "\n")
    }

    static func humour(_ level: HumourLevel) -> String {
        switch level {
        case .off: "off. No jokes or playful asides at all; be plainly helpful."
        case .subtle: "subtle. At most one small dry remark about everyday hassles, and only when the moment is light."
        case .playful: "playful. Light jokes about everyday absurdities and your own over-planning are welcome, still one per reply at most, never at the user's expense."
        }
    }

    static func length(_ length: ReplyLength) -> String {
        switch length {
        case .brief: "brief. One or two sentences unless the user asks for more."
        case .balanced: "balanced. Usually two to four sentences."
        case .detailed: "detailed. Up to six sentences with a short explanation, then offer to go deeper."
        }
    }

    static func formality(_ formality: Formality) -> String {
        switch formality {
        case .casual: "casual, like a friendly mate. Informal words are fine (in Polish use \"ty\")."
        case .neutral: "neutral and friendly, plain everyday words, no slang."
        case .formal: "polite and formal. No slang (in Polish use polite, gender-neutral phrasing; don't guess whether to say \"Pan\" or \"Pani\")."
        }
    }

    static func mood(_ mood: Mood) -> String {
        switch mood {
        case .calm: "calm and quiet. Steady, unhurried delivery, no exclamations."
        case .grounded: "grounded. Relaxed and steady, with a little warmth when something goes well."
        case .lively: "lively. Upbeat and energetic, a bit more enthusiasm, but never over the top."
        }
    }
}
