import Foundation
import XCTest
@testable import DoddyCore

/// Decision 2026-11-12-voice-conversations-per-account: the voice server answers a token request with `userId`, a
/// keyed hash of the Doddy account, and the app gives it to ElevenLabs as the conversation's user so deleting the
/// account can find its conversations. A server without it (or a value that isn't one) leaves the conversation on
/// this iPhone's own random id, as before.
final class VoiceUserIDTests: XCTestCase {
    private let install = "0f8fad5b-d9cb-469f-a165-70867728950e"
    private let account = "3b1d6a4e5f7c8091a2b3c4d5e6f70812"

    // MARK: The choice

    func testTheServersAccountIdWinsOverTheInstallId() {
        XCTAssertEqual(VoiceUserIDPolicy.userID(server: account, install: install), account)
    }

    func testWithoutAServerIdTheInstallIdIsUsedAsBefore() {
        XCTAssertEqual(VoiceUserIDPolicy.userID(server: nil, install: install), install)
    }

    func testAnIdThatIsNotTheServersKindIsNotPassedOn() {
        let bad: [String] = [
            "", " ", "short", String(repeating: "a", count: 15), String(repeating: "a", count: 129),
            " \(account)", "\(account) ", "\(account)\n", "with space in it 1234567", "slash/in/the/id/12345",
            "dot.in.the.id.1234567", "ünïcode-id-1234567890", "emoji-🙂-id-1234567890", "query?x=1&y=2-1234567",
        ]
        for value in bad {
            XCTAssertNil(VoiceUserIDPolicy.accepted(value), "\(value.debugDescription)")
            XCTAssertEqual(VoiceUserIDPolicy.userID(server: value, install: install), install, "\(value.debugDescription)")
        }
    }

    func testTheShapesTheServerMakesAreAccepted() {
        for value in [account, String(repeating: "0", count: 32), "A_b-C_d-E_f-G_h-1234", String(repeating: "z", count: 16), String(repeating: "z", count: 128)] {
            XCTAssertEqual(VoiceUserIDPolicy.accepted(value), value)
        }
    }

    func testTheInstallIdIsNeverChangedOrChecked() {
        // It is what ElevenLabs has always had for this iPhone; the policy only falls back to it.
        XCTAssertEqual(VoiceUserIDPolicy.userID(server: nil, install: "anything"), "anything")
        XCTAssertEqual(VoiceUserIDPolicy.userID(server: nil, install: ""), "")
    }

    // MARK: Reading the token answer

    private func answer(_ json: String) -> Data { Data(json.utf8) }

    func testTheTokenAnswerCarriesTheUserId() {
        XCTAssertEqual(VoiceTokenServer.userID(fromAnswer: answer(#"{"token":"t","userId":"\#(account)"}"#)), account)
    }

    func testAnAnswerWithoutAUsableUserIdGivesNone() {
        for json in [
            #"{"token":"t"}"#, #"{"token":"t","userId":null}"#, #"{"token":"t","userId":7}"#, #"{"token":"t","userId":""}"#,
            #"{"token":"t","userId":"short"}"#, #"{"token":"t","userId":["\#(account)"]}"#, #"{"token":"t","userId":"has space 1234567890"}"#,
            "not json", "[]", "",
        ] {
            XCTAssertNil(VoiceTokenServer.userID(fromAnswer: answer(json)), json)
        }
    }

    func testTheTokenItselfIsReadAsBefore() {
        // An answer with the new field is still a token answer; one without it still works.
        XCTAssertEqual(try VoiceTokenServer.token(status: 200, body: answer(#"{"token":"abc","userId":"\#(account)"}"#)).get(), "abc")
        XCTAssertEqual(try VoiceTokenServer.token(status: 200, body: answer(#"{"token":"abc"}"#)).get(), "abc")
    }

    // MARK: Which token it belongs to

    func testTheIdBelongsToTheTokenItCameWithAndIsTakenOnce() {
        let ids = VoiceTokenUserIDs()
        ids.remember(account, forToken: "token-1")
        ids.remember("b".repeating(32), forToken: "token-2")
        XCTAssertEqual(ids.take(forToken: "token-1"), account)
        XCTAssertNil(ids.take(forToken: "token-1"), "used once")
        XCTAssertEqual(ids.take(forToken: "token-2"), "b".repeating(32))
        XCTAssertNil(ids.take(forToken: "never-seen"))
    }

    func testAnAnswerWithoutAUserIdLeavesNothingForItsToken() {
        let ids = VoiceTokenUserIDs()
        ids.remember(account, forToken: "token-1")
        ids.remember(nil, forToken: "token-1")
        XCTAssertNil(ids.take(forToken: "token-1"), "a later answer for the same token replaces the earlier one")
        ids.remember(account, forToken: "")
        XCTAssertNil(ids.take(forToken: ""), "no token, nothing kept")
    }

    func testOnlyTheLatestFewAreKeptAndForgetClearsThemAll() {
        let ids = VoiceTokenUserIDs(capacity: 3)
        for n in 1...5 { ids.remember(String(repeating: "\(n)", count: 20), forToken: "token-\(n)") }
        XCTAssertNil(ids.take(forToken: "token-1"))
        XCTAssertNil(ids.take(forToken: "token-2"))
        XCTAssertNotNil(ids.take(forToken: "token-3"))
        ids.forget()
        XCTAssertNil(ids.take(forToken: "token-4"))
        XCTAssertNil(ids.take(forToken: "token-5"))
    }

    func testItIsSafeFromSeveralThreadsAtOnce() async {
        let ids = VoiceTokenUserIDs(capacity: 64)
        await withTaskGroup(of: Void.self) { group in
            for n in 0..<200 {
                group.addTask {
                    ids.remember(String(repeating: "a", count: 16), forToken: "token-\(n)")
                    _ = ids.take(forToken: "token-\(n / 2)")
                }
            }
        }
        ids.forget()
        XCTAssertNil(ids.take(forToken: "token-199"))
    }
}

private extension String {
    func repeating(_ count: Int) -> String { String(repeating: self, count: count) }
}
