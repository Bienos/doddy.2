import Foundation

// News digests (server/messaging/src/routes/news.ts): the user picks topics, own keywords and own feeds;
// once a day Doddy sends a short message with the most relevant stories.

public struct NewsCatalogTopic: Equatable, Sendable, Decodable, Identifiable {
    /// One publisher whose public feed Doddy's server reads for the topic, and the host it reads it from.
    public struct Publisher: Equatable, Sendable, Decodable, Hashable {
        public let name: String
        /// "feeds.bbci.co.uk"; nil when an older server named only the publisher.
        public let domain: String?

        public init(name: String, domain: String?) {
            self.name = name
            self.domain = domain
        }
    }

    public let id: String
    public let label: String
    /// The publishers behind the topic (10 Nov 2026); older servers leave it out.
    public let sources: [String]?
    /// The topic's shelf in the Sources list ("news", "tech", "money", "life") and its name in the asked language
    /// (13 Nov 2026); older servers leave them out.
    public let group: String?
    public let groupLabel: String?
    /// Each publisher with the host its feed is read from (13 Nov 2026); older servers leave it out.
    public let publishers: [Publisher]?

    public init(id: String, label: String, sources: [String]? = nil, group: String? = nil, groupLabel: String? = nil,
                publishers: [Publisher]? = nil) {
        self.id = id
        self.label = label
        self.sources = sources
        self.group = group
        self.groupLabel = groupLabel
        self.publishers = publishers
    }

    /// The publishers to show: with their hosts when the server gave them, else by name only.
    public var publisherList: [Publisher] {
        if let publishers, !publishers.isEmpty { return publishers }
        return (sources ?? []).map { Publisher(name: $0, domain: nil) }
    }
}

/// One shelf of the Sources list: a group of catalog topics ("Money": Business & markets, Crypto).
public struct NewsCatalogShelf: Equatable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let topics: [NewsCatalogTopic]

    public init(id: String, label: String, topics: [NewsCatalogTopic]) {
        self.id = id
        self.label = label
        self.topics = topics
    }
}

public enum NewsCatalogShelves {
    /// The topics on their shelves, in the order the server lists them; topics from a server that sends no shelves
    /// share one, so nothing is left out.
    public static func group(_ topics: [NewsCatalogTopic], polish: Bool) -> [NewsCatalogShelf] {
        var order: [String] = []
        var labels: [String: String] = [:]
        var byShelf: [String: [NewsCatalogTopic]] = [:]
        for topic in topics {
            let id = topic.group ?? "topics"
            if byShelf[id] == nil {
                order.append(id)
                labels[id] = topic.groupLabel ?? (polish ? "Tematy" : "Topics")
            }
            byShelf[id, default: []].append(topic)
        }
        return order.map { NewsCatalogShelf(id: $0, label: labels[$0] ?? $0, topics: byShelf[$0] ?? []) }
    }
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
        /// An AI writes the lines; otherwise digests are plain headlines.
        public let writer: Bool
        /// "anthropic" or "openai": who gets the topics and headlines. Older servers omit it (ADR-197).
        public let writerProvider: String?

        /// Who writes the lines, as the privacy text names it. Servers before ADR-197 could only use Claude.
        public var writerName: String {
            switch writerProvider {
            case nil, "anthropic": "Claude, by Anthropic"
            case "openai": "GPT, by OpenAI"
            default: "the server's AI provider"
            }
        }
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
    /// queued (in the server's outbox for notifications/texts), ready (kept for the app only, nothing sent),
    /// empty (nothing new), failed, building.
    public let status: String
    public let aiWritten: Bool
    public let errorCode: String?
    public let createdAt: String
    public let items: [Item]

    public var createdDate: Date? { ServerDates.parse(createdAt) }

    /// How this digest reached the user, never claiming more than the server recorded.
    public var deliveryText: String {
        switch status {
        // In the server's outbox; whether Apple or Twilio took it is recorded per message, not here.
        case "queued": "Queued for your notifications or texts"
        case "ready": errorCode == "no_channel"
            ? "Only here: notifications or texts weren't on, so nothing was sent"
            : "In the app only"
        case "empty": "Nothing new that day"
        case "building": "Being put together"
        default: "Couldn't be put together"
        }
    }
}

public struct FeedCheck: Equatable, Sendable, Decodable {
    public let ok: Bool
    public let title: String
    public let items: Int
}

public struct NewsSendResult: Equatable, Sendable, Decodable {
    public let digestId: UUID?
    /// A digest status (see `NewsDigest.status`), or `unknown` when the server's answer never
    /// reached the phone: the news may still arrive, so it isn't sent again automatically.
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

    /// The server fetches the feeds and waits for the AI writer (up to 60 s, retried once) before
    /// it answers, so this waits longer than other requests. A request that may have reached the
    /// server without an answer coming back is `unknown`: the news may still arrive.
    public func sendNewsNow() async throws -> NewsSendResult {
        let response: ServerResponse
        do {
            response = try await authorized(.post, "/v1/news/send-now", body: nil, startsSomething: true, timeout: 180)
        } catch is OutcomeUnknown {
            return NewsSendResult(digestId: nil, status: "unknown", aiWritten: false, errorCode: "outcome_unknown")
        }
        guard response.status == 200, let result = try? JSONDecoder().decode(NewsSendResult.self, from: response.body)
        else { throw Self.error(from: response) }
        return result
    }

    public func newsDigests() async throws -> [NewsDigest] {
        let list: DigestList = try await getJSON("/v1/news/digests")
        return list.digests
    }
}

private struct CatalogList: Decodable { let topics: [NewsCatalogTopic] }
private struct DigestList: Decodable { let digests: [NewsDigest] }
private struct Saved: Decodable { let nextRunAt: String? }
