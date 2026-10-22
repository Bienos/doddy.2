import Foundation

// Audio privacy signal and stop (OP-024, ADR-361). Doddy has two things that can have the
// microphone open: a voice conversation, a voice memo being recorded, and a DODDY Capture
// recording (ADR-588; "Hey Doddy", another, was removed in ADR-549). While any has it, Doddy shows one indicator that says which, above
// every screen, with Stop listening. "Stop listening" (the indicator, or Siri) ends the
// conversation and stops the memo, then reads each one's own state again:
// "Stopped" only when every one says it is closed and iOS let go of Doddy's audio. Nothing is
// saved by stopping: a note Doddy was asking about and the memo stay as drafts.
// Plain Swift for the Linux tests; ListeningStop.swift in the app uses it.

/// What in Doddy can have the microphone open.
public enum MicrophoneUser: String, CaseIterable, Sendable {
    case conversation, voiceMemo, capture

    public func name(_ language: NotificationLanguage) -> String {
        switch (self, language) {
        case (.conversation, .english): "the conversation"
        case (.conversation, .polish): "rozmowa"
        case (.voiceMemo, .english): "the voice memo"
        case (.voiceMemo, .polish): "notatka głosowa"
        case (.capture, .english): "the recording"
        case (.capture, .polish): "nagranie"
        }
    }
}

/// Who has the microphone open now, read from each one's own state, never from what was asked.
public struct MicrophoneSnapshot: Equatable, Sendable {
    public enum Conversation: Equatable, Sendable {
        case none
        /// Asked to connect; the microphone opens when the voice service is ready.
        case connecting
        case listening
        /// What the user says isn't sent. The microphone itself may still be open (the OpenAI test
        /// voice keeps capturing and drops it), so this still counts as open.
        case muted
        /// "Listen until I finish" (ADR-364): the conversation is muted and the iPhone records the
        /// turn itself, to write it out on the device.
        case longTurn
    }

    public var conversation: Conversation
    public var voiceMemoRecording: Bool
    /// A DODDY Capture recording is writing audio now (`CaptureStateMachine.isCapturingAudio`).
    public var captureRecording: Bool

    public init(conversation: Conversation = .none, voiceMemoRecording: Bool = false, captureRecording: Bool = false) {
        self.conversation = conversation
        self.voiceMemoRecording = voiceMemoRecording
        self.captureRecording = captureRecording
    }

    /// Everything that has the microphone open, or may open it any moment by itself.
    public var open: [MicrophoneUser] {
        var users: [MicrophoneUser] = []
        if conversation != .none { users.append(.conversation) }
        if voiceMemoRecording { users.append(.voiceMemo) }
        if captureRecording { users.append(.capture) }
        return users
    }
}

/// The indicator shown above every screen while Doddy has the microphone open. Nil when nothing
/// has it, so it never says "listening" when nothing is.
public struct ListeningIndicator: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case connecting, conversation, muted, longTurn, voiceMemo, capture
    }

    /// In the order they are shown; the first decides the symbol.
    public let kinds: [Kind]

    public static func current(_ snapshot: MicrophoneSnapshot) -> ListeningIndicator? {
        var kinds: [Kind] = []
        switch snapshot.conversation {
        case .none: break
        case .connecting: kinds.append(.connecting)
        case .listening: kinds.append(.conversation)
        case .muted: kinds.append(.muted)
        case .longTurn: kinds.append(.longTurn)
        }
        if snapshot.voiceMemoRecording { kinds.append(.voiceMemo) }
        if snapshot.captureRecording { kinds.append(.capture) }
        return kinds.isEmpty ? nil : ListeningIndicator(kinds: kinds)
    }

    public func title(_ language: NotificationLanguage) -> String {
        kinds.map { Self.title($0, language) }.joined(separator: " · ")
    }

    /// One line under the title, for the first kind.
    public func detail(_ language: NotificationLanguage) -> String {
        Self.detail(kinds[0], language)
    }

    /// An SF Symbol for the first kind.
    public var symbol: String {
        switch kinds[0] {
        case .connecting, .conversation: "mic.fill"
        case .muted: "mic.slash.fill"
        case .longTurn: "waveform"
        case .voiceMemo: "record.circle"
        case .capture: "record.circle.fill"
        }
    }

    public static func stopLabel(_ language: NotificationLanguage) -> String {
        language == .polish ? "Przestań słuchać" : "Stop listening"
    }

    private static func title(_ kind: Kind, _ language: NotificationLanguage) -> String {
        let polish = language == .polish
        switch kind {
        case .connecting: return polish ? "Doddy się łączy" : "Doddy is connecting"
        case .conversation: return polish ? "Doddy słucha" : "Doddy is listening"
        case .muted: return polish ? "Mikrofon wyciszony" : "Microphone muted"
        case .longTurn: return polish ? "Słucham, aż skończysz" : "Listening until you finish"
        case .voiceMemo: return polish ? "Nagrywanie notatki głosowej" : "Recording a voice memo"
        case .capture: return CapturePresentation.pillTitle(language)
        }
    }

    private static func detail(_ kind: Kind, _ language: NotificationLanguage) -> String {
        let polish = language == .polish
        switch kind {
        case .connecting:
            return polish ? "Mikrofon włączy się, gdy Doddy będzie gotowy." : "The microphone opens when Doddy is ready."
        case .conversation:
            return polish ? "Twój głos trafia do usługi głosowej, dopóki trwa rozmowa." : "Your voice goes to the voice service while you talk."
        case .muted:
            return polish ? "To, co mówisz, nie jest wysyłane. „Przestań słuchać” kończy rozmowę." : "What you say isn't sent. Stop listening ends the conversation."
        case .longTurn:
            return polish ? "Nagrywane na tym iPhonie; po Gotowe wysyłane są tylko słowa." : "Recorded on this iPhone; only the words are sent when you tap Done."
        case .voiceMemo:
            return polish ? "Tylko na tym iPhonie." : "On this iPhone only."
        case .capture:
            return CapturePresentation.pillDetail(language)
        }
    }
}

