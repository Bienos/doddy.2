import AppIntents

/// "Talk to Doddy": opens the app and starts a voice conversation in the foreground.
/// Compiled into the app and the Control Center extension (the control needs the type);
/// because it opens the app, iOS runs `perform()` in the app process.
struct TalkToDoddyIntent: AppIntent {
    static var title: LocalizedStringResource { "Talk to Doddy" }
    static var description: IntentDescription {
        IntentDescription("Opens Doddy and starts a voice conversation. Doddy listens only while the conversation screen is open.")
    }
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !DODDY_CONTROLS_EXTENSION
        AppServices.router.talkShortcutArrived()
        #endif
        return .result()
    }
}
