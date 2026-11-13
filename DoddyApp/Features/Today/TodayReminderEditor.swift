import DoddyCore
import SwiftUI
import UIKit

/// What the reminder sheet opens for.
enum TodayReminderTarget: Identifiable {
    case add
    case edit(ReminderSnapshot)

    var id: String {
        switch self {
        case .add: "add"
        case .edit(let reminder): "edit-" + reminder.id
        }
    }
}

/// Today's reminder sheet (owner, 13 Nov 2026: "fajne te przypomnienia, ale zero edycji"): add one to the
/// default Reminders list, or change the title, day and time, and notes of one, or delete it. Each write
/// goes to Reminders and is read back before the list shows it (`TodayModel`); when something goes wrong the
/// sheet stays open with what was typed and says what happened.
struct TodayReminderEditor: View {
    let target: TodayReminderTarget
    let model: TodayModel

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var notes: String
    @State private var hasDue: Bool
    @State private var hasTime: Bool
    @State private var due: Date
    @State private var problem: String?
    @State private var saving = false
    @State private var confirmDelete = false
    @FocusState private var titleFocused: Bool

    /// What the pickers showed when the sheet opened: unchanged, the reminder keeps its due exactly as read.
    private let startDue: Date
    private let startHasDue: Bool
    private let startHasTime: Bool

    init(target: TodayReminderTarget, model: TodayModel) {
        self.target = target
        self.model = model
        let local = Calendar.current
        let suggested = ReminderForm.suggestedDue(now: .now, calendar: local)
        let firstTitle: String
        let firstNotes: String
        let firstHasDue: Bool
        let firstHasTime: Bool
        let firstDue: Date
        switch target {
        case .add:
            firstTitle = ""
            firstNotes = ""
            firstHasDue = false
            firstHasTime = false
            firstDue = suggested
        case .edit(let reminder):
            firstTitle = reminder.title
            firstNotes = reminder.notes ?? ""
            firstHasDue = reminder.due != nil
            firstHasTime = reminder.due?.hasTime ?? false
            firstDue = ReminderForm.pickerDate(for: reminder.due, local: local, otherwise: suggested)
        }
        startHasDue = firstHasDue
        startHasTime = firstHasTime
        startDue = firstDue
        _title = State(initialValue: firstTitle)
        _notes = State(initialValue: firstNotes)
        _hasDue = State(initialValue: firstHasDue)
        _hasTime = State(initialValue: firstHasTime)
        _due = State(initialValue: firstDue)
    }

    private var editing: ReminderSnapshot? {
        if case .edit(let reminder) = target { reminder } else { nil }
    }

    /// Reminders refuses a repeating reminder without a day, so its day can be moved but not removed here.
    private var repeats: Bool { editing?.repeats != nil }

    private var titleReady: Bool {
        if case .ok = ReminderForm.checkTitle(title) { true } else { false }
    }

