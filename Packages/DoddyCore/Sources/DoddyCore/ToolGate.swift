import Foundation

/// The checks a voice tool call passes before its own handling, and which conversation it belongs
/// to (ADR-458). Pure: the controller reads the switches and its start number and passes them in,
/// so the order and the stale-conversation rule are tested here, on any OS.
public enum ToolGate {
    public enum Decision: Equatable, Sendable {
        /// Translator mode is on and the call isn't stop_translator: nothing runs, a plan card
        /// included (ADR-215). Checked before anything is looked up or logged.
        case translatorRefused
        /// propose_plan: every step is checked on its own (ADR-204), so none of the checks below
        /// apply to the plan as a whole.
        case plan
        /// Settings → Pause all, and the call would reach another app or account.
        case paused
        /// The connection that serves the tool is switched off in Settings → Connections.
        case notConnected(VoiceConnection)
        /// Nothing stops it here; the tool's own handling runs.
        case run
    }

    /// In this order: translator, plan, Pause all, the tool's connection. The controller logs the
    /// request (What Doddy did) after `.plan` and before `.paused`, so a paused or switched-off
    /// call is still listed.
    public static func decide(
        toolName: String, request: VoiceToolRequest, translatorOn: Bool, pauseAll: Bool,
        isOn: (VoiceConnection) -> Bool
    ) -> Decision {
        if translatorOn, !TranslatorPolicy.allows(request) { return .translatorRefused }
        if toolName == VoiceToolName.proposePlan { return .plan }
        if pauseAll, ConnectionPause.applies(to: request) { return .paused }
        if let connection = VoiceConnection.serving(toolName), !isOn(connection) { return .notConnected(connection) }
        return .run
    }
}

/// Which start of the conversation screen each tool call came from (ADR-458). The controller
/// counts every start and every end; a call is recorded with the number current when it arrived.
/// Its card is shown, its screen state set and its result sent only while that number is still
/// the controller's: a lookup that finishes after End, or after End and a new Start, is dropped
/// instead of showing a card, or replying, in the next conversation.
///
/// Tool call ids come from the provider and are unique per call; a call never recorded counts as
/// stale, so a path that forgot to record fails closed (no card, no reply) instead of leaking.
public struct ToolCallOwners: Sendable {
    private var attempts: [String: Int] = [:]

    public init() {}

    /// When the call arrives, with the start number at that moment.
    public mutating func record(_ toolCallID: String, attempt: Int) {
        attempts[toolCallID] = attempt
    }

    /// True only for a call recorded under `current`.
    public func isCurrent(_ toolCallID: String, attempt current: Int) -> Bool {
        attempts[toolCallID] == current
    }

    /// The call's one answer: forgets it, and says whether the answer may be sent.
    public mutating func finish(_ toolCallID: String, attempt current: Int) -> Bool {
        attempts.removeValue(forKey: toolCallID) == current
    }

    /// Forgets a call without answering it (its card was dropped).
    public mutating func forget(_ toolCallID: String) {
        attempts[toolCallID] = nil
    }

    /// Forgets every call from a start before `attempt`; they would be stale anyway, so this only
    /// keeps the table small. Called by each new start.
    public mutating func forget(before attempt: Int) {
        attempts = attempts.filter { $0.value >= attempt }
    }

    public var count: Int { attempts.count }
}
