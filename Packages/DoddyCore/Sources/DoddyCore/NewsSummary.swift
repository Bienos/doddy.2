import Foundation

/// A short AI summary of one story on the radar (owner, 13 Nov 2026: "jak się naciśnie … można dostać podsumowanie
/// artykułu AI-owego … z modelem Haiku"). Doddy's messaging server reads the publisher's page and Claude Haiku writes
/// a headline, two to five points and, sometimes, why it matters, in the asked language (`POST /v1/news/summary`,
/// off until the owner sets `NEWS_SUMMARY_ENABLED=1`). The screen always labels it as written by AI and links to the
/// publisher's full story; nothing in it is Doddy's own opinion.
public struct NewsSummary: Equatable, Sendable, Decodable {
    public struct Body: Equatable, Sendable, Decodable {
        public let headline: String
        public let points: [String]
        public let whyItMatters: String?
    }

    public struct Source: Equatable, Sendable, Decodable {
        public let url: String
        public let host: String
    }

    public let summary: Body
    public let model: String
    public let source: Source
    public let generatedAt: String
    public let cached: Bool

    /// The summary the server sent, or nil when it isn't one the screen may show: no points, more than five, or an
    /// empty headline. A partial answer is never shown as a summary.
    public static func decode(_ data: Data) -> NewsSummary? {
        guard let summary = try? JSONDecoder().decode(NewsSummary.self, from: data) else { return nil }
        let headline = summary.summary.headline.trimmingCharacters(in: .whitespacesAndNewlines)
        let points = summary.summary.points.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !headline.isEmpty, (2...5).contains(points.count), points.count == summary.summary.points.count else { return nil }
        return summary
    }

    /// "Claude Haiku" for the label under the summary; the model id as sent otherwise.
    public var writerName: String {
        model.lowercased().contains("haiku") ? "Claude Haiku" : model
    }
}

/// Why a summary didn't come: each with its own words on screen, never shown as an empty summary.
public enum NewsSummaryProblem: Error, Equatable, Sendable {
    /// The server has summaries switched off, or no AI key.
    case off
    /// The publisher's page couldn't be read (paywall, too little text, not a web page).
    case unreadable
    case dailyLimit
    case invalidLink
    /// The model's answer failed, or anything else the server said.
    case failed

    public init(status: Int, body: Data) {
        struct ErrorBody: Decodable { let error: String? }
        let code = (try? JSONDecoder().decode(ErrorBody.self, from: body))?.error ?? ""
        switch (status, code) {
        case (_, "summary_off"), (_, "not_configured"): self = .off
        case (_, "unreadable_article"): self = .unreadable
        case (_, "daily_limit"), (429, _): self = .dailyLimit
        case (_, "invalid_url"): self = .invalidLink
        case (404, _), (503, _): self = .off
        default: self = .failed
        }
    }

    public func text(polish: Bool) -> String {
        switch self {
        case .off:
            polish ? "Streszczenia AI nie są jeszcze włączone na serwerze Doddy'ego. Otwórz pełny artykuł."
                : "AI summaries aren't switched on on Doddy's server yet. Open the full story."
        case .unreadable:
            polish ? "Nie udało się przeczytać tej strony (może być za paywallem). Otwórz pełny artykuł."
                : "That page couldn't be read (it may be behind a paywall). Open the full story."
        case .dailyLimit:
            polish ? "Na dziś to już limit streszczeń. Jutro znowu będą." : "That's today's limit of summaries. They're back tomorrow."
        case .invalidLink:
            polish ? "Tego linku nie da się streścić." : "That link can't be summarized."
        case .failed:
            polish ? "Streszczenie się nie udało. Spróbuj jeszcze raz albo otwórz pełny artykuł."
                : "The summary didn't work. Try again or open the full story."
        }
    }
}

extension DoddyServerClient {
    /// One story's AI summary. The link and the headline go to Doddy's server, and the page's text to Anthropic.
    public func summarizeStory(url: String, title: String?, language: String) async throws -> NewsSummary {
        struct Request: Encodable { let url: String; let title: String?; let language: String }
        let body = Request(url: url, title: title.map { String($0.prefix(300)) }, language: language == "pl" ? "pl" : "en")
        let response = try await authorized(.post, "/v1/news/summary", body: try Self.json(body), timeout: 60)
        guard response.status == 200 else { throw NewsSummaryProblem(status: response.status, body: response.body) }
        guard let summary = NewsSummary.decode(response.body) else { throw NewsSummaryProblem.failed }
        return summary
    }
}
