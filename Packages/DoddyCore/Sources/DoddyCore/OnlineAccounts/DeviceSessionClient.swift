import Foundation

/// ADR-562: the phone signs itself in to Doddy's server with its device ID, instead of a token
/// pasted into Settings. The app keeps the device ID and the token in the Keychain; this is only the
/// one HTTP call, kept here so it is tested on Linux.
public enum DeviceSessionClient {
    public struct Token: Equatable, Sendable {
        public let token: String
        public let expiresAt: Date?
    }

    private struct Body: Encodable {
        let deviceId: String
        let inviteCode: String?
    }

    private struct Reply: Decodable {
        let token: String
        let expiresAt: String
    }

    /// `POST {server}/v1/session/device`. Nil when the server refuses (another iPhone owns it, a bad
    /// invite code) or can't be reached; the caller then says "not set up" as before.
    public static func signIn(
        server: URL, deviceID: String, inviteCode: String?, transport: any HTTPTransport
    ) async -> Token? {
        let code = inviteCode?.trimmingCharacters(in: .whitespaces)
        guard UUID(uuidString: deviceID) != nil,
              let data = try? JSONEncoder().encode(Body(deviceId: deviceID.lowercased(), inviteCode: (code?.isEmpty ?? true) ? nil : code))
        else { return nil }
        let request = HTTPRequest(
            method: "POST", url: server.appendingPathComponent("v1/session/device"),
            headers: ["content-type": "application/json", "accept": "application/json"], body: data)
        guard let response = try? await transport.send(request), response.status == 200,
              let decoded = try? JSONDecoder().decode(Reply.self, from: response.body),
              decoded.token.hasPrefix("ds1."), decoded.token.count <= 2048
        else { return nil }
        return Token(token: decoded.token, expiresAt: parseDate(decoded.expiresAt))
    }

    static func parseDate(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}
