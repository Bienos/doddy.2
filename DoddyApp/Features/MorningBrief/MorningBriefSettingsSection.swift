import DoddyCore
import SwiftUI

/// Settings → Morning brief (ADR-212). Off unless turned on. Turning it on asks iOS for
/// notifications if it hasn't yet; the brief still shows on Home if notifications are refused.
struct MorningBriefSettingsSection: View {
    @AppStorage(PreferenceKey.morningBriefOn) private var isOn = false
    @AppStorage(PreferenceKey.morningBriefHour) private var hour = MorningBriefSchedule.defaultHour
    @AppStorage(PreferenceKey.morningBriefMinute) private var minute = MorningBriefSchedule.defaultMinute
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
