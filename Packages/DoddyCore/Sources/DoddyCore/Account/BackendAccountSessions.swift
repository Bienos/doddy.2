import Foundation

// One token per server (decision 2026-11-12-one-token-per-server), the app's half for the backend `doddy`.
//
// This iPhone keeps ONE backend session for the signed-in Doddy account (a `ds1` token of 30 days, its `expiresAt` and the
// `deviceListId` of its row), apart from the earlier device session (`DeviceSession`, the iPhone's own). The rules, UI-free and
// tested on Linux (`BackendAccountSessionsTests`, `BackendSessionTokenTests`):
// - With no session, a session the backend refused (401), or one within two days of its end, ask `POST /v1/session/account`
//   with a FRESH Supabase token and keep the new one. Until then a session in hand still works and is used.
// - When no session can be had (a server without the route, one not set up for it, a limit, offline, an answer that isn't an
//   account session for this account) the answer is nil and nothing about it is written down: the caller sends the Supabase
//   token exactly as before this change, and the next launch asks again. Within one launch a failed exchange is not asked
//   again for a few minutes (an hour after a limit, which is the hour the server says), so a server that doesn't answer isn't
//   asked once more for every request.
// - Signing out forgets the session here at once and writes the end the backend still owes (`DELETE /v1/web/devices/:id`,
//   made with the iPhone's own session) down in a slot of its own, until the server confirms it (the pattern of
//   `VoiceAccountSessions`, DOD-08: nothing is called ended that the server did not confirm; DOD-11: nothing of the session
//   stays on this iPhone).
// - The session is for one account on one server: another account's, or another address's, is never used or sent there.
//
// The token is kept in a Keychain item of its own, with its expiry, its row and the account and server it belongs to, because
// the app's own slot (`KeychainSessionStore`, which the backend clients read) holds whichever token they send and knows nothing
// of these. The session is sent only to the backend's routes, never to the link routes (`BackendSessionToken`).

/// One backend account session, as it is kept.
public struct BackendSessionRecord: Codable, Equatable, Sendable {
    /// The Doddy account (the Supabase user id) the session was made for. A session is only ever used for that account.
    public let accountID: String
    /// `scheme://host:port` of the backend that made it (`BoundSessionToken`): it is sent only there.
    public let origin: String
    public let token: String
    /// The expiry the server wrote.
    public let expiresAt: Date
    /// This iPhone's stored row: what the sign-out names.
    public let deviceListID: String

    public init(accountID: String, origin: String, token: String, expiresAt: Date, deviceListID: String) {
        self.accountID = accountID
        self.origin = origin
        self.token = token
        self.expiresAt = expiresAt
        self.deviceListID = deviceListID
    }
}

/// Where the session is kept: the Keychain (this device only) in the app, memory in tests.
public protocol BackendSessionStore: Sendable {
    func load() -> BackendSessionRecord?
    /// False when it couldn't be kept.
    func save(_ record: BackendSessionRecord) -> Bool
    /// True when nothing is left.
    @discardableResult func delete() -> Bool
}

/// A session this iPhone signed out of and the backend hasn't yet confirmed it ended. Kept in the same kind of list as the
/// other servers' owed sign-outs (`PendingRevocationStore`, strings), one JSON text each.
public struct BackendOwedSession: Codable, Equatable, Sendable {
    public let origin: String
    public let token: String
    public let deviceListID: String
    public let expiresAt: Date

    init(_ record: BackendSessionRecord) {
        origin = record.origin
        token = record.token
        deviceListID = record.deviceListID
        expiresAt = record.expiresAt
    }

    init(origin: String, grant: BackendSessionGrant) {
        self.origin = origin
        token = grant.token
        deviceListID = grant.deviceListID
        expiresAt = grant.expiresAt
    }

    var encoded: String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) }
    }

    public static func decode(_ text: String) -> BackendOwedSession? {
        try? JSONDecoder().decode(BackendOwedSession.self, from: Data(text.utf8))
    }
}

