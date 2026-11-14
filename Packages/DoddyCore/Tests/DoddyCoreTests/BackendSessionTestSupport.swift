import Foundation
import XCTest
@testable import DoddyCore

/// Shared by the backend account-session tests: a model of the backend's `POST /v1/session/account` and
/// `DELETE /v1/web/devices/:id` (`backend/src/accountSession.ts`, `devices.ts`), a record slot in memory, and a harness.
/// Every token is made up; none is a real credential.

/// A `ds1` token as the backend makes them: `ds1.<claims as base64url JSON>.<signature>`. The signature here is a
/// made-up word: the app never checks it, and the model server recognises its own tokens by lookup.
func fakeBackendToken(sub: String, dev: String?, acc: Bool, iat: Int = 1_800_000_000, exp: Int = 1_802_592_000) -> String {
    var claims: [String: Any] = ["v": 1, "sub": sub, "iat": iat, "exp": exp]
    if let dev { claims["dev"] = dev }
    if acc { claims["acc"] = 1 }
    let json = try! JSONSerialization.data(withJSONObject: claims, options: [.sortedKeys])
    let payload = json.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    return "ds1.\(payload).signature-not-real"
}

// MARK: A model of the backend

final class ModelBackendServer: HTTPTransport, @unchecked Sendable {
    struct Offline: Error {}
    enum Fault { case offline, status(Int, String) }
    struct Seen: Equatable {
        let method: String
        let path: String
        let bearer: String?
        let body: String?
    }

    static let thirtyDays: TimeInterval = 30 * 24 * 3_600

    private struct Row { let id: String; let account: String; var revoked: Bool }

    private let lock = NSLock()
    private var counter = 0
    private var supabase: [String: String] = [:]              // Supabase token -> account
    private var rows: [String: Row] = [:]                     // "account|device id" -> the stored iPhone
    private var sessions: [String: (row: String, account: String, expires: Date)] = [:]   // session token -> its row
    private var deviceSessions: Set<String> = []              // the iPhone's own earlier device sessions
    private var faults: [String: Fault] = [:]                 // "METHOD /route" -> what it answers instead
    private var log: [Seen] = []
    private var current = Date(timeIntervalSince1970: 1_800_000_000)
    /// Runs while a request to this route is "on its way".
    var duringRequest: (@Sendable (String) async -> Void)?

    // MARK: Setting it up

    func accept(_ supabaseToken: String, account: String = "account-1") { lock.withLock { supabase[supabaseToken] = account } }
    func revokeAllAccountTokens() { lock.withLock { supabase.removeAll() } }
    func addDeviceSession(_ token: String) { lock.withLock { _ = deviceSessions.insert(token) } }
    func fault(_ route: String, _ fault: Fault?) { lock.withLock { faults[route] = fault } }
    var now: Date {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }

    // MARK: Looking at it

    var seen: [Seen] { lock.withLock { log } }
    func count(_ route: String) -> Int { seen.filter { Self.route(method: $0.method, path: $0.path) == route }.count }

    /// The route a request is for: the revoke names the row in its path, so every row is the same route.
    static func route(method: String, path: String) -> String {
        method == "DELETE" && path.hasPrefix("/v1/web/devices/") ? "DELETE /v1/web/devices" : "\(method) \(path)"
    }
    /// How many stored iPhones are live (not revoked), counted over every account.
    var liveRows: Int { lock.withLock { rows.values.filter { !$0.revoked }.count } }
    /// Every session token that is accepted right now.
    func isLive(_ sessionToken: String) -> Bool { lock.withLock { liveRow(of: sessionToken) != nil } }
    /// Another account's or iPhone's revoke: ends the row the token names.
    func revokeRow(of sessionToken: String) {
        lock.withLock {
            guard let known = sessions[sessionToken] else { return }
            for (key, row) in rows where row.id == known.row { rows[key]?.revoked = true }
        }
    }
    func rowID(of sessionToken: String) -> String? { lock.withLock { sessions[sessionToken]?.row } }

    /// What an everyday route (`GET /v1/connected-apps`) answers to this bearer during the release that takes both kinds.
    func everydayStatus(for bearer: String) -> Int {
        lock.withLock { liveRow(of: bearer) != nil || supabase[bearer] != nil ? 200 : 401 }
    }

    private func liveRow(of token: String) -> Row? {
        guard let known = sessions[token], known.expires > current,
              let row = rows.values.first(where: { $0.id == known.row }), !row.revoked else { return nil }
        return row
    }

    /// A row id: a lowercase UUID, as the backend's are. Callers hold the lock.
    private func nextRowID() -> String {
        counter += 1
        let hex = String(counter, radix: 16)
        return "00000000-0000-4000-8000-" + String(repeating: "0", count: 12 - hex.count) + hex
    }

    // MARK: The routes

