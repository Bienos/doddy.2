import AppIntents

/// "Talk to Doddy": opens the app in the foreground and starts (or focuses) the voice
/// conversation. Used by the App Shortcut (Siri, Shortcuts, Action Button, a personal shortcut
/// for Back Tap) and by the Control Center / Lock Screen control. During an active Back Tap test
/// the invocation is the test's receipt instead. `TalkInIslandIntent` (ADR-567) is the one that
/// starts a conversation without opening the app.
///
/// Compiled into the app and the widget extension, because the control needs the type. It
/// opens the app, so iOS runs `perform()` in the app's process; in the extension it does nothing.
/// iOS 27 may otherwise pick "any available target", so the app is pinned there (ADR-131).
struct TalkToDoddyIntent: AppIntent {
    static let title: LocalizedStringResource = "Talk to Doddy"
    static var description: IntentDescription {
        IntentDescription("Opens Doddy and starts a voice conversation. Doddy listens only while the conversation is open.")
    }
    static let openAppWhenRun = true

    #if compiler(>=6.4)
    @available(iOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    #endif

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !DODDY_WIDGET_EXTENSION
        ShortcutRouter.shared.talkToDoddyInvoked()
        #endif
        return .result()
    }
}
