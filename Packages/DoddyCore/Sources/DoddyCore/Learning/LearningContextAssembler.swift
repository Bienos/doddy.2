import Foundation

/// How much learned context one request may carry, on top of the note budget
/// (`GroundingBudget`): a learned item can never push out a cited note (design §5).
public struct LearningBudget: Equatable, Sendable {
    public let maxFacts: Int
    public let maxProcedures: Int
    public let maxTotalScalars: Int

    public init(maxFacts: Int = 3, maxProcedures: Int = 1, maxTotalScalars: Int = 1_500) {
        self.maxFacts = maxFacts
        self.maxProcedures = maxProcedures
        self.maxTotalScalars = maxTotalScalars
    }

    public static let standard = LearningBudget()
}

/// What the assembler chose: records and their ids, so a reply's citations can be checked
/// against exactly what was sent, as `CitationVerifier` does for notes.
public struct LearningContext: Equatable, Sendable {
    public let facts: [LearnedFact]
    public let procedures: [Procedure]

    public var factIDs: Set<UUID> { Set(facts.map(\.id)) }
    public var procedureIDs: Set<UUID> { Set(procedures.map(\.id)) }
    public var isEmpty: Bool { facts.isEmpty && procedures.isEmpty }

    public static let empty = LearningContext(facts: [], procedures: [])
}

/// Picks, per request and from fresh repository results, the confirmed items the assistant may
/// see: only unexpired, only in scope (general, or a connection that is on), never shortened,
/// under the budget. With connections paused no procedure and no connection-scoped fact goes.
/// Two facts that contradict each other are both returned, each with its own provenance:
/// recency is not a truth proof (MEMORY_AND_DATA.md).
public enum LearningContextAssembler {
    public static func assemble(
        facts: [LearnedFact], procedures: [Procedure], connectionsOn: Set<VoiceConnection>,
        connectionsPaused: Bool, now: Date, budget: LearningBudget = .standard
    ) -> LearningContext {
        var total = 0
        var chosenFacts: [LearnedFact] = []
        var seen = Set<UUID>()
        for fact in facts {
            if chosenFacts.count == budget.maxFacts { break }
            guard fact.isRetrievable(at: now), inScope(fact.scope, connectionsOn: connectionsOn, paused: connectionsPaused),
                  !seen.contains(fact.id)
            else { continue }
            let size = fact.value.unicodeScalars.count
            guard total + size <= budget.maxTotalScalars else { continue } // skip, try smaller ones
            seen.insert(fact.id)
            total += size
            chosenFacts.append(fact)
        }
        var chosenProcedures: [Procedure] = []
        if !connectionsPaused {
            for procedure in procedures {
                if chosenProcedures.count == budget.maxProcedures { break }
                guard procedure.isRetrievable(at: now),
                      inScope(procedure.scope, connectionsOn: connectionsOn, paused: false),
                      procedure.steps.allSatisfy({ $0.connection.map(connectionsOn.contains) ?? true }),
                      !seen.contains(procedure.id)
                else { continue }
                let size = procedure.triggerText.unicodeScalars.count
                guard total + size <= budget.maxTotalScalars else { continue }
                seen.insert(procedure.id)
                total += size
                chosenProcedures.append(procedure)
            }
        }
        return LearningContext(facts: chosenFacts, procedures: chosenProcedures)
    }

    static func inScope(_ scope: LearningScope, connectionsOn: Set<VoiceConnection>, paused: Bool) -> Bool {
        switch scope {
        case .general: true
        case .connection(let connection): !paused && connectionsOn.contains(connection)
        }
    }
}
