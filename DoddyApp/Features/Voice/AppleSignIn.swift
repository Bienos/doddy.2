import AuthenticationServices
import CryptoKit
import Foundation
import Security
import SwiftUI

// Sign in with Apple for DODDY's voice account (ADR-483). The capability guard allows
// AuthenticationServices' Apple ID sign-in only in this file. It uses Apple's own sheet and the
// system's credential check: no web view and no browser session (those stay in Connected Apps,
// ADR-079). Talking to DODDY's voice server is VoiceAuthAPI's job, in VoiceTokenClient.swift.

/// What a finished Apple sign-in hands to DODDY's voice server. No name or email is requested.
struct AppleSignInCredential: Sendable {
    let identityToken: String
    let rawNonce: String
    /// Apple's opaque per-app identifier for this Apple ID.
    let userID: String
}

/// Why Apple sign-in didn't produce a credential. The person cancelling Apple's sheet is not one.
enum AppleSignInProblem {
    /// This iPhone couldn't make the random nonce, so the sign-in can't be bound to this request.
    case couldNotStart
    /// Apple's sheet ended with an error, not a cancel.
    case didNotFinish
}

/// The "Sign in with Apple" button. Makes a fresh nonce for each request and returns Apple's
/// signed identity token with the matching raw nonce.
struct AppleSignInButton: View {
    let onSignedIn: (AppleSignInCredential) -> Void
    let onProblem: (AppleSignInProblem) -> Void
    @State private var rawNonce: String?

    var body: some View {
        SignInWithAppleButton(.signIn, onRequest: { request in
            guard let nonce = AppleSignInNonce.make() else {
                onProblem(.couldNotStart)
                return
            }
            rawNonce = nonce.raw
            request.nonce = nonce.hashed
        }, onCompletion: complete)
        .signInWithAppleButtonStyle(.black)
    }

    private func complete(_ result: Result<ASAuthorization, Error>) {
        guard case .success(let authorization) = result,
              let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let data = credential.identityToken,
              let identityToken = String(data: data, encoding: .utf8),
              let rawNonce else {
            if case .failure(let error) = result, (error as? ASAuthorizationError)?.code != .canceled {
                onProblem(.didNotFinish)
            }
            return
        }
        onSignedIn(AppleSignInCredential(identityToken: identityToken, rawNonce: rawNonce, userID: credential.user))
        self.rawNonce = nil
    }
}

/// Apple's own view of whether this Apple ID may still use DODDY. Asked on this iPhone; nothing
/// is sent to DODDY's server.
@MainActor
enum AppleIDAccess {
    /// Posted when the person stops using their Apple ID with DODDY.
    static var revokedNotification: Notification.Name { ASAuthorizationAppleIDProvider.credentialRevokedNotification }

    static func isAuthorized(userID: String) async throws -> Bool {
        let provider = ASAuthorizationAppleIDProvider()
        let state: ASAuthorizationAppleIDProvider.CredentialState = try await withCheckedThrowingContinuation { continuation in
            provider.getCredentialState(forUserID: userID) { state, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: state) }
            }
        }
        return state == .authorized
    }
}

enum AppleSignInNonce {
    static func make() -> (raw: String, hashed: String)? {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return nil }
        let raw = Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let digest = SHA256.hash(data: Data(raw.utf8))
        return (raw, digest.map { String(format: "%02x", $0) }.joined())
    }
}
