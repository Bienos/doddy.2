import DoddyCore
import SwiftUI

/// The sign-in sheet pinned to the bottom of the welcome (ADR-598, ADR-599).
///
/// **With Doddy accounts set up in this build** (decision 2026-11-08-required-account): Apple or
/// Google (`DoddyAccountModel`), and no way past without one. The welcome stays until the person is
/// signed in (`RootView.accountRequired`). Email is off for now (`offersEmail`, decision
/// 2026-11-09-email-sign-in-off-for-now). Every kept sign-in ends the welcome (`signInCount`), and a
/// person who is already signed in when it shows (Settings › "Show the welcome again", or a reinstall,
/// which keeps the Keychain) gets "Continue" instead of the sign-in buttons.
///
/// **Without them** (today's builds, and UI tests), as before: Sign in with Apple is the voice
/// account's sign-in (`AppleAccountSignInButton`, `VoiceAuthSession`) and a finished sign-in moves on;
/// Face ID, Google and email are UI only and each says so; "Try Doddy without an account" moves on.
///
/// It is a custom bottom sheet, not a system `.sheet`: a system sheet would be presented above the
/// Face ID lock's cover (`RootView` draws the lock as an overlay), and the lock must stay above
/// everything. Two heights, a drag that follows the finger, and a spring on release.
struct SignInSheet: View {
    static let collapsedHeight: CGFloat = 138
    static let expandedHeight: CGFloat = 446
    /// Email sign-in is off for now (owner, 9 Nov 2026): the account service still emails a link to
    /// a web page instead of the code the form asks for, so it can't be finished in the app. Turning
    /// it back on is this line, once the email template sends the code (`EmailCodeForm` is kept).
    static let offersEmail = false

    @Binding var expanded: Bool
    let provider: SignInProviding
    let continueWithoutAccount: () -> Void
    /// A sign-in finished (the Doddy account, or without one the voice account): the welcome is over.
    let signedIn: () -> Void

    @GestureState private var drag: CGFloat = 0
    @State private var scanning = false
    @State private var notConnected = false
    @State private var account = VoiceAuthSession.shared
    @State private var doddyAccount = DoddyAccountModel.shared
    /// The email form is open in place of the buttons.
    @State private var emailOpen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var span: CGFloat { Self.expandedHeight - Self.collapsedHeight }

