import DoddyCore
import Foundation

/// The app's only HTTP code: talks to the configured Doddy server for Connected Apps.
/// Ephemeral session: no cookies, no URL cache, nothing written to disk by URLSession.
/// Redirects are refused, so the bearer token can't follow one to another host (DOD-11).
struct URLSessionTransport: HTTPTransport {
    static let shared = URLSessionTransport()
    private static let maxResponseBytes = 512 * 1024
    /// How long a request waits for the server, unless it asks for longer (`HTTPRequest.timeout`).
    private static let usualWait: TimeInterval = 20
    /// The longest any request may ask for: `research_now`'s 45 s (`BackendOnlineAccountsClient.timeout(for:)`).
    private static let longestWait: TimeInterval = 45

    private final class RefuseRedirects: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(
            _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest
        ) async -> URLRequest? {
            nil
        }
    }

    private static func makeSession(wait: TimeInterval) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = wait
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }

    private let session = URLSessionTransport.makeSession(wait: URLSessionTransport.usualWait)
    /// Only for a request that asks to wait longer than usual, so the session's own limit and the request's agree and
    /// every other request keeps its 20 s.
    private let longSession = URLSessionTransport.makeSession(wait: URLSessionTransport.longestWait)

    func send(_ request: HTTPRequest) async throws -> (status: Int, body: Data) {
        let wait = min(max(request.timeout ?? Self.usualWait, 1), Self.longestWait)
        let chosen = wait > Self.usualWait ? longSession : session
        var urlRequest = URLRequest(url: request.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: wait)
        urlRequest.httpMethod = request.method
        for (name, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }
        urlRequest.httpBody = request.body
        let (data, response) = try await chosen.data(for: urlRequest, delegate: RefuseRedirects())
        guard let http = response as? HTTPURLResponse, data.count <= Self.maxResponseBytes else {
            throw URLError(.badServerResponse)
        }
        return (http.statusCode, data)
    }
}
