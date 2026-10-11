import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

// Learning loop (ADR-324, docs/architecture/LEARNING_LOOP.md). Everything Doddy learns about its
// one user is data: proposed by a rule or a model, validated by these types, confirmed by the
// user on a card, stored with provenance, visible, revertible. Nothing here is an instruction:
// a stored row changes no permission, approval or risk tier.

public enum LearnedFactKind: String, CaseIterable, Codable, Sendable {
    case preference, fact, routine, person, place

    /// Days after confirmation when the fact stops being retrieved and is shown as "still
    /// true?" (design §6). `nil`: no expiry, reviewed after `reviewAfterDays`.
    public var expiryDays: Int? {
        switch self {
        case .preference: 365
        case .routine: 180
        case .fact, .person, .place: nil
        }
    }

    public static let reviewAfterDays = 365
}

/// Where a learned item may be used: everywhere, or only while one connection is on.
public enum LearningScope: Hashable, Sendable {
    case general
    case connection(VoiceConnection)

    public static let generalRawValue = "general"

    public init?(rawValue: String) {
        if rawValue == Self.generalRawValue { self = .general; return }
        guard let connection = VoiceConnection(rawValue: rawValue) else { return nil }
        self = .connection(connection)
    }

    public var rawValue: String {
        switch self {
        case .general: Self.generalRawValue
        case .connection(let connection): connection.rawValue
        }
    }
}

extension LearningScope: Codable {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let scope = LearningScope(rawValue: raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "unknown scope \(raw)"))
        }
        self = scope
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum LearningStatus: String, CaseIterable, Codable, Sendable {
    case proposed, confirmed, retired, rejected
}

public enum LearningProposer: String, CaseIterable, Codable, Sendable {
    /// Rules on the iPhone (`SaveSuggestions`, repeated-sequence detection).
    case rule
    /// A model, through `AssistantClient`. Its proposal goes through the same checks.
    case model
}

/// Where a learned item came from. Never user text: a short machine reason and the dates of
/// the source turns (the conversation dates, never the import time).
public struct LearningProvenance: Equatable, Codable, Sendable {
    public static let maxReasonLength = 60

    public let proposer: LearningProposer
    public let reason: String
    public let episodeDates: [Date]

    public init(proposer: LearningProposer, reason: String, episodeDates: [Date]) throws(LearningValidationError) {
        let reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reason.isEmpty else { throw .emptyText("reason") }
        guard reason.unicodeScalars.count <= Self.maxReasonLength else {
            throw .tooLong(field: "reason", length: reason.unicodeScalars.count, maximum: Self.maxReasonLength)
        }
        guard reason.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == "_" }) else {
            throw .notAnIdentifier("reason")
        }
        self.proposer = proposer
        self.reason = reason
        self.episodeDates = episodeDates.map(LearningJSON.truncatedToMilliseconds)
    }
}

public enum LearningValidationError: Error, Equatable, Sendable {
    case emptyText(String)
    case tooLong(field: String, length: Int, maximum: Int)
    /// Reasons, tool names, parameter names and episode ids are identifiers, never prose.
    case notAnIdentifier(String)
    case confidenceOutOfRange(Int)
    /// `confirmed` without a confirmation date, or the other way round.
    case statusMismatch
    case noEpisodes
    case noSteps
    case tooManySteps(Int)
    case stepNumbering
    /// Not in `PlanTool.allowed`: a look-up, a tool that leaves the app, or a name nobody knows.
    case toolNotAllowed(String)
    case parameterOverlap(String)
    case missingGapCategory
    case missingCorrection
    case detailMismatch
}

