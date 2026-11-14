import DoddyCore
import Foundation

// Decision 2026-11-08-required-account: every Doddy user signs in with a Doddy account (Apple, Google or
// a code sent by email). The rules live in DoddyCore (`DoddyAccountModel`, `DoddyAccountClient`,
// `DoddyAccountLink`, tested on Linux). This file is the app's side:
// - where the accounts live (Info.plist), the Keychain and the browser sheet;
// - how each of Doddy's servers is used for the account.
//
// While a server isn't set up for Doddy accounts yet, the iPhone keeps signing in to it as before. The
// backend's device session and the messaging server's anonymous account keep working unchanged; the
// switch happens per server, once that server has said yes.

extension DoddyAccountModel {
    /// The app's one account.
    @MainActor static let shared: DoddyAccountModel = {
        let model = DoddyAccountModel(
            config: DoddyAccountSetup.config(), transport: URLSessionTransport.shared,
            store: DoddyAccountKeychain(), authenticator: SystemWebAuthenticator())
        model.afterSignIn = { session in
            // Whose data this iPhone holds is recorded first; nothing goes to an account that doesn't own it
            // (decision 2026-11-12-local-data-owner, `LocalDataOwnership.swift`).
            await DoddyAccountServers.claimLocalData()
            await DoddyAccountServers.bringEarlierData(session)
        }
        model.afterSignOut = {
            DoddyAccountServers.forgetAccountTokens()
            VoiceTokenWarmer.shared.clear()
            DoddyAccountServers.stopUploadsAfterSignOut()
        }
        return model
    }()
}

enum DoddyAccountSetup {
    /// Where Google's browser sign-in comes back: the app's own scheme (`CFBundleURLSchemes`).
    static let redirect = URL(string: "doddy://auth-callback")

    /// From Info.plist (`DoddyAccountsURL`, `DoddyAccountsPublishableKey`, both public), or nil when this
    /// build has no Doddy accounts set up: then nobody is asked to sign in, as before. UI-test launches
    /// (`-inMemoryStore`, or a per-test database with `-memoryTestID`, the same test-run rule as
    /// `AppLanguageStore`) have none, so their screens stay the same.
    static func config(bundle: Bundle = .main, arguments: [String] = ProcessInfo.processInfo.arguments) -> DoddyAccountConfig? {
        if arguments.contains("-inMemoryStore") || arguments.contains("-memoryTestID") { return nil }
        let address = (bundle.object(forInfoDictionaryKey: "DoddyAccountsURL") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let key = bundle.object(forInfoDictionaryKey: "DoddyAccountsPublishableKey") as? String
        return DoddyAccountConfig(projectURL: address.isEmpty ? nil : URL(string: address), publishableKey: key, redirectURL: redirect)
    }
}

/// How the backend and the messaging server are used for the signed-in account.
@MainActor
enum DoddyAccountServers {
    enum Kind: String { case backend, messaging }

    private static func key(_ kind: Kind, _ server: URL) -> String {
        "doddyAccount.\(kind.rawValue)Use.\(server.absoluteString)"
    }

    static func use(_ kind: Kind, _ server: URL, defaults: UserDefaults = .standard) -> DoddyAccountServerUse? {
        defaults.string(forKey: key(kind, server)).flatMap { DoddyAccountServerUse(rawValue: $0) }
    }

    private static func set(_ use: DoddyAccountServerUse, _ kind: Kind, _ server: URL, defaults: UserDefaults = .standard) {
        defaults.set(use.rawValue, forKey: key(kind, server))
    }

    /// Messaging-server tokens this iPhone signed out of but the server hasn't yet said it forgot (security
    /// audit 2026-11-09, finding 1). Written down before the token leaves the Keychain slot the app uses.
    static let revocations = PendingDeviceRevocations(store: ServerPendingRevocationStore(), transport: URLSessionTransport.shared)

    /// Asks the messaging server again about every token still owed a revocation. Needs no sign-in: the
    /// token itself is the proof, and it is used for nothing else.
    static func retryRevocations() async {
        guard revocations.count > 0, let server = ServerConfig.baseURL() else { return }
        await revocations.retry(server: server)
    }

