import Foundation

// Calls Doddy places for the user (ADR-500..507, docs/decisions/calls.md). A case holds one brief,
// its attempts and the answer card. The server compiles the brief into the exact payload it will
// send and returns a preview made from it; the card shows that preview, and approval is bound to its
// digest. Rules here only give early hints on the iPhone: the server checks everything again.

public enum CaseKind: String, Codable, Sendable, CaseIterable {
    case call
}

/// Where the number came from; shown on the card next to it.
public enum CallNumberSource: String, Codable, Sendable, CaseIterable {
    case contacts, typed, note
}

/// What a fact is. PESEL and address facts are only ever sent when ticked as that kind.
public enum CallFactKind: String, Codable, Sendable, CaseIterable {
    case general, reference, date, device, contact, pesel, address
}

public struct CallFactDraft: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var kind: CallFactKind
    public var text: String
    /// Only ticked facts leave the iPhone.
    public var ticked: Bool

    public init(id: UUID = UUID(), kind: CallFactKind = .general, text: String, ticked: Bool = false) {
        self.id = id
        self.kind = kind
        self.text = text
        self.ticked = ticked
    }

    /// A new fact as typed: a PESEL or an address is recognised and left unticked.
    public static func suggested(_ text: String) -> CallFactDraft {
        if CallFactRules.containsPESEL(text) { return CallFactDraft(kind: .pesel, text: text, ticked: false) }
        if CallFactRules.looksLikeAddress(text) { return CallFactDraft(kind: .address, text: text, ticked: false) }
        return CallFactDraft(kind: .general, text: text, ticked: true)
    }
}

public enum CallBriefProblem: Equatable, Sendable {
    case missingCalleeName, missingPrincipal, missingGoal, missingQuestion
    case numberNotAllowed(PolishNumber.Refusal)
    case tooManyFacts
    /// A ticked fact holds a PESEL or an address but isn't ticked as that kind.
    case sensitiveFactKind(UUID)
    case peselFactInvalid(UUID)
    case braces
    case tooLong
}

public struct CallBriefDraft: Codable, Equatable, Sendable {
    public static let defaultMaxDuration = 240
    public static let maxDurationRange = 60...300
    public static let maxTickedFacts = 5

    public var calleeName: String
    public var phone: String
    public var source: CallNumberSource
    public var sourceLabel: String?
    public var principalName: String
    public var principalGenitive: String
    public var goal: String
    public var question: String
    public var facts: [CallFactDraft]
    public var maxDurationSecs: Int

    public init(calleeName: String = "", phone: String = "", source: CallNumberSource = .typed, sourceLabel: String? = nil,
                principalName: String = "", principalGenitive: String? = nil, goal: String = "", question: String = "",
                facts: [CallFactDraft] = [], maxDurationSecs: Int = CallBriefDraft.defaultMaxDuration) {
        self.calleeName = calleeName
        self.phone = phone
        self.source = source
        self.sourceLabel = sourceLabel
        self.principalName = principalName
        self.principalGenitive = principalGenitive ?? PolishGenitive.suggest(principalName)
        self.goal = goal
        self.question = question
        self.facts = facts
        self.maxDurationSecs = maxDurationSecs
    }

    public var tickedFacts: [CallFactDraft] { facts.filter(\.ticked) }

    /// Hints before sending; the server decides.
    public var problems: [CallBriefProblem] {
        var out: [CallBriefProblem] = []
        let trimmed = { (s: String) in s.trimmingCharacters(in: .whitespacesAndNewlines) }
        if trimmed(calleeName).isEmpty { out.append(.missingCalleeName) }
        if case .refused(let reason) = PolishNumber.classify(phone) { out.append(.numberNotAllowed(reason)) }
        if trimmed(principalName).isEmpty || trimmed(principalGenitive).isEmpty { out.append(.missingPrincipal) }
        if trimmed(goal).count < 3 { out.append(.missingGoal) }
        if trimmed(question).count < 5 { out.append(.missingQuestion) }
        if tickedFacts.count > Self.maxTickedFacts { out.append(.tooManyFacts) }
        if goal.count > 160 || question.count > 200 || calleeName.count > 80 || tickedFacts.contains(where: { $0.text.count > 160 }) {
            out.append(.tooLong)
        }
        let all = [calleeName, sourceLabel ?? "", principalName, principalGenitive, goal, question] + tickedFacts.map(\.text)
        if all.contains(where: { $0.contains("{") || $0.contains("}") }) { out.append(.braces) }
        for fact in tickedFacts {
            if fact.kind == .pesel {
                if !CallFactRules.containsPESEL(fact.text) { out.append(.peselFactInvalid(fact.id)) }
            } else if CallFactRules.containsPESEL(fact.text) || (fact.kind != .address && CallFactRules.looksLikeAddress(fact.text)) {
                out.append(.sensitiveFactKind(fact.id))
            }
        }
        return out
    }

