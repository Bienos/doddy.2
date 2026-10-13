import Foundation

/// The live servers' addresses (docs/implementation/GO_LIVE_RUNBOOK_2026-10-13.md), built in so a
/// tester types only their codes. Registered as UserDefaults defaults, so every `@AppStorage` and
/// `UserDefaults` read of these keys sees them without other changes. A debug build can still
/// point Settings at another server; a shipped build always uses these, because the fields are
/// hidden there and any address saved by an earlier build is dropped at launch.
///
/// Voice goes through the token server (`doddy-voice-token` on Render), so OpenAI Realtime is the
/// default voice (ADR-442) and the OpenAI key stays on the server. The owner picked this on
/// 2026-10-13 over "public agent, no code": a tester types one access code in Settings, Voice, and
/// the token server and agent ID fields stay hidden in shipped builds. Without a code the voice
/// screen says to add one. Home's switch can still pick ElevenLabs, which then also gets its
/// token from this server.
enum ServiceAddresses {
    /// `server/voice-token` on Render (`doddy-voice-token`): voice passes for both providers.
    static let voiceTokenServer = "https://doddy-voice-token.onrender.com"
    /// `gateway/` on Render (`doddy-gateway`): Ask Doddy.
    static let gateway = "https://doddy-gateway.onrender.com"
    /// `backend/` on Render (`doddy`): web search and online accounts.
    static let connectedApps = "https://doddy-yaci.onrender.com"
    /// `server/messaging` on Render (`doddy-messaging`): read through `ServerConfig`.
    static let messaging = "https://doddy-messaging-zw1n.onrender.com"

    static func register(_ defaults: UserDefaults = .standard) {
        let builtIn = [
            PreferenceKey.voiceTokenServer: voiceTokenServer,
            PreferenceKey.gatewayAddress: gateway,
            PreferenceKey.connectedAppsServerURL: connectedApps,
        ]
        #if !DEBUG
        // An address or agent ID saved by an earlier build (or typed in a debug build) must not
        // redirect a shipped build: the built-in servers always win.
        for key in Array(builtIn.keys) + [PreferenceKey.voiceAgentID] {
            defaults.removeObject(forKey: key)
        }
        #endif
        defaults.register(defaults: builtIn)
    }
}
