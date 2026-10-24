import DoddyCore
import SwiftUI
import UserNotifications

/// Puts the weekly plan's notification in iOS and reads it back (ADR-608). The notification says
/// only "New week · Take a look at what's coming?": no names and no counts, so nothing private is
/// on the Lock Screen and nothing can be out of date when it arrives. It is a routine: no sound,
/// never through a Focus, never in quiet hours.
enum WeeklyPlanScheduler {
    enum Outcome: Equatable { case scheduled, off, needsPermission, failed }

    static func apply(_ settings: WeeklyPlanSettings) async -> Outcome {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [WeeklyPlan.notificationID])
        guard settings.isOn else { return .off }
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            status = await center.notificationSettings().authorizationStatus
        }
        guard status == .authorized || status == .provisional || status == .ephemeral else { return .needsPermission }
        let language = NotificationLanguage.current
        let content = UNMutableNotificationContent()
        content.title = WeeklyPlan.title(language)
        content.body = WeeklyPlan.body(language)
        content.interruptionLevel = DoddyNotificationKind.weeklyPlan.interruptionLevel
        // Doddy stretching awake, as on the morning check-in (ADR-323).
        if let art = NotificationArt.attachment(.yawnStretch) { content.attachments = [art] }
        let time = QuietHours.adjusted(hour: settings.hour, minute: settings.minute)
        var when = DateComponents()
        when.weekday = settings.weekday
        when.hour = time.hour
        when.minute = time.minute
        let request = UNNotificationRequest(
            identifier: WeeklyPlan.notificationID, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: true))
        do { try await center.add(request) } catch { return .failed }
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        return pending.contains(WeeklyPlan.notificationID) ? .scheduled : .failed
    }
}

