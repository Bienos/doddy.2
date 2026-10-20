import AVFAudio
import DoddyCore
import Foundation
import Observation

/// Rehearsal before a call (owner backlog #20/#116, ADR-507): the user practises the call with
/// Doddy playing the person who answers, in Polish. One OpenAI Realtime conversation through the
/// token server, like the main voice, but with no tools at all (`CallRehearsal.toolsJSON`), so it
/// can't call, save or read anything. Nobody is called. The lines shown live only in this
/// object's memory and are gone when the screen closes; OpenAI processes the audio, as in any
/// conversation with the OpenAI voice. Its cost is not tracked on the case (v1).
/// Not compiled or heard on a device yet.
@MainActor
@Observable
final class CallRehearsalSession {
    enum State: Equatable {
        case idle, connecting, live, ended
        case failed(String)
    }

    struct Line: Identifiable, Equatable {
        let id = UUID()
        let fromUser: Bool
        let text: String
    }

    private(set) var state: State = .idle
    private(set) var lines: [Line] = []
    private(set) var doddySpeaking = false

    @ObservationIgnored private var session: OpenAIRealtimeSession?
    /// Bumped on every start and stop, so a start that was stopped while it waited never opens
    /// the microphone.
    @ObservationIgnored private var attempt = 0

    var isRunning: Bool { state == .connecting || state == .live }

    func start(preview: CallPreview) async {
        guard !isRunning else { return }
        guard !VoiceSessionController.conversationInProgress else {
            state = .failed(NSLocalizedString("End the conversation with Doddy first: a rehearsal needs the microphone.", comment: ""))
            return
        }
        guard let endpoint = VoiceConfig.tokenEndpoint else {
            state = .failed(NSLocalizedString("Voice isn't set up yet. Try again later.", comment: ""))
            return
        }
        attempt += 1
        let mine = attempt
        lines = []
        state = .connecting
        guard await Self.microphoneAllowed() else {
            state = .failed(NSLocalizedString("A rehearsal needs the microphone. Turn it on in Settings › Doddy.", comment: ""))
            return
        }
        let sessionUpdate: String
        do {
            let instructions = try CallRehearsal.instructions(from: preview)
            sessionUpdate = try OpenAIRealtimeWire.sessionUpdate(instructions: instructions, toolsJSON: CallRehearsal.toolsJSON, eagerness: .medium)
        } catch {
            state = .failed(NSLocalizedString("The rehearsal couldn't be prepared from this card.", comment: ""))
            return
        }
        let model = OpenAIRealtimeModel(stored: UserDefaults.standard.string(forKey: OpenAIRealtimeModel.preferenceKey))
        let grant: OpenAIRealtimeGrant
        do throws(VoiceTokenError) {
            grant = try await VoiceTokenClient(endpoint: endpoint).fetchOpenAIGrant(model: model)
        } catch {
            if mine == attempt { state = .failed(VoiceTokenServer.message(for: error)) }
            return
        }
        guard mine == attempt, state == .connecting else { return }

        let session = OpenAIRealtimeSession(grant: grant) { [weak self] event in self?.apply(event, attempt: mine) }
        self.session = session
        do {
            try await session.start(sessionUpdate: sessionUpdate, greeting: OpenAIRealtimeWire.greeting(CallRehearsal.greeting(for: preview)))
        } catch {
            if self.session === session { self.session = nil }
            if mine == attempt {
                state = .failed(String(format: NSLocalizedString("Couldn't connect the rehearsal. Check your internet connection and try again. (%@)", comment: ""),
                                       error.localizedDescription))
            }
            return
        }
        guard mine == attempt, isRunning else {
            await session.endConversation()
            if self.session === session { self.session = nil }
            return
        }
    }

    /// Says "koniec próby" for the user, so Doddy steps out of the role and gives tips.
    func askForFeedback() async {
        guard state == .live, let session else { return }
        try? await session.sendMessage("koniec próby")
    }

    func stop() async {
        attempt += 1
        let running = session
        session = nil
        doddySpeaking = false
        if isRunning { state = .ended }
        await running?.endConversation()
    }

    private func apply(_ event: RealtimeEvent, attempt mine: Int) {
        guard mine == attempt else { return }
        switch event {
        case .sessionReady:
            if state == .connecting { state = .live }
        case .audioStarted:
            doddySpeaking = true
        case .responseDone, .userSpeechStarted:
            doddySpeaking = false
        case .userSpeechStopped, .responseStarted, .functionCall:
            // No tools exist in a rehearsal; a call for one is ignored and never answered.
            break
        case .userTranscript(let text):
            lines.append(Line(fromUser: true, text: text))
        case .assistantTranscript(let text):
            lines.append(Line(fromUser: false, text: text))
        case .assistantTranscriptCorrected(let original, let corrected):
            if let index = lines.lastIndex(where: { !$0.fromUser && $0.text == original }) {
                lines[index] = Line(fromUser: false, text: corrected)
            }
        case .error(let message):
            state = .failed(message)
            Task { await stop() }
        case .ended:
            Task { await stop() }
        }
    }

    private static func microphoneAllowed() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        case .undetermined: return await AVAudioApplication.requestRecordPermission()
        @unknown default: return false
        }
    }
}
