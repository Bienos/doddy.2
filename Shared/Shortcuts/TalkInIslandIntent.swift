import AppIntents

/// "Talk in the Island" (ADR-566): starts a voice conversation without opening Doddy. Doddy says
/// "Hey Pat, what's up?", the Dynamic Island opens up while he talks, and Mute and Stop are on the
/// island and the Lock Screen. Used by the "Talk in the Island" control, which the Action Button
/// can run (Settings › Action Button › Controls), and listed in the Shortcuts app.
/// `TalkToDoddyIntent` stays the one that opens the app (Siri, Back Tap, the other control).
///
/// An `AudioRecordingIntent`, so iOS lets the recording run with Doddy in the background while
/// its Live Activity is up, and a `LiveActivityIntent`, so iOS runs it in the app's process
/// (starting it in the background) and lets it start that Live Activity. iOS 18 or later
/// (`AudioRecordingIntent`); it is not an App Shortcut because the App Shortcuts list can't hold
/// an iOS 18 intent in an app that still runs on iOS 17.
///
/// Compiled into the app and the widget extension, because the control needs the type. Only the
/// app's copy does anything; iOS 27 would otherwise pick "any available target", so it is pinned
/// to the app (ADR-131).
@available(iOS 18.0, *)
struct TalkInIslandIntent: AudioRecordingIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Talk in the Island"
    static var description: IntentDescription {
        IntentDescription("Starts a voice conversation without opening Doddy. He greets you and stays in the Dynamic Island while you talk. Tap the island to see the conversation.")
    }
    static let openAppWhenRun = false
    /// The conversation hands Doddy your saved notes, so not from a locked iPhone.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    #if compiler(>=6.4)
    @available(iOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    #endif

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !DODDY_WIDGET_EXTENSION
        try await TalkInIsland.start()
        #endif
        return .result()
    }
}
