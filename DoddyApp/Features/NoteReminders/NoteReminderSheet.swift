import DoddyCore
import SwiftUI

/// "When should I bring this back?" Nothing is stored until Set reminder; the first time
/// notifications are undecided, a short explainer comes before the iOS prompt.
struct NoteReminderSheet: View {
    let memoryID: UUID

    @Environment(NoteReminderStore.self) private var reminders
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PreferenceKey.notificationExplainerSeen) private var explainerSeen = false

    private enum Choice: Hashable {
        case quick(ReminderQuickPick)
        case custom
    }

    @State private var options: [ReminderOption] = []
    @State private var choice: Choice = .quick(.tomorrowMorning)
    @State private var customDate = Date.now.addingTimeInterval(3600)
    @State private var showExplainer = false
    @State private var working = false

    private var resolvedDate: Date {
        switch choice {
        case .quick(let pick): options.first { $0.pick == pick }?.date ?? customDate
        case .custom: customDate
        }
    }

    private var zoneID: String { TimeZone.autoupdatingCurrent.identifier }

    var body: some View {
        NavigationStack {
            Group {
                if showExplainer { explainer } else { chooser }
            }
            .background(Theme.canvas)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(working)
                }
            }
        }
        .foregroundStyle(Theme.ink)
        .interactiveDismissDisabled(working)
        .onAppear(perform: prepare)
    }

    private var chooser: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("When should I bring this back?")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)

                VStack(spacing: 8) {
                    ForEach(options, id: \.pick) { option in
                        choiceRow(
                            .quick(option.pick), title: option.pick.title,
                            detail: ReminderFormat.dateTime(option.date, timeZoneID: zoneID))
                    }
                    choiceRow(.custom, title: "Pick a date and time", detail: nil)
                }

                if choice == .custom {
                    DatePicker(
                        "Date and time", selection: $customDate,
                        in: Date.now.addingTimeInterval(NoteReminderLimits.minimumLead * 2)...,
                        displayedComponents: [.date, .hourAndMinute])
                }

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "bell").accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ReminderFormat.dateTime(resolvedDate, timeZoneID: zoneID)).font(.headline)
                        Text("\(ReminderFormat.zoneName(zoneID)) · fires at this moment even if you travel")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityElement(children: .combine)

                Button { confirm() } label: {
                    HStack { Text(working ? "Setting…" : "Set reminder"); Spacer() }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(working)
                .accessibilityIdentifier("reminder.set")
            }
            .padding(24)
        }
    }

    private func choiceRow(_ value: Choice, title: String, detail: String?) -> some View {
        let selected = choice == value
        return Button { choice = value } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    if let detail {
                        Text(detail).font(.subheadline).foregroundStyle(Theme.secondaryText)
                    }
                }
                Spacer()
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(selected ? Theme.quietSurface : .clear, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(selected ? Theme.ink : Theme.separator, lineWidth: selected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var explainer: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                CandidateCharacterView(assetName: "Doddy_waving", size: 140)
                    .frame(maxWidth: .infinity)
                Text("Doddy needs permission to remind you")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("To bring this note back on \(ReminderFormat.dateTime(resolvedDate, timeZoneID: zoneID)), iOS needs to let Doddy send notifications.")
                VStack(alignment: .leading, spacing: 10) {
                    Label("Only reminders you set yourself.", systemImage: "checkmark")
                    Label("No tips, streaks or marketing. No badge on the app icon.", systemImage: "checkmark")
                    Label("The note text stays hidden on your Lock Screen unless you turn it on.", systemImage: "checkmark")
                }
                .font(.subheadline)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 16))

                Button {
                    explainerSeen = true
                    Task {
                        working = true
                        await reminders.requestAuthorization()
                        await commit()
                    }
                } label: { HStack { Text("Continue"); Spacer() } }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(working)
                .accessibilityIdentifier("reminder.permission.continue")

                Button("Not now, keep it inside Doddy") {
                    explainerSeen = true
                    Task { await commit() }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .disabled(working)
            }
            .padding(24)
        }
    }

    private func prepare() {
        options = ReminderQuickPick.options(now: .now, calendar: .autoupdatingCurrent)
        if let existing = reminders.reminder(forMemory: memoryID), !existing.isDue(at: .now) {
            customDate = existing.fireAt
            choice = .custom
        } else if let first = options.first(where: { $0.pick == .tomorrowMorning }) ?? options.first {
            choice = .quick(first.pick)
            customDate = first.date
        }
    }

    private func confirm() {
        if reminders.authorization == .notDetermined && !explainerSeen {
            showExplainer = true
        } else {
            Task { await commit() }
        }
    }

    private func commit() async {
        working = true
        await reminders.set(memoryID: memoryID, at: resolvedDate)
        working = false
        dismiss()
    }
}

extension ReminderQuickPick {
    var title: String {
        switch self {
        case .thisEvening: "This evening"
        case .tomorrowMorning: "Tomorrow morning"
        case .mondayMorning: "Monday morning"
        }
    }
}
