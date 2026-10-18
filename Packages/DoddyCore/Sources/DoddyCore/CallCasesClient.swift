import Foundation

// The app's side of call cases (server/messaging/src/routes/callCases.ts, ADR-500). Like the rest
// of the client: nothing is reported as done unless the server said so, and a request that may have
// started a call without an answer coming back is "unknown", never "offline, try again".

/// Why the server refused, with the details the card can explain.
public enum CallCaseError: Error, Equatable, Sendable {
    case server(ServerError)
    /// A brief field the server won't send (e.g. `pesel_not_ticked`, `question_commits`).
    case briefRefused(field: String, reason: String)
    /// Not a number Doddy may call (emergency, premium, foreign, own number...).
    case destinationRefused(reason: String)
    /// A hard limit stopped the dial: hours, a rate limit, one call at a time, kill switch, agent drift.
    case gateRefused(gate: String)
    /// The approval doesn't match (`digest_mismatch`), the time is outside the hours, an attempt is open...
    case notApprovable(String)
    case callsDisabled
}

extension DoddyServerClient {
    public func callCaseAvailability() async throws -> CallCaseAvailability {
        try await getJSON("/v1/call-cases/availability")
    }

    /// Sends the brief (ticked facts only) and gets back the preview the card must show.
    public func createCallCase(_ draft: CallBriefDraft) async throws -> CallPreview {
        let response = try await authorized(.post, "/v1/call-cases", body: try Self.json(draft.requestBody()))
        guard response.status == 201, let preview = try? JSONDecoder().decode(CallPreview.self, from: response.body)
        else { throw Self.callCaseError(from: response) }
        return preview
    }

    /// Approves exactly the preview with this digest; `at` schedules it (a retry at a set time).
    /// May start a call: an answer that never came back is `unknown`, and nothing is redialled.
    public func approveCallCase(_ caseId: UUID, digest: String, at: Date? = nil) async throws -> CallApproval {
        let response: ServerResponse
        do {
            response = try await authorized(.post, "/v1/call-cases/\(Self.id(caseId))/approve",
                                            body: try Self.json(ApproveBody(digest: digest, at: at.map(ServerDates.format))),
                                            startsSomething: true, timeout: 30)
        } catch is OutcomeUnknown {
            return CallApproval(attemptId: nil, state: "unknown")
        }
        guard response.status == 202, let body = try? JSONDecoder().decode(ApprovalReply.self, from: response.body)
        else { throw Self.callCaseError(from: response) }
        return CallApproval(attemptId: body.attemptId, state: body.state)
    }

    public func callCaseLive(_ caseId: UUID, after cursor: String?) async throws -> CallLiveView {
        var path = "/v1/call-cases/\(Self.id(caseId))/live"
        if let cursor, let encoded = cursor.addingPercentEncoding(withAllowedCharacters: .alphanumerics) { path += "?after=\(encoded)" }
        return try await getJSON(path)
    }

    /// "Zakończ": Doddy says goodbye and hangs up.
    public func endCallCase(_ caseId: UUID) async throws {
        let response = try await authorized(.post, "/v1/call-cases/\(Self.id(caseId))/end", body: nil, startsSomething: true)
        guard response.status == 202 else { throw Self.callCaseError(from: response) }
    }

    /// "Przejmij": the server rings your verified phone; press 1 to join. Returns the takeover state.
    public func takeOverCallCase(_ caseId: UUID) async throws -> String {
        let response: ServerResponse
        do {
            response = try await authorized(.post, "/v1/call-cases/\(Self.id(caseId))/takeover", body: nil, startsSomething: true, timeout: 30)
        } catch is OutcomeUnknown {
            return "unknown"
        }
        guard response.status == 202, let body = try? JSONDecoder().decode(TakeoverReply.self, from: response.body)
        else { throw Self.callCaseError(from: response) }
        return body.state
    }

    public func callCase(_ caseId: UUID) async throws -> CallCaseSnapshot {
        try await getJSON("/v1/call-cases/\(Self.id(caseId))")
    }

    /// Call only after the result is saved on the iPhone: the server then deletes its copies and
    /// says what it deleted.
    public func acknowledgeCallResult(_ caseId: UUID, attemptId: UUID, resultDigest: String) async throws -> [DeletionReceipt] {
        let response = try await authorized(.post, "/v1/call-cases/\(Self.id(caseId))/ack",
                                            body: try Self.json(AckBody(attemptId: Self.id(attemptId), resultDigest: resultDigest)))
        guard response.status == 200, let body = try? JSONDecoder().decode(AckReply.self, from: response.body)
        else { throw Self.callCaseError(from: response) }
        return body.deletions
    }

    public func cancelCallCase(_ caseId: UUID) async throws {
        let response = try await authorized(.post, "/v1/call-cases/\(Self.id(caseId))/cancel", body: nil)
        guard response.status == 204 else { throw Self.callCaseError(from: response) }
    }

    /// Lets the server move the Live Activity (phase and times only, never words) while the app sleeps.
    public func setCallLiveActivityToken(_ caseId: UUID, token: Data, environment: PushEnvironment) async throws {
        try await expect(204, .put, "/v1/call-cases/\(Self.id(caseId))/live-activity",
                         LiveActivityBody(token: token.map { String(format: "%02x", $0) }.joined(), environment: environment))
    }

    static func id(_ uuid: UUID) -> String { uuid.uuidString.lowercased() }

    static func callCaseError(from response: ServerResponse) -> CallCaseError {
        let body = try? JSONDecoder().decode(RefusalBody.self, from: response.body)
        switch (response.status, body?.error ?? "") {
        case (400, "brief_refused"): return .briefRefused(field: body?.field ?? "", reason: body?.reason ?? "")
        case (400, "destination_refused"): return .destinationRefused(reason: body?.reason ?? "")
        case (409, "gate_refused"): return .gateRefused(gate: body?.gate ?? "")
        case (409, let code) where ["digest_mismatch", "outside_hours", "attempt_open", "already_answered", "no_more_attempts",
                                    "not_approvable", "not_live", "taken_over", "not_takeoverable", "result_mismatch",
                                    "call_live", "no_more_tries", "phone_not_supported", "too_many_open_cases"].contains(code):
            return .notApprovable(code)
        case (503, "calls_disabled"): return .callsDisabled
        default: return .server(error(from: response))
        }
    }
}

private struct ApproveBody: Encodable { let digest: String; let at: String? }
private struct ApprovalReply: Decodable { let attemptId: UUID?; let state: String }
private struct TakeoverReply: Decodable { let state: String }
private struct AckBody: Encodable { let attemptId: String; let resultDigest: String }
private struct AckReply: Decodable { let deletions: [DeletionReceipt] }
private struct LiveActivityBody: Encodable { let token: String; let environment: PushEnvironment }
private struct RefusalBody: Decodable { let error: String?; let field: String?; let reason: String?; let gate: String? }
