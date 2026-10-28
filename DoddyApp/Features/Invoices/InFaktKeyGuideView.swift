import DoddyCore
import SwiftUI
import UIKit

/// Settings › Invoices (inFakt) › How to make the key (ADR-640): the steps for making an inFakt key, so a
/// person who has never opened Settings › API can do it. inFakt has no "sign in with inFakt" for other
/// apps, only a key the person makes themselves (docs/implementation/INFAKT_STATUS.md), so this screen
/// makes that as short as it can be. It sends nothing anywhere: "Open inFakt" opens inFakt's own site in
/// the browser, and the paste button only hands the clipboard text to the settings screen, where the key
/// is checked and kept when the person taps Save. The rights listed are `InFaktAPI.neededScopes`.
/// The clipboard is only asked whether it holds text (that does not show iOS's paste prompt); its text is
/// read when the person taps the button. Not seen on a device in this build.
struct InFaktKeyGuideView: View {
    /// Receives the clipboard text when the person taps the paste button.
    let onPaste: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var clipboardHasText = false

    /// inFakt's public site. The address of the signed-in panel could not be checked from here, so this
    /// opens the site, which has the sign-in button.
    private static let inFaktSite = URL(string: "https://www.infakt.pl")!

    var body: some View {
        Form {
            Section {
                Text("A key lets Doddy work in your inFakt account. You make it once, in inFakt, and it stays on this iPhone.")
            }

            Section {
                step(1, Text("Open inFakt and sign in."))
                Link("Open inFakt", destination: Self.inFaktSite)
                    .accessibilityIdentifier("infakt.guide.open")
                step(2, Text("Go to Settings › API. inFakt asks for your password."))
                step(3, Text("Make a new key and tick only these rights:"))
                ForEach(InFaktAPI.neededScopes, id: \.self) { scope in
                    Text(verbatim: scope)
                        .font(.body.monospaced())
                        .padding(.leading, 40)
                }
                step(4, Text("Copy the key before you leave that page."))
            } header: {
                Text("In inFakt")
            } footer: {
                Text("The second right also lets a key change and delete invoices in inFakt. Doddy makes an invoice only after you confirm its card.")
            }

            Section {
                if clipboardHasText {
                    Button("Paste the key from the clipboard") {
                        guard let text = UIPasteboard.general.string else { return }
                        onPaste(text)
                        dismiss()
                    }
                    .accessibilityIdentifier("infakt.guide.paste")
                } else {
                    Text("Copy the key in inFakt and come back: the paste button appears when there is text on the clipboard.")
                        .foregroundStyle(Theme.secondaryText)
                }
            } header: {
                Text("Then come back here")
            } footer: {
                Text("To stop Doddy reaching your account, delete the key in inFakt (Settings › API) or remove it here.")
            }
        }
        .settingsPage()
        .navigationTitle("Make an inFakt key")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { clipboardHasText = UIPasteboard.general.hasStrings }
        }
    }

    private func step(_ number: Int, _ text: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(verbatim: "\(number)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.accentText)
                .frame(width: 28, alignment: .center)
                .accessibilityHidden(true)
            text
        }
        .accessibilityElement(children: .combine)
    }
}
