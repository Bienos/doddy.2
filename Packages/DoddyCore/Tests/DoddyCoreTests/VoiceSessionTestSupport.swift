import Foundation
import XCTest
@testable import DoddyCore

/// Shared by the voice-session tests: a model of the voice server's `/api/voice-auth` and `/api/voice-token`, stores in
/// memory and a signed-in account stand-in. Every token is made up.

// MARK: A model of the voice server's /api/voice-auth

final class ModelVoiceServer: HTTPTransport, @unchecked Sendable {
    struct Offline: Error {}
    enum Fault { case offline, status(Int, String) }
    struct Seen: Equatable { let action: String; let bearer: String?; let refreshToken: String? }

    private let lock = NSLock()
    private var counter = 0
    /// Supabase tokens the exchange accepts.
    private var accepted: Set<String> = []
    private var accessTokens: [String: String] = [:]          // access token -> session
    private var refreshTokens: [String: (session: String, used: Bool)] = [:]
    private var alive: Set<String> = []
    private var faults: [String: Fault] = [:]
    private var log: [Seen] = []
    /// Runs while a request of this action is "on its way".
    var duringRequest: (@Sendable (String) async -> Void)?

    func accept(_ supabaseToken: String) { lock.withLock { _ = accepted.insert(supabaseToken) } }
    func revokeAllAccountTokens() { lock.withLock { accepted.removeAll() } }
    func fault(_ action: String, _ fault: Fault?) { lock.withLock { faults[action] = fault } }
    var seen: [Seen] { lock.withLock { log } }
    func count(_ action: String) -> Int { seen.filter { $0.action == action }.count }
    var liveSessions: Int { lock.withLock { alive.count } }
    /// The access tokens of every session run out (ten minutes pass).
    func accessTokensRunOut() { lock.withLock { accessTokens.removeAll() } }
    /// The server ends everything, as `delete-conversations` does for an account.
    func endEverySession() { lock.withLock { alive.removeAll() } }

    /// What `/api/voice-token` answers to this bearer during the release that takes both kinds: a live session's access
    /// token, or a Supabase token the exchange would accept, gets 200; anything else 401. `refuseSessions` makes it refuse
    /// every session token (a server that has lost its sessions).
    var refuseSessions = false
    func voiceTokenStatus(for bearer: String) -> Int {
        lock.withLock {
            if let id = accessTokens[bearer] { return !refuseSessions && alive.contains(id) ? 200 : 401 }
            return accepted.contains(bearer) ? 200 : 401
        }
    }

    private func next(_ prefix: String) -> String { counter += 1; return "\(prefix)-\(counter)-not-real" }

    private func session(_ id: String) -> (String, String, Int) {
        let access = next("access"), refresh = next("refresh")
        accessTokens[access] = id
        refreshTokens[refresh] = (id, false)
        return (access, refresh, 600)
    }

    private func reply(_ triple: (String, String, Int)) -> (Int, String) {
        (200, #"{"accessToken":"\#(triple.0)","refreshToken":"\#(triple.1)","expiresIn":\#(triple.2)}"#)
    }

    func send(_ request: HTTPRequest) async throws -> (status: Int, body: Data) {
        let json = (try? JSONSerialization.jsonObject(with: request.body ?? Data()) as? [String: Any]) ?? [:]
        let action = json["action"] as? String ?? ""
        let bearer = request.headers["authorization"].flatMap { $0.hasPrefix("Bearer ") ? String($0.dropFirst(7)) : nil }
        let refreshToken = json["refreshToken"] as? String
        lock.withLock { log.append(Seen(action: action, bearer: bearer, refreshToken: refreshToken)) }
        await duringRequest?(action)
        let answer: (Int, String) = try lock.withLock {
            if let fault = faults[action] {
                switch fault {
                case .offline: throw Offline()
                case .status(let status, let text): return (status, text)
                }
            }
            switch action {
            case "account-session":
                guard let bearer, accepted.contains(bearer) else { return (401, #"{"error":"session_expired"}"#) }
                let id = next("session")
                alive.insert(id)
                return reply(session(id))
            case "refresh":
                guard let refreshToken, let known = refreshTokens[refreshToken], alive.contains(known.session) else {
                    return (401, #"{"error":"session_expired"}"#)
                }
                if known.used {
                    // A token that was already swapped for a newer one came back: the whole session ends.
                    alive.remove(known.session)
                    return (401, #"{"error":"session_expired"}"#)
                }
                refreshTokens[refreshToken] = (known.session, true)
                return reply(session(known.session))
            case "sign-out":
                guard let bearer, let id = accessTokens[bearer], alive.contains(id) else { return (401, #"{"error":"session_expired"}"#) }
                alive.remove(id)
                return (200, #"{"signedOut":true}"#)
            default:
                return (400, #"{"error":"unknown_action"}"#)
            }
        }
        return (answer.0, Data(answer.1.utf8))
    }
}

// MARK: Stores, in memory

final class PairSlot: VoiceSessionPairStore, @unchecked Sendable {
    private let lock = NSLock()
    private var kept: VoiceSessionPair?
    var refusesToSave = false
    var pair: VoiceSessionPair? { lock.withLock { kept } }
    func load() -> VoiceSessionPair? { lock.withLock { kept } }
    func save(_ pair: VoiceSessionPair) -> Bool { lock.withLock { if refusesToSave { return false }; kept = pair; return true } }
    func delete() -> Bool { lock.withLock { kept = nil; return true } }
}

final class OwedSlot: PendingRevocationStore, @unchecked Sendable {
    private let lock = NSLock()
    private var kept: [String] = []
    var refuses = false
    var tokens: [String] { lock.withLock { kept } }
    func load() -> [String] { lock.withLock { kept } }
    func save(_ tokens: [String]) -> Bool { lock.withLock { if refuses { return false }; kept = tokens; return true } }
}

@MainActor
final class SignedInAccount: VoiceAccountTokenSource {
    var accountID: String? = "account-1"
    var token: String? = "supabase-1-not-real"
    var tokenAfterRefusalValue: String? = "supabase-2-not-real"
    var freshCalls = 0
    var refusalCalls = 0
    func freshToken() async -> String? { freshCalls += 1; return token }
    func tokenAfterRefusal() async -> String? { refusalCalls += 1; return tokenAfterRefusalValue }
}

let voiceTestEndpoint = URL(string: "https://voice.example.com/api/voice-auth")!

@MainActor
final class VoiceTestHarness {
    let server = ModelVoiceServer()
    let pairs = PairSlot()
    let owed = OwedSlot()
    let account = SignedInAccount()
    var clock = Date(timeIntervalSince1970: 1_800_000_000)
    var sessions: VoiceAccountSessions!

    init() {
        server.accept("supabase-1-not-real")
        server.accept("supabase-2-not-real")
        sessions = makeSessions()
    }

    /// A new object over the same stores: what the next launch has.
    func makeSessions(endpointURL: URL? = voiceTestEndpoint) -> VoiceAccountSessions {
        VoiceAccountSessions(pairs: pairs, owed: owed, accounts: account, endpoint: { endpointURL }, transport: server, now: { [unowned self] in self.clock })
    }

    func tenMinutesPass() {
        clock = clock.addingTimeInterval(601)
        server.accessTokensRunOut()
    }
}

