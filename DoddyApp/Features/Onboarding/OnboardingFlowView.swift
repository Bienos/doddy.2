import DoddyCore
import SwiftUI

/// First use: the optional introduction. It can be skipped; Home is reachable without it.
/// The Back Tap guide is not part of first use: it is V2's `OpenDoddyWaysView` (ways to open Doddy, ADR-558), offered from a
/// Home card and Settings (DECISIONS.md ADR-040, ADR-089).
struct OnboardingFlowView: View {
    @Environment(ProfileStore.self) private var profiles
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch profiles.route {
            case .setup, .introduction:
                // `ProfileStore.route` never returns `.setup`; kept exhaustive for the core enum.
                IntroductionView()
            case .home:
                Theme.canvas
            }
        }
        .background(Theme.canvas.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .animation(reduceMotion ? nil : .default, value: profiles.route)
    }
}

/// Small uppercase label above a screen title.
struct OnboardingLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(1)
            .foregroundStyle(Theme.secondaryText)
    }
}

/// What Doddy "says" on a screen. Written text only; nothing is spoken or listened to.
struct DoddySaysCard: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Doddy")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.accentText)
            Text(text)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

/// Scrollable onboarding page with the standard padding.
struct OnboardingPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                content
            }
            .padding(24)
            .frame(maxWidth: 600, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}
