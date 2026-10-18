import AuthenticationServices
import Foundation
import SwiftUI

// Sign in with Apple for the DODDY voice account (ADR-483). Outside Connected Apps, this is the only
// file that imports AuthenticationServices, and it uses only Apple's own sign-in sheet, the
// credential-state check and the revocation notice: no web authentication session and no web
// view (the capability guard refuses both here). Doddy asks Apple for no name or email, so the
// request never sets requested scopes (the guard refuses that too). The identity token goes only to
// VoiceAuthAPI in VoiceTokenClient.swift.

/// Apple's answer after the sign-in sheet closes.
enum AppleSignInResult {
    /// Apple's signed identity token and its stable user ID for this app.
    case signedIn(identityToken: String, userID: String)
    /// Apple finished without an Apple ID identity token, so there is nothing to send.
    case noToken
    case canceled
    case failed
}

/// Apple's Sign in with Apple button. `onRequest` returns the hashed nonce for this request, or nil
/// when it couldn't make one.
struct AppleSignInButton: View {
    let onRequest: () -> String?
    let onCompletion: (AppleSignInResult) -> Void

    var body: some View {
        SignInWithAppleButton(.signIn, onRequest: { request in
            if let hashedNonce = onRequest() { request.nonce = hashedNonce }
        }, onCompletion: { result in
            onCompletion(Self.result(result))
        })
        .signInWithAppleButtonStyle(.black)
    }

    private static func result(_ result: Result<ASAuthorization, Error>) -> AppleSignInResult {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let data = credential.identityToken,
                  let identityToken = String(data: data, encoding: .utf8) else { return .noToken }
            return .signedIn(identityToken: identityToken, userID: credential.user)
        case .failure(let error):
            return (error as? ASAuthorizationError)?.code == .canceled ? .canceled : .failed
        }
    }
}

/// Not main-actor isolated on purpose: Apple may call the credential-state completion on any queue,
/// and a main-actor closure called there would trip Swift 6's isolation check.
enum AppleSignIn {
    /// Asks Apple whether this Apple ID still authorizes Doddy (false when revoked, not found or transferred).
    static func isStillAuthorized(userID: String) async throws -> Bool {
        let state: ASAuthorizationAppleIDProvider.CredentialState = try await withCheckedThrowingContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { state, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: state) }
            }
        }
        return state == .authorized
    }

    /// Runs `handler` on the main actor when Apple says the user stopped using Apple ID with Doddy.
    static func observeRevocation(_ handler: @escaping @MainActor @Sendable () async -> Void) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: ASAuthorizationAppleIDProvider.credentialRevokedNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in await handler() }
        }
    }
}
