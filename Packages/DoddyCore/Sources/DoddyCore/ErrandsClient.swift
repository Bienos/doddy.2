import Foundation

// The app's side of errands (server/messaging, docs/implementation/ERRANDS.md, ADR-566). Like the
// rest of the client: nothing is reported as started, done or deleted unless the server said so, and
// an approval that may have reached the server without an answer coming back is "unknown", never
// "offline, try again". Every error these calls throw is an `ErrandError`.

/// Why the server refused, with what the app can tell the user.
public enum ErrandError: Error, Equatable, Sendable {
    case server(ServerError)
    /// The approval's digest isn't the draft's (409 `digest_mismatch`).
    case digestMismatch
    /// Not a draft any more, or it expired (409 `not_approvable`).
    case notApprovable
    /// The account's open errands are at the server's limit (409 `too_many_open_errands`).
    case tooManyOpenErrands
    /// Errands are switched off or not set up on the server (503 `errands_disabled`).
    case errandsDisabled
    /// The server's schema refused a field (400).
    case invalid(fields: [String])
    /// The server has no such errand (404).
    case notFound
    /// Another 409, with the server's code.
    case conflict(String)
    /// The server's preview doesn't hold exactly the words, brief and title the user said yes to,
    /// so the app doesn't approve it.
    case previewMismatch
}

extension DoddyServerClient {
    /// A draft on the server; nothing runs. Checked against the draft before it is returned (the
    /// words, brief and title echoed back, and the digest recomputed here), so the digest the app
    /// approves is for exactly what the user said yes to.
    public func createErrand(_ draft: ErrandDraft) async throws -> ErrandPreview {
        let response = try await errandRequest(.post, "/v1/errands", body: try Self.json(CreateErrandBody(draft)))
        guard response.status == 201, let preview = try? JSONDecoder().decode(ErrandPreview.self, from: response.body)
        else { throw Self.errandError(from: response) }
        guard preview.matches(draft) else { throw ErrandError.previewMismatch }
        return preview
    }

    /// Approves exactly the draft with this digest, and the server starts working on it. An answer
    /// that never came back (no reply, or a 500, 502 or 504 that may have come after the server
    /// queued it) is `unknown`, and nothing is approved again.
    public func approveErrand(_ id: UUID, digest: String) async throws -> ErrandApproval {
        let unknown = ErrandApproval(id: nil, state: ErrandState.unknown.rawValue)
        let response: ServerResponse
        do {
            response = try await errandRequest(.post, "/v1/errands/\(Self.id(id))/approve",
                                               body: try Self.json(DigestBody(digest: digest)), startsSomething: true)
        } catch is OutcomeUnknown {
            return unknown
        }
        if [500, 502, 504].contains(response.status) { return unknown }
        guard response.status == 202 else { throw Self.errandError(from: response) }
        // Accepted, but the body can't be read: the state isn't known, so it isn't reported as queued.
        guard let body = try? JSONDecoder().decode(ApprovalBody.self, from: response.body) else { return unknown }
        return ErrandApproval(id: body.id, state: body.state)
    }

    /// Newest first; drafts left out.
    public func errands() async throws -> [ErrandSummary] {
        let list: ErrandList = try await errandJSON("/v1/errands")
        return list.errands
    }

    public func errand(_ id: UUID) async throws -> ErrandSnapshot {
        try await errandJSON("/v1/errands/\(Self.id(id))")
    }

    /// A queued errand never starts; a running one stops at its next step and ends `cancelled`.
    public func cancelErrand(_ id: UUID) async throws {
        let response = try await errandRequest(.post, "/v1/errands/\(Self.id(id))/cancel", body: nil)
        guard response.status == 204 else { throw Self.errandError(from: response) }
    }

    /// Call only after the result is saved on the iPhone and read back: the server then deletes
    /// its copy of the words, brief, title and result, and says what it deleted.
    public func acknowledgeErrand(_ id: UUID, resultDigest: String) async throws -> [ErrandDeletion] {
        let response = try await errandRequest(.post, "/v1/errands/\(Self.id(id))/ack",
                                               body: try Self.json(AckErrandBody(resultDigest: resultDigest)))
        guard response.status == 200, let body = try? JSONDecoder().decode(AckErrandReply.self, from: response.body)
        else { throw Self.errandError(from: response) }
        return body.deletions
    }

    /// Deletes the errand's row on the server. A 404 means the server holds no such errand, which is
    /// what was asked for.
    public func deleteErrand(_ id: UUID) async throws {
        let response = try await errandRequest(.delete, "/v1/errands/\(Self.id(id))", body: nil)
        guard response.status == 204 || response.status == 404 else { throw Self.errandError(from: response) }
    }

    // MARK: Plumbing

    private func errandRequest(_ method: HTTPMethod, _ path: String, body: Data?, startsSomething: Bool = false) async throws -> ServerResponse {
        do {
            return try await authorized(method, path, body: body, startsSomething: startsSomething)
        } catch let error as ServerError {
            throw ErrandError.server(error)
        }
    }

    private func errandJSON<T: Decodable>(_ path: String) async throws -> T {
        let response = try await errandRequest(.get, path, body: nil)
        guard response.status == 200, let value = try? JSONDecoder().decode(T.self, from: response.body)
        else { throw Self.errandError(from: response) }
        return value
    }

    static func errandError(from response: ServerResponse) -> ErrandError {
        let body = try? JSONDecoder().decode(ErrandRefusal.self, from: response.body)
        switch (response.status, body?.error ?? "") {
        case (409, "digest_mismatch"): return .digestMismatch
        case (409, "not_approvable"): return .notApprovable
        case (409, "too_many_open_errands"): return .tooManyOpenErrands
        case (409, let code): return .conflict(code)
        case (503, "errands_disabled"): return .errandsDisabled
        case (400, _): return .invalid(fields: body?.fields ?? [])
        case (404, _): return .notFound
        default: return .server(error(from: response))
        }
    }
}

/// Exactly the four fields the server's schema takes.
private struct CreateErrandBody: Encodable {
    let words: String
    let brief: String
    let title: String
    let language: String

    init(_ draft: ErrandDraft) {
        words = draft.words
        brief = draft.brief
        title = draft.title
        language = draft.language
    }
}

private struct DigestBody: Encodable { let digest: String }
private struct ApprovalBody: Decodable { let id: UUID?; let state: String }
private struct ErrandList: Decodable { let errands: [ErrandSummary] }
private struct AckErrandBody: Encodable { let resultDigest: String }
private struct AckErrandReply: Decodable { let deletions: [ErrandDeletion] }
private struct ErrandRefusal: Decodable { let error: String?; let fields: [String]? }
