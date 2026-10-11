import DoddyCore
import SwiftUI

/// Bills and subscriptions (ADR-344): what the user typed in, soonest first, with a rough monthly
/// cost. Opened from Lists.
struct RenewalsView: View {
    @State private var items: [(renewal: Renewal, next: Date)] = []
    @State private var totals: (totals: [(currency: String, amount: Decimal)], withoutAmount: Int) = ([], 0)
    @State private var editing: Renewal?
    @State private var adding = false

    var body: some View {
        List {
            if items.isEmpty {
                Section {
                    Text("Add what renews, like rent, a phone plan or a streaming service. Doddy can remind you a few days before.")
                        .foregroundStyle(Theme.secondaryText)
                }
            } else {
                Section {
                    ForEach(items, id: \.renewal.id) { item in
                        Button { editing = item.renewal } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(item.renewal.name)
                                    Spacer()
                                    if let amount = item.renewal.amount, let currency = item.renewal.currency {
                                        Text(amount.formatted(.currency(code: currency)))
                                    }
                                }
                                Text(RenewalText.next(item.next, cycle: item.renewal.cycle))
                                    .font(.footnote).foregroundStyle(Theme.secondaryText)
                            }
                            .frame(minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    if !totals.totals.isEmpty {
                        Text(RenewalText.totals(totals.totals, withoutAmount: totals.withoutAmount))
                    }
                }
            }
            Section {
                Text("You type these in. Doddy doesn't read your bank, cards or email, and nothing leaves this iPhone.")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            }
        }
        .navigationTitle("Bills and subscriptions")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { adding = true } label: { Image(systemName: "plus").frame(width: 44, height: 44) }
                    .accessibilityLabel("Add a bill or subscription")
                    .disabled(items.count >= Renewals.limit)
            }
        }
        .sheet(isPresented: $adding, onDismiss: load) { RenewalSheet(existing: nil) }
        .sheet(item: $editing, onDismiss: load) { RenewalSheet(existing: $0) }
        .onAppear(perform: load)
    }

    private func load() {
        let all = RenewalStore.current()
        items = all.upcoming(now: .now, calendar: .current)
        totals = all.monthlyTotals()
    }
}

struct RenewalSheet: View {
    let existing: Renewal?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var hasAmount = false
    @State private var amount: Decimal = 0
    @State private var currency = Locale.current.currency?.identifier ?? "PLN"
    @State private var cycle: RenewalCycle = .monthly
    @State private var start = Date.now
    @State private var remind = true
    @State private var days = 3
    @State private var problem: String?
    @State private var working = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, e.g. Netflix or rent", text: $name)
                    Picker("Renews", selection: $cycle) {
                        Text("Every week").tag(RenewalCycle.weekly)
                        Text("Every month").tag(RenewalCycle.monthly)
                        Text("Every 3 months").tag(RenewalCycle.quarterly)
                        Text("Every year").tag(RenewalCycle.yearly)
                    }
                    DatePicker("Next on", selection: $start, displayedComponents: .date)
                }
                Section {
                    Toggle("Amount", isOn: $hasAmount)
                    if hasAmount {
                        TextField("Amount", value: $amount, format: .number).keyboardType(.decimalPad)
                        TextField("Currency (3 letters)", text: $currency).textInputAutocapitalization(.characters)
                    }
                }
                Section {
                    Toggle("Remind me before", isOn: $remind)
                    if remind {
                        Stepper(value: $days, in: 0...Renewal.maxRemindDays) {
                            Text(days == 0 ? NSLocalizedString("On the day, at 9:00", comment: "")
                                 : String(format: NSLocalizedString("%lld days before, at 9:00", comment: ""), days))
                        }
                    }
                }
                if let problem { Section { Text(problem).foregroundStyle(Theme.error) } }
                if let existing {
                    Section {
                        Button("Delete", role: .destructive) {
                            Task {
                                if await RenewalStore.remove(existing.id) { dismiss() } else { problem = NSLocalizedString("It couldn't be removed. Try again.", comment: "") }
                            }
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? Text("New bill or subscription") : Text("Bill or subscription"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }.disabled(working)
                }
            }
            .onAppear(perform: fill)
        }
    }

    private func fill() {
        guard let existing else { return }
        name = existing.name
        hasAmount = existing.amount != nil
        amount = existing.amount ?? 0
        currency = existing.currency ?? currency
        cycle = existing.cycle
        start = existing.next(after: .now, calendar: .current)
        remind = existing.remindDaysBefore != nil
        days = existing.remindDaysBefore ?? 3
    }

    private func save() async {
        working = true
        defer { working = false }
        let renewal = Renewal(id: existing?.id ?? UUID(), name: name, amount: hasAmount ? amount : nil,
                              currency: hasAmount ? currency : nil, cycle: cycle, start: start,
                              remindDaysBefore: remind ? days : nil)
        switch await RenewalStore.save(renewal) {
        case .saved: dismiss()
        case .savedWithoutReminder:
            problem = NSLocalizedString("Saved, but notifications are off for Doddy, so no reminder will show. You can allow them in iPhone Settings.", comment: "")
        case .problem(let reason): problem = RenewalText.problem(reason)
        case .notSaved: problem = NSLocalizedString("It wasn't saved. Try again.", comment: "")
        }
    }
}

enum RenewalText {
    static func next(_ date: Date, cycle: RenewalCycle) -> String {
        let day = date.formatted(date: .abbreviated, time: .omitted)
        let how: String = switch cycle {
        case .weekly: NSLocalizedString("every week", comment: "Renewal")
        case .monthly: NSLocalizedString("every month", comment: "Renewal")
        case .quarterly: NSLocalizedString("every 3 months", comment: "Renewal")
        case .yearly: NSLocalizedString("every year", comment: "Renewal")
        }
        return String(format: NSLocalizedString("Next %@, %@", comment: "Renewal date and cycle"), day, how)
    }

    static func totals(_ totals: [(currency: String, amount: Decimal)], withoutAmount: Int) -> String {
        let sums = totals.map { $0.amount.formatted(.currency(code: $0.currency)) }.joined(separator: " + ")
        var text = String(format: NSLocalizedString("About %@ a month.", comment: "Renewals total"), sums)
        if withoutAmount > 0 {
            text += " " + String(format: NSLocalizedString("%lld without an amount aren't counted.", comment: ""), withoutAmount)
        }
        return text
    }

    static func problem(_ problem: RenewalProblem) -> String {
        switch problem {
        case .noName: NSLocalizedString("Give it a name.", comment: "")
        case .badAmount: NSLocalizedString("The amount must be more than 0.", comment: "")
        case .badCurrency: NSLocalizedString("Write the currency as 3 letters, like PLN or EUR.", comment: "")
        case .badReminder: NSLocalizedString("Remind up to 14 days before.", comment: "")
        case .full: NSLocalizedString("Doddy keeps up to 100. Delete one first.", comment: "")
        }
    }
}
