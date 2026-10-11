import Foundation

/// How a voice conversation is authorised. `tokenServer` is required before anyone but the
/// owner uses the app: the agent then refuses connections without a token, and the
/// ElevenLabs API key stays on the server (`server/voice-token`).
public enum VoiceConnectionMode: Equatable, Sendable {
    /// Development only: anyone with the agent ID can start a conversation.
    case publicAgent(agentID: String)
    case tokenServer(endpoint: URL, accessCode: String)
    case notSetUp(reason: String)

    /// A non-empty server address switches to the token server; the public agent ID is then ignored.
    public static func resolve(serverAddress: String, accessCode: String?, publicAgentID: String) -> VoiceConnectionMode {
        let address = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if address.isEmpty {
            let agentID = publicAgentID.trimmingCharacters(in: .whitespacesAndNewlines)
            return agentID.isEmpty
                ? .notSetUp(reason: "Voice isn't set up. Add a token server or an ElevenLabs agent ID in Settings → Voice.")
                : .publicAgent(agentID: agentID)
        }
        guard let endpoint = VoiceTokenServer.endpoint(from: address) else {
            return .notSetUp(reason: "The token server address must start with https://. Check Settings → Voice.")
        }
        guard let accessCode, !accessCode.allSatisfy(\.isWhitespace) else {
            return .notSetUp(reason: "Add your access code in Settings → Voice to talk to Doddy.")
        }
        return .tokenServer(endpoint: endpoint, accessCode: accessCode.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

public enum VoiceTokenError: Error, Equatable, Sendable {
    case accessCodeRejected
    case busy
    case serverNotConfigured
    case serverProblem(status: Int)
    case badResponse
    case offline
}

/// Contract with `server/voice-token`: POST, `Authorization: Bearer <code>`, reply `{"token": "…"}`.
public enum VoiceTokenServer {
    /// HTTPS only, with a host; anything else is refused.
    public static func endpoint(from text: String) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty
        else { return nil }
        return url
    }

    public static func token(status: Int, body: Data) -> Result<String, VoiceTokenError> {
        switch status {
        case 200:
            guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                  let token = json["token"] as? String, !token.isEmpty
            else { return .failure(.badResponse) }
            return .success(token)
        case 401: return .failure(.accessCodeRejected)
        case 503: return .failure(.busy)
        case 500: return .failure(.serverNotConfigured)
        default: return .failure(.serverProblem(status: status))
        }
    }

    /// "Hey Doddy" for everyone (ADR-328): asks for the owner's Picovoice AccessKey.
    public static let wakeWordKeyRequestBody = Data(#"{"provider":"picovoice"}"#.utf8)

    /// Reply `{"accessKey": "…"}`, cleaned like a key the user would paste. A server from before
    /// ADR-328 answers 400 (unknown provider), which is a server problem, never a key.
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
        case .accessCodeRejected:
            "Your access code wasn't accepted. Check it in Settings → Voice."
        case .busy:
            "Doddy's voice is busy or has reached today's limit. Try again later; your notes still work."
        case .serverNotConfigured:
            "Doddy's token server isn't set up correctly yet, so voice can't start."
        case .serverProblem(let status):
            "Doddy's token server had a problem (\(status)). Try again in a moment."
        case .badResponse:
            "Doddy's token server sent an unexpected reply, so voice didn't start."
        case .offline:
            "Couldn't reach Doddy's token server. Check your internet connection and try again."
        }
    }
}
