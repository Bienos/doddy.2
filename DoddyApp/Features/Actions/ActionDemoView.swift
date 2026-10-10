import DoddyCore
import SwiftUI

/// SIMULATION of how Doddy asks before acting (UX-02 action receipts, UX-03 approval).
/// Nothing is sent and no contact is used; every screen says so.
struct ActionDemoView: View {
    @State private var model: ActionDemoModel
    @State private var confirmDeleteHistory = false

    init(ledger: ActionLedger, simulation: SimulatedActionAdapter) {
        _model = State(initialValue: ActionDemoModel(ledger: ledger, adapter: simulation))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                banner

                if let record = model.record {
                    statusHeader(record)
                    switch record.status {
                    case .proposed, .drafted, .needsApproval:
                        approvalCard(record)
                    case .executing, .confirmed, .failed, .unknown, .cancelled:
                        receiptCard(record)
                    }
                } else if model.hasLoaded {
                    intro
                }

                if model.hasLoaded {
                    recentSection
                }

                if let problem = model.problem {
                    ProblemView(message: problem)
                        .accessibilityIdentifier("actions.problem")
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .background(Theme.canvas)
        .navigationTitle("Approval flow")
        .navigationBarTitleDisplayMode(.inline)
        .foregroundStyle(Theme.ink)
        .task { await model.load() }
        .confirmationDialog("Delete action history?", isPresented: $confirmDeleteHistory, titleVisibility: .visible) {
            Button("Delete history", role: .destructive) { Task { await model.deleteHistory() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every saved action from this iPhone, including any Doddy couldn't confirm. It can't be undone. Older backups aren't affected.")
        }
    }

    // MARK: Saved actions (persist across restarts)

    @ViewBuilder
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Earlier actions (simulated)")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            if model.recent.isEmpty {
                Text("None saved yet.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                ForEach(model.recent) { earlier in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(ActionStatusCopy.label(earlier.status)) · \(earlier.payload.target)")
                        Text(DateText.full(earlier.updatedAt))
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .accessibilityElement(children: .combine)
                    Divider()
                }
            }
            Text("Actions are saved on this iPhone so their status survives a restart, and are included in device backups. Finished ones are removed after 30 days.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
            Button("Delete action history", role: .destructive) { confirmDeleteHistory = true }
                .disabled(model.isWorking || (model.recent.isEmpty && model.record == nil))
                .accessibilityIdentifier("actions.deleteHistory")
        }
    }

    private var banner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Simulation: nothing is sent", systemImage: "testtube.2")
                .font(.headline)
            Text("This shows how Doddy will ask before doing something outside the app. No message leaves this iPhone and no real contact is used.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("actions.banner")
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Doddy drafts, you check the exact details, and only your tap approves it. If the result can't be confirmed, Doddy says so and won't send it twice.")
            Button {
                Task { await model.draftSample() }
            } label: {
                HStack { Text("Draft a sample message"); Spacer(); Image(systemName: "square.and.pencil") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.isWorking)
            .accessibilityIdentifier("actions.draftSample")
        }
    }

    private func statusHeader(_ record: ActionRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ActionStatusCopy.label(record.status))
                .font(.title2.bold())
                .accessibilityIdentifier("actions.status")
            Text(ActionStatusCopy.summary(record))
                .foregroundStyle(Theme.secondaryText)
                .accessibilityIdentifier("actions.summary")
        }
    }

    // MARK: Approval (what / who / via / permanence, editable)

    private func approvalCard(_ record: ActionRecord) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            StatusRow(title: "What", value: "Send a message")
            VStack(alignment: .leading, spacing: 6) {
                Text("To").font(.subheadline.bold())
                TextField("Recipient", text: $model.recipient)
                    .textInputAutocapitalization(.words)
                    .padding(12)
                    .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("actions.recipient")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Message").font(.subheadline.bold())
                TextEditor(text: $model.text)
                    .frame(minHeight: 100)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("Message")
                    .accessibilityIdentifier("actions.text")
            }
            StatusRow(title: "Via", value: "Simulation (test adapter)")
            StatusRow(title: "Can it be undone?", value: "No. A sent message can't be unsent.")

            if model.hasUnsavedEdits {
                Button("Update draft") { Task { await model.saveEdits() } }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(model.isWorking)
                    .accessibilityIdentifier("actions.updateDraft")
                Text("Update the draft before approving. Changing it clears any earlier approval.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }

            Picker("Simulated result", selection: $model.outcome) {
                ForEach(SimulatedActionAdapter.Outcome.allCases, id: \.self) { outcome in
                    Text(outcome.displayName).tag(outcome)
                }
            }
            .accessibilityIdentifier("actions.outcome")

            Button {
                Task { await model.approveAndSend() }
            } label: {
                HStack { Text("Approve and send (simulated)"); Spacer(); Image(systemName: "checkmark") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!model.isAwaitingApproval || model.hasUnsavedEdits || model.isWorking)
            .accessibilityIdentifier("actions.approve")

            Button("Cancel") { Task { await model.cancel() } }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(model.isWorking)
                .accessibilityIdentifier("actions.cancel")
        }
    }

    // MARK: Receipt (what actually happened)

    private func receiptCard(_ record: ActionRecord) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            StatusRow(title: "To", value: record.payload.target)
            StatusRow(title: "Message", value: record.payload.value(for: "text") ?? "")
            StatusRow(title: "Provider reference", value: record.providerReference ?? "None")
            StatusRow(title: "Via", value: record.isSimulation ? "Simulation (test adapter)" : record.connectorID)

            VStack(alignment: .leading, spacing: 8) {
                Text("What happened").font(.headline).accessibilityAddTraits(.isHeader)
                ForEach(Array(record.history.enumerated()), id: \.offset) { _, event in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(ActionStatusCopy.label(event.status))\(event.note.map { " · \($0)" } ?? "")")
                        Text(DateText.full(event.at))
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            if record.status == .unknown {
                Button {
                    Task { await model.checkStatus() }
                } label: {
                    HStack { Text("Check status"); Spacer(); Image(systemName: "arrow.clockwise") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.isWorking)
                .accessibilityIdentifier("actions.checkStatus")
                Text("Checking only asks the provider what happened. It never sends the message again.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }

            if record.status.isTerminal || record.status == .unknown {
                Button("Start over") { Task { await model.startOver() } }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(model.isWorking)
                    .accessibilityIdentifier("actions.startOver")
            }
        }
    }
}
