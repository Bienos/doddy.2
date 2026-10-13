import Foundation

/// The live servers' addresses (docs/implementation/GO_LIVE_RUNBOOK_2026-10-13.md), built in so a
/// tester types only their codes. Registered as UserDefaults defaults, so every `@AppStorage` and
/// `UserDefaults` read of these keys sees them without other changes. A debug build can still
/// point Settings at another server; a shipped build always uses these, because the fields are
/// hidden there and any address saved by an earlier build is dropped at launch.
enum ServiceAddresses {
    /// `server/voice-token` on Render (`doddy-voice-token`).
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
        for key in builtIn.keys { defaults.removeObject(forKey: key) }
        #endif
        defaults.register(defaults: builtIn)
    }
}