/// SHA-256 over the ordered source episode ids. The same evidence never yields a second
/// proposal while a row carries its digest (design §3).
public enum EvidenceDigest {
    public static func compute(_ episodeIDs: [String]) -> String {
        let joined = episodeIDs.joined(separator: "\n")
        return SHA256.hash(data: Data(joined.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

enum LearningText {
    static func length(_ text: String) -> Int { text.unicodeScalars.count }

    static func validated(_ text: String, field: String, maximum: Int) throws(LearningValidationError) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .emptyText(field) }
        guard length(trimmed) <= maximum else { throw .tooLong(field: field, length: length(trimmed), maximum: maximum) }
        return trimmed
    }

    static func identifier(_ text: String, field: String, maximum: Int = 80) throws(LearningValidationError) -> String {
        let value = try validated(text, field: field, maximum: maximum)
        guard value.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-" || $0 == "." }) else {
            throw .notAnIdentifier(field)
        }
        return value
    }

    static func episodeIDs(_ ids: [String]) throws(LearningValidationError) -> [String] {
        guard !ids.isEmpty else { throw .noEpisodes }
        var checked: [String] = []
        for id in ids { checked.append(try identifier(id, field: "source_episode_ids")) }
        return checked
    }
}

// MARK: Facts

/// A statement about the user that a proposer noticed and the user confirmed word for word.
public struct LearnedFact: Identifiable, Equatable, Sendable {
    public static let schemaVersion = 1
    public static let maxValueLength = 400

    public let id: UUID
    public let kind: LearnedFactKind
    /// The exact text the user confirmed (or the latest revision they confirmed).
    public let value: String
    public let scope: LearningScope
    /// 0–100, the proposer's own estimate. Shown, never used to skip the card.
    public let confidence: Int
    public let provenance: LearningProvenance
    public let sourceEpisodeIDs: [String]
    public let evidenceDigest: String
    public let status: LearningStatus
    public let createdAt: Date
    public let updatedAt: Date
    public let expiresAt: Date?
    public let confirmedAt: Date?

    public init(
        id: UUID, kind: LearnedFactKind, value: String, scope: LearningScope, confidence: Int,
        provenance: LearningProvenance, sourceEpisodeIDs: [String], status: LearningStatus,
        createdAt: Date, updatedAt: Date, expiresAt: Date?, confirmedAt: Date?
    ) throws(LearningValidationError) {
        guard (0...100).contains(confidence) else { throw .confidenceOutOfRange(confidence) }
        guard (status == .confirmed) == (confirmedAt != nil) else { throw .statusMismatch }
        self.id = id
        self.kind = kind
        self.value = try LearningText.validated(value, field: "value", maximum: Self.maxValueLength)
        self.scope = scope
        self.confidence = confidence
        self.provenance = provenance
        self.sourceEpisodeIDs = try LearningText.episodeIDs(sourceEpisodeIDs)
        self.evidenceDigest = EvidenceDigest.compute(self.sourceEpisodeIDs)
        self.status = status
        self.createdAt = LearningJSON.truncatedToMilliseconds(createdAt)
        self.updatedAt = LearningJSON.truncatedToMilliseconds(updatedAt)
        self.expiresAt = expiresAt.map(LearningJSON.truncatedToMilliseconds)
        self.confirmedAt = confirmedAt.map(LearningJSON.truncatedToMilliseconds)
    }

    public func isExpired(at now: Date) -> Bool { expiresAt.map { $0 <= now } ?? false }

    /// Only confirmed, unexpired facts reach the assistant (design §5).
    public func isRetrievable(at now: Date) -> Bool { status == .confirmed && !isExpired(at: now) }

    /// Shown under "still true?" after the review period (design §6).
    public func needsReview(at now: Date) -> Bool {
        guard status == .confirmed, let confirmedAt else { return false }
        if isExpired(at: now) { return true }
        return expiresAt == nil && now >= confirmedAt.addingTimeInterval(Double(LearnedFactKind.reviewAfterDays) * 86_400)
    }

    /// The same fact with another status, text or expiry. Throws if the result breaks the rules.
    public func changing(
        value: String? = nil, status: LearningStatus? = nil, expiresAt: Date?? = nil,
        confirmedAt: Date?? = nil, at date: Date
    ) throws(LearningValidationError) -> LearnedFact {
        try LearnedFact(
            id: id, kind: kind, value: value ?? self.value, scope: scope, confidence: confidence,
            provenance: provenance, sourceEpisodeIDs: sourceEpisodeIDs, status: status ?? self.status,
            createdAt: createdAt, updatedAt: date, expiresAt: expiresAt ?? self.expiresAt,
            confirmedAt: confirmedAt ?? self.confirmedAt)
    }

