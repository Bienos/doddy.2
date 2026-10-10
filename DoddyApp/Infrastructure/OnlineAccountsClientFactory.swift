import DoddyCore
import Foundation

/// Builds the online-accounts client from the same development server settings Connected Apps
/// uses (server address in preferences, session token in the Keychain). Returns nil when either
/// is missing, so callers say "not set up" instead of pretending.
enum OnlineAccountsClientFactory {
    static func make() -> (any OnlineAccountsClient)? {
        let address = UserDefaults.standard.string(forKey: PreferenceKey.connectedAppsServerURL)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        guard let url = URL(string: address), KeychainSessionStore.read() != nil else { return nil }
        return BackendOnlineAccountsClient(
            baseURL: url, sessionToken: { KeychainSessionStore.read() }, transport: URLSessionTransport.shared)
    }
}
