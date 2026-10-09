import Foundation

/// Guided Back Tap setup: the links each step opens and the tap-test rule.
///
/// iOS has no API to assign Back Tap or read what is assigned. Doddy can only open the right
/// screens and notice when its own Open Doddy shortcut opened it; whether that was a double
/// tap is something only the user can confirm.
public enum BackTapSetup {
    /// The name the user gives the shortcut. The Shortcuts links below look it up by name.
    public static let shortcutName = "Open Doddy"

    /// Where the remaining taps are if Settings does not open directly on Back Tap.
    public static let settingsPath = ["Settings", "Accessibility", "Touch", "Back Tap"]

    /// How long after "Start the tap test" a shortcut open still counts for the test.
    public static let tapTestWindow: TimeInterval = 10 * 60

    public enum Link: Equatable, Sendable {
        /// Shortcuts editor with a new, empty shortcut (documented `shortcuts://` URL).
        case newShortcut
        /// The user's Open Doddy shortcut in the Shortcuts editor.
        case editShortcut
        /// Runs the user's Open Doddy shortcut, which should open Doddy.
        case runShortcut
        /// Settings → Accessibility → Touch → Back Tap. Undocumented Settings URL: it may stop
        /// working in a future iOS, and must be reviewed before any App Store submission.
        case backTapSettings

        /// URLs to try in order. The next one is used only if iOS refuses the previous one;
        /// iOS may also accept a Settings URL but open a different page, so the UI always
        /// shows `settingsPath` as well.
        public var candidates: [URL] {
            switch self {
            case .newShortcut:
                [URL(string: "shortcuts://create-shortcut")!, URL(string: "shortcuts://")!]
            case .editShortcut:
                [URL(string: "shortcuts://open-shortcut?name=\(BackTapSetup.encodedName)")!, URL(string: "shortcuts://")!]
            case .runShortcut:
                [URL(string: "shortcuts://run-shortcut?name=\(BackTapSetup.encodedName)")!]
            case .backTapSettings:
                [
                    URL(string: "App-prefs:root=ACCESSIBILITY&path=TOUCH_REACHABILITY_TITLE/Back%20Tap")!,
                    URL(string: "prefs:root=ACCESSIBILITY&path=TOUCH_REACHABILITY_TITLE/Back%20Tap")!,
                    URL(string: "App-prefs:root=ACCESSIBILITY")!,
                    URL(string: "App-prefs:")!,
                ]
            }
        }
    }

    static var encodedName: String {
        shortcutName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+")))!
    }
}

/// Result of the tap test, from two timestamps the app records itself.
public enum TapTestState: Equatable, Sendable {
    case notStarted
    /// Test running; Doddy has not been opened by the Open Doddy shortcut since it started.
    case waiting(since: Date)
    /// The Open Doddy shortcut opened Doddy during the test. The user still has to say whether
    /// that was the double tap (running it from Shortcuts or Siri looks the same to Doddy).
    case openedByShortcut(at: Date)
    /// Nothing arrived within `BackTapSetup.tapTestWindow`.
    case timedOut

    public static func evaluate(
        testStartedAt: Date?, lastShortcutOpenAt: Date?, now: Date,
        window: TimeInterval = BackTapSetup.tapTestWindow
    ) -> TapTestState {
        guard let start = testStartedAt else { return .notStarted }
        if let opened = lastShortcutOpenAt, opened >= start, opened.timeIntervalSince(start) <= window {
            return .openedByShortcut(at: opened)
        }
        return now.timeIntervalSince(start) > window ? .timedOut : .waiting(since: start)
    }
}