    /// Confirmed on the card at `date`; the expiry follows the kind.
    public func confirmed(at date: Date) throws(LearningValidationError) -> LearnedFact {
        let expiry = kind.expiryDays.map { date.addingTimeInterval(Double($0) * 86_400) }
        return try changing(status: .confirmed, expiresAt: .some(expiry), confirmedAt: .some(date), at: date)
    }
}

/// One confirmed wording of a fact, oldest first; number 1 is the first confirmation.
public struct LearnedFactRevision: Equatable, Sendable {
    public let factID: UUID
    public let number: Int
    public let value: String
    public let confirmedAt: Date

    public init(factID: UUID, number: Int, value: String, confirmedAt: Date) {
        self.factID = factID
        self.number = number
        self.value = value
        self.confirmedAt = LearningJSON.truncatedToMilliseconds(confirmedAt)
    }
}

// MARK: Procedures

/// Every tool a procedure may contain is a change, so every step is shown on the plan card and
/// runs only after the tap, each time. There is no other value, and no stored row can supply
/// one: the approval is derived here from the tool name, never read from the row (ADR-324).
public enum ProcedureApproval: Equatable, Sendable {
    case card

    public static func required(for toolName: String) -> ProcedureApproval { .card }
}

/// One step of a procedure: a tool from the plan allowlist, the parameters that were the same
/// every time (`fixed`) and the ones to ask for each run (`asked`).
public struct ProcedureStep: Equatable, Sendable {
    public static let maxParameters = 12
    public static let maxFixedValueLength = 200

    public let number: Int
    public let toolName: String
    public let fixed: [String: String]
    public let asked: [String]

    public init(number: Int, toolName: String, fixed: [String: String], asked: [String]) throws(LearningValidationError) {
        guard number >= 1 else { throw .stepNumbering }
        let tool = try LearningText.identifier(toolName, field: "tool")
        guard PlanTool.allowed.contains(tool) else { throw .toolNotAllowed(tool) }
        guard fixed.count + asked.count <= Self.maxParameters else {
            throw .tooLong(field: "parameters", length: fixed.count + asked.count, maximum: Self.maxParameters)
        }
        var checkedFixed: [String: String] = [:]
        for (name, value) in fixed {
            let key = try LearningText.identifier(name, field: "fixed")
            checkedFixed[key] = try LearningText.validated(value, field: "fixed.\(key)", maximum: Self.maxFixedValueLength)
        }
        var checkedAsked: [String] = []
        for name in asked {
            let key = try LearningText.identifier(name, field: "asked")
            guard checkedFixed[key] == nil, !checkedAsked.contains(key) else { throw .parameterOverlap(key) }
            checkedAsked.append(key)
        }
        self.number = number
        self.toolName = tool
        self.fixed = checkedFixed
        self.asked = checkedAsked
    }

    /// Derived at run time from the registry; not stored.
    public var approval: ProcedureApproval { ProcedureApproval.required(for: toolName) }

    /// The connection the step needs, or `nil` for notes and online-account tools (which
    /// Doddy's server approves for the exact arguments when the card is shown, ADR-209).
    public var connection: VoiceConnection? { VoiceConnection.serving(toolName) }

    public var isCloudTool: Bool { CloudToolName.all.contains(toolName) }
}

extension ProcedureStep: Codable {
    enum CodingKeys: String, CodingKey { case number, toolName = "tool", fixed, asked }

