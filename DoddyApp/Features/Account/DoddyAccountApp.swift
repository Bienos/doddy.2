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
        model.afterSignIn = { session in await DoddyAccountServers.bringEarlierData(session) }
        model.afterSignOut = { DoddyAccountServers.forgetAccountTokens() }
        return model
    }()
}

enum DoddyAccountSetup {
    /// Where Google's browser sign-in comes back: the app's own scheme (`CFBundleURLSchemes`).
    static let redirect = URL(string: "doddy://auth-callback")

    /// From Info.plist (`DoddyAccountsURL`, `DoddyAccountsPublishableKey`, both public), or nil when this
    /// build has no Doddy accounts set up: then nobody is asked to sign in, as before. UI-test launches
    /// (`-inMemoryStore`) have none, so their screens stay the same.
    static func config(bundle: Bundle = .main, arguments: [String] = ProcessInfo.processInfo.arguments) -> DoddyAccountConfig? {
        if arguments.contains("-inMemoryStore") { return nil }
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

    // MARK: The first sign-in, and catching up

    /// After a new sign-in: the backend links this iPhone's earlier data (or says it takes accounts),
    /// and the messaging server signs this iPhone in to the account. Each answer decides how that
    /// server is used from now on; "try again later" leaves it as it was, for `catchUp`.
    static func bringEarlierData(_ session: DoddyAccountSession) async {
        await linkBackend(session)
        await signInMessaging(session)
    }

    /// At launch, signed in: a server that didn't answer before is asked again.
    static func catchUp() async {
        guard let session = DoddyAccountModel.shared.session else { return }
        await bringEarlierData(session)
    }

    private static func linkBackend(_ session: DoddyAccountSession) async {
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
        set(decided, .backend, server)
        // From now on every backend client finds the account's token where it found the device's.
        if decided == .account { KeychainSessionStore.save(session.accessToken, issuedBy: server) }
    }

    private static func signInMessaging(_ session: DoddyAccountSession) async {
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
        switch await DoddyAccountLink.signInMessaging(server: server, account: session, earlierDeviceToken: nil, transport: URLSessionTransport.shared) {
        case .signedIn(_, let token): return token
        case .notSetUp: return nil
        case .conflict, .accountRefused, .retryLater: throw ServerError.offline
        }
    }

    /// For the voice token server: the account's token, unless this iPhone still has its own voice
    /// session (which works whether or not the voice server takes accounts yet).
    static func voiceAccountToken() async -> String? {
        let model = DoddyAccountModel.shared
        guard model.isSignedIn, !VoiceAuthSession.shared.hasSavedSession else { return nil }
        return try? await model.accessToken()
    }

    // MARK: Deleting the account

    /// Settings › Delete my Doddy account. Each step goes ahead only when the one before was confirmed,
    /// and nothing is called deleted that a server didn't confirm (DOD-08):
    /// 1. the messaging server deletes its account (phone number, updates);
    /// 2. the backend deletes what it keeps and, with it, the sign-in at the account service (its
    ///    cleanup queue, decision 2026-11-08-required-account), and disconnects the online accounts;
    /// 3. this iPhone's own voice account, if it still has one, is deleted the way it always was;
    /// 4. only then is this iPhone signed out. The welcome then asks for a sign-in again.
    /// The result goes in the account's message, which the sign-in sheet and Settings show.
    static func deleteAccount() async {
        let model = DoddyAccountModel.shared
        guard model.isSignedIn else { return }
        // Only a backend that takes the account knows its sign-in, so only it can delete that.
        guard let backend = DeviceSession.serverURL(), use(.backend, backend) == .account else {
            model.message = NSLocalizedString("Doddy's server isn't set up for Doddy accounts yet, so it can't delete yours. Nothing was deleted. Try again later.", comment: "")
            return
        }
        if let messaging = ServerConfig.client() {
            do {
                try await messaging.deleteAccount()
            } catch {
                model.message = NSLocalizedString("Doddy's server didn't confirm deleting your messaging data, so nothing else was deleted and you're still signed in. Check your connection and try again.", comment: "")
                return
            }
            UserDefaults.standard.set(false, forKey: PreferenceKey.pushUpdatesOn)
            UserDefaults.standard.set(false, forKey: PreferenceKey.memoryCopyOn)
            UserDefaults.standard.set(false, forKey: PreferenceKey.textsToDoddyOn)
            MemoryCopySync.shared.stop()
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
        await model.signOut()
        let done = NSLocalizedString("Your Doddy account was deleted and this iPhone is signed out. Notes on this iPhone stay.", comment: "")
        model.message = [done, serverLine, voiceLine].compactMap { $0 }.joined(separator: " ")
    }

    /// Signed out: the account's tokens go from where the clients find them.
    static func forgetAccountTokens() {
        if let server = DeviceSession.serverURL(), use(.backend, server) == .account { KeychainSessionStore.delete() }
        if let server = ServerConfig.baseURL(), use(.messaging, server) == .account { try? ServerKeychainStore().delete() }
    }
}

extension VoiceAuthSession {
    /// Whether a conversation may start, as far as accounts go (the provider's consent is asked
    /// separately): the Doddy account, this iPhone's own voice account, or (Debug builds only,
    /// ADR-551) the developer's direct connection. The one rule for the voice screen, its gate, Home
    /// and the Dynamic Island.
    func hasVoiceAccess(for provider: VoiceProvider) -> Bool {
        isSignedIn || DoddyAccountModel.shared.isSignedIn || VoiceConfig.talksWithoutAccount(for: provider)
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
