import XCTest
@testable import DoddyCore

final class RealtimeVoiceTests: XCTestCase {
    private let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    func testRendersEveryPlaceholderAndRefusesHoles() throws {
        let template = "Notes ({{count}}):\n{{ notes }}\nAgain {{count}}"
        XCTAssertEqual(RealtimeInstructions.placeholders(in: template), ["count", "notes"])
        let out = try RealtimeInstructions.render(template, variables: ["count": "2", "notes": "- keys {{count}}"])
        XCTAssertEqual(out, "Notes (2):\n- keys {{count}}\nAgain 2")
        XCTAssertThrowsError(try RealtimeInstructions.render(template, variables: ["count": "2"])) { error in
            XCTAssertEqual(error as? RealtimeInstructions.RenderError, .missingVariables(["notes"]))
        }
    }

    func testRepoInstructionsRenderWithTheDeclaredVariables() throws {
        let template = try String(contentsOf: repoRoot.appendingPathComponent("voice-agent/instructions.md"), encoding: .utf8)
        let session = try JSONSerialization.jsonObject(with: Data(contentsOf: repoRoot.appendingPathComponent("voice-agent/session.json"))) as? [String: Any]
        let declared = Set((session?["variables"] as? [String: String] ?? [:]).keys)
        XCTAssertEqual(Set(RealtimeInstructions.placeholders(in: template)), declared)
        let rendered = try RealtimeInstructions.render(template, variables: Dictionary(uniqueKeysWithValues: declared.map { ($0, "x") }))
        XCTAssertFalse(rendered.contains("{{"))
    }

    func testRepoToolCatalogDecodes() throws {
        let tools = try RealtimeToolCatalog.decode(Data(contentsOf: repoRoot.appendingPathComponent("voice-agent/tools.json")))
        // Every phone tool in the spec is one the app can route; an unrouted one would leave the
        // agent waiting until its timeout.
        let routable = Set(tools.filter { $0.runsOn == .phone }.map(\.name).filter { name in
            // The plan card is routed before VoiceToolRequest (PlanProposal, ADR-204).
            if name == VoiceToolName.proposePlan { return true }
            if case .unsupported = VoiceToolRequest.parse(name: name, parametersJSON: Data("{}".utf8)) { return false }
            return true
        })
        XCTAssertEqual(RealtimeToolCatalog.unhandledPhoneTools(tools, handled: routable), [])
        // The online-account tools exist in the spec, run on the phone, and only the writes ask for a
        // tap; the reads ask too, for a spoken yes or a tap (ASK-01).
        let cloud = tools.filter { CloudToolName.all.contains($0.name) }
        XCTAssertEqual(Set(cloud.map(\.name)), CloudToolName.all)
        XCTAssertTrue(cloud.allSatisfy { $0.runsOn == .phone })
        XCTAssertEqual(Set(cloud.filter(\.confirmOnScreen).map(\.name)), CloudToolName.writes)
        XCTAssertEqual(Set(cloud.filter { $0.ask == .yesOrTap }.map(\.name)),
                       CloudToolName.all.subtracting(CloudToolName.writes).subtracting(AskFirst.publicLookups))
        // Web search, news and places run at once (ADR-574).
        XCTAssertEqual(Set(cloud.filter { $0.ask == .runsNow }.map(\.name)), ["web_search", "news_search", "find_places"])
        let save = try XCTUnwrap(tools.first { $0.name == VoiceToolName.saveMemory })
        XCTAssertEqual(save.runsOn, .phone)
        XCTAssertTrue(save.confirmOnScreen)
        XCTAssertEqual(save.requiredParameters, ["text"])
        // ASK-01: every tool that asks runs on the phone. The web tools are ADR-574's public
        // lookups (weather, Wikipedia), which run at once on ElevenLabs.
        XCTAssertEqual(tools.first { $0.name == "get_weather" }?.runsOn, .web)
        XCTAssertTrue(tools.allSatisfy { ($0.runsOn == .phone || $0.ask == .runsNow) && $0.ask != nil })
        // The memory tools this module parses are in the catalog under the same names.
        let unhandled = RealtimeToolCatalog.unhandledPhoneTools(tools, handled: [VoiceToolName.searchMemories, VoiceToolName.saveMemory])
        XCTAssertFalse(unhandled.contains(VoiceToolName.searchMemories))
        XCTAssertFalse(unhandled.contains(VoiceToolName.saveMemory))
    }

    func testEventsDriveTheSamePhasesForAnyProvider() {
        var state = RealtimeConversationState()
        XCTAssertEqual(state.phase, .connecting)
        state.apply(.sessionReady)
        XCTAssertEqual(state.phase, .listening)
        state.apply(.userSpeechStarted)
        state.apply(.userSpeechStopped)
        XCTAssertEqual(state.phase, .thinking)
        state.apply(.userTranscript("Where are my keys?"))
        state.apply(.functionCall(RealtimeFunctionCall(callID: "c1", name: "search_memories", arguments: #"{"query":"klucze keys"}"#)))
        state.apply(.functionCall(RealtimeFunctionCall(callID: "c1", name: "search_memories", arguments: "{}")))
        XCTAssertEqual(state.openCalls.map(\.callID), ["c1"])
        state.answered("c1")
        XCTAssertTrue(state.openCalls.isEmpty)
        state.apply(.audioStarted)
        XCTAssertEqual(state.phase, .speaking)
        state.apply(.assistantTranscript("In the blue tin above the fridge, I think the whole"))
        state.apply(.assistantTranscriptCorrected(original: "In the blue tin above the fridge, I think the whole", corrected: "In the blue tin above the fridge."))
        state.apply(.responseDone)
        XCTAssertEqual(state.phase, .listening)
        XCTAssertEqual(state.lines.map(\.text), ["Where are my keys?", "In the blue tin above the fridge."])
        state.apply(.ended)
        state.apply(.sessionReady)
        XCTAssertEqual(state.phase, .ended)
        XCTAssertFalse(state.isLive)
    }

    func testErrorsDropOpenCalls() {
        var state = RealtimeConversationState()
        state.apply(.functionCall(RealtimeFunctionCall(callID: "c2", name: "save_memory", arguments: "{}")))
        state.apply(.error("Lost connection"))
        XCTAssertEqual(state.phase, .failed("Lost connection"))
        XCTAssertTrue(state.openCalls.isEmpty)
    }

    func testTurnEagernessMapsToElevenLabs() {
        XCTAssertEqual(RealtimeTurnEagerness.high.elevenLabsValue, "eager")
        XCTAssertEqual(RealtimeTurnEagerness.low.elevenLabsValue, "patient")
        XCTAssertEqual(RealtimeTurnEagerness.auto.elevenLabsValue, "normal")
    }
}
