import AVFAudio
import DoddyCore
import Foundation
import os

/// The one owner of Doddy's audio session (ADR-695). iOS gives the app one audio session; a voice
/// conversation, a call rehearsal, a Capture recording, a voice memo, Messages dictation and every
/// player share it. Each of them asks here before it sets the session up (`claim`), and lets go here
/// when it is done (`release`), which switches the session off only when nothing else of Doddy's
/// still uses it. Before, each checked only some of the others and switched the session off when it
/// stopped, so dictation, a voice sample or a note read aloud could leave a conversation deaf while
/// Home still said "Listening". The rule itself is `AudioSessionPolicy` in DoddyCore.
///
/// Who is using it is read from each one's own state when asked (the same way Stop listening reads
/// the microphone, ADR-361), so a part that forgets to say it stopped can't keep the session held.
@MainActor
final class AudioSessionOwner {
    static let shared = AudioSessionOwner(watchesConversationAndCapture: true)

    private static let log = Logger(subsystem: "com.bienos.doddy2.dev", category: "voice-audio")

    private struct Entry {
        let use: AudioUse
        /// The registered object, or nil for a use read from shared state (the conversation, Capture).
        let id: ObjectIdentifier?
        let isAlive: @MainActor () -> Bool
        let isUsing: @MainActor () -> Bool
        /// Stops it for something that listens or another player. Nil for a use that is never stopped.
        let stop: (@MainActor () -> Void)?
    }

    private var entries: [Entry] = []
    /// Uses whose claim is being granted: counted as running while what plays is stopped for them.
    private var claiming: Set<AudioUse> = []

    /// `watchesConversationAndCapture`: false only in tests, which register fakes instead.
    init(watchesConversationAndCapture: Bool) {
        guard watchesConversationAndCapture else { return }
        // Starting counts too: from the first moment of a start until it ends (ADR-496's gate).
        entries.append(Entry(use: .conversation, id: nil, isAlive: { true },
                             isUsing: { VoiceSessionController.runningConversation != nil || VoiceSessionController.conversationInProgress },
                             stop: nil))
        entries.append(Entry(use: .captureRecording, id: nil, isAlive: { true },
                             isUsing: { RecordingCoordinator.shared.isActive }, stop: nil))
    }

    /// Registers a part of Doddy that uses the session. It is held weakly and dropped once it is gone.
    /// `stop` is called when something that listens, or another player, takes the session from it;
    /// only parts that play are ever stopped.
    func register<Holder: AnyObject>(_ holder: Holder, as use: AudioUse,
                                     isUsing: @escaping @MainActor (Holder) -> Bool,
                                     stop: (@MainActor (Holder) -> Void)? = nil) {
        let box = WeakHolder(holder)
        let id = ObjectIdentifier(holder)
        let alive: @MainActor () -> Bool = { box.value != nil }
        let using: @MainActor () -> Bool = {
            guard let holder = box.value else { return false }
            return isUsing(holder)
        }
        var stopper: (@MainActor () -> Void)?
        if let stop {
            stopper = {
                guard let holder = box.value else { return }
                stop(holder)
            }
        }
        entries.removeAll { $0.id == id }
        entries.append(Entry(use: use, id: id, isAlive: alive, isUsing: using, stop: stopper))
    }

    /// Asks for the session before setting it up. `.go` once whatever only plays has been stopped;
    /// `.refused(by:)` names what has the microphone, for the caller to say in its own words.
    /// `holder`: the asker itself, so it is not counted against itself.
    func claim(_ use: AudioUse, by holder: AnyObject? = nil) -> AudioClaim {
        let others = running(except: holder)
        let decision = AudioSessionPolicy.claim(use, active: Set(others.map(\.use)))
        switch decision {
        case .refused(let by):
            Self.log.notice("audio session refused to \(use.rawValue, privacy: .public): \(by.rawValue, privacy: .public) has it")
        case .go(let stopping):
            guard !stopping.isEmpty else { break }
            Self.log.notice("audio session for \(use.rawValue, privacy: .public): stopping \(stopping.map(\.rawValue).sorted(), privacy: .public)")
            claiming.insert(use)
            defer { claiming.remove(use) }
            for entry in others where stopping.contains(entry.use) { entry.stop?() }
        }
        return decision
    }

    /// Called by a part when it stopped using the session. Switches the session off only when nothing
    /// else of Doddy's uses it (a conversation, a recording or a start under way); true when it did.
    @discardableResult
    func release(_ use: AudioUse, by holder: AnyObject? = nil) -> Bool {
        let still = Set(running(except: holder).map(\.use)).union(claiming.subtracting([use]))
        guard AudioSessionPolicy.mayDeactivate(stillActive: still) else {
            Self.log.notice("audio session kept on after \(use.rawValue, privacy: .public): \(still.map(\.rawValue).sorted(), privacy: .public) still uses it")
            return false
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return true
    }

    /// Whether something that listens is running now.
    var microphoneInUse: Bool { running(except: nil).contains { $0.use.usesMicrophone } }

    private func running(except holder: AnyObject?) -> [Entry] {
        entries.removeAll { !$0.isAlive() }
        let excluded = holder.map { ObjectIdentifier($0) }
        return entries.filter { ($0.id == nil || $0.id != excluded) && $0.isUsing() }
    }
}

private final class WeakHolder<Holder: AnyObject> {
    weak var value: Holder?
    init(_ value: Holder) { self.value = value }
}

/// What starting a conversation or a call rehearsal says when something else listens (ADR-695).
enum AudioTalkRefusal {
    static func message(by holder: AudioUse) -> String {
        switch holder {
        case .conversation:
            NSLocalizedString("End the conversation with Doddy first: a rehearsal needs the microphone.", comment: "")
        case .captureRecording:
            NSLocalizedString("Doddy is recording. Stop the recording to talk to him.", comment: "")
        case .memoRecording:
            NSLocalizedString("A voice memo is recording. Stop it to talk to Doddy.", comment: "")
        case .dictation:
            NSLocalizedString("You're dictating in Messages. Stop dictating to talk to Doddy.", comment: "")
        case .callRehearsal:
            NSLocalizedString("A call rehearsal has the microphone. End it to talk to Doddy.", comment: "")
        case .memoPlayback, .recordingPlayback, .readAloud, .voicePreview:
            // Never the answer: what only plays is stopped instead.
            NSLocalizedString("Something else in Doddy has the microphone. Finish it to talk to him.", comment: "")
        }
    }
}

/// What a player says when something that listens has the audio session (ADR-676, ADR-695).
enum AudioPlaybackRefusal {
    static func message(by holder: AudioUse) -> String {
        switch holder {
        case .captureRecording, .memoRecording:
            NSLocalizedString("Stop recording to play this.", comment: "")
        case .dictation:
            NSLocalizedString("Stop dictating to play this.", comment: "")
        case .conversation, .callRehearsal, .memoPlayback, .recordingPlayback, .readAloud, .voicePreview:
            // Players never refuse each other; a rehearsal is a conversation too.
            NSLocalizedString("This plays after your conversation with Doddy ends.", comment: "")
        }
    }
}
