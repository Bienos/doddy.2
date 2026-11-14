import Foundation

// One token per server (decision 2026-11-12-one-token-per-server), the app's half for the voice server.
//
// This iPhone keeps ONE voice-server session for the signed-in Doddy account, apart from any older Apple voice session
// (`VoiceAuthSession`). The rules, UI-free and tested on Linux (`VoiceAccountSessionsTests`):
// - With no session, or one the server refused, ask `account-session` with a fresh Supabase token and keep the pair.
// - Renew an access token that ran out with the refresh token. The refresh token rotates: the new pair is kept every
//   time, the spent token is never sent again, and two asks at once make one refresh (a second use of the same token is
//   read by the server as a stolen one and ends the session).
// - When no session can be had (an older server, a limit, offline) the answer is nil, and nothing about that is
//   remembered: the caller sends the account's token as before this change, and the next start asks again.
// - Signing out forgets the pair here at once and writes the server's sign-out down as owed, in a slot of its own,
//   until the server answers (the pattern of `PendingDeviceRevocations`, DOD-08: nothing is called ended that the server
//   did not confirm; DOD-11: nothing of the session stays on this iPhone).
//
// The access and refresh tokens are kept together, in one Keychain slot (this device only), because the app's slot is the
// only place that knows which account a pair belongs to. They are used for nothing but this server's requests.

/// One voice session of the signed-in account, as it is kept.
public struct VoiceSessionPair: Codable, Equatable, Sendable {
    /// The Doddy account (the Supabase user id) the session was made for. A pair is only ever used for that account.
    public let accountID: String
    public let accessToken: String
    public let accessExpiresAt: Date
    public let refreshToken: String

    public init(accountID: String, accessToken: String, accessExpiresAt: Date, refreshToken: String) {
        self.accountID = accountID
        self.accessToken = accessToken
        self.accessExpiresAt = accessExpiresAt
        self.refreshToken = refreshToken
    }

    init(accountID: String, tokens: VoiceSessionTokens, at now: Date) {
        self.init(
            accountID: accountID, accessToken: tokens.accessToken,
            accessExpiresAt: now.addingTimeInterval(TimeInterval(tokens.expiresIn)), refreshToken: tokens.refreshToken)
    }

    /// True while the access token has more than `margin` left (as `VoiceAuthSession` reads its own).
    func isFresh(at now: Date, margin: TimeInterval = 30) -> Bool {
        accessExpiresAt.timeIntervalSince(now) > margin
    }
}

/// Where the pair is kept: the Keychain (this device only) in the app, memory in tests.
public protocol VoiceSessionPairStore: Sendable {
    func load() -> VoiceSessionPair?
    /// False when it couldn't be kept.
    func save(_ pair: VoiceSessionPair) -> Bool
    /// True when nothing is left.
    @discardableResult func delete() -> Bool
}

/// Who is signed in, and the Doddy account's own token for the exchange. The app answers from `DoddyAccountModel`.
@MainActor
public protocol VoiceAccountTokenSource {
    /// The signed-in account (its Supabase user id), or nil when signed out.
    var accountID: String? { get }
    /// An access token with time left for the signed-in account, refreshed first when needed; nil when there is none.
    func freshToken() async -> String?
    /// The voice server refused the token just sent: a new one now, once; nil when none could be had.
    func tokenAfterRefusal() async -> String?
}

@MainActor
public final class VoiceAccountSessions {
    private let pairs: any VoiceSessionPairStore
    private let owed: any PendingRevocationStore
    private let accounts: any VoiceAccountTokenSource
    private let endpoint: @MainActor () -> URL?
    private let transport: any HTTPTransport
    private let now: @MainActor () -> Date

    private var pair: VoiceSessionPair?
    private var loaded = false
    /// Changes at every sign-out: work that started before it never keeps anything (and what it made is ended).
    private var generation = 0
    private var nextID = 0
    private var flight: (id: Int, generation: Int, account: String, task: Task<String?, Never>)?
    private var pass: (id: Int, task: Task<Void, Never>)?

