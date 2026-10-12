import Foundation

// DODDY Brain, Phase 3b (docs/architecture/brain/06_EXECUTION_AND_VERIFICATION.md, ADR-444): the
// checks every voice tool call passes before its own handler runs, as one pure function. It was the
// top of `VoiceSessionController.handle`; it moved here unchanged, so it can be tested on Linux.
// Settings are passed in as values: the gate reads no UserDefaults, no iOS permission and no clock.
//
// Order matters and is kept: translator mode first (nothing is looked up or logged), then the plan
// card's own path, then Pause all, then the connection's switch. The tool's handler still checks
// the iOS permission and shows the card for anything that changes something.

/// The user's settings that decide whether a tool may run at all, read fresh for each call.
public struct ToolGateEnvironment: Equatable, Sendable {
    public let translatorOn: Bool
    /// Settings → Pause all connections (`ConnectionPause`).
    public let connectionsPaused: Bool
    /// Settings → Connections switches that are on.
    public let connectionsOn: Set<VoiceConnection>

    public init(translatorOn: Bool, connectionsPaused: Bool, connectionsOn: Set<VoiceConnection>) {
        self.translatorOn = translatorOn
        self.connectionsPaused = connectionsPaused
        self.connectionsOn = connectionsOn
    }
}

public enum ToolGateDecision: Equatable, Sendable {
    /// Translator mode: answered with `reply`; nothing is looked up or logged (ADR-215).
    case refuse(reply: String)
    /// `propose_plan`: its own path (`PlanProposal`), each step checked as if asked alone.
    case plan
    /// Pause all: answered with `reply`; nothing is looked up or changed.
    case paused(reply: String)
    /// The connection's switch is off: the "turn it on" prompt and `VoiceToolReply.notConnected`.
    case notConnected(VoiceConnection)
    /// On to the tool's own handler.
    case proceed

    /// Whether the request goes into What Doddy did. Translator refusals and the plan (which logs
    /// its steps itself) don't.
    public var logsRequest: Bool {
        switch self {
        case .refuse, .plan: false
        case .paused, .notConnected, .proceed: true
        }
    }
}

public enum ToolGate {
    public static func decide(toolName: String, request: VoiceToolRequest, environment: ToolGateEnvironment) -> ToolGateDecision {
        if environment.translatorOn, !TranslatorPolicy.allows(request) {
            return .refuse(reply: VoiceToolReply.translatorRefused(toolName))
        }
        if toolName == VoiceToolName.proposePlan { return .plan }
        if environment.connectionsPaused, ConnectionPause.applies(to: request) {
            return .paused(reply: ConnectionPause.reply)
        }
        if let connection = VoiceConnection.serving(toolName), !environment.connectionsOn.contains(connection) {
            return .notConnected(connection)
        }
        return .proceed
    }
}
