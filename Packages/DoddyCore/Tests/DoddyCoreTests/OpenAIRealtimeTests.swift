import XCTest
@testable import DoddyCore

/// OpenAI Realtime as a test voice provider (ADR-265). Wire shapes follow the GA Realtime API.
final class OpenAIRealtimeTests: XCTestCase {
    private let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    private func object(_ text: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    // MARK: Provider choice

    func testStoredProviderStillReadsAsBefore() {
        // A conversation log's provider: unknown or missing stays ElevenLabs (logs from before ADR-265).
        XCTAssertEqual(VoiceProvider(stored: nil), .elevenLabs)
        XCTAssertEqual(VoiceProvider(stored: "something else"), .elevenLabs)
        XCTAssertEqual(VoiceProvider(stored: "openai"), .openAIRealtime)
        XCTAssertEqual(VoiceProvider(stored: "elevenlabs"), .elevenLabs)
    }

    func testOpenAIIsTheDefaultVoiceOnlyWhereItCanStart() {
        // No choice yet: OpenAI where the token server is set, ElevenLabs where it can't start otherwise.
        XCTAssertEqual(VoiceProvider.effective(stored: nil, tokenServerSet: true), .openAIRealtime)
        XCTAssertEqual(VoiceProvider.effective(stored: nil, tokenServerSet: false), .elevenLabs)
        XCTAssertEqual(VoiceProvider.effective(stored: "", tokenServerSet: true), .openAIRealtime)
        XCTAssertEqual(VoiceProvider.effective(stored: "something else", tokenServerSet: true), .openAIRealtime)
        // A choice the user made always wins.
        XCTAssertEqual(VoiceProvider.effective(stored: "elevenlabs", tokenServerSet: true), .elevenLabs)
        XCTAssertEqual(VoiceProvider.effective(stored: "openai", tokenServerSet: false), .openAIRealtime)
    }

    func testRealtimeModelsAreTheTwoTheServerAllows() {
        XCTAssertEqual(OpenAIRealtimeModel.allCases.map(\.rawValue), ["gpt-realtime-2.1", "gpt-realtime-2.1-mini"])
        XCTAssertEqual(OpenAIRealtimeModel.default, .mini)
        XCTAssertEqual(OpenAIRealtimeModel(stored: nil), .mini)
        XCTAssertEqual(OpenAIRealtimeModel(stored: "gpt-4o"), .mini)
        XCTAssertEqual(OpenAIRealtimeModel(stored: "gpt-realtime-2.1"), .full)
        XCTAssertEqual(OpenAIRealtimeModel(stored: "gpt-realtime-2.1-mini"), .mini)
    }

    // MARK: Token server contract

    func testElevenLabsRequestHasNoBodySoOlderServersSeeTheSameRequest() throws {
        XCTAssertNil(VoiceTokenServer.requestBody(for: .elevenLabs))
        let body = try object(String(decoding: try XCTUnwrap(VoiceTokenServer.requestBody(for: .openAIRealtime)), as: UTF8.self))
        XCTAssertEqual(body["provider"] as? String, "openai")
        XCTAssertEqual(body["model"] as? String, "gpt-realtime-2.1-mini")
        let full = try object(String(decoding: try XCTUnwrap(VoiceTokenServer.requestBody(for: .openAIRealtime, model: .full)), as: UTF8.self))
        XCTAssertEqual(full["model"] as? String, "gpt-realtime-2.1")
    }

    func testOpenAIVoiceIsSentOnlyWhenChosen() throws {
        let unchosen = try object(String(decoding: try XCTUnwrap(VoiceTokenServer.requestBody(for: .openAIRealtime)), as: UTF8.self))
        XCTAssertNil(unchosen["voice"], "nothing chosen: the server's own voice applies")
        let echo = try object(String(decoding: try XCTUnwrap(VoiceTokenServer.requestBody(for: .openAIRealtime, voice: .echo)), as: UTF8.self))
        XCTAssertEqual(echo["voice"] as? String, "echo")
        XCTAssertEqual(OpenAIRealtimeVoice(stored: "cedar"), .cedar)
        XCTAssertNil(OpenAIRealtimeVoice(stored: "ballad"))
        XCTAssertNil(OpenAIRealtimeVoice(stored: nil))
    }

    func testOpenAIGrantParsing() {
        let good = Data(#"{"token":"ek_1","provider":"openai","model":"gpt-realtime"}"#.utf8)
        XCTAssertEqual(VoiceTokenServer.openAIGrant(status: 200, body: good), .success(OpenAIRealtimeGrant(secret: "ek_1", model: "gpt-realtime")))
        // A server from before ADR-265 ignores the body and returns an ElevenLabs token.
        let old = Data(#"{"token":"eyJ.elevenlabs.jwt"}"#.utf8)
        XCTAssertEqual(VoiceTokenServer.openAIGrant(status: 200, body: old), .failure(.badResponse))
        XCTAssertEqual(VoiceTokenServer.openAIGrant(status: 200, body: Data(#"{"token":"","provider":"openai","model":"m"}"#.utf8)), .failure(.badResponse))
        XCTAssertEqual(VoiceTokenServer.openAIGrant(status: 401, body: Data()), .failure(.accessCodeRejected))
        XCTAssertEqual(VoiceTokenServer.openAIGrant(status: 503, body: Data()), .failure(.busy))
        XCTAssertEqual(VoiceTokenServer.openAIGrant(status: 500, body: Data()), .failure(.serverNotConfigured))
        XCTAssertEqual(VoiceTokenServer.openAIGrant(status: 400, body: Data()), .failure(.serverProblem(status: 400)))
    }

    func testSocketURLNamesTheModel() {
        XCTAssertEqual(OpenAIRealtimeWire.socketURL(model: "gpt-realtime")?.absoluteString, "wss://api.openai.com/v1/realtime?model=gpt-realtime")
    }

    // MARK: Session

    func testSessionUpdateCarriesPromptToolsAndTurnTakingButNotVoiceOrModel() throws {
        let tools = try Data(contentsOf: repoRoot.appendingPathComponent("voice-agent/tools.json"))
        let text = try OpenAIRealtimeWire.sessionUpdate(instructions: "Be Doddy.", toolsJSON: tools, eagerness: .high)
        let event = try object(text)
        XCTAssertEqual(event["type"] as? String, "session.update")
        let session = try XCTUnwrap(event["session"] as? [String: Any])
        XCTAssertEqual(session["type"] as? String, "realtime")
        XCTAssertEqual(session["instructions"] as? String, "Be Doddy.")
        XCTAssertEqual(session["tool_choice"] as? String, "auto")
        XCTAssertNil(session["model"], "the model is fixed by the token server")
        let audio = try XCTUnwrap(session["audio"] as? [String: Any])
        let input = try XCTUnwrap(audio["input"] as? [String: Any])
        let output = try XCTUnwrap(audio["output"] as? [String: Any])
        XCTAssertNil(output["voice"], "the voice is fixed by the token server")
        XCTAssertEqual((input["format"] as? [String: Any])?["rate"] as? Int, 24_000)
        XCTAssertEqual((input["format"] as? [String: Any])?["type"] as? String, "audio/pcm")
        XCTAssertEqual((output["format"] as? [String: Any])?["rate"] as? Int, 24_000)
        let turn = try XCTUnwrap(input["turn_detection"] as? [String: Any])
        XCTAssertEqual(turn["type"] as? String, "semantic_vad")
        XCTAssertEqual(turn["eagerness"] as? String, "high")
        XCTAssertEqual(turn["interrupt_response"] as? Bool, true)
        XCTAssertEqual((input["transcription"] as? [String: Any])?["model"] as? String, OpenAIRealtimeWire.transcriptionModel)
    }

    func testToolsAreTheSpecWithoutAppOnlyMetadata() throws {
        let data = try Data(contentsOf: repoRoot.appendingPathComponent("voice-agent/tools.json"))
        let spec = try RealtimeToolCatalog.decode(data)
        let tools = try OpenAIRealtimeWire.realtimeTools(fromToolsJSON: data)
        XCTAssertEqual(tools.map { $0["name"] as? String }, spec.map(\.name))
        for tool in tools {
            XCTAssertNil(tool["x_doddy"])
            XCTAssertEqual(tool["type"] as? String, "function")
            XCTAssertNotNil(tool["parameters"] as? [String: Any])
        }
        // Web tools stay listed, so the model hears they're unavailable instead of inventing an answer.
        XCTAssertTrue(spec.contains { $0.runsOn == .web })
        XCTAssertThrowsError(try OpenAIRealtimeWire.realtimeTools(fromToolsJSON: Data("[]".utf8)))
    }

    func testGreetingFallbackComesFromTheSessionSpecButNeverSpeaksAPlaceholder() throws {
        let spec = Data(#"{"first_message":{"en":"Hey, it's Doddy.","pl":"Hej, tu Doddy.","de":"{{opening_line}}"}}"#.utf8)
        XCTAssertEqual(OpenAIRealtimeWire.greetingLine(sessionJSON: spec, languageCode: "pl"), "Hej, tu Doddy.")
        XCTAssertEqual(OpenAIRealtimeWire.greetingLine(sessionJSON: spec, languageCode: nil), "Hey, it's Doddy.")
        XCTAssertEqual(OpenAIRealtimeWire.greetingLine(sessionJSON: spec, languageCode: "de"), "Hey, it's Doddy.")
        XCTAssertEqual(OpenAIRealtimeWire.greetingLine(sessionJSON: Data(), languageCode: "pl"), "Hey, it's Doddy. What's up?")
        // The repo's spec uses {{opening_line}} (ADR-254); the fallback must still be plain words.
        let session = try Data(contentsOf: repoRoot.appendingPathComponent("voice-agent/session.json"))
        XCTAssertFalse(OpenAIRealtimeWire.greetingLine(sessionJSON: session, languageCode: "pl").contains("{{"))
        let event = try object(OpenAIRealtimeWire.greeting("Hej"))
        XCTAssertEqual(event["type"] as? String, "response.create")
        XCTAssertTrue(((event["response"] as? [String: Any])?["instructions"] as? String ?? "").hasSuffix(": Hej"))
    }

    // MARK: Client events

    func testAudioIsBase64PCM() throws {
        let event = try object(OpenAIRealtimeWire.appendAudio(Data([1, 2, 3, 4])))
        XCTAssertEqual(event["type"] as? String, "input_audio_buffer.append")
        XCTAssertEqual(event["audio"] as? String, "AQIDBA==")
    }

    func testToolOutputIsAnItemAndTheReplyIsAskedForSeparately() throws {
        let event = try object(OpenAIRealtimeWire.functionOutput(RealtimeFunctionOutput(callID: "call_1", output: "Saved.")))
        XCTAssertEqual(event["type"] as? String, "conversation.item.create")
        let item = try XCTUnwrap(event["item"] as? [String: Any])
        XCTAssertEqual(item["type"] as? String, "function_call_output")
        XCTAssertEqual(item["call_id"] as? String, "call_1")
        XCTAssertEqual(item["output"] as? String, "Saved.")
        let failed = try object(OpenAIRealtimeWire.functionOutput(RealtimeFunctionOutput(callID: "c", output: "No access.", isError: true)))
        XCTAssertEqual((failed["item"] as? [String: Any])?["output"] as? String, "Error: No access.")
        XCTAssertEqual(try object(OpenAIRealtimeWire.createResponse())["type"] as? String, "response.create")
    }

    func testSilenceIsZeroPCMOfTheRightLength() throws {
        let event = try object(OpenAIRealtimeWire.silence(milliseconds: 500))
        XCTAssertEqual(event["type"] as? String, "input_audio_buffer.append")
        let pcm = try XCTUnwrap(Data(base64Encoded: event["audio"] as? String ?? ""))
        XCTAssertEqual(pcm.count, 12_000 * 2)
        XCTAssertTrue(pcm.allSatisfy { $0 == 0 })
    }

    func testAppMessagesAreUserItemsToAnswerOrSystemContext() throws {
        let reply = try object(OpenAIRealtimeWire.appMessage("[app] Give the briefing.", respond: true))
        XCTAssertEqual(reply["type"] as? String, "conversation.item.create")
        XCTAssertEqual((reply["item"] as? [String: Any])?["role"] as? String, "user")
        let context = try object(OpenAIRealtimeWire.appMessage("[app] Next words are theirs.", respond: false))
        let item = try XCTUnwrap(context["item"] as? [String: Any])
        XCTAssertEqual(item["role"] as? String, "system")
        XCTAssertEqual((item["content"] as? [[String: Any]])?.first?["text"] as? String, "[app] Next words are theirs.")
    }

    func testTruncateSaysHowMuchWasHeard() throws {
        let event = try object(OpenAIRealtimeWire.truncate(itemID: "item_9", playedSamples: 36_000))
        XCTAssertEqual(event["type"] as? String, "conversation.item.truncate")
        XCTAssertEqual(event["item_id"] as? String, "item_9")
        XCTAssertEqual(event["content_index"] as? Int, 0)
        XCTAssertEqual(event["audio_end_ms"] as? Int, 1500)
        XCTAssertEqual(OpenAIRealtimeWire.audioMilliseconds(samples: -5), 0)
    }

    // MARK: Server events

    func testParsesTheEventsTheAppActsOn() {
        let p = OpenAIRealtimeWire.parse
        XCTAssertEqual(p(#"{"type":"session.created","session":{}}"#), .sessionCreated)
        XCTAssertEqual(p(#"{"type":"session.updated","session":{}}"#), .sessionUpdated)
        XCTAssertEqual(p(#"{"type":"input_audio_buffer.speech_started","audio_start_ms":10}"#), .speechStarted)
        XCTAssertEqual(p(#"{"type":"input_audio_buffer.speech_stopped"}"#), .speechStopped)
        XCTAssertEqual(p(#"{"type":"conversation.item.input_audio_transcription.completed","item_id":"i","transcript":"Hey, can you hear me?"}"#), .userTranscript("Hey, can you hear me?"))
        XCTAssertEqual(p(#"{"type":"response.created","response":{}}"#), .responseCreated)
        XCTAssertEqual(p(#"{"type":"response.output_audio.delta","item_id":"msg_8","delta":"AQIDBA=="}"#), .audioDelta(itemID: "msg_8", pcm16: Data([1, 2, 3, 4])))
        XCTAssertEqual(p(#"{"type":"response.output_audio_transcript.done","item_id":"msg_8","transcript":"Hi!"}"#), .assistantTranscript(itemID: "msg_8", text: "Hi!"))
        XCTAssertEqual(p(#"{"type":"response.function_call_arguments.done","call_id":"call_1","name":"save_memory","arguments":"{\"text\":\"keys\"}"}"#),
                       .functionCall(RealtimeFunctionCall(callID: "call_1", name: "save_memory", arguments: #"{"text":"keys"}"#)))
        XCTAssertEqual(p(#"{"type":"response.done","response":{"status":"completed"}}"#), .responseDone(failure: nil))
        XCTAssertEqual(p(#"{"type":"response.done","response":{"status":"cancelled"}}"#), .responseDone(failure: nil))
        XCTAssertEqual(p(#"{"type":"response.done","response":{"status":"failed","status_details":{"error":{"message":"You exceeded your current quota."}}}}"#),
                       .responseDone(failure: "You exceeded your current quota."))
        XCTAssertEqual(p(#"{"type":"error","error":{"type":"invalid_request_error","code":"invalid_value","message":"Bad"}}"#), .error(code: "invalid_value", message: "Bad"))
        XCTAssertEqual(p(#"{"type":"rate_limits.updated"}"#), .other(type: "rate_limits.updated"))
        XCTAssertEqual(p("not json"), .unreadable)
        XCTAssertEqual(p(#"{"type":"response.output_audio.delta","item_id":"x","delta":"%%%"}"#), .unreadable)
        XCTAssertEqual(p(#"{"type":"response.function_call_arguments.done","name":"x"}"#), .unreadable)
    }

    // MARK: Privacy screen

    func testWhatLeavesThisIPhoneNamesOpenAIOnlyWhenItIsUsed() {
        func state(_ provider: VoiceProvider, tokenServer: Bool = true) -> DataFlowState {
            DataFlowState(rememberConversations: true, shareProfileWithVoice: false, tokenServerSet: tokenServer,
                          connectionsOn: [], pauseAll: false, doddyServerSet: false, askDoddyOn: false,
                          askDoddyUsesNotes: false, voiceProvider: provider)
        }
        func row(_ s: DataFlowState) -> DataFlowRow? { DataFlow.rows(s).first { $0.id == "openaiVoice" } }
        func elevenLabsRow(_ s: DataFlowState) -> DataFlowRow? { DataFlow.rows(s).first { $0.id == "elevenlabs" } }
        func translatorRow(_ s: DataFlowState) -> DataFlowRow? { DataFlow.rows(s).first { $0.id == "translator" } }
        XCTAssertEqual(row(state(.elevenLabs))?.isActive, false)
        // ElevenLabs is named for voice only while it is the one running it.
        XCTAssertEqual(elevenLabsRow(state(.elevenLabs))?.isActive, true)
        XCTAssertEqual(elevenLabsRow(state(.openAIRealtime))?.isActive, false)
        XCTAssertEqual(elevenLabsRow(state(.openAIRealtime, tokenServer: false))?.isActive, true)
        XCTAssertEqual(translatorRow(state(.openAIRealtime))?.destination, "OpenAI (translator mode)")
        XCTAssertEqual(translatorRow(state(.elevenLabs))?.destination, "ElevenLabs (translator mode)")
        XCTAssertEqual(row(state(.openAIRealtime))?.isActive, true)
        XCTAssertEqual(row(state(.openAIRealtime, tokenServer: false))?.isActive, false)
        XCTAssertTrue(row(state(.openAIRealtime))?.what.contains("your saved notes") ?? false)
        XCTAssertTrue(row(state(.openAIRealtime))?.note?.contains("isn't verified") ?? false)
    }

    func testOldConversationLogsStillLoad() throws {
        let old = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","startedAt":0,"endedAt":1,"lines":[{"fromUser":true,"text":"hi"}]}"#
        let log = try JSONDecoder().decode(ConversationLog.self, from: Data(old.utf8))
        XCTAssertNil(log.voiceProvider)
        let tagged = ConversationLog(startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 1), lines: [], voiceProvider: "openai")
        XCTAssertEqual(try JSONDecoder().decode(ConversationLog.self, from: JSONEncoder().encode(tagged)).voiceProvider, "openai")
    }
}
