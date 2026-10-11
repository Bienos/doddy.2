import AVFAudio

/// Whether iOS refuses Doddy the microphone right now. Read by the opening (ADR-225) so a
/// conversation never opens by itself straight into "Microphone is off". A conversation that
/// does start still asks iOS itself (`VoiceSessionController.microphoneAllowed`).
@MainActor
enum MicrophoneAccess {
    static var isDenied: Bool { AVAudioApplication.shared.recordPermission == .denied }
    /// Allowed already; not yet asked is not allowed (ADR-320).
    static var isAllowed: Bool { AVAudioApplication.shared.recordPermission == .granted }
}
