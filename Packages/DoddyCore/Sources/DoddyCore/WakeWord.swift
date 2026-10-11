import Foundation

// "Hey Doddy" (ADR-234): an opt-in listening mode. While it is on and the user has opened Doddy,
// the iPhone listens for the wake word on the device (Picovoice Porcupine, a keyword file the
// user makes in the Picovoice Console). Saying it starts a normal voice conversation and the
// Dynamic Island greets the user ("Hey Pat, what's up?").
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

    /// What Doddy says first. After the wake word: the greeting. Otherwise the agent's usual
    /// opening, so a conversation started with a tap sounds as it always did.
    public static func openingLine(afterWakeWord: Bool, name: String?, polish: Bool) -> String {
        if afterWakeWord { return line(name: name, polish: polish) }
        return polish ? "Hej, tu Doddy. Co słychać?" : "Hey, it's Doddy. What's on your mind?"
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

/// What's missing before "Hey Doddy" can work.
public enum WakeSetUpGap: Equatable, Sendable {
    case accessKey, keywordFile, both
}

/// What the Settings row and the island say about the listener.
public enum WakeListenerState: Equatable, Sendable {
    case off
    case needsSetUp(WakeSetUpGap)
    case microphoneDenied
    /// On, but iOS lets the microphone start only while Doddy is open.
    case waitingForApp
    case listening
    case paused(WakePause)
    /// Picovoice refused the key or the keyword file, or the microphone couldn't start.
    case failed(String)

    /// Plain words for Settings.
    public var summary: String {
        switch self {
        case .off: "Off."
        case .needsSetUp(.accessKey): "Add your Picovoice AccessKey to turn this on."
        case .needsSetUp(.keywordFile): "Add your “Hey Doddy” keyword file to turn this on."
        case .needsSetUp(.both): "Add your Picovoice AccessKey and “Hey Doddy” keyword file to turn this on."
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

    public var switchedOn: Bool
    public var hasAccessKey: Bool
    public var hasKeywordFile: Bool
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

    public init(switchedOn: Bool, hasAccessKey: Bool, hasKeywordFile: Bool, microphone: Microphone,
                conversationOrVoiceScreen: Bool, appSoundPlaying: Bool = false, lowPowerMode: Bool,
                interrupted: Bool, overWakeLimit: Bool, mayStartMicrophone: Bool, running: Bool,
                startFailure: String? = nil) {
        self.switchedOn = switchedOn
        self.hasAccessKey = hasAccessKey
        self.hasKeywordFile = hasKeywordFile
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
        switch (c.hasAccessKey, c.hasKeywordFile) {
        case (false, false): return .needsSetUp(.both)
        case (false, true): return .needsSetUp(.accessKey)
        case (true, false): return .needsSetUp(.keywordFile)
        case (true, true): break
        }
        if c.microphone == .denied { return .microphoneDenied }
        // The conversation comes first: it must have the microphone to itself.
        if c.conversationOrVoiceScreen { return .paused(.conversation) }
        if c.appSoundPlaying { return .paused(.appSound) }
        if c.lowPowerMode { return .paused(.lowPowerMode) }
        if c.overWakeLimit { return .paused(.tooManyWakeUps) }
        if c.interrupted { return .paused(.interrupted) }
        if let failure = c.startFailure, !c.running { return .failed(failure) }
        if c.running { return .listening }
        // Asking for the microphone needs Doddy on screen, so does a first start.
        return c.mayStartMicrophone && c.microphone == .allowed ? .listening : .waitingForApp
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

/// The Picovoice AccessKey as typed or pasted. It is kept in the Keychain on this iPhone only.
public enum WakeAccessKey {
    /// Trimmed key, or nil when it can't be one (empty, spaces inside, implausible length).
    public static func clean(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (20...256).contains(trimmed.count),
              !trimmed.contains(where: { $0.isWhitespace || $0.isNewline })
        else { return nil }
        return trimmed
    }
}

/// The "Hey Doddy" keyword file (.ppn) the user downloads from the Picovoice Console.
public enum WakeKeywordFile {
    public enum Problem: Equatable, Sendable {
        case notAKeywordFile
        case empty
        case tooLarge
        /// Made for another platform (Android, macOS …); Porcupine on iOS refuses it.
        case otherPlatform(String)
        /// Made for a language other than English, which needs a model file Doddy doesn't include.
        case language(String)

        public var message: String {
            switch self {
            case .notAKeywordFile: "That isn't a Porcupine keyword file. Choose the .ppn file from the Picovoice Console."
            case .empty: "That file is empty."
            case .tooLarge: "That file is too large to be a keyword file."
            case .otherPlatform(let platform): "That keyword file is made for \(platform). Make it again in the Picovoice Console with the platform set to iOS."
            case .language(let code): "That keyword file is for language “\(code)”. Doddy can only use English keyword files for now."
            }
        }
    }

    public static let maxBytes = 1_000_000
    private static let otherPlatforms = [
        "android": "Android", "linux": "Linux", "mac": "macOS", "windows": "Windows",
        "wasm": "the web", "raspberry-pi": "Raspberry Pi", "jetson": "Jetson",
    ]

    /// Checks the console's naming (`Hey-Doddy_en_ios_v4_0_0.ppn`) when it is still there; a
    /// renamed file is only checked for type and size, and Porcupine itself checks the rest.
    public static func check(fileName: String, byteCount: Int) -> Problem? {
        let lower = fileName.lowercased()
        guard lower.hasSuffix(".ppn") else { return .notAKeywordFile }
        guard byteCount > 0 else { return .empty }
        guard byteCount <= maxBytes else { return .tooLarge }
        let parts = lower.dropLast(4).split(separator: "_").map(String.init)
        if let platform = parts.first(where: { otherPlatforms[$0] != nil }) {
            return .otherPlatform(otherPlatforms[platform]!)
        }
        if let ios = parts.firstIndex(of: "ios"), ios > 0 {
            let code = parts[ios - 1]
            if code.count == 2, code.allSatisfy(\.isLetter), code != "en" { return .language(code) }
        }
        return nil
    }
}
