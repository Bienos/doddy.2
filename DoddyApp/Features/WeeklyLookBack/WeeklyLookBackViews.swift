import DoddyCore
import SwiftUI
import UserNotifications

/// Puts the weekly look-back's notification in iOS and reads it back (ADR-306). The notification
/// says only "Your week with Doddy · A short look back, when you like.".
enum WeeklyLookBackScheduler {
    enum Outcome: Equatable { case scheduled, off, needsPermission, failed }

    static func apply(_ settings: WeeklyLookBackSettings) async -> Outcome {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [WeeklyLookBack.notificationID])
        guard settings.isOn else { return .off }
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            status = await center.notificationSettings().authorizationStatus
        }
        guard status == .authorized || status == .provisional || status == .ephemeral else { return .needsPermission }
        let language = NotificationLanguage.current
        let content = UNMutableNotificationContent()
        content.title = WeeklyLookBack.title(language)
        content.body = WeeklyLookBack.body(language)
        var when = DateComponents()
        when.weekday = settings.weekday
        when.hour = settings.hour
        when.minute = settings.minute
        let request = UNNotificationRequest(
            identifier: WeeklyLookBack.notificationID, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: true))
        do { try await center.add(request) } catch { return .failed }
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        return pending.contains(WeeklyLookBack.notificationID) ? .scheduled : .failed
    }
}

/// The look-back screen: counts and the user's own words from this iPhone, nothing more.
struct WeeklyLookBackView: View {
    @Environment(MemoryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var week: WeeklyLookBack?
    private let devices = DeviceConnections()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    JourneyHeading(eyebrow: "Weekly look-back", title: "Your week\nwith Doddy")
                    if let week {
                        content(week)
                    } else {
                        ProgressView()
                    }
                    Text("Made on this iPhone from your notes, lists and What Doddy did. Nothing is sent anywhere.")
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
    private func content(_ week: WeeklyLookBack) -> some View {
        if week.isQuiet {
            Text("A quiet week: nothing saved, ticked or changed, and nothing coming up that Doddy can see.")
        }
        if week.noteCount > 0 {
            VStack(alignment: .leading, spacing: 8) {
                Text(String(format: NSLocalizedString("Notes saved: %lld", comment: ""), week.noteCount))
                    .font(.headline)
                ForEach(Array(week.notes.enumerated()), id: \.offset) { _, text in
                    Text("“\(text)”").lineLimit(2)
                }
            }
        }
        if week.ticked > 0 {
            Text(String(format: NSLocalizedString("List items ticked off: %lld", comment: ""), week.ticked))
                .font(.headline)
        }
        if !week.doneByApp.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Done with Doddy, and checked")
                    .font(.headline)
                ForEach(week.doneByApp.indices, id: \.self) { index in
                    let row = week.doneByApp[index]
                    Text("\(row.app.title(.current)): \(row.count)")
                }
            }
        }
        if let events = week.upcomingEvents, !events.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Coming up this week")
                    .font(.headline)
                ForEach(events, id: \.start) { event in
                    Text("\(event.title) · \(event.start.formatted(date: .abbreviated, time: event.allDay ? .omitted : .shortened))")
                }
            }
        }
        if let due = week.remindersDue, due > 0 {
            Text(String(format: NSLocalizedString("Reminders due by the end of next week, overdue included: %lld", comment: ""), due))
        }
    }

    private func load() async {
        await store.reload()
        let now = Date()
        let paused = UserDefaults.standard.bool(forKey: ConnectionPause.preferenceKey)
        let calendarOn = !paused && UserDefaults.standard.bool(forKey: VoiceConnection.calendar.preferenceKey)
            && devices.access(for: .calendar) == .granted
        let remindersOn = !paused && UserDefaults.standard.bool(forKey: VoiceConnection.reminders.preferenceKey)
            && devices.access(for: .reminders) == .granted
        let end = now.addingTimeInterval(Double(WeeklyLookBack.days) * 86_400)
        let events = calendarOn ? devices.events(in: VoiceTimeRange(start: now, end: end)) : nil
        let due = remindersOn ? await devices.remindersDue(by: end, calendar: .current).count : nil
        week = WeeklyLookBack.make(
            notes: store.memories, lists: store.lists, activity: ActivityLogStore.shared.entries,
            events: events, remindersDue: due, now: now)
    }
}

/// Settings › Weekly look-back: off by default; the day and time; read back from iOS.
struct WeeklyLookBackSettingsSection: View {
    @State private var settings = WeeklyLookBackSettings.stored()
    @State private var outcome: WeeklyLookBackScheduler.Outcome?

    private var time: Binding<Date> {
        Binding(
            get: { Calendar.current.date(from: DateComponents(hour: settings.hour, minute: settings.minute)) ?? .now },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                settings.hour = parts.hour ?? 19
                settings.minute = parts.minute ?? 0
            })
    }

    var body: some View {
        Section("Weekly look-back") {
            Toggle("Weekly look-back", isOn: $settings.isOn).accessibilityIdentifier("settings.lookBackOn")
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
            Text("Once a week a notification says only \"Your week with Doddy\". Its screen shows what you saved, ticked off and asked Doddy to do, and what's coming up. No streaks or scores.")
                .font(.footnote).foregroundStyle(Theme.secondaryText)
            Button("Open the look-back now") { ShortcutRouter.shared.weeklyLookBackOpened() }
                .accessibilityIdentifier("settings.lookBackOpen")
        }
        .onChange(of: settings) {
            settings.store()
            let wanted = settings
            Task {
                let result = await WeeklyLookBackScheduler.apply(wanted)
                if wanted == settings { outcome = result }
            }
        }
    }

    private func message(_ outcome: WeeklyLookBackScheduler.Outcome) -> String {
        switch outcome {
        case .scheduled: return NSLocalizedString("Set. The look-back comes once a week.", comment: "")
        case .off: return NSLocalizedString("Off. Nothing is scheduled.", comment: "")
        case .needsPermission: return NSLocalizedString("Notifications are off for Doddy, so the look-back can't arrive. Turn them on in iOS Settings.", comment: "")
        case .failed: return NSLocalizedString("The look-back couldn't be set. Try again.", comment: "")
        }
    }
}
