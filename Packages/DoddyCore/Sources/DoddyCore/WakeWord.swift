import Foundation

// "Hey Doddy" (ADR-254): an opt-in listening mode. While it is on and the user has opened Doddy,
// the iPhone listens for the wake word on the device, with Apple's on-device speech recognition
// (ADR-472; Picovoice before that), so there is no vendor, key or licence to bring. Saying it
// starts a normal voice conversation and the Dynamic Island greets the user ("Hey Pat, what's up?").
//
// What iOS allows, and so what this promises: the microphone can only start while Doddy is open.
// It keeps listening when the user leaves the app (background audio, the orange microphone dot
// stays on and the island says so) until iOS ends the app, the user turns it off, Low Power Mode
// comes on, or another app takes the microphone. It can't listen after a restart or after iOS
// closed Doddy until Doddy is opened again. No audio leaves the iPhone until the wake word starts
// a conversation; the conversation is the same as one started with a tap.
//
// These are the rules only. The listener itself lives in the app (WakeWordListener.swift).

/// What the island says and Doddy speaks first.
public enum WakeGreeting {
    /// Used when the user hasn't given Doddy a name to call them.
    public static let fallbackName = "bud"
    /// The voice agent's first message is `{{opening_line}}` (voice-agent/session.json).
    public static let variableName = "opening_line"

    /// The name to greet with: the nickname from Doddy's personality settings, else the first
    /// word of the approved name from About you, else nil. Both are cleaned like a nickname.
    public static func name(nickname: String?, profileName: String?) -> String? {
        if let nickname = Nickname.clean(nickname) { return nickname }
        let first = profileName?
            .split(whereSeparator: { $0 == " " || $0.isNewline })
            .first
            .map(String.init)
        return Nickname.clean(first)
    }

    /// "Hey Pat, what's up?" — "Hey bud, what's up?" without a name. Polish has no "bud":
    /// "Hej Pat, co słychać?" or "Hej, co słychać?".
    public static func line(name: String?, polish: Bool = false) -> String {
        let name = Nickname.clean(name)
        if polish {
            return name.map { "Hej \($0), co słychać?" } ?? "Hej, co słychać?"
        }
        return "Hey \(name ?? fallbackName), what's up?"
    }

    /// What Doddy says first. After the wake word: the greeting. Otherwise the live agent's own
    /// opening (as read from ElevenLabs on 2026-10-11), so a tap conversation sounds as it did.
    public static func openingLine(afterWakeWord: Bool, name: String?, polish: Bool) -> String {
        if afterWakeWord { return line(name: name, polish: polish) }
        return polish ? "Hej, tu Doddy. Co słychać?" : "Hey, it's Doddy. What's up?"
    }
}

/// Why the listener isn't listening although the switch is on.
public enum WakePause: Equatable, Sendable {
    /// A conversation is running or the voice screen is open; it has the microphone.
    case conversation
    /// Doddy is playing sound of his own (the morning brief read aloud, a voice sample), which
    /// needs the audio set up for playing, not listening.
    case appSound
    /// The iPhone is in Low Power Mode. Listening all the time costs battery.
    case lowPowerMode
    /// iOS gave the microphone to something else (a call, another app recording).
    case interrupted
    /// Too many wake-ups in the last hour (false starts from a TV, say). Each one opens a
    /// conversation with ElevenLabs, so the listener rests until the hour has passed.
    case tooManyWakeUps
}

/// What the Settings row and the island say about the listener.
public enum WakeListenerState: Equatable, Sendable {
    case off
    /// Speech recognition is off for Doddy in the iOS Settings app.
    case speechNotAllowed
    /// This iPhone can't recognize English on the device. Doddy won't send the sound to Apple
    /// instead, so "Hey Doddy" stays off.
    case speechUnavailable
    case microphoneDenied
    /// On, but iOS lets the microphone start only while Doddy is open.
    case waitingForApp
    case listening
    case paused(WakePause)
    /// The microphone or speech recognition couldn't start.
    case failed(String)

