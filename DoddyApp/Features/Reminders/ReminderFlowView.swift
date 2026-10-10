import DoddyCore
import SwiftUI
import UIKit

/// Add a memory to Apple Reminders: explain access → draft → approve the exact details →
/// receipt that says only what Doddy verified (M4, UX-02/UX-03).
struct ReminderFlowView: View {
    @State private var model: ReminderFlowModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(ledger: ActionLedger, client: any RemindersClient, suggestedTitle: String) {
        _model = State(initialValue: ReminderFlowModel(ledger: ledger, client: client, suggestedTitle: suggestedTitle))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    content
                    if let problem = model.problem {
                        ProblemView(message: problem)
                            .accessibilityIdentifier("reminder.problem")
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .background(Theme.canvas)
            .navigationTitle("Add to Reminders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(model.record?.status.isTerminal == true ? "Done" : "Close") { dismiss() }
                        .disabled(model.isWorking)
                }
            }
            .foregroundStyle(Theme.ink)
            .task { await model.start() }
            // Coming back from Settings: access may have changed.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, model.record == nil { Task { await model.start() } }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let record = model.record {
            statusHeader(record)
            switch record.status {
            case .proposed, .drafted, .needsApproval:
                if model.isEditing { form(updating: true) } else { approvalCard }
            case .executing, .confirmed, .failed, .unknown, .cancelled:
                receipt(record)
            }
        } else {
            switch model.access {
            case .checking:
                ProgressView().frame(maxWidth: .infinity)
            case .notAsked:
                accessExplanation
            case .off:
                accessOff
            case .restricted:
                Text("Reminders access is restricted on this iPhone (for example by Screen Time), so Doddy can't add reminders. Nothing was added.")
            case .noList:
                Text("Reminders has no list to add to. Open the Reminders app once, then try again. Nothing was added.")
            case .ready:
                form(updating: false)
            }
        }
    }

    // MARK: Access (asked only here, when you first add a reminder)

    private var accessExplanation: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Doddy needs access to Reminders")
                .font(.title3.bold())
            Text("iOS only offers full access, so Doddy could read your reminders. It uses access only to add the reminders you approve and to check they were saved. Your reminders stay on your iPhone and in your iCloud account, as before.")
            Button("Continue") { Task { await model.requestAccess() } }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("reminder.continue")
            Button("Not now") { dismiss() }
                .buttonStyle(SecondaryButtonStyle())
        }
    }

    private var accessOff: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Reminders access is off for Doddy. Nothing was added.")
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    // MARK: Form

    private func form(updating: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Reminder").font(.subheadline.bold())
                TextField("What to remember", text: $model.title, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(12)
                    .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("reminder.title")
            }
            Toggle("Remind me at a time", isOn: $model.hasDueDate)
            if model.hasDueDate {
                DatePicker("When", selection: $model.dueDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    .environment(\.timeZone, model.timeZone)
                StatusRow(title: "Time zone", value: ReminderText.zone(model.timeZone, at: model.dueDate))
            }
            if let list = model.spec?.list {
                StatusRow(title: "List", value: list.title)
            }
            if updating {
                Button("Update draft") { Task { await model.saveEdits() } }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(model.isWorking)
                    .accessibilityIdentifier("reminder.updateDraft")
                Text("Changing the draft clears any earlier approval.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                Button("Review") { Task { await model.draft() } }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(model.isWorking || model.title.allSatisfy(\.isWhitespace))
                    .accessibilityIdentifier("reminder.review")
                Text("Nothing is added until you approve it on the next screen.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    // MARK: Approval: exactly what will be written

    @ViewBuilder
    private var approvalCard: some View {
        if let spec = model.shownSpec {
            VStack(alignment: .leading, spacing: 16) {
                StatusRow(title: "What", value: "Add a reminder")
                StatusRow(title: "Reminder", value: spec.title)
                StatusRow(title: "When", value: spec.due.map { ReminderText.when($0, in: spec.timeZone) } ?? "No date or time")
                if let due = spec.due {
                    StatusRow(title: "Time zone", value: ReminderText.zone(spec.timeZone, at: due))
                }
                StatusRow(title: "List", value: spec.list.title)
                StatusRow(title: "Can it be undone?", value: "Yes, delete it in Reminders. Doddy won't delete it for you.")
                Text("Doddy adds a note (“Added by Doddy… Ref: …”) so it can check the reminder was saved.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)

                Button {
                    Task { await model.approveAndAdd() }
                } label: {
                    HStack { Text("Approve and add"); Spacer(); Image(systemName: "checkmark") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.isWorking || model.record?.status != .needsApproval)
                .accessibilityIdentifier("reminder.approve")

                Button("Edit") { model.isEditing = true }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(model.isWorking)
                Button("Cancel") { Task { await model.cancel() } }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(model.isWorking)
                    .accessibilityIdentifier("reminder.cancel")
            }
        }
    }

    // MARK: Receipt

    private func statusHeader(_ record: ActionRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ActionStatusCopy.label(record.status))
                .font(.title2.bold())
                .accessibilityIdentifier("reminder.status")
            Text(ActionStatusCopy.summary(record))
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private func receipt(_ record: ActionRecord) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let spec = model.shownSpec {
                StatusRow(title: "Reminder", value: spec.title)
                StatusRow(title: "When", value: spec.due.map { ReminderText.when($0, in: spec.timeZone) } ?? "No date or time")
                StatusRow(title: "List", value: spec.list.title)
            }
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
                    HStack { Text("Check Reminders"); Spacer(); Image(systemName: "arrow.clockwise") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.isWorking)
                .accessibilityIdentifier("reminder.checkStatus")
                Text("Checking only looks for Doddy's reminder in Reminders. It never adds it again.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }
}

enum ReminderText {
    static func when(_ date: Date, in timeZone: TimeZone) -> String {
        date.formatted(Date.FormatStyle(date: .complete, time: .shortened, timeZone: timeZone))
    }

    static func zone(_ timeZone: TimeZone, at date: Date) -> String {
        let abbreviation = timeZone.abbreviation(for: date).map { " (\($0))" } ?? ""
        return timeZone.identifier + abbreviation
    }
}
