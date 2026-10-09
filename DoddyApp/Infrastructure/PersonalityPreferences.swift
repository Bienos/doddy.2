import DoddyCore
import Foundation

extension PersonalitySettings {
    /// The user's choices from Settings → Doddy's personality (UserDefaults, like other UI
    /// preferences; see DECISIONS.md ADR-058). Unknown or missing values use the defaults.
    static func stored(in defaults: UserDefaults = .standard) -> PersonalitySettings {
        PersonalitySettings(
            humour: defaults.string(forKey: PreferenceKey.personalityHumour),
            length: defaults.string(forKey: PreferenceKey.personalityLength),
            formality: defaults.string(forKey: PreferenceKey.personalityFormality),
            mood: defaults.string(forKey: PreferenceKey.personalityMood))
    }
}
