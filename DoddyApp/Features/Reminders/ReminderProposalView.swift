import DoddyCore
import SwiftUI
import UIKit

/// Review screen for one reminder. Nothing reaches Apple Reminders until the user taps "Add to
/// Reminders"; the result shown is what Doddy read back from Reminders afterwards.
struct ReminderProposalView: View {
    let initialTitle: String
    let initialDue: ReminderDueParse
    let sourceMemoryID: UUID?
    /// Called once with the final action (nil = cancelled).
    let onFinish: (ReminderAction?) -> Void

    @Environment(\.appEnvironment) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var operationID = UUID()
    @State private var title = ""
    @State private var hasDue = false
    @State private var includeTime = true
    @State private var dueDate = Date()
    @State private var mustChooseDate = false
    @State private var clarification: String?
    @State private var result: ReminderAction?
    @State private var isWorking = false
    @State private var errorText: String?
    @State private var started = false
    @State private var finished = false

    private var timeZone: TimeZone { .current }

    private var payload: ReminderPayload {
        ReminderPayload(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            due: hasDue ? ReminderDue(date: dueDate, includesTime: includeTime, timeZone: timeZone) : nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let result {
                    resultSection(result)
                } else {
                    draftSections
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .navigationTitle("Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if result == nil {
                        Button("Cancel") { finish(nil) }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if let result {
                        Button("Done") { finish(result) }
                    }
                }
            }
            .disabled(isWorking)
            .overlay { if isWorking { ProgressView() } }
            .interactiveDismissDisabled(isWorking)
        }
        .onAppear(perform: prefill)
        // Swiping the sheet away still reports back (the voice agent is waiting for an answer).
        .onDisappear { if !finished { finished = true; onFinish(result) } }
    }

    @ViewBuilder
    private var draftSections: some View {
        Section("What") {
            TextField("Reminder", text: $title, axis: .vertical)
                .accessibilityIdentifier("reminder.title")
        }
        Section {
            Toggle("Remind me on a date", isOn: $hasDue)
            if hasDue {
                Toggle("At a time", isOn: $includeTime)
                DatePicker("When", selection: $dueDate, in: Date()...,
                           displayedComponents: includeTime ? [.date, .hourAndMinute] : [.date])
                    .onChange(of: dueDate) { _, _ in mustChooseDate = false; clarification = nil }
                Text(dueSummary)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityIdentifier("reminder.dueSummary")
            }
            if let clarification {
                Label(clarification, systemImage: "calendar.badge.exclamationmark")
                    .foregroundStyle(Theme.error)
            }
        } header: {
            Text("When")
        }
        Section {
            Button("Add to Reminders") { Task { await create() } }
                .disabled(!canCreate)
                .accessibilityIdentifier("reminder.create")
            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.error)
            }
        } footer: {
            Text("Doddy adds this one reminder to your default list in Apple Reminders and checks it's there. Deleting the note in Doddy won't delete the reminder.")
        }
    }

    private var canCreate: Bool {
        !payload.title.isEmpty && !(hasDue && mustChooseDate)
    }

    private var dueSummary: String {
        guard hasDue else { return "" }
        let date = dueDate.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
        let time = includeTime ? " at \(dueDate.formatted(date: .omitted, time: .shortened))" : " (no time)"
        return "\(date)\(time) · \(timeZone.identifier)"
    }

    @ViewBuilder
    private func resultSection(_ action: ReminderAction) -> some View {
        Section {
            Label(ReminderCopy.status(action), systemImage: action.state == .verifiedSucceeded ? "checkmark.circle" : "exclamationmark.triangle")
                .accessibilityIdentifier("reminder.result")
            StatusRow(title: "Reminder", value: action.payload.title)
            if let due = action.payload.due, let date = due.instant {
                StatusRow(title: "When", value: due.hasTime ? date.formatted(date: .abbreviated, time: .shortened) : date.formatted(date: .abbreviated, time: .omitted))
            }
        }
        if action.state == .verifiedFailed || action.state == .unknownOutcome {
            Section {
                if action.errorCode == "permission_denied", let url = URL(string: UIApplication.openSettingsURLString) {
                    Link("Open iOS Settings", destination: url)
                }
                Button(action.state == .unknownOutcome ? "Check Reminders again" : "Try again") {
                    Task { await create() }
                }
            }
        }
    }

    private func prefill() {
        guard !started else { return }
        started = true
        title = String(initialTitle.prefix(ReminderPayload.maxTitle))
        switch initialDue {
        case .none:
            hasDue = false
        case .due(let due):
            hasDue = true
            includeTime = due.hasTime
            dueDate = due.instant ?? Date()
        case .needsClarification(let message):
            // Never guess: the user has to pick a date before "Add" is enabled.
            hasDue = true
            mustChooseDate = true
            clarification = message
            dueDate = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        }
    }

    private func create() async {
        guard let executor = environment.reminderExecutor else {
            errorText = "Reminders aren't available in this build."
            return
        }
        isWorking = true
        errorText = nil
        defer { isWorking = false }
        do {
            result = try await executor.confirmAndCreate(payload, operationID: operationID, sourceMemoryID: sourceMemoryID)
        } catch let error as ReminderError {
            errorText = switch error {
            case .emptyTitle: "Write what to be reminded of."
            case .titleTooLong: "That's too long for a reminder."
            case .dueInvalid(let message): message
            default: "Couldn't add the reminder. Nothing was added."
            }
        } catch {
            errorText = "Couldn't save the reminder record on this iPhone, so nothing was added. (\(error.localizedDescription))"
        }
    }

    private func finish(_ action: ReminderAction?) {
        guard !finished else { return }
        finished = true
        onFinish(action)
        dismiss()
    }
}
