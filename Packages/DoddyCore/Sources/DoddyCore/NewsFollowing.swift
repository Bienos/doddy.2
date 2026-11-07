import Foundation

// Following (ADR-656): the stories behind what the person follows, scrolled like a photo feed.
// Follows are kept on the iPhone and travel with each request to Doddy's server, which never stores
// them; a card is the publisher's headline, summary, picture and link, as the feed carried them.
// No AI writes or picks anything here. Rules only; the screen is in DoddyApp/Features/News.
//
// Platforms: iPhone and iPad.

/// One thing the person follows: a curated topic from the server's catalog, or their own words.
public enum NewsFollow: Equatable, Hashable, Sendable, Codable, Identifiable {
    case topic(id: String, label: String)
    case words(label: String, keywords: [String])

    public var id: String {
        switch self {
        case .topic(let id, _): "topic:\(id)"
        case .words(let label, _): "words:\(label.lowercased())"
        }
    }

    public var label: String {
        switch self {
        case .topic(_, let label): label
        case .words(let label, _): label
        }
    }

    public var keywords: [String] {
        if case .words(_, let keywords) = self { return keywords }
        return []
    }

    /// The shape the server takes (the same as the daily digest's topics).
    public var topic: NewsTopic {
        switch self {
        case .topic(let id, let label): NewsTopic(catalogId: id, label: label)
        case .words(let label, let keywords): NewsTopic(label: label, keywords: keywords)
        }
    }

    /// The server's catalog topic that stands for "what's happening in Poland".
    public static let polandTopicID = "poland"

    /// The one follow a new person starts with (owner, 28 Oct 2026): what's happening in Poland.
    public static func defaultFollow(polish: Bool) -> NewsFollow {
        .topic(id: polandTopicID, label: polish ? "Co się dzieje w Polsce" : "What's happening in Poland")
    }
}

/// The follows kept on this iPhone. At most ten, like the digest's topics; the same thing never twice.
public struct NewsFollowList: Equatable, Sendable, Codable {
    public static let maxFollows = 10
    public private(set) var follows: [NewsFollow]

    public init(follows: [NewsFollow]) {
        var seen = Set<String>()
        self.follows = follows.filter { seen.insert($0.id).inserted }.prefix(Self.maxFollows).map { $0 }
    }

    /// What a person who has never chosen anything sees.
    public static func initial(polish: Bool) -> NewsFollowList {
        NewsFollowList(follows: [.defaultFollow(polish: polish)])
    }

    public var isEmpty: Bool { follows.isEmpty }
    public var isFull: Bool { follows.count >= Self.maxFollows }

    /// Adds a follow. False when it is already there or the list is full; nothing changes then.
    @discardableResult
    public mutating func add(_ follow: NewsFollow) -> Bool {
        guard !isFull, !follows.contains(where: { $0.id == follow.id }) else { return false }
        follows.append(follow)
        return true
    }

    /// The person's own words as a follow: a name (1–60 characters) and 1–10 keywords of 2–40
    /// characters, the way the server checks them. Nil when either is missing: nothing half-made
    /// is kept or sent.
    public static func words(name rawName: String, keywordsText: String) -> NewsFollow? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let keywords = NewsTopic.keywords(from: keywordsText)
        guard (1...60).contains(name.count), !keywords.isEmpty else { return nil }
        return .words(label: name, keywords: keywords)
    }

    public mutating func remove(id: String) {
        follows.removeAll { $0.id == id }
    }

    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var copy = follows
        let moving = source.sorted().map { copy[$0] }
        for i in source.sorted(by: >) { copy.remove(at: i) }
        let target = destination - source.filter { $0 < destination }.count
        copy.insert(contentsOf: moving, at: max(0, min(target, copy.count)))
        follows = copy
    }

    /// What is sent with a request. Empty follows send nothing: the server answers 400 to an empty list.
    public func request(language: String, limit: Int = NewsFeedRequest.maxCards) -> NewsFeedRequest? {
        guard !follows.isEmpty else { return nil }
        return NewsFeedRequest(language: language == "pl" ? "pl" : "en", follows: follows.map(\.topic), limit: limit)
    }

    // Stored as JSON in the app's defaults; an unreadable value falls back to the initial list.
    public func encoded() throws -> Data { try JSONEncoder().encode(self) }

    public static func decode(_ data: Data?, polish: Bool) -> NewsFollowList {
        guard let data, let list = try? JSONDecoder().decode(NewsFollowList.self, from: data) else {
            return .initial(polish: polish)
        }
        return list
    }
}

public struct NewsFeedRequest: Equatable, Sendable, Encodable {
    public static let maxCards = 40
    public let language: String
    public let follows: [NewsTopic]
    public let limit: Int

    public init(language: String, follows: [NewsTopic], limit: Int = NewsFeedRequest.maxCards) {
        self.language = language
        self.follows = follows
        self.limit = min(max(limit, 1), Self.maxCards)
    }
}

