import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

// Studio (S0, ADR-584, docs/implementation/STUDIO.md): "research X" becomes a research brief (PDF)
// and an infographic, made in the background by Doddy's messaging server and kept there until the
// user deletes them. The app shows one ask card for a typed job (never a free-form prompt); on a
// yes it creates the job on the server and approves it with the digest of exactly that job. That
// one yes covers the job's web look-ups (capped on the server) and the making of its files in
// Anthropic's container, and nothing else: nothing is published, booked, bought or sent.
//
// As in the rest of the client: nothing here says started, ready or deleted unless the server said
// so, and "unknown" is never success.

// MARK: - The job (what the user said yes to)

/// The typed job the app sends. Strings are trimmed at the ends and otherwise kept exactly; an
/// empty optional string or an empty source list is left out, never sent as "" or [].
public struct StudioJob: Codable, Equatable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// A research brief (PDF) and an infographic: the one kind in S0.
        case brief
        /// A kind this version of the app doesn't know. Never sent.
        case unknown

        public init(from decoder: any Decoder) throws {
            self = Kind(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }
    }

    public enum Length: String, Codable, Sendable, CaseIterable {
        /// About one page.
        case short
        /// Two to three pages.
        case standard
        /// Four to six pages.
        case long
    }

    public enum Style: String, Codable, Sendable, CaseIterable {
        case plain, lively
    }

    /// A page the user picked to start from.
    public struct Source: Codable, Equatable, Hashable, Sendable {
        public let url: String
        public let title: String

        public init(url: String, title: String) {
            self.url = url.trimmingCharacters(in: .whitespacesAndNewlines)
            self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    public static let maxTopic = 300
    public static let maxAudience = 120
    public static let maxDetails = 1_000
    public static let maxSources = 5
    public static let maxSourceTitle = 200
    public static let maxURL = 2_048
    public static let defaultLanguage = "pl"

    public let kind: Kind
    /// What to research, as the user said it.
    public let topic: String
    public let audience: String?
    public let length: Length
    public let style: Style
    /// A two-letter language code, lower case: the language the files are written in.
    public let language: String
    /// The user's own words about what they want. Data in every prompt, never instructions.
    public let details: String?
    public let sources: [Source]?

    public init(kind: Kind = .brief, topic: String, audience: String? = nil, length: Length = .standard, style: Style = .plain,
                language: String = StudioJob.defaultLanguage, details: String? = nil, sources: [Source]? = nil) {
        self.kind = kind
        self.topic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        self.audience = Self.optional(audience)
        self.length = length
        self.style = style
        self.language = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.details = Self.optional(details)
        self.sources = (sources?.isEmpty ?? true) ? nil : sources
    }

    private static func optional(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// Hints before sending, in a fixed order; the server checks the same limits again and decides.
    /// Lengths count UTF-16 units, as the server's schema does (JavaScript string length).
    public func validationIssues() -> [StudioJobIssue] {
        var issues: [StudioJobIssue] = []
        if kind != .brief { issues.append(.unknownKind) }
        if topic.isEmpty { issues.append(.missingTopic) } else if topic.utf16.count > Self.maxTopic { issues.append(.topicTooLong) }
        if let audience, audience.utf16.count > Self.maxAudience { issues.append(.audienceTooLong) }
        if !ErrandDraft.isLanguageCode(language) { issues.append(.languageNotACode) }
        if let details, details.utf16.count > Self.maxDetails { issues.append(.detailsTooLong) }
        if let sources {
            if sources.count > Self.maxSources { issues.append(.tooManySources) }
            if sources.contains(where: { !Self.isWebAddress($0.url) }) { issues.append(.sourceNotAWebAddress) }
            if sources.contains(where: { $0.url.utf16.count > Self.maxURL }) { issues.append(.sourceAddressTooLong) }
            if sources.contains(where: { $0.title.isEmpty }) { issues.append(.missingSourceTitle) }
            if sources.contains(where: { $0.title.utf16.count > Self.maxSourceTitle }) { issues.append(.sourceTitleTooLong) }
        }
        return issues
    }

    public var isValid: Bool { validationIssues().isEmpty }

    /// `http://` or `https://` (lower case), then something, and no white space anywhere, as the
    /// server's schema says (`/^https?:\/\/\S+$/`).
    static func isWebAddress(_ text: String) -> Bool {
        let rest: Substring
        if text.hasPrefix("https://") { rest = text.dropFirst(8) } else if text.hasPrefix("http://") { rest = text.dropFirst(7) } else { return false }
        return !rest.isEmpty && !text.unicodeScalars.contains { CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    /// The canonical JSON the digest is over: keys sorted at every level, no spaces, strings as
    /// JavaScript's JSON.stringify writes them, optional fields left out, sources in their order
    /// (server/messaging `canonicalJson`, docs/implementation/STUDIO.md "The job").
    public var canonicalJSON: String {
        let string = ErrandDraft.jsonString
        var fields: [(String, String)] = [
            ("kind", string(kind.rawValue)),
            ("language", string(language)),
            ("length", string(length.rawValue)),
            ("style", string(style.rawValue)),
            ("topic", string(topic)),
        ]
        if let audience { fields.append(("audience", string(audience))) }
        if let details { fields.append(("details", string(details))) }
        if let sources {
            let list = sources.map { "{\"title\":\(string($0.title)),\"url\":\(string($0.url))}" }
            fields.append(("sources", "[" + list.joined(separator: ",") + "]"))
        }
        // Every key is plain ASCII, so a byte-wise sort is the server's sort.
        let body = fields.sorted { $0.0 < $1.0 }.map { "\(string($0.0)):\($0.1)" }
        return "{" + body.joined(separator: ",") + "}"
    }

    /// SHA-256 (hex, lower case) of `canonicalJSON`: what the approval is bound to.
    public var digest: String {
        SHA256.hash(data: Data(canonicalJSON.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

public enum StudioJobIssue: Equatable, Sendable {
    case unknownKind, missingTopic, topicTooLong, audienceTooLong, languageNotACode, detailsTooLong
    case tooManySources, sourceNotAWebAddress, sourceAddressTooLong, missingSourceTitle, sourceTitleTooLong

    /// For the agent, in the style of the other tools' `invalid` reasons.
    public var reason: String {
        switch self {
        case .unknownKind: "kind must be brief (a research brief and an infographic)"
        case .missingTopic: "missing topic"
        case .topicTooLong: "topic is longer than \(StudioJob.maxTopic) characters"
        case .audienceTooLong: "audience is longer than \(StudioJob.maxAudience) characters"
        case .languageNotACode: "language must be a two-letter code such as pl or en"
        case .detailsTooLong: "details is longer than \(StudioJob.maxDetails) characters"
        case .tooManySources: "at most \(StudioJob.maxSources) sources"
        case .sourceNotAWebAddress: "a source must be an http or https address"
        case .sourceAddressTooLong: "a source address is longer than \(StudioJob.maxURL) characters"
        case .missingSourceTitle: "a source is missing its title"
        case .sourceTitleTooLong: "a source title is longer than \(StudioJob.maxSourceTitle) characters"
        }
    }
}

extension VoiceToolRequest {
    /// `{kind?, topic, audience?, length?, style?, details?, language?}`. Missing, unknown or too
    /// long is refused, never cut or guessed: the agent hears why and asks the user.
    static func parseMakeSomething(_ args: Arguments, name: String) -> VoiceToolRequest {
        var problems: [String] = []
        let kindText = args.text("kind")?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? StudioJob.Kind.brief.rawValue
        let kind = StudioJob.Kind(rawValue: kindText).flatMap { $0 == .unknown ? nil : $0 }
        if kind == nil { problems.append(StudioJobIssue.unknownKind.reason) }
        let lengthText = args.text("length")?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let length = lengthText.map { StudioJob.Length(rawValue: $0) } ?? .standard
        if length == nil { problems.append("length must be short, standard or long") }
        let styleText = args.text("style")?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let style = styleText.map { StudioJob.Style(rawValue: $0) } ?? .plain
        if style == nil { problems.append("style must be plain or lively") }
        let job = StudioJob(
            kind: kind ?? .unknown, topic: args.text("topic") ?? "", audience: args.text("audience"),
            length: length ?? .standard, style: style ?? .plain,
            language: args.text("language") ?? StudioJob.defaultLanguage, details: args.text("details"))
        problems += job.validationIssues().filter { $0 != .unknownKind }.map(\.reason)
        guard problems.isEmpty else { return .invalid(name: name, reason: problems.joined(separator: "; ")) }
        return .makeSomething(job)
    }
}

// MARK: - The ask (ASK-01, ADR-584)

/// The card for `make_something`. It changes nothing on the iPhone or in an account, so a spoken
/// yes or a tap answers it (ASK-01's read rule). It shows the whole job, where it goes and what
/// isn't zero-retention, in the language the files will be written in.
public enum StudioAsk {
    public static func card(_ job: StudioJob) -> AskCard {
        job.language == "pl" ? polish(job) : english(job)
    }

    private static func english(_ job: StudioJob) -> AskCard {
        var lines = ["Research \u{201C}\(job.topic)\u{201D} on the web and make a research brief (PDF) and an infographic."]
        if let details = job.details { lines.append("Your words: \u{201C}\(details)\u{201D}") }
        var shape = [] as [String]
        if let audience = job.audience { shape.append("For: \(audience)") }
        shape.append("Length: \(lengthWords(job.length, polish: false))")
        shape.append("Style: \(job.style == .plain ? "plain" : "lively")")
        lines.append(shape.joined(separator: " · "))
        for source in job.sources ?? [] { lines.append("Start from: \(source.title) (\(host(source.url)))") }
        lines.append("Your topic goes to Anthropic (Claude), which searches the web and makes the files. Anthropic keeps this work under its normal retention: code execution isn't zero-retention.")
        lines.append("It takes a few minutes. Nothing is published or sent anywhere.")
        return AskCard(title: "Make this with Doddy?", lines: lines, confirmLabel: "Allow", declineLabel: "Not now")
    }

    private static func polish(_ job: StudioJob) -> AskCard {
        var lines = ["Doddy poszuka w sieci informacji o \u{201E}\(job.topic)\u{201D} i przygotuje raport (PDF) oraz infografikę."]
        if let details = job.details { lines.append("Twoje słowa: \u{201E}\(details)\u{201D}") }
        var shape = [] as [String]
        if let audience = job.audience { shape.append("Dla: \(audience)") }
        shape.append("Długość: \(lengthWords(job.length, polish: true))")
        shape.append("Styl: \(job.style == .plain ? "prosty" : "żywy")")
        lines.append(shape.joined(separator: " · "))
        for source in job.sources ?? [] { lines.append("Zacznij od: \(source.title) (\(host(source.url)))") }
        lines.append("Temat trafia do Anthropic (Claude), który przeszukuje sieć i tworzy pliki. Anthropic przechowuje tę pracę według swoich zwykłych zasad: wykonywanie kodu nie jest objęte zerową retencją.")
        lines.append("To potrwa kilka minut. Nic nie zostanie opublikowane ani nigdzie wysłane.")
        return AskCard(title: "Przygotować to z Doddym?", lines: lines, confirmLabel: "Zezwól", declineLabel: "Nie teraz")
    }

    static func lengthWords(_ length: StudioJob.Length, polish: Bool) -> String {
        switch (length, polish) {
        case (.short, false): "short, about a page"
        case (.standard, false): "standard, two to three pages"
        case (.long, false): "long, four to six pages"
        case (.short, true): "krótki, około strony"
        case (.standard, true): "standardowy, dwie–trzy strony"
        case (.long, true): "długi, cztery–sześć stron"
        }
    }

    static func host(_ url: String) -> String {
        URL(string: url)?.host ?? url
    }
}

// MARK: - States and failures

/// The item's state as the server reports it (docs/implementation/STUDIO.md "Item states").
public enum StudioItemState: String, Codable, Sendable, CaseIterable {
    case queued, researching, making, checking, ready
    /// Its files failed the code checks twice; kept with the checks, never shown as ready.
    case needsLook = "needs_look"
    case failed, cancelled
    /// A state this version of the app doesn't know, or an approval whose answer never came back.
    /// Never read as success.
    case unknown

    public init(from decoder: any Decoder) throws {
        self = StudioItemState(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }

    /// Queued or working on the server.
    public var isOpen: Bool { [.queued, .researching, .making, .checking].contains(self) }
    public var isFinished: Bool { [.ready, .needsLook, .failed, .cancelled].contains(self) }

    public func label(_ language: NotificationLanguage) -> String {
        let polish = language == .polish
        switch self {
        case .queued: return polish ? "Czeka na start" : "Waiting to start"
        case .researching: return polish ? "Szuka w sieci" : "Researching"
        case .making: return polish ? "Tworzy pliki" : "Making the files"
        case .checking: return polish ? "Sprawdza pliki" : "Checking the files"
        case .ready: return polish ? "Gotowe" : "Ready"
        case .needsLook: return polish ? "Wymaga przejrzenia" : "Needs a look"
        case .failed: return polish ? "Nie udało się" : "Couldn't finish"
        case .cancelled: return polish ? "Anulowane" : "Cancelled"
        case .unknown: return polish ? "Nie wiadomo, czy ruszyło" : "Not sure it started"
        }
    }
}

/// Why a job ended as `failed` (the server's codes).
public enum StudioFailureCode: String, Codable, Sendable, CaseIterable {
    /// The worker stopped mid-run. It is never re-run by itself.
    case interrupted
    case timeLimit = "time_limit"
    /// The model declined.
    case refused
    case providerError = "provider_error"
    case unreadableResult = "unreadable_result"
    /// Fewer than three claims with a source the research really saw.
    case tooLittleFound = "too_little_found"
    /// The job passed its own spending limit.
    case costLimit = "cost_limit"
    case unknown

    public init(from decoder: any Decoder) throws {
        self = StudioFailureCode(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }

    public func explanation(_ language: NotificationLanguage) -> String {
        let polish = language == .polish
        switch self {
        case .interrupted:
            return polish ? "Serwer Doddy’ego zatrzymał się w trakcie. Nie rusza ponownie sam; poproś jeszcze raz, jeśli nadal tego chcesz."
                : "Doddy's server stopped in the middle. It isn't started again by itself; ask again if you still want it."
        case .timeLimit:
            return polish ? "Trwało dłużej niż limit czasu, więc Doddy przerwał." : "It took longer than the time limit, so Doddy stopped it."
        case .refused:
            return polish ? "Model AI, którego używa Doddy, odmówił pracy nad tym." : "The AI model Doddy uses declined to work on this."
        case .providerError:
            return polish ? "Usługa AI, której używa Doddy, miała problem." : "The AI service Doddy uses had a problem."
        case .unreadableResult:
            return polish ? "Doddy nie umiał zamienić wyników w treść, którą da się sprawdzić, więc nic nie pokazuje."
                : "Doddy couldn't turn what it found into content it could check, so nothing is shown."
        case .tooLittleFound:
            return polish ? "W sieci znalazło się za mało informacji ze sprawdzalnym źródłem." : "The research found too little with a source it could check."
        case .costLimit:
            return polish ? "Zadanie przekroczyło swój limit kosztów, więc Doddy przerwał." : "The job went past its own spending limit, so Doddy stopped it."
        case .unknown:
            return polish ? "Zatrzymało się z powodu, którego ta wersja aplikacji nie zna." : "It stopped for a reason this version of the app doesn't know."
        }
    }
}

// MARK: - What the server returns

/// `201` from `POST /v1/studio`: a draft, nothing runs. The approval is bound to `digest`.
public struct StudioPreview: Decodable, Equatable, Sendable {
    public let id: UUID
    public let digest: String
    public let job: StudioJob
    public let expiresAt: Date

    public init(id: UUID, digest: String, job: StudioJob, expiresAt: Date) {
        self.id = id
        self.digest = digest
        self.job = job
        self.expiresAt = expiresAt
    }

    private enum CodingKeys: String, CodingKey { case id, digest, job, expiresAt }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        digest = try c.decode(String.self, forKey: .digest)
        job = try c.decode(StudioJob.self, forKey: .job)
        expiresAt = try c.studioDate(.expiresAt)
    }

    /// The server holds exactly the job the user said yes to, and its digest is for exactly that.
    /// Anything else is never approved.
    public func matches(_ job: StudioJob) -> Bool {
        self.job == job && digest == job.digest
    }
}

public struct StudioApproval: Equatable, Sendable {
    /// Nil when the server's answer never reached the phone.
    public let id: UUID?
    /// `queued` as the server said it, or `unknown`: it may have started, and it is not approved again.
    public let state: String

    public init(id: UUID?, state: String) {
        self.id = id
        self.state = state
    }

    public var isUnknown: Bool { state == StudioItemState.unknown.rawValue }
    /// The server said it has it.
    public var isConfirmed: Bool { (StudioItemState(rawValue: state) ?? .unknown).isOpen }
}

/// One row of `GET /v1/studio` (newest first, no drafts).
public struct StudioItemSummary: Decodable, Equatable, Sendable, Identifiable {
    public let id: UUID
    /// `brief` today; a newer server's kind is kept as sent.
    public let kind: String
    /// Nil until the plan step named it.
    public let title: String?
    public let state: StudioItemState
    public let createdAt: Date
    public let finishedAt: Date?
    public let failure: StudioFailureCode?
    public let costUsd: Double?

    public init(id: UUID, kind: String = "brief", title: String?, state: StudioItemState, createdAt: Date,
                finishedAt: Date? = nil, failure: StudioFailureCode? = nil, costUsd: Double? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.state = state
        self.createdAt = createdAt
        self.finishedAt = finishedAt
        self.failure = failure
        self.costUsd = costUsd
    }

    private enum CodingKeys: String, CodingKey { case id, kind, title, state, createdAt, finishedAt, failure, costUsd }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? StudioJob.Kind.brief.rawValue
        title = try c.decodeIfPresent(String.self, forKey: .title)
        state = try c.decode(StudioItemState.self, forKey: .state)
        createdAt = try c.studioDate(.createdAt)
        finishedAt = try c.studioDateIfPresent(.finishedAt)
        failure = try c.decodeIfPresent(StudioFailureCode.self, forKey: .failure)
        costUsd = try c.decodeIfPresent(Double.self, forKey: .costUsd)
    }
}

/// One file of an item, as the server describes it.
public struct StudioFile: Codable, Equatable, Sendable, Identifiable {
    public enum Role: String, Codable, Sendable, CaseIterable {
        /// `brief.pdf`
        case brief
        /// `infographic.svg`
        case infographic
        /// `infographic.png`, 1080×1350.
        case infographicPNG = "infographic_png"
        /// `infographic-a4.png`, for print.
        case infographicPrint = "infographic_print"
        case unknown

        public init(from decoder: any Decoder) throws {
            self = Role(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }
    }

    public let name: String
    public let role: Role
    public let mime: String
    public let bytes: Int
    public let sha256: String

    public init(name: String, role: Role, mime: String, bytes: Int, sha256: String) {
        self.name = name
        self.role = role
        self.mime = mime
        self.bytes = bytes
        self.sha256 = sha256
    }

    public var id: String { name }

    /// A plain file name the app may put in a path and a URL: letters, digits, dots, dashes and
    /// underscores, not starting with a dot. Anything else is never downloaded.
    public var hasSafeName: Bool { Self.isSafeName(name) }

    public static func isSafeName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 100, !name.hasPrefix(".") else { return false }
        return name.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("A"..."Z").contains($0) || ("0"..."9").contains($0) || $0 == "." || $0 == "-" || $0 == "_" }
    }
}

public struct StudioSource: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let url: String
    public let title: String
    /// When the research saw this page, as the server wrote it.
    public let fetchedAt: String

    public init(id: String, url: String, title: String, fetchedAt: String) {
        self.id = id
        self.url = url
        self.title = title
        self.fetchedAt = fetchedAt
    }

    public var fetchedDate: Date? { ServerDates.parse(fetchedAt) }
}

public struct StudioCheck: Codable, Equatable, Sendable {
    public let name: String
    public let passed: Bool
    public let detail: String?

    public init(name: String, passed: Bool, detail: String? = nil) {
        self.name = name
        self.passed = passed
        self.detail = detail
    }
}

public struct StudioCost: Codable, Equatable, Sendable {
    public let usd: Double
    public let searches: Int?
    public let fetches: Int?

    public init(usd: Double, searches: Int? = nil, fetches: Int? = nil) {
        self.usd = usd
        self.searches = searches
        self.fetches = fetches
    }
}

/// `GET /v1/studio/:id`. Everything but the id, kind, state and creation time is optional, so a
/// running item and a newer server both decode.
public struct StudioItem: Decodable, Equatable, Sendable, Identifiable {
    public struct Summary: Codable, Equatable, Sendable {
        public let answer: String
        public let confidence: String?
        /// The infographic's alt text, for VoiceOver (ADR-584). Absent from an older server.
        public let altText: String?

        public init(answer: String, confidence: String? = nil, altText: String? = nil) {
            self.answer = answer
            self.confidence = confidence
            self.altText = altText
        }
    }

    public let id: UUID
    public let kind: String
    /// The approved job; nil when this app can't read a newer server's job.
    public let job: StudioJob?
    public let title: String?
    public let state: StudioItemState
    public let createdAt: Date
    public let approvedAt: Date?
    public let startedAt: Date?
    public let finishedAt: Date?
    public let summary: Summary?
    public let sources: [StudioSource]
    public let files: [StudioFile]
    public let checks: [StudioCheck]
    public let cost: StudioCost?
    public let model: String?
    public let failure: StudioFailureCode?

    public init(id: UUID, kind: String = "brief", job: StudioJob? = nil, title: String? = nil, state: StudioItemState, createdAt: Date,
                approvedAt: Date? = nil, startedAt: Date? = nil, finishedAt: Date? = nil, summary: Summary? = nil,
                sources: [StudioSource] = [], files: [StudioFile] = [], checks: [StudioCheck] = [], cost: StudioCost? = nil,
                model: String? = nil, failure: StudioFailureCode? = nil) {
        self.id = id
        self.kind = kind
        self.job = job
        self.title = title
        self.state = state
        self.createdAt = createdAt
        self.approvedAt = approvedAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.summary = summary
        self.sources = sources
        self.files = files
        self.checks = checks
        self.cost = cost
        self.model = model
        self.failure = failure
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, job, title, state, createdAt, approvedAt, startedAt, finishedAt, summary, sources, files, checks, cost, model, failure
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? StudioJob.Kind.brief.rawValue
        job = (try? c.decodeIfPresent(StudioJob.self, forKey: .job)) ?? nil
        title = try c.decodeIfPresent(String.self, forKey: .title)
        state = try c.decode(StudioItemState.self, forKey: .state)
        createdAt = try c.studioDate(.createdAt)
        approvedAt = try c.studioDateIfPresent(.approvedAt)
        startedAt = try c.studioDateIfPresent(.startedAt)
        finishedAt = try c.studioDateIfPresent(.finishedAt)
        summary = try c.decodeIfPresent(Summary.self, forKey: .summary)
        sources = try c.decodeIfPresent([StudioSource].self, forKey: .sources) ?? []
        files = try c.decodeIfPresent([StudioFile].self, forKey: .files) ?? []
        checks = try c.decodeIfPresent([StudioCheck].self, forKey: .checks) ?? []
        cost = try c.decodeIfPresent(StudioCost.self, forKey: .cost)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        failure = try c.decodeIfPresent(StudioFailureCode.self, forKey: .failure)
    }

    /// The first file in this role with a name the app may use.
    public func file(_ role: StudioFile.Role) -> StudioFile? {
        files.first { $0.role == role && $0.hasSafeName }
    }

    /// Files are shown only for a ready item or one that needs a look; never while it's working.
    public var showsFiles: Bool { state == .ready || state == .needsLook }

    /// The checks that failed, for a "needs a look" item.
    public var failedChecks: [StudioCheck] { checks.filter { !$0.passed } }
}

/// `200` from `DELETE /v1/studio/:id`.
public struct StudioDeletion: Decodable, Equatable, Sendable {
    public struct AnthropicFiles: Decodable, Equatable, Sendable {
        /// Copies at Anthropic whose delete isn't confirmed yet; the server's worker keeps trying.
        public let pending: Int

        public init(pending: Int) {
            self.pending = pending
        }
    }

    public let deleted: Bool
    public let files: Int
    public let anthropicFiles: AnthropicFiles?

    public init(deleted: Bool, files: Int, anthropicFiles: AnthropicFiles? = nil) {
        self.deleted = deleted
        self.files = files
        self.anthropicFiles = anthropicFiles
    }
}

// MARK: - The delete rule

public enum StudioDeleteRule {
    /// Said to be deleted only when the server said so and a fresh read of the list no longer has
    /// it. A list that couldn't be read back (`nil`) is not proof.
    public static func isDeleted(_ id: UUID, serverSaid: Bool, listAfter: [StudioItemSummary]?) -> Bool {
        guard serverSaid, let listAfter else { return false }
        return !listAfter.contains { $0.id == id }
    }

    /// What the user is told after a confirmed delete: honest about copies at Anthropic still
    /// being deleted.
    public static func confirmation(_ deletion: StudioDeletion?, language: NotificationLanguage) -> String {
        let pending = deletion?.anthropicFiles?.pending ?? 0
        let polish = language == .polish
        guard pending > 0 else { return polish ? "Usunięto." : "Deleted." }
        return polish
            ? "Usunięto z Doddy’ego. Kopia u Anthropic jest jeszcze usuwana."
            : "Deleted from Doddy. Anthropic's copy is still being removed."
    }
}

// MARK: - What the voice agent gets

extension VoiceToolReply {
    /// The server said it has the job (`queued`). The topic follows as data.
    public static func studioStarted(_ job: StudioJob) -> String {
        "started: Doddy's server has the job below. In the background it researches the topic on the web and makes a research brief (PDF) and an infographic; it takes a few minutes, and the user gets a notification when it's ready in Studio (Home, the ••• menu). Nothing is published or sent. Say in one line that you're on it and you'll tell them when it's ready. Never say it's done.\n"
            + ToolData.block([quoted("Topic", job.topic)])
    }

    /// The approve request's answer never came back. Never approved again by itself.
    public static func studioMaybeStarted(_ job: StudioJob) -> String {
        "unknown: the app couldn't confirm the job below started; it may be running. It won't be started again by itself. Tell the user to check Studio in the app before asking again.\n"
            + ToolData.block([quoted("Topic", job.topic)])
    }

    /// Creating or approving failed with an answer from the server, or never left the phone.
    public static func studioNotStarted(_ error: any Error) -> String {
        let said: (reason: String, next: String?) = switch error {
        case StudioError.studioDisabled:
            ("Studio is switched off or not set up on Doddy's server.",
             "Offer to look it up now instead, asking before each search.")
        case StudioError.dailyCapReached(let cap, let spent):
            ("today's spending limit for Studio is reached" + money(cap, spent) + ".",
             "Say it can be made tomorrow; the limit is set on Doddy's server.")
        case StudioError.tooManyOpenItems:
            ("the user already has as many Studio jobs running as Doddy's server allows.", "Offer to wait until one is ready.")
        case StudioError.digestMismatch, StudioError.notApprovable:
            ("the request expired or changed before it was approved.", "It can be asked again with a new yes.")
        case StudioError.previewMismatch:
            ("Doddy's server didn't hold exactly the job the user said yes to, so it wasn't approved.", nil)
        case StudioError.invalid(let fields):
            ("Doddy's server refused the request" + (fields.isEmpty ? "." : " (\(fields.map(ToolData.clean).joined(separator: ", ")))."), nil)
        case StudioError.server(.offline), ServerError.offline:
            ("Doddy's server couldn't be reached.", nil)
        case StudioError.server(.rateLimited), ServerError.rateLimited:
            ("Doddy's server is busy right now.", nil)
        default:
            ("something went wrong on Doddy's server.", nil)
        }
        return (["failed: \(said.reason) Nothing was done."] + [said.next].compactMap { $0 }).joined(separator: "\n")
    }

    private static func money(_ cap: Double?, _ spent: Double?) -> String {
        guard let cap, let spent else { return "" }
        return " (\(StudioMoney.text(spent)) of \(StudioMoney.text(cap)))"
    }
}

/// SHA-256 of a downloaded file, hex, lower case: it must be the one the server described.
public enum StudioFileCheck {
    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Dollars as the app shows them: "$1.84", never fewer than two decimals, never a minus sign.
public enum StudioMoney {
    public static func text(_ usd: Double) -> String {
        let cents = (max(0, usd.isFinite ? usd : 0) * 100).rounded()
        return String(format: "$%.2f", cents / 100)
    }
}

// MARK: - Dates as the server writes them

extension KeyedDecodingContainer {
    fileprivate func studioDate(_ key: Key) throws -> Date {
        let text = try decode(String.self, forKey: key)
        guard let date = ServerDates.parse(text) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "not an ISO 8601 time")
        }
        return date
    }

    fileprivate func studioDateIfPresent(_ key: Key) throws -> Date? {
        guard let text = try decodeIfPresent(String.self, forKey: key) else { return nil }
        guard let date = ServerDates.parse(text) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "not an ISO 8601 time")
        }
        return date
    }
}
