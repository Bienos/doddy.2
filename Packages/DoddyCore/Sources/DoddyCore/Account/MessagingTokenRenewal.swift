import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

// Decision 2026-11-12-account-and-device-tokens, step 5. A messaging-server device token of a Doddy account stops working
// 60 days unseen or 180 days after it was issued. Until now the iPhone found out by being refused: the first call after the end
// failed once, then the client signed in again. This renews the token by rotation (`POST /v1/accounts/sign-in` with the current
// device token) shortly before its end, with the account the app is signed in to, without asking the person.
//
// What is kept next to the token (`MessagingTokenRecord`) is only when it ends, which account answered, and when renewal was last
// tried. It holds no token: the record says which token it describes by a hash, so a token stored some other way (an older
// build, or the client's own sign-in after a refusal) is never given another token's end. An unknown end means "renew at the
// next chance".

/// What is known about the stored messaging token. Never holds the token itself.
public struct MessagingTokenRecord: Codable, Equatable, Sendable {
    /// Hash of the token `expiresAt` and `accountID` belong to.
    public var tokenFingerprint: String?
    /// When that token stops working however it is used (the server's `expiresAt`); nil when the server did not say.
    public var expiresAt: Date?
    /// The messaging account that answered with that token.
    public var accountID: String?
    /// When a renewal was last tried, answered or not.
    public var lastAttempt: Date?

    public init(tokenFingerprint: String? = nil, expiresAt: Date? = nil, accountID: String? = nil, lastAttempt: Date? = nil) {
        self.tokenFingerprint = tokenFingerprint
        self.expiresAt = expiresAt
        self.accountID = accountID
        self.lastAttempt = lastAttempt
    }
}

/// Where the record is kept: UserDefaults in the app (it holds nothing secret), memory in tests.
public protocol MessagingTokenRecordStore: Sendable {
    func load() -> MessagingTokenRecord
    func save(_ record: MessagingTokenRecord)
}

/// The signed-in Doddy account, as renewal needs it (`DoddyAccountModel` in the app).
@MainActor
public protocol MessagingRenewalAccount: AnyObject {
    var session: DoddyAccountSession? { get }
    /// Changes whenever the account signs out or another signs in.
    var identityEpoch: Int { get }
    func freshSession() async -> DoddyAccountSession?
    /// A new access token after the server refused the last one; `session` is the refreshed one afterwards.
    func refreshAfterRefusal() async throws -> String
}

extension DoddyAccountModel: MessagingRenewalAccount {}

@MainActor
public final class MessagingTokenRenewal {
    /// Renew when the token ends within this long. Not a setting. The server ends a token 180 days after it was issued, so
    /// fourteen days leaves the iPhone at least fourteen days of daily chances (launch and coming to the front) to get through
    /// one offline or unopened stretch, while a token is still rotated only about every 166 days. A longer window would rotate
    /// for no reason; a shorter one risks the end arriving first. The idle limit (60 days unseen) is not a concern: an iPhone
    /// that renews is, by that, seen.
    public static let renewWindow: TimeInterval = 14 * 86_400
    /// At most one try in this long, answered or not.
    public static let minimumInterval: TimeInterval = 86_400

    public enum Result: Equatable, Sendable {
        /// Not signed in, or the messaging server is not used for the account: nothing to do.
        case notApplicable
        /// No token stored: the next call signs in by itself.
        case noToken
        /// The token has more than `renewWindow` left.
        case notDue
        /// Tried less than a day ago.
        case tooSoon
        /// Another renewal is on its way.
        case alreadyRunning
        /// A fresh token is stored, with its end.
        case renewed
        /// Nothing changed: the old token is kept (offline, refused, a conflict, or the new one could not be stored).
        case kept
        /// The answer was for another account, or the account changed while the server answered: not stored.
        case refusedOtherAccount
    }

    private let server: () -> URL?
    private let inUse: () -> Bool
    private let tokens: any ServerCredentialStore
    private let records: any MessagingTokenRecordStore
    private let account: any MessagingRenewalAccount
    private let transport: any HTTPTransport
    private let now: () -> Date
    private let discard: (String) async -> Void
    private var running = false

