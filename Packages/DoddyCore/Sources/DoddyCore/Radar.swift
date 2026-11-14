import Foundation

// On my radar (owner, 10 Nov 2026; decision 2026-11-10-radar-alerts): "adding needs to be nicer", "say when Doddy
// should tell them about an event, by keywords". Rules only; the screen is DoddyApp/Features/News.
//
// - RadarMatch: the same keyword rule as the server (server/messaging/src/news/match.ts), allowing for Polish and
//   English endings; both are tested against schemas/fixtures/radar_match_v1.json.
// - RadarSuggest: what the person typed ("bitcoin", "CPK", a feed address) becomes a choice: a catalog topic that
//   fits, their own words, or their own feed.
// - RadarAlert: "tell me when" for one follow. Kept on this iPhone; only an alert the person let Doddy's server
//   check (an explicit switch in the sheet) is sent there, with exactly the follow, its words and how to tell them.
//
// Platforms: iPhone and iPad.

public enum RadarMatch {
    /// The words of a text: lower case, no diacritics (ł → l), split on anything that is not a letter or digit.
    public static func words(_ text: String) -> [String] {
        fold(text).split { !($0.isLetter || $0.isNumber) }.map(String.init)
    }

    /// The server's `fold` (memorySearch.ts): lower case, the same few letters spelled out, marks removed.
    static func fold(_ text: String) -> String {
        let extra: [Character: String] = ["ł": "l", "ß": "ss", "æ": "ae", "ø": "o", "đ": "d", "œ": "oe", "þ": "th"]
        let swapped = String(text.lowercased().flatMap { extra[$0].map(Array.init) ?? [$0] })
        var scalars = String.UnicodeScalarView()
        for scalar in swapped.decomposedStringWithCanonicalMapping.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .nonspacingMark, .spacingMark, .enclosingMark: continue
            default: scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    /// How many leading letters a story's word must share with a keyword's word (server: `lettersNeeded`).
    public static func lettersNeeded(_ keyWord: String) -> Int {
        let n = keyWord.count
        if n <= 4 { return n }
        let vowel = keyWord.last.map { "aeiouy".contains($0) } ?? false
        if vowel { return n <= 6 ? n - 1 : n == 7 ? n - 2 : n - 3 }
        return n <= 6 ? n : n - 1
    }

    static func wordMatches(_ storyWord: String, _ keyWord: String) -> Bool {
        if keyWord.count <= 3 { return storyWord == keyWord }
        let shared = zip(storyWord, keyWord).prefix { $0 == $1 }.count
        return shared >= lettersNeeded(keyWord)
    }

    /// The keyword's words one after another in the text, each allowing for its ending ("Elon Musk" finds "Elona Muska").
    public static func matches(_ text: String, keyword: String) -> Bool {
        matches(words(text), keyword: keyword)
    }

    static func matches(_ textWords: [String], keyword: String) -> Bool {
        let kw = words(keyword)
        guard !kw.isEmpty, kw.joined().count >= 2, kw.count <= textWords.count else { return false }
        for start in 0...(textWords.count - kw.count) where kw.indices.allSatisfy({ wordMatches(textWords[start + $0], kw[$0]) }) {
            return true
        }
        return false
    }

    /// The keywords that appear in the text, in the order given.
    public static func matched(_ text: String, keywords: [String]) -> [String] {
        let textWords = words(text)
        return keywords.filter { matches(textWords, keyword: $0) }
    }
}

/// An own feed's address: https only, no credentials, at most 500 characters. The server checks again (public
/// address, size, time, every redirect) before reading it.
public enum RadarFeedAddress {
    public static func normalized(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("://") { text = "https://" + text }
        guard text.count <= 500, let url = URL(string: text), url.scheme?.lowercased() == "https",
              let host = url.host, host.contains("."), url.user == nil, url.password == nil
        else { return nil }
        return url.absoluteString
    }

