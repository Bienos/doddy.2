import Foundation

// The typed result of an expert mode (ADR-642; research docs/research/2026-10-24/research_expert_modes_PL.md
// section 7.2). A mode answers in this shape, so every answer carries its sources, its caveats and how
// risky it is, and so "done" can only ever be said with a receipt: `verifiedExternalAction` is false
// for everything that only reads, explains or proposes. Nothing in this file talks to a model or to the
// network; it is the shape code gives to what code decided.
//
// Platforms: iPhone, iPad, Mac, Watch (DoddyCore, no UI).

/// A mode's name as it appears in the JSON ("personal_training"). A struct, not an enum, so another
/// mode adds its own constant in its own file without touching this one.
public struct ExpertMode: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static let personalTraining: ExpertMode = "personal_training"
}

/// How much is at stake in an answer. Above `.low`, Doddy's humor is off (research section 1).
public enum RiskLevel: String, Codable, CaseIterable, Comparable, Sendable {
    case low, moderate, high, emergency

    public var rank: Int {
        switch self {
        case .low: 0
        case .moderate: 1
        case .high: 2
        case .emergency: 3
        }
    }

    public static func < (a: RiskLevel, b: RiskLevel) -> Bool { a.rank < b.rank }

    /// Doddy's character stays the same in every mode; only the jokes go (constitution DOD-03, research section 1).
    public var humorAllowed: Bool { self == .low }
}

/// A source an answer rests on: where it is and the day it was last checked.
public struct ExpertSource: Equatable, Hashable, Codable, Sendable {
    public let url: String
    /// A day, `yyyy-MM-dd`.
    public let checkedAt: String
    public let title: String?

    public init(url: String, checkedAt: String, title: String? = nil) {
        self.url = url
        self.checkedAt = checkedAt
        self.title = title
    }

    enum CodingKeys: String, CodingKey {
        case url
        case checkedAt = "checked_at"
        case title
    }

    /// The sources every training answer may cite. Read on the pages on 24 Oct 2026
    /// (research_sport_mode.md, sources 7, 8 and 11).
    public static let who2020 = ExpertSource(
        url: "https://www.ncbi.nlm.nih.gov/books/NBK566046/", checkedAt: "2026-10-24",
        title: "WHO guidelines on physical activity and sedentary behaviour, 2020")
    public static let acsm2026 = ExpertSource(
        url: "https://pmc.ncbi.nlm.nih.gov/articles/PMC12965823/", checkedAt: "2026-10-24",
        title: "ACSM 2026 position stand on resistance training")
    public static let frandsen2025 = ExpertSource(
        url: "https://doi.org/10.1136/bjsports-2024-109380", checkedAt: "2026-10-24",
        title: "Frandsen et al., BJSM 2025: the longest run and injury")
}

/// Something an answer proposes to do. Nothing here is done: every proposal waits for the person's
/// own yes on the exact text (ASK-01), and is a separate result once it has a receipt.
public struct ExpertProposedAction: Equatable, Codable, Sendable {
    public let kind: String
    public let summary: String

    public init(kind: String, summary: String) {
        self.kind = kind
        self.summary = summary
    }
}

public struct ExpertResult: Equatable, Codable, Sendable {
    public let mode: ExpertMode
    public let answer: String
    public let proposedActions: [ExpertProposedAction]
    /// What is still needed to answer, as keys the screens know; empty when nothing is missing.
    public let missingData: [String]
    public let sources: [ExpertSource]
    public let caveats: [String]
    /// A proposal to remember something. Always nil in this slice: nothing is saved on the way.
    public let memoryUpdateProposal: String?
    public let riskLevel: RiskLevel
    /// True only after a trusted confirmation that something outside the app really happened.
    public let verifiedExternalAction: Bool

    public init(mode: ExpertMode, answer: String, proposedActions: [ExpertProposedAction] = [], missingData: [String] = [],
                sources: [ExpertSource] = [], caveats: [String] = [], memoryUpdateProposal: String? = nil,
                riskLevel: RiskLevel = .low, verifiedExternalAction: Bool = false) {
        self.mode = mode
        self.answer = answer
        self.proposedActions = proposedActions
        self.missingData = missingData
        self.sources = sources
        self.caveats = caveats
        self.memoryUpdateProposal = memoryUpdateProposal
        self.riskLevel = riskLevel
        self.verifiedExternalAction = verifiedExternalAction
    }

    public var humorAllowed: Bool { riskLevel.humorAllowed }

    enum CodingKeys: String, CodingKey {
        case mode, answer, sources, caveats
        case proposedActions = "proposed_actions"
        case missingData = "missing_data"
        case memoryUpdateProposal = "memory_update_proposal"
        case riskLevel = "risk_level"
        case verifiedExternalAction = "verified_external_action"
    }

    /// `memory_update_proposal` is written as `null`, not left out, as in the research's contract.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mode, forKey: .mode)
        try container.encode(answer, forKey: .answer)
        try container.encode(proposedActions, forKey: .proposedActions)
        try container.encode(missingData, forKey: .missingData)
        try container.encode(sources, forKey: .sources)
        try container.encode(caveats, forKey: .caveats)
        if let memoryUpdateProposal {
            try container.encode(memoryUpdateProposal, forKey: .memoryUpdateProposal)
        } else {
            try container.encodeNil(forKey: .memoryUpdateProposal)
        }
        try container.encode(riskLevel, forKey: .riskLevel)
        try container.encode(verifiedExternalAction, forKey: .verifiedExternalAction)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decode(ExpertMode.self, forKey: .mode)
        answer = try container.decode(String.self, forKey: .answer)
        proposedActions = try container.decode([ExpertProposedAction].self, forKey: .proposedActions)
        missingData = try container.decode([String].self, forKey: .missingData)
        sources = try container.decode([ExpertSource].self, forKey: .sources)
        caveats = try container.decode([String].self, forKey: .caveats)
        memoryUpdateProposal = try container.decodeIfPresent(String.self, forKey: .memoryUpdateProposal)
        riskLevel = try container.decode(RiskLevel.self, forKey: .riskLevel)
        verifiedExternalAction = try container.decode(Bool.self, forKey: .verifiedExternalAction)
    }

    /// The JSON as the research writes it: snake_case keys, sorted, compact.
    public func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}
