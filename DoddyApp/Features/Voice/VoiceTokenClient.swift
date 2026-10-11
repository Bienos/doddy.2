import DoddyCore
import Foundation
import Security

/// Fetches a one-conversation token from Doddy's token server. This is the app's only
/// network request of its own: it sends the access code, nothing about the user or their notes.
/// For the OpenAI test voice (ADR-264) the body also names the provider.
struct VoiceTokenClient: Sendable {
    let endpoint: URL
    let accessCode: String

    /// ElevenLabs conversation token. Sends no body, exactly as before ADR-264.
    func fetchToken() async throws(VoiceTokenError) -> String {
        let (status, data) = try await post(VoiceTokenServer.requestBody(for: .elevenLabs))
        return try VoiceTokenServer.token(status: status, body: data).get()
    }

    /// OpenAI Realtime client secret (testing only).
    func fetchOpenAIGrant() async throws(VoiceTokenError) -> OpenAIRealtimeGrant {
        let (status, data) = try await post(VoiceTokenServer.requestBody(for: .openAIRealtime))
        return try VoiceTokenServer.openAIGrant(status: status, body: data).get()
    }

    private func post(_ body: Data?) async throws(VoiceTokenError) -> (Int, Data) {
        var request = URLRequest(url: endpoint, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessCode)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        } catch {
            throw .offline
        }
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
    }
}

/// The tester's access code, kept in the Keychain on this device only (not in backups).
enum VoiceAccessCodeStore {
    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.bienos.doddy2.voice-access-code",
            kSecAttrAccount as String: "default",
        ]
    }

    static func read() -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Returns false if the Keychain refused the write; the UI then says it wasn't saved.
    static func save(_ code: String) -> Bool {
        delete()
        var item = query
        item[kSecValueData as String] = Data(code.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}
