import Foundation

// "Listen until I finish" (OP-019, ADR-364). In a conversation the voice service decides when the
// user has finished, from silence, so a pause or a noisy room can cut them off. In this mode the
// user decides: the conversation's microphone is muted (the service hears nothing and can't end
// the turn), the iPhone records the turn itself, and on Done writes it out on this iPhone and
// sends only the words, as one message. The recording never leaves the iPhone and is deleted once
// the words are sent or the turn is dropped. When it can't be written out, the turn stays as a
// draft the user can retry, type, or drop: it is never sent half-done or lost silently.
// Plain Swift for the Linux tests; VoiceSessionController and LongTurnRecorder use it.

public enum LongTurnProblem: Equatable, Sendable {
    /// The recording had no words in it.
    case nothingHeard
    /// Shorter than `LongTurn.minSeconds`: a mis-tap.
    case tooShort
    /// This iPhone can't write out the language on the device, so it didn't.
    case notOnDevice
    /// Speech recognition is off for Doddy in the Settings app.
    case notAllowed
    case writeOutFailed
    /// The microphone couldn't start recording.
    case recordingFailed
    /// Written out, but the conversation didn't take the message.
    case couldNotSend
}

/// A turn that wasn't sent. Kept on the voice screen only, until Send, Discard or the end of the
/// conversation; never saved anywhere.
public struct LongTurnDraft: Equatable, Sendable {
    public let problem: LongTurnProblem
    /// What will be sent: the words written out, or what the user types.
    public var text: String
    /// The recording is still there to write out again.
    public let canWriteOutAgain: Bool

    public init(problem: LongTurnProblem, text: String = "", canWriteOutAgain: Bool = false) {
        self.problem = problem
        self.text = text
        self.canWriteOutAgain = canWriteOutAgain
    }
}

public enum LongTurnPhase: Equatable, Sendable {
    case off
    case listening(since: Date)
    case writingOut
    case draft(LongTurnDraft)

    public var isListening: Bool {
        if case .listening = self { return true }
        return false
    }
}

public enum LongTurn {
    /// One turn at most this long; at the limit it finishes as if Done was tapped.
    public static let maxSeconds: TimeInterval = 180
    /// Shorter is a mis-tap, not a turn.
    public static let minSeconds: TimeInterval = 0.7
    /// The most sent as one message; longer is cut at a word and marked.
    public static let maxCharacters = 4000

    /// The message for written-out words: trimmed, spaces tidied, cut at `maxCharacters`. Nil when
    /// there are no words.
    public static func message(_ transcript: String) -> String? {
        let words = transcript.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !words.isEmpty else { return nil }
        guard words.count > maxCharacters else { return words }
        let cut = words.prefix(maxCharacters - 1)
        let atWord = cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut
        return String(atWord) + "…"
    }

    /// The language to write out in, from the conversation's language (an ISO code, or nil for
    /// automatic) and the identifiers this iPhone can write out on the device. Nil: none fits.
    public static func locale(conversationCode: String?, onDevice available: [String]) -> String? {
        if let code = conversationCode?.lowercased() {
            return available.first { $0.lowercased() == code || $0.lowercased().hasPrefix(code + "-") || $0.lowercased().hasPrefix(code + "_") }
        }
        return available.first
    }

    /// The problem when a turn can't be sent, and whether the recording can be written out again.
    public static func draft(for problem: LongTurnProblem, text: String = "") -> LongTurnDraft {
        LongTurnDraft(problem: problem, text: text, canWriteOutAgain: problem == .writeOutFailed)
    }

    /// "0:42"
    public static func clock(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    // MARK: Words on the screen

    public static func startLabel(_ language: NotificationLanguage) -> String {
        language == .polish ? "Słuchaj, aż skończę" : "Listen until I finish"
    }

    public static func listeningTitle(_ language: NotificationLanguage) -> String {
        language == .polish ? "Słucham. Stuknij Gotowe, gdy skończysz." : "I'm listening. Tap Done when you've finished."
    }

    public static func listeningDetail(_ language: NotificationLanguage) -> String {
        language == .polish
            ? "Doddy nic nie usłyszy, dopóki nie stukniesz Gotowe. Nagranie zostaje na tym iPhonie; wysyłane są tylko słowa."
            : "Doddy hears nothing until you tap Done. The recording stays on this iPhone; only the words are sent."
    }

    public static func writingOut(_ language: NotificationLanguage) -> String {
        language == .polish ? "Spisuję to na tym iPhonie…" : "Writing it out on this iPhone…"
    }

    public static func problem(_ problem: LongTurnProblem, _ language: NotificationLanguage) -> String {
        let polish = language == .polish
        switch problem {
        case .nothingHeard:
            return polish ? "W tym nagraniu nie było słów. Nic nie wysłano." : "Doddy didn't hear any words in that. Nothing was sent."
        case .tooShort:
            return polish ? "To było za krótkie. Nic nie wysłano." : "That was too short. Nothing was sent."
        case .notOnDevice:
            return polish
                ? "Ten iPhone nie potrafi spisać tego języka bez wysyłania nagrania, więc tego nie zrobił. Wpisz to tutaj."
                : "This iPhone can't write out this language without sending the recording, so it didn't. Type it here instead."
        case .notAllowed:
            return polish
                ? "Rozpoznawanie mowy jest wyłączone dla Doddy’ego w Ustawieniach. Wpisz to tutaj albo włącz je tam."
                : "Speech recognition is off for Doddy in the Settings app. Type it here instead, or allow it there."
        case .writeOutFailed:
            return polish ? "Nie udało się tego spisać. Spróbuj ponownie albo wpisz to tutaj." : "That couldn't be written out. Try again, or type it here."
        case .recordingFailed:
            return polish ? "Nagrywanie nie mogło się zacząć. Nic nie wysłano." : "Recording couldn't start. Nothing was sent."
        case .couldNotSend:
            return polish
                ? "Nie udało się tego wysłać do Doddy’ego. Zostaje tutaj: spróbuj ponownie."
                : "It couldn't be sent to Doddy. It's kept here: try again."
        }
    }
}