    /// What is sent: ticked facts only. Unticked facts never leave the iPhone.
    public func requestBody() -> CallBriefBody {
        CallBriefBody(
            callee: .init(name: calleeName, phone: phone, source: source, sourceLabel: sourceLabel?.isEmpty == false ? sourceLabel : nil),
            principal: .init(name: principalName, genitive: principalGenitive),
            goal: goal, question: question,
            facts: tickedFacts.map { .init(kind: $0.kind, text: $0.text) },
            maxDurationSecs: maxDurationSecs)
    }
}

/// The body of `POST /v1/call-cases` (the server's strict schema).
public struct CallBriefBody: Encodable, Equatable, Sendable {
    public struct Callee: Encodable, Equatable, Sendable { public let name: String; public let phone: String; public let source: CallNumberSource; public let sourceLabel: String? }
    public struct Principal: Encodable, Equatable, Sendable { public let name: String; public let genitive: String }
    public struct Fact: Encodable, Equatable, Sendable { public let kind: CallFactKind; public let text: String }

    public var kind = "ask"
    public let callee: Callee
    public let principal: Principal
    public let goal: String
    public let question: String
    public let facts: [Fact]
    public let maxDurationSecs: Int
}

// MARK: - Rules mirrored from the server (hints only)

/// Polish numbers Doddy may call (v1): mobile, geographic and 800. The server's allowlist
/// (server/messaging/src/taskCalls/phone.ts) decides; this only warns early.
public enum PolishNumber {
    public enum Kind: String, Sendable { case mobile, geographic, freephone }
    public enum Refusal: String, Sendable { case notANumber, shortNumber, foreign, premium, sharedCost, special, unknownRange }
    public enum Result: Equatable, Sendable { case allowed(e164: String, kind: Kind), refused(Refusal) }

    public static let mobilePrefixes: Set<String> = ["45", "50", "51", "53", "57", "60", "66", "69", "72", "73", "78", "79", "88"]
    public static let geographicPrefixes: Set<String> = [
        "12", "13", "14", "15", "16", "17", "18", "22", "23", "24", "25", "29", "32", "33", "34", "41", "42", "43", "44",
        "46", "48", "52", "54", "55", "56", "58", "59", "61", "62", "63", "65", "67", "68", "71", "74", "75", "76", "77",
        "81", "82", "83", "84", "85", "86", "87", "89", "91", "94", "95",
    ]

    public static func classify(_ input: String) -> Result {
        let compact = input.trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { !" -.()/\u{00A0}".contains($0) }
        guard !compact.isEmpty, compact.count <= 40,
              compact.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "+") }),
              compact.dropFirst().allSatisfy(\.isNumber) else { return .refused(.notANumber) }
        let national: String
        if compact.hasPrefix("+") {
            guard compact.hasPrefix("+48") else { return .refused(.foreign) }
            national = String(compact.dropFirst(3))
        } else if compact.hasPrefix("00") {
            guard compact.hasPrefix("0048") else { return .refused(.foreign) }
            national = String(compact.dropFirst(4))
        } else if compact.count == 11, compact.hasPrefix("48") {
            national = String(compact.dropFirst(2))
        } else {
            national = compact
        }
        if national.count < 9 { return .refused(national.isEmpty ? .notANumber : .shortNumber) }
        if national.count > 9 { return .refused(.notANumber) }
        let two = String(national.prefix(2)), three = String(national.prefix(3))
        if three == "800" { return .allowed(e164: "+48" + national, kind: .freephone) }
        if two == "70" { return .refused(.premium) }
        if three == "801" || three == "804" { return .refused(.sharedCost) }
        if ["80", "39", "64", "26", "47"].contains(two) { return .refused(.special) }
        if mobilePrefixes.contains(two) { return .allowed(e164: "+48" + national, kind: .mobile) }
        if geographicPrefixes.contains(two) { return .allowed(e164: "+48" + national, kind: .geographic) }
        return .refused(.unknownRange)
    }
}

