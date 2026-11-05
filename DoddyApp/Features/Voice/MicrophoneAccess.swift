import AVFAudio

/// Whether iOS refuses Doddy the microphone right now. Read by the opening (ADR-225) so a
/// conversation never opens by itself straight into "Microphone is off". A conversation that
/// does start still asks iOS itself (`VoiceSessionController.microphoneAllowed`).
@MainActor
enum MicrophoneAccess {
    static var isDenied: Bool { AVAudioApplication.shared.recordPermission == .denied }
    /// Allowed already; not yet asked is not allowed (ADR-325).
    static var isAllowed: Bool { AVAudioApplication.shared.recordPermission == .granted }
}

extension MicrophoneAccess {
    /// The first-run "Allow access" step (ADR-728): shows iOS's question only if it was never answered
    /// and returns whether the microphone is allowed afterwards. Here, not in the step, because audio
    /// code may only live under Features/Voice.
    static func request() async -> Bool {
        if AVAudioApplication.shared.recordPermission == .undetermined {
            _ = await AVAudioApplication.requestRecordPermission()
        }
        return isAllowed
    }
}
