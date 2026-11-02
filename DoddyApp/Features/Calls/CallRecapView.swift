import DoddyCore
import SwiftUI

/// Settings → Phone calls → a recent call: its recap (ADR-684). Only what the server built from the
/// call's transcript; the notes it lists wait in "Notes from your calls" until the user saves them.
struct CallRecapView: View {
    let call: CallRecord
    @State private var model: CallRecapModel
    @State private var confirmDelete = false
    @Environment(\.dismiss) private var dismiss

    init(call: CallRecord) {
        self.call = call
        _model = State(initialValue: CallRecapModel(
            callId: call.id, client: ServerConfig.client(), repository: AppEnvironment.shared.callRecapRepository))
    }

    var body: some View {
        Form {
            Section {
                StatusRow(title: call.direction == "inbound" ? NSLocalizedString("You called Doddy", comment: "")
                                                             : NSLocalizedString("Doddy called you", comment: ""),
                          value: DateText.full(call.createdDate))
            }
            content
            if let message = model.message {
                Section { Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.error) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle("Call recap")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if model.isWorking { ProgressView() } }
        .task { await model.load() }
        .confirmationDialog("Delete this recap?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete recap", role: .destructive) {
                Task { if await model.delete() { dismiss() } }
            }
        } message: {
            Text("It is deleted from this iPhone and from Doddy's server. Notes from the call stay in Notes from your calls.")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            EmptyView()
        case .waiting:
            Section {
                Text("Doddy is still writing the recap. It's usually ready a minute or two after the call ends.")
                Button("Try again") { Task { await model.load() } }
            }
        case .none:
            Section {
                Text("There's no recap for this call. Calls from before recaps, and calls whose transcript didn't reach Doddy's server, have none.")
            }
        case .gone(let state):
            Section { Text(Self.goneText(state)) }
        case .failed(let text):
            Section {
                Label(text, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.error)
                Button("Try again") { Task { await model.load() } }
            }
        case .saved(let stored):
            recap(stored)
        }
    }

    @ViewBuilder
    private func recap(_ stored: StoredCallRecap) -> some View {
        let r = stored.recap
        Section {
            if let summary = r.summary, r.hasSummary {
                Text(summary)
            } else {
                Text(CallRecapModel.text(for: r.missingSummaryReason ?? .unknown))
                    .foregroundStyle(Theme.secondaryText)
            }
            if let seconds = r.durationSecs {
                StatusRow(title: NSLocalizedString("Length", comment: ""),
                          value: Duration.seconds(seconds).formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated)))
            }
        } header: {
            Text("Summary")
        } footer: {
            if r.hasSummary {
                Text("Written by Doddy from what was said on the call. If something looks wrong, the transcript below is what was said.")
            }
        }

        if !r.agreed.isEmpty {
            Section("Settled on the call") {
                ForEach(Array(r.agreed.enumerated()), id: \.offset) { _, item in pointer(item) }
            }
        }

        if !r.couldNotDo.isEmpty {
            Section("Doddy couldn't do this on a call") {
                ForEach(Array(r.couldNotDo.enumerated()), id: \.offset) { _, item in pointer(item) }
            }
        }

        if !r.notes.isEmpty {
            Section {
                ForEach(r.notes) { note in Text(note.text) }
            } header: {
                Text("Notes Doddy took")
            } footer: {
                Text("Doddy wrote these down on the call. Each becomes a memory only when you save it in Notes from your calls.")
            }
        }

        if let next = r.nextStep {
            Section("Next step") { Text(next) }
        }

        if !r.transcript.isEmpty {
            Section {
                DisclosureGroup("Transcript") {
                    ForEach(Array(r.transcript.enumerated()), id: \.offset) { _, line in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.isDoddy ? NSLocalizedString("Doddy", comment: "") : NSLocalizedString("You", comment: ""))
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.secondaryText)
                            Text(line.text)
                        }
                    }
                }
            } footer: {
                Text("A PIN said on the call is shown as ••••.")
            }
        }

        Section {
            Button("Delete recap", role: .destructive) { confirmDelete = true }
                .accessibilityIdentifier("callRecap.delete")
        } footer: {
            Text(stored.serverCopyPending
                 ? NSLocalizedString("Saved on this iPhone. Doddy's server still has its copy; it's deleted the next time you open this recap.", comment: "")
                 : NSLocalizedString("Saved on this iPhone only. Doddy's server deleted its copy.", comment: ""))
        }
    }

    private func pointer(_ item: CallRecapPointer) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.text)
            Text(String(format: NSLocalizedString("Said: “%@”", comment: ""), item.quote))
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    static func goneText(_ state: CallRecapState) -> String {
        switch state {
        case .acked: NSLocalizedString("This recap was saved on another device and deleted from Doddy's server, so it isn't on this iPhone.", comment: "")
        case .deleted: NSLocalizedString("This recap was deleted.", comment: "")
        case .expired: NSLocalizedString("This recap was deleted from Doddy's server after 30 days without being opened.", comment: "")
        default: NSLocalizedString("There's no recap for this call.", comment: "")
        }
    }
}
