import Foundation

/// Durable local storage for learned items. As with `MemoryRepository`, a returned record means
/// the write is committed and read back; nothing is reported saved on any other evidence.
public enum LearningStoreError: Error, Equatable, Sendable {
    case notFound(UUID)
    /// The write reported success but reading it back did not match. Treated as a failed save.
    case verificationFailed
    case corruptRecord(String)
    /// The text the user confirmed is not the text that was proposed. Nothing is stored.
    case textMismatch
    /// Only a `proposed` item can be confirmed or rejected.
    case notProposed(UUID)
    /// Only a `confirmed` item can be retired, revised or used; only a `retired` one revived.
    case wrongStatus(UUID, LearningStatus)
    /// A row with this evidence digest exists already.
    case duplicateEvidence
    /// A fact proposal was given to the procedure repository, or the other way round.
    case wrongProposalKind
}

public protocol LearnedFactRepository: Sendable {
    /// Stores the proposal as `proposed`. Only a `ValidatedProposal` is accepted.
    func propose(_ proposal: ValidatedProposal) async throws -> LearnedFact
    /// The user tapped Save on the card showing `exactText`. Confirms only if it is the stored
    /// text, byte for byte; sets the expiry for the kind; writes revision 1.
    func confirm(id: UUID, exactText: String) async throws -> LearnedFact
    /// "Never this": the row stays as `rejected`, so the evidence is never proposed again.
    func reject(id: UUID) async throws -> LearnedFact
    /// "That's wrong": kept, visible, out of retrieval.
    func retire(id: UUID) async throws -> LearnedFact
    /// Confirmed again after "still true?": a fresh expiry from `now`.
    func reconfirm(id: UUID) async throws -> LearnedFact
    /// The user edited the wording: a new confirmed revision; earlier wordings are kept.
    func revise(id: UUID, value: String) async throws -> LearnedFact
    func revisions(of id: UUID) async throws -> [LearnedFactRevision]
    func fact(id: UUID) async throws -> LearnedFact?
    /// Newest first. `nil` status returns everything.
    func list(status: LearningStatus?) async throws -> [LearnedFact]
    /// Confirmed, unexpired facts matching the query, best first. Scope is the assembler's job.
    func query(_ query: String, limit: Int) async throws -> [LearnedFact]
    /// Every evidence digest with a row, whatever its status.
    func knownDigests() async throws -> Set<String>
    /// Drops `proposed` rows older than the limit. Returns how many.
    func pruneProposals(olderThan: Date) async throws -> Int
    func delete(id: UUID) async throws
    func deleteAll() async throws
    /// JSON with provenance, for the Memory Wallet export.
    func export() async throws -> Data
}

public protocol ProcedureRepository: Sendable {
    func propose(_ proposal: ValidatedProposal) async throws -> Procedure
    /// The user tapped Save on the card showing `exactTrigger` and the steps.
    func confirm(id: UUID, exactTrigger: String) async throws -> Procedure
    func reject(id: UUID) async throws -> Procedure
    func retire(id: UUID) async throws -> Procedure
    func revive(id: UUID) async throws -> Procedure
    /// The user edited the trigger or the steps: version + 1, still confirmed.
    func update(id: UUID, triggerText: String, steps: [ProcedureStep]) async throws -> Procedure
    /// The plan card ran (whatever each step's outcome): `use_count` + 1, `last_used_at` = now.
    func markUsed(id: UUID) async throws -> Procedure
    func procedure(id: UUID) async throws -> Procedure?
    func list(status: LearningStatus?) async throws -> [Procedure]
    /// Confirmed procedures whose trigger matches the query, best first.
    func query(_ query: String, limit: Int) async throws -> [Procedure]
    /// Retires confirmed procedures unused since `before`. Returns the ones retired.
    func retireUnused(since before: Date) async throws -> [Procedure]
    func knownDigests() async throws -> Set<String>
    func pruneProposals(olderThan: Date) async throws -> Int
    func delete(id: UUID) async throws
    func deleteAll() async throws
    func export() async throws -> Data
}

public protocol OutcomeEventRepository: Sendable {
    func record(_ event: OutcomeEvent) async throws -> OutcomeEvent
    /// Oldest first, from `since`.
    func list(since: Date, limit: Int) async throws -> [OutcomeEvent]
    func count(kinds: Set<OutcomeKind>, since: Date) async throws -> Int
    /// Drops events older than `before` (the 90-day retention). Returns how many.
    func prune(olderThan before: Date) async throws -> Int
    func deleteAll() async throws
    func export() async throws -> Data
}

/// The one metric (design §6): corrections in the last seven days, computed on the iPhone.
public enum OutcomeMetrics {
    public static let week: TimeInterval = 7 * 86_400

    public static func corrections(in events: [OutcomeEvent], now: Date) -> Int {
        events.filter { OutcomeEvent.correctionKinds.contains($0.kind) && $0.createdAt > now.addingTimeInterval(-week) }.count
    }
}