    /// Whether the account that started some work waiting on a server is still the one signed in. Read
    /// `DoddyAccountModel.shared.identityEpoch` before the wait and pass it here after: false means the person
    /// signed out (or another account signed in) meanwhile, and the answer must not be kept.
    private static func stillSignedIn(since epoch: Int) -> Bool {
        let model = DoddyAccountModel.shared
        return model.isSignedIn && model.identityEpoch == epoch
    }

    // MARK: The first sign-in, and catching up

    /// After a new sign-in: the backend links this iPhone's earlier data (or says it takes accounts),
    /// and the messaging server signs this iPhone in to the account. Each answer decides how that
    /// server is used from now on; "try again later" leaves it as it was, for `catchUp`.
    static func bringEarlierData(_ session: DoddyAccountSession) async {
        // What the account is when this starts: anything kept below is dropped if that changed while a server answered.
        let epoch = DoddyAccountModel.shared.identityEpoch
        await retryRevocations()
        // A kept session's access token runs out after about an hour. Sent expired, the backend answers 401,
        // which reads as "doesn't take accounts yet" (and is remembered) or "nothing to link". Refresh first.
        guard let fresh = await DoddyAccountModel.shared.freshSession(), fresh.userID == session.userID else { return }
        await linkBackend(fresh, epoch: epoch)
        await signInMessaging(fresh, epoch: epoch)
    }

    /// At launch, signed in: a server that didn't answer before is asked again.
    static func catchUp() async {
        // First, signed in or not: a sign-out that couldn't reach the messaging server still owes it that.
        await retryRevocations()
        guard let session = DoddyAccountModel.shared.session else { return }
        await bringEarlierData(session)
    }

    private static func linkBackend(_ session: DoddyAccountSession, epoch: Int) async {
        guard let server = DeviceSession.serverURL(), use(.backend, server) != .account else { return }
        let earlier = KeychainSessionStore.read()?.token(for: server).flatMap { $0.hasPrefix("ds1.") ? $0 : nil }
        let decided: DoddyAccountServerUse?
        if let earlier {
            let outcome = await DoddyAccountLink.linkBackend(server: server, account: session, deviceToken: earlier, transport: URLSessionTransport.shared)
            decided = DoddyAccountServerUse.backend(after: outcome)
            // Never merged: the earlier data stays apart, and the person is told why (in the server's words).
            if case .conflict(let message) = outcome { DoddyAccountModel.shared.message = message }
        } else {
            decided = await DoddyAccountLink.probeBackend(server: server, account: session, transport: URLSessionTransport.shared)
        }
        guard let decided else { return }
        // The answer took a while (a sleeping server takes about 20 seconds): if the person signed out meanwhile,
        // it is not kept. Writing it now would put the signed-out account's token back (audit finding 2).
        guard stillSignedIn(since: epoch) else { return }
        set(decided, .backend, server)
        // From now on every backend client finds the account's token where it found the device's.
        if decided == .account { KeychainSessionStore.save(session.accessToken, issuedBy: server) }
    }

    private static func signInMessaging(_ session: DoddyAccountSession, epoch: Int) async {
        guard let server = ServerConfig.baseURL(), use(.messaging, server) != .account else { return }
        let store = ServerKeychainStore()
        let earlier = try? store.load()
        var outcome = await DoddyAccountLink.signInMessaging(
            server: server, account: session, earlierDeviceToken: earlier, transport: URLSessionTransport.shared)
        if outcome == .accountRefused, (try? await DoddyAccountModel.shared.refreshAfterRefusal()) != nil,
           let fresh = DoddyAccountModel.shared.session {
            outcome = await DoddyAccountLink.signInMessaging(
                server: server, account: fresh, earlierDeviceToken: earlier, transport: URLSessionTransport.shared)
        }
        switch outcome {
        case .signedIn(_, let deviceToken):
            // Signed out while the server was answering: the server made (or linked) a token for an account
            // this iPhone no longer has. It is not kept, and the server is told to forget it right away.
            guard stillSignedIn(since: epoch) else {
                await revocations.revoke(deviceToken, server: server)
                return
            }
            // Counted only once this iPhone kept its token (DOD-08).
            if (try? store.save(deviceToken)) != nil { set(.account, .messaging, server) }
        case .notSetUp, .conflict:
            // Not set up yet, or never merged: this iPhone's earlier account there stays in use.
            set(.notYet, .messaging, server)
        case .accountRefused, .retryLater:
            break
        }
    }

