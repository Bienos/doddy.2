import Foundation
import XCTest
@testable import DoddyCore

/// Decision 2026-11-12-voice-conversations-per-account: deleting a Doddy account also deletes its voice conversations
/// at ElevenLabs, through the voice server. The app says "deleted" only when the server confirmed all of them (DOD-08):
/// the server reads each conversation back and answers counts, and `pending` is what it could not confirm gone.
final class VoiceConversationErasureTests: XCTestCase {
    private func reply(_ json: String) -> Data { Data(json.utf8) }

    // MARK: What the server's answer means

    func testNothingPendingIsConfirmed() {
        let attempt = VoiceConversationErasure.attempt(status: 200, body: reply(#"{"deleted":3,"pending":0}"#))
        XCTAssertEqual(attempt, .answered(deleted: 3, pending: 0))
        XCTAssertEqual(VoiceConversationErasure.outcome(attempt), .deleted(count: 3))
        XCTAssertEqual(VoiceConversationErasure.outcome(attempt).finalLine, .deleted)
    }

    func testAnythingPendingIsNeverCalledDeleted() {
        for (deleted, pending) in [(0, 1), (2, 1), (0, 40), (299, 1)] {
            let attempt = VoiceConversationErasure.attempt(status: 200, body: reply(#"{"deleted":\#(deleted),"pending":\#(pending)}"#))
            let outcome = VoiceConversationErasure.outcome(attempt)
            XCTAssertEqual(outcome, .stillDeleting(pending: pending), "\(deleted) deleted, \(pending) pending")
            XCTAssertEqual(outcome.finalLine, .stillDeleting)
            XCTAssertNotEqual(outcome.finalLine, .deleted)
            XCTAssertTrue(outcome.mayContinue, "the server owns the retry, so the account deletion can go on")
        }
    }

    func testNothingThereIsSaidNowhere() {
        let outcome = VoiceConversationErasure.outcome(VoiceConversationErasure.attempt(status: 200, body: reply(#"{"deleted":0,"pending":0}"#)))
        XCTAssertEqual(outcome, .nothingToDelete)
        XCTAssertNil(outcome.finalLine, "no claim about conversations when there were none to delete")
        XCTAssertTrue(outcome.mayContinue)
    }

    func testAnAnswerThatIsNotCountsIsNotConfirmed() {
        let bad = [
            "", "not json", "[]", "{}", #"{"deleted":1}"#, #"{"pending":0}"#, #"{"deleted":"1","pending":"0"}"#,
            #"{"deleted":1.5,"pending":0}"#, #"{"deleted":-1,"pending":0}"#, #"{"deleted":0,"pending":-1}"#,
            #"{"deleted":null,"pending":null}"#, #"{"error":"server_not_configured"}"#,
        ]
        for json in bad {
            let attempt = VoiceConversationErasure.attempt(status: 200, body: reply(json))
            XCTAssertEqual(attempt, .failed, json.debugDescription)
            XCTAssertEqual(VoiceConversationErasure.outcome(attempt), .notConfirmed)
        }
    }

    func testOtherAnswersAreNotConfirmedAndStopTheDeletion() {
        for status in [0, 201, 204, 301, 401, 403, 404, 408, 429, 500, 502, 503, 504] {
            let attempt = VoiceConversationErasure.attempt(status: status, body: reply(#"{"deleted":3,"pending":0}"#))
            XCTAssertEqual(attempt, .failed, "\(status)")
            let outcome = VoiceConversationErasure.outcome(attempt)
            XCTAssertEqual(outcome, .notConfirmed)
            XCTAssertFalse(outcome.mayContinue, "the person stays signed in and tries again (as for the messaging server)")
            XCTAssertNil(outcome.finalLine)
        }
        XCTAssertEqual(VoiceConversationErasure.outcome(.failed), .notConfirmed, "offline, timed out, anything else")
    }

    func testAServerWithoutTheActionClaimsNothingAndDoesNotBlockTheDeletion() {
        // A server from before this answers 400 unknown_action: it recorded nothing and can delete nothing, so the
        // account can still be deleted, but nothing is said about voice conversations.
        let attempt = VoiceConversationErasure.attempt(status: 400, body: reply(#"{"error":"unknown_action"}"#))
        XCTAssertEqual(attempt, .notSupported)
        let outcome = VoiceConversationErasure.outcome(attempt)
        XCTAssertEqual(outcome, .serverCannotDelete)
        XCTAssertTrue(outcome.mayContinue)
        XCTAssertNil(outcome.finalLine)
    }

    func testOtherBadRequestsAreNotTreatedAsAnOldServer() {
        for json in [#"{"error":"invalid_request"}"#, "", "not json", #"{"error":"unknown_provider"}"#, #"{"error":7}"#] {
            XCTAssertEqual(VoiceConversationErasure.attempt(status: 400, body: reply(json)), .failed, json.debugDescription)
        }
    }

    func testOnlyOneOutcomeCanSayDeleted() {
        let outcomes: [VoiceConversationErasure.Outcome] = [
            .nothingToDelete, .stillDeleting(pending: 2), .serverCannotDelete, .notConfirmed, .deleted(count: 1),
        ]
        XCTAssertEqual(outcomes.filter { $0.finalLine == .deleted }, [.deleted(count: 1)])
        XCTAssertEqual(outcomes.filter { !$0.mayContinue }, [.notConfirmed])
    }

    // MARK: What is sent

    func testTheRequestNamesTheActionAndCarriesOnlyAValidInstallId() {
        let install = "0F8FAD5B-D9CB-469F-A165-70867728950E"
        XCTAssertEqual(VoiceConversationErasure.requestBody(installID: install),
                       ["action": "delete-conversations", "installUserId": "0f8fad5b-d9cb-469f-a165-70867728950e"],
                       "the server only takes the shape the app makes, in lower case")
        XCTAssertEqual(VoiceConversationErasure.requestBody(installID: nil), ["action": "delete-conversations"])
        for stored in ["", "user", "anonymous", "not-a-uuid", "0f8fad5b-d9cb-469f-a165-70867728950e0", " 0f8fad5b-d9cb-469f-a165-70867728950e"] {
            XCTAssertEqual(VoiceConversationErasure.requestBody(installID: stored), ["action": "delete-conversations"], stored.debugDescription)
        }
    }

    func testTheInstallIdIsTheOneTheAppMakes() {
        let made = UUID().uuidString.lowercased()
        XCTAssertEqual(VoiceConversationErasure.installUserID(made), made)
        XCTAssertNil(VoiceConversationErasure.installUserID(nil))
    }
}
