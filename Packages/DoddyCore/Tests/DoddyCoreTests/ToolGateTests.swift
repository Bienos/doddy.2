import Foundation
import XCTest
@testable import DoddyCore

/// The checks before a voice tool call runs, and the stale-conversation rule (ADR-458).
final class ToolGateTests: XCTestCase {
    private func request(_ name: String, _ json: String = "{}") -> VoiceToolRequest {
        VoiceToolRequest.parse(name: name, parametersJSON: Data(json.utf8))
    }

    private func decide(
        _ name: String, _ json: String = "{}", translator: Bool = false, pauseAll: Bool = false,
        on: Set<VoiceConnection> = Set(VoiceConnection.allCases)
    ) -> ToolGate.Decision {
        ToolGate.decide(toolName: name, request: request(name, json), translatorOn: translator, pauseAll: pauseAll,
                        isOn: { on.contains($0) })
    }

    // MARK: Gate order (VoiceSessionController.handle, before the switch)

    func testGateTable() {
        let timer = #"{"seconds": 300}"#
        let rows: [(String, String, Bool, Bool, Set<VoiceConnection>, ToolGate.Decision, String)] = [
            // name, args, translator, pause all, connections on, expected, why
            (VoiceToolName.searchMemories, #"{"query":"keys"}"#, false, false, [], .run, "notes need no connection"),
            (VoiceToolName.searchMemories, #"{"query":"keys"}"#, true, false, [], .translatorRefused, "translating runs no tool"),
            (VoiceToolName.stopTranslator, "{}", true, true, [], .run, "stop_translator is the one tool while translating"),
            (VoiceToolName.proposePlan, "{}", true, false, [], .translatorRefused, "translator before plan"),
            (VoiceToolName.proposePlan, "{}", false, true, [], .plan, "plan before Pause all: steps are checked one by one"),
            (VoiceToolName.setTimer, timer, false, true, [], .paused, "Pause all before the connection switch"),
            (VoiceToolName.setTimer, timer, false, false, [], .notConnected(.timers), "switch off"),
            (VoiceToolName.setTimer, timer, false, false, [.timers], .run, "switch on"),
            (VoiceToolName.setTimer, timer, true, true, [], .translatorRefused, "translator before everything"),
            (VoiceToolName.saveMemory, #"{"text":"Car is on level 3"}"#, false, true, [], .run, "Pause all leaves notes alone"),
            (VoiceToolName.lookupContact, #"{"name":"Ana"}"#, false, false, [.calendar], .notConnected(.contacts), "the tool's own connection"),
            (CloudToolName.draftEmail, Self.draft, false, true, [], .paused, "online accounts are paused too"),
            (CloudToolName.draftEmail, Self.draft, false, false, [], .run, "online accounts have no phone switch; the server checks"),
        ]
        for (name, json, translator, pauseAll, on, expected, why) in rows {
            XCTAssertEqual(decide(name, json, translator: translator, pauseAll: pauseAll, on: on), expected, "\(name): \(why)")
        }
    }

    func testOrderHoldsWhenEveryCheckWouldStopTheCall() {
        // A request that Pause all covers, under names that a switch also covers: the earlier
        // check wins each time. Swapping any two checks in decide fails one of these.
        let paused = VoiceToolRequest.deleteReminder(title: "x")
        func decide(_ name: String, translator: Bool) -> ToolGate.Decision {
            ToolGate.decide(toolName: name, request: paused, translatorOn: translator, pauseAll: true, isOn: { _ in false })
        }
        XCTAssertEqual(decide(VoiceToolName.proposePlan, translator: true), .translatorRefused)
        XCTAssertEqual(decide(VoiceToolName.proposePlan, translator: false), .plan)
        XCTAssertEqual(decide(VoiceToolName.deleteReminder, translator: false), .paused)
    }

    func testEveryServedToolIsBlockedOnlyByItsOwnSwitch() {
        // Each connection's tools: off → notConnected(that connection); every other switch on.
        for connection in VoiceConnection.allCases {
            let others = Set(VoiceConnection.allCases).subtracting([connection])
            for name in Self.allToolNames where VoiceConnection.serving(name) == connection {
                let decision = ToolGate.decide(toolName: name, request: .unsupported(name: name), translatorOn: false,
                                               pauseAll: false, isOn: { others.contains($0) })
                XCTAssertEqual(decision, .notConnected(connection), name)
            }
        }
    }

    func testPauseAllMatchesConnectionPause() {
        // The gate adds nothing to ConnectionPause.applies: same answer for every parsed request.
        let samples: [VoiceToolRequest] = [
            .searchMemories(query: "x"), .stopTranslator, .calculate(expression: "2+2"), .undoLast,
            .deleteReminder(title: "x"), .upcomingBirthdays(days: 7),
        ]
        for sample in samples {
            let decision = ToolGate.decide(toolName: "any_tool", request: sample, translatorOn: false, pauseAll: true, isOn: { _ in true })
            XCTAssertEqual(decision == .paused, ConnectionPause.applies(to: sample), "\(sample)")
        }
    }

    // MARK: Stale conversations (ADR-458)

    func testCallFromTheCurrentStartIsAnsweredOnce() {
        var owners = ToolCallOwners()
        owners.record("call-1", attempt: 3)
        XCTAssertTrue(owners.isCurrent("call-1", attempt: 3))
        XCTAssertTrue(owners.finish("call-1", attempt: 3))
        // Answered: a second answer for the same call is not sent.
        XCTAssertFalse(owners.isCurrent("call-1", attempt: 3))
        XCTAssertFalse(owners.finish("call-1", attempt: 3))
        XCTAssertEqual(owners.count, 0)
    }

    func testEndAndNewStartMakeAnOlderCallStale() {
        // Conversation A is start 1; End makes it 2; Start B makes it 3. A's Gmail draft finishes
        // preparing after that: no card and no result in B.
        var owners = ToolCallOwners()
        owners.record("a-draft", attempt: 1)
        XCTAssertFalse(owners.isCurrent("a-draft", attempt: 2), "after End")
        XCTAssertFalse(owners.isCurrent("a-draft", attempt: 3), "after End and a new Start")
        owners.record("b-search", attempt: 3)
        XCTAssertFalse(owners.finish("a-draft", attempt: 3))
        XCTAssertTrue(owners.finish("b-search", attempt: 3))
    }

    func testUnknownCallIsStale() {
        // Fails closed: a path that never recorded its call can't reach the conversation.
        XCTAssertFalse(ToolCallOwners().isCurrent("never-seen", attempt: 0))
        var owners = ToolCallOwners()
        XCTAssertFalse(owners.finish("never-seen", attempt: 0))
    }

    func testForgetDropsTheCall() {
        var owners = ToolCallOwners()
        owners.record("call-1", attempt: 5)
        owners.forget("call-1")
        XCTAssertFalse(owners.isCurrent("call-1", attempt: 5))
    }

    func testNewStartForgetsOlderCallsOnly() {
        var owners = ToolCallOwners()
        owners.record("old", attempt: 1)
        owners.record("also-old", attempt: 2)
        owners.record("now", attempt: 3)
        owners.forget(before: 3)
        XCTAssertEqual(owners.count, 1)
        XCTAssertTrue(owners.isCurrent("now", attempt: 3))
        XCTAssertFalse(owners.isCurrent("old", attempt: 1), "forgotten, and stale either way")
    }

    // MARK: Helpers

    private static let draft = #"{"to":"ana@example.com","subject":"Hi","body":"Hello"}"#

    /// Every client tool the app handles, from VoiceToolName (by reflection would hide a typo).
    private static let allToolNames = [
        VoiceToolName.searchMemories, VoiceToolName.saveMemory, VoiceToolName.readCalendar, VoiceToolName.createCalendarEvent,
        VoiceToolName.createReminder, VoiceToolName.remindAboutNote, VoiceToolName.lookupContact, VoiceToolName.setTimer,
        VoiceToolName.openMap, VoiceToolName.runShortcut, VoiceToolName.draftMessage, VoiceToolName.findFreeTime,
        VoiceToolName.changeCalendarEvent, VoiceToolName.changeReminder, VoiceToolName.deleteCalendarEvent,
        VoiceToolName.deleteReminder, VoiceToolName.deleteCalendarEvents, VoiceToolName.moveReminders,
        VoiceToolName.upcomingBirthdays, VoiceToolName.setAlarm, VoiceToolName.listAlarms, VoiceToolName.cancelAlarm,
        VoiceToolName.remindWhenToLeave, VoiceToolName.draftBlikTransfer, VoiceToolName.makePresentation,
        VoiceToolName.readSteps, VoiceToolName.findPhotos, VoiceToolName.openCamera,
    ]
}