    // MARK: Tokens for the clients

    enum BackendToken {
        /// The account's token, fresh.
        case account(String)
        /// The backend takes the account, but no token could be had now (offline, or signed out).
        case unavailable
        /// The backend still uses this iPhone's device session.
        case deviceSession
    }

    /// What `DeviceSession` hands the backend clients. `afterRefusal`: the server said 401.
    static func backendToken(for server: URL, afterRefusal: Bool = false) async -> BackendToken {
        let model = DoddyAccountModel.shared
        guard model.isConfigured, use(.backend, server) == .account else { return .deviceSession }
        // Signed out: no token, and no device session behind the person's back either.
        guard model.isSignedIn else { return .unavailable }
        do throws(DoddyAccountError) {
            let token: String
            if afterRefusal {
                token = try await model.refreshAfterRefusal()
            } else {
                token = try await model.accessToken()
            }
            return .account(token)
        } catch {
            return .unavailable
        }
    }

    /// For the messaging client with no token: this iPhone's token for the account, or nil while the
    /// server doesn't take accounts yet (it then makes an anonymous account, as before).
    nonisolated static func messagingToken() async throws -> String? {
        try await messagingTokenOnMain()
    }

    private static func messagingTokenOnMain() async throws -> String? {
        let model = DoddyAccountModel.shared
        guard model.isConfigured, let server = ServerConfig.baseURL(), use(.messaging, server) == .account else { return nil }
        guard let session = model.session else { throw ServerError.accountMissing }
        let epoch = model.identityEpoch
        switch await DoddyAccountLink.signInMessaging(server: server, account: session, earlierDeviceToken: nil, transport: URLSessionTransport.shared) {
        case .signedIn(_, let token):
            // The caller stores what it is given: not for an account that signed out while the server answered.
            guard stillSignedIn(since: epoch) else {
                await revocations.revoke(token, server: server)
                throw ServerError.accountMissing
            }
            return token
        case .notSetUp: return nil
        case .conflict, .accountRefused, .retryLater: throw ServerError.offline
        }
    }

    /// For the voice token server: the account's token whenever this iPhone is signed in to a Doddy
    /// account. An older voice session kept in the Keychain from an earlier build no longer wins over it:
    /// it can be dead, and then a signed-in person was told "Your voice session expired" at the start
    /// (8 Nov 2026, decision 2026-11-08-voice-prefers-doddy-account). Signed out: nil, and the voice
    /// session is used as before.
    static func voiceAccountToken() async -> String? {
        let model = DoddyAccountModel.shared
        guard model.isSignedIn else { return nil }
        return try? await model.accessToken()
    }

    // MARK: Deleting the account

