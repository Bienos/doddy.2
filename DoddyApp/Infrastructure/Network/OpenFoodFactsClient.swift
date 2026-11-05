import DoddyCore
import Foundation

/// Asks Open Food Facts what product a barcode is (Shopping list+, ADR-631), from this iPhone and
/// only at `OpenFoodFacts.productURL(for:)`, which DoddyCore builds from checked digits. The request
/// carries the barcode and the app's name (Open Food Facts asks every app to name itself), nothing
/// about the user: ephemeral session, no cookies, no cache, redirects refused, a size cap, a 10 s
/// timeout, and at most `OpenFoodFacts.lookupsPerMinute` look-ups a minute (Open Food Facts allows
/// 15 per IP address). Nothing is kept. `scripts/check_forbidden_capabilities.sh` allows URLSession here.
actor OpenFoodFactsClient {
    static let shared = OpenFoodFactsClient()

    enum Outcome: Equatable, Sendable {
        case found(OpenFoodFactsProduct)
        case notFound
        /// The app's own limit for a minute was reached; nothing was sent.
        case tooMany
        /// No connection, a timeout, an error or an answer that isn't Open Food Facts'.
        case failed
    }

    private final class RefuseRedirects: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(
            _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest
        ) async -> URLRequest? {
            nil
        }
    }

    private let session: URLSession
    private var window = LookupWindow(limit: OpenFoodFacts.lookupsPerMinute, seconds: 60)

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = OpenFoodFacts.timeout
        session = URLSession(configuration: configuration)
    }

    func product(for code: ProductBarcode, now: Date = Date()) async -> Outcome {
        guard window.take(now: now) else { return .tooMany }
        var request = URLRequest(url: OpenFoodFacts.productURL(for: code), cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: OpenFoodFacts.timeout)
        request.httpMethod = "GET"
        request.setValue(OpenFoodFacts.userAgent(appVersion: Self.appVersion), forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Open Food Facts answers an unknown product with 404 and the same JSON shape.
        guard let (data, response) = try? await session.data(for: request, delegate: RefuseRedirects()),
              let http = response as? HTTPURLResponse, http.statusCode == 200 || http.statusCode == 404,
              data.count <= OpenFoodFacts.maxBytes else { return .failed }
        switch OpenFoodFacts.parse(data, code: code) {
        case .found(let product): return .found(product)
        case .notFound: return .notFound
        case .unreadable: return .failed
        }
    }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1"
    }
}
