import Foundation

/// Asks Doddy's messaging server for a recap (`POST /v1/recaps`, decision 2026-11-09-conversation-recaps,
/// step 3b), used only when this iPhone can't write one itself and the person said yes
/// (`RecapSettings.serverWriterKey`). The lines go for this one request; the server stores none of them.
/// The answer is a proposal: it comes back as the three lists' JSON for `RecapModelIO.read`, which checks
/// every rule again before anything is saved.
public struct ServerRecapClient: Sendable {
    public enum Failure: Error, Equatable, Sendable {
        /// No server address in this build, the server's switch is off, or this kind isn't written there.
        case notConfigured
        case offline
        case dailyLimitReached
        case refused
        /// It may have reached the server, but no answer came back. Not retried on its own (DOD-08).
        case outcomeUnknown
        case unavailable
    }

    /// The most a line may hold on the server; a longer one is cut here (the input, never the note).
    public static let maxLineLength = 4_000

    private let server: DoddyServerClient?
    private let timeout: TimeInterval

    public init(server: DoddyServerClient?, timeout: TimeInterval = 50) {
        self.server = server
        self.timeout = timeout
    }

    /// The server writes only conversations with Doddy and recordings: a call Doddy made for the person
    /// needs no model, and the phone line's recap is made where the call is (step 5).
    public static func serves(_ kind: ConversationRecapKind) -> Bool {
        kind == .voiceConversation || kind == .recording
    }

    /// The request body. A long conversation keeps its start and its end, like the iPhone's own writer.
    static func body(kind: ConversationRecapKind, lines: [RecapModelIO.Line], languageCode: String, requestID: UUID) throws -> Data {
        struct Line: Encodable { let speaker: String; let text: String }
        struct Body: Encodable {
            let schemaVersion = 1
            let requestId: String
            let kind: String
            let language: String
            let lines: [Line]
        }
        let fitted = RecapModelIO.fitted(lines.map {
            RecapModelIO.Line(speaker: $0.speaker, text: String($0.text.unicodeScalars.prefix(maxLineLength)))
        })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(Body(
            requestId: requestID.uuidString.lowercased(), kind: kind.rawValue, language: languageCode,
            lines: fitted.map { Line(speaker: $0.speaker.rawValue, text: $0.text) }))
    }

    /// The three lists from a server answer, as JSON for `RecapModelIO.read`; a failure says why.
    static func answer(_ response: ServerResponse) throws(Failure) -> Data {
        guard response.status == 200 else {
            let code = (try? JSONSerialization.jsonObject(with: response.body) as? [String: Any])
                .flatMap { $0["error"] as? [String: Any] }?["code"] as? String
            switch (response.status, code) {
            case (429, _), (_, "dailyLimitReached"): throw .dailyLimitReached
            case (503, "notConfigured"), (404, _): throw .notConfigured
            case (_, "refused"): throw .refused
            default: throw .unavailable
            }
        }
        guard let object = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any] else { throw .unavailable }
        var lists: [String: Any] = [:]
        for key in ["discussed", "agreed", "to_do"] {
            guard let list = object[key] else { throw .unavailable }
            lists[key] = list
        }
        guard let data = try? JSONSerialization.data(withJSONObject: lists) else { throw .unavailable }
        return data
    }

    public func write(kind: ConversationRecapKind, lines: [RecapModelIO.Line], languageCode: String,
                      requestID: UUID = UUID()) async throws(Failure) -> Data {
        guard let server, Self.serves(kind) else { throw .notConfigured }
        guard let body = try? Self.body(kind: kind, lines: lines, languageCode: languageCode, requestID: requestID) else {
            throw .unavailable
        }
        var retriedAccount = false
        while true {
            do {
                let response = try await server.authorized(.post, "/v1/recaps", body: body, startsSomething: true, timeout: timeout)
                return try Self.answer(response)
            } catch let failure as Failure {
                throw failure
            } catch ServerError.accountMissing where !retriedAccount {
                retriedAccount = true
            } catch is DoddyServerClient.OutcomeUnknown {
                throw .outcomeUnknown
            } catch ServerError.offline {
                throw .offline
            } catch ServerError.rateLimited {
                throw .dailyLimitReached
            } catch ServerError.notConfigured {
                throw .notConfigured
            } catch {
                throw .unavailable
            }
        }
    }
}

extension RecapModelIO {
    /// The lines cut to `maxConversationLength` Unicode scalars in all (what the server counts): the start and the end are kept, the
    /// middle is dropped and marked, as `shortened` does for the iPhone's own writer.
    public static func fitted(_ lines: [Line]) -> [Line] {
        let total = lines.reduce(0) { $0 + $1.text.unicodeScalars.count + 1 }
        guard total > maxConversationLength else { return lines }
        let half = maxConversationLength / 2
        var head: [Line] = []
        var used = 0
        for line in lines {
            guard used + line.text.unicodeScalars.count + 1 <= half else { break }
            head.append(line)
            used += line.text.unicodeScalars.count + 1
        }
        var tail: [Line] = []
        used = 0
        for line in lines.dropFirst(head.count).reversed() {
            guard used + line.text.unicodeScalars.count + 1 <= half - 8 else { break }
            tail.insert(line, at: 0)
            used += line.text.unicodeScalars.count + 1
        }
        return head + [Line(speaker: .other, text: "[…]")] + tail
    }
}