    /// Plain words for Settings.
    public var summary: String {
        switch self {
        case .off: "Off."
        case .speechNotAllowed: "Doddy isn't allowed to use speech recognition. Allow it in iOS Settings, Doddy."
        case .speechUnavailable: "This iPhone can't recognize English on the device, and Doddy never sends this sound to Apple, so “Hey Doddy” stays off."
        case .microphoneDenied: "Doddy isn't allowed to use the microphone. Allow it in iOS Settings, Doddy."
        case .waitingForApp: "On. Listening starts when Doddy is open (iOS only lets it start then)."
        case .listening: "Listening for “Hey Doddy” on this iPhone."
        case .paused(.conversation): "Paused while you talk to Doddy."
        case .paused(.appSound): "Paused while Doddy plays sound."
        case .paused(.lowPowerMode): "Paused: Low Power Mode is on."
        case .paused(.interrupted): "Paused: another app or a call has the microphone. Open Doddy to listen again."
        case .paused(.tooManyWakeUps): "Resting: it woke up too often in the last hour. It starts again on its own."
        case .failed(let reason): "Not listening: \(reason)"
        }
    }

    public var isListening: Bool { self == .listening }
}

/// Everything the listener's state depends on, read fresh each time it is worked out.
public struct WakeConditions: Equatable, Sendable {
    public enum Microphone: Equatable, Sendable { case allowed, denied, notAsked }
    /// Speech recognition on this iPhone, for the language and without sending sound to Apple.
    public enum Speech: Equatable, Sendable { case allowed, denied, notAsked, unavailable }

    public var switchedOn: Bool
    public var speech: Speech
    public var microphone: Microphone
    /// A conversation is live or the voice screen is open.
    public var conversationOrVoiceScreen: Bool
    /// The brief is read aloud or a voice sample plays.
    public var appSoundPlaying: Bool
    public var lowPowerMode: Bool
    /// iOS interrupted the microphone and hasn't said it may resume.
    public var interrupted: Bool
    /// Wake-ups that started a conversation in the last hour hit the limit.
    public var overWakeLimit: Bool
    /// Doddy is open on screen, or a conversation has only just handed the microphone back
    /// (the one moment iOS may still let it restart in the background).
    public var mayStartMicrophone: Bool
    /// The engine is running now.
    public var running: Bool
    /// Why the last start failed, until something changes.
    public var startFailure: String?

    public init(switchedOn: Bool, speech: Speech, microphone: Microphone,
                conversationOrVoiceScreen: Bool, appSoundPlaying: Bool = false, lowPowerMode: Bool,
                interrupted: Bool, overWakeLimit: Bool, mayStartMicrophone: Bool, running: Bool,
                startFailure: String? = nil) {
        self.switchedOn = switchedOn
        self.speech = speech
        self.microphone = microphone
        self.conversationOrVoiceScreen = conversationOrVoiceScreen
        self.appSoundPlaying = appSoundPlaying
        self.lowPowerMode = lowPowerMode
        self.interrupted = interrupted
        self.overWakeLimit = overWakeLimit
        self.mayStartMicrophone = mayStartMicrophone
        self.running = running
        self.startFailure = startFailure
    }
}

public enum WakeListenerPolicy {
    /// What the listener should be doing now. `.listening` means: run the engine (start it if it
    /// isn't running and `mayStartMicrophone`). Anything else means: the engine must be stopped.
    public static func state(_ c: WakeConditions) -> WakeListenerState {
        guard c.switchedOn else { return .off }
        if c.microphone == .denied { return .microphoneDenied }
        switch c.speech {
        case .denied: return .speechNotAllowed
        case .unavailable: return .speechUnavailable
        case .allowed, .notAsked: break
        }
        // The conversation comes first: it must have the microphone to itself.
        if c.conversationOrVoiceScreen { return .paused(.conversation) }
        if c.appSoundPlaying { return .paused(.appSound) }
        if c.lowPowerMode { return .paused(.lowPowerMode) }
        if c.overWakeLimit { return .paused(.tooManyWakeUps) }
        if c.interrupted { return .paused(.interrupted) }
        if let failure = c.startFailure, !c.running { return .failed(failure) }
        if c.running { return .listening }
        // Asking for the microphone or speech recognition needs Doddy on screen, so does a first start.
        return c.mayStartMicrophone && c.microphone == .allowed && c.speech == .allowed ? .listening : .waitingForApp
    }
}

