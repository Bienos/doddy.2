import Foundation

/// What Doddy is waiting on while the person waits for an answer, named after the tool that is
/// running. The voice screen turns it into "Searching the web…" and the like instead of one
/// "Working on it…" for 15 seconds (owner, 12 Nov 2026; decision `2026-11-12-voice-turn-feedback`).
/// Only a tool that really started is named: nothing here guesses what Doddy is doing.
public enum VoiceWaitActivity: String, Sendable, CaseIterable {
    case searchingWeb
    case readingNews
    case lookingAtScreen
    case searchingNotes
    case askingClaude
    case checkingEmail
    case findingPlaces
    case makingDocument
    case checkingWeather
    case lookingUp
    case checkingCalendar

    /// The activity for a tool name from the agent, or nil for a tool the screen describes with
    /// the plain "Working on it…" (most tools answer in well under a second).
    public static func forTool(_ name: String) -> VoiceWaitActivity? {
        switch name {
        case "web_search": .searchingWeb
        case "news_search": .readingNews
        case "look_at_screen": .lookingAtScreen
        case "search_memories": .searchingNotes
        case "ask_claude": .askingClaude
        case "check_email", "read_email", "check_outlook_email", "read_outlook_email": .checkingEmail
        case "find_places", "geocode_place": .findingPlaces
        case "make_document", "make_presentation", "make_something": .makingDocument
        case "get_weather": .checkingWeather
        case "wikipedia_search", "wikipedia_summary": .lookingUp
        case "read_calendar", "read_google_calendar", "read_outlook_calendar", "find_free_time": .checkingCalendar
        default: nil
        }
    }
}

/// What the voice screen says while Doddy works: the running tool's activity (nil for a plain
/// wait), and whether the wait has gone on long enough to say "still".
public struct VoiceWaitLabel: Sendable, Equatable {
    public let activity: VoiceWaitActivity?
    public let still: Bool

    public init(activity: VoiceWaitActivity?, still: Bool) {
        self.activity = activity
        self.still = still
    }
}

/// One finished turn: from the person's words arriving on the phone to Doddy starting to answer
/// on the phone, and the tools that ran in between.
public struct VoiceTurnTiming: Sendable, Equatable {
    public struct Tool: Sendable, Equatable {
        public let name: String
        /// nil: still running when Doddy started speaking (he often says "one moment" first).
        public let seconds: Double?
    }

    public let secondsToSpeech: Double
    public let tools: [Tool]

    /// "turn 2.31 s to Doddy speaking · web_search 1.92 s · ask_claude running"
    /// Privacy: fixed words, seconds and tool names from the agent's own tool list. Nothing said,
    /// saved or typed can appear; a name that isn't a plain identifier is written as "tool".
    public var line: String {
        var parts = ["turn \(Self.format(secondsToSpeech)) to Doddy speaking"]
        for tool in tools {
            let name = Self.safeName(tool.name)
            parts.append(tool.seconds.map { "\(name) \(Self.format($0))" } ?? "\(name) running")
        }
        return parts.joined(separator: " · ")
    }

    static func format(_ seconds: Double) -> String { String(format: "%.2f s", seconds) }

    static func safeName(_ name: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789_")
        guard !name.isEmpty, name.count <= 40, name.allSatisfy({ allowed.contains($0) }) else { return "tool" }
        return name
    }
}

/// Follows one conversation's turns from the provider's events, for two things the person sees
/// and one the developer reads (decision `2026-11-12-voice-turn-feedback`):
///
/// - the label while Doddy works (`label(at:)`), with "still" after `stillAfterSeconds`;
/// - holding "Working on it…" after a tool answered (`holdsThinking(at:)`): the ElevenLabs Swift
///   SDK 3.3.1 turns every `agent_tool_response` into "listening", so the screen said Listening
///   while the model was still writing the answer to the tool's result;
/// - the time of each turn, logged on the phone (`agentStartedSpeaking(at:)`).
///
/// Every `at` is one monotonic clock in seconds (`ProcessInfo.systemUptime` in the app). The
/// turn starts when the person's final transcript reaches the phone, the earliest sign the app has
/// that they finished: it has no speech detection of its own (the SDK's runs only while muted), so
/// the provider's end-of-turn wait before that is not in the number.
public struct VoiceTurnWatch: Sendable, Equatable {
    /// "Working on it…" becomes "Still…" after this long.
    public static let stillAfterSeconds: Double = 4
    /// How long "Working on it…" is held after a tool answered, unless Doddy speaks first. The
    /// model's answer starts within about 3.4 s in 95% of turns (ElevenLabs, 9–12 Nov 2026), and
    /// a hold must end on its own if no answer comes.
    public static let holdAfterToolSeconds: Double = 6

