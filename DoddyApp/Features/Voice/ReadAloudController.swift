import AVFAudio
import DoddyCore
import NaturalLanguage
import Observation
import SwiftUI

/// Reads one saved note aloud with iOS's built-in voice, on this iPhone only (ADR-243). Nothing
/// is sent anywhere. While it reads, the island shows the owner's Story Spool board ("Reading
/// aloud", "Your note"), never the note's words. It keeps reading when you leave the app (the
/// app already has background audio for conversations) and never starts during a conversation.
@MainActor
@Observable
final class ReadAloudController: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = ReadAloudController()

    enum Status: Equatable {
        case idle
        case reading(UUID)
        case paused(UUID)
    }

    private(set) var status: Status = .idle
    /// Why it couldn't start, for the button's caption.
    private(set) var problem: String?

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private let island = ToolLiveActivity(kind: .readAloud)
    @ObservationIgnored private var startedAt = Date()
    /// The utterance being read. A stopped one's late didCancel (note A, after note B started)
    /// must not end B's state (review H6). Kept strongly, so its identity can't be reused meanwhile.
    @ObservationIgnored private var current: AVSpeechUtterance?
    /// How long "Finished reading" stays on the Lock Screen.
    private static let doneCardFor: TimeInterval = 30

    override init() {
        super.init()
        synthesizer.delegate = self
        ToolActivityActions.shared.togglePause[.readAloud] = { [weak self] in self?.togglePause() }
        ToolActivityActions.shared.stop[.readAloud] = { [weak self] in self?.stop() }
    }

    func isActive(for id: UUID) -> Bool {
        switch status {
        case .reading(let current), .paused(let current): current == id
        case .idle: false
        }
    }

    func read(_ record: MemoryRecord) {
        problem = nil
        guard !VoiceSessionController.conversationInProgress else {
            problem = "Doddy is in a conversation. Read it aloud after it ends."
            return
        }
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            problem = "iOS didn't let Doddy play sound just now."
            return
        }
        let utterance = AVSpeechUtterance(string: record.currentText)
        utterance.voice = Self.voice(for: record.currentText)
        startedAt = Date()
        status = .reading(record.id)
        current = utterance
        synthesizer.speak(utterance)
        island.show(.init(isPaused: false), startedAt: startedAt, duration: 0)
    }

    func togglePause() {
        switch status {
        case .reading(let id):
            if synthesizer.pauseSpeaking(at: .word) {
                status = .paused(id)
                island.show(.init(isPaused: true), startedAt: startedAt, duration: 0)
            }
        case .paused(let id):
            if synthesizer.continueSpeaking() {
                status = .reading(id)
                island.show(.init(isPaused: false), startedAt: startedAt, duration: 0)
            }
        case .idle:
            break
        }
    }

    func stop() {
        guard status != .idle else {
            island.end(final: nil)
            return
        }
        synthesizer.stopSpeaking(at: .immediate)
        // didCancel finishes the clean-up.
    }

    private func ended(finished: Bool, utterance: ObjectIdentifier) {
        guard status != .idle, let current, ObjectIdentifier(current) == utterance else { return }
        self.current = nil
        status = .idle
        if finished {
            island.end(final: .init(isPaused: false, isFinished: true), keepFor: Self.doneCardFor)
        } else {
            island.end(final: nil)
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// The installed voice for the note's language (on-device language guess), else the
    /// phone's default.
    private static func voice(for text: String) -> AVSpeechSynthesisVoice? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        if let language = recognizer.dominantLanguage, let voice = AVSpeechSynthesisVoice(language: language.rawValue) {
            return voice
        }
        return AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
    }

    // MARK: AVSpeechSynthesizerDelegate (called off the main actor)

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.ended(finished: true, utterance: id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.ended(finished: false, utterance: id) }
    }
}

/// "Read aloud" on a note's page, with Pause and Stop while it reads.
struct ReadAloudButton: View {
    let record: MemoryRecord
    private var reader: ReadAloudController { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if reader.isActive(for: record.id) {
                HStack(spacing: 10) {
                    Button { reader.togglePause() } label: {
                        let paused = reader.status == .paused(record.id)
                        HStack { Text(paused ? "Resume" : "Pause"); Spacer(); Image(systemName: paused ? "play.fill" : "pause.fill") }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("detail.readAloud.pause")
                    Button { reader.stop() } label: {
                        HStack { Text("Stop"); Spacer(); Image(systemName: "stop.fill") }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("detail.readAloud.stop")
                }
            } else {
                Button { reader.read(record) } label: {
                    HStack { Text("Read aloud"); Spacer(); Image(systemName: "speaker.wave.2") }
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("detail.readAloud")
            }
            if let problem = reader.problem {
                Text(problem).font(.footnote).foregroundStyle(Theme.secondaryText)
            } else {
                Text("Read by your iPhone's own voice. Nothing is sent anywhere.")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            }
        }
    }
}
