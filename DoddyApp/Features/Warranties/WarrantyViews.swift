import DoddyCore
import SwiftUI

/// On a note's screen (ADR-342): its warranty, or a button to add one.
struct WarrantySection: View {
    let record: MemoryRecord
    @State private var warranty: Warranty?
    @State private var editing = false

    var body: some View {
        Group {
            if let warranty {
                Button { editing = true } label: {
                    HStack {
                        Image(systemName: "checkmark.shield")
                        Text(WarrantyText.summary(warranty))
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Theme.secondaryText)
                    }
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Change or remove the warranty"))
            } else {
                Button { editing = true } label: {
                    HStack { Text("Add a warranty"); Spacer(); Image(systemName: "checkmark.shield") }
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .accessibilityIdentifier("detail.warranty")
        .sheet(isPresented: $editing, onDismiss: load) { WarrantySheet(record: record) }
        .onAppear(perform: load)
    }

    private func load() { warranty = WarrantyStore.current().warranty(for: record.id) }
}

/// Doddy suggests the date and length from the note's words; the user checks them. Nothing is
/// kept until Save, and the reminder is set only if the switch is on at Save.
struct WarrantySheet: View {
    let record: MemoryRecord
    @Environment(NoteReminderStore.self) private var reminders
    @Environment(\.dismiss) private var dismiss
    @State private var purchased = Date.now
    @State private var months = WarrantyReading.defaultMonths
    @State private var title = ""
    @State private var remind = true
    @State private var suggestion: WarrantySuggestion?
    @State private var exists = false
    @State private var problem: String?
    @State private var working = false

    private var draft: Warranty { Warranty(id: record.id, purchased: purchased, months: months, title: title) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What it is", text: $title)
                    DatePicker("Bought on", selection: $purchased, in: ...Date.now, displayedComponents: .date)
                    Stepper(value: $months, in: WarrantyReading.monthsRange) {
                        Text(String(format: NSLocalizedString("Warranty: %lld months", comment: ""), months))
                    }
                } footer: {
                    if let suggestion, suggestion.purchased != nil || suggestion.months != nil {
                        Text("Filled in from the note's words. Check them against the receipt.")
                    } else {
                        Text("Doddy couldn't read a date or a length from this note, so check both.")
                    }
                }
                Section {
                    Text(String(format: NSLocalizedString("Ends %@", comment: "Warranty end"),
                                draft.ends(calendar: .current).formatted(date: .long, time: .omitted)))
                    if draft.reminderDate(calendar: .current, now: .now) != nil {
                        Toggle("Remind me a month before", isOn: $remind)
                        if reminders.reminder(forMemory: record.id) != nil {
                            Text("This note already has a reminder; this one replaces it.")
                                .font(.footnote).foregroundStyle(Theme.secondaryText)
                        }
                    } else {
                        Text("It ends within a month, so there's no reminder to set.")
                            .font(.footnote).foregroundStyle(Theme.secondaryText)
                    }
                } footer: {
                    Text("The length is what the receipt or you say. Doddy doesn't know your rights as a buyer.")
                }
                if let problem { Section { Text(problem).foregroundStyle(Theme.error) } }
                if exists {
                    Section {
                        Button("Remove the warranty", role: .destructive) {
                            if WarrantyStore.remove(record.id) { dismiss() } else { problem = NSLocalizedString("It couldn't be removed. Try again.", comment: "") }
                        }
                    }
                }
            }
            .navigationTitle("Warranty")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }.disabled(working || title.allSatisfy(\.isWhitespace))
                }
            }
            .onAppear(perform: fill)
        }
    }

    private func fill() {
        if let kept = WarrantyStore.current().warranty(for: record.id) {
            exists = true
            purchased = kept.purchased
            months = kept.months
            title = kept.title
            remind = false
            return
        }
        let found = WarrantyReading.suggest(from: record.currentText, now: .now, calendar: .current)
        suggestion = found
        purchased = found.purchased ?? .now
        months = found.months ?? WarrantyReading.defaultMonths
        title = String(record.currentText.split(whereSeparator: \.isNewline).first.map(String.init)?.prefix(80) ?? "")
    }

    private func save() async {
        working = true
        defer { working = false }
        switch WarrantyStore.save(draft) {
        case .saved?, .replaced?:
            if remind, let date = draft.reminderDate(calendar: .current, now: .now) {
                // An ordinary note reminder: the note's screen shows what iOS confirmed.
                await reminders.set(memoryID: record.id, at: date)
            }
            dismiss()
        case .full?:
            problem = NSLocalizedString("Doddy keeps up to 200 warranties. Remove an old one first.", comment: "")
        case .invalid?:
            problem = NSLocalizedString("The length must be 1 to 120 months.", comment: "")
        case nil:
            problem = NSLocalizedString("It wasn't saved. Try again.", comment: "")
        }
    }
}

/// Every warranty, the soonest to end first (ADR-342). Opened from Notes when there are any.
struct WarrantiesView: View {
    @Environment(MemoryStore.self) private var store
    @State private var items: [Warranty] = []

    var body: some View {
        List {
            ForEach(items) { warranty in
                NavigationLink(value: MemoryNavigationRoute.note(warranty.id)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(warranty.title)
                        Text(WarrantyText.summary(warranty)).font(.footnote).foregroundStyle(Theme.secondaryText)
                    }
                    .frame(minHeight: 44, alignment: .leading)
                }
            }
        }
        .navigationTitle("Warranties")
        .onAppear {
            WarrantyStore.prune(keeping: Set(store.memories.map(\.id)))
            // A private note's warranty shows only after Face ID (ADR-310): its title is the note's words.
            let hidden = AppLock.shared.privateUnlocked ? [] : PrivateNotesStore.current().ids
            items = WarrantyStore.current().sorted(calendar: .current, now: .now).filter { !hidden.contains($0.id) }
        }
    }
}

enum WarrantyText {
    static func summary(_ warranty: Warranty) -> String {
        let end = warranty.ends(calendar: .current)
        let day = end.formatted(date: .abbreviated, time: .omitted)
        return end < .now
            ? String(format: NSLocalizedString("Warranty ended %@", comment: ""), day)
            : String(format: NSLocalizedString("Warranty until %@", comment: ""), day)
    }
}
