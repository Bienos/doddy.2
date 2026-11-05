@testable import DoddyCore
import XCTest

/// ADR-579: one "Talk to Doddy" control whose press follows Settings › Action Button.
final class TalkLaunchTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 10_000)

    func testDynamicIslandIsTheDefaultAndUnknownValuesFallBackToIt() {
        XCTAssertEqual(TalkLaunchMode.stored(nil), .dynamicIsland)
        XCTAssertEqual(TalkLaunchMode.stored("somethingNewer"), .dynamicIsland)
        XCTAssertEqual(TalkLaunchMode.stored("openApp"), .openApp)
        XCTAssertEqual(TalkLaunchMode.stored("automatic"), .automatic)
    }

    func testAFirstPressFollowsTheChoice() {
        XCTAssertEqual(TalkLaunchPlanner.step(mode: .dynamicIsland, conversation: .none, appOnScreen: false, now: now), .startInIsland)
        XCTAssertEqual(TalkLaunchPlanner.step(mode: .automatic, conversation: .none, appOnScreen: false, now: now), .startInIsland)
        XCTAssertEqual(TalkLaunchPlanner.step(mode: .openApp, conversation: .none, appOnScreen: false, now: now), .openApp)
    }

    func testWithDoddyOnScreenTheConversationOpensThereWhateverTheChoice() {
        for mode in TalkLaunchMode.allCases {
            XCTAssertEqual(TalkLaunchPlanner.step(mode: mode, conversation: .none, appOnScreen: true, now: now), .showInApp, "\(mode)")
        }
    }

    func testRapidPressesNeverStartASecondConversation() {
        for mode in TalkLaunchMode.allCases {
            XCTAssertEqual(TalkLaunchPlanner.step(mode: mode, conversation: .starting, appOnScreen: false, now: now), .ignore)
            let justStarted = TalkPressState.running(since: now.addingTimeInterval(-1))
            XCTAssertEqual(TalkLaunchPlanner.step(mode: mode, conversation: justStarted, appOnScreen: false, now: now), .ignore,
                           "a bounce within the window is not \"stop\"")
        }
    }

    func testPressingAgainEndsTheConversation() {
        let running = TalkPressState.running(since: now.addingTimeInterval(-TalkLaunchPlanner.repeatPressWindow))
        for mode in TalkLaunchMode.allCases {
            for onScreen in [false, true] {
                XCTAssertEqual(TalkLaunchPlanner.step(mode: mode, conversation: running, appOnScreen: onScreen, now: now), .endRunning)
            }
        }
    }

    func testAProblemOnlyTheAppCanFixAsksOrOpensByChoice() {
        let problem = TalkStartProblem.needsApp("Allow the microphone")
        XCTAssertEqual(TalkLaunchPlanner.fallback(mode: .dynamicIsland, problem: problem, canOpenApp: true), .askToOpenApp("Allow the microphone"))
        XCTAssertEqual(TalkLaunchPlanner.fallback(mode: .automatic, problem: problem, canOpenApp: true), .openApp)
    }

    func testAFailedConversationIsToldAndNothingOpens() {
        let problem = TalkStartProblem.failed("You're offline.")
        for mode in TalkLaunchMode.allCases {
            XCTAssertEqual(TalkLaunchPlanner.fallback(mode: mode, problem: problem, canOpenApp: true), .tell("You're offline."))
        }
    }

    func testWhenIOSCantBringDoddyForwardTheReasonIsSaid() {
        let problem = TalkStartProblem.needsApp("Open Doddy to unlock him.")
        XCTAssertEqual(TalkLaunchPlanner.fallback(mode: .automatic, problem: problem, canOpenApp: false), .tell("Open Doddy to unlock him."))
    }

    // MARK: Migration of "Small island"

    func testSmallIslandBecomesTheIslandSwitchAndBackTapKeepsTalking() {
        let moved = LaunchPreferencesMigration.migrate(.init(backTapAction: "smallIsland", islandExpands: nil))
        XCTAssertEqual(moved, .init(backTapAction: "conversation", islandExpands: false))
        XCTAssertFalse(IslandExpansion(isOn: LaunchPreferencesMigration.islandExpands(moved.islandExpands)).isOn)
    }

    func testOtherChoicesAreLeftExactlyAsTheyWere() {
        for raw in [nil, "conversation", "openApp", "unknown"] {
            let values = LaunchPreferencesMigration.Values(backTapAction: raw, islandExpands: nil)
            XCTAssertEqual(LaunchPreferencesMigration.migrate(values), values)
        }
        let set = LaunchPreferencesMigration.Values(backTapAction: "openApp", islandExpands: false)
        XCTAssertEqual(LaunchPreferencesMigration.migrate(set), set)
    }

    func testRunningItTwiceChangesNothingMore() {
        let once = LaunchPreferencesMigration.migrate(.init(backTapAction: "smallIsland", islandExpands: nil))
        XCTAssertEqual(LaunchPreferencesMigration.migrate(once), once)
    }

    func testTheIslandOpensUpByDefault() {
        XCTAssertTrue(LaunchPreferencesMigration.islandExpands(nil))
        XCTAssertFalse(LaunchPreferencesMigration.islandExpands(false))
    }
}
