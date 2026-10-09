/// Voice configuration for the development prototype.
enum VoiceConfig {
    /// Public ElevenLabs agent "Doddy (dev prototype)". An agent ID is not a secret key, but a
    /// public agent can be used by anyone who has the ID and spends the owner's minutes.
    /// Before anyone else installs the app, deploy `server/voice-token`, set it in Settings → Voice,
    /// then switch the agent to authenticated mode (docs/implementation/VOICE_TOKEN_SERVER_STATUS.md).
    static let developmentAgentID = "agent_0501m4et27vyeawrwqfdxxfszfa6"
}
