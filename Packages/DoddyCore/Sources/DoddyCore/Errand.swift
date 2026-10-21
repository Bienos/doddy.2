import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

// Errands (ADR-566, docs/implementation/ERRANDS.md): a task ("sprawa") the user hands Doddy in a
// conversation. The app shows one ask card; on a yes it creates the errand on Doddy's messaging
// server and approves it with the digest the server returned for exactly those words. The server
// researches it in the background (web search and web fetch, nothing else) and writes a result
// card; the app fetches it, saves it on the iPhone, then acknowledges it so the server deletes its
// copy. One yes covers every look-up of that one errand, with no limit (owner, 21 Oct 2026), and
// nothing else. "Errand" in code because `Task` is Swift concurrency's; the user never sees the word.
//
// As in the rest of the client: nothing here says started, done or saved unless the server or the
// store said so, and "unknown" is never success.

// MARK: - The draft (what the user said yes to)

/// What Doddy hands over. The user's words are kept as given: only leading and trailing spaces are
/// trimmed, nothing else is changed. The brief is Doddy's, and is labelled as Doddy's everywhere.
public struct ErrandDraft: Codable, Equatable, Hashable, Sendable {
    public static let maxWords = 1_000
    public static let maxBrief = 1_000
    public static let maxTitle = 80
    public static let defaultLanguage = "pl"

    /// The user's exact words.
    public let words: String
    /// Doddy's one-line restatement, with any assumption it said out loud.
    public let brief: String
    /// Short, for the list, the push and the card ("Rzym, 7 dni").
    public let title: String
    /// A two-letter language code, lower case.
    public let language: String