public enum CallFactRules {
    /// Runs of digits joined across single spaces or hyphens.
    public static func digitGroups(_ text: String) -> [String] {
        var groups: [String] = []
        var current = ""
        var pendingSeparator = false
        for ch in text {
            if ch.isASCII && ch.isNumber {
                current.append(ch)
                pendingSeparator = false
            } else if (ch == " " || ch == "-") && !current.isEmpty && !pendingSeparator {
                pendingSeparator = true
            } else {
                if !current.isEmpty { groups.append(current) }
                current = ""
                pendingSeparator = false
            }
        }
        if !current.isEmpty { groups.append(current) }
        return groups
    }

    /// 11 digits, valid checksum, a month and day that can exist (same rule as the server).
    public static func isPESEL(_ d: String) -> Bool {
        let digits = d.compactMap(\.wholeNumberValue)
        guard d.count == 11, digits.count == 11 else { return false }
        let weights = [1, 3, 7, 9, 1, 3, 7, 9, 1, 3]
        let sum = zip(weights, digits).map(*).reduce(0, +)
        guard (10 - sum % 10) % 10 == digits[10] else { return false }
        let month = (digits[2] * 10 + digits[3]) % 20
        let day = digits[4] * 10 + digits[5]
        return (1...12).contains(month) && (1...31).contains(day)
    }

    public static func containsPESEL(_ text: String) -> Bool { digitGroups(text).contains(where: isPESEL) }

    public static func looksLikeAddress(_ text: String) -> Bool {
        let folded = PolishText.fold(text)
        if text.range(of: #"\b\d{2}-\d{3}\b"#, options: .regularExpression) != nil { return true }
        if folded.range(of: #"\b(ul|al|os|pl)\.\s*\p{L}"#, options: .regularExpression) != nil { return true }
        return folded.range(of: #"\b(ulica|ulicy|aleja|alei|osiedle|mieszkania|mieszkanie)\b"#, options: .regularExpression) != nil
    }
}

public enum PolishText {
    /// Lower case without diacritics (ł → l), for matching words.
    public static func fold(_ text: String) -> String {
        text.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "pl_PL")).replacingOccurrences(of: "ł", with: "l")
    }
}

/// A suggestion for "w imieniu …" (genitive). Polish names are irregular, so the user can edit it.
public enum PolishGenitive {
    public static func suggest(_ name: String) -> String {
        let first = name.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").first.map(String.init) ?? ""
        guard first.count >= 2 else { return first }
        let lower = first.lowercased()
        func replacing(_ suffixCount: Int, with ending: String) -> String { String(first.dropLast(suffixCount)) + ending }
        if lower.hasSuffix("ia") { return replacing(1, with: "i") }                       // Maria → Marii
        if lower.hasSuffix("aja") || lower.hasSuffix("oja") || lower.hasSuffix("eja") { return replacing(2, with: "i") } // Maja → Mai
        if lower.hasSuffix("ka") || lower.hasSuffix("ga") { return replacing(1, with: "i") } // Monika → Moniki
        if lower.hasSuffix("a") { return replacing(1, with: "y") }                         // Anna → Anny
        if lower.hasSuffix("ek") { return replacing(2, with: "ka") }                       // Marek → Marka
        if lower.hasSuffix("eł") { return replacing(2, with: "ła") }                       // Paweł → Pawła
        if lower.hasSuffix("y") { return replacing(1, with: "ego") }                      // Jerzy → Jerzego
        if lower.hasSuffix("i") { return first + "ego" }                                   // Antoni → Antoniego
        if lower.hasSuffix("e") || lower.hasSuffix("o") || lower.hasSuffix("u") { return first }
        return first + "a"                                                                  // Patryk → Patryka
    }
}

/// Calling hours: the whole call must fit inside 8:00–23:00 Warsaw time (server/…/hours.ts).
public enum CallHours {
    public static let ringSecs = 25
    public static let graceSecs = 20
    public static var warsaw: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return c
    }

