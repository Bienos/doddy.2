import XCTest
@testable import DoddyCore

final class VoiceNetworkPreparationTests: XCTestCase {
    private var allowed: VoicePreparationConditions {
        VoicePreparationConditions(foreground: true, hasVoiceAccess: true, hasSignedInOwner: true, consentGranted: true,
                                   microphoneAllowed: true, paused: false, conversationRunning: false, configured: true)
    }

    func testEveryPermissionAndReadinessGateBlocksPreparationWithoutSpendingItsBudget() {
        let blockers: [(WritableKeyPath<VoicePreparationConditions, Bool>, Bool)] = [
            (\.foreground, false), (\.hasVoiceAccess, false), (\.hasSignedInOwner, false), (\.consentGranted, false),
            (\.microphoneAllowed, false), (\.paused, true), (\.conversationRunning, true), (\.configured, false),
        ]
        for (key, value) in blockers {
            var policy = VoiceNetworkPreparationPolicy()
            var denied = allowed
            denied[keyPath: key] = value
            XCTAssertFalse(denied.mayPrepare)
            XCTAssertFalse(policy.request(if: denied, at: 100))
            XCTAssertTrue(policy.request(if: allowed, at: 100), "a denied trigger spends no preparation budget")
        }
    }

    func testRapidForegroundAndSettingsChangesCannotRequestMorePreparations() {
        var policy = VoiceNetworkPreparationPolicy()
        XCTAssertTrue(policy.request(if: allowed, at: 100))
        for offset in [0.0, 1, 30, 60, VoiceNetworkPreparationPolicy.minimumInterval - 0.01] {
            XCTAssertFalse(policy.request(if: allowed, at: 100 + offset))
        }
        XCTAssertTrue(policy.request(if: allowed, at: 100 + VoiceNetworkPreparationPolicy.minimumInterval))
    }

    func testBrokenOrBackwardsClockCannotCauseABurst() {
        var policy = VoiceNetworkPreparationPolicy()
        for time: Double in [.nan, .infinity, -.infinity, -1] {
            XCTAssertFalse(policy.request(if: allowed, at: time))
        }
        XCTAssertTrue(policy.request(if: allowed, at: 100))
        XCTAssertFalse(policy.request(if: allowed, at: 90))
        XCTAssertFalse(policy.request(if: allowed, at: .nan))
        XCTAssertFalse(policy.request(if: allowed, at: 101))
    }

    func testNetworkCanBePreparedAgainWhileATokenIsStillHeld() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let endpoint = URL(string: "https://voice.example.com/api/voice-token")!
        var shelf = VoiceTokenShelf()
        shelf.warmStarted(now: now)
        shelf.store("unit-test-token", endpoint: endpoint, owner: "one", fetchedAt: now)
        let later = now.addingTimeInterval(VoiceNetworkPreparationPolicy.minimumInterval)
        XCTAssertFalse(shelf.shouldWarm(endpoint: endpoint, owner: "one", now: later))
        var network = VoiceNetworkPreparationPolicy()
        XCTAssertTrue(network.request(if: allowed, at: 0))
        XCTAssertTrue(network.request(if: allowed, at: VoiceNetworkPreparationPolicy.minimumInterval))
        XCTAssertEqual(shelf.take(endpoint: endpoint, owner: "one", now: later), "unit-test-token",
                       "network preparation does not spend the conversation token")
    }

    func testTransportMetricsContainOnlyKnownStageNamesAndDurations() {
        let timing = VoiceTransportTiming(room: 0.81, agent: 1.24, initialization: 0.02, total: 2.07)
        XCTAssertEqual(timing.line, "room/microphone 0.81 s · agent 1.24 s · init 0.02 s · total 2.07 s")
    }

    func testMissingOrInvalidMetricsAreUnavailableRatherThanClaimedAsZero() {
        let missing = VoiceTransportTiming(room: nil, agent: .nan, initialization: -1, total: .infinity)
        XCTAssertEqual(missing.line, "room/microphone unavailable · agent unavailable · init unavailable · total unavailable")
        XCTAssertTrue(VoiceTransportTiming(room: 0, agent: nil, initialization: nil, total: nil).line.hasPrefix("room/microphone 0.00 s"))
    }
}
