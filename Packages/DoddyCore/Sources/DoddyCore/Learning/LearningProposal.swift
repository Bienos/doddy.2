import Foundation

// A proposer (a rule on the iPhone, later a model through `AssistantClient`) hands over JSON.
// It is parsed strictly into these structs: every key must be known, so a proposal cannot
// smuggle in an approval, a tier, a status or a confirmation. Who proposed is told by the
// caller, never by the JSON.

public struct FactProposal: Equatable, Sendable {
    public let kind: LearnedFactKind
    public let value: String
    public let scope: LearningScope
    public let confidence: Int
    public let provenance: LearningProvenance
    public let sourceEpisodeIDs: [String]

    public init(
        kind: LearnedFactKind, value: String, scope: LearningScope = .general, confidence: Int,
        provenance: LearningProvenance, sourceEpisodeIDs: [String]
    ) throws(LearningValidationError) {
        guard (0...100).contains(confidence) else { throw .confidenceOutOfRange(confidence) }
        self.kind = kind
        self.value = try LearningText.validated(value, field: "value", maximum: LearnedFact.maxValueLength)
        self.scope = scope
        self.confidence = confidence
        self.provenance = provenance
        self.sourceEpisodeIDs = try LearningText.episodeIDs(sourceEpisodeIDs)
    }
}

public struct ProcedureProposal: Equatable, Sendable {
    public let triggerText: String
    public let steps: [ProcedureStep]
    public let scope: LearningScope
    public let provenance: LearningProvenance
    public let sourceEpisodeIDs: [String]

    public init(
        triggerText: String, steps: [ProcedureStep], scope: LearningScope = .general,
        provenance: LearningProvenance, sourceEpisodeIDs: [String]
    ) throws(LearningValidationError) {
        guard !steps.isEmpty else { throw .noSteps }
        guard steps.count <= Procedure.maxSteps else { throw .tooManySteps(steps.count) }
        guard steps.map(\.number) == Array(1...steps.count) else { throw .stepNumbering }
        self.triggerText = try LearningText.validated(triggerText, field: "trigger_text", maximum: Procedure.maxTriggerLength)
        self.steps = steps
        self.scope = scope
        self.provenance = provenance
        self.sourceEpisodeIDs = try LearningText.episodeIDs(sourceEpisodeIDs)
    }
}

public enum LearningProposal: Equatable, Sendable {
    case fact(FactProposal)
    case procedure(ProcedureProposal)

    public var sourceEpisodeIDs: [String] {
        switch self {
        case .fact(let fact): fact.sourceEpisodeIDs
        case .procedure(let procedure): procedure.sourceEpisodeIDs
        }
    }

    public var scope: LearningScope {
        switch self {
        case .fact(let fact): fact.scope
        case .procedure(let procedure): procedure.scope
        }
    }

    public var provenance: LearningProvenance {
        switch self {
        case .fact(let fact): fact.provenance
        case .procedure(let procedure): procedure.provenance
        }
    }

    public var evidenceDigest: String { EvidenceDigest.compute(sourceEpisodeIDs) }

    /// The text the card will show and the user confirms word for word.
    public var shownText: String {
        switch self {
        case .fact(let fact): fact.value
        case .procedure(let procedure): procedure.triggerText
        }
    }
}

public enum LearningProposalError: Error, Equatable, Sendable {
    /// Not the contract: wrong JSON, a missing field, a wrong type.
    case malformed(String)
    /// A key the contract doesn't have ("approval", "status", "confirmed"...). Refused, not ignored.
    case unexpectedKey(String)
    case invalid(LearningValidationError)
    /// Matches the never-learned list (design §6). Not shown; the user can still save a note by hand.
    case sensitive
    /// The step's connection or online account is off, so the procedure can't run today.
    case toolOff(String)
    /// Settings → Pause all connections.
    case paused
    /// The conversation is in the sensitive mode of the character router.
    case sensitiveMode
    case overDailyCap
    case overConversationCap
    /// A row with this evidence digest exists already (proposed, confirmed, retired or "never this").
    case rejectedBefore
}

extension LearningProposal {
    static let factKeys: Set<String> = ["type", "kind", "value", "scope", "confidence", "reason", "source_episode_ids", "episode_dates_ms"]
    static let procedureKeys: Set<String> = ["type", "trigger_text", "scope", "reason", "source_episode_ids", "episode_dates_ms", "steps"]
    static let stepKeys: Set<String> = ["number", "tool", "fixed", "asked"]

