import DoddyCore
import SwiftUI

/// Settings › Memories: the one "Erase everything on this iPhone". It replaces "Delete all memories", which left remembered
/// conversations, the About you answers, files Doddy made, the parking spot and the training log behind. The plan and its
/// rules are `EraseThisIPhone` (app) and `DeviceErasure` (DoddyCore, tested on Linux); this is only the button, the words and
/// the next step.
///
/// The confirmation says what is removed and what is not. The Doddy account is a separate step, offered right after: erasing
/// what is on this iPhone doesn't delete the account or what Doddy's servers keep for it.
///
/// Not compiled on Linux: the hosted `ios-build` job is its first compile. Not run on a device.
struct EraseThisIPhoneRow: View {
    @Environment(MemoryStore.self) private var store
    @Environment(ProfileStore.self) private var profiles
    @State private var account = DoddyAccountModel.shared
    @State private var confirming = false
    @State private var working = false
    @State private var message: EraseThisIPhone.Message?
    @State private var offeringAccountStep = false

    var body: some View {
        Group {
            Button("Erase everything on this iPhone", role: .destructive) { confirming = true }
                .disabled(working)
                .accessibilityIdentifier("settings.deleteAll")
                // On the row that opens it, so on iPad its popover points here (ADR-437).
                .confirmationDialog("Erase everything on this iPhone?", isPresented: $confirming, titleVisibility: .visible) {
                    Button("Erase everything", role: .destructive) { Task { await erase() } }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    // The full consequences stay at the point of decision (ADR-580 rule 5).
                    confirmationText
                }
                // Right after the erase: the Doddy account is its own step. On the button too, not on the group: a modifier on
                // a group is applied to each of its rows.
                .confirmationDialog("Your Doddy account is separate", isPresented: $offeringAccountStep, titleVisibility: .visible) {
                    Button("Delete my Doddy account", role: .destructive) { Task { await deleteAccount() } }
                    Button("Sign out") { Task { await account.signOut() } }
                    Button("Not now", role: .cancel) {}
                } message: {
                    Text("Everything Doddy kept on this iPhone is erased. Your Doddy account, and what Doddy's server keeps for it, stay until you delete the account.")
                }
            if working {
                ProgressView().accessibilityIdentifier("settings.erase.working")
            }
            if let message {
                Label(message.text, systemImage: message.isProblem ? "exclamationmark.triangle" : "checkmark.circle")
                    .foregroundStyle(message.isProblem ? Theme.error : Theme.confirmed)
                    .accessibilityIdentifier("settings.erase.result")
            }
            // Another account's data is here (decision 2026-11-12-local-data-owner): this is the way to clear it.
            if DoddyAccountServers.localDataMismatch != nil {
                Text("This iPhone holds Doddy data made with another account, so nothing from it is sent to yours. Erasing it lets your account take this iPhone over.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private var confirmationText: Text {
        let removed = Text("This removes everything Doddy keeps on this iPhone and can't be undone: notes and lists with their photos and voice memos, recordings, Messages, remembered conversations, what Doddy did and learned, your answers in About you, tasks and calls, the training log and plan, parcels, your inFakt key, files Doddy made, trips, your settings, and the alarms, timers and reminders Doddy set.")
        let notRemoved = Text("Lists you shared stop being shared, so the people you invited lose them too. With Memory on calls on, the copy on your Doddy messaging server is emptied. Other copies on Doddy's servers, exported files and older backups aren't affected.")
        let kept = account.isSignedIn
            ? Text("Doddy keeps only your sign-in, your choices about what is sent, and the marks that say which first screens you've seen and that you accepted the Terms. Your Doddy account is a separate step: you can delete it next.")
            : Text("Doddy keeps only your choices about what is sent, and the marks that say which first screens you've seen and that you accepted the Terms.")
        return removed + Text(verbatim: " ") + notRemoved + Text(verbatim: " ") + kept
    }

    private func erase() async {
        working = true
        message = nil
        let signedIn = account.isSignedIn
        let outcome = await EraseThisIPhone.run(store: store, profiles: profiles)
        working = false
        message = EraseThisIPhone.message(for: outcome, signedIn: signedIn)
        if case .finished(let report, _) = outcome, report.isErased, signedIn { offeringAccountStep = true }
    }

    /// The account's own deletion (each server confirms, `DoddyAccountServers.deleteAccount`), then what it left on this iPhone:
    /// the sign-in items and server links, which `.keepSignIn` kept so the deletion could reach the servers.
    private func deleteAccount() async {
        working = true
        let store = store
        let profiles = profiles
        await DoddyAccountServers.deleteAccount(thenErase: {
            await EraseThisIPhone.lineAfterAccountDeleted(store: store, profiles: profiles)
        })
        working = false
        // Still signed in: a server didn't confirm, and the account's message says which.
        if account.isSignedIn, let text = account.shownMessage { message = EraseThisIPhone.Message(text: text, isProblem: true) }
    }
}
