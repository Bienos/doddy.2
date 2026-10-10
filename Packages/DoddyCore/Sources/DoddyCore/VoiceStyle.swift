import Foundation

/// Which voice Doddy speaks with. Every option is a voice already in the owner's ElevenLabs
/// account (built-in or in My Voices), so the agent can use it without further setup. `doddy`
/// keeps the voice set on the agent (ADR-051) by sending nothing.
public enum VoiceChoice: String, CaseIterable, Sendable, Codable {
    case doddy, josh, wiktor, river, jessica, will

    /// ElevenLabs voice id sent as the TTS override, or nil for the agent's own voice.
    public var elevenLabsVoiceID: String? {
        switch self {
        case .doddy: nil
        case .josh: "ZoiZ8fuDWInAcwPXaVeq"     // Josh – warm, smooth, steady (Doddy's voice before ADR-051)
        case .wiktor: "Mmjvne5i15kUnfr4fQF3"   // Wiktor – native Polish, warm
        case .river: "SAz9YHcvj6GT2YYXdXww"    // River – relaxed, neutral
        case .jessica: "cgSgspJ2msm6clMCkdW9"  // Jessica – bright, warm
        case .will: "bIHbv24MWmeRgasZH58o"     // Will – laid-back
        }
    }
}

extension VoiceChoice {
    /// Bundled sample (`DoddyApp/Resources/VoicePreviews/<name>.mp3`): Doddy's hello in English
    /// and Polish, recorded once in this voice (ADR-122).
    public var previewResourceName: String { "voice-preview-\(rawValue)" }
}

/// How fast Doddy talks. ElevenLabs accepts 0.7–1.2; the agent default is 1.0.
public enum SpeakingSpeed: String, CaseIterable, Sendable, Codable {
    case slower, normal, faster

    public var elevenLabsSpeed: Double {
        switch self {
        case .slower: 0.85
        case .normal: 1.0
        case .faster: 1.15
        }
    }
}

/// How much the voice varies in delivery. Maps to ElevenLabs stability (higher = steadier);
/// the agent default is 0.5.
public enum Expressiveness: String, CaseIterable, Sendable, Codable {
    case steady, natural, expressive

    public var elevenLabsStability: Double {
        switch self {
        case .steady: 0.75
        case .natural: 0.5
        case .expressive: 0.3
        }
    }
}

/// The TTS settings to override for one conversation. Fields left nil keep the agent's value.
public struct VoiceOverride: Equatable, Sendable {
    public var voiceID: String?
    public var speed: Double?
    public var stability: Double?
}

/// How Doddy sounds: voice, speed and expressiveness. Stored on the phone and sent as TTS
/// overrides when a conversation starts. Unlike `PersonalitySettings`, nothing here reaches the
/// prompt, so it cannot change what Doddy says or which rules he follows.
public struct VoiceStyle: Equatable, Sendable, Codable {
    public var voice: VoiceChoice
    public var speed: SpeakingSpeed
    public var expressiveness: Expressiveness

    public init(voice: VoiceChoice, speed: SpeakingSpeed, expressiveness: Expressiveness) {
        self.voice = voice
        self.speed = speed
        self.expressiveness = expressiveness
    }

    /// The agent's own settings: its voice, normal speed, natural delivery.
    public static let doddyDefault = VoiceStyle(voice: .doddy, speed: .normal, expressiveness: .natural)

    /// Builds the style from stored raw strings. Anything missing or unknown falls back to the
    /// default for that one setting, so an old or damaged value never blocks a conversation.
    public init(voice: String?, speed: String?, expressiveness: String?) {
        let fallback = Self.doddyDefault
        self.init(
            voice: voice.flatMap(VoiceChoice.init(rawValue:)) ?? fallback.voice,
            speed: speed.flatMap(SpeakingSpeed.init(rawValue:)) ?? fallback.speed,
            expressiveness: expressiveness.flatMap(Expressiveness.init(rawValue:)) ?? fallback.expressiveness)
    }

    /// Playback rate for the bundled sample: the same factor the conversation uses.
    public var previewRate: Double { speed.elevenLabsSpeed }

