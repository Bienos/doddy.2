import Foundation

// News digests (server/src/routes/news.ts): the user picks topics, own keywords and own feeds;
// once a day Doddy sends a short message with the most relevant stories.

public struct NewsCatalogTopic: Equatable, Sendable, Decodable, Identifiable {
    public let id: String
    public let label: String
}

public struct NewsTopic: Equatable, Sendable, Codable {
    /// A curated topic id, or nil for the user's own keyword topic.
    public var catalogId: String?
    public var label: String
    public var keywords: [String]

    public init(catalogId: String? = nil, label: String, keywords: [String] = []) {
        self.catalogId = catalogId
        self.label = label
        self.keywords = keywords
    }

    /// The server takes either `{catalogId}` or `{label, keywords}`.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if let catalogId {
            try c.encode(catalogId, forKey: .catalogId)
        } else {
            try c.encode(label, forKey: .label)
            try c.encode(keywords, forKey: .keywords)
        }
    }

    /// "espresso, flat white" → ["espresso", "flat white"] (2–40 characters each, at most 10).
    public static func keywords(from text: String) -> [String] {
        let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return Array(parts.filter { (2...40).contains($0.count) }.prefix(10))
    }
}

public struct NewsFeed: Equatable, Sendable, Decodable {
    public let url: String
    public let title: String?
    /// The last fetch failed (the digest keeps using older items until it recovers).
    public let failing: Bool
}

public struct NewsSettings: Equatable, Sendable, Decodable {
    public struct Available: Equatable, Sendable, Decodable {
        /// Claude writes the lines; otherwise digests are plain headlines.
        public let writer: Bool
        /// Own keywords are searched across news sources; otherwise only matched in feeds.
        public let keywordSearch: Bool
    }

    public let available: Available
    public let enabled: Bool
    public let sendTime: String
    public let timezone: String
    public let channels: [UpdateChannel]
    public let language: String
    public let nextRunAt: String?
    public let topics: [NewsTopic]
    public let feeds: [NewsFeed]
}

public struct NewsSettingsUpdate: Equatable, Sendable, Encodable {
    public var enabled: Bool
    public var sendTime: String
    public var timezone: String
    public var channels: [UpdateChannel]
    public var language: String
    public var topics: [NewsTopic]
    public var feeds: [String]

    public init(enabled: Bool, sendTime: String, timezone: String, channels: [UpdateChannel], language: String,
                topics: [NewsTopic], feeds: [String]) {
        self.enabled = enabled
        self.sendTime = sendTime
        self.timezone = timezone
        self.channels = channels
        self.language = language
        self.topics = topics
        self.feeds = feeds
    }
}

public struct NewsDigest: Equatable, Sendable, Decodable, Identifiable {
    public struct Item: Equatable, Sendable, Decodable {
        public let line: String
        public let url: String
        public let source: String
    }

    public let id: UUID
    /// queued (handed to notifications/texts), empty (nothing new), failed, building.
    public let status: String
    public let aiWritten: Bool
    public let errorCode: String?
    public let createdAt: String
    public let items: [Item]

    public var createdDate: Date? { ServerDates.parse(createdAt) }
}

public struct FeedCheck: Equatable, Sendable, Decodable {
    public let ok: Bool
    public let title: String
    public let items: Int
}

public struct NewsSendResult: Equatable, Sendable, Decodable {
    public let digestId: UUID?
    public let status: String
    public let aiWritten: Bool
    public let errorCode: String?
}

extension DoddyServerClient {
    public func newsCatalog(language: String) async throws -> [NewsCatalogTopic] {
        let list: CatalogList = try await getJSON("/v1/news/catalog?lang=\(language == "pl" ? "pl" : "en")")
        return list.topics
    }

    public func newsSettings() async throws -> NewsSettings {
        try await getJSON("/v1/news/settings")
    }

    @discardableResult
    public func saveNewsSettings(_ update: NewsSettingsUpdate) async throws -> String? {
        let response = try await authorized(.put, "/v1/news/settings", body: try Self.json(update))
        guard response.status == 200, let saved = try? JSONDecoder().decode(Saved.self, from: response.body)
        else { throw Self.error(from: response) }
        return saved.nextRunAt
    }

    public func checkFeed(_ url: String) async throws -> FeedCheck {
        let response = try await authorized(.post, "/v1/news/feeds/check", body: try Self.json(["url": url]))
        guard response.status == 200, let check = try? JSONDecoder().decode(FeedCheck.self, from: response.body)
        else { throw Self.error(from: response) }
        return check
    }

    public func sendNewsNow() async throws -> NewsSendResult {
        let response = try await authorized(.post, "/v1/news/send-now", body: nil)
        guard response.status == 200, let result = try? JSONDecoder().decode(NewsSendResult.self, from: response.body)
        else { throw Self.error(from: response) }
        return result
    }

    public func newsDigests() async throws -> [NewsDigest] {
        let list: DigestList = try await getJSON("/v1/news/digests")
        return list.digests
    }

    private func getJSON<T: Decodable>(_ path: String) async throws -> T {
        let response = try await authorized(.get, path, body: nil)
        guard response.status == 200, let value = try? JSONDecoder().decode(T.self, from: response.body)
        else { throw Self.error(from: response) }
        return value
    }
}

private struct CatalogList: Decodable { let topics: [NewsCatalogTopic] }
private struct DigestList: Decodable { let digests: [NewsDigest] }
private struct Saved: Decodable { let nextRunAt: String? }
