import Foundation

// S2: phone calls with Doddy (server/src/routes/calls.ts). Same rules as the rest of the client:
// nothing is reported as on until the server confirmed it.

public struct CallSettings: Equatable, Sendable, Decodable {
    public struct Available: Equatable, Sendable, Decodable {
        public let inbound: Bool
        public let outbound: Bool
    }

    public struct MemoryCopy: Equatable, Sendable, Decodable {
        public let enabled: Bool
        public let count: Int
    }

    /// What the server's phone line can do right now (keys and agent configured).
    public let available: Available
    public let doddyNumber: String?
    public let phoneVerified: Bool
    public let inboundEnabled: Bool
    public let pinSet: Bool
    public let pinLocked: Bool
    public let outboundConsent: Bool
    public let memoryCopy: MemoryCopy
}

public struct CallNote: Equatable, Sendable, Decodable, Identifiable {
    public let id: UUID
    public let text: String
    /// When it was said on the call (ISO 8601 from the server).
    public let createdAt: String

    public var createdDate: Date? { ServerDates.parse(createdAt) }
}

/// A call note the server holds but can't decrypt (e.g. after a key change). Only when it was
/// said is known; it can still be discarded with `deleteCallNote`.
public struct UnreadableCallNote: Equatable, Sendable, Decodable, Identifiable {
    public let id: UUID
    public let createdAt: String

    public var createdDate: Date? { ServerDates.parse(createdAt) }
}

/// Everything waiting in the call-notes inbox, including the notes that can't be read.
public struct CallInbox: Equatable, Sendable, Decodable {
    public let notes: [CallNote]
    public let unreadable: [UnreadableCallNote]

    private enum CodingKeys: String, CodingKey { case notes, unreadable }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        notes = try container.decode([CallNote].self, forKey: .notes)
        // Servers before the unreadable list omit it.
        unreadable = try container.decodeIfPresent([UnreadableCallNote].self, forKey: .unreadable) ?? []
    }
}

public struct CallRecord: Equatable, Sendable, Decodable, Identifiable {
    public let id: UUID
    public let direction: String
    public let status: String
    public let createdAt: String

    public var createdDate: Date? { ServerDates.parse(createdAt) }
}

public struct CallRequest: Equatable, Sendable, Decodable {
    /// Nil when the server's answer never reached the phone.
    public let callId: UUID?
    /// `requested` (ElevenLabs accepted it) or `unknown` (no answer from ElevenLabs, or the
    /// server's answer was lost on the way back; the phone may already be ringing; not redialled).
    public let status: String
}

/// Wording next to "Doddy may call me"; the server stores the version with the consent.
public enum CallConsent {
    public static let textVersion = "calls-v1"
    public static let text = "Doddy may call this number when you ask it to, for example with Call me now. You'll be talking to an AI. Standard call rates may apply. Turn this off at any time."
}

public enum CallPIN {
    /// Mirrors the server (ADR-175): 6–8 digits, not one repeated digit, not a straight run like 123456.
    public static func isAcceptable(_ pin: String) -> Bool {
        let digits = pin.compactMap(\.wholeNumberValue)
        guard (6...8).contains(pin.count), digits.count == pin.count, pin.allSatisfy(\.isASCII) else { return false }
        let allSame = digits.allSatisfy { $0 == digits[0] }
        let up = zip(digits, digits.dropFirst()).allSatisfy { ($0 + 1) % 10 == $1 }
        let down = zip(digits, digits.dropFirst()).allSatisfy { ($0 + 9) % 10 == $1 }
        return !(allSame || up || down)
    }
}

/// One memory as copied to the server for calls: only the current (corrected) text.
public struct MemoryCopyItem: Equatable, Sendable, Encodable {
    public let id: UUID
    public let text: String
    public let capturedAt: String?

