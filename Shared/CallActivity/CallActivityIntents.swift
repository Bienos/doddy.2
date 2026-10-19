import AppIntents
import Foundation

/// Lets the call island's buttons reach the app (ADR-504), the same way as the tools' buttons
/// (`ToolActivityActions`): the intents run in the app's process, where `CallLiveActivity`
/// registers these handlers at launch. Each handler asks the server; the island changes only when
/// the server's answer or push says the call changed.
@MainActor
final class CallActivityActions {
    static let shared = CallActivityActions()

    var takeOver: (@MainActor (UUID) async -> Void)?
    var end: (@MainActor (UUID) async -> Void)?
}

/// "Przejmij" on the call island: the server rings the user's verified phone; pressing 1 there
/// joins the call. Needs the iPhone unlocked.
struct TakeOverCallIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Take over the call"
    static let isDiscoverable = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    #if compiler(>=6.4)
    @available(iOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    #endif

    @Parameter(title: "Call") var caseId: String

    init() { caseId = "" }
    init(caseId: UUID) { self.caseId = caseId.uuidString }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: caseId) { await CallActivityActions.shared.takeOver?(id) }
        return .result()
    }
}

/// "Zakończ" on the call island: Doddy says goodbye and hangs up. Needs the iPhone unlocked.
struct EndDoddyCallIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "End the call"
    static let isDiscoverable = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    #if compiler(>=6.4)
    @available(iOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }
    #endif

    @Parameter(title: "Call") var caseId: String

    init() { caseId = "" }
    init(caseId: UUID) { self.caseId = caseId.uuidString }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: caseId) { await CallActivityActions.shared.end?(id) }
        return .result()
    }
}
