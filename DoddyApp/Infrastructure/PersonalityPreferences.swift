import DoddyCore
import Foundation

extension PersonalitySettings {
    /// The user's choices from Settings → Doddy's voice and personality (UserDefaults, like other UI
    /// preferences; see DECISIONS.md ADR-062). Unknown or missing values use the defaults.
    static func stored(in defaults: UserDefaults = .standard) -> PersonalitySettings {
        PersonalitySettings(
            humour: defaults.string(forKey: PreferenceKey.personalityHumour),
            length: defaults.string(forKey: PreferenceKey.personalityLength),
            formality: defaults.string(forKey: PreferenceKey.personalityFormality),
            mood: defaults.string(forKey: PreferenceKey.personalityMood))
    }
}

extension VoiceStyle {
    /// Voice, speed and expressiveness from the same Settings screen (ADR-105).
    static func stored(in defaults: UserDefaults = .standard) -> VoiceStyle {
        VoiceStyle(
            voice: defaults.string(forKey: PreferenceKey.voiceChoice),
            speed: defaults.string(forKey: PreferenceKey.voiceSpeed),
            expressiveness: defaults.string(forKey: PreferenceKey.voiceExpressiveness))
    }
}

extension ConversationLanguage {
    static func stored(in defaults: UserDefaults = .standard) -> ConversationLanguage {
        ConversationLanguage(stored: defaults.string(forKey: PreferenceKey.voiceLanguage))
    }
}

extension Nickname {
    /// The cleaned nickname from Settings, or nil when unset or not a plain name.
    static func stored(in defaults: UserDefaults = .standard) -> String? {
        clean(defaults.string(forKey: PreferenceKey.nickname))
    }
}
