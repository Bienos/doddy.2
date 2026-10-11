import CloudKit
import DoddyCore
import SwiftUI
import UIKit

/// Gets the share link when Doddy is opened from one (ADR-263). Nothing is joined until the user
/// taps Join on the invite sheet.
@MainActor
final class ShareAcceptSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            SharedListsController.shared.received(metadata)
        }
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        SharedListsController.shared.received(cloudKitShareMetadata)
    }
}

/// Apple's sharing screen for one share. Lists' screens hold this, never CloudKit types.
struct CloudShareSheet: Identifiable {
    let id = UUID()
    let share: CKShare
    let container: CKContainer
}

/// Apple's screen for inviting people to a shared list, or seeing and removing them.
struct CloudSharingView: UIViewControllerRepresentable {
    let sheet: CloudShareSheet
    let listName: String
    /// The owner stopped sharing, or someone who joined removed themselves, in Apple's screen.
    /// Apple removes only the share; the caller removes the zone and the link (review I5).
    let onStopped: () -> Void
    /// Apple's screen couldn't save a change to the share (review I5).
    let onFailed: (any Error) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(listName: listName, onStopped: onStopped, onFailed: onFailed) }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: sheet.share, container: sheet.container)
        // Only people the user invites; they can tick and add.
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let listName: String
        let onStopped: () -> Void
        let onFailed: (any Error) -> Void

        init(listName: String, onStopped: @escaping () -> Void, onFailed: @escaping (any Error) -> Void) {
            self.listName = listName
            self.onStopped = onStopped
            self.onFailed = onFailed
        }

        func itemTitle(for csc: UICloudSharingController) -> String? { listName }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: any Error) { onFailed(error) }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) { onStopped() }
    }
}

/// "Join a shared list?", from a share link. The list name and who shared it, and what joining does.
struct SharedListInviteView: View {
    let invite: SharedListsController.Invite
    @Environment(\.dismiss) private var dismiss
    @State private var isJoining = false
    @State private var problem: String?
    let onJoined: (DoddyList) -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                JourneyHeading(eyebrow: "Shared list", title: invite.title)
                if let owner = invite.owner {
                    Text(String(format: NSLocalizedString("Shared by %@ through iCloud.", comment: ""), owner))
                        .foregroundStyle(Theme.secondaryText)
                }
                Text("Joining adds this list to Doddy on this iPhone. Its items, and the changes anyone makes, go through iCloud to everyone who shares it. Your notes and other lists aren't shared.")
                    .font(.subheadline)
                if let problem { ProblemView(message: problem) }
                Button {
                    Task { await join() }
                } label: {
                    HStack { Text("Join list"); Spacer(); if isJoining { ProgressView() } else { Image(systemName: "person.2") } }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isJoining)
                .accessibilityIdentifier("sharing.join")
                Button("Not now") {
                    SharedListsController.shared.declineInvite()
                    dismiss()
                }
                .frame(minHeight: 44)
                Spacer()
            }
            .padding(24)
            .background(Theme.canvas).foregroundStyle(Theme.ink)
        }
    }

    private func join() async {
        isJoining = true
        defer { isJoining = false }
        do {
            let list = try await SharedListsController.shared.join(invite)
            dismiss()
            onJoined(list)
        } catch {
            problem = SharingError.message(for: error)
        }
    }
}

/// On a list's screen: shared or not, last update, Sync now, and people.
struct SharedListStatusRow: View {
    let list: DoddyList
    let link: ListShare
    let onPeople: () -> Void
    private let sharing = SharedListsController.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(link.role == .owner ? "Shared through your iCloud" : "Shared with you through iCloud", systemImage: "person.2")
                .font(.footnote.weight(.semibold))
            Text(String(format: sharing.liveUpdates
                        ? NSLocalizedString("Last updated %@. Changes from others arrive straight away.", comment: "")
                        : NSLocalizedString("Last updated %@. Changes from others show when Doddy is open.", comment: ""),
                        link.syncedAt.formatted(date: .abbreviated, time: .shortened)))
                .font(.caption).foregroundStyle(Theme.secondaryText)
            if let problem = sharing.problem {
                Text(problem).font(.caption).foregroundStyle(Theme.error)
            }
            HStack {
                Button(sharing.isSyncing ? "Updating…" : "Update now") { Task { await sharing.syncAll() } }
                    .disabled(sharing.isSyncing)
                Spacer()
                Button("People", action: onPeople)
            }
            .font(.subheadline)
            .frame(minHeight: 44)
        }
        .accessibilityIdentifier("list.shared")
    }
}