    /// Settings › Delete my Doddy account. Each step goes ahead only when the one before was confirmed,
    /// and nothing is called deleted that a server didn't confirm (DOD-08):
    /// 1. the messaging server deletes its account (phone number, updates);
    /// 1b. an account made with Apple has Sign in with Apple ended at Apple (`revokeApple`, decision
    ///    2026-11-09-apple-revoke-for-doddy-accounts); Apple failing is said at the end and doesn't stop the rest;
    /// 1c. the voice server deletes the account's voice conversations at ElevenLabs (`deleteVoiceConversations`, decision
    ///    2026-11-12-voice-conversations-per-account). Like the servers above, no answer stops here and leaves the person
    ///    signed in; an answer with some still pending goes on, and the end says so (`VoiceConversationErasure`);
    /// 2. the backend deletes what it keeps and, with it, the sign-in at the account service (its
    ///    cleanup queue, decision 2026-11-08-required-account), and disconnects the online accounts;
    /// 3. this iPhone's own voice account, if it still has one, is deleted the way it always was;
    /// 4. only then is this iPhone signed out. The welcome then asks for a sign-in again.
    /// The result goes in the account's message, which the sign-in sheet and Settings show.
    static func deleteAccount() async {
        let model = DoddyAccountModel.shared
        guard model.isSignedIn else { return }
        // Only a backend that takes the account knows its sign-in, so only it can delete that.
        // An answer remembered from a launch with a run-out token is asked again before it refuses anything.
        if let backend = DeviceSession.serverURL(), use(.backend, backend) != .account { await catchUp() }
        guard let backend = DeviceSession.serverURL(), use(.backend, backend) == .account else {
            model.message = NSLocalizedString("Doddy's server isn't set up for Doddy accounts yet, so it can't delete yours. Nothing was deleted. Try again later.", comment: "")
            return
        }
        if let messaging = ServerConfig.client(), let server = ServerConfig.baseURL() {
            // Decision 2026-11-12-account-deletion-truth: no token on this iPhone, or a refused one, is not "deleted".
            // The account's own token is minted and the delete tried once more; only a 204, or the server saying it
            // takes no Doddy accounts, counts (`AccountErasurePlan`).
            let outcome = await AccountErasurePlan.run(
                deleteWithStoredToken: { await messaging.deleteAccountWithStoredToken() },
                mintAccountToken: { await mintMessagingToken(server) },
                deleteWithToken: { token in await messaging.deleteAccount(withToken: token) })
            guard outcome.isConfirmed else {
                model.message = NSLocalizedString("Doddy's server didn't confirm deleting your messaging data, so nothing else was deleted and you're still signed in. Check your connection and try again.", comment: "")
                return
            }
            UserDefaults.standard.set(false, forKey: PreferenceKey.pushUpdatesOn)
            UserDefaults.standard.set(false, forKey: PreferenceKey.memoryCopyOn)
            UserDefaults.standard.set(false, forKey: PreferenceKey.textsToDoddyOn)
            MemoryCopySync.shared.stop()
        }
        // Before the backend removes the sign-in at the account service: the voice server checks the
        // account's token to end Sign in with Apple. A failure doesn't stop the deletion; it is said at the end.
        let appleLine = await revokeApple()
        // Also before the backend removes the sign-in: the voice server checks the account's token for this too.
        // Unlike Apple, this is Doddy's own server, so with no answer nothing more is deleted and the person stays
        // signed in to try again (asking again is harmless: it answers 0 and 0 once everything is gone).
        let conversations = await deleteVoiceConversations()
        guard conversations.mayContinue else {
            model.message = NSLocalizedString("Your messaging data was deleted, but Doddy's voice server didn't confirm deleting your voice conversations, so you're still signed in. Check your connection and try again.", comment: "")
            return
        }
        guard await DeviceSession.ensure(server: backend) else {
            model.message = NSLocalizedString("Your messaging data was deleted, but Doddy couldn't reach his server to delete the rest, so you're still signed in. Check your connection and try again.", comment: "")
            return
        }
        let outcome = await ServerAccountErasure.run()
        switch outcome {
        case .complete, .onlineAccountsPending:
            break
        case .notAvailable, .failed, .nothingThere:
            model.message = NSLocalizedString("Your messaging data was deleted, but Doddy's server didn't confirm deleting your account, so you're still signed in. Try again.", comment: "")
            return
        }
        let serverLine = ServerAccountErasure.message(for: outcome)
        // Not `VoiceAuthSession.deleteAccount`: that would ask the backend again, with a token it now refuses.
        var voiceLine: String?
        if VoiceAuthSession.shared.hasSavedSession { voiceLine = await VoiceAuthSession.shared.deleteVoiceAccountOnly() }
        let userID = model.session?.userID
        await model.signOut()
        if let userID { UserDefaults.standard.removeObject(forKey: appleRevokedKey(userID)) }
        // The agreement to keep voice conversations belonged to this account; the next one is asked again. Nothing
        // asks yet (`VoiceConsent.requiredVersion` is nil), so this only clears what was never written.
        VoiceConsent.withdraw()
        let done = NSLocalizedString("Your Doddy account was deleted and this iPhone is signed out. Notes on this iPhone stay.", comment: "")
        // Voice conversations are named as deleted only when the voice server confirmed all of them (DOD-08).
        let conversationsLine: String? = switch conversations.finalLine {
        case .deleted:
            NSLocalizedString("Your voice conversations were deleted.", comment: "")
        case .stillDeleting:
            NSLocalizedString("Some of your voice conversations are still being deleted. Doddy's server keeps trying every day until they're gone.", comment: "")
        case nil:
            nil
        }
        model.message = [done, serverLine, conversationsLine, voiceLine, appleLine].compactMap { $0 }.joined(separator: " ")
    }

