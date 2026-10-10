import DoddyCore
import Foundation

/// HTTP to the Doddy messaging server (`server/messaging`) and no other host
/// (`scripts/check_forbidden_capabilities.sh` allows URLSession in this file). Same settings as
/// `AppHTTPTransport`: ephemeral session, no cookies or cache, redirects refused so the bearer
/// token can't follow one elsewhere, and a response size ceiling.
struct ServerHTTPTransport: ServerTransport {
    /// Server origin, e.g. `https://doddy-messaging.onrender.com`.
    let baseURL: URL

    private final class RefuseRedirects: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(
            _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest
        ) async -> URLRequest? {
            nil
        }
    }

    private static let maxResponseBytes = 512 * 1024

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    func send(_ request: ServerRequest) async throws -> ServerResponse {
        guard let url = URL(string: request.path, relativeTo: baseURL)?.absoluteURL, url.host() == baseURL.host() else {
            throw ServerError.unexpected(status: 0)
        }
        var urlRequest = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        urlRequest.httpMethod = request.method.rawValue
        if let body = request.body {
            urlRequest.httpBody = body
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let token = request.bearerToken {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await Self.session.data(for: urlRequest, delegate: RefuseRedirects())
        } catch {
            throw ServerError.offline
        }
        guard let http = response as? HTTPURLResponse, data.count <= Self.maxResponseBytes else {
            throw ServerError.unexpected(status: 0)
        }
        return ServerResponse(status: http.statusCode, body: data)
    }
}
