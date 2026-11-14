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

/// Which ElevenLabs agent a conversation talks to (decision 2026-11-12-translator-agent). Translating gets
/// its own agent, `voice-agent/translator/`, which has no tools at all (owner, 12 Nov 2026: the agent must not
/// use any function while translating); everything else talks to the main agent, as before.
public enum VoiceAgentKind: String, Equatable, Sendable {
    case main
    case translator

    /// The body of the token request: none for the main agent (as before 12 Nov 2026, so older servers and
    /// builds agree), `{"agent":"translator"}` for the translator agent. A server that predates the field
    /// ignores it and answers with the main agent's token, which still translates (the app refuses every
    /// tool while it does), so a new app and an old server never fail.
    public var requestBody: Data? {
        switch self {
        case .main: return nil
        case .translator: return Data(#"{"agent":"translator"}"#.utf8)
        }
    }

    /// The agent a conversation needs: the translator agent for a translator start, the main one otherwise.
    public static func forTranslatorStart(_ isTranslatorStart: Bool) -> VoiceAgentKind {
        isTranslatorStart ? .translator : .main
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

/// What a reply that isn't a success from the voice account endpoint (`/api/voice-auth`, the same
/// server) means to the app (ADR-712).
public enum VoiceAuthStatus: Equatable, Sendable {
    case sessionExpired
    case serverNotConfigured
    /// 429 on a sign-in: the server counts sign-ins per caller address, per hour and per day, and
    /// says in Retry-After how long until the window ends. Not a verification failure.
    case tooManySignIns(retryAfterSeconds: Int?)
    /// Any other refusal, such as Apple's token not verifying.
    case rejected

    /// `action` is the request's (`sign-in`, `refresh`, `sign-out`, `delete-account`); only a sign-in
    /// is throttled, so a 429 for another one is just a refusal.
    public static func failure(status: Int, action: String, retryAfter: String?) -> VoiceAuthStatus {
        switch status {
        case 401: .sessionExpired
        case 404, 500, 503: .serverNotConfigured
        case 429 where action == "sign-in": .tooManySignIns(retryAfterSeconds: VoiceTokenServer.retryAfterSeconds(retryAfter))
        default: .rejected
        }
    }
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

    /// The reply's Retry-After header as a number of seconds, or nil when it is missing, not a number
    /// or not more than zero.
    public static func retryAfterSeconds(_ header: String?) -> Int? {
        header.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }.flatMap { $0 > 0 ? $0 : nil }
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
            return .failure(.rateLimited(retryAfterSeconds: retryAfterSeconds(retryAfter)))
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

    /// A wait in words, for a 429's Retry-After (ADR-712). The token server answers with the seconds
    /// until its hourly or its daily window ends, so a wait can be most of a day: up to an hour and a
    /// half it reads in minutes, then in hours, and several hours that run past local midnight read
    /// "tomorrow". No wait given, or one of zero or less, reads "later".
    public static func waitPhrase(seconds: Int?, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let seconds, seconds > 0 else { return "later" }
        if seconds <= 90 { return "in a minute or two" }
        let minutes = (seconds + 59) / 60
        if minutes <= 90 { return "in about \(minutes) minutes" }
        let hours = (seconds + 3_599) / 3_600
        if hours >= 36 { return "in about \((hours + 23) / 24) days" }
        if hours >= tomorrowFromHours, !calendar.isDate(now, inSameDayAs: now.addingTimeInterval(TimeInterval(seconds))) {
            return "tomorrow"
        }
        return "in about \(hours) hours"
    }

    /// From this many hours on, a wait that ends after midnight reads "tomorrow"; a shorter one still
    /// says how many hours, even across midnight.
    static let tomorrowFromHours = 6

    public static func message(for error: VoiceTokenError, now: Date = Date(), calendar: Calendar = .current) -> String {
        switch error {
        case .sessionExpired:
            "Your voice session expired. Close this screen and tap Talk to Doddy to reconnect with Apple."
        case .rateLimited(let seconds):
            "You've started a lot of conversations. Try again \(waitPhrase(seconds: seconds, now: now, calendar: calendar)); your notes still work."
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

    /// What a throttled sign-in says (ADR-712): that too many were made from this network, and when to
    /// try again if the server said. It must not read as if Apple's sign-in had failed to verify.
    public static func signInThrottledMessage(retryAfterSeconds: Int?, now: Date = Date(), calendar: Calendar = .current) -> String {
        "Too many sign-ins from this network. Try again \(waitPhrase(seconds: retryAfterSeconds, now: now, calendar: calendar))."
    }
}
