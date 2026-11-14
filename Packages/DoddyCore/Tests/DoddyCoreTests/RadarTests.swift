import XCTest
@testable import DoddyCore

// On my radar (decision 2026-11-10-radar-alerts).
final class RadarTests: XCTestCase {
    func testMatchingAgreesWithTheServerOnTheSharedFixture() throws {
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Fixtures.data("radar_match_v1.json")) as? [String: Any])
        let cases = try XCTUnwrap(json["cases"] as? [[String: Any]])
        XCTAssertGreaterThan(cases.count, 20)
        for c in cases {
            let text = c["text"] as! String, keyword = c["keyword"] as! String, expected = c["match"] as! Bool
            XCTAssertEqual(RadarMatch.matches(text, keyword: keyword), expected, "\(keyword) in \"\(text)\"")
        }
        XCTAssertEqual(RadarMatch.matched("Rynek kryptowalut: Bitcoina kupują banki", keywords: ["bitcoin", "ETF", "kryptowaluty"]),
                       ["bitcoin", "kryptowaluty"])
    }

    func testTypingBitcoinSuggestsTheCryptoTopicThenTheWords() {
        let catalog = [NewsCatalogTopic(id: "crypto", label: "Kryptowaluty", sources: ["CoinDesk", "Decrypt", "Bitcoin.pl"])]
        let choices = RadarSuggest.choices(for: "Bitcoin", catalog: catalog, following: .initial(polish: true), polish: true)
        XCTAssertEqual(choices, [
            .topic(id: "crypto", label: "Kryptowaluty", sources: ["CoinDesk", "Decrypt", "Bitcoin.pl"]),
            .words(label: "Bitcoin", keywords: ["Bitcoin"]),
        ])
        XCTAssertEqual(RadarSuggest.choices(for: "kryptowalutach", catalog: [], following: .initial(polish: false), polish: false).first,
                       .topic(id: "crypto", label: "Crypto", sources: []), "a Polish ending still finds the topic")
        XCTAssertEqual(RadarSuggest.choices(for: "sztuczna inteligencja", catalog: [], following: .initial(polish: true), polish: true).first,
                       .topic(id: "ai", label: "Sztuczna inteligencja", sources: []))
    }

    func testOwnWordsAloneWhenNoTopicFitsAndNothingAlreadyFollowedIsOfferedAgain() {
        XCTAssertEqual(RadarSuggest.choices(for: " CPK ", catalog: [], following: .initial(polish: true), polish: true),
                       [.words(label: "CPK", keywords: ["CPK"])])
        XCTAssertEqual(RadarSuggest.choices(for: "Tesla, Musk", catalog: [], following: .initial(polish: false), polish: false),
                       [.words(label: "Tesla, Musk", keywords: ["Tesla", "Musk"])])
        var list = NewsFollowList.initial(polish: true)
        list.add(.topic(id: "crypto", label: "Kryptowaluty"))
        XCTAssertEqual(RadarSuggest.choices(for: "bitcoin", catalog: [], following: list, polish: true), [.words(label: "bitcoin", keywords: ["bitcoin"])])
        XCTAssertEqual(RadarSuggest.choices(for: "x", catalog: [], following: list, polish: true), [], "one letter is nothing to look for")
    }

    func testAnAddressIsTheirOwnFeedHttpsOnly() {
        XCTAssertEqual(RadarSuggest.choices(for: "https://blog.example.com/feed.xml", catalog: [], following: .initial(polish: true), polish: true),
                       [.feed(url: "https://blog.example.com/feed.xml")])
        XCTAssertEqual(RadarSuggest.choices(for: "blog.example.com/rss", catalog: [], following: .initial(polish: true), polish: true),
                       [.feed(url: "https://blog.example.com/rss")], "no scheme: https is assumed")
        XCTAssertEqual(RadarSuggest.choices(for: "http://blog.example.com/rss", catalog: [], following: .initial(polish: true), polish: true), [],
                       "plain http is not offered")
        XCTAssertNil(RadarFeedAddress.normalized("https://user:pass@example.com/feed"))
        XCTAssertNil(RadarFeedAddress.normalized("https://localhost/feed"))
        XCTAssertNil(NewsFollowList.feed(name: "", url: "https://example.com/feed"))
        XCTAssertEqual(NewsFollowList.feed(name: "Mój blog", url: " https://example.com/feed ", keywordsText: "CPK"),
                       .feed(label: "Mój blog", url: "https://example.com/feed", keywords: ["CPK"]))
    }

    func testSuggestionHintsNameOnlyCatalogTopics() {
        let ids = Set(NewsFollowAsk.catalog.map(\.id))
        XCTAssertEqual(Set(RadarSuggest.hints.keys), ids)
    }

    func testAFeedFollowGoesToTheServerWithItsAddressAndKeepsItsOwnId() throws {
        var list = NewsFollowList.initial(polish: true)
        list.add(.feed(label: "Blog", url: "https://blog.example.com/feed", keywords: []))
        XCTAssertFalse(list.add(.feed(label: "blog", url: "https://other.example.com/feed", keywords: [])), "same name, same follow")
        let request = try XCTUnwrap(list.request(language: "pl"))
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as! [String: Any]
        let follows = json["follows"] as! [[String: Any]]
        XCTAssertEqual(follows[1] as NSDictionary, ["label": "Blog", "feedUrl": "https://blog.example.com/feed", "keywords": []])
        XCTAssertEqual(NewsFollowList.decode(try list.encoded(), polish: true), list, "a feed follow is kept and read back")
    }

    func testOldStoredFollowsStillReadAfterTheNewCase() throws {
        // What builds before 10 Nov 2026 wrote to "news.follows".
        let old = Data(#"{"follows":[{"topic":{"id":"poland","label":"Co się dzieje w Polsce"}},{"words":{"label":"CPK","keywords":["CPK"]}}]}"#.utf8)
        XCTAssertEqual(NewsFollowList.decode(old, polish: true).follows,
                       [.topic(id: "poland", label: "Co się dzieje w Polsce"), .words(label: "CPK", keywords: ["CPK"])])
    }

    func testOnlyAlertsThePersonLetTheServerCheckAreSentAndOnlyValidOnes() throws {
        var list = NewsFollowList.initial(polish: true)
        list.add(.topic(id: "crypto", label: "Kryptowaluty"))
        list.add(.words(label: "Tesla", keywords: ["Tesla"]))
        list.add(.words(label: "CPK", keywords: ["CPK"]))
        var alerts = RadarAlertList()
        alerts.set(RadarAlert(followID: "topic:crypto", words: ["ETF"], how: .instant))
        alerts.set(RadarAlert(followID: "words:tesla", how: .daily, dailyTime: "07:30"))
        alerts.set(RadarAlert(followID: "words:cpk", words: ["przetarg"], how: .app))
        alerts.set(RadarAlert(followID: "topic:poland", how: .instant))
        alerts.set(RadarAlert(followID: "words:gone", words: ["x"], how: .instant))
        XCTAssertEqual(alerts.alert(for: .topic(id: "poland", label: "x"))?.problem(for: .topic(id: "poland", label: "x")), .wordsNeeded,
                       "a whole topic as it happens needs words")
        XCTAssertTrue(alerts.anyServerChecks(list))
        let request = alerts.request(list, language: "pl", timeZone: "Europe/Warsaw")
        XCTAssertEqual(request.alerts.map(\.followKey), ["topic:crypto", "words:tesla"], "the in-app one, the invalid one and the removed follow stay off the server")
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as! [String: Any]
        XCTAssertEqual(json["timeZone"] as? String, "Europe/Warsaw")
        let items = json["alerts"] as! [[String: Any]]
        XCTAssertEqual(items[0] as NSDictionary, ["followKey": "topic:crypto", "label": "Kryptowaluty", "catalogId": "crypto", "keywords": [],
                                                  "alertWords": ["ETF"], "mode": "instant"])
        XCTAssertEqual(items[1] as NSDictionary, ["followKey": "words:tesla", "label": "Tesla", "keywords": ["Tesla"], "alertWords": [],
                                                  "mode": "daily", "dailyTime": "07:30"])
        XCTAssertEqual(alerts.keeping(list).alerts.count, 4, "an alert for a follow that is gone is dropped")
        XCTAssertEqual(RadarAlertList.decode(try alerts.encoded()), alerts)
        XCTAssertEqual(RadarAlertList.decode(Data("nope".utf8)), RadarAlertList())
        XCTAssertEqual(RadarAlert(followID: "a", how: .daily, dailyTime: "25:00").problem(for: .words(label: "a", keywords: ["a"])), .timeNeeded)
    }

    func testTheLineUnderAFollowSaysWhoChecksAndHow() {
        XCTAssertEqual(RadarAlert(followID: "a").summary(polish: true), "Tylko tutaj")
        XCTAssertEqual(RadarAlert(followID: "a", words: ["ETF", "zakaz"]).summary(polish: false), "Shown here only; stories that mention ETF and zakaz get a flag")
        XCTAssertEqual(RadarAlert(followID: "a", words: ["ETF"], how: .instant).summary(polish: true), "Serwer Doddy’ego da znać od razu, gdy w artykule padnie ETF")
        XCTAssertEqual(RadarAlert(followID: "a", how: .daily, dailyTime: "07:30").summary(polish: false), "Doddy's server sends a summary every day at 07:30")
    }

    func testServerStateAndReportsDecodeAndSayWhereStoriesComeFrom() throws {
        let page = #"{"fetchedAt":"2026-11-10T12:00:00.000Z","keywordSearch":false,"cards":[],"follows":[{"label":"Kryptowaluty","sources":[{"name":"CoinDesk","ok":true},{"name":"Decrypt","ok":true},{"name":"The Block","ok":false}],"cards":0},{"label":"Tesla","sources":[],"searchedFeeds":31,"cards":2}]}"#
        let decoded = try JSONDecoder().decode(NewsFeedPage.self, from: Data(page.utf8))
        let crypto = try XCTUnwrap(decoded.report(for: .topic(id: "crypto", label: "Kryptowaluty")))
        XCTAssertEqual(crypto.sourcesLine(polish: true), "Źródła: CoinDesk i Decrypt. Teraz nie odpowiada: The Block")
        XCTAssertEqual(crypto.sourcesLine(polish: false), "From CoinDesk and Decrypt. Not answering right now: The Block")
        XCTAssertEqual(decoded.report(for: .words(label: "Tesla", keywords: ["Tesla"]))?.sourcesLine(polish: false),
                       "Looking for these words in the 31 publishers' feeds Doddy reads")
        let old = #"{"fetchedAt":"x","keywordSearch":true,"cards":[]}"#
        XCTAssertNil(try JSONDecoder().decode(NewsFeedPage.self, from: Data(old.utf8)).follows, "an older server: no reports, still decodes")

        let state = #"{"available":true,"push":false,"alerts":[{"followKey":"topic:crypto","label":"Kryptowaluty","mode":"instant","dailyTime":null,"alertWords":["ETF"],"lastCheckedAt":null}],"hits":[{"id":"7c1","followKey":"topic:crypto","label":"Kryptowaluty","title":"SEC approves ETF","summary":"","url":"https://coindesk.com/1","source":"CoinDesk","publishedAt":"2026-11-10T11:00:00.000Z","matched":["ETF"],"foundAt":"2026-11-10T11:10:00.000Z","toldBy":"app","seen":false},{"id":"7c2","followKey":"topic:crypto","label":"Kryptowaluty","title":"x","summary":"","url":"javascript:1","source":"X","publishedAt":"2026-11-10T11:00:00.000Z","matched":[],"foundAt":"2026-11-10T11:10:00.000Z","toldBy":null,"seen":true}]}"#
        let s = try JSONDecoder().decode(RadarServerState.self, from: Data(state.utf8))
        XCTAssertEqual(s.unseen, 1)
        XCTAssertFalse(s.push)
        XCTAssertEqual(s.hits[0].link, URL(string: "https://coindesk.com/1"))
        XCTAssertNil(s.hits[1].link)
        XCTAssertEqual(try JSONDecoder().decode([NewsCatalogTopic].self, from: Data(#"[{"id":"crypto","label":"Crypto"}]"#.utf8))[0].sources, nil)
    }
}
