import DoddyCore
import SwiftUI

/// "Change" on one plan card step (ADR-205). The fields depend on the kind of step; Save runs the
/// edit through the same checks as the agent's call (`PlanStepForm.apply`) and says what to fix.
/// Nothing runs from here: the card's own button still does that.
struct PlanStepEditor: View {
    let step: PlanStep
    let onSave: (PlanStep) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var form: PlanStepForm
    @State private var problem: String?

    init(step: PlanStep, onSave: @escaping (PlanStep) -> Void) {
        self.step = step
        self.onSave = onSave
        _form = State(initialValue: PlanStepForm(step))
    }

    var body: some View {
        NavigationStack {
            Form {
                fields
                if let problem {
                    Section {
                        Label(problem, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.error)
                            .accessibilityIdentifier("planEdit.problem")
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .accessibilityIdentifier("planEdit.save")
                }
            }
        }
    }

    @ViewBuilder
    private var fields: some View {
        switch form.kind {
        case .note:
            Section("Note") {
                TextField("What to remember", text: $form.text, axis: .vertical)
                    .accessibilityIdentifier("planEdit.text")
            }
        case .reminder:
            Section("Reminder") {
                TextField("Title", text: $form.text)
                    .accessibilityIdentifier("planEdit.text")
                Toggle("Due date", isOn: $form.hasDate)
                if form.hasDate {
                    Toggle("At a time", isOn: $form.hasTime)
                    DatePicker("Due", selection: $form.start, displayedComponents: form.hasTime ? [.date, .hourAndMinute] : [.date])
                }
                TextField("Notes", text: $form.notes, axis: .vertical)
            }
        case .event:
            Section("Event") {
                TextField("Title", text: $form.text)
                    .accessibilityIdentifier("planEdit.text")
                Toggle("All day", isOn: Binding(get: { !form.hasTime }, set: { form.hasTime = !$0 }))
                DatePicker("Starts", selection: $form.start, displayedComponents: form.hasTime ? [.date, .hourAndMinute] : [.date])
                if form.hasTime {
                    DatePicker("Ends", selection: $form.end, displayedComponents: [.date, .hourAndMinute])
                }
                TextField("Place", text: $form.location)
                TextField("Notes", text: $form.notes, axis: .vertical)
            }
        case .timer:
            Section("Timer") {
                Stepper("\(form.minutes) min", value: $form.minutes, in: 0...1440)
                Stepper("\(form.seconds) s", value: $form.seconds, in: 0...59, step: 5)
                TextField("Label", text: $form.label)
            }
        }
        Section {
            Text("Times are in this iPhone's time zone. Doddy checks the change the same way as its own suggestion.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private var title: String {
        switch form.kind {
        case .note: "Change note"
        case .reminder: "Change reminder"
        case .event: "Change event"
        case .timer: "Change timer"
        }
    }

    private func save() {
        switch form.apply(to: step) {
        case .step(let changed):
            onSave(changed)
            dismiss()
        case .problem(let text):
            problem = text
        }
    }
}
