import DoddyCore
import Foundation

/// What the first-launch welcome (ADR-595) remembers, read straight from UserDefaults so a UI
/// test's launch argument works like the real switch. The rule itself is `WelcomeRule` (DoddyCore, tested).
enum WelcomePreferences {
    static func seen(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: PreferenceKey.welcomeSeen)
    }

    static func replayRequested(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: PreferenceKey.welcomeReplay)
    }

    /// The welcome is over for this installation (finished or skipped), and a replay is spent.
    static func markSeen(_ defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: PreferenceKey.welcomeSeen)
        defaults.set(false, forKey: PreferenceKey.welcomeReplay)
    }

    /// Settings › "Show the welcome again".
    static func requestReplay(_ defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: PreferenceKey.welcomeReplay)
    }

    /// UI tests only: `-welcome YES` forces the welcome, `-welcome NO` skips it. Nil when absent.
    static func override(_ defaults: UserDefaults = .standard) -> Bool? {
        defaults.object(forKey: "welcome") == nil ? nil : defaults.bool(forKey: "welcome")
    }
}
