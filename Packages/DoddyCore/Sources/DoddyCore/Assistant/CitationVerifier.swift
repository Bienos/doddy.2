import Foundation

/// Whether an answer rests on the user's own saved notes.
public enum AnswerBasis: Equatable, Sendable {
    /// At least one verified note was cited.
    case savedNotes
    /// No note was cited. The UI must say this is not from the user's notes.
    case general
}

/// A reply whose citations have been checked against what was actually sent.
public struct VerifiedAnswer: Equatable, Sendable {
    public let text: String
    /// The cited notes, resolved to the real stored records, in the order cited.
    public let sources: [MemoryRecord]
    /// A file the person asked for, offered as a card (ADR-606). Nothing is made until they tap it.
    public var proposal: AssistantProposal? = nil
    /// A training plan the person asked for, offered as a card (ADR-626). The plan screen opens only on a tap.
    public var planAsk: PlanAsk? = nil

    public var basis: AnswerBasis { sources.isEmpty ? .general : .savedNotes }
}

/// Acceptance A-14: a model may cite only notes that were sent with this request.
/// The gateway checks too; this is the check the user's device does not delegate.
public enum CitationVerifier {
    public static func verify(_ reply: AssistantReply, for request: AssistantRequest) throws(AssistantError) -> VerifiedAnswer {
        if reply.text.allSatisfy(\.isWhitespace) { throw .malformedResponse }

        let allowed = Dictionary(
            request.groundingMemories.map { ($0.record.id, $0.record) },
            uniquingKeysWith: { first, _ in first })
        var seen = Set<UUID>()
        var sources: [MemoryRecord] = []
        for id in reply.citedMemoryIDs {
            guard let record = allowed[id], seen.insert(id).inserted else { throw .invalidCitations }
            sources.append(record)
        }
        return VerifiedAnswer(text: reply.text, sources: sources, proposal: reply.proposal, planAsk: reply.planAsk)
    }
}
