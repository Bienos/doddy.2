import DoddyCore
import Foundation

/// Asks the Ministry of Finance's VAT register about one NIP (ADR-685), from this iPhone and only at
/// `VatRegister.url(for:on:)`, which DoddyCore builds from a NIP that passed its check digit. The
/// register asks for no key or account; the request carries the NIP and the app's name, nothing about
/// the user: ephemeral session, no cookies, no cache, redirects refused, a size cap, a 10 s timeout,
/// and at most `VatRegister.lookupsPerMinute` look-ups a minute (the register allows 100 a day).
/// Nothing is kept here; `VatRegister.read` decides what the answer means, and a page that isn't
/// the register's JSON (its bot check) is "couldn't check", never "not found".
/// `scripts/check_forbidden_capabilities.sh` allows URLSession here and nowhere else for the register.
///
/// Not run against the register from the app in this build: NOT COMPILED, not run on a device.
actor VatRegisterClient {
    static let shared = VatRegisterClient()

    private final class RefuseRedirects: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(
            _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest
        ) async -> URLRequest? {
            nil
        }
    }

    private let session: URLSession
    private var window = LookupWindow(limit: VatRegister.lookupsPerMinute, seconds: 60)

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = VatRegister.timeout
        session = URLSession(configuration: configuration)
    }

    func lookup(_ nip: Nip, on day: CalendarDate) async -> CompanyLookup {
        guard window.take(now: Date()) else { return .couldNotCheck }
        var request = URLRequest(url: VatRegister.url(for: nip, on: day), cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: VatRegister.timeout)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request, delegate: RefuseRedirects()),
              let http = response as? HTTPURLResponse else { return .couldNotCheck }
        return VatRegister.read(data, statusCode: http.statusCode, nip: nip, on: day)
    }
}
