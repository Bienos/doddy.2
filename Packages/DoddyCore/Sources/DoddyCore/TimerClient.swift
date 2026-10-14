import Foundation

/// Voice timers that end with a Live Activity push (ADR-483). The server updates the island when
/// the time is up, even if the app is not running. Device-authenticated like the other calls.
extension DoddyServerClient {
    /// Registers a timer's Live Activity push token and end time. Returns the timer's id.
    public func registerTimer(activityToken: Data, environment: PushEnvironment, endsAt: Date, label: String?) async throws -> String {
        let hex = activityToken.map { String(format: "%02x", $0) }.joined()
        let cleanLabel = label.map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60)) }
        let body = TimerBody(activityToken: hex, environment: environment, endsAt: endsAt,
                             label: cleanLabel?.isEmpty == false ? cleanLabel : nil)
        let encoder = JSONEncoder()
        // The server reads an ISO 8601 date (zod z.iso.datetime), not JSONEncoder's default number.
        encoder.dateEncodingStrategy = .iso8601
        let response = try await authorized(.post, "/v1/timers", body: try encoder.encode(body))
        guard response.status == 201, let created = try? JSONDecoder().decode(CreatedTimer.self, from: response.body) else {
            throw Self.error(from: response)
        }
        return created.id
    }

    /// Cancels a timer that has not yet ended. Safe to call after it ended.
    public func cancelTimer(id: String) async throws {
        try await expect(204, .delete, "/v1/timers/\(id)")
    }
}

private struct TimerBody: Encodable {
    let activityToken: String
    let environment: PushEnvironment
    let endsAt: Date
    let label: String?
}

private struct CreatedTimer: Decodable { let id: String }
