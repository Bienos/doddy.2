import Foundation

/// The live servers' addresses (docs/implementation/GO_LIVE_RUNBOOK_2026-10-13.md), built in so a
/// tester types only their codes. Registered as UserDefaults defaults, so every `@AppStorage` and
/// `UserDefaults` read of these keys sees them without other changes. A debug build can still
/// point Settings at another server; a shipped build always uses these, because the fields are
/// hidden there and any address saved by an earlier build is dropped at launch.
///
/// Voice has no built-in token server: owner, 2026-10-13, "public agent, no code". Talk to Doddy
/// uses the development agent directly, with no access code. `server/voice-token` stays deployed
/// (`doddy-voice-token` on Render) for when ElevenLabs authentication is turned on: then add it
/// back here and hide nothing else.
enum ServiceAddresses {
    /// `gateway/` on Render (`doddy-gateway`): Ask Doddy.
    static let gateway = "https://doddy-gateway.onrender.com"
    /// `backend/` on Render (`doddy`): web search and online accounts.
    static let connectedApps = "https://doddy-yaci.onrender.com"
    /// `server/messaging` on Render (`doddy-messaging`): read through `ServerConfig`.
    static let messaging = "https://doddy-messaging-zw1n.onrender.com"

    static func register(_ defaults: UserDefaults = .standard) {
        let builtIn = [
            PreferenceKey.gatewayAddress: gateway,
            PreferenceKey.connectedAppsServerURL: connectedApps,
        ]
        #if !DEBUG
        // An earlier build may have saved a token server: voice uses the development agent now.
        for key in Array(builtIn.keys) + [PreferenceKey.voiceTokenServer, PreferenceKey.voiceAgentID] {
            defaults.removeObject(forKey: key)
        }
        #endif
        defaults.register(defaults: builtIn)
    }
}
