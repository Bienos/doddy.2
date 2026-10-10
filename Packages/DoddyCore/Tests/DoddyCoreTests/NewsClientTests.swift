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
        XCTAssertEqual(s.available.writerName, "Claude, by Anthropic", "servers before ADR-197 only had Claude")
        let openAI = #"{"writer":true,"writerProvider":"openai","keywordSearch":false}"#
        XCTAssertEqual(try JSONDecoder().decode(NewsSettings.Available.self, from: Data(openAI.utf8)).writerName, "GPT, by OpenAI")
        let map = { (status: Int, body: String) in DoddyServerClient.error(from: ServerResponse(status: status, body: Data(body.utf8))) }
        XCTAssertEqual(map(400, #"{"error":"unsafe_url"}"#), .unsafeURL)
        XCTAssertEqual(map(422, #"{"error":"not_a_feed"}"#), .notAFeed)
        XCTAssertEqual(map(400, #"{"error":"no_topics"}"#), .notEnabled("no_topics"))
    }

    func testDigestDeliveryTextNeverOverclaims() throws {
        func digest(_ status: String, _ error: String? = nil) throws -> NewsDigest {
            let errorJSON = error.map { "\"\($0)\"" } ?? "null"
            let json = #"{"id":"6f1c2b1e-1d9a-4c55-9a51-0b1b6f5f1a01","status":"\#(status)","aiWritten":false,"errorCode":\#(errorJSON),"createdAt":"2026-10-10T08:00:00Z","items":[]}"#
            return try JSONDecoder().decode(NewsDigest.self, from: Data(json.utf8))
        }
        XCTAssertEqual(try digest("queued").deliveryText, "Sent to you")
        XCTAssertEqual(try digest("ready").deliveryText, "In the app only")
        XCTAssertTrue(try digest("ready", "no_channel").deliveryText.contains("nothing was sent"))
        XCTAssertEqual(try digest("empty", "no_topics").deliveryText, "Nothing new that day")
        XCTAssertFalse(try digest("failed", "build_error").deliveryText.contains("Sent"))
    }
}