    func send(_ request: HTTPRequest) async throws -> (status: Int, body: Data) {
        let path = request.url.path
        let route = Self.route(method: request.method, path: path)
        let bearer = request.headers["authorization"].flatMap { $0.hasPrefix("Bearer ") ? String($0.dropFirst(7)) : nil }
        let body = request.body.flatMap { String(data: $0, encoding: .utf8) }
        lock.withLock { log.append(Seen(method: request.method, path: path, bearer: bearer, body: body)) }
        await duringRequest?(route)
        let answer: (Int, String) = try lock.withLock {
            if let fault = faults[route] {
                switch fault {
                case .offline: throw Offline()
                case .status(let status, let text): return (status, text)
                }
            }
            switch route {
            case "POST /v1/session/account": return exchange(bearer: bearer, body: request.body)
            case "DELETE /v1/web/devices": return revoke(bearer: bearer, id: String(path.dropFirst("/v1/web/devices/".count)))
            case "POST /v1/account/link-device/start":
                guard let bearer, deviceSessions.contains(bearer) else { return (401, #"{"error":{"code":"unauthenticated"}}"#) }
                return (200, #"{"linkCode":"\#(String(repeating: "a", count: 43))"}"#)
            case "GET /v1/connected-apps":
                guard let bearer, liveRow(of: bearer) != nil || supabase[bearer] != nil else { return (401, #"{"error":{"code":"unauthenticated"}}"#) }
                return (200, "{}")
            default: return (404, #"{"error":{"code":"not_found"}}"#)
            }
        }
        return (answer.0, Data(answer.1.utf8))
    }

    /// Callers hold the lock.
    private func exchange(bearer: String?, body: Data?) -> (Int, String) {
        guard let bearer, let account = supabase[bearer] else { return (401, #"{"error":{"code":"unauthenticated","message":"Sign-in is required."}}"#) }
        guard let json = (body.flatMap { try? JSONSerialization.jsonObject(with: $0) }) as? [String: Any], Set(json.keys) == ["deviceId"],
              let device = json["deviceId"] as? String, UUID(uuidString: device) != nil, device == device.lowercased()
        else { return (400, #"{"error":{"code":"invalid_request"}}"#) }
        let key = "\(account)|\(device)"
        var row = rows[key]
        // A live row is renewed (same id); no row, or a revoked one, gets a new id, as `Store.registerAccountDevice` does.
        if row == nil || row!.revoked { row = Row(id: nextRowID(), account: account, revoked: false) }
        rows[key] = row
        let issued = Int(current.timeIntervalSince1970)
        let expires = current.addingTimeInterval(Self.thirtyDays)
        let token = fakeBackendToken(sub: account, dev: row!.id, acc: true, iat: issued, exp: issued + Int(Self.thirtyDays))
            + "-\(counter)"   // a renewal is a new token
        counter += 1
        sessions[token] = (row!.id, account, expires)
        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return (200, #"{"token":"\#(token)","expiresAt":"\#(stamp.string(from: expires))","access":"full","deviceListId":"\#(row!.id)"}"#)
    }

    /// Callers hold the lock.
    private func revoke(bearer: String?, id: String) -> (Int, String) {
        guard let bearer, let row = liveRow(of: bearer) else { return (401, #"{"error":{"code":"unauthenticated"}}"#) }
        guard row.id == id else { return (404, #"{"error":{"code":"not_found"}}"#) }
        for (key, value) in rows where value.id == id { rows[key]?.revoked = true }
        return (200, #"{"revoked":true,"revokedAt":"2027-01-15T08:00:00.000Z"}"#)
    }
}

// MARK: Stores, in memory

final class RecordSlot: BackendSessionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var kept: BackendSessionRecord?
    var refusesToSave = false
    var record: BackendSessionRecord? { lock.withLock { kept } }
    func load() -> BackendSessionRecord? { lock.withLock { kept } }
    func save(_ record: BackendSessionRecord) -> Bool { lock.withLock { if refusesToSave { return false }; kept = record; return true } }
    func delete() -> Bool { lock.withLock { kept = nil; return true } }
    /// Puts a record there as an earlier launch left it.
    func put(_ record: BackendSessionRecord?) { lock.withLock { kept = record } }
}

let backendTestServer = URL(string: "https://backend.example.com")!
let otherBackendTestServer = URL(string: "https://other-backend.example.com")!
let backendTestDeviceID = "11111111-2222-4333-8444-555555555555"

/// What the sessions object reads from the test: held in a box of its own, so a try that is still on its way when a test
/// ends reads the box and never a harness that is gone.
@MainActor
final class BackendTestState {
    var deviceID: String? = backendTestDeviceID
    var currentServer: URL? = backendTestServer
    var clock = Date(timeIntervalSince1970: 1_800_000_000)
}

@MainActor
final class BackendTestHarness {
    let server = ModelBackendServer()
    let records = RecordSlot()
    let owed = OwedSlot()
    let account = SignedInAccount()
    private let state = BackendTestState()
    var sessions: BackendAccountSessions!

    var deviceID: String? {
        get { state.deviceID }
        set { state.deviceID = newValue }
    }
    var currentServer: URL? {
        get { state.currentServer }
        set { state.currentServer = newValue }
    }
    var clock: Date {
        get { state.clock }
        set {
            state.clock = newValue
            server.now = newValue
        }
    }

    init() {
        server.accept("supabase-1-not-real")
        server.accept("supabase-2-not-real")
        server.now = state.clock
        sessions = makeSessions()
    }

    /// A new object over the same stores: what the next launch has.
    func makeSessions() -> BackendAccountSessions {
        let state = self.state
        return BackendAccountSessions(
            records: records, owed: owed, accounts: account, endpoint: { state.currentServer },
            deviceID: { _ in state.deviceID }, transport: server, now: { state.clock })
    }

    func pass(_ seconds: TimeInterval) { clock = clock.addingTimeInterval(seconds) }
    func passDays(_ days: Double) { pass(days * 24 * 3_600) }
}