@MainActor
public final class BackendAccountSessions {
    /// Ask for a new session this long before the one in hand ends (its tokens last 30 days).
    public static let renewBefore: TimeInterval = 2 * 24 * 3_600
    /// A session with less than this left is not used any more.
    static let usableMargin: TimeInterval = 60
    /// After an exchange that couldn't be done: not asked again in this launch for this long.
    static let pauseAfterFailure: TimeInterval = 300
    /// After a limit: the hour the server's own message names.
    static let pauseAfterLimit: TimeInterval = 3_600

    private let records: any BackendSessionStore
    private let owed: any PendingRevocationStore
    private let accounts: any VoiceAccountTokenSource
    private let endpoint: @MainActor () -> URL?
    private let deviceID: @MainActor (URL) -> String?
    private let transport: any HTTPTransport
    private let now: @MainActor () -> Date

    private var record: BackendSessionRecord?
    private var loaded = false
    /// Changes at every sign-out: work that started before it never keeps anything (and what it made is ended).
    private var generation = 0
    private var nextID = 0
    private var flight: (id: Int, generation: Int, account: String, origin: String, task: Task<String?, Never>)?
    private var pass: (id: Int, task: Task<Void, Never>)?
    private var pause: (account: String, origin: String, until: Date)?

    /// - `accounts`: who is signed in, and the Doddy account's own token for the exchange (the same stand-in the voice server's
    ///   session uses; the app answers from `DoddyAccountModel`).
    /// - `endpoint`: the backend's address now, for the ends still owed.
    /// - `deviceID`: this iPhone's device id for the exchange, or nil when this address isn't one the app may send it to
    ///   (ADR-720): then nothing is sent at all.
    public init(
        records: any BackendSessionStore, owed: any PendingRevocationStore, accounts: any VoiceAccountTokenSource,
        endpoint: @escaping @MainActor () -> URL?, deviceID: @escaping @MainActor (URL) -> String?, transport: any HTTPTransport,
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.records = records
        self.owed = owed
        self.accounts = accounts
        self.endpoint = endpoint
        self.deviceID = deviceID
        self.transport = transport
        self.now = now
    }

    /// How many sign-outs are still owed to the backend.
    public var owedCount: Int { owed.load().count }

    // MARK: Asking for the session

    /// The backend's own session token for the signed-in account on `server`, with time left: the one in hand, or a new one
    /// when there is none, it was refused, or it is near its end. Nil when signed out or when no session can be had now: the
    /// caller then sends the account's Supabase token, exactly as before. Safe to call from anywhere, as often as wanted:
    /// asks at once share one request.
    /// - `refused`: the token a backend request was just refused with (401). When it is the session in hand, the session is
    ///   forgotten and a new one made once (nothing is owed for it: the server said it doesn't take it). Any other token (a
    ///   newer session, the Supabase token) changes nothing about the session.
    public func token(for server: URL, refused: String? = nil) async -> String? {
        guard let account = accounts.accountID, let origin = BoundSessionToken.origin(of: server) else { return nil }
        load()
        if let held = record {
            if held.accountID != account || held.origin != origin {
                // Another account's, or another address's: never used here, never sent here. Ended where it was made.
                retire(held)
            } else if let refused, refused == held.token {
                forget()
            } else if isUsable(held) && !needsRenewal(held) {
                return held.token
            }
        }
        if let flight, flight.generation == generation, flight.account == account, flight.origin == origin { return await flight.task.value }
        if let pause, pause.account == account, pause.origin == origin, now() < pause.until { return inHand(account, origin) }
        let started = generation
        nextID += 1
        let id = nextID
        // The request clears itself when it is done, in the same step, so a later ask never joins a finished one.
        let task = Task { @MainActor () -> String? in
            let token = await self.obtain(server: server, account: account, origin: origin, generation: started)
            if self.flight?.id == id { self.flight = nil }
            return token
        }
        flight = (id, started, account, origin, task)
        return await task.value
    }