    /// Step 1c of `deleteAccount`: the voice server deletes the account's voice conversations at ElevenLabs and answers
    /// counts. Sends the Doddy account's token and this iPhone's old per-install id (`PreferenceKey.voiceUserID`), so
    /// conversations from before the account's own user id existed are found too. No token, or no answer: not confirmed.
    private static func deleteVoiceConversations() async -> VoiceConversationErasure.Outcome {
        guard let token = try? await DoddyAccountModel.shared.accessToken() else { return .notConfirmed }
        let attempt = await VoiceAuthAPI.shared.deleteConversations(
            accountToken: token, installID: UserDefaults.standard.string(forKey: PreferenceKey.voiceUserID))
        return VoiceConversationErasure.outcome(attempt)
    }

    /// The Doddy account's own token for the messaging server, asked for with the account as after a sign-in
    /// (`POST /v1/accounts/sign-in`), for deleting its account there when this iPhone keeps no token or a refused
    /// one (decision 2026-11-12-account-deletion-truth). Used for that one delete and not kept. A refused account
    /// token is refreshed and asked once more, as `signInMessaging` does.
    private static func mintMessagingToken(_ server: URL) async -> AccountErasurePlan.Mint {
        let model = DoddyAccountModel.shared
        guard let session = await model.freshSession() else { return .failed }
        var answer = await DoddyAccountLink.signInMessaging(
            server: server, account: session, earlierDeviceToken: nil, transport: URLSessionTransport.shared)
        if answer == .accountRefused, (try? await model.refreshAfterRefusal()) != nil, let fresh = model.session {
            answer = await DoddyAccountLink.signInMessaging(
                server: server, account: fresh, earlierDeviceToken: nil, transport: URLSessionTransport.shared)
        }
        return AccountErasurePlan.Mint(answer)
    }

    // MARK: Sign in with Apple, ended when the account is deleted

    /// Decision 2026-11-09-apple-revoke-for-doddy-accounts (App Store 5.1.1(v)). Right after a Doddy
    /// account signs in with Apple, Apple's one-time code goes to the voice server, which keeps Apple's
    /// token sealed. Best effort: the sign-in has already counted, and a failure only means deleting the
    /// account can't end Sign in with Apple (the delete result then says how to do it by hand).
    static func linkAppleRevocation(identityToken: String, rawNonce: String, authorizationCode: String) async {
        guard let token = try? await DoddyAccountModel.shared.accessToken() else { return }
        _ = try? await VoiceAuthAPI.shared.linkApple(
            accountToken: token, identityToken: identityToken, rawNonce: rawNonce, authorizationCode: authorizationCode)
    }

    /// Set once Apple confirmed the revoke, so asking to delete again after a later step failed doesn't
    /// report a missing token as a failure. Removed when the deletion finishes.
    private static func appleRevokedKey(_ userID: String) -> String { "doddyAccount.appleRevoked.\(userID)" }

