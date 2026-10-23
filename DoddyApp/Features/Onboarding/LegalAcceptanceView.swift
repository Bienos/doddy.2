import DoddyCore
import SwiftUI

/// "Before we start" (ADR-581): the Terms & Conditions and the Privacy Policy, one unticked box,
/// and Continue. First use shows it before the introduction; someone who used Doddy before sees
/// it once as "We've updated our terms", and again only when the Terms change materially
/// (`LegalDocuments.minimumTermsVersion`). The documents open on the website; the app holds no
/// legal text. Accepting turns nothing on: the microphone, voice data sharing and every optional
/// feature keep their own questions. While it is up, "Your data and account" still reaches
/// export, delete and sign-out, so nobody is locked out of them by a pending acceptance.
struct LegalAcceptanceView: View {
    let source: LegalAcceptanceRecord.Source
    @State private var agreed = false
    @State private var saveFailed = false
    @State private var showingDataControls = false
    @AppStorage(PreferenceKey.hideCharacterArt) private var hideArt = false

    private var languageCode: String? { Bundle.main.preferredLocalizations.first }

    var body: some View {
        OnboardingPage {
            if !hideArt {
                UploadedCharacterView(assetName: "UploadedDoddy_Privacy", height: 120)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
            }
            Group {
                if source == .updatedTerms {
                    Text("We've updated our terms")
                } else {
                    Text("Before we start")
                }
            }
            .font(.largeTitle.bold())
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("legal.title")

            Text("By continuing, you agree to Doddy's Terms & Conditions and acknowledge the Privacy Policy.")

            VStack(alignment: .leading, spacing: 12) {
                Link(destination: LegalDocuments.url(.terms, languageCode: languageCode)) {
                    Label("Terms & Conditions", systemImage: "doc.text")
                }
                .accessibilityIdentifier("legal.terms")
                Link(destination: LegalDocuments.url(.privacy, languageCode: languageCode)) {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }
                .accessibilityIdentifier("legal.privacy")
            }
            .font(.body.weight(.semibold))

            Toggle(isOn: $agreed) {
                Text("I agree to the Terms & Conditions")
            }
            .toggleStyle(TickBoxToggleStyle())
            .accessibilityIdentifier("legal.agree")

            Button {
                saveFailed = !LegalAcceptanceStore.accept(source: source)
            } label: {
                Text("Continue").frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!agreed)
            .accessibilityIdentifier("legal.continue")

            if saveFailed {
                Label("Doddy couldn't save this on your iPhone. Try again.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.error)
            }

            Text("This doesn't turn anything on. Doddy asks separately before using the microphone or sending anything.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)

            if source == .updatedTerms {
                Button("Your data and account") { showingDataControls = true }
                    .font(.footnote.weight(.semibold))
                    .accessibilityIdentifier("legal.dataControls")
            }
        }
        .background(Theme.canvas.ignoresSafeArea())
        .foregroundStyle(Theme.ink)
        .sheet(isPresented: $showingDataControls) { LegalPendingDataControls() }
    }
}

/// A square box that is empty until tapped: never ticked in advance. VoiceOver reads it as a
/// switch with its label, because it is a `Toggle`.
private struct TickBoxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(configuration.isOn ? Theme.accentText : Theme.secondaryText)
                    .accessibilityHidden(true)
                configuration.label
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? Text("Ticked") : Text("Not ticked"))
    }
}

/// While the updated terms wait (ADR-581): export, delete and sign out stay reachable.
private struct LegalPendingDataControls: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                NavigationLink {
                    MemoriesSettingsView()
                } label: {
                    Text("Memories: export or delete")
                }
                NavigationLink {
                    AboutYouSettingsView()
                } label: {
                    Text("My profile: export or forget")
                }
                Section("Voice account") {
                    VoiceAccountSettings()
                }
                NavigationLink {
                    UpdatesSettingsView()
                } label: {
                    Text("Doddy messaging data")
                }
            }
            .navigationTitle("Your data and account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