    /// 0 collapsed, 1 expanded, following the finger while it drags.
    private var openness: CGFloat {
        let base: CGFloat = expanded ? 1 : 0
        return min(max(base - drag / span, 0), 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            grabber
            ZStack(alignment: .top) {
                collapsed
                    .opacity(Double(1 - min(1, openness * 1.8)))
                    .allowsHitTesting(openness < 0.3)
                    .accessibilityHidden(openness >= 0.3)
                expandedContent
                    .opacity(Double(min(1, max(0, (openness - 0.35) * 1.8))))
                    .allowsHitTesting(openness > 0.6)
                    .accessibilityHidden(openness <= 0.6)
            }
            .padding(.horizontal, 24)
            Spacer(minLength: 0)
        }
        .frame(height: Self.collapsedHeight + span * openness, alignment: .top)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 34, bottomLeadingRadius: 0, bottomTrailingRadius: 0,
                                   topTrailingRadius: 34, style: .continuous)
                .fill(reduceTransparency ? AnyShapeStyle(Theme.canvas) : AnyShapeStyle(.regularMaterial))
                .shadow(color: .black.opacity(0.07), radius: 20, x: 0, y: -6)
                .ignoresSafeArea(edges: .bottom)
        }
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.86), value: expanded)
        .sensoryFeedback(.impact(weight: .light), trigger: expanded)
        .onChange(of: account.isSignedIn) { _, now in if now, !doddyAccount.isConfigured { signedIn() } }
        // Each kept sign-in, not "signed in" turning true: a sign-in made while a session was already
        // kept left that true, and the welcome never closed (TestFlight build 20).
        .onChange(of: doddyAccount.signInCount) { _, _ in emailOpen = false; signedIn() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("welcome.sheet")
    }

    // MARK: Gesture

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .updating($drag) { value, state, _ in state = value.translation.height }
            .onEnded { value in
                // Decide from where the flick is going, not only where the finger stopped.
                let projected = value.predictedEndTranslation.height
                if projected < -40 { expanded = true } else if projected > 40 { expanded = false }
            }
    }

    // MARK: Pieces

    private var grabber: some View {
        Button {
            expanded.toggle()
        } label: {
            Capsule()
                .fill(Theme.ink.opacity(0.22))
                .frame(width: 38, height: 5)
                .frame(maxWidth: .infinity, minHeight: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(expanded ? Text("Close sign-in options") : Text("Open sign-in options"))
        .accessibilityIdentifier("welcome.grabber")
    }

    /// Collapsed: one glass button.
    private var collapsed: some View {
        Button {
            expanded = true
        } label: {
            HStack(spacing: 14) {
                biometryGlyph(size: 40, scanning: false)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Get in").font(.headline)
                    Group {
                        if doddyAccount.isConfigured { Text("Apple or Google") } else { Text("Apple, Face ID, Google or email") }
                    }
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.up").font(.headline).foregroundStyle(Theme.ink)
            }
            .padding(.leading, 14).padding(.trailing, 22)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(Capsule().fill(Theme.quietSurface))
            .shadow(color: .black.opacity(0.1), radius: 14, x: 0, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Opens sign-in options"))
        .accessibilityIdentifier("welcome.getIn")
    }

    @ViewBuilder private var expandedContent: some View {
        if doddyAccount.isConfigured { accountContent } else { withoutAccountsContent }
    }

    /// With Doddy accounts: Apple and Google, the same size and weight, and no way past without one of
    /// them. Already signed in (the welcome shown again, or a reinstall): which account, and Continue.
    private var accountContent: some View {
        VStack(spacing: 10) {
            Text("Your turn")
                .font(.title3.weight(.bold))
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
            if let session = doddyAccount.session {
                Text(verbatim: DoddyAccountSettingsSection.methodTitle(session.method))
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityIdentifier("welcome.account.signedIn")
                Button(action: signedIn) {
                    Text("Continue")
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .foregroundStyle(Theme.canvas)
                        .background(Capsule().fill(Theme.ink))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("welcome.continue")
            } else if emailOpen && Self.offersEmail {
                EmailCodeForm(account: doddyAccount, back: {
                    doddyAccount.changeEmail()
                    emailOpen = false
                })
            } else {
                Group {
                    AppleAccountSignInButton(usesContinueTitle: true, height: 52,
                                             isCapsule: true, adaptsToDarkAppearance: true)
                        .accessibilityIdentifier("welcome.apple")
                    googleButton { Task { await doddyAccount.signInWithGoogle() } }
                    if Self.offersEmail {
                        emailButton {
                            doddyAccount.message = nil
                            emailOpen = true
                        }
                    }
                }
                .disabled(doddyAccount.isWorking)
            }
            if doddyAccount.isWorking {
                ProgressView().accessibilityIdentifier("welcome.account.working")
            } else if let message = doddyAccount.shownMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.updatesFrequently)
                    .accessibilityIdentifier("welcome.account.message")
            } else if !emailOpen && !doddyAccount.isSignedIn {
                Text("Doddy needs an account. There's no password: sign in with Apple or Google.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.body.weight(.semibold))
    }

    private func googleButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Continue with Google")
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(Theme.ink)
                .background(Capsule().fill(Theme.canvas))
                .overlay(Capsule().stroke(Theme.ink.opacity(0.16), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("welcome.google")
    }

    private func emailButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "envelope").font(.body)
                Text("Continue with email")
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(Theme.ink)
            .background(Capsule().fill(Theme.separator.opacity(0.5)))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("welcome.email")
    }

    /// Without Doddy accounts (as before): Face ID, Google and email, the same size and weight.
    private var withoutAccountsContent: some View {
        VStack(spacing: 10) {
            Text("Your turn")
                .font(.title3.weight(.bold))
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
            // Apple first, and the same size as the others (Apple's rule): the one that works today.
            AppleAccountSignInButton(usesContinueTitle: true, height: 52,
                                     isCapsule: true, adaptsToDarkAppearance: true)
                .accessibilityIdentifier("welcome.apple")
            Button { tap(.faceID) } label: {
                HStack(spacing: 8) {
                    biometryGlyph(size: 24, scanning: scanning)
                    faceIDTitle
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(Theme.canvas)
                .background(Capsule().fill(Theme.ink))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("welcome.faceID")
            googleButton { tap(.google) }
            emailButton { tap(.email) }
            Button(action: continueWithoutAccount) {
                Text("Try Doddy without an account")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("welcome.withoutAccount")
            if account.isLoading {
                ProgressView().accessibilityIdentifier("welcome.apple.loading")
            } else if let message = account.message {
                // Apple's own failures (cancelled is silent), in the voice account's words.
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("welcome.apple.message")
            } else if notConnected {
                Text("Sign-in isn't connected yet. You can try Doddy without an account.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("welcome.notConnected")
            } else {
                legalLine
            }
        }
        .font(.body.weight(.semibold))
    }

    @ViewBuilder private var legalLine: some View {
        Group {
            switch AppLock.biometry {
            case .faceID: Text("Face ID opens Doddy on this iPhone. Doddy only learns that it matched.")
            case .touchID: Text("Touch ID opens Doddy on this iPhone. Doddy only learns that it matched.")
            case .unavailable: Text("A passkey opens Doddy on this iPhone. Doddy only learns that it matched.")
            }
        }
        .font(.footnote)
        .foregroundStyle(Theme.secondaryText)
        .multilineTextAlignment(.center)
    }

    /// Named for the method this device really has (Apple's HIG).
    @ViewBuilder private var faceIDTitle: some View {
        switch AppLock.biometry {
        case .faceID: Text("Continue with Face ID")
        case .touchID: Text("Continue with Touch ID")
        case .unavailable: Text("Continue with passkey")
        }
    }

    private func biometryGlyph(size: CGFloat, scanning: Bool) -> some View {
        BiometryGlyph(biometry: AppLock.biometry, size: size, scanning: scanning)
    }

    // MARK: Actions

    private func tap(_ option: SignInOption) {
        notConnected = false
        Task { @MainActor in
            if option == .faceID {
                // The scan is only the pressed state of the button: it does not check anything.
                scanning = true
                try? await Task.sleep(for: .seconds(reduceMotion ? 0.4 : 1.2))
                scanning = false
            }
            switch await provider.signIn(with: option) {
            case .notConnectedYet: notConnected = true
            case .signedIn: notConnected = false
            }
        }
    }
}

/// The biometry glyph: a system symbol, with an orange line that sweeps while `scanning`.
struct BiometryGlyph: View {
    let biometry: AppLock.Biometry
    let size: CGFloat
    let scanning: Bool

    @State private var sweep = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var symbol: String {
        switch biometry {
        case .faceID: "faceid"
        case .touchID: "touchid"
        case .unavailable: "person.badge.key"
        }
    }

    var body: some View {
        ZStack {
            Image(systemName: symbol)
                .resizable().scaledToFit()
                .frame(width: size * 0.92, height: size * 0.92)
            if scanning {
                Rectangle()
                    .fill(Theme.orangeCue)
                    .frame(width: size * 0.7, height: 2)
                    .offset(y: sweep ? size * 0.3 : -size * 0.3)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .onChange(of: scanning) { _, on in
            guard on, !reduceMotion else { sweep = false; return }
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { sweep = true }
        }
    }
}
