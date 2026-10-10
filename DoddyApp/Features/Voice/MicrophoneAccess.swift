import AVFAudio

/// Whether iOS refuses Doddy the microphone right now. Read by the opening (ADR-207) so a
/// conversation never opens by itself straight into "Microphone is off". A conversation that
/// does start still asks iOS itself (`VoiceSessionController.microphoneAllowed`).
@MainActor
enum MicrophoneAccess {
    static var isDenied: Bool { AVAudioApplication.shared.recordPermission == .denied }
}
