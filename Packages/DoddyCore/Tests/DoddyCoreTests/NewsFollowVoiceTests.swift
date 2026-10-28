import XCTest
@testable import DoddyCore

/// ADR-657: "śledź CPK" by voice. A change, so a card and a tap; said as followed only once the
/// follow list has it.
final class NewsFollowVoiceTests: XCTestCase {
    private func parse(_ json: String) -> VoiceToolRequest {
        VoiceToolRequest.parse(name: "follow_news", parametersJSON: Data(json.utf8))
    }

    func testOwnWordsTopicsAndRefusals() {
        XCTAssertEqual(parse(#"{"name":"CPK"}"#), .followNews(.words(name: "CPK", keywords: ["CPK"])),
                       "no words given: the name is the word to look for")
        XCTAssertEqual(parse(#"{"name":"CPK","words":["CPK","lotnisko"]}"#), .followNews(.words(name: "CPK", keywords: ["CPK", "lotnisko"])))
        XCTAssertEqual(parse(#"{"name":"Kawa","words":"espresso"}"#), .followNews(.words(name: "Kawa", keywords: ["espresso"])),
                       "a single string counts as one word")
        XCTAssertEqual(parse(#"{"topic":" Sport ","name":"ignored"}"#), .followNews(.topic(id: "sport")), "a topic wins over a name")
        for bad in [#"{}"#, #"{"topic":"weather"}"#, #"{"name":"x"}"#, #"{"name":"   "}"#,
                    #"{"name":"\#(String(repeating: "a", count: 61))"}"#] {
            guard case .invalid(let name, _) = parse(bad) else { return XCTFail(bad) }
            XCTAssertEqual(name, "follow_news")
        }
    }

    func testTheTopicListMatchesTheServersCatalog() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let ts = try String(contentsOf: root.appendingPathComponent("server/messaging/src/news/catalog.ts"), encoding: .utf8)
        let ids = try NSRegularExpression(pattern: #"\{ id: "([a-z]+)""#)
            .matches(in: ts, range: NSRange(ts.startIndex..., in: ts))
            .compactMap { Range($0.range(at: 1), in: ts).map { String(ts[$0]) } }
        XCTAssertEqual(ids, NewsFollowAsk.catalog.map(\.id))
    }

    func testFollowingNeedsATapAndShowsExactlyWhat() throws {
        let need = AskFirst.need(for: .followNews(.words(name: "CPK", keywords: ["CPK", "lotnisko"])))
        guard case .tapFirst(let card) = need else { return XCTFail("\(need)") }
        XCTAssertEqual(card.title, "Follow this?")
        XCTAssertEqual(card.confirmLabel, "Follow")
        XCTAssertEqual(card.lines, ["“CPK”", "Stories with: CPK, lotnisko", "Shown in Following, in Home's menu"])
        XCTAssertTrue(AskFirst.needsTap(need))
        guard case .tapFirst(let topic) = AskFirst.need(for: .followNews(.topic(id: "poland"))) else { return XCTFail() }
        XCTAssertEqual(topic.lines.first, "Topic: What's happening in Poland")
        let descriptor = try XCTUnwrap(ToolCatalog.descriptor("follow_news"))
        XCTAssertEqual(descriptor.effect, .localChange)
        XCTAssertEqual(descriptor.approval, .card)
        XCTAssertNil(VoiceConnection.serving(VoiceToolName.followNews), "no Connections switch serves it")
        XCTAssertFalse(ConnectionPause.applies(to: .followNews(.topic(id: "sport"))), "Doddy's own feature, outside Pause all")
        guard case .refuse = CarProfile.decision(for: .followNews(.topic(id: "sport"))) else { return XCTFail("needs a tap, not while driving") }
    }

    func testAddedOnlyWhenTheListHasIt() {
        var list = NewsFollowList.initial(polish: true)
        let poland = NewsFollowAsk.topic(id: "poland").follow(polish: true)
        XCTAssertEqual(NewsFollowOutcome.apply(poland, to: &list), .alreadyFollowing(poland),
                       "asking for Poland again is the default follow, not a second one")
        let cpk = NewsFollowAsk.words(name: "CPK", keywords: ["CPK"]).follow(polish: true)
        XCTAssertEqual(NewsFollowOutcome.apply(cpk, to: &list), .added(cpk))
        XCTAssertEqual(list.follows.map(\.label), ["Co się dzieje w Polsce", "CPK"])
        for i in 0..<8 { list.add(.words(label: "w\(i)", keywords: ["x\(i)"])) }
        XCTAssertEqual(NewsFollowOutcome.apply(.topic(id: "sport", label: "Sport"), to: &list), .full)
        XCTAssertEqual(list.follows.count, NewsFollowList.maxFollows)
    }

    func testRepliesAreClassifiedAndCarryTheNameAsData() throws {
        let cpk = NewsFollow.words(label: "CPK", keywords: ["CPK"])
        let added = VoiceToolReply.newsFollow(.added(cpk))
        XCTAssertTrue(added.hasPrefix("added:"))
        XCTAssertTrue(added.contains("<<<DATA") && added.contains("CPK"))
        XCTAssertEqual(ActivityEntry.outcome(of: added, isLookup: false).0, .done)
        for outcome in [NewsFollowOutcome.alreadyFollowing(cpk), .full, .notKept] {
            let reply = VoiceToolReply.newsFollow(outcome)
            XCTAssertTrue(reply.hasPrefix("failed:"), reply)
            XCTAssertEqual(ActivityEntry.outcome(of: reply, isLookup: false).0, .notDone)
        }
        let row = try XCTUnwrap(ActivityRequest.describe(.followNews(.words(name: "CPK", keywords: ["CPK"])), calendar: .current))
        XCTAssertEqual(row.app, .news)
        XCTAssertEqual(row.title, "Follow in Following")
        XCTAssertEqual(row.detail, "“CPK”")
        XCTAssertFalse(row.isLookup)
        XCTAssertEqual(ActivityText.title("Follow in Following", .polish), "Śledź w Śledzonych")
        XCTAssertEqual(ActivityApp.news.title, "Following")
    }
}
