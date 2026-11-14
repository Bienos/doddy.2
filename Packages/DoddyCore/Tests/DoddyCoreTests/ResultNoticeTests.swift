import XCTest
@testable import DoddyCore

final class ResultNoticeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_794_444_000)
    private let task = UUID(uuidString: "02746662-6644-4bb8-b873-359970c7b3a2")!

    private func server(_ kind: ServerPushKind?, minutesAgo: Double) -> ResultNotice.Delivered {
        .init(identifier: UUID().uuidString, kind: kind, date: now.addingTimeInterval(-minutesAgo * 60))
    }

    private func local(minutesAgo: Double) -> ResultNotice.Delivered {
        .init(identifier: ResultNotice.identifier(for: UUID()), kind: .errandResult, date: now.addingTimeInterval(-minutesAgo * 60))
    }

    func testPostsWhenTheAppIsOpenAndNothingSaidItYet() {
        XCTAssertTrue(ResultNotice.shouldPost(appActive: true, threadVisible: false, delivered: [], now: now))
        // Other notifications (a reminder, a call's result) don't count.
        XCTAssertTrue(ResultNotice.shouldPost(appActive: true, threadVisible: false,
                                              delivered: [server(nil, minutesAgo: 1), server(.callResult, minutesAgo: 1), server(.fileReady, minutesAgo: 1)],
                                              now: now))
    }

    func testNeverInTheBackgroundOrWhileMessagesIsOnScreen() {
        XCTAssertFalse(ResultNotice.shouldPost(appActive: false, threadVisible: false, delivered: [], now: now),
                       "in the background only the server's push can come; the app never adds a second one")
        XCTAssertFalse(ResultNotice.shouldPost(appActive: true, threadVisible: true, delivered: [], now: now))
    }

    func testNotTwiceAboutOneResult() {
        XCTAssertFalse(ResultNotice.shouldPost(appActive: true, threadVisible: false, delivered: [server(.errandResult, minutesAgo: 2)], now: now),
                       "the server's push already said it")
        XCTAssertFalse(ResultNotice.shouldPost(appActive: true, threadVisible: false, delivered: [local(minutesAgo: 9)], now: now))
        XCTAssertTrue(ResultNotice.shouldPost(appActive: true, threadVisible: false, delivered: [server(.errandResult, minutesAgo: 11)], now: now),
                      "an old push was about another task")
    }

    func testAServerPushIsHeldBackOnlyRightAfterTheAppsOwnNotice() {
        XCTAssertFalse(ResultNotice.shouldPresentServerPush(kind: .errandResult, delivered: [local(minutesAgo: 1)], now: now))
        XCTAssertTrue(ResultNotice.shouldPresentServerPush(kind: .errandResult, delivered: [local(minutesAgo: 30)], now: now))
        XCTAssertTrue(ResultNotice.shouldPresentServerPush(kind: .errandResult, delivered: [server(.errandResult, minutesAgo: 1)], now: now))
        for kind: ServerPushKind? in [nil, .callResult, .fileReady] {
            XCTAssertTrue(ResultNotice.shouldPresentServerPush(kind: kind, delivered: [local(minutesAgo: 1)], now: now))
        }
    }

    func testTheNoticeRoutesLikeTheServersPushAndSaysNoWords() {
        XCTAssertEqual(ServerPushKind.parse(ResultNotice.userInfo), .errandResult)
        XCTAssertEqual(ServerPushKind.parse(ResultNotice.userInfo)?.opensMessages, true)
        let id = ResultNotice.identifier(for: task)
        XCTAssertTrue(ResultNotice.isLocal(identifier: id))
        XCTAssertFalse(ResultNotice.isLocal(identifier: task.uuidString))
        XCTAssertEqual(ResultNotice.userInfo["doddy"]?.keys.sorted(), ["kind"], "a kind only: the payload is readable on the Lock Screen")
    }
}
