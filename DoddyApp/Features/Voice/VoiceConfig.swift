/// Voice configuration for the development prototype.
enum VoiceConfig {
    /// Public ElevenLabs agent "Doddy (dev prototype)". An agent ID is not a secret key, but a
    /// public agent can be used by anyone who has the ID and spends the owner's minutes.
    /// Before anyone else installs the app, switch the agent to authenticated mode and fetch a
    /// conversation token from a server instead (see docs/implementation/V1_VOICE_STATUS.md).
    static let developmentAgentID = "agent_0501m4et27vyeawrwqfdxxfszfa6"
}
