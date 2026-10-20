import Foundation

// OpenAI Realtime as a choice for Doddy's live voice (ADR-265; the default from ADR-442 until
// ADR-546 made ElevenLabs the default again). Everything here is pure: what the app sends over the WebSocket
// and how it reads what comes back. The socket and audio live in DoddyApp/Features/Voice.
// Wire shapes follow the GA Realtime API (session.type "realtime", audio/pcm at 24 kHz).

// MARK: Provider choice

/// Which company runs Doddy's live voice. ElevenLabs is the default (ADR-546); OpenAI Realtime
/// is a choice in the voice picker. Notes, lists and every tool are the same on both: they live
/// on this iPhone, not with either provider.
public enum VoiceProvider: String, CaseIterable, Sendable, Identifiable {
    case elevenLabs = "elevenlabs"
    case openAIRealtime = "openai"

    public static let preferenceKey = "voice.provider"

    public var id: String { rawValue }

    public var shortName: String {
        switch self {
        case .elevenLabs: "ElevenLabs"
        case .openAIRealtime: "OpenAI"
        }
    }

    /// Anything unknown or missing is ElevenLabs. For a *stored value that is known to be set*
    /// (a conversation log); for "which voice runs the next conversation" use `effective`.
    public init(stored: String?) {
        self = stored.flatMap(VoiceProvider.init(rawValue:)) ?? .elevenLabs
    }

    /// The voice that runs the next conversation. A choice the user made wins. With none (or an
    /// unknown stored value), ElevenLabs is the default (ADR-546, which replaces ADR-442's default),
    /// whether or not the token server is set. `tokenServerSet` stays in the signature so callers
    /// don't change; it no longer picks the default.
    public static func effective(stored: String?, tokenServerSet: Bool) -> VoiceProvider {
        stored.flatMap(VoiceProvider.init(rawValue:)) ?? .elevenLabs
    }
}

/// Which OpenAI Realtime model runs the conversation. The token server only mints secrets for
/// these two ids (it refuses anything else), so the app can't be pointed at a pricier model.
public enum OpenAIRealtimeModel: String, CaseIterable, Sendable, Identifiable {
    case full = "gpt-realtime-2.1"
    case mini = "gpt-realtime-2.1-mini"

    public static let preferenceKey = "voice.openaiModel"
    /// Mini is about a third of the price (docs/research/VOICE_SHORTCUT_ISLAND_TOOLS_2026-10.md);
    /// how it does in Polish and with tools is for the owner to judge on a device.
    public static let `default`: OpenAIRealtimeModel = .mini

    public var id: String { rawValue }

    public var shortName: String {
        switch self {
        case .full: "2.1"
        case .mini: "2.1 mini"
        }
    }

    /// Anything unknown or missing is the default.
    public init(stored: String?) {
        self = stored.flatMap(OpenAIRealtimeModel.init(rawValue:)) ?? .default
    }
}

/// A one-conversation OpenAI client secret from `server/voice-token`.
public struct OpenAIRealtimeGrant: Equatable, Sendable {
    public let secret: String
    public let model: String

    public init(secret: String, model: String) {
        self.secret = secret
        self.model = model
    }
}

