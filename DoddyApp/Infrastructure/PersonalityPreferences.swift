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
