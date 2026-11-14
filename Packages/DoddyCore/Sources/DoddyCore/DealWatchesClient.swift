import Foundation

// The app's side of the deal watches (owner, 13 Nov 2026: "daj znać, gdy masło będzie poniżej 5 zł"; decision
// docs/decisions/2026-11-13-leaflet-results-and-deal-watches.md; contract schemas/fixtures/deal_watch_v1.json): four
// requests with the device's account token. Reading the list and a watch's matches changes nothing. Making a watch
// starts something the person would notice twice (a second watch, a second push), so a try whose answer never came
// back is `.outcomeUnknown`: never shown as saved, never sent again by itself (DOD-08); the person looks at the list.
// A delete that finds the watch already gone is a delete that worked: the server's own answer says it is not there.
// Failures are `DealWatchesError`s (a cancelled task still throws `CancellationError`).

/// Why a deal-watch request didn't do what was asked, with what the app can tell the person.
public enum DealWatchesError: Error, Equatable, Sendable {
    case server(ServerError)
    /// The server's schema refused a field (400 `invalid_request`), or the app refused it before sending (the same
    /// limits, `DealWatchRequest.validationIssues`): nothing was sent.
    case invalid(fields: [String])
    /// This account has the most watches the server allows (409 `too_many_watches`).
    case tooManyWatches
    /// The server holds the most watches it allows for everyone (409 `server_full`).
    case serverFull
    /// No such watch for this account (404 `not_found`).
    case notFound
    /// Deal watches are switched off on the server (503 `deal_watches_disabled`): nothing is kept or checked.
    case disabled
    /// The request may have reached the server but no readable answer came back: the watch may exist.
    case outcomeUnknown
}

extension DoddyServerClient {
    /// The account's watches, newest first.
    public func dealWatches() async throws -> DealWatchList {
        let response = try await dealWatchCall(.get, "/v1/deal-watches")
        guard response.status == 200, let list = try? JSONDecoder().decode(DealWatchList.self, from: response.body)
        else { throw Self.dealWatchError(from: response) }
        return list
    }

    /// Makes a watch. A request that breaks the contract's limits isn't sent. The answer is the watch as the server
    /// keeps it and what already matches (shown at once, never pushed). A 201 whose body can't be read is
    /// `.outcomeUnknown`: the watch was made, the app just can't show it, and it must not be made twice.
    public func createDealWatch(_ request: DealWatchRequest) async throws -> DealWatchCreated {
        let issues = request.validationIssues()
        guard issues.isEmpty else { throw DealWatchesError.invalid(fields: Self.uniqueFields(issues.map(\.field))) }
        let response = try await dealWatchCall(.post, "/v1/deal-watches", body: try Self.json(request), startsSomething: true)
        if response.status == 201 {
            guard let created = try? JSONDecoder().decode(DealWatchCreated.self, from: response.body) else { throw DealWatchesError.outcomeUnknown }
            return created
        }
        throw Self.dealWatchError(from: response)
    }

    /// What matches the watch in the catalog now, cheapest first, and when each chain was last read.
    public func dealWatchMatches(id: String) async throws -> DealWatchMatches {
        guard UUID(uuidString: id) != nil else { throw DealWatchesError.invalid(fields: ["id"]) }
        let response = try await dealWatchCall(.get, "/v1/deal-watches/\(id)/offers")
        guard response.status == 200, let matches = try? JSONDecoder().decode(DealWatchMatches.self, from: response.body)
        else { throw Self.dealWatchError(from: response) }
        return matches
    }

    /// Deletes the watch and what it found. Already gone (404) is done.
    public func deleteDealWatch(id: String) async throws {
        guard UUID(uuidString: id) != nil else { throw DealWatchesError.invalid(fields: ["id"]) }
        let response = try await dealWatchCall(.delete, "/v1/deal-watches/\(id)")
        guard response.status == 204 || response.status == 404 else { throw Self.dealWatchError(from: response) }
    }

    static func dealWatchError(from response: ServerResponse) -> DealWatchesError {
        let body = try? JSONDecoder().decode(DealWatchRefusalBody.self, from: response.body)
        switch (response.status, DealWatchRefusal(rawValue: body?.error ?? "")) {
        case (400, _): return .invalid(fields: body?.fields ?? [])
        case (404, .some(.notFound)): return .notFound
        case (409, .some(.tooManyWatches)): return .tooManyWatches
        case (409, .some(.serverFull)): return .serverFull
        case (503, .some(.disabled)): return .disabled
        default: return .server(error(from: response))
        }
    }

    private func dealWatchCall(_ method: HTTPMethod, _ path: String, body: Data? = nil, startsSomething: Bool = false) async throws -> ServerResponse {
        do {
            return try await authorized(method, path, body: body, startsSomething: startsSomething)
        } catch let error as ServerError {
            throw DealWatchesError.server(error)
        } catch is OutcomeUnknown {
            throw DealWatchesError.outcomeUnknown
        }
    }

    private static func uniqueFields(_ fields: [String]) -> [String] {
        var out: [String] = []
        for field in fields where !out.contains(field) { out.append(field) }
        return out
    }
}

private struct DealWatchRefusalBody: Decodable { let error: String?; let fields: [String]? }