    /// The first step of deleting an account made with Apple: the voice server tells Apple to end the
    /// link. Nil when Apple confirmed it (now or on an earlier try), or the account didn't use Apple.
    /// Otherwise a line, shown at the end, saying how to remove Doddy in the Apple ID settings. Apple
    /// failing never keeps the account (ADR-524).
    private static func revokeApple() async -> String? {
        let model = DoddyAccountModel.shared
        guard let session = model.session, session.method == .apple else { return nil }
        let key = appleRevokedKey(session.userID)
        if UserDefaults.standard.bool(forKey: key) { return nil }
        if let token = try? await model.accessToken(),
           (try? await VoiceAuthAPI.shared.revokeApple(accountToken: token)) == true {
            UserDefaults.standard.set(true, forKey: key)
            return nil
        }
        return NSLocalizedString("Doddy couldn't end its Sign in with Apple link. To remove it yourself, open Settings, tap your name, then Sign in with Apple, choose Doddy and tap Stop Using Apple ID.", comment: "")
    }

    /// Signed out, or another account took this iPhone over: the account's tokens go from where the clients find
    /// them, and the messaging server is told to forget this iPhone (security audit 2026-11-09, finding 1).
    /// Local first and immediate; the server's side is written down as owed before the token leaves the
    /// Keychain slot the app uses, and tried now and again later until the server answers (`revocations`).
    static func forgetAccountTokens() {
        if let server = DeviceSession.serverURL(), use(.backend, server) == .account { KeychainSessionStore.delete() }
        guard let server = ServerConfig.baseURL(), use(.messaging, server) == .account else { return }
        let store = ServerKeychainStore()
        let token = try? store.load()
        if let token { revocations.add(token) }
        try? store.delete()
        guard let token else { return }
        Task { await revocations.revoke(token, server: server) }
    }
}

extension VoiceAuthSession {
    /// Whether a conversation may start, as far as accounts go (the voice-data consent is asked
    /// separately): the Doddy account, this iPhone's own voice account, or (Debug builds only,
    /// ADR-551) the developer's direct connection. The one rule for the voice screen, its gate, Home
    /// and the Dynamic Island.
    func hasVoiceAccess() -> Bool {
        isSignedIn || DoddyAccountModel.shared.isSignedIn || VoiceConfig.talksWithoutAccount
    }
}

extension DoddyAccountModel {
    /// `message` in the app's language. The model's own words are DoddyCore's English (tested there);
    /// each has its line in `DoddyAccountWords`, so the string catalogs carry it. Words from a server
    /// (an account that can't be linked) and the app's own lines are shown as they came.
    var shownMessage: String? {
        message.map { DoddyAccountWords.translated[$0] ?? $0 }
    }
}

enum DoddyAccountWords {
    static let translated: [String: String] = [
        DoddyAccountError.notConfigured.userMessage: NSLocalizedString("Sign-in isn't set up in this build of Doddy yet.", comment: ""),
        DoddyAccountError.invalidEmail.userMessage: NSLocalizedString("That doesn't look like an email address. Check it and try again.", comment: ""),
        DoddyAccountError.invalidCode.userMessage: NSLocalizedString("That code is wrong or has expired. Check it, or ask for a new one.", comment: ""),
        DoddyAccountError.rateLimited.userMessage: NSLocalizedString("Too many tries for now. Wait a minute, then try again.", comment: ""),
        DoddyAccountError.refused.userMessage: NSLocalizedString("That sign-in didn't work. Try again, or use another way to sign in.", comment: ""),
        DoddyAccountError.signedOut.userMessage: NSLocalizedString("You were signed out. Sign in again to keep using Doddy.", comment: ""),
        DoddyAccountError.offline.userMessage: NSLocalizedString("Doddy couldn't reach the sign-in service. Check your connection and try again.", comment: ""),
        DoddyAccountError.unavailable.userMessage: NSLocalizedString("The sign-in service had a problem. Try again in a moment.", comment: ""),
        "This iPhone couldn't keep your sign-in, so you aren't signed in. Try again.":
            NSLocalizedString("This iPhone couldn't keep your sign-in, so you aren't signed in. Try again.", comment: ""),
    ]
}
