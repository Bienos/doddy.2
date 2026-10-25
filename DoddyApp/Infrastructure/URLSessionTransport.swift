import DoddyCore
import Foundation

/// The app's only HTTP code: talks to the configured Doddy server for Connected Apps.
/// Ephemeral session: no cookies, no URL cache, nothing written to disk by URLSession.
/// Redirects are refused, so the bearer token can't follow one to another host (DOD-11).
struct URLSessionTransport: HTTPTransport {
    static let shared = URLSessionTransport()
    /// For the files Doddy's server made (decks, documents, spreadsheets; ADR-564, ADR-654): the
    /// default's 512 KB refused any deck over that (one with pictures), so it never opened from Files. The server
    /// keeps files up to 15 MB (`MAX_DOCUMENT_BYTES`); the same token and the same refusal of
    /// redirects, with a longer wait for a file on a mobile connection.
    static let documents = URLSessionTransport(maxResponseBytes: 16 * 1024 * 1024, timeout: 60)

    private let maxResponseBytes: Int
    private let timeout: TimeInterval

    init(maxResponseBytes: Int = 512 * 1024, timeout: TimeInterval = 20) {
        self.maxResponseBytes = maxResponseBytes
        self.timeout = timeout
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = timeout
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
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

    func send(_ request: HTTPRequest) async throws -> (status: Int, body: Data) {
        var urlRequest = URLRequest(url: request.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        urlRequest.httpMethod = request.method
        for (name, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }
        urlRequest.httpBody = request.body
        let (data, response) = try await session.data(for: urlRequest, delegate: RefuseRedirects())
        guard let http = response as? HTTPURLResponse, data.count <= maxResponseBytes else {
            throw URLError(.badServerResponse)
        }
        return (http.statusCode, data)
    }
}
