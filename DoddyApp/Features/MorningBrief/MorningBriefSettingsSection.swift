import DoddyCore
import SwiftUI

/// Settings → Morning brief (ADR-212). Off unless turned on. Turning it on asks iOS for
/// notifications if it hasn't yet; the brief still shows on Home if notifications are refused.
struct MorningBriefSettingsSection: View {
    @AppStorage(PreferenceKey.morningBriefOn) private var isOn = false
    @AppStorage(PreferenceKey.morningBriefHour) private var hour = MorningBriefSchedule.defaultHour
    @AppStorage(PreferenceKey.morningBriefMinute) private var minute = MorningBriefSchedule.defaultMinute
    // In your brief (ADR-213): what's on the iPhone is in by default; server sections are chosen.
    @AppStorage(PreferenceKey.morningBriefEvents) private var events = MorningBriefSections.standard.events
    @AppStorage(PreferenceKey.morningBriefReminders) private var reminders = MorningBriefSections.standard.reminders
    @AppStorage(PreferenceKey.morningBriefNoteReminders) private var noteReminders = MorningBriefSections.standard.noteReminders
    @AppStorage(PreferenceKey.morningBriefNews) private var news = MorningBriefSections.standard.news
    @AppStorage(PreferenceKey.morningBriefTodoist) private var todoist = MorningBriefSections.standard.todoist
    @AppStorage(PreferenceKey.morningBriefGmail) private var gmail = MorningBriefSections.standard.gmail
    @AppStorage(PreferenceKey.morningBriefGmailImportant) private var gmailImportant = MorningBriefSections.standard.gmailImportantOnly
    @State private var status: String?
    @State private var isWorking = false

    private var schedule: MorningBriefSchedule { MorningBriefSchedule(isOn: isOn, hour: hour, minute: minute) }

    private var timeBinding: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: schedule.hour, minute: schedule.minute, second: 0, of: .now) ?? .now },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                hour = parts.hour ?? MorningBriefSchedule.defaultHour
                minute = parts.minute ?? MorningBriefSchedule.defaultMinute
            })
    }

    private var timeText: String {
        timeBinding.wrappedValue.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        mainSection
        if isOn { contentsSection }
    }

    private var contentsSection: some View {
        Section {
            Toggle("Events left today", isOn: $events)
                .accessibilityIdentifier("settings.brief.events")
            Toggle("Reminders due", isOn: $reminders)
                .accessibilityIdentifier("settings.brief.reminders")
            Toggle("Doddy's note reminders", isOn: $noteReminders)
                .accessibilityIdentifier("settings.brief.noteReminders")
            Toggle("Today's daily news", isOn: $news)
                .accessibilityIdentifier("settings.brief.news")
            Toggle("Todoist tasks for today", isOn: $todoist)
                .accessibilityIdentifier("settings.brief.todoist")
            Toggle("Unread Gmail from the last day", isOn: $gmail)
                .accessibilityIdentifier("settings.brief.gmail")
            if gmail {
                Toggle("Only mail Gmail marks important", isOn: $gmailImportant)
                    .accessibilityIdentifier("settings.brief.gmailImportant")
            }
        } header: {
            Text("In your morning brief")
        } footer: {
            Text("Events and reminders are read on this iPhone and need Calendar and Reminders on in Connections. News, Todoist and Gmail are fetched through Doddy's server when the brief is on Home, at most once a morning unless you tap Refresh, and kept only until the app closes: up to 3 stories from your daily news digest (set up in Daily news), Todoist tasks due today or earlier, and for Gmail only the sender and subject of up to 5 unread emails, never the message. Todoist and Gmail need the account connected and \"List my tasks\" or \"Check my email\" switched on in Online accounts; each check shows there like any other.")
        }
    }

    private var mainSection: some View {
        Section {
            Toggle("Morning brief", isOn: $isOn)
                .accessibilityIdentifier("settings.morningBrief")
            if isOn {
                DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
                    .accessibilityIdentifier("settings.morningBriefTime")
            }
            if isWorking {
                ProgressView()
            } else if let status {
                Text(status)
                    .font(.footnote)
                    .accessibilityIdentifier("settings.morningBriefStatus")
            }
        } header: {
            Text("Morning brief")
        } footer: {
            Text("Your day at a glance at the top of Home: events left today and reminders due (if Calendar and Reminders are on in Connections) and Doddy's note reminders. Put together on this iPhone; nothing is sent anywhere. The daily notification only says the brief is ready, so nothing personal shows on the Lock Screen. Read aloud uses the iPhone's voice.")
        }
        .onChange(of: isOn) { _, _ in Task { await apply(mayAsk: true) } }
        .onChange(of: hour) { _, _ in Task { await apply(mayAsk: false) } }
        .onChange(of: minute) { _, _ in Task { await apply(mayAsk: false) } }
    }

    private func apply(mayAsk: Bool) async {
        isWorking = true
        defer { isWorking = false }
        guard isOn else {
            status = await MorningBriefNotifications.cancel()
                ? "Off. No morning notification."
                : "Off, but iOS still lists the morning notification. Turn it on and off again."
            return
        }
        switch await MorningBriefNotifications.schedule(schedule, mayAsk: mayAsk) {
        case .set:
            status = "On. A notification every day at \(timeText); the brief is on Home from then until a few hours later."
        case .unconfirmed:
            status = "iOS took the notification but didn't confirm it for \(timeText). The brief still shows on Home; check again later."
        case .notificationsOff:
            status = "Notifications are off for Doddy, so there's no morning notification. The brief still shows on Home from \(timeText). Turn notifications on in iPhone Settings, Notifications, Doddy."
        case .failed(let reason):
            status = "The morning notification wasn't set (\(reason)). The brief still shows on Home from \(timeText)."
        }
    }
}
