import SwiftUI

/// The notice shown before cloud AI is switched on (docs/architecture/AI_RUNTIME.md: "Cloud model
/// requires clear user-facing notice"). Wording is a draft pending the privacy policy.
struct CloudAIConsentSheet: View {
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Before Doddy can answer")
                        .font(.title.bold())
                        .accessibilityAddTraits(.isHeader)
                    notice("What is sent", "Only when you ask a question: the question itself, and up to 3 of your saved notes that match it. Nothing else — not your other notes, name, contacts or location. There is no account.")
                    notice("Where it goes", "Over the internet to Doddy's server (Supabase, Frankfurt), which forwards it to OpenAI to write the answer.")
                    notice("What is kept", "Doddy's server stores no question or answer text, only anonymous usage counters. OpenAI may keep requests for a limited time under its own policy. Doddy's privacy policy isn't written yet.")
                    notice("Your control", "Turn this off in Settings at any time and nothing more is sent. Text already sent can't be taken back by this app.")
                    notice("Honest limits", "Doddy is an AI, not a person. Answers can be wrong. This is a preview that hasn't been tested on a physical iPhone.")

                    VStack(spacing: 12) {
                        Button(action: onAccept) { Text("Turn on cloud AI") }
                            .buttonStyle(PrimaryButtonStyle())
                            .accessibilityIdentifier("consent.accept")
                        Button(action: onDecline) { Text("Not now") }
                            .buttonStyle(SecondaryButtonStyle())
                            .accessibilityIdentifier("consent.decline")
                    }
                }
                .padding(24)
            }
            .background(Theme.canvas)
            .interactiveDismissDisabled()
        }
        .foregroundStyle(Theme.ink)
    }

    private func notice(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(body).foregroundStyle(Theme.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }
}
