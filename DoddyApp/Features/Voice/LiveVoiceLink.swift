import ElevenLabs
import LiveKit

/// What `VoiceSessionController` needs from a live conversation, whichever provider runs it
/// (ADR-265). The names are the ElevenLabs SDK's own, so its `Conversation` conforms with two
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
    /// Starts reading the loudness of Doddy's voice into `meter`, for Home's island extension
    /// (ADR-655). True when there was a voice to listen to; false from a provider that doesn't
    /// give one, and the extension falls back to a clock-made rhythm.
    func attachAgentLevelMeter(_ meter: AgentVoiceMeter) -> Bool
    func detachAgentLevelMeter(_ meter: AgentVoiceMeter)
}

extension LiveVoiceLink {
    func attachAgentLevelMeter(_ meter: AgentVoiceMeter) -> Bool { false }
    func detachAgentLevelMeter(_ meter: AgentVoiceMeter) {}
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

    /// The agent's audio track, for its loudness only (ADR-655).
    func attachAgentLevelMeter(_ meter: AgentVoiceMeter) -> Bool {
        guard let track = agentAudioTrack else { return false }
        track.add(audioRenderer: meter)
        return true
    }

    func detachAgentLevelMeter(_ meter: AgentVoiceMeter) {
        agentAudioTrack?.remove(audioRenderer: meter)
    }
}
