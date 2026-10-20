import DoddyCore
import Foundation

/// Writes the screens' language where iOS reads it (ADR-459). iOS picks the language when the app
/// starts, from the app's own `AppleLanguages` setting (the one iOS Settings › Doddy › Language
/// writes too), so a change shows the next time Doddy is opened. The rules are
/// `AppLanguage.launchAction` in DoddyCore; this only reads and writes the values.
///
/// Not covered: widgets, Siri phrases and the system's permission prompts follow the iPhone's
/// language unless the person also sets iOS Settings › Doddy › Language.
enum AppLanguageStore {
    private static let appleLanguages = "AppleLanguages"

    /// The app's own `AppleLanguages`: nil when it has none, so iOS uses the iPhone's languages.
    private static func appLanguages(_ defaults: UserDefaults) -> [String]? {
        guard let id = Bundle.main.bundleIdentifier else { return nil }
        return defaults.persistentDomain(forName: id)?[appleLanguages] as? [String]
    }

    /// What the picker shows now.
    static func chosen(defaults: UserDefaults = .standard) -> AppLanguage {
        AppLanguage.chosen(stored: defaults.string(forKey: PreferenceKey.appLanguage), appLanguages: appLanguages(defaults))
    }

    /// Set once the English that builds before ADR-562 wrote has been replaced by Polish.
    private static let polishDefaultAppliedKey = "appLanguage.polishDefaultApplied"

    /// Before the first screen. UI-test launches leave the simulator's setting alone. iOS has
    /// already picked this launch's language, so a language written here shows from the next launch.
    static func applyAtLaunch(defaults: UserDefaults = .standard) {
        guard !ProcessInfo.processInfo.arguments.contains("-inMemoryStore") else { return }
        write(AppLanguage.launchAction(
            stored: defaults.string(forKey: PreferenceKey.appLanguage), appLanguages: appLanguages(defaults),
            polishDefaultApplied: defaults.bool(forKey: polishDefaultAppliedKey)), to: defaults)
        defaults.set(true, forKey: polishDefaultAppliedKey)
    }

    /// The person picked a language in Settings.
    static func choose(_ language: AppLanguage, defaults: UserDefaults = .standard) {
        defaults.set(language.rawValue, forKey: PreferenceKey.appLanguage)
        write(AppLanguage.launchAction(stored: language.rawValue, appLanguages: appLanguages(defaults)), to: defaults)
    }

    private static func write(_ action: AppLanguage.LaunchAction, to defaults: UserDefaults) {
        switch action {
        case .leave: break
        case .set(let codes): defaults.set(codes, forKey: appleLanguages)
        case .remove: defaults.removeObject(forKey: appleLanguages)
        }
    }
}
