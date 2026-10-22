import DoddyCore
import SwiftUI

/// The sign-in sheet pinned to the bottom of the welcome (ADR-595). UI only: no option is
/// connected, so each says so and none looks like a success. "Try Doddy without an account" is the
/// only button that moves on.
///
/// It is a custom bottom sheet, not a system `.sheet`: a system sheet would be presented above the
/// Face ID lock's cover (`RootView` draws the lock as an overlay), and the lock must stay above
/// everything. Two heights, a drag that follows the finger, and a spring on release.
struct SignInSheet: View {
    static let collapsedHeight: CGFloat = 138
    static let expandedHeight: CGFloat = 384

    @Binding var expanded: Bool
    let provider: SignInProviding
    let continueWithoutAccount: () -> Void

    @GestureState private var drag: CGFloat = 0
    @State private var scanning = false
    @State private var notConnected = false
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
                    Text("Face ID, Google or email").font(.footnote).foregroundStyle(Theme.secondaryText)
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

    /// Expanded: Face ID, Google and email, the same size and weight.
    private var expandedContent: some View {
        VStack(spacing: 10) {
            Text("Your turn")
                .font(.title3.weight(.bold))
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
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
            Button { tap(.google) } label: {
                Text("Continue with Google")
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .foregroundStyle(Theme.ink)
                    .background(Capsule().fill(Theme.canvas))
                    .overlay(Capsule().stroke(Theme.ink.opacity(0.16), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("welcome.google")
            Button { tap(.email) } label: {
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
            Button(action: continueWithoutAccount) {
                Text("Try Doddy without an account")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("welcome.withoutAccount")
            if notConnected {
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
