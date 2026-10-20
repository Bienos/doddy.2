import DoddyCore

/// Whether talking to Doddy needs a DODDY voice account made with Sign in with Apple (ADR-549).
///
/// **It is off for now (`false`)**, because Sign in with Apple isn't set up yet and the app runs
/// only on the owner's own iPhone. While it is off, every build skips the sign-in and the token
/// server and connects straight to the live ElevenLabs agent, which has authentication off. The
/// consent screen for ElevenLabs stays. OpenAI's voice needs a DODDY session, so ElevenLabs is the
/// only voice meanwhile.
///
/// **Set it to `true` before any TestFlight or App Store build**, and turn the agent's
/// authentication on (docs/implementation/GO_LIVE_CHECKLIST.md, A4b). With `true` the app is
/// exactly what ADR-522 describes: Sign in with Apple, a DODDY session, no public agent.
enum VoiceAccess {
    static let requiresAppleSignIn = false

    /// The live ElevenLabs agent (STATUS.md). An identifier, not a credential: the agent has
    /// authentication off, so anyone who has this ID can already connect to it.
    static let directAgentID = "agent_0501m4et27vyeawrwqfdxxfszfa6"

    /// The voice provider a conversation uses: ElevenLabs while sign-in is off, otherwise the
    /// user's choice or the default (ADR-442).
    static func provider(stored: String?, tokenServerSet: Bool) -> VoiceProvider {
        if !requiresAppleSignIn { return .elevenLabs }
        return VoiceProvider.effective(stored: stored, tokenServerSet: tokenServerSet)
    }
}
