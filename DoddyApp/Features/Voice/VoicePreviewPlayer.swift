import AVFAudio
import DoddyCore
import Foundation
import Observation

/// Plays the bundled hello for a voice so the user can hear it before choosing (ADR-122).
/// The clips were recorded once with ElevenLabs and ship inside the app: no network and no
/// cost per play. Speed is applied as the playback rate; expressiveness can't be applied to a
/// recording, so it is only heard in a conversation.
@MainActor
@Observable
final class VoicePreviewPlayer {
    private(set) var playing: VoiceChoice?
    private(set) var problem: String?

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var delegate: FinishDelegate?

    /// Plays `style`'s sample, or stops it if that voice is already playing.
    func toggle(_ style: VoiceStyle) {
        if playing == style.voice {
            stop()
        } else {
            play(style)
        }
    }

    func play(_ style: VoiceStyle) {
        stop()
        problem = nil
        guard !VoiceSessionController.conversationInProgress else {
            problem = NSLocalizedString("Samples don't play while you're talking to Doddy.", comment: "")
            return
        }
        guard let url = Bundle.main.url(forResource: style.voice.previewResourceName, withExtension: "mp3") else {
            problem = NSLocalizedString("This sample is missing from the app.", comment: "")
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.enableRate = true
            player.rate = Float(style.previewRate)
            let ref = WeakPlayer(self)
            let delegate = FinishDelegate { Task { @MainActor in ref.value?.finished() } }
            player.delegate = delegate
            guard player.play() else {
                problem = NSLocalizedString("Couldn't play the sample.", comment: "")
                deactivateSession()
                return
            }
            self.player = player
            self.delegate = delegate
            playing = style.voice
        } catch {
            problem = NSLocalizedString("Couldn't play the sample.", comment: "")
            deactivateSession()
        }
    }

    func stop() {
        player?.stop()
        player = nil
        delegate = nil
        if playing != nil {
            playing = nil
            deactivateSession()
        }
    }

    private func finished() {
        player = nil
        delegate = nil
        playing = nil
        deactivateSession()
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

private final class FinishDelegate: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    private let onFinish: @Sendable () -> Void
    init(onFinish: @escaping @Sendable () -> Void) { self.onFinish = onFinish }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { onFinish() }
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) { onFinish() }
}

private final class WeakPlayer: @unchecked Sendable {
    weak var value: VoicePreviewPlayer?
    init(_ value: VoicePreviewPlayer) { self.value = value }
}
