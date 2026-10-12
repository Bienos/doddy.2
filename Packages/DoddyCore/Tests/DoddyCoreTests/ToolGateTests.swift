import XCTest
@testable import DoddyCore

/// ADR-444: `ToolGate.decide` is the top of `VoiceSessionController.handle`, moved unchanged.
/// `legacy` below is that code as it was before the move (commit fafb46a), with `UserDefaults`
/// and `isOn` replaced by the same values. The equivalence test runs both over every tool name in
/// the spec, a spread of parsed requests and every combination of settings.
final class ToolGateTests: XCTestCase {
    // MARK: The code as it was in the controller

    private enum Legacy: Equatable {
        case reply(String, logged: Bool)
        case plan
        case notConnected(VoiceConnection)
        case proceed
    }

    private func legacy(_ name: String, _ request: VoiceToolRequest, translator: Bool, paused: Bool, on: Set<VoiceConnection>) -> Legacy {
        if translator, !TranslatorPolicy.allows(request) {
            return .reply(VoiceToolReply.translatorRefused(name), logged: false)
        }
        if name == VoiceToolName.proposePlan { return .plan }
        // asked[...] = ... (logged from here on)
        if paused, ConnectionPause.applies(to: request) { return .reply(ConnectionPause.reply, logged: true) }
        if let connection = VoiceConnection.serving(name), !on.contains(connection) { return .notConnected(connection) }
        return .proceed
    }

    private func asLegacy(_ decision: ToolGateDecision) -> Legacy {
        switch decision {
        case .refuse(let reply): .reply(reply, logged: decision.logsRequest)
        case .plan: .plan
        case .paused(let reply): .reply(reply, logged: decision.logsRequest)
        case .notConnected(let connection): .notConnected(connection)
        case .proceed: .proceed
        }
    }

    // MARK: Inputs

    private func specToolNames() throws -> [String] {
        let tools = try RealtimeToolCatalog.decode(Data(contentsOf: Fixtures.root.appendingPathComponent("voice-agent/tools.json")))
        return tools.map(\.name)
    }

    private func parse(_ name: String, _ json: String) -> VoiceToolRequest {
        VoiceToolRequest.parse(name: name, parametersJSON: Data(json.utf8))
    }

