import AppIntents
import DoddyCore

/// "Stop listening in Doddy" (OP-024, ADR-335): ends a voice conversation, turns "Hey Doddy" off
/// and stops a voice memo, then says "Stopped" only when each says its microphone is closed.
/// Works with the iPhone locked: it only turns things off. The app doesn't open. App target only.
struct StopListeningIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Doddy listening"
    static var description: IntentDescription {
        IntentDescription("Ends a conversation with Doddy, turns off “Hey Doddy” and stops a voice memo recording. Nothing is saved.")
    }
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    #if compiler(>=6.4)
    @available(iOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    #endif

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let report = await ListeningStop.stopAll()
        ListeningIndicatorModel.shared.show(report)
        return .result(dialog: "\(report.reply(.current))")
    }
}