    /// Stored rows are decoded by these keys only. A hand-edited `"approval"` or `"tier"` is
    /// ignored; the step's approval still comes from `ProcedureApproval.required(for:)`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        do {
            try self.init(
                number: c.decode(Int.self, forKey: .number), toolName: c.decode(String.self, forKey: .toolName),
                fixed: c.decodeIfPresent([String: String].self, forKey: .fixed) ?? [:],
                asked: c.decodeIfPresent([String].self, forKey: .asked) ?? [])
        } catch let error as LearningValidationError {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "\(error)"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(number, forKey: .number)
        try c.encode(toolName, forKey: .toolName)
        try c.encode(fixed, forKey: .fixed)
        try c.encode(asked, forKey: .asked)
    }
}

/// A saved plan template (ADR-204): a trigger and up to `PlanTool.maxSteps` steps. Running it
/// shows the same plan card as any plan, with every step checked as if asked on its own.
public struct Procedure: Identifiable, Equatable, Sendable {
    public static let schemaVersion = 1
    public static let maxTriggerLength = 120
    public static let maxSteps = PlanTool.maxSteps

    public let id: UUID
    public let triggerText: String
    public let steps: [ProcedureStep]
    public let version: Int
    public let scope: LearningScope
    public let status: LearningStatus
    public let provenance: LearningProvenance
    public let sourceEpisodeIDs: [String]
    public let evidenceDigest: String
    public let createdAt: Date
    public let updatedAt: Date
    public let confirmedAt: Date?
    public let lastUsedAt: Date?
    public let useCount: Int

    public init(
        id: UUID, triggerText: String, steps: [ProcedureStep], version: Int, scope: LearningScope,
        status: LearningStatus, provenance: LearningProvenance, sourceEpisodeIDs: [String],
        createdAt: Date, updatedAt: Date, confirmedAt: Date?, lastUsedAt: Date?, useCount: Int
    ) throws(LearningValidationError) {
        guard !steps.isEmpty else { throw .noSteps }
        guard steps.count <= Self.maxSteps else { throw .tooManySteps(steps.count) }
        guard steps.map(\.number) == Array(1...steps.count) else { throw .stepNumbering }
        guard version >= 1, useCount >= 0 else { throw .statusMismatch }
        guard (status == .confirmed) == (confirmedAt != nil) else { throw .statusMismatch }
        self.id = id
        self.triggerText = try LearningText.validated(triggerText, field: "trigger_text", maximum: Self.maxTriggerLength)
        self.steps = steps
        self.version = version
        self.scope = scope
        self.status = status
        self.provenance = provenance
        self.sourceEpisodeIDs = try LearningText.episodeIDs(sourceEpisodeIDs)
        self.evidenceDigest = EvidenceDigest.compute(self.sourceEpisodeIDs)
        self.createdAt = LearningJSON.truncatedToMilliseconds(createdAt)
        self.updatedAt = LearningJSON.truncatedToMilliseconds(updatedAt)
        self.confirmedAt = confirmedAt.map(LearningJSON.truncatedToMilliseconds)
        self.lastUsedAt = lastUsedAt.map(LearningJSON.truncatedToMilliseconds)
        self.useCount = useCount
    }

    public func isRetrievable(at now: Date) -> Bool { status == .confirmed }

    /// Unused this long, a confirmed procedure is retired and shown as such (design §6).
    public func isStale(at now: Date, retirementDays: Int) -> Bool {
        guard status == .confirmed else { return false }
        let last = lastUsedAt ?? confirmedAt ?? updatedAt
        return now >= last.addingTimeInterval(Double(retirementDays) * 86_400)
    }

    public func changing(
        triggerText: String? = nil, steps: [ProcedureStep]? = nil, version: Int? = nil,
        status: LearningStatus? = nil, confirmedAt: Date?? = nil, lastUsedAt: Date?? = nil,
        useCount: Int? = nil, at date: Date
    ) throws(LearningValidationError) -> Procedure {
        try Procedure(
            id: id, triggerText: triggerText ?? self.triggerText, steps: steps ?? self.steps,
            version: version ?? self.version, scope: scope, status: status ?? self.status,
            provenance: provenance, sourceEpisodeIDs: sourceEpisodeIDs, createdAt: createdAt,
            updatedAt: date, confirmedAt: confirmedAt ?? self.confirmedAt,
            lastUsedAt: lastUsedAt ?? self.lastUsedAt, useCount: useCount ?? self.useCount)
    }
}