    /// What to send, or nil when everything matches the agent's defaults. Only changed fields are
    /// set, so the default style works even on an agent that allows no overrides.
    public var override: VoiceOverride? {
        let fallback = Self.doddyDefault
        let result = VoiceOverride(
            voiceID: voice.elevenLabsVoiceID,
            speed: speed == fallback.speed ? nil : speed.elevenLabsSpeed,
            stability: expressiveness == fallback.expressiveness ? nil : expressiveness.elevenLabsStability)
        return result == VoiceOverride() ? nil : result
    }
}

/// Which language a voice conversation starts in. `auto` keeps the agent's language detection
/// (it starts in English and follows the user); a fixed language is sent as the ElevenLabs
/// `agent.language` override, which also picks that language's greeting (ADR-132). Either way the
/// agent switches when the user switches (ADR-206). The fixed choices are the European languages
/// the ElevenLabs Swift SDK can start in; the agent also follows Estonian, Catalan, Serbian,
/// Icelandic, Irish, Maltese, Macedonian, Bosnian, Belarusian, Welsh, Galician and Luxembourgish
/// once the user speaks them. Raw values are stored, so existing ones never change.
public enum ConversationLanguage: String, CaseIterable, Sendable, Codable {
    case auto
    case english, polish, german, french, spanish, italian, portuguese, dutch, swedish, danish, norwegian, finnish, czech, slovak, hungarian, romanian, bulgarian, greek, croatian, slovenian, latvian, lithuanian, ukrainian, russian, turkish

    /// ISO 639-1 code for the override, or nil to send nothing.
    public var overrideCode: String? {
        switch self {
        case .auto: nil
        case .english: "en"
        case .polish: "pl"
        case .german: "de"
        case .french: "fr"
        case .spanish: "es"
        case .italian: "it"
        case .portuguese: "pt"
        case .dutch: "nl"
        case .swedish: "sv"
        case .danish: "da"
        case .norwegian: "no"
        case .finnish: "fi"
        case .czech: "cs"
        case .slovak: "sk"
        case .hungarian: "hu"
        case .romanian: "ro"
        case .bulgarian: "bg"
        case .greek: "el"
        case .croatian: "hr"
        case .slovenian: "sl"
        case .latvian: "lv"
        case .lithuanian: "lt"
        case .ukrainian: "uk"
        case .russian: "ru"
        case .turkish: "tr"
        }
    }

    /// The language's own name ("Deutsch"); "Automatic" is the app's word, not a language.
    public var nativeName: String? {
        switch self {
        case .auto: nil
        case .english: "English"
        case .polish: "Polski"
        case .german: "Deutsch"
        case .french: "Français"
        case .spanish: "Español"
        case .italian: "Italiano"
        case .portuguese: "Português"
        case .dutch: "Nederlands"
        case .swedish: "Svenska"
        case .danish: "Dansk"
        case .norwegian: "Norsk"
        case .finnish: "Suomi"
        case .czech: "Čeština"
        case .slovak: "Slovenčina"
        case .hungarian: "Magyar"
        case .romanian: "Română"
        case .bulgarian: "Български"
        case .greek: "Ελληνικά"
        case .croatian: "Hrvatski"
        case .slovenian: "Slovenščina"
        case .latvian: "Latviešu"
        case .lithuanian: "Lietuvių"
        case .ukrainian: "Українська"
        case .russian: "Русский"
        case .turkish: "Türkçe"
        }
    }

    public var englishName: String? {
        switch self {
        case .auto: nil
        case .english: "English"
        case .polish: "Polish"
        case .german: "German"
        case .french: "French"
        case .spanish: "Spanish"
        case .italian: "Italian"
        case .portuguese: "Portuguese"
        case .dutch: "Dutch"
        case .swedish: "Swedish"
        case .danish: "Danish"
        case .norwegian: "Norwegian"
        case .finnish: "Finnish"
        case .czech: "Czech"
        case .slovak: "Slovak"
        case .hungarian: "Hungarian"
        case .romanian: "Romanian"
        case .bulgarian: "Bulgarian"
        case .greek: "Greek"
        case .croatian: "Croatian"
        case .slovenian: "Slovenian"
        case .latvian: "Latvian"
        case .lithuanian: "Lithuanian"
        case .ukrainian: "Ukrainian"
        case .russian: "Russian"
        case .turkish: "Turkish"
        }
    }

    /// Unknown or missing stored values mean `auto`.
    public init(stored: String?) {
        self = stored.flatMap(ConversationLanguage.init(rawValue:)) ?? .auto
    }
}
