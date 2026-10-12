import Foundation

// DODDY Brain, Phase 1 (docs/architecture/brain/01_BRAIN_ARCHITECTURE.md, ADR-442): a narrow,
// provider-independent coordination boundary for one request. It decides the route in typed code,
// assembles context under the destination's egress rules, calls the reasoning step and returns
// the verified outcome with a content-free trace. It owns no state, no tools and no prompts.
//
// Phase 1 covers typed questions (Ask Doddy). Voice keeps its own transport and tool dispatch in
// VoiceSessionController until a later phase moves one workflow at a time behind this boundary.

/// Which surface a request came from. Only typed questions run through the brain so far.
public enum BrainChannel: String, Equatable, Sendable {
    case typed
}

public struct BrainRequest: Equatable, Sendable {
    public let text: String
    public let sessionID: UUID
    /// Earlier turns of the same chat, in memory only.
    public let history: [ConversationTurn]
    /// BCP 47 language code, e.g. "en" or "pl".
    public let locale: String
    public let channel: BrainChannel

    public init(
        text: String, sessionID: UUID, history: [ConversationTurn] = [], locale: String = "en",
        channel: BrainChannel = .typed
    ) {
        self.text = text
        self.sessionID = sessionID
        self.history = history
        self.locale = locale
        self.channel = channel
    }
}

/// The decision made before anything is searched or sent.
public enum BrainRoute: Equatable, Sendable {
    /// Nothing is searched and nothing leaves the device; the error says why, in plain words.
    case refused(AssistantError)
    /// Ask the reasoning provider, with matching notes only when the user allowed them.
    case assistant(includeNotes: Bool)
}

/// What happened, without any of the user's words: counts and decisions only, so it can be kept
/// for evaluation (brain/10_TESTING_AND_EVALUATIONS.md) without becoming a copy of the chat.
public struct BrainTrace: Equatable, Sendable {
    public var route: BrainRoute
    /// Notes the search returned (private notes already removed).
    public var notesConsidered = 0
    /// Notes that actually left the device.
    public var notesSent = 0
    /// Matches held back because the destination does not accept their source.
    public var notesWithheldBySource = 0
    public var notesSearchFailed = false
    /// Learned facts and routines that left the device (none on the typed path yet).
    public var learnedItemsSent = 0
    /// The request reached the reasoning provider (the network), whatever the result.
    public var providerCalled = false
    /// Tools proposed or run. Typed questions have none; kept so evaluations can assert it.
    public var toolCalls = 0

    public init(route: BrainRoute) { self.route = route }
}

public struct BrainOutcome: Sendable {
    public let result: Result<AssistantAnswer, AssistantError>
    public let trace: BrainTrace
}

/// request → route → context → reasoning → citation check → outcome.
public struct BrainCoordinator: Sendable {
    private let assistant: AssistantService

    public init(assistant: AssistantService) {
        self.assistant = assistant
    }

    /// Pure: the same request and policy always take the same route. Consent and input checks
    /// come first, so a refused request never searches notes or reaches the network.
    public static func route(_ request: BrainRequest, policy: AssistantPolicy) -> BrainRoute {
        do throws(AssistantError) {
            try AssistantService.validate(request.text, policy: policy)
        } catch {
            return .refused(error)
        }
        return .assistant(includeNotes: policy.includeNotes)
    }

    public func respond(_ request: BrainRequest, policy: AssistantPolicy) async -> BrainOutcome {
        let route = Self.route(request, policy: policy)
        var trace = BrainTrace(route: route)
        let includeNotes: Bool
        switch route {
        case .refused(let error): return BrainOutcome(result: .failure(error), trace: trace)
        case .assistant(let notes): includeNotes = notes
        }
        if Task.isCancelled { return BrainOutcome(result: .failure(.cancelled), trace: trace) }

        let context: AssembledContext
        do throws(AssistantError) {
            context = try await assistant.context.assemble(for: request.text, includeNotes: includeNotes, target: .assistantGateway)
        } catch {
            return BrainOutcome(result: .failure(error), trace: trace)
        }
        trace.notesConsidered = context.notesConsidered
        trace.notesSent = context.notes.count
        trace.notesWithheldBySource = context.notesWithheldBySource
        trace.notesSearchFailed = context.notesSearchFailed
        trace.learnedItemsSent = context.learned.facts.count + context.learned.procedures.count
        if Task.isCancelled { return BrainOutcome(result: .failure(.cancelled), trace: trace) }

        trace.providerCalled = true
        do throws(AssistantError) {
            let answer = try await assistant.answer(
                request.text, context: context, sessionID: request.sessionID, history: request.history, locale: request.locale)
            return BrainOutcome(result: .success(answer), trace: trace)
        } catch {
            return BrainOutcome(result: .failure(error), trace: trace)
        }
    }
}
