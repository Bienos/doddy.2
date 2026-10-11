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
    /// The owner stopped sharing in Apple's screen.
    let onStopped: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(listName: listName, onStopped: onStopped) }

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

        init(listName: String, onStopped: @escaping () -> Void) {
            self.listName = listName
            self.onStopped = onStopped
        }

        func itemTitle(for csc: UICloudSharingController) -> String? { listName }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: any Error) {}

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

/// Under a shared list's reminder (ADR-307): share this iPhone's place with everyone on the list,
/// or, when someone else shared one, be reminded there too. Nothing is shared or set until a tap.
struct SharedPlaceRow: View {
    let list: DoddyList
    @Environment(NoteReminderStore.self) private var reminders
    private let sharing = SharedListsController.shared
    @State private var isWorking = false
    @State private var message: String?

    private var mine: ReminderPlace? {
        reminders.reminder(forMemory: list.id)?.place
    }

    var body: some View {
        let offer = sharing.placeOffer(for: list.id, mine: mine)
        VStack(alignment: .leading, spacing: 8) {
            switch offer {
            case .nothing:
                EmptyView()
            case .canShare(let place):
                Button("Share this place with everyone on the list") { run { try await sharing.setSharedPlace(place, for: list.id) } }
                    .disabled(isWorking)
                    .accessibilityIdentifier("list.sharePlace")
                Text("They see the place you picked (“\(place.name)”) and can choose to be reminded there too. Not where you are.")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            case .remindMeToo(let shared, let by):
                Group {
                    if let by {
                        Text(String(format: NSLocalizedString("%@ shared a reminder at “%@”.", comment: ""), by, shared.place.name))
                    } else {
                        Text(String(format: NSLocalizedString("Someone on the list shared a reminder at “%@”.", comment: ""), shared.place.name))
                    }
                }
                .font(.subheadline)
                Button("Remind me there too") {
                    run { await reminders.set(memoryID: list.id, place: shared.place) }
                }
                .disabled(isWorking)
                .accessibilityIdentifier("list.remindMeToo")
                if mine != nil {
                    Text("This replaces your own reminder for this list.").font(.footnote).foregroundStyle(Theme.secondaryText)
                }
            case .shared(let shared, let byMe):
                Text(String(format: NSLocalizedString("Everyone on the list can be reminded at “%@”.", comment: ""), shared.place.name))
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
                if byMe {
                    Button("Stop sharing this place") { run { try await sharing.setSharedPlace(nil, for: list.id) } }
                        .disabled(isWorking)
                        .accessibilityIdentifier("list.stopSharingPlace")
                }
            }
            if let message {
                Text(message).font(.footnote).foregroundStyle(Theme.error)
            }
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        isWorking = true
        message = nil
        Task {
            do { try await work() } catch { message = SharingError.message(for: error) }
            isWorking = false
        }
    }
}