extension VoiceTokenServer {
    /// Request body for the token server. ElevenLabs sends none, exactly as before ADR-265.
    /// OpenAI names the model; a server from before ADR-442 ignores it and uses its own.
    public static func requestBody(for provider: VoiceProvider, model: OpenAIRealtimeModel = .default) -> Data? {
        switch provider {
        case .elevenLabs: nil
        case .openAIRealtime: Data(#"{"provider":"openai","model":"\#(model.rawValue)"}"#.utf8)
        }
    }

    /// Reply `{"token": "ek_…", "provider": "openai", "model": "…"}`. A server from before
    /// ADR-265 ignores the body and returns an ElevenLabs token without `provider`; that is
    /// refused here rather than sent to OpenAI.
    public static func openAIGrant(status: Int, body: Data) -> Result<OpenAIRealtimeGrant, VoiceTokenError> {
        guard status == 200 else {
            if case .failure(let error) = token(status: status, body: body) { return .failure(error) }
            return .failure(.serverProblem(status: status))
        }
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              json["provider"] as? String == VoiceProvider.openAIRealtime.rawValue,
              let secret = json["token"] as? String, !secret.isEmpty,
              let model = json["model"] as? String, !model.isEmpty
        else { return .failure(.badResponse) }
        return .success(OpenAIRealtimeGrant(secret: secret, model: model))
    }
}

// MARK: Server events

/// What OpenAI sends, reduced to what the app acts on.
public enum OpenAIRealtimeServerEvent: Equatable, Sendable {
    case sessionCreated
    case sessionUpdated
    /// The user started / stopped talking (server-side voice detection).
    case speechStarted
    case speechStopped
    case userTranscript(String)
    case responseCreated
    /// PCM16 mono 24 kHz audio of one assistant item.
    case audioDelta(itemID: String, pcm16: Data)
    case assistantTranscript(itemID: String, text: String)
    case functionCall(RealtimeFunctionCall)
    /// A response finished. `failure` is set only when OpenAI says it failed (quota, server
    /// error); a reply cut off by the user is not a failure.
    case responseDone(failure: String?)
    /// OpenAI reports a problem with something the app sent. Not necessarily the end of the
    /// conversation; the socket closing is.
    case error(code: String?, message: String)
    case other(type: String)
    case unreadable
}

// MARK: Wire format

public enum OpenAIRealtimeWire {
    public static let sampleRate = 24_000
    /// Model for the user's side of the transcript (shown on screen, kept in the conversation log).
    public static let transcriptionModel = "gpt-4o-mini-transcribe"

    public enum SpecError: Error, Equatable {
        case unreadableTools
    }

    public static func socketURL(model: String) -> URL? {
        var components = URLComponents(string: "wss://api.openai.com/v1/realtime")
        components?.queryItems = [URLQueryItem(name: "model", value: model)]
        return components?.url
    }

    /// `voice-agent/tools.json` as Realtime function tools: `x_doddy` (app-only metadata) removed.
    /// Web tools stay in the list so the model asks for them and hears that they aren't available,
    /// instead of making up a weather report.
    public static func realtimeTools(fromToolsJSON data: Data) throws -> [[String: Any]] {
        guard let file = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tools = file["tools"] as? [[String: Any]]
        else { throw SpecError.unreadableTools }
        return tools.map { tool in
            var stripped = tool
            stripped.removeValue(forKey: "x_doddy")
            return stripped
        }
    }

    /// The first thing sent after connecting: Doddy's rendered prompt, tools and turn-taking.
    /// The voice and model were fixed by the token server and are not changed here.
    public static func sessionUpdate(instructions: String, toolsJSON: Data, eagerness: RealtimeTurnEagerness) throws -> String {
        let session: [String: Any] = [
            "type": "realtime",
            "instructions": instructions,
            "tools": try realtimeTools(fromToolsJSON: toolsJSON),
            "tool_choice": "auto",
            "audio": [
                "input": [
                    "format": ["type": "audio/pcm", "rate": sampleRate],
                    "transcription": ["model": transcriptionModel],
                    "turn_detection": [
                        "type": "semantic_vad",
                        "eagerness": eagerness.rawValue,
                        "create_response": true,
                        "interrupt_response": true,
                    ] as [String: Any],
                ] as [String: Any],
                "output": [
                    "format": ["type": "audio/pcm", "rate": sampleRate],
                ] as [String: Any],
            ] as [String: Any],
        ]
        return encode(["type": "session.update", "session": session])
    }

    /// Doddy speaks first, with the same greeting the ElevenLabs agent uses.
    public static func greeting(_ line: String) -> String {
        encode([
            "type": "response.create",
            "response": ["instructions": "Greet the user by saying exactly this, and nothing else: \(line)"],
        ])
    }

    /// Fallback greeting when the app has no opening line of its own (it normally sends
    /// `WakeGreeting`'s, ADR-254): `voice-agent/session.json` `first_message` for the language, then
    /// English. A `{{placeholder}}` there is never spoken; the plain English line is used instead.
    public static func greetingLine(sessionJSON: Data, languageCode: String?) -> String {
        let fallback = "Hey, it's Doddy. What's up?"
        guard let session = try? JSONSerialization.jsonObject(with: sessionJSON) as? [String: Any],
              let lines = session["first_message"] as? [String: String]
        else { return fallback }
        let usable = lines.filter { !$0.value.contains("{{") }
        if let code = languageCode, let line = usable[code] { return line }
        return usable["en"] ?? fallback
    }

