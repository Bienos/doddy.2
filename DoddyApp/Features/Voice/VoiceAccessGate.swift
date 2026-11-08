import AuthenticationServices
import DoddyCore
import SwiftUI

/// First voice use has two explicit steps: DODDY account sign-in, then consent for the selected
/// provider. Neither step is required for local notes or other local features.
struct VoiceAccessGate: View {
    let provider: VoiceProvider
    let onContinue: () -> Void
    @State private var session = VoiceAuthSession.shared
    @State private var consented = false
    /// A Doddy account, a DODDY voice account, or (Debug builds only, ADR-551) the developer's direct connection.
    private var accessReady: Bool { session.hasVoiceAccess(for: provider) }

    var body: some View {
        ScrollView {
        VStack(spacing: 20) {
            VoiceDoddyView(art: .pose(.listening))
                .frame(height: 140)
                .accessibilityHidden(true)
            Text(accessReady ? "Before Doddy listens" : "Talk to Doddy")
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            if session.isLoading {
                ProgressView("Connecting your voice account…")
                    .accessibilityIdentifier("voice.auth.loading")
            } else if !accessReady && session.hasSavedSession {
                Text("Your Doddy voice account is saved on this iPhone. Reconnecting doesn’t require another Apple sign-in.")
                    .font(.body)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                if session.message == nil {
                    Button("Retry connection") { Task { await session.restore() } }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("voice.auth.retryConnection")
                }
            } else if !accessReady {
                Text("Sign in once with Apple to set up your Doddy voice account. Apple sends a signed identity token to Doddy only to verify your account and create the session. The protected session stays on this iPhone, so you won’t need to sign in every time. Sign-in doesn’t share your voice or notes.")
                    .font(.body)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                AppleAccountSignInButton(provider: provider)
                    .accessibilityIdentifier("voice.auth.appleSignIn")
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Voice runs through \(provider.shortName)", systemImage: "waveform")
                        .font(.headline)
                    Text("When you continue, your voice and this conversation are sent to \(provider.shortName) so Doddy can respond. Depending on your settings, Doddy may also send non-private notes, list details used in the conversation, recent conversations, approved profile details, and enabled connected-service results. The provider processes this data under its own privacy terms.")
                        .font(.body)
                    Text("Apple sign-in and microphone access are separate. You can use notes without enabling voice, and you can change this provider’s consent in Settings.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityIdentifier("voice.auth.providerConsent")

                Toggle("I agree to send voice data to \(provider.shortName) for this conversation", isOn: $consented)
                    .accessibilityIdentifier("voice.auth.consentToggle")
                Button("Continue to microphone access") {
                    VoiceProviderConsent.grant(for: provider)
                    onContinue()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!consented)
                .accessibilityIdentifier("voice.auth.continue")
            }

            if let message = session.message {
                VStack(spacing: 8) {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.updatesFrequently)
                    if session.hasSavedSession {
                        Button("Retry connection") { Task { await session.restore() } }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("voice.auth.retry")
                    }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: 520)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { consented = VoiceProviderConsent.isGranted(for: provider) }
    }
}

/// The one Sign in with Apple button: the voice screen's gate and the first-launch welcome (ADR-599)
/// both use it, so there is a single place that builds Apple's request and checks its answer. With
/// Doddy accounts set up in this build (decision 2026-11-08-required-account) it signs in to the Doddy
/// account (`DoddyAccountModel`); without them, to the voice account (`VoiceAuthSession`), as before.
/// It lives in this file because `check_forbidden_capabilities.sh` allows AuthenticationServices only
/// in the voice account's files.
///
/// Apple's rules (HIG, Sign in with Apple): the system button with a system title, black on light
/// and white on dark backgrounds, no smaller than the other sign-in buttons. A rounder corner is
/// allowed to match the other buttons.
struct AppleAccountSignInButton: View {
    let provider: VoiceProvider
    /// "Continue with Apple" next to other "Continue with…" buttons; "Sign in with Apple" alone.
    var usesContinueTitle = false
    var height: CGFloat = 50
    /// A capsule, to match the welcome's other buttons.
    var isCapsule = false
    /// Black on light backgrounds, white on dark ones, as Apple asks (the voice gate keeps black).
    var adaptsToDarkAppearance = false

    @State private var session = VoiceAuthSession.shared
    @State private var doddyAccount = DoddyAccountModel.shared
    @State private var rawNonce: String?
    @Environment(\.colorScheme) private var colorScheme

    /// Where this build's failures are shown: the Doddy account's message, or the voice account's.
    private func say(_ message: String) {
        if doddyAccount.isConfigured { doddyAccount.message = message } else { session.message = message }
    }

    var body: some View {
        SignInWithAppleButton(usesContinueTitle ? .continue : .signIn, onRequest: { request in
            guard let nonce = AppleSignInNonce.make() else {
                say(NSLocalizedString("This iPhone couldn’t start secure Apple sign-in. Try again.", comment: ""))
                return
            }
            rawNonce = nonce.raw
            request.nonce = nonce.hashed
            // Doddy accounts only (decision 2026-11-09-apple-email-for-linking): Apple's token then carries
            // the person's email (or Apple's private relay address), so Supabase can join this sign-in to a
            // Google or email account with the same verified address. The voice-only sign-in is unchanged.
            if doddyAccount.isConfigured { request.requestedScopes = [.email] }
        }, onCompletion: completeSignIn)
        .signInWithAppleButtonStyle(adaptsToDarkAppearance && colorScheme == .dark ? .white : .black)
        .frame(height: height)
        .clipShape(isCapsule ? AnyShape(Capsule()) : AnyShape(RoundedRectangle(cornerRadius: 8, style: .continuous)))
    }

    private func completeSignIn(_ result: Result<ASAuthorization, Error>) {
        guard case .success(let authorization) = result,
              let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let data = credential.identityToken,
              let identityToken = String(data: data, encoding: .utf8),
              let rawNonce else {
            if case .failure(let error) = result, (error as? ASAuthorizationError)?.code != .canceled {
                say(NSLocalizedString("Apple sign-in didn’t finish. Try again.", comment: ""))
            }
            return
        }
        if doddyAccount.isConfigured {
            // Apple's token and the raw nonce go to the Doddy account service, which checks both.
            // Apple's one-time code goes to the voice server once the account exists, so deleting the
            // account can also end Sign in with Apple (decision 2026-11-09-apple-revoke-for-doddy-accounts).
            // That step is best effort: the sign-in has already counted without it.
            let authorizationCode = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
            let account = doddyAccount
            Task { @MainActor in
                await account.signInWithApple(identityToken: identityToken, rawNonce: rawNonce)
                if account.isSignedIn, let authorizationCode, !authorizationCode.isEmpty {
                    await DoddyAccountServers.linkAppleRevocation(
                        identityToken: identityToken, rawNonce: rawNonce, authorizationCode: authorizationCode)
                }
            }
            self.rawNonce = nil
            return
        }
        // Apple's one-time code lets the server revoke Sign in with Apple if the account is
        // deleted later (ADR-524). Sign-in works without it.
        let authorizationCode = credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
        Task { await session.finishAppleSignIn(identityToken: identityToken, rawNonce: rawNonce,
                                               authorizationCode: authorizationCode,
                                               userID: credential.user, provider: provider) }
        self.rawNonce = nil
    }
}
