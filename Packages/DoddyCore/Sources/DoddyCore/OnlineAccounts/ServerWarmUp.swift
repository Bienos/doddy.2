import Foundation

/// Wakes Doddy's server before anything needs it (ADR-670).
///
/// The backend runs on a free Render instance that sleeps when idle and takes about 20 seconds
/// to wake (docs/implementation/MESSAGES_STATUS.md), while the app gives a request 20 seconds.
/// So the first request after a quiet spell could time out. One `GET /v1/health` when Doddy
/// comes to the front starts the wake-up early. It sends no token and nothing of the user's,
/// and its answer is ignored: it only has to arrive.
public actor ServerWarmUp {
    public static let shared = ServerWarmUp()

    /// At most one ping in this many seconds: a server that was awake a few minutes ago still is.
    public static let minimumInterval: TimeInterval = 5 * 60

    private var lastPing: Date?
    private var pinging = false

    public init() {}

    /// Sends the ping unless one was sent in the last `minimumInterval` (or is still on its way).
    /// True when a ping was sent. Never throws: a failed ping changes nothing.
    @discardableResult
    public func wake(server: URL, transport: any HTTPTransport, now: Date = Date()) async -> Bool {
        guard server.scheme?.lowercased() == "https", let host = server.host, !host.isEmpty else { return false }
        guard !pinging else { return false }
        if let lastPing, now.timeIntervalSince(lastPing) < Self.minimumInterval { return false }
        lastPing = now
        pinging = true
        defer { pinging = false }
        let request = HTTPRequest(method: "GET", url: server.appendingPathComponent("v1/health"), headers: [:], body: nil)
        _ = try? await transport.send(request)
        return true
    }
}
