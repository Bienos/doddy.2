import AVFAudio
import DoddyCore
import Foundation
import LiveKit
import os

/// Who sets up the audio session for a voice conversation (decision
/// `2026-11-12-action-button-audio-and-island`; the rule is `ConversationAudioHolds` in DoddyCore).
///
/// LiveKit, under the ElevenLabs SDK, sets the session up itself when its audio engine starts. Since
/// LiveKit 2.17 its preset doesn't mix with other apps (`.mixWithOthers` was taken out of it), and it
/// switches the session on. iOS refuses that while the app is in the background
/// (`AVAudioSession.ErrorCode.cannotInterruptOthers`), and the engine then doesn't start: the island
/// is up but Doddy can't hear or be heard. That is the Action Button's start without opening Doddy.
/// For that start Doddy takes the session itself, mixable, inside the intent
/// (`VoiceSessionController.takeAudioSessionWithoutOpening`), and LiveKit's automatic set-up is off
/// until the conversation is over. Every other start leaves the session to LiveKit, as before.
///
/// `AudioManager.sessionConfiguration`, which `VoiceSessionController.allowOtherAppsAudio` sets, is
/// not read by LiveKit 2.19's set-up at all, so it can't do this.
@MainActor
enum ConversationAudioSession {
    private static var holds = ConversationAudioHolds()
    private static let log = Logger(subsystem: "com.bienos.doddy2.dev", category: "voice-audio")
    /// `RTCAudioSessionHighPerformanceIOBufferDuration`, which LiveKit's own set-up asks for.
    private static let webRTCBufferDuration: TimeInterval = 0.02

    /// Doddy has just taken the session itself, mixable, for a start without opening the app. LiveKit
    /// leaves it as it is until `release`.
    static func takenByDoddy() -> ConversationAudioHolds.Hold {
        let hold = holds.take()
        AudioManager.shared.audioSession.isAutomaticConfigurationEnabled = false
        // The one other thing LiveKit's set-up does: ask for WebRTC's 20 ms IO buffer. Only a hint.
        try? AVAudioSession.sharedInstance().setPreferredIOBufferDuration(Self.webRTCBufferDuration)
        log.notice("audio session held by Doddy for this conversation: LiveKit won't set it up")
        return hold
    }

    /// Right before the connect, so before LiveKit's engine starts. Without a hold in force LiveKit
    /// sets the session up itself, as it always did.
    static func beforeConnect(_ hold: ConversationAudioHolds.Hold?) {
        let liveKit = holds.liveKitSetsUpSession(for: hold)
        AudioManager.shared.audioSession.isAutomaticConfigurationEnabled = liveKit
    }

    /// The conversation that took `hold` is over and its SDK conversation has ended. LiveKit gets the
    /// session back. Doddy switches the session off unless LiveKit's engine still runs (LiveKit then
    /// switches it off itself when the engine stops) or something else of Doddy's uses it
    /// (`AudioSessionOwner`). A hold that a newer conversation replaced changes nothing.
    static func release(_ hold: ConversationAudioHolds.Hold?) {
        guard holds.release(hold) else { return }
        let audio = AudioManager.shared
        audio.audioSession.isAutomaticConfigurationEnabled = true
        guard !audio.isEngineRunning else {
            log.notice("audio session given back to LiveKit while its engine still runs")
            return
        }
        let off = AudioSessionOwner.shared.release(.conversation)
        log.notice("audio session given back to LiveKit, switched off: \(off, privacy: .public)")
    }
}
