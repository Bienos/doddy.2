import Foundation

// Provider-neutral voice layer shaped after the OpenAI Realtime API, so ElevenLabs (today) and
// OpenAI Realtime (later) plug into the same app code. The spec lives in voice-agent/
// (instructions.md, tools.json, session.json); see voice-agent/README.md for the mapping.

/// What a provider reports during a conversation, in Realtime terms. Adapters translate their
/// SDK's callbacks into these; nothing here is inferred from timers.
public enum RealtimeEvent: Equatable, Sendable {
    /// Connected and ready for the user to speak (Realtime: session.created).
    case sessionReady
    /// The user started / stopped talking (Realtime: input_audio_buffer.speech_started / _stopped).
    case userSpeechStarted
    case userSpeechStopped
    /// Final transcript of what the user said (Realtime: …input_audio_transcription.completed).
    case userTranscript(String)
    /// The assistant began working on a reply (Realtime: response.created; ElevenLabs: "thinking").
    case responseStarted
    /// The assistant's audio started playing (Realtime: first response.output_audio.delta).
    case audioStarted
    /// Text of what the assistant said (Realtime: response.output_audio_transcript.done).
    case assistantTranscript(String)
    /// The assistant was cut off; the text actually spoken replaces the earlier line.
    case assistantTranscriptCorrected(original: String, corrected: String)
    /// The model wants the app to run a tool (Realtime: response.function_call_arguments.done).
    case functionCall(RealtimeFunctionCall)
    /// The reply finished and the assistant is listening again (Realtime: response.done).
    case responseDone
    case error(String)
    case ended
}

/// A tool call proposed by the model. `arguments` is the JSON object text the model produced.
public struct RealtimeFunctionCall: Equatable, Sendable {
    public let callID: String
    public let name: String
    public let arguments: String

    public init(callID: String, name: String, arguments: String) {
        self.callID = callID
        self.name = name
        self.arguments = arguments
    }

    public var argumentsData: Data { Data(arguments.utf8) }
}

/// The app's answer to a tool call (Realtime: conversation.item.create of type
/// function_call_output, followed by response.create).
public struct RealtimeFunctionOutput: Equatable, Sendable {
    public let callID: String
    public let output: String
    public let isError: Bool

    public init(callID: String, output: String, isError: Bool = false) {
        self.callID = callID
        self.output = output
        self.isError = isError
    }
}

/// How quickly the assistant takes its turn once the user pauses.
/// Realtime: semantic_vad eagerness; ElevenLabs: turn_eagerness (patient / normal / eager).
public enum RealtimeTurnEagerness: String, Sendable, CaseIterable {
    case low, medium, high, auto

    public var elevenLabsValue: String {
        switch self {
        case .low: "patient"
        case .medium, .auto: "normal"
        case .high: "eager"
        }
    }
}

public struct RealtimeSessionConfig: Equatable, Sendable {
    /// voice-agent/instructions.md with {{placeholders}}.
    public var instructionsTemplate: String
    /// Values for the placeholders (ElevenLabs: dynamic variables; Realtime: rendered locally).
    public var variables: [String: String]
    public var tools: [RealtimeToolSpec]
    public var turnEagerness: RealtimeTurnEagerness
    /// Stable, random per-install id (no personal data), for provider-side usage limits.
    public var userID: String?

    public init(instructionsTemplate: String, variables: [String: String], tools: [RealtimeToolSpec],
                turnEagerness: RealtimeTurnEagerness = .high, userID: String? = nil) {
        self.instructionsTemplate = instructionsTemplate
        self.variables = variables
        self.tools = tools
        self.turnEagerness = turnEagerness
        self.userID = userID
    }
}

/// One live conversation with a voice provider. The app drives it only through this protocol.
public protocol RealtimeVoiceSession: AnyObject, Sendable {
    var events: AsyncStream<RealtimeEvent> { get }
    func start(_ config: RealtimeSessionConfig) async throws
    func send(_ output: RealtimeFunctionOutput) async throws
    func setMicrophoneMuted(_ muted: Bool) async throws
    func end() async
}

// MARK: Instructions

public enum RealtimeInstructions {
    public enum RenderError: Error, Equatable {
        case missingVariables([String])
    }

    /// Names of the {{placeholders}} in a template, in order of first appearance.
    public static func placeholders(in template: String) -> [String] {
        var seen: [String] = []
        for match in template.matches(of: placeholderPattern) {
            let name = String(match.output.1)
            if !seen.contains(name) { seen.append(name) }
        }
        return seen
    }

    /// Fills every placeholder. Throws instead of sending a prompt with a hole in it.
    /// Values are inserted as plain text; braces in them are not expanded again.
    public static func render(_ template: String, variables: [String: String]) throws -> String {
        let missing = placeholders(in: template).filter { variables[$0] == nil }
        guard missing.isEmpty else { throw RenderError.missingVariables(missing) }
        return template.replacing(placeholderPattern) { match in
            variables[String(match.output.1)] ?? ""
        }
    }

    private static var placeholderPattern: Regex<(Substring, Substring)> {
        #/\{\{\s*([a-z_][a-z0-9_]*)\s*\}\}/#
    }
}

// MARK: Tool catalog (voice-agent/tools.json)