    private struct OpenTool: Sendable, Equatable {
        let id: String
        let name: String
        let startedAt: Double
    }

    /// When the person's words arrived; nil once Doddy started answering them.
    public private(set) var turnStartedAt: Double?
    private var openTools: [OpenTool] = []
    private var finishedTools: [VoiceTurnTiming.Tool] = []
    private var waitStartedAt: Double?
    private var toolAnsweredAt: Double?

    public init() {}

    /// The person's words arrived: a new turn. Anything still open from the last one is dropped.
    public mutating func userFinished(at now: Double) {
        self = VoiceTurnWatch()
        turnStartedAt = now
        waitStartedAt = now
    }

    /// A tool started. The same call reported twice (the app's own client tool and the provider's
    /// `agent_tool_request`) counts once.
    public mutating func toolStarted(id: String, name: String, at now: Double) {
        guard !openTools.contains(where: { $0.id == id }) else { return }
        openTools.append(OpenTool(id: id, name: name, startedAt: now))
        waitStartedAt = now
        toolAnsweredAt = nil
    }

    /// A tool answered. An id that isn't open (already answered, or from before this turn) changes
    /// nothing.
    public mutating func toolAnswered(id: String, at now: Double) {
        guard let index = openTools.firstIndex(where: { $0.id == id }) else { return }
        let tool = openTools.remove(at: index)
        if turnStartedAt != nil {
            finishedTools.append(VoiceTurnTiming.Tool(name: tool.name, seconds: max(0, now - tool.startedAt)))
        }
        if openTools.isEmpty {
            toolAnsweredAt = now
            waitStartedAt = now
        }
    }

    /// Doddy started speaking. Returns the finished turn the first time he speaks after the
    /// person's words, nil after that (a second sentence, or speaking with no turn, as in the
    /// opening line).
    public mutating func agentStartedSpeaking(at now: Double) -> VoiceTurnTiming? {
        toolAnsweredAt = nil
        if openTools.isEmpty { waitStartedAt = nil }
        guard let started = turnStartedAt else { return nil }
        turnStartedAt = nil
        let running = openTools.map { VoiceTurnTiming.Tool(name: $0.name, seconds: nil) }
        let timing = VoiceTurnTiming(secondsToSpeech: max(0, now - started), tools: finishedTools + running)
        finishedTools = []
        return timing
    }

    /// The person interrupted, or the conversation ended: nothing is waiting any more.
    public mutating func reset() {
        self = VoiceTurnWatch()
    }

    /// What to say while Doddy works: the newest running tool's activity, "still" after
    /// `stillAfterSeconds` of the same wait. nil when nothing is being waited on.
    public func label(at now: Double) -> VoiceWaitLabel? {
        guard let since = waitStartedAt else { return nil }
        let activity = openTools.last.flatMap { VoiceWaitActivity.forTool($0.name) }
        return VoiceWaitLabel(activity: activity, still: now - since >= Self.stillAfterSeconds)
    }

    /// When the current wait's label turns to "still", for the app to look again then.
    public func stillFrom() -> Double? {
        waitStartedAt.map { $0 + Self.stillAfterSeconds }
    }

    /// True while the screen should keep "Working on it…" although the provider said listening:
    /// a tool answered less than `holdAfterToolSeconds` ago and Doddy hasn't spoken since.
    public func holdsThinking(at now: Double) -> Bool {
        guard let answered = toolAnsweredAt, openTools.isEmpty else { return false }
        return now - answered < Self.holdAfterToolSeconds
    }

    /// When a hold that is on now ends by itself, for the app to look again then.
    public func holdEnds() -> Double? {
        toolAnsweredAt.map { $0 + Self.holdAfterToolSeconds }
    }
}
