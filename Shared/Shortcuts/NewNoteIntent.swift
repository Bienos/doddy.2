import AppIntents

/// "New note in Doddy": opens Doddy's capture screen, empty, as if the user tapped "Save a
/// detail". Used by the App Shortcut (Siri, Shortcuts, Action Button) and the Control Center /
/// Lock Screen control. Nothing is saved until the user types and taps Save (ADR-137).
///
/// Compiled into the app and the widget extension, like `TalkToDoddyIntent`: the control needs
/// the type, and because it opens the app, iOS runs `perform()` in the app's process.
struct NewNoteIntent: AppIntent {
    static let title: LocalizedStringResource = "New Note in Doddy"
    static var description: IntentDescription {
        IntentDescription("Opens Doddy ready for a new note. Nothing is saved until you tap Save.")
    }
    static let openAppWhenRun = true

    #if compiler(>=6.4)
    @available(iOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    #endif

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !DODDY_WIDGET_EXTENSION
        ShortcutRouter.shared.newNoteInvoked()
        #endif
        return .result()
    }
}
