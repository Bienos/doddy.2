import Foundation

// One owner of the audio session (ADR-695). iOS gives an app one audio session, and before this rule
// every part of Doddy that uses it checked only some of the others and switched the session off when
// it was done, whatever else was using it. Messages dictation, a voice sample or a note read aloud could
// so turn off a conversation's microphone while Home still said "Listening". Now each part asks before
// it starts, and the session is switched off only when nothing of Doddy's uses it any more. Plain Swift
// for the Linux tests; `AudioSessionOwner` in the app follows it.

/// Everything in Doddy that uses the audio session.
public enum AudioUse: String, CaseIterable, Sendable {
    /// A voice conversation with Doddy (ElevenLabs), the translator included.
    case conversation
    /// A DODDY Capture recording (ADR-579).
    case captureRecording
    /// A voice memo being recorded (ADR-230).
    case memoRecording
    /// The microphone in Messages.
    case dictation
    /// A voice memo being played.
    case memoPlayback
    /// A Capture recording being played.
    case recordingPlayback
    /// A note read aloud (ADR-243).
    case readAloud
    /// A voice sample in Settings › Voice.
    case voicePreview

    /// It listens. Only one of these may run at a time; the others only play.
    public var usesMicrophone: Bool {
        switch self {
        case .conversation, .captureRecording, .memoRecording, .dictation: true
        case .memoPlayback, .recordingPlayback, .readAloud, .voicePreview: false
        }
    }
}

/// The answer to a part of Doddy that wants the audio session.
public enum AudioClaim: Equatable, Sendable {
    /// Go ahead, once these have been stopped (only ever uses that play, never one that listens).
    case go(stopping: Set<AudioUse>)
    /// Don't start: this one has the microphone. The caller says so in its own words.
    case refused(by: AudioUse)
}

public enum AudioSessionPolicy {
    /// When several are in the way, the one named first here is the one the refusal names.
    public static let precedence: [AudioUse] = [
        .conversation, .captureRecording, .memoRecording, .dictation,
        .memoPlayback, .recordingPlayback, .readAloud, .voicePreview,
    ]

    /// `active`: the uses running now, other than the asker itself (another memo player playing counts).
    ///
    /// - Something that listens is never stopped for anything: anything asking while it runs is refused,
    ///   a playback included (it would switch the session to playback only and deafen it, ADR-676).
    /// - With nothing listening, whatever plays is stopped for the new use, so one thing plays at a time.
    /// - A conversation asking ignores conversations: the one-conversation gate (ADR-496) decides that,
    ///   and shows the running one instead of refusing.
    public static func claim(_ use: AudioUse, active: Set<AudioUse>) -> AudioClaim {
        let others = use == .conversation ? active.subtracting([.conversation]) : active
        if let listener = precedence.first(where: { others.contains($0) && $0.usesMicrophone }) {
            return .refused(by: listener)
        }
        return .go(stopping: others)
    }

    /// Whether the session may be switched off after a use stopped. `stillActive`: the uses still running
    /// besides the one that stopped, and any whose start is under way.
    public static func mayDeactivate(stillActive: Set<AudioUse>) -> Bool {
        stillActive.isEmpty
    }
}
