import DoddyCore
import Foundation

/// The app's only HTTP client (`scripts/check_forbidden_capabilities.sh` allows URLSession here and nowhere else).
/// Ephemeral session: no cookies, no URL cache, nothing written to disk.
struct AppHTTPTransport: HTTPTransport {
    private let session: URLSession

    /// The gateway never redirects. Refusing redirects means the bearer token can't follow one elsewhere.
    private final class RefuseRedirects: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(
            _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    func send(_ request: HTTPRequest) async throws(TransportFailure) -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: request.timeout)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (name, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest, delegate: RefuseRedirects())
        } catch let error as URLError {
            throw Self.failure(for: error)
        } catch is CancellationError {
            throw .cancelled
        } catch {
            throw .other
        }

        guard let http = response as? HTTPURLResponse else { throw .other }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let key = key as? String, let value = value as? String { headers[key.lowercased()] = value }
        }
        return HTTPResponse(status: http.statusCode, headers: headers, body: data)
    }

    static func failure(for error: URLError) -> TransportFailure {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            .offline
        case .timedOut:
            .timedOut
        case .cancelled:
            .cancelled
        default:
            .other
        }
    }
}
