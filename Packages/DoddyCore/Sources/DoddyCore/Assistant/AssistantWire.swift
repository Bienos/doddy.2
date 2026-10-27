import Foundation

// JSON wire format shared with the gateway (schemas/fixtures/*.json, gateway/src/validate.js).
// Anything not listed here is never sent: the gateway rejects unknown fields.

struct AssistWireRequest: Codable, Equatable {
    struct Turn: Codable, Equatable {
        let role: String
        let text: String
    }

    struct Memory: Codable, Equatable {
        let id: String
        let text: String
        let source: String
        let capturedAt: String?
    }

    var schemaVersion = 1
    let requestId: String
    let sessionId: String
    let locale: String
    let userText: String
    let turns: [Turn]
    let memories: [Memory]
}

struct AssistWireResponse: Codable, Equatable {
    struct Usage: Codable, Equatable {
        let inputTokens: Int
        let outputTokens: Int
    }

    /// A file the person asked for, offered as a card (ADR-606). Absent from older servers and when none was asked for.
    struct Proposal: Codable, Equatable {
        let kind: String
        let title: String
        let request: String
    }

    /// A training plan the person asked for, offered as a card (ADR-626). Only a goal and, if said, the days and
    /// minutes: never a safety answer. Absent from older servers and when none was asked for.
    struct PlanOffer: Codable, Equatable {
        let goal: String
        let daysPerWeek: Int?
        let minutesPerSession: Int?
    }

    let schemaVersion: Int
    let requestId: String
    let text: String
    let citedMemoryIDs: [String]
    let usage: Usage?
    var proposal: Proposal? = nil
    var plan: PlanOffer? = nil
}

struct AssistWireError: Codable, Equatable {
    struct Detail: Codable, Equatable {
        let code: String
        let message: String
        let retryAfterSeconds: Int?
    }

    let schemaVersion: Int
    let requestId: String?
    let error: Detail
}

struct RegisterWireRequest: Codable, Equatable {
    let inviteCode: String
    let deviceId: String
}

struct RegisterWireResponse: Codable, Equatable {
    let schemaVersion: Int
    let token: String
    let expiresAtMs: Int64
}

enum WireCoding {
    static func uuid(_ id: UUID) -> String { id.uuidString.lowercased() }

    /// "2026-10-08T09:30:00Z" (whole seconds, UTC), the only date shape the gateway accepts.
    static func isoDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    static func wireRequest(from request: AssistantRequest) -> AssistWireRequest {
        AssistWireRequest(
            requestId: uuid(request.requestID),
            sessionId: uuid(request.sessionID),
            locale: request.locale,
            userText: request.userText,
            turns: request.recentTurns.map { .init(role: $0.role.rawValue, text: $0.text) },
            memories: request.groundingMemories.map {
                .init(
                    id: uuid($0.record.id),
                    text: $0.record.currentText,
                    source: $0.record.source.rawValue,
                    capturedAt: $0.record.capturedAt.map(isoDate))
            })
    }
}