    /// True when what was typed reads as an address rather than words ("https://…", "blog.example.com/feed").
    public static func looksLikeAddress(_ raw: String) -> Bool {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("http://") || text.lowercased().hasPrefix("https://") { return true }
        return !text.contains(" ") && text.contains(".") && text.contains("/")
    }
}

public enum RadarText {
    /// "A, B and C" / "A, B i C".
    public static func list(_ names: [String], polish: Bool) -> String {
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + (polish ? " i " : " and ") + names.last!
    }
}

/// One way to put what the person typed on the radar.
public enum RadarChoice: Equatable, Sendable, Identifiable {
    /// A catalog topic that fits the words ("bitcoin" → Crypto), with its publishers when the server listed them.
    case topic(id: String, label: String, sources: [String])
    /// The person's own words, looked for in every feed Doddy reads.
    case words(label: String, keywords: [String])
    /// The person's own feed.
    case feed(url: String)

    public var id: String {
        switch self {
        case .topic(let id, _, _): "topic:\(id)"
        case .words(let label, _): "words:\(label.lowercased())"
        case .feed(let url): "feed:\(url)"
        }
    }
}

public enum RadarSuggest {
    /// Words that point at a catalog topic, in Polish and English (folded when compared). A test keeps the ids in
    /// step with the server's catalog (`NewsFollowAsk.catalog`).
    public static let hints: [String: [String]] = [
        "crypto": ["crypto", "krypto", "kryptowaluty", "cryptocurrency", "bitcoin", "btc", "ethereum", "ether", "eth",
                   "blockchain", "solana", "stablecoin", "altcoin", "binance", "coinbase", "nft"],
        "ai": ["ai", "sztuczna inteligencja", "artificial intelligence", "openai", "chatgpt", "anthropic", "claude", "gemini", "llm"],
        "technology": ["tech", "technologia", "technology", "smartfon", "smartphone", "iphone", "apple", "google", "microsoft",
                       "samsung", "gadżety", "gadgets"],
        "business": ["biznes", "business", "giełda", "stock market", "rynki", "markets", "gospodarka", "economy", "inflacja",
                     "inflation", "akcje", "stocks", "waluty", "gpw", "nbp"],
        "poland": ["polska", "poland", "sejm", "rząd", "polityka"],
        "world": ["świat", "world", "zagranica"],
        "europe": ["europa", "europe", "unia europejska", "european union", "bruksela", "brussels"],
        "science": ["nauka", "science", "kosmos", "space", "nasa", "fizyka", "physics"],
        "health": ["zdrowie", "health", "medycyna", "medicine", "szpital", "hospital"],
        "sport": ["sport", "piłka nożna", "football", "soccer", "tenis", "tennis", "formuła 1", "siatkówka", "skoki narciarskie",
                  "ekstraklasa", "nba"],
    ]

    /// The choices for what was typed: an address is the person's own feed; words get the catalog topic they point
    /// at first (if any, and not followed yet), then "these words". Nothing for text too short to look for.
    public static func choices(for typed: String, catalog: [NewsCatalogTopic], following: NewsFollowList, polish: Bool) -> [RadarChoice] {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else { return [] }
        if RadarFeedAddress.looksLikeAddress(text) {
            return RadarFeedAddress.normalized(text).map { [.feed(url: $0)] } ?? []
        }
        var out: [RadarChoice] = []
        let followed = Set(following.follows.map(\.id))
        let textWords = RadarMatch.words(text)
        for id in NewsFollowAsk.catalog.map(\.id) where !followed.contains("topic:\(id)") {
            let entry = NewsFollowAsk.catalog.first { $0.id == id }!
            let server = catalog.first { $0.id == id }
            let names = [entry.en, entry.pl, server?.label].compactMap { $0 }
            let fits = (hints[id] ?? []).contains { RadarMatch.matches(textWords, keyword: $0) }
                || names.contains { RadarMatch.words($0) == textWords }
            if fits {
                out.append(.topic(id: id, label: server?.label ?? (polish ? entry.pl : entry.en), sources: server?.sources ?? []))
                break
            }
        }
        if let words = NewsFollowList.words(name: String(text.prefix(60)), keywordsText: text.replacingOccurrences(of: ";", with: ",")),
           case .words(let label, let keywords) = words {
            out.append(.words(label: label, keywords: keywords))
        }
        return out
    }
}

/// How Doddy tells the person about a follow's stories.
public enum RadarHow: String, Codable, Sendable, CaseIterable {
    /// Only on this screen; nothing is stored on Doddy's server.
    case app
    /// A notification as it happens (outside quiet hours, a few a day at most). Needs words to look out for.
    case instant
    /// One short summary a day at the person's time.
    case daily
}

/// "Tell me when" for one follow. `how` other than `.app` means the person turned on "Let Doddy's server check
/// this for you" in the sheet: that switch is the only way to set it.
public struct RadarAlert: Equatable, Sendable, Codable {
    public var followID: String
    /// A story must mention one of these (empty: any new story of the follow; for `.instant` the follow's own words).
    public var words: [String]
    public var how: RadarHow
    /// "HH:MM", for `.daily`.
    public var dailyTime: String

