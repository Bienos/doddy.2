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

    func testFollowingRunsAtOnceAndSaysExactlyWhat() throws {
        // Decision 2026-11-11-asked-for-runs-at-once: following a topic is one of Doddy's own small things,
        // undone by unfollowing, so it runs at once with no card.
        let ask = NewsFollowAsk.words(name: "CPK", keywords: ["CPK", "lotnisko"])
        let need = AskFirst.need(for: .followNews(ask))
        XCTAssertEqual(need, .runsNow)
        XCTAssertFalse(AskFirst.needsTap(need))
        XCTAssertEqual(AskFirst.need(for: .followNews(.topic(id: "poland"))), .runsNow)
        XCTAssertTrue(AskFirst.ownSmallActions.contains(VoiceToolName.followNews))
        // What is followed is still described exactly.
        XCTAssertEqual(ask.cardLines, ["“CPK”", "Stories with: CPK, lotnisko", "Shown in Following, in Home's menu"])
        XCTAssertEqual(NewsFollowAsk.topic(id: "poland").cardLines.first, "Topic: What's happening in Poland")
        let descriptor = try XCTUnwrap(ToolCatalog.descriptor("follow_news"))
        XCTAssertEqual(descriptor.effect, .localChange)
        XCTAssertEqual(descriptor.approval, .runsNow)
        XCTAssertNil(VoiceConnection.serving(VoiceToolName.followNews), "no Connections switch serves it")
        XCTAssertFalse(ConnectionPause.applies(to: .followNews(.topic(id: "sport"))), "Doddy's own feature, outside Pause all")
        // CarProfile is unchanged by the decision: it still waits until the user isn't driving.
        guard case .refuse = CarProfile.decision(for: .followNews(.topic(id: "sport"))) else { return XCTFail("not while driving (CarProfile)") }
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
        XCTAssertEqual(ActivityApp.news.title, "On my radar")
    }

    func testAlertsAskedByVoice() throws {
        // Words alone mean "as it happens".
        let ask = try XCTUnwrap(NewsFollowAsk.parse(topic: nil, name: "CPK", words: nil, alertWords: ["lotnisko"]).get())
        XCTAssertEqual(ask.base, .words(name: "CPK", keywords: ["CPK"]))
        XCTAssertEqual(ask.alertAsk?.how, .instant)
        XCTAssertEqual(ask.alertAsk?.words, ["lotnisko"])
        // A time alone means one summary a day.
        let daily = try XCTUnwrap(NewsFollowAsk.parse(topic: "sport", name: nil, words: nil, tellMe: "daily", dailyTime: "08:30").get())
        XCTAssertEqual(daily.alertAsk?.how, .daily)
        XCTAssertEqual(daily.alertAsk?.dailyTime, "08:30")
        // No alert arguments: the follow is as before.
        XCTAssertEqual(try NewsFollowAsk.parse(topic: "sport", name: nil, words: nil).get(), .topic(id: "sport"))
        // The sheet's own refusals: a whole topic as it happens needs words; bad time; bad mode; bad words.
        let refused: [Result<NewsFollowAsk, NewsFollowRefusal>] = [
            NewsFollowAsk.parse(topic: "sport", name: nil, words: nil, tellMe: "instant"),
            NewsFollowAsk.parse(topic: "sport", name: nil, words: nil, alertWords: ["x"]),
            NewsFollowAsk.parse(topic: "sport", name: nil, words: nil, alertWords: ["ok words"], tellMe: "weekly"),
            NewsFollowAsk.parse(topic: "sport", name: nil, words: nil, tellMe: "daily", dailyTime: "25:99"),
        ]
        for result in refused {
            guard case .failure = result else { return XCTFail("should be refused") }
        }
        XCTAssertEqual(NewsFollowAsk.parse(topic: "sport", name: nil, words: nil, tellMe: "app"), .success(.alerting(.topic(id: "sport"), NewsFollowAlertAsk(words: [], how: .app, dailyTime: "18:00"))))
        XCTAssertEqual(ask.name, "CPK")
        XCTAssertEqual(ask.cardLines.count, 4, "the card also says how the alert works")
    }

    func testTheReplySaysWhatTheAlertEndedAs() {
        let follow = NewsFollow.words(label: "CPK", keywords: ["CPK"])
        let kept = RadarAlert(followID: follow.id, words: ["lotnisko"], how: .instant)
        XCTAssertTrue(VoiceToolReply.newsFollow(.added(follow), alert: .kept(kept)).contains("alert kept"))
        XCTAssertTrue(VoiceToolReply.newsFollow(.added(follow), alert: .hereOnly(reason: "no server")).contains("alert not on the server"))
        XCTAssertEqual(VoiceToolReply.newsFollow(.full, alert: .kept(kept)), VoiceToolReply.newsFollow(.full), "nothing added: no alert claim")
        XCTAssertEqual(VoiceToolReply.newsFollow(.added(follow), alert: nil), VoiceToolReply.newsFollow(.added(follow)))
    }
}
