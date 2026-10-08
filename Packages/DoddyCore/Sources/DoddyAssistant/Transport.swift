import Foundation

/// Minimal HTTP shapes so the client logic is testable without a network.
public struct HTTPRequest: Equatable, Sendable {
    public let url: URL
    public let method: String
    public let headers: [String: String]
    public let body: Data?

    public init(url: URL, method: String, headers: [String: String] = [:], body: Data? = nil) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }
}

public struct HTTPResponse: Equatable, Sendable {
    public let status: Int
    public let body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
}

/// Transport-level failures a transport must report in these terms.
/// Task cancellation must surface as `CancellationError`.
public enum TransportError: Error, Equatable, Sendable {
    case offline
    case timedOut
}

public protocol HTTPTransport: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}
