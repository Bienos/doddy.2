import Foundation

/// The owner's defaults (design §6 and §12, accepted 2026-10-11).
public struct LearningLimits: Equatable, Sendable {
    public let proposalsPerDay: Int
    public let proposalsPerConversation: Int
    /// A proposal nobody answered is dropped after this many days.
    public let proposalExpiryDays: Int
    /// A confirmed procedure unused this long is retired (shown, one tap to revive).
    public let procedureRetirementDays: Int
    public let outcomeRetentionDays: Int

    public init(
        proposalsPerDay: Int = 3, proposalsPerConversation: Int = 1, proposalExpiryDays: Int = 7,
        procedureRetirementDays: Int = 90, outcomeRetentionDays: Int = 90
    ) {
        self.proposalsPerDay = proposalsPerDay
        self.proposalsPerConversation = proposalsPerConversation
        self.proposalExpiryDays = proposalExpiryDays
        self.procedureRetirementDays = procedureRetirementDays
        self.outcomeRetentionDays = outcomeRetentionDays
    }

    public static let standard = LearningLimits()
}

/// What the app knows when a proposal arrives. The policy never reads Settings itself.
public struct LearningEnvironment: Sendable {
    /// Tools a procedure may contain. Narrower than `PlanTool.allowed` is fine; wider is ignored.
    public let allowedTools: Set<String>
    public let connectionsPaused: Bool
    /// The character router's sensitive mode: no proposals at all (design §6).
    public let sensitiveMode: Bool
    /// Whether a tool can run now: its connection on in Settings and allowed by iOS, or its
    /// online account connected. Notes are always on.
    public let isToolOn: @Sendable (String) -> Bool

    public init(
        allowedTools: Set<String> = Set(PlanTool.allowed), connectionsPaused: Bool, sensitiveMode: Bool,
        isToolOn: @escaping @Sendable (String) -> Bool
    ) {
        self.allowedTools = allowedTools.intersection(PlanTool.allowed)
        self.connectionsPaused = connectionsPaused
        self.sensitiveMode = sensitiveMode
        self.isToolOn = isToolOn
    }
}

/// How many proposals were already shown.
public struct ProposalCounts: Equatable, Sendable {
    public let shownToday: Int
    public let shownThisConversation: Int

    public init(shownToday: Int, shownThisConversation: Int) {
        self.shownToday = shownToday
        self.shownThisConversation = shownThisConversation
    }

    public static let none = ProposalCounts(shownToday: 0, shownThisConversation: 0)
}

/// A proposal that passed `LearningPolicy`. Only the policy makes one; repositories take only
/// these, so nothing reaches a card or a row without the checks.
public struct ValidatedProposal: Equatable, Sendable {
    public let proposal: LearningProposal
    public let evidenceDigest: String
    public let validatedAt: Date

    fileprivate init(proposal: LearningProposal, validatedAt: Date) {
        self.proposal = proposal
        self.evidenceDigest = proposal.evidenceDigest
        self.validatedAt = LearningJSON.truncatedToMilliseconds(validatedAt)
    }
}

public enum LearningPolicy {
    /// Checks, in order: the content (sensitive text, tools), the evidence (seen before), the
    /// moment (paused, sensitive mode), then the caps. A dropped proposal is never shown.
    public static func validate(
        _ proposal: LearningProposal, environment: LearningEnvironment, counts: ProposalCounts,
        knownDigests: Set<String>, limits: LearningLimits = .standard, now: Date
    ) throws(LearningProposalError) -> ValidatedProposal {
        switch proposal {
        case .fact(let fact):
            if SensitiveContentFilter.isSensitive(fact.value) { throw .sensitive }
        case .procedure(let procedure):
            if SensitiveContentFilter.isSensitive(procedure.triggerText) { throw .sensitive }
            for step in procedure.steps {
                guard environment.allowedTools.contains(step.toolName) else {
                    throw .invalid(.toolNotAllowed(step.toolName))
                }
                for value in step.fixed.values where SensitiveContentFilter.isSensitive(value) { throw .sensitive }
                guard environment.isToolOn(step.toolName) else { throw .toolOff(step.toolName) }
            }
        }
        if knownDigests.contains(proposal.evidenceDigest) { throw .rejectedBefore }
        if environment.connectionsPaused { throw .paused }
        if environment.sensitiveMode { throw .sensitiveMode }
        if counts.shownThisConversation >= limits.proposalsPerConversation { throw .overConversationCap }
        if counts.shownToday >= limits.proposalsPerDay { throw .overDailyCap }
        return ValidatedProposal(proposal: proposal, validatedAt: now)
    }
}

/// The never-learned list (design §6, owner default): secrets (the ADR-247 list and long digit
/// runs), health and medication, sexual orientation, religion, political views, immigration
/// status, precise location history, and a third person's health or money. Word rules in
/// English and Polish on folded text; a match means "not proposed", never "deleted".
public enum SensitiveContentFilter {
    public static func isSensitive(_ text: String) -> Bool {
        let folded = SearchFolding.fold(text)
        let words = SearchFolding.tokens(folded: folded)
        if SaveSuggestions.containsSecret(folded: folded, words: words) { return true }
        if phrases.contains(where: { SaveSuggestions.contains(words, $0) }) { return true }
        if words.contains(where: { word in prefixes.contains(where: word.hasPrefix) }) { return true }
        return false
    }

    static let phrases: [String] = [
        // health and medication
        "diagnosed", "diagnosis", "therapy", "therapist", "psychiatrist", "medication", "prescription", "pills", "pregnant",
        "pregnancy", "hiv", "cancer", "chemo", "depression", "anxiety", "disorder", "surgery", "diabetes", "allergy", "allergic",
        "diagnoza", "zdiagnozowan", "terapia", "terapeut", "psychiatr", "leki", "lek na", "recepta", "w ciazy", "ciaza", "rak",
        "chemia", "depresja", "nerwica", "operacja", "cukrzyca", "alergia", "uczulon",
        // sexual orientation, religion, politics, immigration
        "gay", "lesbian", "bisexual", "trans", "sexual orientation", "orientacja", "homoseksual", "biseksual",
        "religion", "religious", "catholic", "muslim", "jewish", "atheist", "church", "mosque", "synagogue",
        "religia", "wyznan", "katoli", "muzulman", "zyd", "ateist", "kosciol", "meczet", "synagog",
        "vote", "voted", "voting", "party member", "political", "politics", "glosuj", "glosowal", "partia", "politycz",
        "visa", "immigration", "asylum", "residence permit", "deport", "wiza", "imigrac", "azyl", "karta pobytu", "deportac",
        // precise location history
        "gps", "coordinates", "latitude", "longitude", "wspolrzedne", "szerokosc geograficzna",
        // a third person's health or money
        "salary", "earns", "debt", "owes", "bankrupt", "zarabia", "pensja", "zadluzony", "bankrut",
    ]

    /// Word stems, so inflected forms match too ("cukrzycę", "zdiagnozowano", "alergii").
    static let prefixes: [String] = [
        "medic", "diagnos", "zdiagnoz", "psychiatr", "chemoterap", "chemioterap", "antydepres", "antidepress",
        "cukrzyc", "alergi", "uczulon", "depresj", "terapeut", "terapi", "religi", "wyznani", "katoli", "muzulman",
        "ateist", "kosciol", "polityc", "partyjn", "imigra", "deporta", "homoseks", "biseks", "zarabia", "pensj",
        "zadluz", "bankrut",
    ]
}
