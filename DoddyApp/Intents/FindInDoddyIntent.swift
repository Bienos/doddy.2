import AppIntents

/// "Find in Doddy": opens Memories → Find with the words filled in, and the search runs on the
/// phone exactly as if they were typed. It only searches; nothing is saved or changed (ADR-181).
/// App target only.
struct FindInDoddyIntent: AppIntent {
    static let title: LocalizedStringResource = "Find in Doddy"
    static var description: IntentDescription {
        IntentDescription("Opens Doddy and searches your saved notes on this iPhone.")
    }
    static let openAppWhenRun = true

    #if compiler(>=6.4)
    @available(iOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    #endif

    @Parameter(title: "Search for", requestValueDialog: "What are you looking for?")
    var query: String

    static var parameterSummary: some ParameterSummary {
        Summary("Find \(\.$query) in Doddy")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        ShortcutRouter.shared.findInDoddyInvoked(query: query)
        return .result()
    }
}