/// Which detections may start a conversation.
public struct WakeGate: Equatable, Sendable {
    /// After listening (re)starts, detections are ignored this long, so the end of Doddy's last
    /// sentence or the user's "thanks, bye" can't wake him straight back up.
    public static let settleTime: TimeInterval = 4
    /// At most this many wake-ups start a conversation per rolling hour.
    public static let maxWakeUpsPerHour = 12
    /// A conversation the wake word started ends by itself if the user says nothing this long
    /// after Doddy is ready: most likely the wake word was heard by mistake.
    public static let silentWakeTimeout: TimeInterval = 20

    private(set) public var listeningSince: Date?
    private(set) public var wakeUps: [Date] = []

    public init() {}

    public mutating func listeningStarted(at now: Date) {
        listeningSince = now
    }

    public mutating func listeningStopped() {
        listeningSince = nil
    }

    /// True when a detection at `now` should start a conversation; it is then counted.
    public mutating func accept(at now: Date) -> Bool {
        guard let since = listeningSince, now.timeIntervalSince(since) >= Self.settleTime else { return false }
        prune(now)
        guard wakeUps.count < Self.maxWakeUpsPerHour else { return false }
        wakeUps.append(now)
        return true
    }

    public func isOverLimit(at now: Date) -> Bool {
        wakeUps.filter { now.timeIntervalSince($0) < 3600 }.count >= Self.maxWakeUpsPerHour
    }

    /// When the oldest counted wake-up leaves the hour, or nil when not over the limit.
    public func limitEnds(at now: Date) -> Date? {
        guard isOverLimit(at: now) else { return nil }
        let recent = wakeUps.filter { now.timeIntervalSince($0) < 3600 }.sorted()
        return recent.first.map { $0.addingTimeInterval(3600) }
    }

    private mutating func prune(_ now: Date) {
        wakeUps.removeAll { now.timeIntervalSince($0) >= 3600 }
    }
}

/// Decides whether text the on-device recognizer wrote down contains "Hey Doddy" (ADR-472).
/// Recognizers write a made-up name in many ways, so the common spellings of "Doddy" count, but
/// only straight after a greeting: the name alone, or words like "daddy", never wake Doddy.
public enum WakePhraseMatcher {
    static let greetings: Set<String> = ["hey", "hay", "hei", "hej", "heya", "hi"]
    static let names: Set<String> = ["doddy", "dody", "dodi", "dodie", "doddie", "doddi", "dodee", "dodey"]

    public static func containsWakePhrase(_ transcript: String) -> Bool {
        let folded = transcript.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        let words = folded.split(whereSeparator: { !$0.isLetter }).map(String.init)
        for (index, word) in words.enumerated() {
            // "heydoddy" written as one word.
            if greetings.contains(where: { greeting in names.contains(where: { greeting + $0 == word }) }) { return true }
            if greetings.contains(word), index + 1 < words.count, names.contains(words[index + 1]) { return true }
        }
        return false
    }
}

/// The Home card that offers "Hey Doddy" (ADR-328). Once, after a few real conversations, and only
/// when this iPhone can do it: speech recognition on the device is possible and not refused.
/// "Not now" or "Turn on" ends the offer for good; it never comes back.
public enum HeyDoddyOffer {
    /// Conversations that really connected before the card shows.
    public static let afterConversations = 3

    public static func shouldOffer(conversations: Int, heyDoddyOn: Bool, dismissed: Bool, speechPossible: Bool) -> Bool {
        conversations >= afterConversations && !heyDoddyOn && !dismissed && speechPossible
    }
}

