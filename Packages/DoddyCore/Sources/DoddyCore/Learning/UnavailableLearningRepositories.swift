import Foundation

// Explicit stand-ins when the memory store is not open (the M0 pattern): every call says so.

public struct UnavailableLearnedFactRepository: LearnedFactRepository {
    public init() {}
    public func propose(_ proposal: ValidatedProposal) async throws -> LearnedFact { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func confirm(id: UUID, exactText: String) async throws -> LearnedFact { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func reject(id: UUID) async throws -> LearnedFact { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func retire(id: UUID) async throws -> LearnedFact { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func reconfirm(id: UUID) async throws -> LearnedFact { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func revise(id: UUID, value: String) async throws -> LearnedFact { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func revisions(of id: UUID) async throws -> [LearnedFactRevision] { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func fact(id: UUID) async throws -> LearnedFact? { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func list(status: LearningStatus?) async throws -> [LearnedFact] { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func query(_ query: String, limit: Int) async throws -> [LearnedFact] { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func knownDigests() async throws -> Set<String> { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func pruneProposals(olderThan: Date) async throws -> Int { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func delete(id: UUID) async throws { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func deleteAll() async throws { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func export() async throws -> Data { throw DoddyError.capabilityUnavailable(.memoryStorage) }
}

public struct UnavailableProcedureRepository: ProcedureRepository {
    public init() {}
    public func propose(_ proposal: ValidatedProposal) async throws -> Procedure { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func confirm(id: UUID, exactTrigger: String) async throws -> Procedure { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func reject(id: UUID) async throws -> Procedure { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func retire(id: UUID) async throws -> Procedure { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func revive(id: UUID) async throws -> Procedure { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func update(id: UUID, triggerText: String, steps: [ProcedureStep]) async throws -> Procedure { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func markUsed(id: UUID) async throws -> Procedure { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func procedure(id: UUID) async throws -> Procedure? { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func list(status: LearningStatus?) async throws -> [Procedure] { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func query(_ query: String, limit: Int) async throws -> [Procedure] { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func retireUnused(since before: Date) async throws -> [Procedure] { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func knownDigests() async throws -> Set<String> { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func pruneProposals(olderThan: Date) async throws -> Int { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func delete(id: UUID) async throws { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func deleteAll() async throws { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func export() async throws -> Data { throw DoddyError.capabilityUnavailable(.memoryStorage) }
}

public struct UnavailableOutcomeEventRepository: OutcomeEventRepository {
    public init() {}
    public func record(_ event: OutcomeEvent) async throws -> OutcomeEvent { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func list(since: Date, limit: Int) async throws -> [OutcomeEvent] { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func count(kinds: Set<OutcomeKind>, since: Date) async throws -> Int { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func prune(olderThan before: Date) async throws -> Int { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func deleteAll() async throws { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func export() async throws -> Data { throw DoddyError.capabilityUnavailable(.memoryStorage) }
}