    public init(
        pairs: any VoiceSessionPairStore, owed: any PendingRevocationStore, accounts: any VoiceAccountTokenSource,
        endpoint: @escaping @MainActor () -> URL?, transport: any HTTPTransport,
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.pairs = pairs
        self.owed = owed
        self.accounts = accounts
        self.endpoint = endpoint
        self.transport = transport
        self.now = now
    }

    /// How many sign-outs are still owed to the voice server.
    public var owedCount: Int { owed.load().count }

    // MARK: Asking for the session

    /// The voice server's own access token for the signed-in account, with time left: the kept one, a renewed one, or
    /// a new session's. Nil when signed out or when no session could be had now; the caller then sends the account's
    /// token, exactly as before. Safe to call from anywhere, as often as wanted: asks at once share one request.
    public func accessToken() async -> String? {
        guard let account = accounts.accountID else { return nil }
        load()
        if let held = pair {
            if held.accountID != account {
                // Another account's session: never used for this one. Ended at the server like any session left behind.
                retire(held)
            } else if held.isFresh(at: now()) {
                return held.accessToken
            }
        }
        if let flight, flight.generation == generation, flight.account == account { return await flight.task.value }
        let started = generation
        nextID += 1
        let id = nextID
        // The request clears itself when it is done, in the same step, so a later ask never joins a finished one.
        let task = Task { @MainActor () -> String? in
            let token = await self.obtain(account: account, generation: started)
            if self.flight?.id == id { self.flight = nil }
            return token
        }
        flight = (id, started, account, task)
        return await task.value
    }

    /// The voice server refused this access token (a 401 at `/api/voice-token`): the pair is forgotten here at once, so
    /// the next ask makes a new session, and the old one is ended at the server (owed until it answers). A token that is
    /// no longer the kept pair's (a newer pair replaced it meanwhile) changes nothing.
    @discardableResult
    public func refused(_ accessToken: String) -> Task<Void, Never>? {
        load()
        guard let held = pair, held.accessToken == accessToken else { return nil }
        return retire(held)
    }

    // MARK: Signing out

    /// The Doddy account signed out (or another account took this iPhone over). The pair is gone from this iPhone before
    /// this returns; the server's sign-out is written down first and tried now, and again by `retryOwed` until the server
    /// answers. Nothing says the session ended until it did. The returned task is the first try, for tests.
    @discardableResult
    public func signedOut() -> Task<Void, Never> {
        generation += 1
        flight = nil
        load()
        let leaving = pair
        pair = nil
        let task = endLater(leaving?.refreshToken)
        pairs.delete()
        return task
    }