/// One function tool in OpenAI Realtime form, plus what only the app needs (x_doddy).
public struct RealtimeToolSpec: Equatable, Sendable, Decodable {
    public enum RunsOn: String, Sendable, Decodable {
        /// Executed by the app on the iPhone (notes, calendar, reminders, contacts).
        case phone
        /// A plain HTTPS lookup (weather, Wikipedia). ElevenLabs runs these itself; with
        /// OpenAI Realtime the app or the token server must make the request.
        case web
    }

    public let name: String
    public let description: String
    public let parameterNames: [String]
    public let requiredParameters: [String]
    public let runsOn: RunsOn
    /// The user must approve on screen before anything happens.
    public let confirmOnScreen: Bool
    /// ASK-01 (ADR-483): how the user says yes before the tool runs. Nil only in older specs
    /// (the phone agent); the app agent's spec check requires it on every tool.
    public enum Ask: String, Sendable, Decodable {
        /// A read: the user's spoken yes or a tap.
        case yesOrTap = "yes_or_tap"
        /// A change: only a tap on the card.
        case tap
        /// A public lookup (web, news, places, sums, conversions): runs at once (ADR-565).
        case runsNow = "runs_now"
    }
    public let ask: Ask?
    public let timeoutSeconds: Int

    private enum Keys: String, CodingKey { case type, name, description, parameters, x_doddy }
    private enum ParameterKeys: String, CodingKey { case properties, required }
    private enum DoddyKeys: String, CodingKey { case runs_on, confirm_on_screen, ask, timeout_secs }

    private struct AnyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let type = try c.decode(String.self, forKey: .type)
        guard type == "function" else {
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "only function tools are supported")
        }
        name = try c.decode(String.self, forKey: .name)
        description = try c.decode(String.self, forKey: .description)
        let p = try c.nestedContainer(keyedBy: ParameterKeys.self, forKey: .parameters)
        let props = try p.nestedContainer(keyedBy: AnyKey.self, forKey: .properties)
        parameterNames = props.allKeys.map(\.stringValue).sorted()
        requiredParameters = try p.decodeIfPresent([String].self, forKey: .required) ?? []
        let x = try c.nestedContainer(keyedBy: DoddyKeys.self, forKey: .x_doddy)
        runsOn = try x.decode(RunsOn.self, forKey: .runs_on)
        confirmOnScreen = try x.decodeIfPresent(Bool.self, forKey: .confirm_on_screen) ?? false
        ask = try x.decodeIfPresent(Ask.self, forKey: .ask)
        timeoutSeconds = try x.decode(Int.self, forKey: .timeout_secs)
    }
}

public enum RealtimeToolCatalog {
    private struct File: Decodable { let tools: [RealtimeToolSpec] }

    public static func decode(_ data: Data) throws -> [RealtimeToolSpec] {
        try JSONDecoder().decode(File.self, from: data).tools
    }

    /// Phone tools the app does not know how to run. Each one would leave the model waiting
    /// until its timeout, so this list must be empty in a build that talks to the agent.
    public static func unhandledPhoneTools(_ tools: [RealtimeToolSpec], handled: Set<String>) -> [String] {
        tools.filter { $0.runsOn == .phone && !handled.contains($0.name) }.map(\.name)
    }
}

// MARK: Conversation state

/// Turns provider events into what the voice screen shows. Pure and deterministic, so both
/// providers produce the same UI from the same events.
public struct RealtimeConversationState: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case connecting, listening, userSpeaking, thinking, speaking, ended
        case failed(String)
    }

    public struct Line: Equatable, Sendable {
        public let fromUser: Bool
        public var text: String
    }

    public private(set) var phase: Phase = .connecting
    public private(set) var lines: [Line] = []
    /// Tool calls received and not yet answered, oldest first.
    public private(set) var openCalls: [RealtimeFunctionCall] = []

    public init() {}

    public var isLive: Bool {
        switch phase {
        case .ended, .failed: false
        default: true
        }
    }

    public mutating func apply(_ event: RealtimeEvent) {
        guard isLive else { return }
        switch event {
        case .sessionReady:
            if phase == .connecting { phase = .listening }
        case .userSpeechStarted:
            phase = .userSpeaking
        case .userSpeechStopped:
            if phase == .userSpeaking { phase = .thinking }
        case .userTranscript(let text):
            append(text, fromUser: true)
        case .responseStarted:
            phase = .thinking
        case .audioStarted:
            phase = .speaking
        case .assistantTranscript(let text):
            append(text, fromUser: false)
        case .assistantTranscriptCorrected(let original, let corrected):
            if let i = lines.lastIndex(where: { !$0.fromUser && $0.text == original }) {
                lines[i].text = corrected
            }
        case .functionCall(let call):
            if !openCalls.contains(where: { $0.callID == call.callID }) { openCalls.append(call) }
            phase = .thinking
        case .responseDone:
            phase = .listening
        case .error(let message):
            phase = .failed(message)
            openCalls = []
        case .ended:
            phase = .ended
            openCalls = []
        }
    }

    /// Records that the app answered a call (or gave up on it).
    public mutating func answered(_ callID: String) {
        openCalls.removeAll { $0.callID == callID }
    }

    private mutating func append(_ text: String, fromUser: Bool) {
        guard !text.allSatisfy(\.isWhitespace) else { return }
        lines.append(Line(fromUser: fromUser, text: text))
    }
}