    /// Strict parse. `proposer` is who the caller ran, not a field of the JSON.
    ///
    /// Fact: `{"type":"fact","kind":"preference","value":"…","scope":"general","confidence":80,
    ///        "reason":"preference","source_episode_ids":["…"],"episode_dates_ms":[…]}`
    /// Procedure: `{"type":"procedure","trigger_text":"…","scope":"general","reason":"repeated_sequence",
    ///        "source_episode_ids":["…"],"episode_dates_ms":[…],
    ///        "steps":[{"number":1,"tool":"create_reminder","fixed":{"list":"Home"},"asked":["title","due"]}]}`
    public static func parse(_ data: Data, proposer: LearningProposer) throws(LearningProposalError) -> LearningProposal {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw .malformed("not a JSON object")
        }
        guard let type = object["type"] as? String else { throw .malformed("type") }
        switch type {
        case "fact":
            try checkKeys(object, allowed: factKeys)
            guard let kindRaw = object["kind"] as? String, let kind = LearnedFactKind(rawValue: kindRaw) else { throw .malformed("kind") }
            guard let value = object["value"] as? String else { throw .malformed("value") }
            guard let confidence = object["confidence"] as? Int else { throw .malformed("confidence") }
            let fact: FactProposal
            do {
                fact = try FactProposal(
                    kind: kind, value: value, scope: try scope(object), confidence: confidence,
                    provenance: try provenance(object, proposer: proposer), sourceEpisodeIDs: try episodeIDs(object))
            } catch let error as LearningValidationError {
                throw .invalid(error)
            } catch let error as LearningProposalError {
                throw error
            } catch {
                throw .malformed("fact")
            }
            return .fact(fact)
        case "procedure":
            try checkKeys(object, allowed: procedureKeys)
            guard let trigger = object["trigger_text"] as? String else { throw .malformed("trigger_text") }
            guard let rawSteps = object["steps"] as? [Any] else { throw .malformed("steps") }
            var steps: [ProcedureStep] = []
            for raw in rawSteps {
                guard let step = raw as? [String: Any] else { throw .malformed("steps") }
                try checkKeys(step, allowed: stepKeys)
                guard let number = step["number"] as? Int, let tool = step["tool"] as? String else { throw .malformed("step") }
                let fixed = step["fixed"] as? [String: Any] ?? [:]
                var fixedStrings: [String: String] = [:]
                for (name, value) in fixed {
                    // Scalars only; nested objects, arrays and null are not parameters.
                    switch value {
                    case let string as String: fixedStrings[name] = string
                    case let number as NSNumber: fixedStrings[name] = number.stringValue
                    default: throw .malformed("fixed.\(name)")
                    }
                }
                let asked = step["asked"] as? [String] ?? (step["asked"] == nil ? [] : nil)
                guard let asked else { throw .malformed("asked") }
                do {
                    steps.append(try ProcedureStep(number: number, toolName: tool, fixed: fixedStrings, asked: asked))
                } catch {
                    throw .invalid(error)
                }
            }
            let procedure: ProcedureProposal
            do {
                procedure = try ProcedureProposal(
                    triggerText: trigger, steps: steps, scope: try scope(object),
                    provenance: try provenance(object, proposer: proposer), sourceEpisodeIDs: try episodeIDs(object))
            } catch let error as LearningValidationError {
                throw .invalid(error)
            } catch let error as LearningProposalError {
                throw error
            } catch {
                throw .malformed("procedure")
            }
            return .procedure(procedure)
        default:
            throw .malformed("type \(type)")
        }
    }

    private static func checkKeys(_ object: [String: Any], allowed: Set<String>) throws(LearningProposalError) {
        if let stray = object.keys.sorted().first(where: { !allowed.contains($0) }) { throw .unexpectedKey(stray) }
    }

    private static func scope(_ object: [String: Any]) throws(LearningProposalError) -> LearningScope {
        guard let raw = object["scope"] else { return .general }
        guard let string = raw as? String, let scope = LearningScope(rawValue: string) else { throw .malformed("scope") }
        return scope
    }

    private static func episodeIDs(_ object: [String: Any]) throws(LearningProposalError) -> [String] {
        guard let ids = object["source_episode_ids"] as? [String] else { throw .malformed("source_episode_ids") }
        return ids
    }

    private static func provenance(_ object: [String: Any], proposer: LearningProposer) throws(LearningProposalError) -> LearningProvenance {
        guard let reason = object["reason"] as? String else { throw .malformed("reason") }
        guard let dates = object["episode_dates_ms"] as? [NSNumber] else { throw .malformed("episode_dates_ms") }
        do {
            return try LearningProvenance(
                proposer: proposer, reason: reason,
                episodeDates: dates.map { Date(timeIntervalSince1970: $0.doubleValue / 1000) })
        } catch {
            throw .invalid(error)
        }
    }
}
