import AppIntents

/// "Talk to Doddy": starts (or focuses) the voice conversation. Used by the App Shortcut (Siri,
/// Shortcuts, Action Button, Back Tap) and by the Control Center / Lock Screen control. During an
/// active Back Tap test the invocation is the test's receipt instead.
///
/// Where it runs decides what the user sees:
/// - Doddy is already listening for "Hey Doddy" (iPhone microphone live, possibly in the
///   background): the conversation starts exactly as the wake word starts it, on the Dynamic
///   Island only, and the app is not brought to the front.
/// - Anything else: the app opens, because iOS gives the microphone and a new Live Activity only
///   to an app that is in front (ADR-254).
/// iOS 26 and later run the intent in the background first and open the app only in the second
/// case; earlier versions always open it (`openAppWhenRun`).
///
/// Compiled into the app and the widget extension, because the control needs the type. In the
/// extension it does nothing. iOS 27 may otherwise pick "any available target", so the app is
/// pinned there (ADR-131).
struct TalkToDoddyIntent: AppIntent {
    static let title: LocalizedStringResource = "Talk to Doddy"
    static var description: IntentDescription {
        IntentDescription("Starts a voice conversation with Doddy. Doddy listens only while the conversation is open.")
    }
    static let openAppWhenRun = true

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }

    #if compiler(>=6.4)
    @available(iOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    #endif

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !DODDY_WIDGET_EXTENSION
        // A Back Tap test needs the app in front to take the tap as its receipt.
        if #available(iOS 26.0, *), !ShortcutRouter.shared.isBackTapTestActive,
           WakeWordListener.shared.startFromTap() {
            return .result()
        }
        if #available(iOS 26.0, *) {
            try await continueInForeground(alwaysConfirm: false)
        }
        ShortcutRouter.shared.talkToDoddyInvoked()
        #endif
        return .result()
    }
}
