import Foundation

/// What the learning loop knows about this moment, supplied by the app (Settings, the state of
/// the connections). The service never reads Settings itself.
public struct LearningMoment: Sendable {
    public let learningOn: Bool
    public let connectionsPaused: Bool
    public let connectionsOn: Set<VoiceConnection>
    /// The conversation was private or a translator conversation: nothing is proposed.
    public let isPrivate: Bool
    /// The character router's sensitive mode. The app has no such router yet, so this is `false`
    /// until one exists; the content filter still applies.
    public let sensitiveMode: Bool
    /// The iPhone's language is Polish: a suggested routine name is made in Polish.
    public let polish: Bool

    public init(
        learningOn: Bool, connectionsPaused: Bool, connectionsOn: Set<VoiceConnection>, isPrivate: Bool,
        sensitiveMode: Bool = false, polish: Bool = false
    ) {
        self.polish = polish
        self.learningOn = learningOn
        self.connectionsPaused = connectionsPaused
        self.connectionsOn = connectionsOn
        self.isPrivate = isPrivate
        self.sensitiveMode = sensitiveMode
    }

    var environment: LearningEnvironment {
        let on = connectionsOn
        return LearningEnvironment(connectionsPaused: connectionsPaused, sensitiveMode: sensitiveMode) { tool in
            // Notes and online-account tools have no connection switch here; the plan card
            // checks an online account when it is shown.
            VoiceConnection.serving(tool).map(on.contains) ?? true
        }
    }
}

/// One card to show: the stored row, still `proposed`.
public enum LearningCardItem: Equatable, Sendable, Identifiable {
    case fact(LearnedFact)
    case procedure(Procedure)

    public var id: UUID {
        switch self {
        case .fact(let fact): fact.id
        case .procedure(let procedure): procedure.id
        }
    }

    /// The text the user confirms word for word.
    public var shownText: String {
        switch self {
        case .fact(let fact): fact.value
        case .procedure(let procedure): procedure.triggerText
        }
    }
}

public struct LearningMetrics: Equatable, Sendable {
    /// Undo, changed steps, "that's wrong", redone, cancelled — the last seven days.
    public let correctionsThisWeek: Int
    public let gaps: [CapabilityGapCategory: Int]
    public let proceduresUsedThisWeek: Int

    public static let empty = LearningMetrics(correctionsThisWeek: 0, gaps: [:], proceduresUsedThisWeek: 0)
}

/// The learning loop's orchestration, apart from any screen (ADR-440): what gets recorded from
/// "What Doddy did", what is proposed when a conversation ends, what the voice agent is told,
/// and what "That's wrong" and delete do. Every claim that something was saved or removed comes
/// from a repository result that was read back.
public struct LearningService: Sendable {
    public let facts: any LearnedFactRepository
    public let procedures: any ProcedureRepository
    public let outcomes: any OutcomeEventRepository
    public let limits: LearningLimits
    private let now: @Sendable () -> Date
    private let calendar: Calendar

    public init(
        facts: any LearnedFactRepository, procedures: any ProcedureRepository, outcomes: any OutcomeEventRepository,
        limits: LearningLimits = .standard, now: @escaping @Sendable () -> Date = Date.init, calendar: Calendar = .current
    ) {
        self.facts = facts
        self.procedures = procedures
        self.outcomes = outcomes
        self.limits = limits
        self.now = now
        self.calendar = calendar
    }

    // MARK: Outcomes

    /// Writes the outcome events an activity entry implies. Failures are returned, never hidden.
    @discardableResult
    public func recordActivity(
        _ entry: ActivityEntry, previous: ActivityEntry?, recent: [ActivityEntry], sessionID: String?
    ) async -> [LearningStoreError] {
        var failures: [LearningStoreError] = []
        for event in OutcomeRecorder.events(for: entry, previous: previous, recent: recent, sessionID: sessionID, now: now()) {
            do { _ = try await outcomes.record(event) } catch { failures.append(Self.storeError(error)) }
        }
        return failures
    }