    /// The session in hand for `server`, if any, whoever it is for: what the link routes must never be sent
    /// (`BackendSessionToken.earlierDeviceSession`).
    public func heldToken(for server: URL) -> String? {
        load()
        guard let held = record, held.origin == BoundSessionToken.origin(of: server) else { return nil }
        return held.token
    }

    // MARK: Signing out

    /// The Doddy account signed out (or another account took this iPhone over, or its account was deleted). The session is
    /// gone from this iPhone before this returns; the backend's end is written down first and tried now, and again by
    /// `retryOwed` until the server answers. Nothing says the session ended until it did. The returned task is the first try,
    /// for tests.
    @discardableResult
    public func signedOut() -> Task<Void, Never> {
        generation += 1
        flight = nil
        pause = nil
        load()
        let leaving = record
        record = nil
        let task = endLater(leaving.map { BackendOwedSession($0) })
        records.delete()
        return task
    }

    /// Asks the backend about every end still owed: `DELETE /v1/web/devices/:id` with the session itself. Owed no more once
    /// the server said it ended the iPhone's row or no longer accepts the session; kept when it didn't answer. A session past
    /// its own expiry is dropped without asking: it ended by itself. Needs no sign-in. One pass at a time. Returns how many
    /// are still owed.
    @discardableResult
    public func retryOwed() async -> Int {
        while let running = pass { await running.task.value }
        nextID += 1
        let id = nextID
        let task = Task { @MainActor in
            await self.runPass()
            if self.pass?.id == id { self.pass = nil }
        }
        pass = (id, task)
        await task.value
        return owed.load().count
    }

    // MARK: The work

    private func load() {
        guard !loaded else { return }
        record = records.load()
        loaded = true
    }

    private func isUsable(_ held: BackendSessionRecord) -> Bool {
        held.expiresAt.timeIntervalSince(now()) > Self.usableMargin
    }

    private func needsRenewal(_ held: BackendSessionRecord) -> Bool {
        held.expiresAt.timeIntervalSince(now()) <= Self.renewBefore
    }

    /// The session in hand for this account and address, while it lasts: what is used when a new one can't be had now.
    private func inHand(_ account: String, _ origin: String) -> String? {
        guard let held = record, held.accountID == account, held.origin == origin, isUsable(held) else { return nil }
        return held.token
    }

    /// Whether the account that asked is still the one signed in, in the same sign-in.
    private func stillCurrent(_ account: String, _ started: Int) -> Bool {
        generation == started && accounts.accountID == account
    }

    private func obtain(server: URL, account: String, origin: String, generation started: Int) async -> String? {
        // The device id goes only where the app's policy lets it (ADR-720), and nothing is asked for before that.
        guard let device = deviceID(server) else { return inHand(account, origin) }
        guard let accountToken = await accounts.freshToken() else { return inHand(account, origin) }
        var answer = await BackendAccountSessionWire.exchange(
            server: server, accountID: account, accountToken: accountToken, deviceID: device, transport: transport)
        // The account's token ran out on its way: a new one, and one more try. Never a third.
        if answer == .accountRefused, let renewed = await accounts.tokenAfterRefusal() {
            answer = await BackendAccountSessionWire.exchange(
                server: server, accountID: account, accountToken: renewed, deviceID: device, transport: transport)
        }
        guard stillCurrent(account, started) else {
            // Signed out, or another account in, while the server answered: what it made is never kept, and is ended.
            if case .minted(let grant) = answer { retireMinted(grant, origin: origin) }
            return nil
        }
        switch answer {
        case .minted(let grant):
            let next = BackendSessionRecord(
                accountID: account, origin: origin, token: grant.token, expiresAt: grant.expiresAt, deviceListID: grant.deviceListID)
            guard isUsable(next) else {
                // Already over (a clock far apart from the server's): not kept, ended, and not asked for again at once.
                retireMinted(grant, origin: origin)
                holdOff(account, origin, Self.pauseAfterFailure)
                return inHand(account, origin)
            }
            pause = nil
            return keep(next).token
        case .rateLimited:
            holdOff(account, origin, Self.pauseAfterLimit)
        case .accountRefused, .unavailable:
            holdOff(account, origin, Self.pauseAfterFailure)
        }
        return inHand(account, origin)
    }