    /// Asks the voice server about every sign-out still owed: a refresh (the token's own proof) for a fresh access token,
    /// then `sign-out` with it. Owed no more once the server said it ended the session or no longer knows it; kept when
    /// it didn't answer. Needs no sign-in. One pass at a time. Returns how many are still owed.
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
        pair = pairs.load()
        loaded = true
    }

    /// Whether the account that asked is still the one signed in, in the same sign-in.
    private func stillCurrent(_ account: String, _ started: Int) -> Bool {
        generation == started && accounts.accountID == account
    }

    private func obtain(account: String, generation started: Int) async -> String? {
        guard let url = endpoint() else { return nil }
        if let held = pair, held.accountID == account {
            switch await VoiceSessionWire.refresh(endpoint: url, refreshToken: held.refreshToken, transport: transport) {
            case .rotated(let tokens):
                // The refresh token just used is spent. If it was owed meanwhile (a refused access token), it no longer is.
                dropOwed(held.refreshToken)
                guard stillCurrent(account, started) else { retireMinted(tokens); return nil }
                return keep(VoiceSessionPair(accountID: account, tokens: tokens, at: now())).accessToken
            case .refused:
                // The server no longer knows the session: nothing is left to end. A new one is made below, once.
                guard stillCurrent(account, started) else { return nil }
                pair = nil
                pairs.delete()
            case .unavailable:
                // Offline or busy says nothing about the session: it stays, and the account's token is used this time.
                return nil
            }
        }
        return await exchange(url, account: account, generation: started)
    }

    private func exchange(_ url: URL, account: String, generation started: Int) async -> String? {
        guard let token = await accounts.freshToken() else { return nil }
        var answer = await VoiceSessionWire.exchange(endpoint: url, accountToken: token, transport: transport)
        // The account's token ran out on its way: a new one, and one more try. Never a third.
        if answer == .accountRefused, let renewed = await accounts.tokenAfterRefusal() {
            answer = await VoiceSessionWire.exchange(endpoint: url, accountToken: renewed, transport: transport)
        }
        guard case .minted(let tokens) = answer else { return nil }
        guard stillCurrent(account, started) else { retireMinted(tokens); return nil }
        return keep(VoiceSessionPair(accountID: account, tokens: tokens, at: now())).accessToken
    }

    /// The new pair is the session from now on. If the Keychain won't take it, it works from memory for this launch, and
    /// what was kept (spent by the refresh, or replaced) is removed rather than left to be sent again.
    @discardableResult
    private func keep(_ next: VoiceSessionPair) -> VoiceSessionPair {
        pair = next
        if !pairs.save(next) { pairs.delete() }
        return next
    }

    /// A pair this iPhone is done with while the server may still hold the session: forgotten here, ended there.
    @discardableResult
    private func retire(_ held: VoiceSessionPair) -> Task<Void, Never> {
        pair = nil
        let task = endLater(held.refreshToken)
        pairs.delete()
        return task
    }

    /// A session the server made for work that was overtaken by a sign-out: never kept, ended.
    private func retireMinted(_ tokens: VoiceSessionTokens) {
        endLater(tokens.refreshToken)
    }

    /// Writes the sign-out down as owed (when there is a session to end), then tries it now. A token that couldn't even
    /// be written down is tried once anyway.
    @discardableResult
    private func endLater(_ refreshToken: String?) -> Task<Void, Never> {
        let tryOnce: String? = refreshToken.flatMap { owe($0) ? nil : $0 }
        return Task { @MainActor in
            if let tryOnce, let url = self.endpoint() { await self.end(tryOnce, at: url) }
            _ = await self.retryOwed()
        }
    }

    private func runPass() async {
        guard let url = endpoint() else { return }
        for token in owed.load() { await end(token, at: url) }
    }

    /// One owed sign-out. Gone from the list only on the server's own answer.
    private func end(_ token: String, at url: URL) async {
        switch await VoiceSessionWire.refresh(endpoint: url, refreshToken: token, transport: transport) {
        case .refused:
            dropOwed(token)   // the server no longer knows it: gone
        case .unavailable:
            return
        case .rotated(let tokens):
            // The token just used is spent: what is owed now is the new one, written down before the sign-out is tried.
            replaceOwed(token, with: tokens.refreshToken)
            switch await VoiceSessionWire.signOut(endpoint: url, accessToken: tokens.accessToken, transport: transport) {
            case .ended, .alreadyGone: dropOwed(tokens.refreshToken)
            case .unavailable: return
            }
        }
    }

    // MARK: The owed list

    /// False when it couldn't be written down.
    private func owe(_ token: String) -> Bool {
        var tokens = owed.load().filter { $0 != token }
        tokens.append(token)
        if tokens.count > PendingDeviceRevocations.maxKept { tokens.removeFirst(tokens.count - PendingDeviceRevocations.maxKept) }
        return owed.save(tokens)
    }

    private func replaceOwed(_ old: String, with new: String) {
        var tokens = owed.load().filter { $0 != old && $0 != new }
        tokens.append(new)
        if tokens.count > PendingDeviceRevocations.maxKept { tokens.removeFirst(tokens.count - PendingDeviceRevocations.maxKept) }
        _ = owed.save(tokens)
    }

    private func dropOwed(_ token: String) {
        let tokens = owed.load()
        guard tokens.contains(token) else { return }
        _ = owed.save(tokens.filter { $0 != token })
    }
}