    public init(followID: String, words: [String] = [], how: RadarHow = .app, dailyTime: String = "18:00") {
        self.followID = followID
        self.words = Array(words.prefix(10))
        self.how = how
        self.dailyTime = dailyTime
    }

    public var serverChecks: Bool { how != .app }

    /// Why this alert can't be kept as it is, or nil. A whole topic "as it happens" would be a notification per story.
    public func problem(for follow: NewsFollow) -> RadarAlertProblem? {
        if how == .instant && words.isEmpty && (follow.catalogID != nil || follow.keywords.isEmpty) { return .wordsNeeded }
        if how == .daily && !Self.isClock(dailyTime) { return .timeNeeded }
        return nil
    }

    /// One line under the follow's name: how Doddy tells about it, and who checks.
    public func summary(polish: Bool) -> String {
        let list = RadarText.list(words, polish: polish)
        switch (how, polish) {
        case (.app, false):
            return words.isEmpty ? "Shown here only" : "Shown here only; stories that mention \(list) get a flag"
        case (.app, true):
            return words.isEmpty ? "Tylko tutaj" : "Tylko tutaj; artykuły, w których pada \(list), dostają flagę"
        case (.instant, false):
            return words.isEmpty ? "Doddy's server tells you about each new story as it happens"
                : "Doddy's server tells you as it happens when a story mentions \(list)"
        case (.instant, true):
            return words.isEmpty ? "Serwer Doddy’ego da znać od razu o każdym nowym artykule"
                : "Serwer Doddy’ego da znać od razu, gdy w artykule padnie \(list)"
        case (.daily, false):
            return words.isEmpty ? "Doddy's server sends a summary every day at \(dailyTime)"
                : "Doddy's server sends a summary every day at \(dailyTime) of stories that mention \(list)"
        case (.daily, true):
            return words.isEmpty ? "Serwer Doddy’ego wyśle podsumowanie codziennie o \(dailyTime)"
                : "Serwer Doddy’ego wyśle codziennie o \(dailyTime) podsumowanie artykułów, w których pada \(list)"
        }
    }

    static func isClock(_ text: String) -> Bool {
        text.range(of: #"^([01][0-9]|2[0-3]):[0-5][0-9]$"#, options: .regularExpression) != nil
    }
}

public enum RadarAlertProblem: Equatable, Sendable {
    case wordsNeeded, timeNeeded
}

/// The alerts kept on this iPhone, by follow id. Stored as JSON in the app's defaults.
public struct RadarAlertList: Equatable, Sendable, Codable {
    public private(set) var alerts: [String: RadarAlert]

    public init(alerts: [RadarAlert] = []) {
        self.alerts = Dictionary(alerts.map { ($0.followID, $0) }, uniquingKeysWith: { _, last in last })
    }

    public func alert(for follow: NewsFollow) -> RadarAlert? { alerts[follow.id] }

    public mutating func set(_ alert: RadarAlert) { alerts[alert.followID] = alert }

    public mutating func remove(followID: String) { alerts[followID] = nil }

    /// Drops alerts whose follow is gone.
    public func keeping(_ follows: NewsFollowList) -> RadarAlertList {
        let ids = Set(follows.follows.map(\.id))
        return RadarAlertList(alerts: alerts.values.filter { ids.contains($0.followID) })
    }

    /// True when at least one follow is checked by Doddy's server.
    public func anyServerChecks(_ follows: NewsFollowList) -> Bool {
        follows.follows.contains { alerts[$0.id]?.serverChecks == true }
    }

