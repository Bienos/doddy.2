import DoddyCore
import SwiftUI

/// "When should I bring this back?" At a time, or at a place (ADR-196). Nothing is stored until
/// Set reminder; the first time a permission is undecided, a short explainer comes before the iOS prompt.
struct NoteReminderSheet: View {
    let memoryID: UUID
    /// Open on "At a time" even if the note has a place reminder (e.g. location is off).
    var startAtTime = false

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
    @State private var atPlace = false
    @State private var working = false
    /// Never (nil), every day, weekdays, every week or every month (ADR-218).
    @State private var repeatRule: ReminderRepeat?

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
                Text(atPlace ? "Where should I bring this back?" : "When should I bring this back?")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)

                Picker("Remind me", selection: $atPlace) {
                    Text("At a time").tag(false)
                    Text("At a place").tag(true)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("reminder.mode")

                if atPlace {
                    NotePlacePicker(memoryID: memoryID) { dismiss() }
                } else {
                    timeChoices
                }
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private var timeChoices: some View {
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

                repeatChoices

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: repeatRule == nil ? "bell" : "repeat").accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        if let repeatRule {
                            Text(ReminderFormat.repeatPhrase(repeatRule, anchor: resolvedDate, timeZoneID: zoneID)).font(.headline)
                            Text(repeatDetail(repeatRule))
                                .font(.footnote)
                                .foregroundStyle(Theme.secondaryText)
                        } else {
                            Text(ReminderFormat.dateTime(resolvedDate, timeZoneID: zoneID)).font(.headline)
                            Text("\(ReminderFormat.zoneName(zoneID)) · fires at this moment even if you travel")
                                .font(.footnote)
                                .foregroundStyle(Theme.secondaryText)
                        }
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

    /// Repeat: Never, every day, weekdays, every week, every month (days 1–28 only).
    private var repeatChoices: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Repeat").font(.headline)
            Picker("Repeat", selection: $repeatRule) {
                Text("Never").tag(ReminderRepeat?.none)
                Text("Every day").tag(ReminderRepeat?.some(.daily))
                Text("Weekdays").tag(ReminderRepeat?.some(.weekdays))
                Text("Every week, on \(ReminderFormat.cadence(.weekly, anchor: resolvedDate, timeZoneID: zoneID).dropFirst(6))")
                    .tag(ReminderRepeat?.some(.weekly))
                if monthlyAllowed {
                    Text("Every month, on the \(ReminderFormat.ordinal(Calendar.autoupdatingCurrent.component(.day, from: resolvedDate)))")
                        .tag(ReminderRepeat?.some(.monthly))
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("reminder.repeat")
            if !monthlyAllowed {
                Text("Every month works for days 1 to 28, so every month has the day.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .onChange(of: resolvedDate) {
            if repeatRule == .monthly && !monthlyAllowed { repeatRule = nil }
        }
    }

    private var monthlyAllowed: Bool {
        ReminderSchedule.allows(.monthly, picked: resolvedDate, timeZoneID: zoneID)
    }

    /// "Warsaw time · first on Mon 12 Oct, 20:00 · uses 5 of your 50 reminders".
    private func repeatDetail(_ rule: ReminderRepeat) -> String {
        var parts = [ReminderFormat.zoneName(zoneID)]
        if let first = ReminderSchedule.firstOccurrence(
            rule, picked: resolvedDate, timeZoneID: zoneID, now: .now, lead: NoteReminderLimits.minimumLead) {
            parts.append("first on \(ReminderFormat.dateTime(first, timeZoneID: zoneID))")
        }
        if rule == .weekdays { parts.append("uses 5 of your \(NoteReminderLimits.maxActive) reminders") }
        parts.append("until you stop it")
        return parts.joined(separator: " · ")
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
        if !startAtTime, let existing = reminders.reminder(forMemory: memoryID), existing.place != nil {
            atPlace = true
        } else if let existing = reminders.reminder(forMemory: memoryID), existing.repeats != nil,
                  let next = existing.nextFire(after: .now) {
            repeatRule = existing.repeats
            customDate = next
            choice = .custom
        } else if let existing = reminders.reminder(forMemory: memoryID), let fireAt = existing.fireAt, !existing.isDue(at: .now) {
            customDate = fireAt
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
        await reminders.set(memoryID: memoryID, at: resolvedDate, repeats: repeatRule)
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
