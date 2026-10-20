#if DEBUG
import os

/// Debug builds only (Xcode ▶ Run). While Sign in with Apple isn't set up, this lets the owner talk
/// to Doddy on ElevenLabs without a DODDY voice account (ADR-548). None of it is compiled into a
/// Release, TestFlight or App Store build, which keep ADR-522 exactly: Sign in with Apple, a DODDY
/// session, no public agent.
///
/// The switch lives in memory only. Every launch starts with it off, so a fresh run shows the
/// sign-in screen until "Talk without signing in" is tapped there. Tapping it is also the consent
/// to send voice to ElevenLabs.
enum DebugVoiceTesting {
    private static let state = OSAllocatedUnfairLock(initialState: false)

    static var isOn: Bool { state.withLock { $0 } }
    static func turnOn() { state.withLock { $0 = true } }

    /// The live ElevenLabs agent (STATUS.md). An identifier, not a credential: the agent has
    /// authentication off, so anyone with this ID can already connect to it.
    static let agentID = "agent_0501m4et27vyeawrwqfdxxfszfa6"
}
#endif
