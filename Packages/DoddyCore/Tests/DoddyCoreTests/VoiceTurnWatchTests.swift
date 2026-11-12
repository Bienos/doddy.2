import XCTest
@testable import DoddyCore

final class VoiceTurnWatchTests: XCTestCase {
    func testAPlainTurnIsTimedFromTheWordsToDoddySpeaking() {
        var watch = VoiceTurnWatch()
        watch.userFinished(at: 10)
        let timing = watch.agentStartedSpeaking(at: 12.31)
        XCTAssertEqual(timing?.secondsToSpeech ?? -1, 2.31, accuracy: 0.0001)
        XCTAssertEqual(timing?.tools, [])
        XCTAssertEqual(timing?.line, "turn 2.31 s to Doddy speaking")
    }

    func testOnlyTheFirstSpeechAfterTheWordsEndsTheTurn() {
        var watch = VoiceTurnWatch()
        XCTAssertNil(watch.agentStartedSpeaking(at: 1), "the opening line is no turn")
        watch.userFinished(at: 2)
        XCTAssertNotNil(watch.agentStartedSpeaking(at: 3))
        XCTAssertNil(watch.agentStartedSpeaking(at: 4), "a second sentence is the same turn")
    }

    func testToolsAreTimedAndOneStillRunningIsSaidSo() {
        var watch = VoiceTurnWatch()
        watch.userFinished(at: 0)
        watch.toolStarted(id: "a", name: "search_memories", at: 0.5)
        watch.toolAnswered(id: "a", at: 1.0)
        watch.toolStarted(id: "b", name: "web_search", at: 1.2)
        let timing = watch.agentStartedSpeaking(at: 1.5)
        XCTAssertEqual(timing?.line, "turn 1.50 s to Doddy speaking · search_memories 0.50 s · web_search running")
    }

    func testTheSameCallReportedTwiceCountsOnce() {
        var watch = VoiceTurnWatch()
        watch.userFinished(at: 0)
        watch.toolStarted(id: "a", name: "web_search", at: 0.1)
        watch.toolStarted(id: "a", name: "web_search", at: 0.3)
        watch.toolAnswered(id: "a", at: 2.1)
        watch.toolAnswered(id: "a", at: 2.5)
        XCTAssertEqual(watch.agentStartedSpeaking(at: 3)?.tools, [VoiceTurnTiming.Tool(name: "web_search", seconds: 2.0)])
    }

    func testTheLineNeverCarriesAnythingButAPlainToolName() {
        let timing = VoiceTurnTiming(secondsToSpeech: 1, tools: [
            VoiceTurnTiming.Tool(name: "Kod do paczkomatu 1234", seconds: 1),
            VoiceTurnTiming.Tool(name: "", seconds: nil),
            VoiceTurnTiming.Tool(name: String(repeating: "a", count: 41), seconds: 0.5),
        ])
        XCTAssertEqual(timing.line, "turn 1.00 s to Doddy speaking · tool 1.00 s · tool running · tool 0.50 s")
    }

    func testTheLabelNamesTheRunningToolAndSaysStillAfterFourSeconds() {
        var watch = VoiceTurnWatch()
        XCTAssertNil(watch.label(at: 0), "nothing waited on")
        watch.userFinished(at: 0)
        XCTAssertEqual(watch.label(at: 1), VoiceWaitLabel(activity: nil, still: false))
        watch.toolStarted(id: "a", name: "web_search", at: 2)
        XCTAssertEqual(watch.label(at: 3), VoiceWaitLabel(activity: .searchingWeb, still: false))
        XCTAssertEqual(watch.label(at: 6), VoiceWaitLabel(activity: .searchingWeb, still: true))
        XCTAssertEqual(watch.stillFrom() ?? -1, 6, accuracy: 0.0001)
        watch.toolAnswered(id: "a", at: 7)
        XCTAssertEqual(watch.label(at: 7.5), VoiceWaitLabel(activity: nil, still: false), "a new wait: the answer")
        XCTAssertEqual(watch.stillFrom() ?? -1, 11, accuracy: 0.0001)
    }

    func testAToolWithoutAnActivityGetsThePlainLabel() {
        var watch = VoiceTurnWatch()
        watch.userFinished(at: 0)
        watch.toolStarted(id: "a", name: "set_timer", at: 0.1)
        XCTAssertEqual(watch.label(at: 0.2), VoiceWaitLabel(activity: nil, still: false))
    }

    func testThinkingIsHeldAfterAToolAnswersUntilDoddySpeaksOrTheHoldRunsOut() {
        var watch = VoiceTurnWatch()
        watch.userFinished(at: 0)
        watch.toolStarted(id: "a", name: "web_search", at: 1)
        XCTAssertFalse(watch.holdsThinking(at: 2), "the tool is still running: no hold needed")
        watch.toolAnswered(id: "a", at: 5)
        XCTAssertTrue(watch.holdsThinking(at: 5.1))
        XCTAssertEqual(watch.holdEnds() ?? -1, 11, accuracy: 0.0001)
        XCTAssertFalse(watch.holdsThinking(at: 11), "a hold ends on its own")
        _ = watch.agentStartedSpeaking(at: 6)
        XCTAssertFalse(watch.holdsThinking(at: 6.1), "Doddy spoke")
    }

    func testNewWordsAndResetDropTheHold() {
        var watch = VoiceTurnWatch()
        watch.toolStarted(id: "a", name: "web_search", at: 0)
        watch.toolAnswered(id: "a", at: 1)
        XCTAssertTrue(watch.holdsThinking(at: 1.5))
        watch.userFinished(at: 2)
        XCTAssertFalse(watch.holdsThinking(at: 2.1))
        watch.toolStarted(id: "b", name: "web_search", at: 3)
        watch.toolAnswered(id: "b", at: 4)
        watch.reset()
        XCTAssertFalse(watch.holdsThinking(at: 4.1))
        XCTAssertNil(watch.label(at: 4.1))
    }

    func testEveryActivityHasATool() {
        let names = ["web_search", "news_search", "look_at_screen", "search_memories", "ask_claude", "check_email",
                     "find_places", "make_document", "get_weather", "wikipedia_search", "read_calendar"]
        XCTAssertEqual(Set(names.compactMap(VoiceWaitActivity.forTool)), Set(VoiceWaitActivity.allCases))
    }
}
