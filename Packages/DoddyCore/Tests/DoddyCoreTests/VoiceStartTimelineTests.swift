import XCTest
@testable import DoddyCore

final class VoiceStartTimelineTests: XCTestCase {
    func testEachStageTakesTheTimeSinceTheLastMark() {
        var timeline = VoiceStartTimeline(startedAt: 100)
        timeline.mark(.account, at: 100.31)
        timeline.mark(.profile, at: 100.33)
        timeline.mark(.connect, at: 102.73)
        XCTAssertEqual(timeline.entries.map(\.stage), [.account, .profile, .connect])
        XCTAssertEqual(timeline.entries[0].seconds, 0.31, accuracy: 0.0001)
        XCTAssertEqual(timeline.entries[1].seconds, 0.02, accuracy: 0.0001)
        XCTAssertEqual(timeline.entries[2].seconds, 2.40, accuracy: 0.0001)
        XCTAssertEqual(timeline.total(at: 102.73), 2.73, accuracy: 0.0001)
    }

    func testTheLineHasOnlyFixedWordsAndSeconds() {
        var timeline = VoiceStartTimeline(startedAt: 0)
        timeline.mark(.account, at: 0.31)
        timeline.mark(.connect, at: 2.71)
        XCTAssertEqual(timeline.line(at: 2.73), "account 0.31 s · connect 2.40 s · total 2.73 s")
    }

    func testAStartThatStopsEarlyStillReadsWell() {
        var timeline = VoiceStartTimeline(startedAt: 5)
        timeline.mark(.account, at: 5.5)
        XCTAssertEqual(timeline.line(at: 5.5), "account 0.50 s · total 0.50 s")
        XCTAssertEqual(VoiceStartTimeline(startedAt: 5).line(at: 5), "total 0.00 s")
    }

    func testABackwardsOrBrokenClockNeverGivesANegativeOrNaN() {
        var timeline = VoiceStartTimeline(startedAt: 10)
        timeline.mark(.account, at: 9)
        timeline.mark(.profile, at: .nan)
        XCTAssertEqual(timeline.entries.map(\.seconds), [0, 0])
        XCTAssertEqual(timeline.total(at: 8), 0)
        XCTAssertEqual(VoiceStartTimeline.text(-3), "0.00 s")
        XCTAssertEqual(VoiceStartTimeline.text(.infinity), "0.00 s")
    }

    func testTheStageWordsAreFixed() {
        XCTAssertEqual(VoiceStartStage.allCases.map(\.rawValue), ["account", "profile", "island", "connect"])
    }

    func testTheLineSaysWhereTheTokenCameFromInFixedWords() {
        var timeline = VoiceStartTimeline(startedAt: 0)
        timeline.mark(.connect, at: 1)
        XCTAssertEqual(timeline.line(at: 1, token: .shelf), "connect 1.00 s · total 1.00 s · token shelf")
        XCTAssertEqual(timeline.line(at: 1, token: .fetched), "connect 1.00 s · total 1.00 s · token fetched")
        XCTAssertEqual(timeline.line(at: 1, token: .warming), "connect 1.00 s · total 1.00 s · token warming")
        XCTAssertEqual(timeline.line(at: 1), "connect 1.00 s · total 1.00 s")
    }
}
