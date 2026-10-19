import AuthenticationServices
import DoddyCore
import SwiftUI

/// First voice use has two explicit steps: DODDY account sign-in, then consent for the selected
/// provider. Neither step is required for local notes or other local features.
struct VoiceAccessGate: View {
    let provider: VoiceProvider
    let onContinue: () -> Void
    @State private var session = VoiceAuthSession.shared
    @State private var rawNonce: String?
    @State private var consented = false

    var body: some View {
        ScrollView {
        VStack(spacing: 20) {
            VoiceDoddyView(art: .pose(.listening))
                .frame(height: 140)
                .accessibilityHidden(true)
            Text(session.isSignedIn ? "Before Doddy listens" : "Talk to Doddy")
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            if session.isLoading {
                ProgressView("Connecting your voice account…")
                    .accessibilityIdentifier("voice.auth.loading")
            } else if !session.isSignedIn && session.hasSavedSession {
                Text("Your DODDY voice account is saved on this iPhone. Reconnecting doesn’t require another Apple sign-in.")
                    .font(.body)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                if session.message == nil {
                    Button("Retry connection") { Task { await session.restore() } }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("voice.auth.retryConnection")
                }
            } else if !session.isSignedIn {
                Text("Sign in once with Apple to set up your DODDY voice account. Apple sends a signed identity token to DODDY only to verify your account and create the session. The protected session stays on this iPhone, so you won’t need to sign in every time. Sign-in doesn’t share your voice or notes.")
                    .font(.body)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                SignInWithAppleButton(.signIn, onRequest: { request in
                    guard let nonce = AppleSignInNonce.make() else {
                        session.message = "This iPhone couldn’t start secure Apple sign-in. Try again."
                        return
                    }
                    rawNonce = nonce.raw
                    request.nonce = nonce.hashed
                }, onCompletion: completeSignIn)
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
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

    private func completeSignIn(_ result: Result<ASAuthorization, Error>) {
        guard case .success(let authorization) = result,
              let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let data = credential.identityToken,
              let identityToken = String(data: data, encoding: .utf8),
              let rawNonce else {
            if case .failure(let error) = result, (error as? ASAuthorizationError)?.code != .canceled {
                session.message = "Apple sign-in didn’t finish. Try again."
            }
            return
        }
        Task { await session.finishAppleSignIn(identityToken: identityToken, rawNonce: rawNonce,
                                               userID: credential.user, provider: provider) }
        self.rawNonce = nil
    }
}