    public static func fits(_ start: Date, maxDurationSecs: Int) -> Bool {
        let end = start.addingTimeInterval(TimeInterval(ringSecs + maxDurationSecs + graceSecs))
        let cal = warsaw
        guard cal.isDate(start, inSameDayAs: end) else { return false }
        let s = cal.dateComponents([.hour, .minute, .second], from: start)
        let e = cal.dateComponents([.hour, .minute, .second], from: end)
        let secs = { (c: DateComponents) in (c.hour ?? 0) * 3600 + (c.minute ?? 0) * 60 + (c.second ?? 0) }
        return secs(s) >= 8 * 3600 && secs(e) <= 23 * 3600
    }

    /// Times offered for "Zadzwoń ponownie o …": in an hour (rounded up to a quarter), then 9:00,
    /// 12:00 and 16:00 on the next days, only those where the whole call fits.
    public static func retrySuggestions(after now: Date, maxDurationSecs: Int, count: Int = 4) -> [Date] {
        let cal = warsaw
        var out: [Date] = []
        let inAnHour = now.addingTimeInterval(3600)
        let minute = cal.component(.minute, from: inAnHour)
        if let rounded = cal.date(byAdding: .minute, value: (15 - minute % 15) % 15, to: inAnHour),
           let clean = cal.date(bySetting: .second, value: 0, of: rounded), fits(clean, maxDurationSecs: maxDurationSecs) {
            out.append(clean)
        }
        var day = cal.startOfDay(for: now)
        while out.count < count {
            for hour in [9, 12, 16] {
                guard out.count < count, let t = cal.date(bySettingHour: hour, minute: 0, second: 0, of: day),
                      t > now.addingTimeInterval(600), fits(t, maxDurationSecs: maxDurationSecs), !out.contains(t) else { continue }
                out.append(t)
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
            if out.isEmpty && day > now.addingTimeInterval(7 * 86_400) { break }
        }
        return out.sorted()
    }
}

// MARK: - What the server returns

public struct CallPreview: Codable, Equatable, Sendable {
    public struct Callee: Codable, Equatable, Sendable {
        public let name: String
        public let phone: String
        public let destinationKind: String
        public let source: CallNumberSource
        public let sourceLabel: String?
    }
    public struct Principal: Codable, Equatable, Sendable { public let name: String; public let genitive: String }
    public struct Fact: Codable, Equatable, Sendable { public let kind: CallFactKind; public let text: String }

    public let caseId: UUID
    /// The digest the approval is bound to.
    public let digest: String
    public let approvableUntil: String
    public let callee: Callee
    public let principal: Principal
    public let goal: String
    /// Spoken word for word, first.
    public let openingLine: String
    public let question: String
    public let facts: [Fact]
    public let forbidden: [String]
    public let callbackLine: String
    public let maxDurationSecs: Int
    public let notice: String
    public let recordsAudio: Bool
    /// Only on create: whether the call would fit inside the hours right now.
    public let callableNow: Bool?
}

public struct CallCaseAvailability: Decodable, Equatable, Sendable {
    public let available: Bool
    public let configured: Bool
    public let killSwitch: Bool
    public let phoneVerified: Bool
    public let recordingNotice: String
    public let recordsAudio: Bool
    public let maxDurationSecs: Int
    public let agentProblems: [String]
}

public struct CallApproval: Equatable, Sendable {
    /// Nil when the server's answer never reached the phone.
    public let attemptId: UUID?
    /// `dialing`, `scheduled`, or `unknown` (the call may be ringing; Doddy won't redial).
    public let state: String

    public init(attemptId: UUID?, state: String) {
        self.attemptId = attemptId
        self.state = state
    }
}

public enum CallPhase: String, Codable, Sendable {
    case scheduled, ringing, connecting, talking, takenOver = "taken_over", ending, ended, unknown

