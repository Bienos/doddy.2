import DoddyCore
import SwiftUI

/// What Today's reminder sheet is for: a new reminder, or one the row showed.
enum ReminderEditTarget: Identifiable {
    case add
    case edit(ReminderSummary)

    var id: String {
        switch self {
        case .add: "add"
        case .edit(let reminder): reminder.id
        }
    }
}

/// Changing, ticking off, deleting or adding a reminder from Today (owner, 13 Nov 2026: "fajne te przypomnienia, ale
/// zero edycji"). The sheet only collects the title and the date; `TodayModel` writes to Reminders, reads it back, and
/// the card under it says what happened. A due is moved or added here, never cleared (`ReminderEdit`).
struct ReminderEditSheet: View {
    let target: ReminderEditTarget
    let save: @MainActor (String, ReminderDue?) async -> Void
    let complete: @MainActor (ReminderSummary) async -> Void
    let delete: @MainActor (ReminderSummary) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var hasDue = false
    @State private var hasTime = true
    @State private var due = Date()
    @State private var working = false
    @State private var confirmDelete = false
    @State private var loaded = false

    private var existing: ReminderSummary? {
        if case .edit(let reminder) = target { reminder } else { nil }
    }

    /// A reminder that has a due keeps one: this screen moves it, it doesn't clear it.
    private var dueLocked: Bool { existing?.due != nil }

    private var problem: ReminderEdit.Problem? {
        if case .failure(let problem) = ReminderEdit.title(title) { problem } else { nil }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What to remember", text: $title, axis: .vertical)
                        .lineLimit(1...4)
                        .accessibilityIdentifier("reminderEdit.title")
                    if problem == .titleTooLong {
                        Text("That title is too long for Reminders.").font(.footnote).foregroundStyle(Theme.error)
                    }
                }
                Section {
                    if !dueLocked {
                        Toggle("On a day", isOn: $hasDue.animation())
                    }
                    if hasDue || dueLocked {
                        DatePicker("Day", selection: $due, displayedComponents: .date)
                        Toggle("At a time", isOn: $hasTime.animation())
                        if hasTime {
                            DatePicker("Time", selection: $due, displayedComponents: .hourAndMinute)
                        }
                    }
                } footer: {
                    Text("Saved in Reminders on this iPhone, with an alert at the time. Doddy says it's saved only once Reminders shows it.")
                }
                if let reminder = existing {
                    Section {
                        Button {
                            run { await complete(reminder) }
                        } label: { Label("Mark as done", systemImage: "checkmark.circle") }
                            .accessibilityIdentifier("reminderEdit.done")
                        Button(role: .destructive) { confirmDelete = true } label: { Label("Delete reminder", systemImage: "trash") }
                            .accessibilityIdentifier("reminderEdit.delete")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .tint(Theme.accentText)
            .navigationTitle(existing == nil ? NSLocalizedString("New reminder", comment: "") : NSLocalizedString("Change reminder", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if working {
                        ProgressView()
                    } else {
                        Button("Save") {
                            let due: ReminderDue? = (hasDue || dueLocked) ? ReminderEdit.due(due, hasTime: hasTime, calendar: .current) : nil
                            let words = title
                            run { await save(words, due) }
                        }
                        .disabled(problem != nil)
                        .accessibilityIdentifier("reminderEdit.save")
                    }
                }
            }
            .confirmationDialog("Delete this reminder from Reminders?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let reminder = existing { run { await delete(reminder) } }
                }
            }
            .disabled(working)
            .onAppear(perform: load)
        }
        .presentationDetents([.medium, .large])
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let reminder = existing else {
            // A new reminder starts at the next full hour.
            let next = Calendar.current.nextDate(after: .now, matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? .now
            due = next
            return
        }
        title = reminder.title
        if let date = reminder.due {
            due = date
            hasDue = true
            hasTime = reminder.dueHasTime
        }
    }

    /// One write at a time; the sheet closes when it's done and the card says how it went.
    private func run(_ work: @escaping @MainActor () async -> Void) {
        guard !working else { return }
        working = true
        Task {
            await work()
            working = false
            dismiss()
        }
    }
}
