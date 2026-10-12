import DoddyCore
import Foundation

/// Builds the payments client from the same development server settings Connected Apps and online
/// accounts use (server address in preferences, session token in the Keychain). Returns nil when
/// either is missing, or the token was issued by another server, so callers say "not set up"
/// instead of pretending.
enum PaymentsClientFactory {
    static func make() -> (any PaymentsClient)? {
        let address = UserDefaults.standard.string(forKey: PreferenceKey.connectedAppsServerURL)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        // The token is used only with the server that issued it (`BoundSessionToken`).
        guard let url = URL(string: address), KeychainSessionStore.read()?.token(for: url) != nil else { return nil }
        return BackendPaymentsClient(
            baseURL: url, boundToken: { KeychainSessionStore.read() }, transport: URLSessionTransport.shared)
    }
}
