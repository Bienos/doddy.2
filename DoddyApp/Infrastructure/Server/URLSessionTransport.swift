import DoddyCore
import Foundation

/// The app's only network code of its own. It talks to the Doddy server and no other host
/// (`scripts/check_forbidden_capabilities.sh` keeps URLSession inside this folder).
struct URLSessionTransport: ServerTransport {
    /// Server origin, e.g. `https://doddy-api.onrender.com`.
    let baseURL: URL

    func send(_ request: ServerRequest) async throws -> ServerResponse {
        guard let url = URL(string: request.path, relativeTo: baseURL)?.absoluteURL else {
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
        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else { throw ServerError.offline }
            return ServerResponse(status: http.statusCode, body: data)
        } catch let error as ServerError {
            throw error
        } catch {
            throw ServerError.offline
        }
    }
}
