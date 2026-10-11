import ElevenLabs
import LiveKit

/// What `VoiceSessionController` needs from a live conversation, whichever provider runs it
/// (ADR-235). The names are the ElevenLabs SDK's own, so its `Conversation` conforms with two
/// small shims and the ElevenLabs path is unchanged; `OpenAIRealtimeSession` is the other one.
@MainActor
protocol LiveVoiceLink: AnyObject {
    func sendToolResult(for toolCallId: String, result: String, isError: Bool) async throws
    func setMuted(_ muted: Bool) async throws
    /// A message Doddy answers now.
    func sendMessage(_ text: String) async throws
    /// Background context; Doddy doesn't answer it on its own.
    func updateContext(_ context: String) async throws
    func endConversation() async
    /// Doddy's playback volume on this iPhone only (0 = silent; the provider still makes the
    /// audio). Returns the volume now in effect, or nil when there is no voice to set yet.
    func setAgentVolume(_ volume: Double) -> Double?
}

extension Conversation: LiveVoiceLink {
    func sendToolResult(for toolCallId: String, result: String, isError: Bool) async throws {
        // The SDK's String overload, sent verbatim.
        try await sendToolResult(for: toolCallId, result: result, isError: isError, errorType: nil)
    }

    /// LiveKit's local volume for the agent's track (ADR-215 Listen only).
    func setAgentVolume(_ volume: Double) -> Double? {
        guard let track = agentAudioTrack else { return nil }
        track.volume = volume
        return track.volume
    }
}
