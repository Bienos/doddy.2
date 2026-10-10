import XCTest
@testable import DoddyCore

final class NewsClientTests: XCTestCase {
    func testTopicsEncodeAsCatalogOrOwnKeywords() throws {
        let update = NewsSettingsUpdate(
            enabled: true, sendTime: "08:00", timezone: "Europe/Warsaw", channels: [.push], language: "pl",
            topics: [NewsTopic(catalogId: "ai", label: "AI"), NewsTopic(label: "Coffee", keywords: ["espresso"])], feeds: [])
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(update)) as! [String: Any]
        let topics = json["topics"] as! [[String: Any]]
        XCTAssertEqual(topics[0] as NSDictionary, ["catalogId": "ai"])
        XCTAssertEqual(topics[1] as NSDictionary, ["label": "Coffee", "keywords": ["espresso"]])
    }

    func testKeywordParsing() {
        XCTAssertEqual(NewsTopic.keywords(from: " espresso, flat white ,x, "), ["espresso", "flat white"])
    }

    func testSettingsAndErrorsDecode() throws {
        let json = #"{"available":{"writer":true,"keywordSearch":false},"enabled":true,"sendTime":"08:00","timezone":"Europe/Warsaw","channels":["push","sms"],"language":"en","nextRunAt":"2026-10-11T06:00:00.000Z","topics":[{"catalogId":"ai","label":"AI","keywords":[]}],"feeds":[{"url":"https://x.com/f","title":null,"failing":true}]}"#
        let s = try JSONDecoder().decode(NewsSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.channels, [.push, .sms])
        XCTAssertTrue(s.feeds[0].failing)
        let map = { (status: Int, body: String) in DoddyServerClient.error(from: ServerResponse(status: status, body: Data(body.utf8))) }
        XCTAssertEqual(map(400, #"{"error":"unsafe_url"}"#), .unsafeURL)
        XCTAssertEqual(map(422, #"{"error":"not_a_feed"}"#), .notAFeed)
        XCTAssertEqual(map(400, #"{"error":"no_topics"}"#), .notEnabled("no_topics"))
    }
}
