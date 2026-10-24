import DoddyCore
import Foundation

/// Asks InPost where a parcel is (Parcels, ADR-634), from this iPhone and only at
/// `InPostTracking.url(for:)`, which DoddyCore builds from a checked 24-digit number. InPost documents
/// that address as open: no account, no token, no key. The request carries the number and the app's
/// name, nothing about the user: ephemeral session, no cookies, no cache, redirects refused, a size
/// cap, a 10 s timeout, and at most `InPostTracking.lookupsPerMinute` look-ups a minute. Nothing is
/// kept here; ParcelTracker reads the answer. It is called only after the person's own act
/// (`ParcelLookupPolicy`), which ParcelTracker checks first.
/// `scripts/check_forbidden_capabilities.sh` allows URLSession here and nowhere else for InPost.
///
/// Not run against InPost from the app in this build: BLOCKED / NOT RUN on a device (INPOST_STATUS.md).
actor InPostTrackingClient: ParcelFetching {
    static let shared = InPostTrackingClient()

    private final class RefuseRedirects: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(
            _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest
        ) async -> URLRequest? {
            nil
        }
    }

    private let session: URLSession
    private var window = LookupWindow(limit: InPostTracking.lookupsPerMinute, seconds: 60)

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = InPostTracking.timeout
        session = URLSession(configuration: configuration)
    }

    func fetch(_ number: ParcelNumber) async -> ParcelFetch {
        guard window.take(now: Date()) else { return .tooMany }
        var request = URLRequest(url: InPostTracking.url(for: number), cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: InPostTracking.timeout)
        request.httpMethod = "GET"
        request.setValue(InPostTracking.userAgent(appVersion: Self.appVersion), forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Every HTTP answer is handed on with its code: ParcelTracker decides what 404, 400 and 429 mean,
        // because InPost's error bodies differ from its documentation.
        guard let (data, response) = try? await session.data(for: request, delegate: RefuseRedirects()),
              let http = response as? HTTPURLResponse,
              data.count <= InPostTracking.maxBytes else { return .failed }
        return .reply(data, statusCode: http.statusCode)
    }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1"
    }
}