/// "Your week ahead": the next seven days, built when it opens from what this iPhone has.
struct WeeklyPlanView: View {
    @Environment(MemoryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var plan: WeeklyPlan?
    private let devices = DeviceConnections()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    JourneyHeading(eyebrow: "Weekly plan", title: "Your week\nahead")
                    SceneryBackdrop(place: .coffee, height: 110, focus: 0.2, pose: .yawnStretch)
                        .padding(.horizontal, -24)
                    if let plan {
                        content(plan)
                    } else {
                        ProgressView()
                    }
                    Text("Made on this iPhone from your calendar, reminders, Doddy's reminders and the birthdays you picked. Nothing is sent anywhere.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(24)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private func content(_ plan: WeeklyPlan) -> some View {
        if plan.isEmpty {
            Text("Nothing on your calendar, no reminders and no birthdays in the next seven days that Doddy can see.")
        }
        ForEach(plan.days, id: \.date) { day in
            VStack(alignment: .leading, spacing: 8) {
                Text(dayTitle(day.date))
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                if day.items.isEmpty {
                    Text("Nothing planned")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                } else {
                    ForEach(Array(day.items.prefix(WeeklyPlan.maxPerDay).enumerated()), id: \.offset) { _, item in
                        row(item)
                    }
                    if day.items.count > WeeklyPlan.maxPerDay {
                        Text(String(format: NSLocalizedString("And %lld more", comment: ""), day.items.count - WeeklyPlan.maxPerDay))
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
        }
        if plan.calendarOff {
            Text("Calendar is off in Connections, so events aren't shown.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
        if plan.remindersOff {
            Text("Reminders is off in Connections, so Apple Reminders aren't shown.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private func row(_ item: WeeklyPlan.Item) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol(item.kind))
                .foregroundStyle(Theme.accentText)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .lineLimit(2)
                Text(detail(item))
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func symbol(_ kind: WeeklyPlan.Kind) -> String {
        switch kind {
        case .event: "calendar"
        case .reminder: "checklist"
        case .noteReminder: "bell"
        case .birthday: "gift"
        }
    }

    private func detail(_ item: WeeklyPlan.Item) -> String {
        let label = item.kind.label(.current)
        guard item.hasTime else { return label }
        return "\(label) · \(item.at.formatted(date: .omitted, time: .shortened))"
    }

    private func dayTitle(_ date: Date) -> String {
        let calendar = Calendar.current
        let name = date.formatted(.dateTime.weekday(.wide).day().month(.wide))
        if calendar.isDateInToday(date) { return NSLocalizedString("Today", comment: "") + " · " + name }
        if calendar.isDateInTomorrow(date) { return NSLocalizedString("Tomorrow", comment: "") + " · " + name }
        return name
    }

    private func load() async {
        await store.reload()
        let now = Date()
        let calendar = Calendar.current
        let paused = UserDefaults.standard.bool(forKey: ConnectionPause.preferenceKey)
        let calendarOn = !paused && UserDefaults.standard.bool(forKey: VoiceConnection.calendar.preferenceKey)
            && devices.access(for: .calendar) == .granted
        let remindersOn = !paused && UserDefaults.standard.bool(forKey: VoiceConnection.reminders.preferenceKey)
            && devices.access(for: .reminders) == .granted
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: WeeklyPlan.days, to: start) ?? now.addingTimeInterval(Double(WeeklyPlan.days) * 86_400)
        let events = calendarOn ? devices.events(in: VoiceTimeRange(start: start, end: end)) : nil
        let due = remindersOn ? await devices.remindersDue(by: end, calendar: calendar) : nil
        // Doddy's reminders: the note's first line, or "A private note" for a private one.
        let shareable = Set(PrivateNotesStore.current().shareable(store.memories).map(\.id))
        let texts = Dictionary(store.memories.map { ($0.id, $0.currentText) }, uniquingKeysWith: { first, _ in first })
        let noteReminders = (store.noteReminders?.reminders ?? []).map { reminder in
            let text = texts[reminder.memoryID].flatMap { $0.split(whereSeparator: \.isNewline).first.map(String.init) } ?? ""
            let title = shareable.contains(reminder.memoryID) && !text.isEmpty ? text : NSLocalizedString("A private note", comment: "")
            return (reminder: reminder, title: title)
        }
        // The people picked in Settings › Birthdays, only with Contacts allowed.
        let picked = Set(UserDefaults.standard.stringArray(forKey: Birthdays.pickedKey) ?? [])
        let contacts = (devices.birthdays() ?? []).filter { picked.contains($0.id) }
        let birthdays = UpcomingBirthdays.upcoming(
            contacts.map { ContactBirthday(name: $0.name, month: $0.month, day: $0.day) },
            now: now, days: WeeklyPlan.days, calendar: calendar)
        plan = WeeklyPlan.make(
            events: events, reminders: due, noteReminders: noteReminders, birthdays: birthdays, now: now, calendar: calendar)
    }
}

/// Settings › Weekly plan: off by default; Monday 08:00 to start; read back from iOS.
struct WeeklyPlanSettingsSection: View {
    @State private var settings = WeeklyPlanSettings.stored()
    @State private var outcome: WeeklyPlanScheduler.Outcome?

    private var time: Binding<Date> {
        Binding(
            get: { Calendar.current.date(from: DateComponents(hour: settings.hour, minute: settings.minute)) ?? .now },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                // Quiet hours (ADR-608): the picker shows where the time really goes.
                let moved = QuietHours.adjusted(hour: parts.hour ?? 8, minute: parts.minute ?? 0)
                settings.hour = moved.hour
                settings.minute = moved.minute
            })
    }

    var body: some View {
        Section("Weekly plan") {
            Toggle("Weekly plan", isOn: $settings.isOn).accessibilityIdentifier("settings.weeklyPlanOn")
            if settings.isOn {
                Picker("Day", selection: $settings.weekday) {
                    ForEach(1...7, id: \.self) { day in
                        Text(Calendar.current.weekdaySymbols[day - 1]).tag(day)
                    }
                }
                DatePicker("Time", selection: time, displayedComponents: .hourAndMinute)
            }
            if let outcome {
                Text(message(outcome)).font(.footnote)
                    .foregroundStyle(outcome == .failed || outcome == .needsPermission ? Theme.error : Theme.secondaryText)
            }
            Text("Once a week a notification says only \"New week\". Its screen shows the next seven days from your calendar, reminders, Doddy's reminders and the birthdays you picked. It comes quietly, never between 22:00 and 7:00.")
                .font(.footnote).foregroundStyle(Theme.secondaryText)
            Button("Open the plan now") { ShortcutRouter.shared.weeklyPlanOpened() }
                .accessibilityIdentifier("settings.weeklyPlanOpen")
        }
        .onChange(of: settings) {
            settings.store()
            let wanted = settings
            Task {
                let result = await WeeklyPlanScheduler.apply(wanted)
                if wanted == settings { outcome = result }
            }
        }
    }

    private func message(_ outcome: WeeklyPlanScheduler.Outcome) -> String {
        switch outcome {
        case .scheduled: return NSLocalizedString("Set. The plan comes once a week.", comment: "")
        case .off: return NSLocalizedString("Off. Nothing is scheduled.", comment: "")
        case .needsPermission: return NSLocalizedString("Notifications are off for Doddy, so the plan can't arrive. Turn them on in iOS Settings.", comment: "")
        case .failed: return NSLocalizedString("The plan couldn't be set. Try again.", comment: "")
        }
    }
}
