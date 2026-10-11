import DoddyCore
import Foundation

/// The app's only HTTP code: talks to the configured Doddy server for Connected Apps.
/// Ephemeral session: no cookies, no URL cache, nothing written to disk by URLSession.
/// Redirects are refused, so the bearer token can't follow one to another host (DOD-11).
struct URLSessionTransport: HTTPTransport {
    static let shared = URLSessionTransport()
    private static let maxResponseBytes = 512 * 1024

    private final class RefuseRedirects: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(
            _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest
        ) async -> URLRequest? {
            nil
        }
    }

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    func send(_ request: HTTPRequest) async throws -> (status: Int, body: Data) {
        var urlRequest = URLRequest(url: request.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        urlRequest.httpMethod = request.method
        for (name, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }
        urlRequest.httpBody = request.body
        let (data, response) = try await session.data(for: urlRequest, delegate: RefuseRedirects())
        guard let http = response as? HTTPURLResponse, data.count <= Self.maxResponseBytes else {
            throw URLError(.badServerResponse)
        }
        return (http.statusCode, data)
    }
}
