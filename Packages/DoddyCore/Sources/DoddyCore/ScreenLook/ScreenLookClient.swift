import Foundation

/// The request `POST /v1/screen/look` takes (server/messaging/src/screen/look.ts). The picture goes to this
/// one call; the server keeps neither it nor the question.
public struct ScreenLookRequest: Equatable, Sendable {
    public let requestID: UUID
    public let locale: String
    public let question: String
    public let frameAge: TimeInterval
    public let jpeg: Data

    /// The question as the server takes it, in Unicode scalars.
    public static let maxQuestionScalars = 500

    public init(requestID: UUID = UUID(), locale: String, question: String, frameAge: TimeInterval, jpeg: Data) {
        self.requestID = requestID
        self.locale = locale
        self.question = question
        self.frameAge = frameAge
        self.jpeg = jpeg
    }

    /// Nil when the request can't be sent as it is: an empty question, a picture that isn't a JPEG or is too
    /// large, or a frame too old for the server. A long question is cut to the server's limit.
    public func wireBody() -> Data? {
        let question = String(String.UnicodeScalarView(self.question.trimmingCharacters(in: .whitespacesAndNewlines)
            .unicodeScalars.prefix(Self.maxQuestionScalars)))
        guard !question.isEmpty,
              jpeg.count > 3, jpeg.count <= ScreenShare.maxFrameBytes, jpeg.starts(with: [0xFF, 0xD8, 0xFF]),
              frameAge >= 0, frameAge <= ScreenShare.serverMaxAge
        else { return nil }
        let body = Wire(schemaVersion: 1, requestId: requestID.uuidString.lowercased(), locale: Self.wireLocale(locale),
                        question: question, frameAgeSeconds: (frameAge * 10).rounded() / 10,
                        image: .init(mediaType: "image/jpeg", data: jpeg.base64EncodedString()))
        return try? JSONEncoder().encode(body)
    }

    /// "pl-PL" → "pl-PL", "pl_PL" → "pl-PL", anything the server wouldn't take → "en".
    static func wireLocale(_ locale: String) -> String {
        let value = locale.replacingOccurrences(of: "_", with: "-")
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard let language = parts.first, (2...3).contains(language.count), language.allSatisfy({ $0.isASCII && $0.isLowercase }) else { return "en" }
        guard parts.count <= 2 else { return String(language) }
        if parts.count == 2 {
            let region = parts[1]
            guard (2...8).contains(region.count), region.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return String(language) }
        }
        return value
    }

    private struct Wire: Encodable {
        let schemaVersion: Int
        let requestId: String
        let locale: String
        let question: String
        let frameAgeSeconds: Double
        let image: Image
        struct Image: Encodable { let mediaType: String; let data: String }
    }
}

/// What came back. Each failure is something the voice agent can say honestly.
public enum ScreenLookOutcome: Equatable, Sendable {
    case answered(String)
    case notConfigured
    case dailyLimitReached
    case rateLimited
    case refused
    case timeout
    case unavailable
    case offline
    case invalidRequest
}

extension DoddyServerClient {
    /// Asks Doddy's server about one picture of the screen. A read: nothing is started, so a request that may
    /// have reached the server without an answer is a timeout, and trying again is the person's choice.
    public func lookAtScreen(_ request: ScreenLookRequest, timeout: TimeInterval = 25) async -> ScreenLookOutcome {
        guard let body = request.wireBody() else { return .invalidRequest }
        let response: ServerResponse
        do {
            response = try await authorized(.post, "/v1/screen/look", body: body, startsSomething: true, timeout: timeout)
        } catch is OutcomeUnknown {
            return .timeout
        } catch ServerError.accountMissing {
            return .unavailable
        } catch {
            return .offline
        }
        return Self.screenOutcome(response, requestID: request.requestID)
    }

    static func screenOutcome(_ response: ServerResponse, requestID: UUID) -> ScreenLookOutcome {
        struct Reply: Decodable { let requestId: String; let text: String }
        struct Failure: Decodable { struct E: Decodable { let code: String }; let error: E }
        if response.status == 200 {
            guard let reply = try? JSONDecoder().decode(Reply.self, from: response.body),
                  reply.requestId.lowercased() == requestID.uuidString.lowercased(),
                  !reply.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return .unavailable }
            return .answered(reply.text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        switch (response.status, (try? JSONDecoder().decode(Failure.self, from: response.body))?.error.code) {
        case (_, "notConfigured"): return .notConfigured
        case (_, "dailyLimitReached"): return .dailyLimitReached
        case (_, "refused"): return .refused
        case (_, "timeout"), (504, _): return .timeout
        case (_, "invalidRequest"), (400, _), (413, _): return .invalidRequest
        case (429, _): return .rateLimited
        default: return .unavailable
        }
    }
}
