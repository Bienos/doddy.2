/// Voice configuration for the development prototype.
enum VoiceConfig {
    /// Public ElevenLabs agent "Doddy (dev prototype)". An agent ID is not a secret key, but a
    /// public agent can be used by anyone who has the ID and spends the owner's minutes.
    /// Used only by debug builds with no Doddy server connected (VoiceAuthPolicy). With a server,
    /// the app fetches a short-lived token from `/v1/voice/token`. Before anyone else installs
    /// the app, turn on authentication for this agent in ElevenLabs so the ID alone stops working.
    static let developmentAgentID = "agent_0501m4et27vyeawrwqfdxxfszfa6"
}
