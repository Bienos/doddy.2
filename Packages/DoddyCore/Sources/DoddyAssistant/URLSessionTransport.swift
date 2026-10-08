import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The only file in the package allowed to touch the system network stack
/// (scripts/check_forbidden_capabilities.sh excludes exactly this filename).
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession
    private let timeout: TimeInterval

    public init(timeout: TimeInterval = 30) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.waitsForConnectivity = false
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        session = URLSession(configuration: configuration)
        self.timeout = timeout
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url, timeoutInterval: timeout)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (name, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }
        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else { throw TransportError.offline }
            return HTTPResponse(status: http.statusCode, body: data)
        } catch let error as URLError {
            switch error.code {
            case .cancelled: throw CancellationError()
            case .timedOut: throw TransportError.timedOut
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .cannotFindHost, .cannotConnectToHost:
                throw TransportError.offline
            default: throw error
            }
        }
    }
}