    var body: some View {
        NavigationStack {
            DoddyPage {
                header
                titleField
                dueCard
                notesField
                if let problem {
                    DoddyNotice(text: Text(verbatim: problem), isProblem: true)
                        .accessibilityIdentifier("today.reminder.problem")
                }
                saveButton
                if editing != nil {
                    deleteButton
                }
                DoddyFinePrint(text: Text("Saved in Reminders on this iPhone, so it shows wherever your Reminders do. Nothing here goes to Doddy's server."))
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(saving)
                }
            }
            .confirmationDialog("Delete this reminder?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { Task { await delete() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("It's deleted in Reminders too, not only from this list.")
            }
        }
        .interactiveDismissDisabled(saving)
        .onAppear { if editing == nil { titleFocused = true } }
    }

    // MARK: Pieces

    @ViewBuilder
    private var header: some View {
        if editing == nil {
            DoddyPageHeader(title: "Add a reminder", subtitle: "It goes in your default list in Reminders.")
        } else {
            DoddyPageHeader(title: "Change a reminder", subtitle: "Changes are saved in Reminders on this iPhone.")
        }
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What to remember")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
            TextField("Buy milk, call the dentist…", text: $title)
                .font(.body)
                .foregroundStyle(Theme.ink)
                .submitLabel(.done)
                .focused($titleFocused)
                .doddyField()
                .accessibilityIdentifier("today.reminder.title")
        }
    }

    private var dueCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $hasDue.animation()) {
                Label("On a day", systemImage: "calendar")
                    .foregroundStyle(Theme.ink)
            }
            .tint(Theme.orangeCue)
            .disabled(repeats && hasDue)
            .accessibilityIdentifier("today.reminder.hasDue")
            if hasDue {
                DatePicker("Day", selection: $due, displayedComponents: .date)
                    .foregroundStyle(Theme.ink)
                    .tint(Theme.accentText)
                Toggle(isOn: $hasTime.animation()) {
                    Label("At a time", systemImage: "clock")
                        .foregroundStyle(Theme.ink)
                }
                .tint(Theme.orangeCue)
                .accessibilityIdentifier("today.reminder.hasTime")
                if hasTime {
                    DatePicker("Time", selection: $due, displayedComponents: .hourAndMinute)
                        .foregroundStyle(Theme.ink)
                        .tint(Theme.accentText)
                }
            }
            if repeats {
                Text("This reminder repeats, so it keeps a day. Change or stop the repeat in Reminders.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else if hasDue && hasTime {
                Text("Reminders will alert you at this time.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if editing == nil {
                Text("Today lists reminders due today or tomorrow; the others are in Reminders.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .doddyCard()
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Notes")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
            TextField("Optional", text: $notes, axis: .vertical)
                .lineLimit(3...8)
                .font(.body)
                .foregroundStyle(Theme.ink)
                .doddyField()
                .accessibilityIdentifier("today.reminder.notes")
        }
    }

    private var saveButton: some View {
        Button {
            Task { await save() }
        } label: {
            HStack(spacing: 10) {
                if saving { ProgressView().tint(Theme.inkOnOrange) }
                Text(editing == nil ? "Add to Reminders" : "Save in Reminders")
            }
        }
        .buttonStyle(DoddyAccentButtonStyle())
        .disabled(saving || !titleReady)
        .accessibilityIdentifier("today.reminder.save")
    }

    private var deleteButton: some View {
        Button(role: .destructive) {
            confirmDelete = true
        } label: {
            Label("Delete reminder", systemImage: "trash")
                .font(.headline)
                .foregroundStyle(Theme.error)
                .frame(maxWidth: .infinity, minHeight: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(saving)
        .accessibilityIdentifier("today.reminder.delete")
    }

    // MARK: Writing

    /// The due as the sheet shows it. Left as it was, the reminder keeps exactly the due Reminders had
    /// (its own time zone included); otherwise the day, and the time if one is on.
    private func chosenDue(keeping original: ReminderDue?) -> ReminderDue? {
        let untouched = hasDue == startHasDue && hasTime == startHasTime && (!hasDue || due == startDue)
        if untouched { return original }
        guard hasDue else { return nil }
        return ReminderForm.due(from: due, hasTime: hasTime, calendar: .current)
    }

    private func save() async {
        guard !saving else { return }
        problem = nil
        saving = true
        let result: TodayModel.ReminderSaveResult
        if let before = editing {
            result = await model.saveReminder(before, title: title, notes: notes, due: chosenDue(keeping: before.due))
        } else {
            result = await model.addReminder(title: title, notes: notes, due: hasDue ? due : nil, hasTime: hasTime)
        }
        saving = false
        finish(result)
    }

    private func delete() async {
        guard !saving, let before = editing else { return }
        problem = nil
        saving = true
        let result = await model.deleteReminder(before)
        saving = false
        finish(result)
    }

    private func finish(_ result: TodayModel.ReminderSaveResult) {
        switch result {
        case .done:
            dismiss()
        case .problem(let text):
            problem = text
            UIAccessibility.post(notification: .announcement, argument: text)
        }
    }
}
