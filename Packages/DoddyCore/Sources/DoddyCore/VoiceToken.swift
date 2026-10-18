import Foundation

/// How a voice conversation is authorised. The production app uses the owner-configured
/// token server and a DODDY session; it never falls back to a public provider agent.
public enum VoiceConnectionMode: Equatable, Sendable {
    case tokenServer(endpoint: URL)
    case notSetUp(reason: String)

    /// HTTPS only. An unset or malformed endpoint fails closed and never starts a public agent.
    public static func resolve(serverAddress: String) -> VoiceConnectionMode {
        let address = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let endpoint = VoiceTokenServer.endpoint(from: address) else {
            return .notSetUp(reason: "Voice isn't set up yet. Try again later.")
        }
        return .tokenServer(endpoint: endpoint)
    }
}

public enum VoiceTokenError: Error, Equatable, Sendable {
    case sessionExpired
    case rateLimited(retryAfterSeconds: Int?)
    case busy
    case serverNotConfigured
    case serverProblem(status: Int)
    case badResponse
    case offline
}

/// Contract with `server/voice-token`: POST with a short-lived DODDY access session.
public enum VoiceTokenServer {
    /// HTTPS only, with a host; anything else is refused.
    public static func endpoint(from text: String) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil
        else { return nil }
        return url
    }

    /// `retryAfter` is the reply's Retry-After header (seconds), read only for a 429.
    public static func token(status: Int, body: Data, retryAfter: String? = nil) -> Result<String, VoiceTokenError> {
        switch status {
        case 200:
            guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                  let token = json["token"] as? String, !token.isEmpty
            else { return .failure(.badResponse) }
            return .success(token)
        case 401: return .failure(.sessionExpired)
        case 429:
            let seconds = retryAfter.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }.flatMap { $0 > 0 ? $0 : nil }
            return .failure(.rateLimited(retryAfterSeconds: seconds))
        // The server answers 500 only when it isn't configured; 503 is busy unless its body says
        // the same (server/voice-token/src/handler.js).
        case 500: return .failure(.serverNotConfigured)
        case 503:
            let error = (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["error"] as? String
            return .failure(error == "server_not_configured" ? .serverNotConfigured : .busy)
        case 404: return .failure(.serverNotConfigured)
        default: return .failure(.serverProblem(status: status))
        }
    }

    /// "Hey Doddy" for everyone (ADR-328): asks for the owner's Picovoice AccessKey.
    public static let wakeWordKeyRequestBody = Data(#"{"provider":"picovoice"}"#.utf8)

    /// Reply `{"accessKey": "…"}`, cleaned like a key the user would paste.
    public static func wakeWordKey(status: Int, body: Data) -> Result<String, VoiceTokenError> {
        guard status == 200 else {
            if case .failure(let error) = token(status: status, body: body) { return .failure(error) }
            return .failure(.serverProblem(status: status))
        }
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let raw = json["accessKey"] as? String, let key = WakeAccessKey.clean(raw)
        else { return .failure(.badResponse) }
        return .success(key)
    }

    public static func message(for error: VoiceTokenError) -> String {
        switch error {
        case .sessionExpired:
            "Your voice session expired. Close this screen and tap Talk to Doddy to reconnect with Apple."
        case .rateLimited(let seconds?) where seconds > 90:
            "You've started a lot of conversations. Try again in about \((seconds + 59) / 60) minutes; your notes still work."
        case .rateLimited(let seconds?) where seconds > 0:
            "You've started a lot of conversations. Try again in a minute or two; your notes still work."
        case .rateLimited:
            "You've started a lot of conversations. Try again later; your notes still work."
        case .busy:
            "Doddy's voice is busy or has reached today's limit. Try again later; your notes still work."
        case .serverNotConfigured:
            "Voice isn't set up yet. Try again later; you don't need to enter a code or provider key."
        case .serverProblem(let status):
            "Doddy's voice service had a problem (\(status)). Try again in a moment."
        case .badResponse:
            "Doddy's voice service sent an unexpected reply, so voice didn't start."
        case .offline:
            "Couldn't reach Doddy's voice service. Check your internet connection and try again."
        }
    }
}