    /// Tool call ids come from the voice service; anything outside letters, digits and `_-.` becomes `_`.
    static func safeID(_ id: String) -> String {
        let mapped = String(id.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) || "_-.".unicodeScalars.contains(scalar) ? Character(scalar) : "_"
        }.prefix(80))
        return mapped.isEmpty ? "unknown" : mapped
    }

    public func recordGap(_ category: CapabilityGapCategory, requestID: String, sessionID: String?) async throws {
        let event = try OutcomeEvent(
            requestID: Self.safeID(requestID), kind: .capabilityGap,
            detail: try OutcomeDetail(gapCategory: category, sessionID: sessionID), createdAt: now())
        _ = try await outcomes.record(event)
    }

    /// A step changed on the plan card before it ran.
    public func recordChangedStep(tool: String, requestID: String, sessionID: String?) async throws {
        let event = try OutcomeEvent(
            requestID: Self.safeID(requestID), kind: .corrected,
            detail: try OutcomeDetail(toolName: tool, correction: .changedStep, sessionID: sessionID), createdAt: now())
        _ = try await outcomes.record(event)
    }

    public func metrics() async throws -> LearningMetrics {
        let current = now()
        let weekAgo = current.addingTimeInterval(-OutcomeMetrics.week)
        let corrections = try await outcomes.count(kinds: OutcomeEvent.correctionKinds, since: weekAgo)
        let recent = try await outcomes.list(since: current.addingTimeInterval(-Double(limits.outcomeRetentionDays) * 86_400), limit: 5_000)
        var gaps: [CapabilityGapCategory: Int] = [:]
        for event in recent where event.kind == .capabilityGap {
            if let category = event.detail.gapCategory { gaps[category, default: 0] += 1 }
        }
        let used = try await procedures.list(status: .confirmed).filter { ($0.lastUsedAt ?? .distantPast) > weekAgo }.count
        return LearningMetrics(correctionsThisWeek: corrections, gaps: gaps, proceduresUsedThisWeek: used)
    }

    // MARK: Housekeeping

    /// Drops unanswered proposals after their limit, retires procedures unused for 90 days, and
    /// deletes outcome events past their retention. Returns what was retired, for the screen.
    @discardableResult
    public func housekeeping() async throws -> [Procedure] {
        let current = now()
        _ = try await facts.pruneProposals(olderThan: current.addingTimeInterval(-Double(limits.proposalExpiryDays) * 86_400))
        _ = try await procedures.pruneProposals(olderThan: current.addingTimeInterval(-Double(limits.proposalExpiryDays) * 86_400))
        _ = try await outcomes.prune(olderThan: current.addingTimeInterval(-Double(limits.outcomeRetentionDays) * 86_400))
        return try await procedures.retireUnused(since: current.addingTimeInterval(-Double(limits.procedureRetirementDays) * 86_400))
    }

    // MARK: Proposals

    /// After a conversation ends: at most one card. A repeated tool sequence first (rarer), else
    /// a preference or personal fact from sentences the "Worth keeping?" card did not already
    /// offer. Nothing is proposed when learning is off, the conversation was private, the
    /// connections are paused, or today's cap is used.
    public func proposeAfterConversation(
        leftoverSuggestions: [SaveSuggestion], moment: LearningMoment
    ) async throws -> [LearningCardItem] {
        guard moment.learningOn, !moment.isPrivate else { return [] }
        let current = now()
        let environment = moment.environment
        let shownToday = try await rowsCreatedToday(current)
        let counts = ProposalCounts(shownToday: shownToday, shownThisConversation: 0)
        guard shownToday < limits.proposalsPerDay else { return [] }

        let known = try await facts.knownDigests().union(procedures.knownDigests())
        var candidates: [LearningProposal] = []
        let since = current.addingTimeInterval(-Double(ProcedureDetector.windowDays) * 86_400)
        let events = try await outcomes.list(since: since, limit: 5_000)
        let sequences = Set(try await procedures.list(status: nil).map { $0.steps.map(\.toolName) })
        candidates += ProcedureDetector.detect(
            events: events, knownDigests: known, existingSequences: sequences, now: current, calendar: calendar,
            polish: moment.polish)
        if let fact = FactProposer.propose(from: leftoverSuggestions, savedTexts: [], date: current) { candidates.append(fact) }

        for candidate in candidates {
            let validated: ValidatedProposal
            do {
                validated = try LearningPolicy.validate(
                    candidate, environment: environment, counts: counts, knownDigests: known, limits: limits, now: current)
            } catch {
                continue // dropped: not shown, not stored
            }
            switch candidate {
            case .fact: return [.fact(try await facts.propose(validated))]
            case .procedure: return [.procedure(try await procedures.propose(validated))]
            }
        }
        return []
    }

    private func rowsCreatedToday(_ current: Date) async throws -> Int {
        let start = calendar.startOfDay(for: current)
        let factRows = try await facts.list(status: nil).filter { $0.createdAt >= start }.count
        let procedureRows = try await procedures.list(status: nil).filter { $0.createdAt >= start }.count
        return factRows + procedureRows
    }

    // MARK: Answers on a card, and "That's wrong"

    /// Save on the card: confirmed only for the exact text shown, and reported only from the read-back row.
    public func confirm(_ item: LearningCardItem) async throws -> LearningCardItem {
        switch item {
        case .fact(let fact): .fact(try await facts.confirm(id: fact.id, exactText: fact.value))
        case .procedure(let procedure): .procedure(try await procedures.confirm(id: procedure.id, exactTrigger: procedure.triggerText))
        }
    }

    /// "Never this".
    public func reject(_ item: LearningCardItem) async throws {
        switch item {
        case .fact(let fact): _ = try await facts.reject(id: fact.id)
        case .procedure(let procedure): _ = try await procedures.reject(id: procedure.id)
        }
    }

    /// "That's wrong": retired (kept, visible, out of use), then counted as a correction. The
    /// correction is written only after the retirement was read back.
    public func thatsWrong(fact: LearnedFact) async throws {
        _ = try await facts.retire(id: fact.id)
        try await recordWrong(id: fact.id)
    }

    public func thatsWrong(procedure: Procedure) async throws {
        _ = try await procedures.retire(id: procedure.id)
        try await recordWrong(id: procedure.id)
    }

    private func recordWrong(id: UUID) async throws {
        let event = try OutcomeEvent(
            requestID: id.uuidString, kind: .corrected,
            detail: try OutcomeDetail(correction: .thatsWrong, learnedItemID: id), createdAt: now())
        _ = try await outcomes.record(event)
    }

    // MARK: The voice agent

    /// The text for `{{learned_context}}`. Without the user's switch the agent gets `notShared`
    /// and nothing is read.
    public func voiceContext(shared: Bool, connectionsOn: Set<VoiceConnection>, connectionsPaused: Bool) async throws -> String {
        guard shared else { return LearningPrompt.notShared }
        let current = now()
        let context = LearningContextAssembler.assemble(
            facts: try await facts.list(status: .confirmed), procedures: try await procedures.list(status: .confirmed),
            connectionsOn: connectionsOn, connectionsPaused: connectionsPaused, now: current, budget: LearningPrompt.voiceBudget)
        return LearningPrompt.render(context, shared: true)
    }

    /// A plan card ran with exactly these tools in this order: the confirmed procedure with that
    /// sequence, if any, counts as used. Returns it when it was marked (read back).
    public func planRan(tools: [String]) async throws -> Procedure? {
        guard let match = try await procedures.list(status: .confirmed).first(where: { $0.steps.map(\.toolName) == tools }) else { return nil }
        return try await procedures.markUsed(id: match.id)
    }

    // MARK: Delete

    /// Everything learned and every outcome event. Each table is emptied and read back.
    public func deleteAll() async throws {
        try await facts.deleteAll()
        try await procedures.deleteAll()
        try await outcomes.deleteAll()
        let left = try await facts.list(status: nil).count + procedures.list(status: nil).count
            + outcomes.list(since: .distantPast, limit: 1).count
        guard left == 0 else { throw LearningStoreError.verificationFailed }
    }

    static func storeError(_ error: any Error) -> LearningStoreError {
        error as? LearningStoreError ?? .verificationFailed
    }
}
