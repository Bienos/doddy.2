import AVFoundation
import Observation

/// Reads the morning brief aloud with the iPhone's own speech voice (ADR-230), on the device.
/// It is not Doddy's voice and not a conversation: nothing is sent anywhere and nothing listens.
/// Lives in Features/Voice because audio code is kept here (guard script).
@MainActor
@Observable
final class BriefSpeaker: NSObject, AVSpeechSynthesizerDelegate {
    private(set) var isSpeaking = false
    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Doesn't speak over a voice conversation.
    func speak(_ text: String) {
        guard !VoiceSessionController.conversationInProgress, !text.isEmpty else { return }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        // The brief is written in English.
        utterance.voice = AVSpeechSynthesisVoice(language: "en-GB")
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}