    public init(from decoder: any Decoder) throws {
        self = CallPhase(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }

    /// Whether "Przejmij" and "Zakończ" make sense now.
    public var canTakeOver: Bool { self == .talking }
    public var canEnd: Bool { [.ringing, .connecting, .talking].contains(self) }
    public var isLive: Bool { [.ringing, .connecting, .talking, .takenOver, .ending].contains(self) }
}

public struct CallLiveLine: Codable, Equatable, Sendable, Identifiable {
    public let key: String
    public let speaker: String
    public let text: String
    public var id: String { key }
    public var isDoddy: Bool { speaker == "doddy" }
}

public struct CallLiveView: Decodable, Equatable, Sendable {
    public struct Attempt: Decodable, Equatable, Sendable {
        public struct Takeover: Decodable, Equatable, Sendable { public let state: String }
        public let id: UUID
        public let attemptNo: Int
        public let phase: CallPhase
        public let answeredAt: String?
        public let hangupDueAt: String?
        public let endedAt: String?
        public let endReason: String?
        public let takenOverAt: String?
        public let takeover: Takeover?
    }
    public let attempt: Attempt?
    public let lines: [CallLiveLine]
    public let cursor: String?
}

public enum CallOutcome: String, Codable, Sendable {
    case answered, noAnswer = "no_answer", busy, failed, notPlaced = "not_placed", voicemail, ivr, wrongNumber = "wrong_number"
    case noConversation = "no_conversation", takenOver = "taken_over", voiceUnavailable = "voice_unavailable", stopped, unknown

    public init(from decoder: any Decoder) throws {
        self = CallOutcome(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }

    /// A failed call can be retried at a set time (a new approval).
    public var isRetryable: Bool { [.noAnswer, .busy, .failed, .notPlaced, .voicemail, .ivr, .wrongNumber, .voiceUnavailable, .unknown].contains(self) }
}

public enum CallConfidence: String, Codable, Sendable {
    case high, medium, low, none
}

/// The answer card, as built by the server (quote always cut from the transcript).
public struct CallResultCard: Codable, Equatable, Sendable {
    public struct Quote: Codable, Equatable, Sendable { public let text: String; public let line: Int }
    public struct Line: Codable, Equatable, Sendable { public let speaker: String; public let text: String; public let atSecs: Double? }
    public struct NextStep: Codable, Equatable, Sendable { public let kind: String; public let text: String }
    public struct Warning: Codable, Equatable, Sendable { public let kind: String; public let line: Int }

    public let outcome: CallOutcome
    public let source: String
    public let confidence: CallConfidence
    public let confidenceReasons: [String]
    public let summary: String
    public let summaryBy: String
    public let quote: Quote?
    public let transcript: [Line]
    public let nextStep: NextStep
    public let warnings: [Warning]
    public let callbackPromised: Bool
    public let takenOverAtSecs: Double?
    public let durationSecs: Double?
}

public struct CaseCost: Codable, Equatable, Sendable {
    public struct Item: Codable, Equatable, Sendable {
        public let component: String
        public let ref: String
        public let status: String
        public let amountMicros: Int64?
        public let currency: String?
        public let quantity: Double?
        public let unit: String?
    }
    public let currency: String
    public let totalMicros: Int64
    public let complete: Bool
    public let approximate: Bool
    public let pending: Bool
    public let unknownParts: [String]
    public let items: [Item]

