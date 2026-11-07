import XCTest
@testable import DoddyCore

final class NewsFollowingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_793_620_800) // 2026-11-02T12:00:00Z (a Monday)

    func testANewPersonFollowsPolandOnly() {
        XCTAssertEqual(NewsFollowList.initial(polish: true).follows, [.topic(id: "poland", label: "Co się dzieje w Polsce")])
        XCTAssertEqual(NewsFollowList.initial(polish: false).follows, [.topic(id: "poland", label: "What's happening in Poland")])
        XCTAssertEqual(NewsFollowList.decode(nil, polish: true), .initial(polish: true), "nothing stored yet")
        XCTAssertEqual(NewsFollowList.decode(Data("garbage".utf8), polish: false), .initial(polish: false), "unreadable storage falls back")
    }

    func testFollowsAreUniqueAndCapped() {
        var list = NewsFollowList.initial(polish: true)
        XCTAssertFalse(list.add(.topic(id: "poland", label: "Polska")), "the same topic under another label is still the same follow")
        XCTAssertTrue(list.add(.words(label: "CPK", keywords: ["CPK"])))
        XCTAssertFalse(list.add(.words(label: "cpk", keywords: ["lotnisko"])), "a name differing only in case is the same follow")
        for i in 0..<20 { list.add(.words(label: "w\(i)", keywords: ["x\(i)"])) }
        XCTAssertEqual(list.follows.count, NewsFollowList.maxFollows)
        XCTAssertTrue(list.isFull)
        list.remove(id: "words:cpk")
        XCTAssertFalse(list.follows.contains { $0.label == "CPK" })
        XCTAssertEqual(NewsFollowList(follows: [.words(label: "A", keywords: ["a"]), .words(label: "a", keywords: ["b"])]).follows.count, 1)
    }

    func testOwnWordsNeedANameAndKeywords() {
        XCTAssertNil(NewsFollowList.words(name: "  ", keywordsText: "CPK, lotnisko"))
        XCTAssertNil(NewsFollowList.words(name: "CPK", keywordsText: "x"), "one-letter words are not keywords")
        XCTAssertNil(NewsFollowList.words(name: String(repeating: "a", count: 61), keywordsText: "CPK"))
        XCTAssertEqual(NewsFollowList.words(name: " CPK ", keywordsText: "CPK, lotnisko ,x"), .words(label: "CPK", keywords: ["CPK", "lotnisko"]))
    }

    func testRequestMatchesTheServersShape() throws {
        var list = NewsFollowList.initial(polish: true)
        list.add(.words(label: "Kawa", keywords: ["espresso"]))
        let request = try XCTUnwrap(list.request(language: "pl", limit: 99))
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as! [String: Any]
        XCTAssertEqual(json["language"] as? String, "pl")
        XCTAssertEqual(json["limit"] as? Int, NewsFeedRequest.maxCards, "the limit never exceeds what the server takes")
        let follows = json["follows"] as! [[String: Any]]
        XCTAssertEqual(follows[0] as NSDictionary, ["catalogId": "poland"])
        XCTAssertEqual(follows[1] as NSDictionary, ["label": "Kawa", "keywords": ["espresso"]])
        XCTAssertNil(NewsFollowList(follows: []).request(language: "pl"), "nothing followed: nothing asked")
        XCTAssertEqual(list.request(language: "de")?.language, "en", "the server knows English and Polish")
    }

    func testStoredAndReadBack() throws {
        var list = NewsFollowList.initial(polish: false)
        list.add(.words(label: "Coffee", keywords: ["espresso", "flat white"]))
        XCTAssertEqual(NewsFollowList.decode(try list.encoded(), polish: true), list)
    }

    func testMoveKeepsEveryFollow() {
        var list = NewsFollowList(follows: [.words(label: "A", keywords: ["a"]), .words(label: "B", keywords: ["b"]), .words(label: "C", keywords: ["c"])])
        list.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertEqual(list.follows.map(\.label), ["C", "A", "B"])
        list.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        XCTAssertEqual(list.follows.map(\.label), ["A", "B", "C"])
    }

    func testCardsDecodeAndNeverInventWhatTheServerDidNotSay() throws {
        let json = #"{"fetchedAt":"2026-11-02T11:59:00.000Z","keywordSearch":false,"cards":[{"id":"ab12","title":"Sejm uchwalił budżet","summary":"","url":"https://tvn24.pl/1","source":"TVN24","publishedAt":"2026-11-02T10:00:00.000Z","imageUrl":"https://cdn.tvn24.pl/1.jpg","follows":["Polska"]},{"id":"cd34","title":"Old one","summary":"S","url":"javascript:alert(1)","source":"","publishedAt":"not a date","imageUrl":"http://x/1.jpg","follows":[]}]}"#
        let page = try JSONDecoder().decode(NewsFeedPage.self, from: Data(json.utf8))
        XCTAssertFalse(page.keywordSearch)
        let card = page.cards[0]
        XCTAssertEqual(card.link, URL(string: "https://tvn24.pl/1"))
        XCTAssertEqual(card.image, URL(string: "https://cdn.tvn24.pl/1.jpg"))
        XCTAssertEqual(card.sourceInitial, "T")
        XCTAssertEqual(card.ageText(now: now, polish: true), "2 godz. temu")
        XCTAssertEqual(card.ageText(now: now, polish: false), "2 h ago")
        XCTAssertEqual(card.noteText, "Sejm uchwalił budżet\nTVN24 · https://tvn24.pl/1")
        let odd = page.cards[1]
        XCTAssertNil(odd.link, "a link that isn't http(s) is not tappable")
        XCTAssertNil(odd.image, "an http picture is not loaded")
        XCTAssertNil(odd.publishedDate)
        XCTAssertNil(odd.ageText(now: now, polish: true))
        XCTAssertEqual(odd.sourceInitial, "•")
    }

    func testAgeTextSteps() throws {
        func card(minutesAgo: Int) -> NewsCard {
            NewsCard(id: "x", title: "t", summary: "", url: "https://x", source: "X",
                     publishedAt: ServerDates.format(now.addingTimeInterval(TimeInterval(-minutesAgo * 60))), follows: [])
        }
        XCTAssertEqual(card(minutesAgo: 0).ageText(now: now, polish: false), "just now")
        XCTAssertEqual(card(minutesAgo: 5).ageText(now: now, polish: true), "5 min temu")
        XCTAssertEqual(card(minutesAgo: 26 * 60).ageText(now: now, polish: false), "yesterday")
        XCTAssertEqual(card(minutesAgo: 26 * 60).ageText(now: now, polish: true), "wczoraj")
        XCTAssertEqual(card(minutesAgo: 3 * 24 * 60).ageText(now: now, polish: true), "3 dni temu")
    }

    func testSectionsByDayNewestFirstUndatedLast() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        func card(_ id: String, hoursAgo: Double?) -> NewsCard {
            NewsCard(id: id, title: id, summary: "", url: "https://x/\(id)", source: "X",
                     publishedAt: hoursAgo.map { ServerDates.format(now.addingTimeInterval(-$0 * 3600)) } ?? "?", follows: [])
        }
        let sections = NewsFeedSections.group([card("undated", hoursAgo: nil), card("older", hoursAgo: 3), card("y", hoursAgo: 20),
                                               card("fresh", hoursAgo: 1), card("e", hoursAgo: 50)], now: now, calendar: calendar)
        XCTAssertEqual(sections.map(\.day), [.today, .yesterday, .earlier])
        XCTAssertEqual(sections[0].cards.map(\.id), ["fresh", "older"])
        XCTAssertEqual(sections[1].cards.map(\.id), ["y"])
        XCTAssertEqual(sections[2].cards.map(\.id), ["e", "undated"])
        XCTAssertEqual(NewsFeedDay.yesterday.title(polish: true), "Wczoraj")
        XCTAssertTrue(NewsFeedSections.group([], now: now).isEmpty)
    }
}