/// One story, as the publisher's feed carried it. Nothing in it was written by Doddy or an AI.
public struct NewsCard: Equatable, Sendable, Decodable, Identifiable, Hashable {
    public let id: String
    public let title: String
    public let summary: String
    public let url: String
    public let source: String
    public let publishedAt: String
    public let imageUrl: String?
    /// The follows this story belongs to, by label.
    public let follows: [String]

    public init(id: String, title: String, summary: String, url: String, source: String, publishedAt: String,
                imageUrl: String? = nil, follows: [String]) {
        self.id = id
        self.title = title
        self.summary = summary
        self.url = url
        self.source = source
        self.publishedAt = publishedAt
        self.imageUrl = imageUrl
        self.follows = follows
    }

    public var publishedDate: Date? { ServerDates.parse(publishedAt) }
    public var link: URL? {
        guard let url = URL(string: url), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http"
        else { return nil }
        return url
    }
    /// Only an https picture is shown (the app's transport security would refuse http anyway).
    public var image: URL? {
        guard let imageUrl, let url = URL(string: imageUrl), url.scheme?.lowercased() == "https" else { return nil }
        return url
    }

    /// The first letter of the publisher, for the round badge next to its name.
    public var sourceInitial: String {
        source.first.map { String($0).uppercased() } ?? "•"
    }

    /// The note kept when the person taps Save: the headline, the publisher and the link, so the
    /// note says where it came from and nothing Doddy made up.
    public var noteText: String {
        var lines = [title]
        if !summary.isEmpty { lines.append(summary) }
        lines.append("\(source) · \(url)")
        return lines.joined(separator: "\n")
    }

    /// "2 h ago" / "2 godz. temu" style, from the card's own time. Nil when the server gave no readable time.
    public func ageText(now: Date, polish: Bool) -> String? {
        guard let date = publishedDate else { return nil }
        let minutes = Int(now.timeIntervalSince(date) / 60)
        if minutes < 1 { return polish ? "teraz" : "just now" }
        if minutes < 60 { return polish ? "\(minutes) min temu" : "\(minutes) min ago" }
        let hours = minutes / 60
        if hours < 24 { return polish ? "\(hours) godz. temu" : "\(hours) h ago" }
        let days = hours / 24
        return polish ? (days == 1 ? "wczoraj" : "\(days) dni temu") : (days == 1 ? "yesterday" : "\(days) days ago")
    }
}

public struct NewsFeedPage: Equatable, Sendable, Decodable {
    public let fetchedAt: String
    /// The server searches news sources for the person's own words; otherwise it looks for them only
    /// in the stories of their other follows.
    public let keywordSearch: Bool
    public let cards: [NewsCard]
}

/// The feed in the order it is read: by day, newest first, so a day's heading can sit between cards.
public enum NewsFeedDay: Equatable, Sendable {
    case today, yesterday, earlier

    public func title(polish: Bool) -> String {
        switch self {
        case .today: polish ? "Dziś" : "Today"
        case .yesterday: polish ? "Wczoraj" : "Yesterday"
        case .earlier: polish ? "Wcześniej" : "Earlier"
        }
    }
}

public struct NewsFeedSection: Equatable, Sendable, Identifiable {
    public let day: NewsFeedDay
    public let cards: [NewsCard]
    public var id: String { "\(day)" }
}

public enum NewsFeedSections {
    /// Cards whose time can't be read go last, under Earlier, rather than being pretended into today.
    public static func group(_ cards: [NewsCard], now: Date, calendar: Calendar = .current) -> [NewsFeedSection] {
        var byDay: [NewsFeedDay: [NewsCard]] = [:]
        let sorted = cards.sorted { ($0.publishedDate ?? .distantPast) > ($1.publishedDate ?? .distantPast) }
        for card in sorted {
            let day: NewsFeedDay
            if let date = card.publishedDate {
                if calendar.isDate(date, inSameDayAs: now) { day = .today }
                else if calendar.isDateInYesterday(date) || (calendar.isDate(date, inSameDayAs: now.addingTimeInterval(-86_400))) { day = .yesterday }
                else { day = .earlier }
            } else {
                day = .earlier
            }
            byDay[day, default: []].append(card)
        }
        return [NewsFeedDay.today, .yesterday, .earlier].compactMap { day in
            byDay[day].map { NewsFeedSection(day: day, cards: $0) }
        }
    }
}

extension DoddyServerClient {
    /// The stories behind the follows, right now. The follows go with the request and are not kept
    /// by the server; the feeds behind them are fetched through its shared cache.
    public func newsFeed(_ request: NewsFeedRequest) async throws -> NewsFeedPage {
        let response = try await authorized(.post, "/v1/news/feed", body: try Self.json(request), timeout: 60)
        guard response.status == 200, let page = try? JSONDecoder().decode(NewsFeedPage.self, from: response.body)
        else { throw Self.error(from: response) }
        return page
    }
}
