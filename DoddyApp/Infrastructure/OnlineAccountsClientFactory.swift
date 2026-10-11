import DoddyCore
import Foundation

/// Builds the online-accounts client from the same development server settings Connected Apps
/// uses (server address in preferences, session token in the Keychain). Returns nil when either
/// is missing, or the token was issued by another server, so callers say "not set up" instead of pretending.
enum OnlineAccountsClientFactory {
    static func make() -> (any OnlineAccountsClient)? {
        let address = UserDefaults.standard.string(forKey: PreferenceKey.connectedAppsServerURL)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        // The token is used only with the server that issued it (`BoundSessionToken`).
        guard let url = URL(string: address), KeychainSessionStore.read()?.token(for: url) != nil else { return nil }
        return BackendOnlineAccountsClient(
            baseURL: url, boundToken: { KeychainSessionStore.read() }, transport: URLSessionTransport.shared)
    }
}
