import DoddyCore
import Foundation

/// Writes the screens' language where iOS reads it (ADR-459). iOS picks the language when the app
/// starts, from the app's own `AppleLanguages` setting (the one iOS Settings › Doddy › Language
/// writes too). A choice made in Doddy also shows at once (`ScreenLanguage`, decision
/// `2026-11-14-language-switch-at-once`). The rules are `AppLanguage.launchAction` and
/// `AppLanguage.screenLanguage` in DoddyCore; this only reads and writes the values.
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

    /// Set once the English that builds before ADR-573 wrote has been replaced by Polish.
    private static let polishDefaultAppliedKey = "appLanguage.polishDefaultApplied"

    /// Before the first screen. Test runs leave the simulator's setting alone: UI tests (an
    /// in-memory or per-test store) and the unit tests' host app. Writing the Polish default there
    /// (ADR-573) made every later test run in Polish. iOS has already picked this launch's
    /// language, so the Polish default written here shows from the next launch; a choice made in
    /// Doddy shows on this one too, in case iOS Settings › Doddy › Language changed it since.
    static func applyAtLaunch(defaults: UserDefaults = .standard) {
        let process = ProcessInfo.processInfo
        let isTestRun = process.arguments.contains("-inMemoryStore") || process.arguments.contains("-memoryTestID")
            || process.environment["XCTestConfigurationFilePath"] != nil
        guard !isTestRun else { return }
        write(AppLanguage.launchAction(
            stored: defaults.string(forKey: PreferenceKey.appLanguage), appLanguages: appLanguages(defaults),
            polishDefaultApplied: defaults.bool(forKey: polishDefaultAppliedKey)), to: defaults)
        defaults.set(true, forKey: polishDefaultAppliedKey)
        if let stored = defaults.string(forKey: PreferenceKey.appLanguage) {
            ScreenLanguage.show(AppLanguage(stored: stored))
        }
    }

    /// The person picked a language in Settings. It shows at once: the table first, then the saved
    /// choice, whose change makes `RootView` draw the screens again with that table.
    static func choose(_ language: AppLanguage, defaults: UserDefaults = .standard) {
        ScreenLanguage.show(language)
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