    /// Held in this launch only: the next launch asks again, whatever happened here.
    private func holdOff(_ account: String, _ origin: String, _ seconds: TimeInterval) {
        pause = (account, origin, now().addingTimeInterval(seconds))
    }

    /// The new session is the one from now on. If the Keychain won't take it, it works from memory for this launch, and what
    /// was kept (replaced) is removed rather than left behind.
    @discardableResult
    private func keep(_ next: BackendSessionRecord) -> BackendSessionRecord {
        record = next
        if !records.save(next) { records.delete() }
        return next
    }

    /// A session the server doesn't take any more, or that this iPhone no longer holds for another reason it needs nothing
    /// ended for: forgotten here.
    private func forget() {
        record = nil
        records.delete()
    }

    /// A session this iPhone is done with while the server may still hold it: forgotten here, ended there.
    @discardableResult
    private func retire(_ held: BackendSessionRecord) -> Task<Void, Never> {
        record = nil
        let task = endLater(BackendOwedSession(held))
        records.delete()
        return task
    }

    /// A session the server made for work that was overtaken by a sign-out: never kept, ended.
    private func retireMinted(_ grant: BackendSessionGrant, origin: String) {
        endLater(BackendOwedSession(origin: origin, grant: grant))
    }

    /// Writes the end down as owed (when there is a session to end), then tries it now. A session that couldn't even be written
    /// down is tried once anyway.
    @discardableResult
    private func endLater(_ session: BackendOwedSession?) -> Task<Void, Never> {
        let tryOnce: BackendOwedSession? = session.flatMap { owe($0) ? nil : $0 }
        return Task { @MainActor in
            if let tryOnce, let url = self.endpoint(), BoundSessionToken.origin(of: url) == tryOnce.origin {
                _ = await self.end(tryOnce, at: url)
            }
            _ = await self.retryOwed()
        }
    }

    private func runPass() async {
        // A session past its own expiry is over: nothing is asked about it.
        let current = now()
        for text in owed.load() {
            if let session = BackendOwedSession.decode(text), session.expiresAt <= current { dropOwed(text) }
        }
        guard let url = endpoint(), let origin = BoundSessionToken.origin(of: url) else { return }
        for text in owed.load() {
            // Unreadable here (kept as it is) and another address's (asked when that address is the one in use): not sent.
            guard let session = BackendOwedSession.decode(text), session.origin == origin else { continue }
            if await end(session, at: url) { dropOwed(text) }
        }
    }

    /// One owed end. True only on the server's own answer: it ended the iPhone's row, or it no longer accepts the session.
    private func end(_ session: BackendOwedSession, at url: URL) async -> Bool {
        switch await BackendAccountSessionWire.signOut(server: url, token: session.token, deviceListID: session.deviceListID, transport: transport) {
        case .ended, .alreadyGone: return true
        case .unavailable: return false
        }
    }

    // MARK: The owed list

    /// False when it couldn't be written down.
    private func owe(_ session: BackendOwedSession) -> Bool {
        guard let text = session.encoded else { return false }
        var items = owed.load().filter { $0 != text }
        items.append(text)
        if items.count > PendingDeviceRevocations.maxKept { items.removeFirst(items.count - PendingDeviceRevocations.maxKept) }
        return owed.save(items)
    }

    private func dropOwed(_ text: String) {
        let items = owed.load()
        guard items.contains(text) else { return }
        _ = owed.save(items.filter { $0 != text })
    }
}
