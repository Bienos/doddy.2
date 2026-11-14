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

    func testThePressIslandStaysOnlyWhenAConversationTookItOver() {
        XCTAssertEqual(TalkIslandFirst.afterwards(shownByPress: true, conversationLive: true), .leave)
        XCTAssertEqual(TalkIslandFirst.afterwards(shownByPress: true, conversationLive: false), .end)
    }

    func testAnIslandThePressDidNotPutUpIsNeverEndedByIt() {
        // Already up (another conversation's) or refused by iOS: not the press's to end.
        XCTAssertEqual(TalkIslandFirst.afterwards(shownByPress: false, conversationLive: false), .leave)
        XCTAssertEqual(TalkIslandFirst.afterwards(shownByPress: false, conversationLive: true), .leave)
    }

    func testALaunchLineSplitsTheTimeBeforeThePress() {
        let timing = TalkLaunchTiming(processAge: 1.2, beforeAppInit: 0.6, appInit: 0.15)
        XCTAssertEqual(timing.isFreshLaunch, true)
        XCTAssertEqual(timing.line(), "process age 1.20 s (fresh launch) · before app init 0.60 s · app init 0.15 s")
    }

    func testARunningProcessSaysOnlyItsAge() {
        // The launch times belong to a start long before this press, so they are left out.
        let timing = TalkLaunchTiming(processAge: 600, beforeAppInit: 0.6, appInit: 0.15)
        XCTAssertEqual(timing.isFreshLaunch, false)
        XCTAssertEqual(timing.line(), "process age 600.00 s (already running)")
    }

    func testTheFreshLimitIsTheFirstRunningSecond() {
        XCTAssertEqual(TalkLaunchTiming(processAge: TalkLaunchTiming.freshBelow - 0.01, beforeAppInit: nil, appInit: nil).isFreshLaunch, true)
        XCTAssertEqual(TalkLaunchTiming(processAge: TalkLaunchTiming.freshBelow, beforeAppInit: nil, appInit: nil).isFreshLaunch, false)
    }

    func testAMissingOrBrokenAgeIsSaidNotGuessed() {
        XCTAssertEqual(TalkLaunchTiming(processAge: nil, beforeAppInit: 0.6, appInit: 0.15).line(), "process age unknown")
        XCTAssertEqual(TalkLaunchTiming(processAge: .nan, beforeAppInit: nil, appInit: nil).line(), "process age unknown")
        XCTAssertNil(TalkLaunchTiming(processAge: .infinity, beforeAppInit: nil, appInit: nil).isFreshLaunch)
    }

    func testAFreshLaunchWithPartsMissingKeepsWhatItHas() {
        XCTAssertEqual(TalkLaunchTiming(processAge: 2, beforeAppInit: nil, appInit: 0.2).line(),
                       "process age 2.00 s (fresh launch) · app init 0.20 s")
        XCTAssertEqual(TalkLaunchTiming(processAge: 2, beforeAppInit: nil, appInit: nil).line(), "process age 2.00 s (fresh launch)")
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
        XCTAssertEqual(TalkStartHandoff.decide(islandReady: false, startEnded: false, waited: TalkStartHandoff.maxWait - 0.01), .keepWaiting)
        XCTAssertEqual(TalkStartHandoff.decide(islandReady: false, startEnded: false, waited: TalkStartHandoff.maxWait), .timedOut)
        XCTAssertEqual(TalkStartHandoff.decide(islandReady: false, startEnded: false, waited: TalkStartHandoff.maxWait + 1), .timedOut)
    }

    func testReadinessOrAnActualFailureWinsAtTheDeadline() {
        XCTAssertEqual(TalkStartHandoff.decide(islandReady: true, startEnded: false, waited: TalkStartHandoff.maxWait), .handBack)
        XCTAssertEqual(TalkStartHandoff.decide(islandReady: false, startEnded: true, waited: TalkStartHandoff.maxWait), .report)
    }
}
