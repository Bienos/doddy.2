import DoddyCore
import SwiftUI

/// Settings → Reminders from Doddy: what Doddy added (or tried to), with honest status.
struct RemindersListView: View {
    @Environment(\.appEnvironment) private var environment
    @State private var actions: [ReminderAction] = []
    @State private var isWorking = false
    @State private var message: String?

    var body: some View {
        List {
            if actions.isEmpty {
                Text("No reminders yet. Open a memory and tap \"Remind me\", or ask Doddy by voice.")
                    .foregroundStyle(Theme.secondaryText)
            }
            ForEach(actions) { action in
                VStack(alignment: .leading, spacing: 6) {
                    Text(action.payload.title)
                    Text(ReminderCopy.status(action))
                        .font(.footnote)
                        .foregroundStyle(action.state == .verifiedSucceeded ? Theme.secondaryText : Theme.error)
                    if action.state == .unknownOutcome {
                        HStack {
                            Button("Check again") { Task { await reconcile(action, create: false) } }
                            Spacer()
                            Button("Add it now") { Task { await reconcile(action, create: true) } }
                        }
                        .buttonStyle(.borderless)
                    } else if action.state == .verifiedFailed {
                        Button("Try again") { Task { await reconcile(action, create: true) } }
                            .buttonStyle(.borderless)
                    }
                }
            }
            if let message {
                Label(message, systemImage: "info.circle")
            }
            Section {
                Text("These are records on this iPhone of reminders Doddy added to Apple Reminders. Deleting them here, or deleting all memories, doesn't remove the reminders themselves.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle("Reminders from Doddy")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isWorking)
        .task { await load() }
    }

    private func load() async {
        actions = (try? await environment.reminderStore?.recent(limit: 50)) ?? []
    }

    /// "Check again" only looks; "Add it now" looks first and adds only if it isn't there.
    private func reconcile(_ action: ReminderAction, create: Bool) async {
        guard let executor = environment.reminderExecutor else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let updated: ReminderAction
            if action.state == .verifiedFailed {
                updated = try await executor.confirmAndCreate(action.payload, operationID: action.operationID, sourceMemoryID: action.sourceMemoryID)
            } else {
                updated = try await executor.reconcile(action, createIfMissing: create)
            }
            message = ReminderCopy.status(updated)
        } catch {
            message = "Couldn't check Reminders right now. (\(error.localizedDescription))"
        }
        await load()
    }
}
