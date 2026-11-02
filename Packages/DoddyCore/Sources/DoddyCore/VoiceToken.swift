import Foundation

/// How a voice conversation is authorised. The production app uses the owner-configured
/// token server and a DODDY session; it never falls back to a public provider agent.
public enum VoiceConnectionMode: Equatable, Sendable {
    case tokenServer(endpoint: URL)
    /// Development builds only (ADR-551): connect straight to the ElevenLabs agent, without a DODDY
    /// voice account. `resolve` never returns it; only Debug code in the app builds it, and a Release
    /// build can't (`VoiceConfig.directVoiceEnabled` is false there).
    case directAgent(agentID: String)
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
    /// The request was cancelled before an answer came (ADR-681: a start cancelled with the voice
    /// sheet was shown as "You're offline").
    case cancelled
    /// The server didn't answer in time. Not "offline": the iPhone had a connection.
    case timedOut
    /// No secure (TLS) connection could be made: often a Wi-Fi that wants a sign-in first, or a
    /// wrong date on the iPhone. Not "offline" either.
    case secureConnectionFailed
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
        case 503, 500:
            let error = (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["error"] as? String
            return .failure(error == "server_not_configured" ? .serverNotConfigured : .busy)
        case 404: return .failure(.serverNotConfigured)
        default: return .failure(.serverProblem(status: status))
        }
    }

    /// What a failed request to the token server means (ADR-681). Before, every loading
    /// error was `.offline`, so a cancelled start, a timeout or a refused secure connection said
    /// "You're offline" and showed the offline note card. Only a missing or lost connection is
    /// `.offline` now; a loading error none of these names stays `.offline`, as before.
    public static func loadingFailure(_ error: any Error) -> VoiceTokenError {
        if error is CancellationError { return .cancelled }
        guard let url = error as? URLError else { return .offline }
        switch url.code {
        case .cancelled: return .cancelled
        case .timedOut: return .timedOut
        default: return secureConnectionCodes.contains(url.code) ? .secureConnectionFailed : .offline
        }
    }

    /// URL loading errors that mean the secure connection itself failed.
    static let secureConnectionCodes: Set<URLError.Code> = [
        .secureConnectionFailed,
        .serverCertificateHasBadDate,
        .serverCertificateUntrusted,
        .serverCertificateHasUnknownRoot,
        .serverCertificateNotYetValid,
        .clientCertificateRejected,
        .clientCertificateRequired,
    ]

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
        case .cancelled:
            "Starting the conversation was interrupted before Doddy's voice service answered. Tap Talk to Doddy to try again."
        case .timedOut:
            "Doddy's voice service didn't answer in time, so voice didn't start. Try again in a moment."
        case .secureConnectionFailed:
            "Doddy couldn't open a secure connection to his voice service, so voice didn't start. A Wi-Fi that asks you to sign in first, or a wrong date and time on this iPhone, can cause this."
        }
    }
}
