import Foundation

/// What the user has agreed to, read fresh for every question.
public struct AssistantPolicy: Equatable, Sendable {
    /// The user turned on Ask Doddy knowing questions go to a server and then to the model provider.
    public let consentGranted: Bool
    /// Relevant saved notes may be sent along. Off means nothing from the notes leaves the device.
    public let includeNotes: Bool

    public init(consentGranted: Bool, includeNotes: Bool) {
        self.consentGranted = consentGranted
        self.includeNotes = includeNotes
    }
}

public struct AssistantAnswer: Equatable, Sendable {
    public let answer: VerifiedAnswer
    /// How many saved notes left the device with this question (they are shown to the user).
    public let notesSent: [MemoryRecord]
    /// Searching notes failed, so the question went without them. The UI must say so.
    public let notesSearchFailed: Bool
    /// Matching notes held back because the gateway does not accept their source (e.g. imported
    /// files, ADR-442). A count only; the notes themselves stay on the device.
    public var notesWithheld: Int = 0
}

public enum AssistantLimits {
    public static let maxQuestionLength = 2_000
    public static let maxTurns = 6
}

/// context -> gateway -> citation check. Stateless: the chat lives in the UI, in memory.
/// `ask` runs through `BrainCoordinator` (ADR-442); `answer` is the reasoning step on its own.
public struct AssistantService: Sendable {
    /// Chooses what may leave the device with a question (ADR-442).
    public let context: ContextAssembler
    private let client: any AssistantClient
    private let sleep: @Sendable (Duration) async throws -> Void
    private let backoff: [Duration]

    /// - Parameter backoff: waits between automatic retries of transient failures (so at most `backoff.count + 1` tries).
    public init(
        recall: any RecallService,
        client: any AssistantClient,
        backoff: [Duration] = [.milliseconds(500), .milliseconds(1500)],
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.context = ContextAssembler(recall: recall)
        self.client = client
        self.backoff = backoff
        self.sleep = sleep
    }

    public func ask(
        _ question: String,
        sessionID: UUID,
        history: [ConversationTurn] = [],
        locale: String = "en",
        policy: AssistantPolicy
    ) async throws(AssistantError) -> AssistantAnswer {
        let request = BrainRequest(text: question, sessionID: sessionID, history: history, locale: locale)
        return try await BrainCoordinator(assistant: self).respond(request, policy: policy).result.get()
    }

    /// Checked before anything is searched or sent.
    static func validate(_ question: String, policy: AssistantPolicy) throws(AssistantError) {
        guard policy.consentGranted else { throw .consentRequired }
        guard !question.allSatisfy(\.isWhitespace),
              question.unicodeScalars.count <= AssistantLimits.maxQuestionLength
        else { throw .invalidRequest }
    }

    /// Sends one question with already assembled context and checks the reply's citations against
    /// exactly what was sent. Retries only transient failures.
    public func answer(
        _ question: String,
        context: AssembledContext,
        sessionID: UUID,
        history: [ConversationTurn] = [],
        locale: String = "en"
    ) async throws(AssistantError) -> AssistantAnswer {
        let request = AssistantRequest(
            sessionID: sessionID,
            userText: question,
            groundingMemories: context.notes,
            recentTurns: Self.prepare(history),
            locale: Self.safeLocale(locale))

        let reply = try await send(request)
        let verified = try CitationVerifier.verify(reply, for: request)
        return AssistantAnswer(
            answer: verified, notesSent: context.notes.map(\.record), notesSearchFailed: context.notesSearchFailed,
            notesWithheld: context.notesWithheldBySource)
    }

    private func send(_ request: AssistantRequest) async throws(AssistantError) -> AssistantReply {
        var attempt = 0
        while true {
            if Task.isCancelled { throw .cancelled }
            do {
                return try await client.respond(request)
            } catch {
                let mapped = Self.map(error)
                guard mapped.isTransient, attempt < backoff.count else { throw mapped }
                do { try await sleep(backoff[attempt]) } catch { throw .cancelled }
                attempt += 1
            }
        }
    }

    static func map(_ error: any Error) -> AssistantError {
        if let error = error as? AssistantError { return error }
        if error is CancellationError { return .cancelled }
        if let error = error as? DoddyError, case .capabilityUnavailable = error { return .notConfigured }
        return .providerUnavailable
    }

    /// Last few non-blank turns, each cut to the question limit (chat text, unlike notes, may be shortened).
    static func prepare(_ history: [ConversationTurn]) -> [ConversationTurn] {
        history
            .filter { !$0.text.allSatisfy(\.isWhitespace) }
            .suffix(AssistantLimits.maxTurns)
            .map { turn in
                let scalars = turn.text.unicodeScalars
                guard scalars.count > AssistantLimits.maxQuestionLength else { return turn }
                var cut = String.UnicodeScalarView()
                cut.append(contentsOf: scalars.prefix(AssistantLimits.maxQuestionLength))
                return ConversationTurn(role: turn.role, text: String(cut))
            }
    }

    /// The gateway accepts only plain language tags like "en" or "pl-PL".
    static func safeLocale(_ locale: String) -> String {
        let parts = locale.split(separator: "-", omittingEmptySubsequences: false)
        guard let language = parts.first, (2...3).contains(language.count),
              language.allSatisfy({ $0.isASCII && $0.isLowercase && $0.isLetter }),
              parts.count <= 2,
              parts.dropFirst().allSatisfy({ (2...8).contains($0.count) && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) } })
        else { return "en" }
        return locale
    }
}
