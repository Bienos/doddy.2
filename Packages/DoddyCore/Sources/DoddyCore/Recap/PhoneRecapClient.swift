import Foundation

/// The recaps of calls to and from Doddy's phone line (decision 2026-11-09-conversation-recaps, step 5).
/// After a call, the messaging server writes three short lists from the call (only for an account that turned
/// recaps on here) and keeps ONLY those lists, encrypted, until this iPhone has saved them as a note and said
/// so, or for 30 days; the transcript is never stored there. Like a call note, a recap is "waiting" on the
/// server and is deleted there only after the iPhone saved it and read it back (DOD-08).
///
/// Everything the server sends is a proposal: `RecapKeeper` builds a `ConversationRecap` from it, which checks
/// every recap rule again, before anything is saved.
public struct PhoneRecapClient: Sendable {
    public enum Failure: Error, Equatable, Sendable {
        /// No server address in this build, or the server isn't set up for recaps.
        case notConfigured
        case offline
        case unavailable
    }

    public enum Direction: String, Sendable { case inbound, outbound }

    public struct Recap: Equatable, Sendable {
        public let callId: UUID
        public let discussed: [String]
        public let agreed: [String]
        public let toDo: [String]
        public let endedAt: Date
        public let durationSecs: Double?
        public let direction: Direction
    }

    public struct Listing: Equatable, Sendable {
        /// Whether the server has recaps switched on for this account.
        public let enabled: Bool
        public let recaps: [Recap]
        /// Recaps the server couldn't decrypt (a key change): they can only be deleted.
        public let unreadable: [UUID]
    }

    private let server: DoddyServerClient?

    public init(server: DoddyServerClient?) { self.server = server }

    /// The server's answer as a `Listing`. A recap that isn't well formed is left out, never guessed.
    static func listing(_ response: ServerResponse) throws(Failure) -> Listing {
        guard response.status == 200 else { throw failure(for: response) }
        struct Wire: Decodable {
            struct Item: Decodable {
                let callId: String
                let discussed: [String]
                let agreed: [String]
                let to_do: [String]
                let endedAt: String
                let durationSecs: Double?
                let direction: String
            }
            let enabled: Bool
            let recaps: [Item]
            let unreadable: [String]
        }
        guard let wire = try? JSONDecoder().decode(Wire.self, from: response.body) else { throw .unavailable }
        let recaps: [Recap] = wire.recaps.compactMap { item in
            guard let id = UUID(uuidString: item.callId), let ended = ServerDates.parse(item.endedAt),
                  let direction = Direction(rawValue: item.direction) else { return nil }
            return Recap(callId: id, discussed: item.discussed, agreed: item.agreed, toDo: item.to_do, endedAt: ended,
                         durationSecs: item.durationSecs, direction: direction)
        }
        return Listing(enabled: wire.enabled, recaps: recaps, unreadable: wire.unreadable.compactMap(UUID.init(uuidString:)))
    }

    private static func failure(for response: ServerResponse) -> Failure {
        switch response.status {
        case 503, 404: .notConfigured
        default: .unavailable
        }
    }

    private func call(_ method: HTTPMethod, _ path: String, body: Data? = nil) async throws(Failure) -> ServerResponse {
        guard let server else { throw .notConfigured }
        var retriedAccount = false
        while true {
            do {
                return try await server.authorized(method, path, body: body)
            } catch ServerError.accountMissing where !retriedAccount {
                retriedAccount = true
            } catch ServerError.offline {
                throw .offline
            } catch ServerError.notConfigured {
                throw .notConfigured
            } catch {
                throw .unavailable
            }
        }
    }

    public func list() async throws(Failure) -> Listing {
        try Self.listing(try await call(.get, "/v1/calls/recaps"))
    }

    /// Turns recaps on or off on the server. Off deletes every recap waiting there.
    public func setEnabled(_ enabled: Bool) async throws(Failure) {
        struct Body: Encodable { let enabled: Bool }
        guard let body = try? JSONEncoder().encode(Body(enabled: enabled)) else { throw .unavailable }
        let response = try await call(.put, "/v1/calls/recaps/settings", body: body)
        guard response.status == 200 else { throw Self.failure(for: response) }
    }

    /// Deletes a recap on the server, after it was saved here (or when it can never be saved). Already
    /// gone is done: asking twice is not an error.
    public func delete(_ callId: UUID) async throws(Failure) {
        let response = try await call(.delete, "/v1/calls/recaps/\(callId.uuidString.lowercased())")
        guard response.status == 204 || response.status == 404 else { throw Self.failure(for: response) }
    }
}