/// What happened to one microphone user when the user said "Stop listening".
public enum MicrophoneStopOutcome: Equatable, Sendable {
    /// It wasn't on, and isn't.
    case wasOff
    /// It was on and now says it is closed.
    case closed
    /// It still says it is open after being stopped.
    case stillOpen
}

/// Whether iOS let go of Doddy's audio after everything was stopped.
public enum AudioRelease: Equatable, Sendable {
    /// Nothing was on, so it wasn't asked.
    case notNeeded
    case released
    /// iOS said something was still running and stopped it (the audio session's "busy"). Closed.
    case stoppedWhatWasRunning
    case failed(String)
}

public struct ListeningStopReport: Equatable, Sendable {
    public let conversation: MicrophoneStopOutcome
    public let voiceMemo: MicrophoneStopOutcome
    public let capture: MicrophoneStopOutcome
    public let release: AudioRelease
    /// The "Save this note?" card that was showing is kept as a draft on the voice screen.
    public let keptNoteDraft: Bool
    /// The memo recorded so far is kept on the note being written, not saved.
    public let keptMemoDraft: Bool
    /// The recording was closed and saved (read back from the store), not merely stopped.
    public let captureSaved: Bool

    /// `before` is read before anything is stopped, `after` once each has been asked to stop.
    public init(before: MicrophoneSnapshot, after: MicrophoneSnapshot, release: AudioRelease,
                keptNoteDraft: Bool = false, keptMemoDraft: Bool = false, captureSaved: Bool = false) {
        func outcome(_ user: MicrophoneUser, wasOn: Bool) -> MicrophoneStopOutcome {
            if after.open.contains(user) { return .stillOpen }
            return wasOn ? .closed : .wasOff
        }
        conversation = outcome(.conversation, wasOn: before.open.contains(.conversation))
        voiceMemo = outcome(.voiceMemo, wasOn: before.open.contains(.voiceMemo))
        capture = outcome(.capture, wasOn: before.open.contains(.capture))
        self.release = release
        self.keptNoteDraft = keptNoteDraft
        self.keptMemoDraft = keptMemoDraft
        self.captureSaved = captureSaved
    }

    public var stillOpen: [MicrophoneUser] {
        [(MicrophoneUser.conversation, conversation), (.voiceMemo, voiceMemo), (.capture, capture)]
            .filter { $0.1 == .stillOpen }.map(\.0)
    }

    /// True only when every user says it is closed and iOS let go of the audio.
    public var stopped: Bool {
        guard stillOpen.isEmpty else { return false }
        if case .failed = release { return false }
        return true
    }

    public var nothingWasOn: Bool {
        [conversation, voiceMemo, capture].allSatisfy { $0 == .wasOff }
    }

    /// What Siri says and the indicator shows. "Stopped" only when `stopped`.
    public func reply(_ language: NotificationLanguage) -> String {
        let polish = language == .polish
        if !stillOpen.isEmpty {
            let names = stillOpen.map { $0.name(language) }.joined(separator: polish ? ", " : " and ")
            return polish
                ? "Doddy nie zdołał zatrzymać: \(names). Spróbuj ponownie; jeśli pomarańczowa kropka mikrofonu nie znika, zamknij Doddy’ego w przełączniku aplikacji."
                : "Doddy couldn't stop \(names). Try again; if iOS's orange microphone dot stays on, close Doddy from the app switcher."
        }
        if case .failed(let reason) = release {
            return polish
                ? "Doddy wyłączył wszystko, co słuchało, ale iOS jeszcze nie zwolnił dźwięku Doddy’ego (\(reason)). Jeśli pomarańczowa kropka mikrofonu nie znika, spróbuj ponownie albo zamknij Doddy’ego w przełączniku aplikacji."
                : "Doddy turned off everything that was listening, but iOS hasn't released Doddy's audio yet (\(reason)). If the orange microphone dot stays on, try again or close Doddy from the app switcher."
        }
        if nothingWasOn {
            return polish ? "Doddy nie słuchał. Mikrofon jest wyłączony." : "Doddy wasn't listening. The microphone is off."
        }
        var parts = [polish ? "Zatrzymano. Doddy nie słucha." : "Stopped. Doddy isn't listening."]
        if conversation == .closed { parts.append(polish ? "Rozmowa zakończona." : "The conversation is ended.") }
        if keptNoteDraft {
            parts.append(polish ? "Notatka, o którą pytał Doddy, czeka jako szkic; nic nie zostało zapisane." : "The note Doddy was asking about is kept as a draft; nothing was saved.")
        }
        if voiceMemo == .closed {
            parts.append(keptMemoDraft
                ? (polish ? "Nagranie czeka przy notatce jako szkic, dopóki go nie zapiszesz albo nie odrzucisz." : "The recording is kept with your note as a draft until you save or drop it.")
                : (polish ? "Nagrywanie zatrzymane; było za krótkie, żeby je zachować." : "Recording stopped; it was too short to keep."))
        }
        if capture == .closed {
            parts.append(captureSaved
                ? (polish ? "Nagranie zapisane w Nagraniach." : "The recording is saved in Recordings.")
                : (polish ? "Nagranie zatrzymane. Doddy nie potwierdził zapisu; sprawdź Nagrania." : "Recording stopped. Doddy hasn't confirmed it was saved; check Recordings."))
        }
        return parts.joined(separator: " ")
    }
}
