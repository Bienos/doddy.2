import Foundation

// The app's side of price watches (server/messaging, docs/implementation/SHOPPING_WATCH.md, ADR-614), over
// the same transport and device token as errands. Like the rest of the client: nothing is reported as
// watching, stopped or deleted unless the server said so, and an approval that may have reached the server
// without an answer coming back is "unknown", never "offline, try again". Every error these calls throw is
// a `WatchError`.

extension DoddyServerClient {
    /// Making the draft makes the server read the shop's page once (robots.txt, then the page: up to 10 s
    /// each, SHOPPING_WATCH.md section 2), so the app waits longer than its default before calling it unanswered.
    public static let watchCreateTimeout: TimeInterval = 30

    /// A draft on the server; nothing is watched yet. A draft that breaks the contract's rules isn't sent.
    /// The server's preview is checked against the draft before it is returned (everything echoed back,
    /// the promise, and the digest recomputed here), so the digest the app approves is for exactly what
    /// the user was shown. A price already at or below the user's is never a draft, whichever side says so.
    public func createWatch(_ draft: PriceWatchDraft) async throws -> WatchPreview {
        let issues = draft.validationIssues()
        guard issues.isEmpty else {
            var fields: [String] = []
            for field in issues.map(\.field) where !fields.contains(field) { fields.append(field) }
            throw WatchError.invalid(fields: fields)
        }
        let response = try await watchRequest(.post, "/v1/watches", body: try Self.json(CreateWatchBody(draft)), timeout: Self.watchCreateTimeout)
        guard response.status == 201, let preview = try? JSONDecoder().decode(WatchPreview.self, from: response.body)
        else { throw Self.watchError(from: response) }
        guard preview.matches(draft) else { throw WatchError.previewMismatch }
        guard preview.currentMinor > preview.thresholdMinor else { throw WatchError.alreadyBelow(currentMinor: preview.currentMinor) }
        return preview
    }

    /// Approves exactly the draft with this digest, and the server starts watching. An answer that never
    /// came back (no reply, a 500, 502 or 504 that may have come after the server started it, or a reply
    /// that can't be read) is `unknown`, and nothing is approved again.
    public func approveWatch(_ id: UUID, digest: String) async throws -> WatchApproval {
        let response: ServerResponse
        do {
            response = try await watchRequest(.post, "/v1/watches/\(Self.id(id))/approve",
                                              body: try Self.json(WatchDigestBody(digest: digest)), startsSomething: true)
        } catch is OutcomeUnknown {
            return .unknown
        }
        if [500, 502, 504].contains(response.status) { return .unknown }
        guard response.status == 202 else { throw Self.watchError(from: response) }
        // Accepted, but the body can't be read or isn't about this watch: the state isn't known, so it
        // isn't reported as active.
        guard let body = try? JSONDecoder().decode(WatchApprovalBody.self, from: response.body), body.id == id else { return .unknown }
        return WatchApproval(id: body.id, state: body.state, endsAt: body.endsAt)
    }

    /// Newest first, at most 50; drafts left out.
    public func watches() async throws -> [WatchSummary] {
        let list: WatchList = try await watchJSON("/v1/watches")
        return list.watches
    }

    /// One watch. A draft reads as `draft`: the way to look up a watch whose approval had no answer.
    public func watch(_ id: UUID) async throws -> WatchSummary {
        try await watchJSON("/v1/watches/\(Self.id(id))")
    }

    /// Only an active watch can be stopped; the server answers `not_stoppable` otherwise.
    public func stopWatch(_ id: UUID) async throws {
        let response = try await watchRequest(.post, "/v1/watches/\(Self.id(id))/stop", body: nil)
        guard response.status == 204 else { throw Self.watchError(from: response) }
    }

    /// Removes the watch from the server in any state. A 404 means the server holds no such watch, which is
    /// what was asked for.
    public func deleteWatch(_ id: UUID) async throws {
        let response = try await watchRequest(.delete, "/v1/watches/\(Self.id(id))", body: nil)
        guard response.status == 204 || response.status == 404 else { throw Self.watchError(from: response) }
    }

    // MARK: Plumbing

    private func watchRequest(_ method: HTTPMethod, _ path: String, body: Data?, startsSomething: Bool = false,
                              timeout: TimeInterval = ServerRequest.defaultTimeout) async throws -> ServerResponse {
        do {
            return try await authorized(method, path, body: body, startsSomething: startsSomething, timeout: timeout)
        } catch let error as ServerError {
            throw WatchError.server(error)
        }
    }

    private func watchJSON<T: Decodable>(_ path: String) async throws -> T {
        let response = try await watchRequest(.get, path, body: nil)
        guard response.status == 200, let value = try? JSONDecoder().decode(T.self, from: response.body)
        else { throw Self.watchError(from: response) }
        return value
    }

    static func watchError(from response: ServerResponse) -> WatchError {
        let body = try? JSONDecoder().decode(WatchRefusal.self, from: response.body)
        switch (response.status, body?.error ?? "") {
        case (400, _): return .invalid(fields: body?.fields ?? [])
        case (404, _): return .notFound
        case (409, "not_approvable"): return .notApprovable(state: body?.state)
        case (409, "digest_mismatch"): return .digestMismatch
        case (409, "too_many_open_watches"): return .tooManyOpenWatches
        case (409, "not_stoppable"): return .notStoppable(state: body?.state)
        case (409, let code): return .conflict(code)
        case (422, "price_not_readable"): return .priceNotReadable(body?.reason ?? .unknown)
        case (422, "currency_mismatch"): return .currencyMismatch
        case (422, "already_below"): return .alreadyBelow(currentMinor: body?.currentMinor)
        case (429, _): return .rateLimited
        case (503, "watches_disabled"): return .watchesDisabled
        default: return .server(error(from: response))
        }
    }
}

/// Exactly the fields the server's schema takes (strict: nothing else is sent).
private struct CreateWatchBody: Encodable {
    let title: String
    let shop: String
    let url: String
    let thresholdMinor: Int
    let currency: String
    let language: String

    init(_ draft: PriceWatchDraft) {
        title = draft.title
        shop = draft.shop
        url = draft.url
        thresholdMinor = draft.thresholdMinor
        currency = draft.currency
        language = draft.language
    }
}

private struct WatchDigestBody: Encodable { let digest: String }
private struct WatchList: Decodable { let watches: [WatchSummary] }

private struct WatchApprovalBody: Decodable {
    let id: UUID
    let state: WatchState
    let endsAt: Date?

    private enum CodingKeys: String, CodingKey { case id, state, endsAt }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        state = try c.decode(WatchState.self, forKey: .state)
        endsAt = try c.serverDateIfPresent(.endsAt)
    }
}

/// The refusal's fields, each read on its own: a field of a shape this version doesn't know never turns a
/// known code into a generic failure.
private struct WatchRefusal: Decodable {
    let error: String?
    let fields: [String]?
    let reason: PriceUnreadableReason?
    let currentMinor: Int?
    let state: WatchState?

    private enum CodingKeys: String, CodingKey { case error, fields, reason, currentMinor, state }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        error = try? c.decodeIfPresent(String.self, forKey: .error)
        fields = try? c.decodeIfPresent([String].self, forKey: .fields)
        reason = try? c.decodeIfPresent(PriceUnreadableReason.self, forKey: .reason)
        currentMinor = try? c.decodeIfPresent(Int.self, forKey: .currentMinor)
        state = try? c.decodeIfPresent(WatchState.self, forKey: .state)
    }
}
