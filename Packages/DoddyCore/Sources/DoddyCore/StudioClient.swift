import Foundation

// The app's side of Studio (server/messaging, docs/implementation/STUDIO.md, ADR-584). Like the
// rest of the client: nothing is reported as started, ready or deleted unless the server said so,
// and an approval that may have reached the server without an answer coming back is "unknown",
// never "offline, try again". Every error these calls throw is a `StudioError`.

/// Why the server refused, with what the app can tell the user.
public enum StudioError: Error, Equatable, Sendable {
    case server(ServerError)
    /// The approval's digest isn't the draft's (409 `digest_mismatch`).
    case digestMismatch
    /// Not a draft any more, or it expired (409 `not_approvable`).
    case notApprovable
    /// The account's open jobs are at the server's limit (409 `too_many_open_items`).
    case tooManyOpenItems
    /// Today's spending cap for this account is reached (409 `daily_cap_reached`), in dollars.
    case dailyCapReached(capUsd: Double?, spentUsd: Double?)
    /// Studio is switched off or not set up on the server (503 `studio_disabled`).
    case studioDisabled
    /// The server's schema refused a field (400).
    case invalid(fields: [String])
    /// The server has no such item, or no such file (404).
    case notFound
    /// Another 409, with the server's code.
    case conflict(String)
    /// The server's preview doesn't hold exactly the job the user said yes to, so the app doesn't
    /// approve it.
    case previewMismatch
    /// A file the app was asked to fetch has a name it won't put in a path or URL, or the bytes
    /// that came back aren't the file the server described (size or SHA-256).
    case fileRefused
}

extension DoddyServerClient {
    /// A draft on the server; nothing runs. Checked against the job before it is returned (the job
    /// echoed back, and the digest recomputed here), so the digest the app approves is for exactly
    /// what the user said yes to.
    public func createStudioJob(_ job: StudioJob) async throws -> StudioPreview {
        let response = try await studioRequest(.post, "/v1/studio", body: try Self.json(job))
        guard response.status == 201, let preview = try? JSONDecoder().decode(StudioPreview.self, from: response.body)
        else { throw Self.studioError(from: response) }
        guard preview.matches(job) else { throw StudioError.previewMismatch }
        return preview
    }

    /// Approves exactly the job with this digest, and the server starts working on it. An answer
    /// that never came back (no reply, or a 500, 502 or 504 that may have come after the server
    /// queued it) is `unknown`, and nothing is approved again.
    public func approveStudioJob(_ id: UUID, digest: String) async throws -> StudioApproval {
        let unknown = StudioApproval(id: nil, state: StudioItemState.unknown.rawValue)
        let response: ServerResponse
        do {
            response = try await studioRequest(.post, "/v1/studio/\(Self.id(id))/approve",
                                               body: try Self.json(StudioDigestBody(digest: digest)), startsSomething: true)
        } catch is OutcomeUnknown {
            return unknown
        }
        if [500, 502, 504].contains(response.status) { return unknown }
        guard response.status == 202 else { throw Self.studioError(from: response) }
        // Accepted, but the body can't be read: the state isn't known, so it isn't reported as queued.
        guard let body = try? JSONDecoder().decode(StudioApprovalBody.self, from: response.body) else { return unknown }
        return StudioApproval(id: body.id, state: body.state)
    }

    /// Newest first; drafts left out.
    public func studioItems() async throws -> [StudioItemSummary] {
        let list: StudioList = try await studioJSON("/v1/studio")
        return list.items
    }

    public func studioItem(_ id: UUID) async throws -> StudioItem {
        try await studioJSON("/v1/studio/\(Self.id(id))")
    }

    /// One file's bytes, checked against what the server said about it (size and SHA-256) before
    /// they are returned. Only a plain file name is ever asked for.
    public func studioFile(_ id: UUID, _ file: StudioFile) async throws -> Data {
        guard file.hasSafeName else { throw StudioError.fileRefused }
        let response = try await studioRequest(.get, "/v1/studio/\(Self.id(id))/files/\(file.name)", body: nil, timeout: 60)
        guard response.status == 200 else { throw Self.studioError(from: response) }
        guard response.body.count == file.bytes, StudioFileCheck.sha256(response.body) == file.sha256.lowercased()
        else { throw StudioError.fileRefused }
        return response.body
    }

    /// A draft is deleted; a queued job never starts; a running one stops at its next step.
    public func cancelStudioJob(_ id: UUID) async throws {
        let response = try await studioRequest(.post, "/v1/studio/\(Self.id(id))/cancel", body: nil)
        guard response.status == 204 else { throw Self.studioError(from: response) }
    }

    /// Deletes the item and its files on the server. The server answers only after they read back
    /// as gone; the caller still reads the list back before saying "deleted" (`StudioDeleteRule`).
    /// A 404 means the server holds no such item, which is what was asked for.
    public func deleteStudioItem(_ id: UUID) async throws -> StudioDeletion {
        let response = try await studioRequest(.delete, "/v1/studio/\(Self.id(id))", body: nil)
        if response.status == 404 { return StudioDeletion(deleted: true, files: 0) }
        guard response.status == 200, let body = try? JSONDecoder().decode(StudioDeletion.self, from: response.body), body.deleted
        else { throw Self.studioError(from: response) }
        return body
    }

    // MARK: Plumbing

    private func studioRequest(_ method: HTTPMethod, _ path: String, body: Data?, startsSomething: Bool = false,
                               timeout: TimeInterval = ServerRequest.defaultTimeout) async throws -> ServerResponse {
        do {
            return try await authorized(method, path, body: body, startsSomething: startsSomething, timeout: timeout)
        } catch let error as ServerError {
            throw StudioError.server(error)
        }
    }

    private func studioJSON<T: Decodable>(_ path: String) async throws -> T {
        let response = try await studioRequest(.get, path, body: nil)
        guard response.status == 200, let value = try? JSONDecoder().decode(T.self, from: response.body)
        else { throw Self.studioError(from: response) }
        return value
    }

    static func studioError(from response: ServerResponse) -> StudioError {
        let body = try? JSONDecoder().decode(StudioRefusal.self, from: response.body)
        switch (response.status, body?.error ?? "") {
        case (409, "digest_mismatch"): return .digestMismatch
        case (409, "not_approvable"): return .notApprovable
        case (409, "too_many_open_items"): return .tooManyOpenItems
        case (409, "daily_cap_reached"): return .dailyCapReached(capUsd: body?.capUsd, spentUsd: body?.spentUsd)
        case (409, let code): return .conflict(code)
        case (503, "studio_disabled"): return .studioDisabled
        case (400, _): return .invalid(fields: body?.fields ?? [])
        case (404, _): return .notFound
        default: return .server(error(from: response))
        }
    }
}

private struct StudioDigestBody: Encodable { let digest: String }
private struct StudioApprovalBody: Decodable { let id: UUID?; let state: String }
private struct StudioList: Decodable { let items: [StudioItemSummary] }
private struct StudioRefusal: Decodable {
    let error: String?
    let fields: [String]?
    let capUsd: Double?
    let spentUsd: Double?
}
