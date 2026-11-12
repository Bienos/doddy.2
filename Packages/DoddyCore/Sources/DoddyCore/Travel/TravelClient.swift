import Foundation

// The trip screen's "find my trips in Gmail" (TRAVEL_EMAILS.md): first the server's ask-first card
// (`POST v1/travel/prepare`), then, after the person's tap, one search (`POST v1/travel/scan`). The
// server keeps nothing; the bookings it answers with are saved on this iPhone (`TripStore`).

public struct TravelScanResponse: Codable, Equatable, Sendable {
    public let mode: ConnectedAppsMode
    public let emailsFound: Int
    public let emailsUnreadable: Int
    public let emailsNotTravel: Int
    public let bookings: [TravelBooking]
}

public protocol TravelClient: Sendable {
    func prepareScan() async throws(OnlineAccountsError) -> PrepareResult
    func scan(approvalId: UUID) async throws(OnlineAccountsError) -> TravelScanResponse
}

public struct BackendTravelClient: TravelClient {
    private let baseURL: URL
    private let sessionToken: @Sendable () -> String?
    private let transport: any HTTPTransport

    public init?(baseURL: URL, boundToken: @escaping @Sendable () -> BoundSessionToken?, transport: any HTTPTransport) {
        guard BackendConnectedAppsClient.isAllowed(baseURL) else { return nil }
        self.baseURL = baseURL
        self.sessionToken = { boundToken()?.token(for: baseURL) }
        self.transport = transport
    }

    public func prepareScan() async throws(OnlineAccountsError) -> PrepareResult {
        try await call("v1/travel/prepare", body: Body(approvalId: nil, timeZone: TimeZone.current.identifier))
    }

    public func scan(approvalId: UUID) async throws(OnlineAccountsError) -> TravelScanResponse {
        try await call("v1/travel/scan", body: Body(approvalId: approvalId.uuidString.lowercased(), timeZone: TimeZone.current.identifier))
    }

    struct Body: Encodable, Equatable {
        let approvalId: String?
        let timeZone: String

        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeIfPresent(approvalId, forKey: .approvalId)
            try c.encode(timeZone, forKey: .timeZone)
        }
        enum CodingKeys: String, CodingKey { case approvalId, timeZone }
    }

    private func call<Response: Decodable>(_ path: String, body: Body) async throws(OnlineAccountsError) -> Response {
        guard let token = sessionToken(), !token.isEmpty else { throw .notConfigured }
        let data: Data
        do { data = try JSONEncoder().encode(body) } catch { throw .transport("encoding") }
        let request = HTTPRequest(
            method: "POST", url: baseURL.appendingPathComponent(path),
            headers: ["authorization": "Bearer \(token)", "accept": "application/json", "content-type": "application/json"], body: data)
        let status: Int, payload: Data
        do { (status, payload) = try await transport.send(request) } catch { throw .transport(String(describing: type(of: error))) }
        return try BackendOnlineAccountsClient.decode(status: status, data: payload)
    }
}

/// What the trip screen says when a search can't run, from the server's error code. Polish and English.
public enum TravelScanProblem: Equatable, Sendable {
    case gmailNotConnected, readingEmailsOff, notSetUp, dailyLimit, askAgain, unavailable

    public init(_ error: OnlineAccountsError) {
        switch error {
        case let .server(code, _, _, receipt):
            if receipt?.errorCode == "ask_first_required" { self = .askAgain; return }
            switch code {
            case "not_connected", "connection_expired", "permission_insufficient": self = .gmailNotConnected
            case "capability_disabled": self = .readingEmailsOff
            case "live_not_configured": self = .notSetUp
            case "quota_exceeded", "rate_limited": self = .dailyLimit
            default: self = .unavailable
            }
        case .notConfigured: self = .notSetUp
        default: self = .unavailable
        }
    }

    public func text(polish: Bool) -> String {
        switch self {
        case .gmailNotConnected:
            polish ? "Gmail nie jest podłączony. Podłącz go w Ustawieniach › Konta online i spróbuj jeszcze raz."
                : "Gmail isn't connected. Connect it in Settings › Online accounts and try again."
        case .readingEmailsOff:
            polish ? "Czytanie maili jest wyłączone dla Gmaila. Włącz „Przeczytaj maila” w Ustawieniach › Konta online › Gmail."
                : "Reading emails is off for Gmail. Turn on “Read an email” in Settings › Online accounts › Gmail."
        case .notSetUp:
            polish ? "Szukanie rezerwacji nie jest jeszcze włączone na serwerze Doddy'ego." : "Finding bookings isn't set up on Doddy's server yet."
        case .dailyLimit:
            polish ? "Na dziś wyczerpany limit. Spróbuj jutro." : "Today's limit is used up. Try again tomorrow."
        case .askAgain:
            polish ? "Ta zgoda już wygasła. Dotknij jeszcze raz, żeby zacząć od nowa." : "That yes has expired. Tap again to start over."
        case .unavailable:
            polish ? "Nie udało się przeszukać Gmaila. Nic nie zostało zmienione; spróbuj za chwilę." : "Couldn't search Gmail. Nothing was changed; try again in a moment."
        }
    }
}
