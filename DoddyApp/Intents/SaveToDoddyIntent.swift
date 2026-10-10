import AppIntents

/// "Save to Doddy": opens Doddy's capture screen with the given text filled in. Nothing is saved
/// until the user taps Save there, so a shortcut can never add a note on its own (ADR-179).
/// Works from Siri (Siri asks what to save), the Shortcuts app, the Action Button and a personal
/// shortcut shown in the Share Sheet. App target only.
struct SaveToDoddyIntent: AppIntent {
    static let title: LocalizedStringResource = "Save to Doddy"
    static var description: IntentDescription {
        IntentDescription("Opens Doddy with this text ready to save. Nothing is saved until you tap Save.")
    }
    static let openAppWhenRun = true

    #if compiler(>=6.4)
    @available(iOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    #endif

    @Parameter(
        title: "Text",
        inputOptions: String.IntentInputOptions(multiline: true),
        requestValueDialog: "What should Doddy keep?")
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Save \(\.$text) to Doddy")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        ShortcutRouter.shared.saveToDoddyInvoked(text: text)
        return .result()
    }
}
