import XCTest
@testable import DoddyCore

/// On my radar's AI summary (13 Nov 2026) and the Sources list's shelves: what the app sends, and every answer of
/// `POST /v1/news/summary` read as the server's code writes it (server/messaging/test/newsSummary.test.ts).
final class NewsSummaryTests: XCTestCase {
    private func json(_ text: String) -> Data { Data(text.utf8) }

    func testTheRequestCarriesOnlyTheAddressTheHeadlineAndTheLanguage() throws {
        let card = NewsCard(id: "1", title: "  Tram line gets longer ", summary: "Feed text", url: "https://city.example.com/tram",
                            source: "City News", publishedAt: "2026-11-13T08:00:00Z", follows: ["Kraków", "Transport"])
        let request = NewsSummaryRequest(card: card, language: "pl")
        let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as! [String: Any]
        XCTAssertEqual(body as NSDictionary, ["url": "https://city.example.com/tram", "title": "Tram line gets longer", "language": "pl"],
                       "never the follows or the feed's summary")
        let untitled = try JSONSerialization.jsonObject(with: JSONEncoder().encode(NewsSummaryRequest(url: "https://a.example.com/x", title: " ", language: "de"))) as! [String: Any]
        XCTAssertEqual(untitled as NSDictionary, ["url": "https://a.example.com/x", "language": "en"])
        XCTAssertEqual(NewsSummaryRequest(url: "u", title: String(repeating: "a", count: 400), language: "en").title?.count, 300)
    }

    func testASummaryIsOnlyEverTheServersOwn() {
        let ok = json(#"{"url":"https://city.example.com/tram","language":"pl","points":["Rada przegłosowała.","Linia do 2028."],"whyItMatters":"Dojazd.","provider":"anthropic","model":"claude-haiku-5-5","createdAt":"2026-11-13T08:00:00.000Z"}"#)
        guard case .summary(let summary)? = NewsSummaryOutcome.from(status: 200, body: ok) else { return XCTFail("a summary") }
        XCTAssertEqual(summary.points, ["Rada przegłosowała.", "Linia do 2028."])
        XCTAssertEqual(summary.writerName, "Claude Haiku")
        XCTAssertNotNil(summary.createdDate)
        XCTAssertNil(NewsSummaryOutcome.from(status: 200, body: json("{}")), "an unreadable 200 is an error, not a summary")
        XCTAssertNil(NewsSummaryOutcome.from(status: 200, body: json(#"{"url":"u","language":"en","points":[],"whyItMatters":"w","provider":"anthropic","model":"m","createdAt":"c"}"#)))
    }

    func testEveryRefusalSaysWhy() {
        XCTAssertEqual(NewsSummaryOutcome.from(status: 422, body: json(#"{"error":"unreadable","reason":"paywall"}"#)), .unreadable(.paywall))
        XCTAssertEqual(NewsSummaryOutcome.from(status: 422, body: json(#"{"error":"unreadable","reason":"not_allowed"}"#)), .unreadable(.notAllowed))
        XCTAssertEqual(NewsSummaryOutcome.from(status: 422, body: json(#"{"error":"unreadable","reason":"something_new"}"#)), .unreadable(nil))
        XCTAssertEqual(NewsSummaryOutcome.from(status: 429, body: json(#"{"error":"limit_reached","scope":"account"}"#)), .limitReached(serverWide: false))
        XCTAssertEqual(NewsSummaryOutcome.from(status: 429, body: json(#"{"error":"limit_reached","scope":"server"}"#)), .limitReached(serverWide: true))
        XCTAssertEqual(NewsSummaryOutcome.from(status: 503, body: json(#"{"error":"not_configured"}"#)), .notConfigured)
        // The rate limiter's own 429, the model failing and an unsafe address stay ServerError.
        XCTAssertNil(NewsSummaryOutcome.from(status: 429, body: json(#"{"statusCode":429,"error":"Too Many Requests"}"#)))
        XCTAssertNil(NewsSummaryOutcome.from(status: 502, body: json(#"{"error":"summary_failed"}"#)))
        XCTAssertNil(NewsSummaryOutcome.from(status: 400, body: json(#"{"error":"unsafe_url"}"#)))
        XCTAssertEqual(DoddyServerClient.error(from: ServerResponse(status: 502, body: json(#"{"error":"summary_failed"}"#))), .providerUnavailable)
    }

    func testTheCatalogsShelvesAndPublishers() throws {
        let body = json(#"{"topics":[{"id":"world","label":"Świat","sources":["BBC News"],"group":"news","groupLabel":"Wiadomości","publishers":[{"name":"BBC News","domain":"feeds.bbci.co.uk"}]},{"id":"crypto","label":"Kryptowaluty","sources":["CoinDesk"],"group":"money","groupLabel":"Pieniądze","publishers":[{"name":"CoinDesk","domain":"coindesk.com"}]},{"id":"poland","label":"Polska","sources":["TVN24"],"group":"news","groupLabel":"Wiadomości","publishers":[{"name":"TVN24","domain":"tvn24.pl"}]}]}"#)
        struct List: Decodable { let topics: [NewsCatalogTopic] }
        let topics = try JSONDecoder().decode(List.self, from: body).topics
        XCTAssertEqual(topics[0].publisherList, [.init(name: "BBC News", domain: "feeds.bbci.co.uk")])
        let shelves = NewsCatalogShelves.group(topics, polish: true)
        XCTAssertEqual(shelves.map(\.label), ["Wiadomości", "Pieniądze"])
        XCTAssertEqual(shelves[0].topics.map(\.id), ["world", "poland"])
        // A server from before 13 Nov: names only, one shelf.
        let old = [NewsCatalogTopic(id: "ai", label: "AI", sources: ["TechCrunch", "The Verge"])]
        XCTAssertEqual(old[0].publisherList.map(\.name), ["TechCrunch", "The Verge"])
        XCTAssertNil(old[0].publisherList[0].domain)
        XCTAssertEqual(NewsCatalogShelves.group(old, polish: false).map(\.label), ["Topics"])
    }
}