// MARK: Outcome events

public enum OutcomeKind: String, CaseIterable, Codable, Sendable {
    case completed, corrected, cancelled, redone, declined
    case capabilityGap = "capability_gap"
}

/// What the user asked for that no tool covers. A category, never their words (design §4.4).
public enum CapabilityGapCategory: String, CaseIterable, Codable, Sendable {
    case sendMessage = "send_message"
    case payment
    case music
    case smartHome = "smart_home"
    case otherAppControl = "other_app_control"
    case webAction = "web_action"
    case unknown
}

public enum CorrectionKind: String, CaseIterable, Codable, Sendable {
    /// Undo on a "What Doddy did" entry.
    case undo
    /// A step changed on the plan card before it ran.
    case changedStep = "changed_step"
    /// "That's wrong" on a learned item.
    case thatsWrong = "thats_wrong"
}

/// The detail of an outcome: identifiers and categories only. There is no field for user text.
public struct OutcomeDetail: Equatable, Codable, Sendable {
    public let toolName: String?
    public let procedureID: UUID?
    public let stepNumber: Int?
    public let gapCategory: CapabilityGapCategory?
    public let correction: CorrectionKind?
    public let learnedItemID: UUID?
    /// The conversation the request belonged to (an id, so the same tools in one conversation
    /// can be seen as one sequence). Nothing of the conversation itself.
    public let sessionID: String?

    public init(
        toolName: String? = nil, procedureID: UUID? = nil, stepNumber: Int? = nil,
        gapCategory: CapabilityGapCategory? = nil, correction: CorrectionKind? = nil, learnedItemID: UUID? = nil,
        sessionID: String? = nil
    ) throws(LearningValidationError) {
        self.toolName = try toolName.map { (name) throws(LearningValidationError) in try LearningText.identifier(name, field: "tool") }
        self.procedureID = procedureID
        self.stepNumber = stepNumber
        self.gapCategory = gapCategory
        self.correction = correction
        self.learnedItemID = learnedItemID
        self.sessionID = try sessionID.map { (id) throws(LearningValidationError) in try LearningText.identifier(id, field: "session_id") }
    }
}

/// What happened after a request, written by the app (never by the model). The evidence for
/// proposals and the source of the one metric, corrections per week.
public struct OutcomeEvent: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let requestID: String
    public let kind: OutcomeKind
    public let detail: OutcomeDetail
    public let createdAt: Date

    public init(id: UUID = UUID(), requestID: String, kind: OutcomeKind, detail: OutcomeDetail, createdAt: Date) throws(LearningValidationError) {
        switch kind {
        case .capabilityGap:
            guard detail.gapCategory != nil else { throw .missingGapCategory }
            guard detail.toolName == nil, detail.procedureID == nil, detail.correction == nil else { throw .detailMismatch }
        case .corrected:
            guard detail.correction != nil else { throw .missingCorrection }
            guard detail.gapCategory == nil else { throw .detailMismatch }
        case .completed, .cancelled, .redone, .declined:
            guard detail.gapCategory == nil, detail.correction == nil else { throw .detailMismatch }
        }
        self.id = id
        self.requestID = try LearningText.identifier(requestID, field: "request_id")
        self.kind = kind
        self.detail = detail
        self.createdAt = LearningJSON.truncatedToMilliseconds(createdAt)
    }

    /// The kinds that count as a correction for the metric (design §4.3).
    public static let correctionKinds: Set<OutcomeKind> = [.corrected, .redone, .cancelled]
}

// MARK: JSON

/// One encoder and decoder for every learned-item JSON column: dates as milliseconds, keys
/// sorted, so a row reads back byte for byte.
public enum LearningJSON {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }

    public static func truncatedToMilliseconds(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 * 1000).rounded(.down) / 1000)
    }
}
