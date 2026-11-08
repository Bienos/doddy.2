import DoddyCore
import SwiftUI

/// Settings › Your Doddy account (decision 2026-11-08-required-account): who is signed in, signing
/// out, and deleting the account. Shown only in a build with Doddy accounts set up; a build without
/// them shows nothing new.
struct DoddyAccountSettingsSection: View {
    @State private var account = DoddyAccountModel.shared
    @State private var confirmSignOut = false
    @State private var confirmDelete = false
    @State private var deleting = false

    var body: some View {
        if account.isConfigured {
            Section("Your Doddy account") {
                if let session = account.session {
                    LabeledContent {
                        Text(verbatim: session.email ?? "")
                    } label: {
                        Text(Self.methodTitle(session.method))
                    }
                    .accessibilityIdentifier("settings.doddyAccount")
                }
                if let message = account.shownMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .accessibilityAddTraits(.updatesFrequently)
                        .accessibilityIdentifier("settings.doddyAccount.message")
                }
                if deleting {
                    ProgressView().accessibilityIdentifier("settings.doddyAccount.deleting")
                }
                Button("Sign out") { confirmSignOut = true }
                    .disabled(deleting || !account.isSignedIn)
                    .accessibilityIdentifier("settings.doddyAccount.signOut")
                Button("Delete my Doddy account", role: .destructive) { confirmDelete = true }
                    .disabled(deleting || !account.isSignedIn)
                    .accessibilityIdentifier("settings.doddyAccount.delete")
            }
            .confirmationDialog("Sign out of Doddy?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { Task { await account.signOut() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Doddy asks you to sign in again before you use him. Your notes stay on this iPhone, and whoever signs in here next can see them.")
            }
            .confirmationDialog("Delete your Doddy account?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete my Doddy account", role: .destructive) {
                    Task {
                        deleting = true
                        await DoddyAccountServers.deleteAccount()
                        deleting = false
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Doddy's server deletes what it keeps for you, your messaging data and your sign-in, and disconnects your online accounts. Notes on this iPhone stay.")
            }
        }
    }

    private static func methodTitle(_ method: DoddyAccountMethod) -> String {
        switch method {
        case .apple: NSLocalizedString("Signed in with Apple", comment: "")
        case .google: NSLocalizedString("Signed in with Google", comment: "")
        case .email: NSLocalizedString("Signed in with email", comment: "")
        }
    }
}