    /// What `PUT /v1/news/radar` gets: only the follows the person let the server check, in the order of the row,
    /// and only ones that can be kept as they are. An empty list turns every check off on the server.
    public func request(_ follows: NewsFollowList, language: String, timeZone: String) -> RadarAlertsRequest {
        let items = follows.follows.compactMap { follow -> RadarAlertsRequest.Item? in
            guard let alert = alerts[follow.id], alert.serverChecks, alert.problem(for: follow) == nil else { return nil }
            return RadarAlertsRequest.Item(
                followKey: follow.id, label: follow.label, catalogId: follow.catalogID,
                keywords: follow.catalogID == nil ? follow.keywords : [], feedUrl: follow.feedURL, alertWords: alert.words,
                mode: alert.how.rawValue, dailyTime: alert.how == .daily ? alert.dailyTime : nil)
        }
        return RadarAlertsRequest(language: language == "pl" ? "pl" : "en", timeZone: timeZone, alerts: items)
    }

    public func encoded() throws -> Data { try JSONEncoder().encode(self) }

    public static func decode(_ data: Data?) -> RadarAlertList {
        guard let data, let list = try? JSONDecoder().decode(RadarAlertList.self, from: data) else { return RadarAlertList() }
        return list
    }
}

public struct RadarAlertsRequest: Equatable, Sendable, Encodable {
    public struct Item: Equatable, Sendable, Encodable {
        public let followKey: String
        public let label: String
        public let catalogId: String?
        public let keywords: [String]
        public let feedUrl: String?
        public let alertWords: [String]
        public let mode: String
        public let dailyTime: String?

        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(followKey, forKey: .followKey)
            try c.encode(label, forKey: .label)
            try c.encodeIfPresent(catalogId, forKey: .catalogId)
            try c.encode(keywords, forKey: .keywords)
            try c.encodeIfPresent(feedUrl, forKey: .feedUrl)
            try c.encode(alertWords, forKey: .alertWords)
            try c.encode(mode, forKey: .mode)
            try c.encodeIfPresent(dailyTime, forKey: .dailyTime)
        }

        private enum CodingKeys: String, CodingKey { case followKey, label, catalogId, keywords, feedUrl, alertWords, mode, dailyTime }
    }

    public let language: String
    public let timeZone: String
    public let alerts: [Item]
}

/// What Doddy's server holds for this account (`GET /v1/news/radar`).
public struct RadarServerState: Equatable, Sendable, Decodable {
    public struct Alert: Equatable, Sendable, Decodable {
        public let followKey: String
        public let label: String
        public let mode: String
        public let dailyTime: String?
        public let alertWords: [String]
        public let lastCheckedAt: String?
    }

    /// A story an alert found: the publisher's own headline, summary and link.
    public struct Hit: Equatable, Sendable, Decodable, Identifiable {
        public let id: String
        public let followKey: String
        public let label: String
        public let title: String
        public let summary: String
        public let url: String
        public let source: String
        public let publishedAt: String
        public let matched: [String]
        public let foundAt: String
        /// "push": a notification was queued; "app": shown here only; nil: not told yet (quiet hours, or the summary's time).
        public let toldBy: String?
        public let seen: Bool

        public var link: URL? {
            guard let url = URL(string: url), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return nil }
            return url
        }
    }

    /// RADAR_ALERTS_ENABLED on the server: false means it doesn't check anything for anyone yet.
    public let available: Bool
    /// A notification can reach this account now (the server can send them and this iPhone gave a token).
    public let push: Bool
    public let alerts: [Alert]
    public let hits: [Hit]

    public var unseen: Int { hits.filter { !$0.seen }.count }
}

private struct RadarSeen: Decodable { let marked: Int }

extension DoddyServerClient {
    public func radarState() async throws -> RadarServerState {
        try await getJSON("/v1/news/radar")
    }

    /// Replaces what the server checks with exactly this list; the answer is what it then holds.
    public func saveRadar(_ request: RadarAlertsRequest) async throws -> RadarServerState {
        let response = try await authorized(.put, "/v1/news/radar", body: try Self.json(request))
        guard response.status == 200, let state = try? JSONDecoder().decode(RadarServerState.self, from: response.body)
        else { throw Self.error(from: response) }
        return state
    }

    @discardableResult
    public func markRadarSeen(ids: [String]) async throws -> Int {
        let response = try await authorized(.post, "/v1/news/radar/seen", body: try Self.json(["ids": ids]))
        guard response.status == 200, let seen = try? JSONDecoder().decode(RadarSeen.self, from: response.body)
        else { throw Self.error(from: response) }
        return seen.marked
    }
}
