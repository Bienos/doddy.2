import Foundation

// On my radar's AI summary (owner, 13 Nov 2026): a tap on a story asks Doddy's server for a short summary of the
// article, which Claude Haiku writes from the article's own text (`POST /v1/news/summary`,
// server/messaging/src/news/summary.ts). Only the story's address, its headline and the app's language go with the
// request, never what the person follows. Every answer the server can give is a case here, so the screen never shows
// a summary that wasn't written, and says plainly why when there is none. Rules only; the screen is in
// DoddyApp/Features/News.
//
// Platforms: iPhone and iPad.

/// What `POST /v1/news/summary` takes.
public struct NewsSummaryRequest: Equatable, Sendable, Encodable {
    public let url: String
    /// The card's headline, as the publisher's feed gave it: a hint for the model, never shown back as its words.
    public let title: String?
    public let language: String

    public init(url: String, title: String?, language: String) {
        self.url = url
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.title = trimmed.isEmpty ? nil : String(trimmed.prefix(300))
        self.language = language == "pl" ? "pl" : "en"
    }

    public init(card: NewsCard, language: String) {
        self.init(url: card.url, title: card.title, language: language)
    }
}

/// A summary the server's model wrote. Only ever made from the server's answer.
public struct NewsSummary: Equatable, Sendable, Decodable {
    public let url: String
    public let language: String
    /// Two to five short points, the most important first.
    public let points: [String]
    public let whyItMatters: String
    /// Who received the article's text: "anthropic".
    public let provider: String
    /// The model that wrote it, e.g. "claude-haiku-5-5".
    public let model: String
    /// When it was written; the server may answer from summaries written in the last few hours.
    public let createdAt: String

    public init(url: String, language: String, points: [String], whyItMatters: String, provider: String, model: String, createdAt: String) {
        self.url = url
        self.language = language
        self.points = points
        self.whyItMatters = whyItMatters
        self.provider = provider
        self.model = model
        self.createdAt = createdAt
    }

    public var createdDate: Date? { ServerDates.parse(createdAt) }

    /// The model's family name for the label under the summary ("Claude Haiku"), from the model the server named.
    public var writerName: String {
        let model = model.lowercased()
        if model.hasPrefix("claude-haiku") { return "Claude Haiku" }
        if model.hasPrefix("claude-sonnet") { return "Claude Sonnet" }
        if model.hasPrefix("claude-opus") { return "Claude Opus" }
        if model.hasPrefix("claude") { return "Claude" }
        return self.model
    }
}

/// Why the server wrote no summary for a page it couldn't use.
public enum NewsSummaryUnreadable: String, Equatable, Sendable {
    /// The publisher marks the article as not free.
    case paywall
    /// A sign-in, a bot check or a refusal (401, 403, 429).
    case blocked
    /// The publisher's rules for automated readers (robots.txt, or "no AI input") say no.
    case notAllowed = "not_allowed"
    /// The page didn't load (a timeout, a missing page, the site down).
    case unreachable
    /// Not an article: not a web page, or no article text on it.
    case notArticle = "not_article"
    /// Too little text: a teaser, a video or a live page.
    case tooShort = "too_short"
}

/// Every answer `POST /v1/news/summary` gives that isn't a plain server error.
public enum NewsSummaryOutcome: Equatable, Sendable {
    case summary(NewsSummary)
    /// The page couldn't be used; nil for a reason this app doesn't know yet.
    case unreadable(NewsSummaryUnreadable?)
    /// The day's summaries are used up: the person's own (`serverWide` false) or the whole server's.
    case limitReached(serverWide: Bool)
    /// Summaries aren't set up on this server (no Anthropic key).
    case notConfigured

    /// The outcome the server's reply stands for, or nil when it is an error `DoddyServerClient.error(from:)` maps
    /// (offline, rate limited, an unsafe address, the model failing). A 200 that doesn't decode is nil too: it is
    /// never shown as a summary.
    public static func from(status: Int, body: Data) -> NewsSummaryOutcome? {
        switch status {
        case 200:
            guard let summary = try? JSONDecoder().decode(NewsSummary.self, from: body), !summary.points.isEmpty else { return nil }
            return .summary(summary)
        case 422, 429, 503:
            guard let error = try? JSONDecoder().decode(SummaryError.self, from: body) else { return nil }
            switch (status, error.error) {
            case (422, "unreadable"): return .unreadable(error.reason.flatMap(NewsSummaryUnreadable.init(rawValue:)))
            case (429, "limit_reached"): return .limitReached(serverWide: error.scope == "server")
            case (503, "not_configured"): return .notConfigured
            default: return nil
            }
        default:
            return nil
        }
    }
}

private struct SummaryError: Decodable {
    let error: String
    let reason: String?
    let scope: String?
}

extension DoddyServerClient {
    /// The AI summary of one story. The server reads the article and its model writes the summary, so this waits
    /// longer than most requests. Asking again is safe: nothing is sent or changed anywhere.
    public func newsSummary(_ request: NewsSummaryRequest) async throws -> NewsSummaryOutcome {
        let response = try await authorized(.post, "/v1/news/summary", body: try Self.json(request), timeout: 60)
        if let outcome = NewsSummaryOutcome.from(status: response.status, body: response.body) { return outcome }
        throw Self.error(from: response)
    }
}
