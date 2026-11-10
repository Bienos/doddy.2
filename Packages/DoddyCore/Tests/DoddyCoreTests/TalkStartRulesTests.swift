@testable import DoddyCore
import XCTest

final class TalkStartRulesTests: XCTestCase {
    func testADoddyAccountNeverRestoresTheOlderVoiceLogin() {
        XCTAssertFalse(TalkStartAccount.needsRestore(accountSignedIn: true, voiceSessionSecondsLeft: nil))
        XCTAssertFalse(TalkStartAccount.needsRestore(accountSignedIn: true, voiceSessionSecondsLeft: 0))
    }

    func testAnOlderVoiceSessionIsRestoredOnlyWhenItIsNotUsable() {
        XCTAssertTrue(TalkStartAccount.needsRestore(accountSignedIn: false, voiceSessionSecondsLeft: nil))
        XCTAssertTrue(TalkStartAccount.needsRestore(accountSignedIn: false, voiceSessionSecondsLeft: 30))
        XCTAssertFalse(TalkStartAccount.needsRestore(accountSignedIn: false, voiceSessionSecondsLeft: 600))
    }

    func testTheIntentReturnsOnceTheIslandIsUpNotAfterTheConnect() {
        XCTAssertEqual(TalkStartHandoff.decide(islandReady: false, startEnded: false, waited: 0.2), .keepWaiting)
        XCTAssertEqual(TalkStartHandoff.decide(islandReady: true, startEnded: false, waited: 0.4), .handBack)
    }

    func testARefusalOrFinishedStartIsReportedNotHandedBack() {
        XCTAssertEqual(TalkStartHandoff.decide(islandReady: false, startEnded: true, waited: 0.1), .report)
        XCTAssertEqual(TalkStartHandoff.decide(islandReady: true, startEnded: true, waited: 0.1), .report)
    }

    func testItNeverWaitsPastTheLimit() {
        XCTAssertEqual(TalkStartHandoff.decide(islandReady: false, startEnded: false, waited: TalkStartHandoff.maxWait), .handBack)
    }
}
