import Foundation

/// What Doddy's "Talk to Doddy" control does when the Action Button, Control Center or the Lock
/// Screen runs it (ADR-579). The user picks it once in Settings › Action Button. It changes what
/// Doddy does after iOS runs the control; it can't change which control iOS has on the button
/// (that is iPhone Settings › Action Button, and only the user can set it).
///
/// - `dynamicIsland`: talk without opening Doddy; he stays in the Dynamic Island. When something
///   only the app can fix is missing (the microphone was never allowed, voice isn't set up, the
///   Face ID lock is on, Live Activities are off, the terms aren't accepted), iOS asks whether to
///   open Doddy instead. The default.
/// - `openApp`: open Doddy on the conversation screen, as "Talk to Doddy" always did.
/// - `automatic`: as `dynamicIsland`, but when something only the app can fix is missing, Doddy
///   opens without asking.
public enum TalkLaunchMode: String, CaseIterable, Sendable {
    case dynamicIsland
    case openApp
    case automatic

    /// UserDefaults key (app process; the control's intent runs there, ADR-131).
    public static let preferenceKey = "talkLaunchMode"
    public static let `default`: TalkLaunchMode = .dynamicIsland

    /// The stored choice, or the default when none (or an unknown one) is stored.
    public static func stored(_ raw: String?) -> TalkLaunchMode {
        raw.flatMap(TalkLaunchMode.init(rawValue:)) ?? .default
    }
}

/// Why a start without opening Doddy didn't happen.
public enum TalkStartProblem: Equatable, Sendable {
    /// Something only the app can fix (a permission prompt, sign-in, the voice data notice, the
    /// Face ID lock, the terms) or iOS refused the microphone or the island in the background.
    /// Opening Doddy is the way forward.
    case needsApp(String)
    /// The conversation itself failed (no internet, the provider refused). Opening the app
    /// wouldn't help by itself; the sentence says what happened.
    case failed(String)

    public var message: String {
        switch self {
        case .needsApp(let message), .failed(let message): message
        }
    }
}

/// The conversation as a press of the control finds it.
public enum TalkPressState: Equatable, Sendable {
    case none
    /// A press is still starting one (checks, notes, connecting).
    case starting
    /// One is connecting or live, started at that time.
    case running(since: Date)
}

/// One press of the control, decided before anything starts (ADR-579).
public enum TalkPressStep: Equatable, Sendable {
    /// Open Doddy on the conversation screen.
    case openApp
    /// Start the conversation without opening Doddy.
    case startInIsland
    /// Doddy is the app on screen: show the conversation there (iOS doesn't show his own island
    /// over him).
    case showInApp
    /// Press again to stop: end the running conversation.
    case endRunning
    /// A repeat press while one is starting, or right after: nothing happens.
    case ignore
}

/// What to do after a start without opening Doddy failed.
public enum TalkFallback: Equatable, Sendable {
    /// Open Doddy without asking (Automatic).
    case openApp
    /// Ask iOS to offer "Open Doddy?", with the reason (Dynamic Island).
    case askToOpenApp(String)
    /// Say what happened; nothing opens.
    case tell(String)
}

public enum TalkLaunchPlanner {
    /// A second press within this many seconds of the first is a bounce, not "stop".
    public static let repeatPressWindow: TimeInterval = 2

    public static func step(
        mode: TalkLaunchMode, conversation: TalkPressState, appOnScreen: Bool, now: Date
    ) -> TalkPressStep {
        switch conversation {
        case .starting:
            return .ignore
        case .running(let since):
            return now.timeIntervalSince(since) < repeatPressWindow ? .ignore : .endRunning
        case .none:
            break
        }
        if appOnScreen { return .showInApp }
        return mode == .openApp ? .openApp : .startInIsland
    }

    /// After `.startInIsland` failed. `canOpenApp`: iOS can bring Doddy forward from this run of
    /// the intent (it can't from every place iOS runs it).
    public static func fallback(mode: TalkLaunchMode, problem: TalkStartProblem, canOpenApp: Bool) -> TalkFallback {
        guard case .needsApp(let message) = problem, canOpenApp else { return .tell(problem.message) }
        switch mode {
        case .automatic, .openApp: return .openApp
        case .dynamicIsland: return .askToOpenApp(message)
        }
    }
}

/// One-time move of launch preferences (ADR-579). Until then the island's "Small island" was a
/// third choice of `BackTapAction`, which mixed "what Siri and Back Tap do" with "how big the
/// island gets". It becomes `islandExpands = false` and Back Tap goes back to starting a
/// conversation, so the user keeps exactly what they had. Run before anything reads either key.
public enum LaunchPreferencesMigration {
    /// UserDefaults key: the island opens up by itself when Doddy starts speaking (ADR-577).
    public static let islandExpandsKey = "islandExpands"

    public struct Values: Equatable, Sendable {
        public var backTapAction: String?
        public var islandExpands: Bool?
        public init(backTapAction: String?, islandExpands: Bool?) {
            self.backTapAction = backTapAction
            self.islandExpands = islandExpands
        }
    }

    /// Returns the values to store. Unchanged when there is nothing to move, so running it at
    /// every launch is harmless.
    public static func migrate(_ values: Values) -> Values {
        guard BackTapAction(rawValue: values.backTapAction ?? "") == .smallIsland else { return values }
        return Values(backTapAction: BackTapAction.conversation.rawValue, islandExpands: values.islandExpands ?? false)
    }

    /// The island-expansion switch as stored, on by default.
    public static func islandExpands(_ stored: Bool?) -> Bool { stored ?? true }
}