    /// Sample fixtures are never copied; they are not the user's memories.
    public static func from(_ records: [MemoryRecord]) -> [MemoryCopyItem] {
        records.filter { $0.source != .sampleFixture }.map {
            MemoryCopyItem(id: $0.id, text: $0.currentText, capturedAt: $0.capturedAt.map(ServerDates.format))
        }
    }
}


extension DoddyServerClient {
    public func callSettings() async throws -> CallSettings {
        try await decoded(.get, "/v1/calls/settings")
    }

    public func setInboundCalls(_ on: Bool) async throws {
        try await expect(204, .put, "/v1/calls/settings", InboundBody(inboundEnabled: on))
    }

    /// Records consent to `CallConsent.text` (with its version), or withdraws it.
    public func setOutboundConsent(_ on: Bool) async throws {
        try await expect(204, .put, "/v1/calls/settings",
                         ConsentBody(outboundConsent: on, outboundConsentTextVersion: on ? CallConsent.textVersion : nil))
    }

    public func setCallPIN(_ pin: String) async throws {
        try await expect(204, .put, "/v1/calls/pin", PinBody(pin: pin))
    }

    public func removeCallPIN() async throws {
        try await expect(204, .delete, "/v1/calls/pin")
    }

    /// Waits longer than the server's own ElevenLabs timeout (15 s). A request that may have
    /// reached the server without an answer coming back is `unknown`, never "offline, try again".
    public func callMeNow() async throws -> CallRequest {
        let response: ServerResponse
        do {
            response = try await authorized(.post, "/v1/calls/outbound", body: nil, startsSomething: true, timeout: 30)
        } catch is OutcomeUnknown {
            return CallRequest(callId: nil, status: "unknown")
        }
        guard response.status == 202, let request = try? JSONDecoder().decode(CallRequest.self, from: response.body)
        else { throw Self.error(from: response) }
        return request
    }

    public func recentCalls() async throws -> [CallRecord] {
        let list: CallList = try await decoded(.get, "/v1/calls")
        return list.calls
    }

    /// Turning it off deletes every copy on the server.
    public func setMemoryCopy(enabled: Bool) async throws {
        try await expect(204, .put, "/v1/memory-copy", EnabledBody(enabled: enabled))
    }

    /// Replaces the server's copy with exactly these memories (so deletions carry over).
    @discardableResult
    public func replaceMemoryCopy(_ items: [MemoryCopyItem]) async throws -> Int {
        let response = try await authorized(.put, "/v1/memory-copy/snapshot", body: try Self.json(SnapshotBody(items: items)))
        guard response.status == 200, let result = try? JSONDecoder().decode(CountBody.self, from: response.body)
        else { throw Self.error(from: response) }
        return result.count
    }

    /// Only the readable notes. Use `callInbox()` so notes that can't be read can be discarded.
    public func callNotes() async throws -> [CallNote] {
        try await callInbox().notes
    }

    /// Throws when the inbox couldn't be loaded; an empty inbox is only ever what the server said.
    public func callInbox() async throws -> CallInbox {
        try await decoded(.get, "/v1/call-notes")
    }

    public func deleteCallNote(_ id: UUID) async throws {
        try await expect(204, .delete, "/v1/call-notes/\(id.uuidString.lowercased())")
    }

    private func decoded<T: Decodable>(_ method: HTTPMethod, _ path: String) async throws -> T {
        let response = try await authorized(method, path, body: nil)
        guard response.status == 200, let value = try? JSONDecoder().decode(T.self, from: response.body)
        else { throw Self.error(from: response) }
        return value
    }
}

private struct InboundBody: Encodable { let inboundEnabled: Bool }
private struct ConsentBody: Encodable { let outboundConsent: Bool; let outboundConsentTextVersion: String? }
private struct PinBody: Encodable { let pin: String }
private struct EnabledBody: Encodable { let enabled: Bool }
private struct SnapshotBody: Encodable { let items: [MemoryCopyItem] }
private struct CountBody: Decodable { let count: Int }
private struct CallList: Decodable { let calls: [CallRecord] }