    /// e.g. "0.0423 USD", "≈ 0.0423 USD", plus whether a part is still unknown. Never shows an
    /// unknown part as zero.
    public var amountText: String {
        let amount = String(format: "%.4f", Double(totalMicros) / 1_000_000)
        return "\(approximate ? "≈ " : "")\(amount) \(currency)"
    }
}

public struct DeletionReceipt: Codable, Equatable, Sendable, Identifiable {
    public let item: String
    public let location: String
    public let reason: String
    public let result: String
    public let requestedAt: String
    public let settledAt: String?
    public let rows: Int?
    public var id: String { "\(location):\(item):\(requestedAt)" }
    public var isConfirmed: Bool { result == "deleted" || result == "not_found" }
}

public struct CallCaseSnapshot: Decodable, Equatable, Sendable {
    public struct Attempt: Decodable, Equatable, Sendable {
        public let id: UUID
        public let attemptNo: Int
        public let state: String
        public let phase: CallPhase
        public let endReason: String?
    }
    public struct Result: Decodable, Equatable, Sendable {
        public let attemptId: UUID
        public let state: String
        public let outcome: CallOutcome?
        public let confidence: CallConfidence?
        public let resultDigest: String?
        public let result: CallResultCard?
    }
    public let caseId: UUID
    public let state: String
    public let approvableUntil: String
    public let preview: CallPreview?
    public let attempts: [Attempt]
    public let results: [Result]
    public let cost: CaseCost
    public let deletions: [DeletionReceipt]

    /// The newest result the server has built and still holds.
    public var readyResult: Result? { results.last(where: { $0.state == "ready" && $0.result != nil && $0.resultDigest != nil }) }
}

// MARK: - Stored on the iPhone

/// One call case as kept on the iPhone (DoddyPersistence, `v14_call_cases`). The transcript lives
/// only here once the server's copy is deleted.
public struct StoredCallCase: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let kind: CaseKind
    public var createdAt: Date
    public var updatedAt: Date
    public var state: String
    public var brief: CallBriefDraft
    public var preview: CallPreview?
    public var resultAttemptId: UUID?
    public var result: CallResultCard?
    public var cost: CaseCost?
    public var deletions: [DeletionReceipt]

    public init(id: UUID, createdAt: Date, state: String, brief: CallBriefDraft, preview: CallPreview? = nil,
                resultAttemptId: UUID? = nil, result: CallResultCard? = nil, cost: CaseCost? = nil, deletions: [DeletionReceipt] = []) {
        self.id = id
        self.kind = .call
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.state = state
        self.brief = brief
        self.preview = preview
        self.resultAttemptId = resultAttemptId
        self.result = result
        self.cost = cost
        self.deletions = deletions
    }

    public var title: String { brief.calleeName }
}

public protocol CallCaseRepository: Sendable {
    /// Inserts or replaces; returns what was read back.
    func save(_ record: StoredCallCase) async throws -> StoredCallCase
    func list() async throws -> [StoredCallCase]
    func get(_ id: UUID) async throws -> StoredCallCase?
    func delete(_ id: UUID) async throws
    func deleteAll() async throws
    func export() async throws -> Data
}

public struct UnavailableCallCaseRepository: CallCaseRepository {
    public init() {}
    public func save(_ record: StoredCallCase) async throws -> StoredCallCase { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func list() async throws -> [StoredCallCase] { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func get(_ id: UUID) async throws -> StoredCallCase? { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func delete(_ id: UUID) async throws { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func deleteAll() async throws { throw DoddyError.capabilityUnavailable(.memoryStorage) }
    public func export() async throws -> Data { throw DoddyError.capabilityUnavailable(.memoryStorage) }
}

/// For the cost-per-outcome gate: what calls cost, and what an answered call cost on average.
/// Cases with any unknown cost part are counted separately, never averaged in as zero.
public struct CostPerOutcome: Equatable, Sendable {
    public let cases: Int
    public let answered: Int
    public let knownTotalMicros: Int64
    public let casesWithUnknownCost: Int
    /// Total known cost divided by answered calls; nil when there are none or a cost is unknown.
    public let perAnsweredMicros: Int64?

    public static func summarize(_ cases: [StoredCallCase]) -> CostPerOutcome {
        let costed = cases.filter { $0.cost != nil }
        let unknown = costed.filter { !($0.cost!.complete) }.count
        let total = costed.reduce(Int64(0)) { $0 + $1.cost!.totalMicros }
        let answered = cases.filter { $0.result?.outcome == .answered }.count
        return CostPerOutcome(cases: cases.count, answered: answered, knownTotalMicros: total, casesWithUnknownCost: unknown,
                              perAnsweredMicros: answered > 0 && unknown == 0 ? total / Int64(answered) : nil)
    }
}
