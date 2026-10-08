import Foundation

/// Where the anonymous gateway device token lives. Production should use the Keychain
/// (an app-side adapter, not yet written); the token is a bearer credential.
public protocol DeviceTokenStore: Sendable {
    func token() async -> String?
    func save(_ token: String) async throws
    func clear() async
}

public actor InMemoryDeviceTokenStore: DeviceTokenStore {
    private var stored: String?

    public init(token: String? = nil) { stored = token }

    public func token() async -> String? { stored }
    public func save(_ token: String) async throws { stored = token }
    public func clear() async { stored = nil }
}
