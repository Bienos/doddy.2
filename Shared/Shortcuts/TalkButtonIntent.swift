import AppIntents

/// "Talk to Doddy" as the Action Button, Control Center or the Lock Screen runs it (ADR-579,
/// ADR-632): both Talk to Doddy controls run it. A press talks in the Dynamic Island without
/// opening Doddy; pressed again while a conversation runs, it ends it (`TalkLaunchPlanner`).
/// Settings has no choice for it since ADR-593, so `TalkButton.press` always uses the island.
///
/// Why a second intent next to `TalkToDoddyIntent`: talking without opening needs
/// `AudioRecordingIntent` (iOS 18) and `openAppWhenRun = false`, while Siri, the Shortcuts app and
/// Back Tap use the App Shortcut, which must stay an iOS 17 type that opens the app. When something
/// only the app can fix is missing, the press continues in the foreground after iOS's own "Open
/// Doddy?" confirmation (`supportedModes` on iOS 26, `ForegroundContinuableIntent` on iOS 18 to
/// 25, the only supported way there).
///
/// Compiled into the app and the widget extension (the control needs the type). Only the app's
/// copy does anything, so it is pinned to the app (ADR-131). Not listed in Shortcuts: there it is
/// the App Shortcut "Talk to Doddy".
@available(iOS 18.0, *)
struct TalkButtonIntent: AudioRecordingIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Talk to Doddy"
    static var description: IntentDescription {
        IntentDescription("Talks to Doddy in the Dynamic Island, without opening him. Press again to end.")
    }
    static let isDiscoverable = false
    static let openAppWhenRun = false
    /// The conversation hands Doddy your saved notes, so not from a locked iPhone.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    #if compiler(>=6.2)
    /// Starts in the background; may come to the front once `perform()` decides it should.
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }
    #endif

    #if compiler(>=6.4)
    @available(iOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    #endif

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !DODDY_WIDGET_EXTENSION
        switch await TalkButton.press() {
        case .done:
            break
        case .openApp:
            try await openDoddy(confirm: false, reason: nil)
        case .askToOpenApp(let reason):
            try await openDoddy(confirm: true, reason: reason)
        case .tell(let message):
            throw TalkInIsland.Problem(message: message)
        }
        #endif
        return .result()
    }

    #if !DODDY_WIDGET_EXTENSION
    /// Brings Doddy forward on the conversation screen. `confirm`: iOS asks first.
    @MainActor
    private func openDoddy(confirm: Bool, reason: String?) async throws {
        let dialog = reason.map { IntentDialog(LocalizedStringResource(stringLiteral: $0)) }
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            guard systemContext.currentMode.canContinueInForeground else {
                throw TalkInIsland.Problem(message: reason ?? TalkButton.openDoddyToTalk)
            }
            try await continueInForeground(dialog, alwaysConfirm: confirm)
            ShortcutRouter.shared.talkButtonOpenedApp()
            return
        }
        #endif
        // The continuation runs once the app is in front; it isn't main-actor isolated itself.
        throw needsToContinueInForegroundError(dialog) {
            await ShortcutRouter.shared.talkButtonOpenedApp()
        }
    }
    #endif
}

#if !DODDY_WIDGET_EXTENSION
/// Only the app's copy can bring Doddy to the front, and `ForegroundContinuableIntent` is
/// unavailable in app extensions, so the widget's copy of the type doesn't conform.
@available(iOS 18.0, *)
extension TalkButtonIntent: ForegroundContinuableIntent {}
#endif
