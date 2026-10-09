import AppIntents
import Foundation

/// "Open Doddy" action for the user's Back Tap shortcut. It opens the app and records when it
/// ran, which is the only evidence the tap test has (see `TapTestState`).
struct OpenDoddyIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Doddy"
    static let description = IntentDescription("Opens Doddy. Put it in a shortcut to use with Back Tap.")
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: PreferenceKey.lastOpenedByShortcut)
        return .result()
    }
}

/// Makes the action show up under Doddy in the Shortcuts app and Spotlight with no setup.
/// Back Tap only lists shortcuts in the user's own library, so setup still has the user make one.
struct DoddyAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenDoddyIntent(),
            phrases: ["Open \(.applicationName)"],
            shortTitle: "Open Doddy",
            systemImageName: "hand.tap")
    }
}
