import Foundation

/// A request that carries a bearer token is answered by the server it was sent to, and by no other
/// (decision 2026-11-12-local-data-owner). The app's transports refuse redirects, so the token never follows
/// one; this is the check after the answer: one whose address isn't the request's is not read.
/// `ServerHTTPTransport` checks the request side the same way for the messaging server.
public enum BearerHost {
    /// True when `answered` (the response's URL) has the scheme, host and port of `asked`. A missing URL is
    /// not the same server.
    public static func answered(_ answered: URL?, sameAs asked: URL) -> Bool {
        guard let answered, let left = Origin(answered), let right = Origin(asked) else { return false }
        return left == right
    }

    private struct Origin: Equatable {
        let scheme: String
        let host: String
        let port: Int?

        init?(_ url: URL) {
            guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: true),
                  let scheme = parts.scheme?.lowercased(), let host = parts.host?.lowercased(), !host.isEmpty
            else { return nil }
            self.scheme = scheme
            self.host = host
            port = parts.port ?? Self.defaultPort[scheme]
        }

        private static let defaultPort = ["https": 443, "http": 80]
    }
}