    /// Real parsed requests, so both sides of `ConnectionPause.applies` and the translator's one
    /// allowed tool are exercised.
    private var sampleRequests: [VoiceToolRequest] {
        [
            parse(VoiceToolName.searchMemories, #"{"query":"car"}"#),
            parse(VoiceToolName.readCalendar, #"{"range":"today"}"#),
            parse(VoiceToolName.calculate, #"{"expression":"2+2"}"#),
            parse(VoiceToolName.setTimer, #"{"seconds":60}"#),
            parse(VoiceToolName.stopTranslator, "{}"),
            parse(VoiceToolName.lookupContact, #"{"name":"Ana"}"#),
            parse(CloudToolName.checkEmail, "{}"),
            parse(VoiceToolName.searchMemories, "{}"),   // invalid
            parse("fly_a_drone", "{}"),                  // unsupported
        ]
    }

    private var environments: [ToolGateEnvironment] {
        let all = Set(VoiceConnection.allCases)
        var sets: [Set<VoiceConnection>] = [all, []]
        sets += VoiceConnection.allCases.map { all.subtracting([$0]) }
        var out: [ToolGateEnvironment] = []
        for translator in [false, true] {
            for paused in [false, true] {
                for on in sets { out.append(ToolGateEnvironment(translatorOn: translator, connectionsPaused: paused, connectionsOn: on)) }
            }
        }
        return out
    }

    // MARK: Equivalence

    func testTheGateDecidesExactlyAsTheControllerDid() throws {
        let names = try specToolNames() + ["fly_a_drone"]
        let requests = sampleRequests
        // Both sides of the pause rule are in the sample.
        XCTAssertTrue(requests.contains { ConnectionPause.applies(to: $0) })
        XCTAssertTrue(requests.contains { !ConnectionPause.applies(to: $0) })
        XCTAssertTrue(requests.contains { TranslatorPolicy.allows($0) })
        var checked = 0
        for name in names {
            for request in requests + [parse(name, "{}")] {
                for env in environments {
                    let expected = legacy(name, request, translator: env.translatorOn, paused: env.connectionsPaused, on: env.connectionsOn)
                    let actual = asLegacy(ToolGate.decide(toolName: name, request: request, environment: env))
                    XCTAssertEqual(actual, expected, "\(name) \(env)")
                    checked += 1
                }
            }
        }
        XCTAssertGreaterThan(checked, 10_000)
    }

    // MARK: The rules, one by one

    private let open = ToolGateEnvironment(translatorOn: false, connectionsPaused: false, connectionsOn: Set(VoiceConnection.allCases))

    func testTranslatorModeRefusesEveryToolButStopAndLogsNothing() throws {
        let env = ToolGateEnvironment(translatorOn: true, connectionsPaused: false, connectionsOn: Set(VoiceConnection.allCases))
        for name in try specToolNames() where name != VoiceToolName.stopTranslator {
            let decision = ToolGate.decide(toolName: name, request: parse(name, "{}"), environment: env)
            XCTAssertEqual(decision, .refuse(reply: VoiceToolReply.translatorRefused(name)), name)
            XCTAssertFalse(decision.logsRequest)
        }
        XCTAssertEqual(ToolGate.decide(toolName: VoiceToolName.stopTranslator, request: .stopTranslator, environment: env), .proceed)
    }

    func testAPlanTakesItsOwnPathEvenWhenPausedOrSwitchedOff() {
        let closed = ToolGateEnvironment(translatorOn: false, connectionsPaused: true, connectionsOn: [])
        let plan = parse(VoiceToolName.proposePlan, #"{"steps":"[]"}"#)
        XCTAssertEqual(ToolGate.decide(toolName: VoiceToolName.proposePlan, request: plan, environment: closed), .plan)
        XCTAssertFalse(ToolGateDecision.plan.logsRequest)
    }

    func testPauseAllStopsOtherAppsButNotNotes() {
        let paused = ToolGateEnvironment(translatorOn: false, connectionsPaused: true, connectionsOn: Set(VoiceConnection.allCases))
        XCTAssertEqual(ToolGate.decide(toolName: VoiceToolName.readCalendar, request: parse(VoiceToolName.readCalendar, #"{"range":"today"}"#), environment: paused),
                       .paused(reply: ConnectionPause.reply))
        XCTAssertEqual(ToolGate.decide(toolName: CloudToolName.checkEmail, request: parse(CloudToolName.checkEmail, "{}"), environment: paused),
                       .paused(reply: ConnectionPause.reply))
        XCTAssertEqual(ToolGate.decide(toolName: VoiceToolName.searchMemories, request: parse(VoiceToolName.searchMemories, #"{"query":"car"}"#), environment: paused),
                       .proceed)
        XCTAssertTrue(ToolGateDecision.paused(reply: "").logsRequest)
    }

    func testPauseIsCheckedBeforeTheConnectionSwitch() {
        let both = ToolGateEnvironment(translatorOn: false, connectionsPaused: true, connectionsOn: [])
        XCTAssertEqual(ToolGate.decide(toolName: VoiceToolName.readCalendar, request: parse(VoiceToolName.readCalendar, #"{"range":"today"}"#), environment: both),
                       .paused(reply: ConnectionPause.reply))
    }

    func testASwitchedOffConnectionAsksToTurnItOn() {
        let noCalendar = ToolGateEnvironment(translatorOn: false, connectionsPaused: false, connectionsOn: Set(VoiceConnection.allCases).subtracting([.calendar]))
        XCTAssertEqual(ToolGate.decide(toolName: VoiceToolName.createCalendarEvent, request: parse(VoiceToolName.createCalendarEvent, "{}"), environment: noCalendar),
                       .notConnected(.calendar))
        // An invalid call to a switched-off tool still gets the switch prompt first, as before.
        XCTAssertEqual(ToolGate.decide(toolName: VoiceToolName.readCalendar, request: parse(VoiceToolName.readCalendar, "{}"), environment: noCalendar),
                       .notConnected(.calendar))
    }

    func testNotesAndListsNeedNoSwitch() {
        let closed = ToolGateEnvironment(translatorOn: false, connectionsPaused: false, connectionsOn: [])
        for name in [VoiceToolName.searchMemories, VoiceToolName.saveMemory, VoiceToolName.addToList, VoiceToolName.calculate] {
            XCTAssertEqual(ToolGate.decide(toolName: name, request: parse(name, "{}"), environment: closed), .proceed, name)
        }
    }

    func testWithEverythingOnEveryPhoneToolReachesItsHandler() throws {
        let tools = try RealtimeToolCatalog.decode(Data(contentsOf: Fixtures.root.appendingPathComponent("voice-agent/tools.json")))
        for tool in tools where tool.runsOn == .phone {
            let decision = ToolGate.decide(toolName: tool.name, request: parse(tool.name, "{}"), environment: open)
            XCTAssertTrue(decision == .proceed || decision == .plan, "\(tool.name): \(decision)")
        }
    }
}
