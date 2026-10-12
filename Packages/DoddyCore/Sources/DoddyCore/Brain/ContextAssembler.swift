import Foundation

// DODDY Brain, Phase 1 (docs/architecture/brain/03_CONTEXT_AND_MEMORY.md, ADR-442): the one place
// that decides which of the user's data may go with a request to a given destination. It reuses
// the existing pieces (RecallService, GroundingSelector, LearningContext); it does not store,
// rank or embed anything itself.

/// Where assembled context is about to go. Each destination has its own egress contract.
public enum EgressTarget: Sendable {
    /// The Ask Doddy gateway (`gateway/src/validate.js`), then the model provider behind it.
    case assistantGateway

    /// Note sources the destination accepts. Must equal the gateway's `SOURCES`: a source it
    /// rejects makes the whole question fail ("memory-source"), so such notes are withheld instead.
    public var allowedNoteSources: Set<MemorySource> {
        switch self {
        case .assistantGateway: [.explicitText, .explicitVoice, .sharedContent, .importedLegacyUnknown]
        }
    }

    public var notesBudget: GroundingBudget {
        switch self {
        case .assistantGateway: .standard
        }
    }

    /// Learned facts and routines (ADR-440). Off for the gateway until its limits are raised in
    /// step (LEARNING_LOOP.md §5, §13): a hard cap the gateway would reject is a bug, not a fallback.
    public var acceptsLearnedContext: Bool {
        switch self {
        case .assistantGateway: false
        }
    }
}

/// What may leave the device with one request, plus content-free counts of what was held back.
public struct AssembledContext: Equatable, Sendable {
    /// The only stored notes the reply may cite.
    public let notes: [MemoryCandidate]
    public let learned: LearningContext
    /// Matches the search returned (after private notes were removed by the recall service).
    public let notesConsidered: Int
    /// Matches held back because the destination does not accept their source.
    public let notesWithheldBySource: Int
    /// Searching failed, so the request goes without notes. The UI must say so.
    public let notesSearchFailed: Bool

    /// Internal on purpose: outside DoddyCore a context can only come from `ContextAssembler`,
    /// so nothing reaches `AssistantService.answer` around the egress rules.
    init(
        notes: [MemoryCandidate], learned: LearningContext = .empty, notesConsidered: Int,
        notesWithheldBySource: Int, notesSearchFailed: Bool
    ) {
        self.notes = notes
        self.learned = learned
        self.notesConsidered = notesConsidered
        self.notesWithheldBySource = notesWithheldBySource
        self.notesSearchFailed = notesSearchFailed
    }

    /// Nothing from the user's data goes (notes switched off, or nothing asked for).
    public static let none = AssembledContext(notes: [], notesConsidered: 0, notesWithheldBySource: 0, notesSearchFailed: false)
}

/// Picks context per request from fresh search results: only notes that matched the request, only
/// sources the destination accepts, never more than its budget, never shortened. Notes are passed
/// on as data in their own field, never merged into the user's words.
public struct ContextAssembler: Sendable {
    private let recall: any RecallService
    private let recallLimit: Int

    /// - Parameter recall: should already hide private notes (`ShareableRecallService`, ADR-310).
    public init(recall: any RecallService, recallLimit: Int = 20) {
        self.recall = recall
        self.recallLimit = recallLimit
    }

    /// Throws only `.cancelled`. A failed search is reported in the result, not thrown: the
    /// request can still go, without notes, and the user is told.
    public func assemble(
        for question: String, includeNotes: Bool, target: EgressTarget
    ) async throws(AssistantError) -> AssembledContext {
        guard includeNotes else { return .none }
        let found: [MemoryCandidate]
        do {
            switch try await recall.recall(question, limit: recallLimit) {
            case .matches(let candidates): found = candidates
            case .noMatch: found = []
            }
        } catch is CancellationError {
            throw .cancelled
        } catch {
            return AssembledContext(notes: [], notesConsidered: 0, notesWithheldBySource: 0, notesSearchFailed: true)
        }
        if Task.isCancelled { throw .cancelled }
        return Self.select(found, for: target)
    }

    /// Pure selection over search results, for tests and for callers that already searched.
    public static func select(_ found: [MemoryCandidate], for target: EgressTarget) -> AssembledContext {
        let allowed = target.allowedNoteSources
        let accepted = found.filter { allowed.contains($0.record.source) }
        let withheld = found.count - accepted.count
        let notes = GroundingSelector.select(from: accepted, budget: target.notesBudget)
        return AssembledContext(
            notes: notes, learned: .empty, notesConsidered: found.count,
            notesWithheldBySource: withheld, notesSearchFailed: false)
    }
}
