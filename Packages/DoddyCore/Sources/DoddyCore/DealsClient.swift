import Foundation

// The app's side of the leaflets (docs/implementation/SHOPPING.md section 2): one request,
// `POST /v1/deals/search`, with the device's account token like errands. It reads public leaflets
// and changes nothing anywhere, so it is sent once and never retried by itself: each try counts
// against the user's daily leaflet checks. Every error it throws is a `DealsError`.

/// Why the leaflets weren't checked, with what the app can tell the user.
public enum DealsError: Error, Equatable, Sendable {
    case server(ServerError)
    /// The server's schema refused a field (400 `invalid_request`), or the app refused it before
    /// sending (the same limits, `DealsRequest.validationIssues`).
    case invalid(fields: [String])
    /// The account's leaflet checks for today are used up (429 `daily_limit`).
    case dailyLimit
    /// Leaflets are switched off on the server (503 `deals_disabled`).
    case dealsDisabled
}

extension DoddyServerClient {
    /// The server reads every chain in parallel within about 25 s (SHOPPING.md), so the app waits
    /// longer than its default before calling it unanswered.
    public static let dealsTimeout: TimeInterval = 45

    /// This week's leaflets for these items. A request that breaks the contract's limits isn't
    /// sent. No answer (offline, or a timeout) is `.server(.offline)`: nothing changed anywhere, and
    /// the user can ask again.
    public func searchDeals(_ request: DealsRequest) async throws -> DealsResult {
        let issues = request.validationIssues()
        guard issues.isEmpty else {
            var fields: [String] = []
            for field in issues.map(\.field) where !fields.contains(field) { fields.append(field) }
            throw DealsError.invalid(fields: fields)
        }
        let response: ServerResponse
        do {
            response = try await authorized(.post, "/v1/deals/search", body: try Self.json(request), timeout: Self.dealsTimeout)
        } catch let error as ServerError {
            throw DealsError.server(error)
        }
        guard response.status == 200, let result = try? JSONDecoder().decode(DealsResult.self, from: response.body)
        else { throw Self.dealsError(from: response) }
        return result
    }

    static func dealsError(from response: ServerResponse) -> DealsError {
        let body = try? JSONDecoder().decode(DealsRefusal.self, from: response.body)
        switch (response.status, body?.error ?? "") {
        case (400, _): return .invalid(fields: body?.fields ?? [])
        case (429, "daily_limit"): return .dailyLimit
        case (503, "deals_disabled"): return .dealsDisabled
        default: return .server(error(from: response))
        }
    }
}

private struct DealsRefusal: Decodable { let error: String?; let fields: [String]? }