    /// - `inUse`: true while the messaging server is used with the Doddy account (not an anonymous account).
    /// - `discard`: given a token the server issued that must not be kept, so it can be ended there (the app's
    ///   `PendingDeviceRevocations.revoke`).
    public init(
        server: @escaping () -> URL?, inUse: @escaping () -> Bool, tokens: any ServerCredentialStore,
        records: any MessagingTokenRecordStore, account: any MessagingRenewalAccount, transport: any HTTPTransport,
        now: @escaping () -> Date = Date.init, discard: @escaping (String) async -> Void
    ) {
        self.server = server
        self.inUse = inUse
        self.tokens = tokens
        self.records = records
        self.account = account
        self.transport = transport
        self.now = now
        self.discard = discard
    }

    /// A hash that tells which token a record describes.
    public static func fingerprint(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// The account signed out: nothing about its token is kept.
    public func forget() {
        records.save(MessagingTokenRecord())
    }

    /// The messaging sign-in the app already makes, keeping the token's end next to it. Answers exactly what
    /// `DoddyAccountLink.signInMessaging` does.
    public func signIn(server: URL, account: DoddyAccountSession, earlierDeviceToken: String?) async -> DoddyAccountLink.MessagingSignIn {
        let result = await DoddyAccountLink.signInMessagingWithExpiry(
            server: server, account: account, earlierDeviceToken: earlierDeviceToken, transport: transport)
        if case .signedIn(let accountID, let token) = result.outcome {
            var record = records.load()
            record.tokenFingerprint = Self.fingerprint(token)
            record.expiresAt = result.expiresAt
            record.accountID = accountID
            records.save(record)
        }
        return result.outcome
    }

    /// Renews the token when it is within `renewWindow` of its end (or its end is unknown), at most once a day, one at a time.
    @discardableResult
    public func renewIfDue() async -> Result {
        guard !running else { return .alreadyRunning }
        guard let url = server(), inUse(), let signedIn = account.session else { return .notApplicable }
        guard let stored = (try? tokens.load()) ?? nil else { return .noToken }
        let record = records.load()
        let end = record.tokenFingerprint == Self.fingerprint(stored) ? record.expiresAt : nil
        let current = now()
        if let end, end.timeIntervalSince(current) > Self.renewWindow { return .notDue }
        if let last = record.lastAttempt, current.timeIntervalSince(last) < Self.minimumInterval, last <= current { return .tooSoon }

        running = true
        defer { running = false }
        // Written down before the request, so an answer that never comes still counts as a try today.
        var tried = record
        tried.lastAttempt = current
        records.save(tried)

        let epoch = account.identityEpoch
        guard var session = await account.freshSession(), session.userID == signedIn.userID else { return .kept }
        var result = await DoddyAccountLink.signInMessagingWithExpiry(
            server: url, account: session, earlierDeviceToken: stored, transport: transport)
        if result.outcome == .accountRefused {
            // The account's own token was refused: a new one, once. A still-refused account is left to the existing path.
            guard (try? await account.refreshAfterRefusal()) != nil, let refreshed = account.session, refreshed.userID == signedIn.userID else { return .kept }
            session = refreshed
            result = await DoddyAccountLink.signInMessagingWithExpiry(
                server: url, account: session, earlierDeviceToken: stored, transport: transport)
        }
        guard case .signedIn(let accountID, let fresh) = result.outcome else { return .kept }

        // Another account's answer, or an account that changed meanwhile: never stored, and ended on the server.
        let stillThisAccount = account.session?.userID == signedIn.userID && account.identityEpoch == epoch
        let sameMessagingAccount = record.accountID == nil || record.accountID == accountID
        guard stillThisAccount, sameMessagingAccount else {
            await discard(fresh)
            return .refusedOtherAccount
        }
        // The client may have replaced the token while the server answered (its own sign-in after a refusal): that one stays.
        guard (try? tokens.load()) == stored else {
            await discard(fresh)
            return .kept
        }
        // Stored before anything uses it; only then is it counted as renewed, and the old one is not kept (DOD-08).
        guard (try? tokens.save(fresh)) != nil else { return .kept }
        var done = records.load()
        done.tokenFingerprint = Self.fingerprint(fresh)
        done.expiresAt = result.expiresAt
        done.accountID = accountID
        records.save(done)
        return .renewed
    }
}
