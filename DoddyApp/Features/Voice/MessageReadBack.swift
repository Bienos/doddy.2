import AVFoundation
import Foundation

/// Reads the app's exact, local message draft aloud. It does not send draft text to another
/// provider, and its completion is the only signal that the spoken review has finished.
@MainActor
final class MessageReadBack: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var completion: ((Bool) -> Void)?
    private var activeUtteranceID: ObjectIdentifier?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(recipient: String, body: String, prompt: String, language: String, completion: @escaping (Bool) -> Void) {
        stop()
        self.completion = completion
        let recipientLine = String(format: NSLocalizedString("Message for %@.", comment: "Recipient in spoken message review"), recipient)
        let utterance = AVSpeechUtterance(string: "\(recipientLine) \(body). \(prompt)")
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        activeUtteranceID = ObjectIdentifier(utterance)
        synthesizer.speak(utterance)
    }

    func stop() {
        completion = nil
        activeUtteranceID = nil
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.finish(success: true, utteranceID: utteranceID) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.finish(success: false, utteranceID: utteranceID) }
    }

    private func finish(success: Bool, utteranceID: ObjectIdentifier) {
        guard activeUtteranceID == utteranceID else { return }
        let callback = completion
        completion = nil
        activeUtteranceID = nil
        callback?(success)
    }
}