    public static func appendAudio(_ pcm16: Data) -> String {
        encode(["type": "input_audio_buffer.append", "audio": pcm16.base64EncodedString()])
    }

    /// The app's answer to a tool call. Realtime has no error flag on tool output, so an error is
    /// marked in the text. Doddy goes on only after `createResponse()`, which the session sends
    /// once no other response is running (OpenAI refuses a second one at the same time).
    public static func functionOutput(_ output: RealtimeFunctionOutput) -> String {
        encode([
            "type": "conversation.item.create",
            "item": [
                "type": "function_call_output",
                "call_id": output.callID,
                "output": output.isError ? "Error: \(output.output)" : output.output,
            ],
        ])
    }

    /// A message from the app (never something the user said). `respond` = Doddy answers it, after
    /// `createResponse()` (ElevenLabs `sendMessage`); otherwise it is background context
    /// (`updateContext`), sent as a system item.
    public static func appMessage(_ text: String, respond: Bool) -> String {
        encode([
            "type": "conversation.item.create",
            "item": [
                "type": "message",
                "role": respond ? "user" : "system",
                "content": [["type": "input_text", "text": text]],
            ] as [String: Any],
        ])
    }

    /// Asks Doddy to reply to what is in the conversation now.
    public static func createResponse() -> String {
        encode(["type": "response.create"])
    }

    /// Silence for the voice detector: sent once when the microphone is muted mid-sentence (the
    /// translator's hold-to-talk), so OpenAI hears the user stop instead of waiting forever.
    public static func silence(milliseconds: Int) -> String {
        appendAudio(Data(count: max(0, milliseconds) * sampleRate / 1000 * MemoryLayout<Int16>.size))
    }

    /// The user cut Doddy off: tell OpenAI how much of the item was actually heard, so the
    /// conversation history doesn't contain words the user never heard.
    public static func truncate(itemID: String, playedSamples: Int) -> String {
        encode([
            "type": "conversation.item.truncate",
            "item_id": itemID,
            "content_index": 0,
            "audio_end_ms": audioMilliseconds(samples: playedSamples),
        ])
    }

    public static func audioMilliseconds(samples: Int) -> Int {
        max(0, samples) * 1000 / sampleRate
    }

    public static func parse(_ text: String) -> OpenAIRealtimeServerEvent {
        guard let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let type = json["type"] as? String
        else { return .unreadable }
        switch type {
        case "session.created": return .sessionCreated
        case "session.updated": return .sessionUpdated
        case "input_audio_buffer.speech_started": return .speechStarted
        case "input_audio_buffer.speech_stopped": return .speechStopped
        case "conversation.item.input_audio_transcription.completed":
            return .userTranscript(json["transcript"] as? String ?? "")
        case "response.created": return .responseCreated
        case "response.output_audio.delta":
            guard let itemID = json["item_id"] as? String,
                  let delta = json["delta"] as? String,
                  let pcm = Data(base64Encoded: delta)
            else { return .unreadable }
            return .audioDelta(itemID: itemID, pcm16: pcm)
        case "response.output_audio_transcript.done":
            return .assistantTranscript(itemID: json["item_id"] as? String ?? "", text: json["transcript"] as? String ?? "")
        case "response.function_call_arguments.done":
            guard let callID = json["call_id"] as? String, let name = json["name"] as? String else { return .unreadable }
            return .functionCall(RealtimeFunctionCall(callID: callID, name: name, arguments: json["arguments"] as? String ?? "{}"))
        case "response.done":
            let response = json["response"] as? [String: Any]
            guard response?["status"] as? String == "failed" else { return .responseDone(failure: nil) }
            let details = response?["status_details"] as? [String: Any]
            let error = details?["error"] as? [String: Any]
            return .responseDone(failure: error?["message"] as? String ?? "OpenAI couldn't finish the reply.")
        case "error":
            let error = json["error"] as? [String: Any]
            return .error(code: error?["code"] as? String, message: error?["message"] as? String ?? "Unknown error")
        default:
            return .other(type: type)
        }
    }

    private static func encode(_ object: [String: Any]) -> String {
        // Only dictionaries, arrays, strings, numbers and booleans built above: always valid JSON.
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}
