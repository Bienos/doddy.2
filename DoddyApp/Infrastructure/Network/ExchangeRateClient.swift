import DoddyCore
import Foundation

/// Downloads the European Central Bank's daily euro reference rates (ADR-291), the one public
/// file at `ExchangeRateSource.url`. The request carries nothing about the user: no account, no
/// key, no amount. Ephemeral session, no cookies, redirects refused, a size cap. The last good
/// rates are kept on this iPhone (UserDefaults) so a conversion without a connection can still
/// answer, saying the rates' date. `scripts/check_forbidden_capabilities.sh` allows URLSession here.
actor ExchangeRateClient {
    static let shared = ExchangeRateClient()

    private struct Kept: Codable {
        let rates: ExchangeRates
        let fetchedAt: Date
    }

    private static let keptKey = "exchangeRates.lastKnown"

    private final class RefuseRedirects: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(
            _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest
        ) async -> URLRequest? {
            nil
        }
    }

    private let session: URLSession
    private var kept: Kept?

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 10
        session = URLSession(configuration: configuration)
        if let data = UserDefaults.standard.data(forKey: Self.keptKey) {
            kept = try? JSONDecoder().decode(Kept.self, from: data)
        }
    }

    /// Fresh rates when they can be fetched; otherwise the last ones kept (`isLastKnown`), or nil.
    func rates(now: Date = Date()) async -> (rates: ExchangeRates?, isLastKnown: Bool) {
        if let kept, !ExchangeRateSource.needsRefresh(fetchedAt: kept.fetchedAt, now: now) {
            return (kept.rates, false)
        }
        if let fresh = await fetch() {
            let entry = Kept(rates: fresh, fetchedAt: now)
            kept = entry
            if let data = try? JSONEncoder().encode(entry) { UserDefaults.standard.set(data, forKey: Self.keptKey) }
            return (fresh, false)
        }
        return (kept?.rates, kept != nil)
    }

    private func fetch() async -> ExchangeRates? {
        var request = URLRequest(url: ExchangeRateSource.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.httpMethod = "GET"
        guard let (data, response) = try? await session.data(for: request, delegate: RefuseRedirects()),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              data.count <= ExchangeRateSource.maxBytes,
              let text = String(data: data, encoding: .utf8) else { return nil }
        return ExchangeRateSource.parse(text)
    }
}