    public init(words: String, brief: String, title: String, language: String = ErrandDraft.defaultLanguage) {
        self.words = words.trimmingCharacters(in: .whitespacesAndNewlines)
        self.brief = brief.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.language = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Hints before sending, in a fixed order; the server checks the same limits again and decides.
    /// Lengths count UTF-16 units, as the server's schema does (JavaScript string length), so an
    /// emoji counts twice.
    public func validationIssues() -> [ErrandDraftIssue] {
        var issues: [ErrandDraftIssue] = []
        if words.isEmpty { issues.append(.missingWords) } else if words.utf16.count > Self.maxWords { issues.append(.wordsTooLong) }
        if brief.isEmpty { issues.append(.missingBrief) } else if brief.utf16.count > Self.maxBrief { issues.append(.briefTooLong) }
        if title.isEmpty { issues.append(.missingTitle) } else if title.utf16.count > Self.maxTitle { issues.append(.titleTooLong) }
        if !Self.isLanguageCode(language) { issues.append(.languageNotACode) }
        return issues
    }

    /// The digest the server binds the approval to: SHA-256 (hex) over the canonical JSON of
    /// `{brief, language, title, words}`, keys sorted, no spaces, strings escaped as JavaScript's
    /// JSON.stringify escapes them (server/messaging/src/errands/schema.ts). The app approves a
    /// preview only when its digest is this one, so the yes is bound to exactly these words.
    public var digest: String {
        let json = "{\"brief\":\(Self.jsonString(brief)),\"language\":\(Self.jsonString(language)),"
            + "\"title\":\(Self.jsonString(title)),\"words\":\(Self.jsonString(words))}"
        return SHA256.hash(data: Data(json.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// A JSON string literal exactly as JSON.stringify writes it: `"` and `\` escaped, control
    /// characters as `\b \t \n \f \r` or `\u00xx` (lower case), everything else as it is.
    static func jsonString(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x22: out += "\\\""
            case 0x5C: out += "\\\\"
            case 0x08: out += "\\b"
            case 0x09: out += "\\t"
            case 0x0A: out += "\\n"
            case 0x0C: out += "\\f"
            case 0x0D: out += "\\r"
            case 0..<0x20: out += String(format: "\\u%04x", scalar.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }

    public var isValid: Bool { validationIssues().isEmpty }

    static func isLanguageCode(_ text: String) -> Bool {
        text.unicodeScalars.count == 2 && text.unicodeScalars.allSatisfy { ("a"..."z").contains($0) }
    }
}

public enum ErrandDraftIssue: Equatable, Sendable {
    case missingWords, wordsTooLong, missingBrief, briefTooLong, missingTitle, titleTooLong, languageNotACode

    /// For the agent, in the style of the other tools' `invalid` reasons.
    public var reason: String {
        switch self {
        case .missingWords: "missing words"
        case .wordsTooLong: "words is longer than \(ErrandDraft.maxWords) characters"
        case .missingBrief: "missing brief"
        case .briefTooLong: "brief is longer than \(ErrandDraft.maxBrief) characters"
        case .missingTitle: "missing title"
        case .titleTooLong: "title is longer than \(ErrandDraft.maxTitle) characters"
        case .languageNotACode: "language must be a two-letter code such as pl or en"
        }
    }
}

extension VoiceToolRequest {
    /// `{words, brief, title, language?}`. Too long or missing is refused, never cut or filled in:
    /// the agent hears why and asks the user.
    static func parseHandOverErrand(_ args: Arguments, name: String) -> VoiceToolRequest {
        let draft = ErrandDraft(
            words: args.text("words") ?? "", brief: args.text("brief") ?? "", title: args.text("title") ?? "",
            language: args.text("language") ?? ErrandDraft.defaultLanguage)
        let issues = draft.validationIssues()
        guard issues.isEmpty else { return .invalid(name: name, reason: issues.map(\.reason).joined(separator: "; ")) }
        return .handOverErrand(draft)
    }

    /// `{about?}`: which task the user asked about, in the agent's words. Blank means the newest.
    static func parseCheckErrands(_ args: Arguments) -> VoiceToolRequest {
        .checkErrands(about: args.text("about")?.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

// MARK: - The ask (ASK-01)

/// The cards for the two errand tools. Both change nothing on the iPhone or in an account, so a
/// spoken yes or a tap answers them (ASK-01's read rule).
public enum ErrandAsk {
    public static func handOverCard(_ draft: ErrandDraft) -> AskCard {
        AskCard(
            title: "Hand this to Doddy?",
            lines: [
                "\u{201C}\(draft.words)\u{201D}",
                "Doddy's note: \(draft.brief)",
                "Doddy searches the web and reads pages as often as this needs, in the background, and sends you a notification when it's done.",
                "Nothing is booked, bought or sent.",
            ],
            confirmLabel: "Yes, go")
    }

    public static let checkCard = AskCard(
        title: "Check your tasks?", lines: ["What Doddy found for the tasks you handed over"], confirmLabel: "Yes, check")
}

// MARK: - States and failures

public enum ErrandState: String, Codable, Sendable, CaseIterable {
    case draft, queued, running, done, failed, cancelled
    /// A state this version of the app doesn't know, or an approval whose answer never came back.
    /// Never read as success.
    case unknown

    /// A newer server's state decodes as `unknown` instead of breaking the app.
    public init(from decoder: any Decoder) throws {
        self = ErrandState(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }

    /// Queued or running on the server.
    public var isOpen: Bool { self == .queued || self == .running }
    public var isFinished: Bool { self == .done || self == .failed || self == .cancelled }
}

/// Why a run ended as `failed` (the server's codes).
public enum ErrandFailureCode: String, Codable, Sendable, CaseIterable {
    /// The worker stopped mid-run. It is never re-run by itself; the user hands it over again.
    case interrupted
    case timeLimit = "time_limit"
    /// The model declined.
    case refused
    case providerError = "provider_error"
    /// The result didn't fit the result card's schema.
    case unreadableResult = "unreadable_result"
    /// A code this version of the app doesn't know.
    case unknown

    public init(from decoder: any Decoder) throws {
        self = ErrandFailureCode(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }

    /// For the result card and the agent: what happened, in plain words.
    public var explanation: String {
        switch self {
        case .interrupted:
            "Doddy's server stopped in the middle of this task. It isn't started again by itself; hand it over again if you still want it."
        case .timeLimit:
            "It took longer than the time limit, so Doddy stopped it."
        case .refused:
            "The AI model Doddy uses declined to work on this task."
        case .providerError:
            "The AI service Doddy uses had a problem, so the task stopped."
        case .unreadableResult:
            "Doddy couldn't turn what it found into a result card it could check, so nothing is shown."
        case .unknown:
            "It stopped for a reason this version of the app doesn't know."
        }
    }

    /// The same, as a few words after "couldn't finish:".
    public var shortReason: String {
        switch self {
        case .interrupted: "it was interrupted"
        case .timeLimit: "it hit the time limit"
        case .refused: "the AI model declined it"
        case .providerError: "the AI service had a problem"
        case .unreadableResult: "the result couldn't be checked"
        case .unknown: "reason unknown"
        }
    }
}

/// What the server deleted after `ack`, as it reported it (`words`, `brief`, `title`, `result`).
public struct ErrandDeletion: Codable, Equatable, Sendable, Identifiable {
    public let what: String
    /// `acked`, `expired` or `deleted`, when the server says.
    public let reason: String?
    public let deletedAt: String

    public init(what: String, reason: String? = nil, deletedAt: String) {
        self.what = what
        self.reason = reason
        self.deletedAt = deletedAt
    }

    public var id: String { "\(what):\(deletedAt)" }
}

// MARK: - What the server returns

/// `201` from `POST /v1/errands`: a draft, nothing runs. The approval is bound to `digest`.
public struct ErrandPreview: Decodable, Equatable, Sendable {
    public let id: UUID
    public let digest: String
    public let title: String
    public let words: String
    public let brief: String
    public let expiresAt: Date

    public init(id: UUID, digest: String, title: String, words: String, brief: String, expiresAt: Date) {
        self.id = id
        self.digest = digest
        self.title = title
        self.words = words
        self.brief = brief
        self.expiresAt = expiresAt
    }

    private enum CodingKeys: String, CodingKey { case id, digest, title, words, brief, expiresAt }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        digest = try c.decode(String.self, forKey: .digest)
        title = try c.decode(String.self, forKey: .title)
        words = try c.decode(String.self, forKey: .words)
        brief = try c.decode(String.self, forKey: .brief)
        expiresAt = try c.serverDate(.expiresAt)
    }

    /// The server holds exactly what the user said yes to, and its digest is for exactly that.
    /// Anything else is never approved.
    public func matches(_ draft: ErrandDraft) -> Bool {
        words == draft.words && brief == draft.brief && title == draft.title && digest == draft.digest
    }
}

public struct ErrandApproval: Equatable, Sendable {
    /// Nil when the server's answer never reached the phone.
    public let id: UUID?
    /// `queued` as the server said it, or `unknown`: it may have started, and it is not approved again.
    public let state: String

    public init(id: UUID?, state: String) {
        self.id = id
        self.state = state
    }

    public var isUnknown: Bool { state == ErrandState.unknown.rawValue }
    /// The server said it has it.
    public var isConfirmed: Bool { state == ErrandState.queued.rawValue || state == ErrandState.running.rawValue }
}

/// One row of `GET /v1/errands` (newest first, no drafts).
public struct ErrandSummary: Decodable, Equatable, Sendable, Identifiable {
    public let id: UUID
    /// Nil once the app acknowledged the result: the server deleted it.
    public let title: String?
    public let state: ErrandState
    public let createdAt: Date
    public let finishedAt: Date?
    public let failure: ErrandFailureCode?

    private enum CodingKeys: String, CodingKey { case id, title, state, createdAt, finishedAt, failure }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        state = try c.decode(ErrandState.self, forKey: .state)
        createdAt = try c.serverDate(.createdAt)
        finishedAt = try c.serverDateIfPresent(.finishedAt)
        failure = try c.decodeIfPresent(ErrandFailureCode.self, forKey: .failure)
    }
}

/// `GET /v1/errands/:id`. After `ack` only the id, state and times are left, so the rest is optional.
public struct ErrandSnapshot: Decodable, Equatable, Sendable {
    public let id: UUID
    public let title: String?
    public let words: String?
    public let brief: String?
    public let language: String?
    public let state: ErrandState
    public let createdAt: Date
    public let approvedAt: Date?
    public let startedAt: Date?
    public let finishedAt: Date?
    /// When the server took the app's `ack` and deleted its copy.
    public let acknowledgedAt: Date?
    /// Cancel was asked while it ran; it stops at its next step.
    public let cancelRequested: Bool?
    public let searches: Int?
    public let fetches: Int?
    /// Only when `done`.
    public let result: ErrandResult?
    public let resultDigest: String?
    public let failure: ErrandFailureCode?

    private enum CodingKeys: String, CodingKey {
        case id, title, words, brief, language, state, createdAt, approvedAt, startedAt, finishedAt, acknowledgedAt, cancelRequested
        case searches, fetches, result, resultDigest, failure
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        words = try c.decodeIfPresent(String.self, forKey: .words)
        brief = try c.decodeIfPresent(String.self, forKey: .brief)
        language = try c.decodeIfPresent(String.self, forKey: .language)
        state = try c.decode(ErrandState.self, forKey: .state)
        createdAt = try c.serverDate(.createdAt)
        approvedAt = try c.serverDateIfPresent(.approvedAt)
        startedAt = try c.serverDateIfPresent(.startedAt)
        finishedAt = try c.serverDateIfPresent(.finishedAt)
        acknowledgedAt = try c.serverDateIfPresent(.acknowledgedAt)
        cancelRequested = try c.decodeIfPresent(Bool.self, forKey: .cancelRequested)
        searches = try c.decodeIfPresent(Int.self, forKey: .searches)
        fetches = try c.decodeIfPresent(Int.self, forKey: .fetches)
        result = try c.decodeIfPresent(ErrandResult.self, forKey: .result)
        resultDigest = try c.decodeIfPresent(String.self, forKey: .resultDigest)
        failure = try c.decodeIfPresent(ErrandFailureCode.self, forKey: .failure)
    }

    /// The finished result with the digest `ack` needs; nil unless the server has both.
    public var readyResult: (result: ErrandResult, digest: String)? {
        guard state == .done, let result, let resultDigest, !resultDigest.isEmpty else { return nil }
        return (result, resultDigest)
    }
}

/// The result card, exactly the server's schema. Links and prices were checked on the server
/// (every URL came from this run; no price without its page). `checkedAt` is kept as sent.
public struct ErrandResult: Codable, Equatable, Sendable {
    public enum SectionKind: String, Codable, Sendable, CaseIterable {
        /// A comparison table.
        case options
        /// Short research.
        case brief
        /// Steps.
        case checklist
        case places
        /// A kind this version of the app doesn't know; shown as a plain list.
        case unknown

        public init(from decoder: any Decoder) throws {
            self = SectionKind(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }
    }

    public enum BudgetFit: String, Codable, Sendable, CaseIterable {
        case yes, no, unknown

        public init(from decoder: any Decoder) throws {
            self = BudgetFit(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }
    }

    public struct Item: Codable, Equatable, Sendable {
        public let title: String
        public let detail: String?
        public let when: String?
        public let price: String?
        public let url: String?
        public let site: String?

        public init(title: String, detail: String? = nil, when: String? = nil, price: String? = nil, url: String? = nil, site: String? = nil) {
            self.title = title
            self.detail = detail
            self.when = when
            self.price = price
            self.url = url
            self.site = site
        }
    }

    public struct Section: Codable, Equatable, Sendable {
        public let heading: String
        public let kind: SectionKind
        public let items: [Item]

        public init(heading: String, kind: SectionKind, items: [Item]) {
            self.heading = heading
            self.kind = kind
            self.items = items
        }

        private enum CodingKeys: String, CodingKey { case heading, kind, items }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            heading = try c.decode(String.self, forKey: .heading)
            kind = try c.decodeIfPresent(SectionKind.self, forKey: .kind) ?? .unknown
            items = try c.decodeIfPresent([Item].self, forKey: .items) ?? []
        }
    }

    public struct Budget: Codable, Equatable, Sendable {
        /// The user's budget as they said it.
        public let asked: String
        public let within: BudgetFit

        public init(asked: String, within: BudgetFit) {
            self.asked = asked
            self.within = within
        }
    }

    public struct Source: Codable, Equatable, Sendable {
        public let title: String
        public let url: String
        public let site: String?

        public init(title: String, url: String, site: String? = nil) {
            self.title = title
            self.url = url
            self.site = site
        }
    }

    public let answer: String
    public let sections: [Section]
    public let recommendation: String?
    /// Left out when the user gave no budget.
    public let budget: Budget?
    public let next: [String]
    public let sources: [Source]
    public let checkedAt: String

    public init(answer: String, sections: [Section] = [], recommendation: String? = nil, budget: Budget? = nil,
                next: [String] = [], sources: [Source] = [], checkedAt: String) {
        self.answer = answer
        self.sections = sections
        self.recommendation = recommendation
        self.budget = budget
        self.next = next
        self.sources = sources
        self.checkedAt = checkedAt
    }

    private enum CodingKeys: String, CodingKey { case answer, sections, recommendation, budget, next, sources, checkedAt }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        answer = try c.decode(String.self, forKey: .answer)
        sections = try c.decodeIfPresent([Section].self, forKey: .sections) ?? []
        recommendation = try c.decodeIfPresent(String.self, forKey: .recommendation)
        budget = try c.decodeIfPresent(Budget.self, forKey: .budget)
        next = try c.decodeIfPresent([String].self, forKey: .next) ?? []
        sources = try c.decodeIfPresent([Source].self, forKey: .sources) ?? []
        checkedAt = try c.decode(String.self, forKey: .checkedAt)
    }

    /// `checkedAt` as a date, when it is one.
    public var checkedDate: Date? { ServerDates.parse(checkedAt) }
}

// MARK: - Stored on the iPhone

/// One errand as kept on the iPhone (DoddyPersistence, `v15_errands`). The result lives only here
/// once the server's copy is deleted after `ack`.
public struct StoredErrand: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var state: ErrandState
    public var draft: ErrandDraft
    public var result: ErrandResult?
    /// The digest the server gave for `result`; `ack` sends it back.
    public var resultDigest: String?
    public var failure: ErrandFailureCode?
    /// What the server reported deleting after `ack`.
    public var deletions: [ErrandDeletion]
    /// When the server answered `ack`. Set only after the result was saved here and the server said so.
    public var acknowledgedAt: Date?

    public init(id: UUID, createdAt: Date, state: ErrandState, draft: ErrandDraft, result: ErrandResult? = nil,
                resultDigest: String? = nil, failure: ErrandFailureCode? = nil, deletions: [ErrandDeletion] = [],
                acknowledgedAt: Date? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.state = state
        self.draft = draft
        self.result = result
        self.resultDigest = resultDigest
        self.failure = failure
        self.deletions = deletions
        self.acknowledgedAt = acknowledgedAt
    }

    public var title: String { draft.title }

    /// The row the app keeps once the approve request was answered (or wasn't): `queued` when the
    /// server said so, `unknown` when the answer never came back.
    public static func handedOver(_ preview: ErrandPreview, draft: ErrandDraft, approval: ErrandApproval, at now: Date) -> StoredErrand {
        StoredErrand(id: preview.id, createdAt: now, state: ErrandState(rawValue: approval.state) ?? .unknown, draft: draft)
    }

    /// The server's latest view, without losing what is kept here: a saved result is never cleared
    /// or replaced (after `ack` the server no longer has it), and a state this app doesn't know
    /// never overwrites a known one. A snapshot of another errand changes nothing.
    public func applying(_ snapshot: ErrandSnapshot, at now: Date) -> StoredErrand {
        guard snapshot.id == id else { return self }
        var next = self
        if snapshot.state != .unknown { next.state = snapshot.state }
        if next.result == nil, let ready = snapshot.readyResult {
            next.result = ready.result
            next.resultDigest = ready.digest
        }
        if snapshot.state == .failed { next.failure = snapshot.failure ?? .unknown }
        next.updatedAt = max(now, createdAt)
        return next
    }

    /// Saved here, not yet acknowledged: the server still holds its copy until `ack` succeeds.
    public var needsAcknowledgement: Bool { result != nil && resultDigest != nil && acknowledgedAt == nil }
}

public protocol ErrandRepository: Sendable {
    /// Inserts or replaces; returns what was read back.
    func save(_ record: StoredErrand) async throws -> StoredErrand
    /// Newest first.
    func list() async throws -> [StoredErrand]
    func get(_ id: UUID) async throws -> StoredErrand?
    func delete(_ id: UUID) async throws
    func deleteAll() async throws
    /// Everything kept about errands, for the user's own export.
    func export() async throws -> Data
}

public struct UnavailableErrandRepository: ErrandRepository {
    public init() {}
    public func save(_ record: StoredErrand) async throws -> StoredErrand { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func list() async throws -> [StoredErrand] { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func get(_ id: UUID) async throws -> StoredErrand? { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func delete(_ id: UUID) async throws { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func deleteAll() async throws { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func export() async throws -> Data { throw DoddyError.capabilityUnavailable(.memoryStorage) }
}

// MARK: - What the voice agent gets

/// `{{errands}}` at the start of a conversation: the newest tasks, one line each. Information only,
/// no instructions; the prompt puts it between the data markers, so the markers are removed from
/// inside each line. Deterministic for a given `now`.
public enum ErrandsPrompt {
    /// The placeholder in voice-agent/instructions.md and session.json.
    public static let variableName = "errands"
    public static let maxShown = 5
    public static let answerPreviewLength = 160
    /// What the agent gets when there are none.
    public static let none = "none"

    public static func render(_ errands: [StoredErrand], now: Date) -> String {
        guard !errands.isEmpty else { return none }
        let newest = errands.sorted(by: newestFirst)
        var lines = newest.prefix(maxShown).map { line($0, now: now) }
        let older = newest.count - maxShown
        if older > 0 { lines.append("(\(older) older task\(older == 1 ? "" : "s") not listed)") }
        return lines.joined(separator: "\n")
    }

    static func line(_ errand: StoredErrand, now: Date) -> String {
        var text = "- \"\(clip(errand.draft.title, ErrandDraft.maxTitle))\" (handed over \(age(errand.createdAt, now: now))): \(stateWords(errand))"
        if errand.state == .done, let answer = errand.result?.answer {
            text += ". Answer starts: \"\(clip(answer, answerPreviewLength))\""
        }
        return text
    }

    static func stateWords(_ errand: StoredErrand) -> String {
        switch errand.state {
        case .draft: "not handed over, no yes was given"
        case .queued, .running: "working on it"
        case .done: errand.result == nil ? "done, but the result isn't saved on this iPhone yet" : "done"
        case .failed: "couldn't finish: \((errand.failure ?? .unknown).shortReason)"
        case .cancelled: "cancelled"
        case .unknown: "not sure it started"
        }
    }

    /// Newest first; ties in a fixed order.
    static func newestFirst(_ a: StoredErrand, _ b: StoredErrand) -> Bool {
        a.createdAt != b.createdAt ? a.createdAt > b.createdAt : a.id.uuidString < b.id.uuidString
    }

    static func age(_ date: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        guard seconds >= 60 else { return "just now" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return count(minutes, "minute") + " ago" }
        let hours = minutes / 60
        if hours < 24 { return count(hours, "hour") + " ago" }
        return count(hours / 24, "day") + " ago"
    }

    private static func count(_ n: Int, _ unit: String) -> String { "\(n) \(unit)\(n == 1 ? "" : "s")" }

    /// One line, no data markers, at most `limit` characters (an ellipsis marks a cut).
    static func clip(_ text: String, _ limit: Int) -> String {
        let flat = ToolData.clean(text).trimmingCharacters(in: .whitespaces)
        guard flat.count > limit else { return flat }
        return String(flat.prefix(limit - 1)) + "…"
    }
}

/// What `check_errands` returns to the agent. The first line is the app's and starts with the
/// result word (`done:`, `working:`, `failed:`, `cancelled:`, or `unknown:` / `not started:`); the
/// user's words and everything the run found follow between the data markers, with the markers
/// removed from inside. Bounded: never longer than `maxCharacters`.
public enum ErrandResultText {
    public static let maxCharacters = 4_000
    /// How many tasks one `check_errands` reply reads out.
    public static let maxPerReply = 3
    static let maxLine = 400
    static let cutNote = "(Cut short: the rest is on the result card in the app.)"

    public static func forAgent(_ errand: StoredErrand, maxCharacters: Int = maxCharacters) -> String {
        var data = [
            "Title: \"\(ErrandsPrompt.clip(errand.draft.title, ErrandDraft.maxTitle))\"",
            "The user's words: \"\(ErrandsPrompt.clip(errand.draft.words, maxLine))\"",
            "Doddy's note: \"\(ErrandsPrompt.clip(errand.draft.brief, maxLine))\"",
        ]
        var footer: String?
        let header: String
        switch errand.state {
        case .done:
            if let result = errand.result {
                header = "done: Doddy finished the task below. What it found follows as data; times and prices are as they were when checked."
                data += lines(for: result)
                let count = result.sources.count
                footer = count == 0
                    ? "Sources: none listed."
                    : "Sources: \(count) page\(count == 1 ? "" : "s"), with links on the result card in the app."
            } else {
                header = "done: Doddy's server finished the task below, but the result isn't saved on this iPhone yet, so there is nothing to read out yet."
            }
        case .queued:
            header = "working: the task below is waiting to start on Doddy's server. Nothing found yet."
        case .running:
            header = "working: Doddy is still working on the task below in the background. Nothing found yet."
        case .failed:
            header = "failed: Doddy couldn't finish the task below. \((errand.failure ?? .unknown).explanation)"
        case .cancelled:
            header = "cancelled: the task below was cancelled. Nothing more is looked up for it."
        case .draft:
            header = "not started: the task below was never handed over, so nothing was looked up."
        case .unknown:
            header = "unknown: the app isn't sure the task below started. It may be running; it isn't handed over again by itself."
        }
        return bounded(header: header, data: data, footer: footer, maxCharacters: maxCharacters)
    }

    /// The whole `check_errands` reply: the tasks that match `about` (newest first), or the newest
    /// ones when nothing matches or nothing was asked; at most `maxPerReply`, within `maxCharacters`.
    public static func reply(_ errands: [StoredErrand], about: String?, maxCharacters: Int = maxCharacters) -> String {
        guard !errands.isEmpty else {
            return "none: the user hasn't handed Doddy any tasks on this iPhone, so there is nothing to read out."
        }
        let newest = errands.sorted(by: ErrandsPrompt.newestFirst)
        var picked = newest
        var lead: String?
        if let about, !about.isEmpty {
            let matching = newest.filter { matches($0, about: about) }
            if matching.isEmpty { lead = "No task matched what was asked; the newest ones follow." } else { picked = matching }
        }
        let chosen = Array(picked.prefix(maxPerReply))
        let more = picked.count - chosen.count
        let tail = more > 0 ? "(\(more) more not read out; they are in the app.)" : nil
        let fixed = [lead, tail].compactMap { $0 }.reduce(0) { $0 + $1.count + 2 }
        let share = max(200, (maxCharacters - fixed) / chosen.count - 2)
        let parts = [lead].compactMap { $0 } + chosen.map { forAgent($0, maxCharacters: share) } + [tail].compactMap { $0 }
        return parts.joined(separator: "\n\n")
    }

    /// A word of `about` (four letters or more, folded) whose stem appears in the task's title or words.
    static func matches(_ errand: StoredErrand, about: String) -> Bool {
        let haystack = PolishText.fold(errand.draft.title + " " + errand.draft.words)
        let words = PolishText.fold(about).components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count >= 4 }
        return words.contains { haystack.contains(String($0.prefix(max(3, $0.count - 2)))) }
    }

    static func lines(for result: ErrandResult) -> [String] {
        let clip = ErrandsPrompt.clip
        var out = ["Answer: \"\(clip(result.answer, 700))\""]
        for section in result.sections {
            let count = section.items.count
            out.append("Section \"\(clip(section.heading, 120))\" (\(kindWords(section.kind)), \(count) item\(count == 1 ? "" : "s")):")
            for item in section.items {
                var parts = ["- \"\(clip(item.title, 160))\""]
                if let when = item.when { parts.append("when: \(clip(when, 80))") }
                if let price = item.price { parts.append("price: \(clip(price, 80))") }
                if let site = item.site { parts.append("site: \(clip(site, 80))") }
                if let detail = item.detail { parts.append(clip(detail, 200)) }
                out.append(parts.joined(separator: " · "))
            }
        }
        if let recommendation = result.recommendation { out.append("Recommendation: \"\(clip(recommendation, maxLine))\"") }
        if let budget = result.budget {
            let within = switch budget.within {
            case .yes: "yes"
            case .no: "no"
            case .unknown: "not known"
            }
            out.append("Budget the user gave: \"\(clip(budget.asked, 160))\"; within it: \(within)")
        }
        if !result.next.isEmpty {
            out.append("Doddy could look next: " + result.next.map { "\"\(clip($0, 160))\"" }.joined(separator: "; "))
        }
        out.append("Checked: \(clip(result.checkedAt, 40))")
        return out
    }

    static func kindWords(_ kind: ErrandResult.SectionKind) -> String {
        switch kind {
        case .options: "options to compare"
        case .brief: "short research"
        case .checklist: "steps"
        case .places: "places"
        case .unknown: "list"
        }
    }

    /// Header, then as many data lines as fit, then the footer. A cut says so.
    static func bounded(header: String, data: [String], footer: String?, maxCharacters: Int) -> String {
        let headerPart = header + "\n" + ToolData.begin
        let closing = { (cut: Bool) -> String in
            ([ToolData.end] + [cut ? cutNote : nil, footer].compactMap { $0 }).joined(separator: "\n")
        }
        var kept: [String] = []
        var used = headerPart.count + 1 + closing(true).count
        var cut = false
        for line in data {
            guard used + line.count + 1 <= maxCharacters else {
                cut = true
                break
            }
            kept.append(line)
            used += line.count + 1
        }
        return ([headerPart] + kept + [closing(cut)]).joined(separator: "\n")
    }
}

extension VoiceToolReply {
    /// The server said it has the task (`queued`). The title follows as data.
    public static func errandStarted(_ draft: ErrandDraft) -> String {
        "started: Doddy's server has the task below and works on it in the background. It searches the web and reads pages as often as the task needs, and the user gets a notification when it's done. Nothing is booked, bought or sent. Tell the user they can close the app.\n"
            + ToolData.block([quoted("Title", draft.title)])
    }

    /// The approve request's answer never came back. Never approved again by itself.
    public static func errandMaybeStarted(_ draft: ErrandDraft) -> String {
        "unknown: the app couldn't confirm the task below started; it may be running. It won't be handed over again by itself. Tell the user to check their tasks in the app before handing it over again.\n"
            + ToolData.block([quoted("Title", draft.title)])
    }

    /// Creating or approving failed with an answer from the server, or never left the phone.
    public static func errandNotStarted(_ error: any Error) -> String {
        let said: (reason: String, next: String?) = switch error {
        case ErrandError.errandsDisabled:
            ("Doddy can't work on tasks in the background yet: it's switched off or not set up on Doddy's server.",
             "Offer to look it up now instead, asking before each search.")
        case ErrandError.tooManyOpenErrands:
            ("the user already has as many open tasks as Doddy's server allows.", "Offer to wait until one finishes, or to cancel one in the app.")
        case ErrandError.digestMismatch, ErrandError.notApprovable:
            ("the request expired or changed before it was approved.", "It can be handed over again with a new yes.")
        case ErrandError.previewMismatch:
            ("Doddy's server didn't hold exactly the words the user said yes to, so it wasn't approved.", nil)
        case ErrandError.invalid(let fields):
            ("Doddy's server refused the request" + (fields.isEmpty ? "." : " (\(fields.map(ToolData.clean).joined(separator: ", ")))."), nil)
        case ErrandError.server(.offline), ServerError.offline:
            ("Doddy's server couldn't be reached.", nil)
        case ErrandError.server(.rateLimited), ServerError.rateLimited:
            ("Doddy's server is busy right now.", nil)
        default:
            ("something went wrong on Doddy's server.", nil)
        }
        return (["failed: \(said.reason) Nothing was done."] + [said.next].compactMap { $0 }).joined(separator: "\n")
    }
}

// MARK: - Dates as the server writes them

extension KeyedDecodingContainer {
    fileprivate func serverDate(_ key: Key) throws -> Date {
        let text = try decode(String.self, forKey: key)
        guard let date = ServerDates.parse(text) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "not an ISO 8601 time")
        }
        return date
    }

    fileprivate func serverDateIfPresent(_ key: Key) throws -> Date? {
        guard let text = try decodeIfPresent(String.self, forKey: key) else { return nil }
        guard let date = ServerDates.parse(text) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "not an ISO 8601 time")
        }
        return date
    }
}
