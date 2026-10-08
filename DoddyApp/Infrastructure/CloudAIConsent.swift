import Foundation

/// Consent to send questions to the cloud assistant. Stored as the notice version the user
/// accepted, so changing the notice text later (bump `noticeVersion`) asks again.
enum CloudAIConsent {
    static let noticeVersion = 1
    static let storageKey = "cloudAIConsentVersion"

    static func isGranted(_ storedVersion: Int) -> Bool { storedVersion == noticeVersion }
}

/// Public address of Doddy's gateway (see gateway/README.md). Not a secret; the OpenAI key lives
/// only on the server.
enum GatewayEndpoint {
    static let baseURL = URL(string: "https://sliondswemhneuzehpoq.supabase.co/functions/v1/assistant")!
}
