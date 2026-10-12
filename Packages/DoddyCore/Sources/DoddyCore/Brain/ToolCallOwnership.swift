import Foundation

// DODDY Brain, Phase 3a (docs/architecture/brain/06_EXECUTION_AND_VERIFICATION.md, ADR-443):
// which voice conversation each tool call belongs to.
//
// The voice controller numbers every start and every stop (`startAttempt`, review H1). A tool
// call is recorded with the number current when it arrived. Work that finishes after an `await`
// (a server prepare, a Maps search, a list lookup) asks whether its call still belongs to the
// conversation open now. If the user ended it, or ended it and started another, the answer is no:
// no card is shown, no change runs and no result goes to the new conversation.

public struct ToolCallOwnership: Equatable, Sendable {
    private var attempts: [String: Int] = [:]

    public init() {}

    /// Records the conversation a call arrived in. The first record wins, so a provider repeating
    /// an id can't move a call into a later conversation.
    public mutating func arrived(_ toolCallID: String, attempt: Int) {
        if attempts[toolCallID] == nil { attempts[toolCallID] = attempt }
    }

    /// Whether the call arrived in `attempt`. A call never recorded belongs to no conversation:
    /// unknown ids fail closed.
    public func belongs(_ toolCallID: String, to attempt: Int) -> Bool {
        attempts[toolCallID] == attempt
    }

    /// A new conversation is starting: calls of earlier ones are forgotten (they could only ever
    /// be stale now), so memory stays bounded by one conversation's calls.
    public mutating func starting(_ attempt: Int) {
        attempts = attempts.filter { $0.value >= attempt }
    }

    /// How many calls are remembered (for tests).
    public var count: Int { attempts.count }
}
