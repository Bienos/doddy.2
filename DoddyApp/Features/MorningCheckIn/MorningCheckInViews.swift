import DoddyCore
import SwiftUI

/// The morning check-in screen (ADR-220): built on this iPhone from Doddy's own reminders and
/// lists, plus the Today card (Calendar and Reminders, when connected). Nothing is sent anywhere
/// until "Talk it through", which starts a conversation with these facts.
struct MorningCheckInView: View {
    @Environment(MemoryStore.self) private var store
    @Environment(NoteReminderStore.self) private var noteReminders
    @Environment(\.dismiss) private var dismiss
    let openSettings: () -> Void

    private var briefing: MorningBriefing {
        MorningBriefing.make(now: .now, memories: store.memories, lists: store.lists, reminders: noteReminders.reminders)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    JourneyHeading(eyebrow: "Morning check-in", title: "Your day,\nat a glance.")
                    let briefing = briefing
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Doddy reminders today").font(.headline)
                        if briefing.reminders.isEmpty {
                            Text("None set for today.").foregroundStyle(Theme.secondaryText)
                        }
                        ForEach(briefing.reminders, id: \.memoryID) { line in
                            HStack(alignment: .firstTextBaseline) {
                                Text(line.time, format: .dateTime.hour().minute()).monospacedDigit()
                                Text(line.text)
                            }
                        }
                    }
                    .accessibilityIdentifier("checkin.reminders")
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Lists with things left").font(.headline)
                        if briefing.lists.isEmpty {
                            Text("Nothing left on your lists.").foregroundStyle(Theme.secondaryText)
                        }
                        ForEach(briefing.lists, id: \.listID) { list in
                            Text("\(list.name) · \(list.openCount) to go")
                        }
                    }
                    .accessibilityIdentifier("checkin.lists")
                    TodayCard(openSettings: { dismiss(); openSettings() })
                    Button {
                        ShortcutRouter.shared.openCheckInConversation(briefing)
                    } label: {
                        HStack { Text("Talk it through with Doddy"); Spacer(); Image(systemName: "waveform") }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("checkin.talk")
                    Text("Talking sends these reminders and list names to ElevenLabs to run the conversation, as any conversation does. Calendar events are read only if Calendar is on in Settings, Connections.")
                        .font(.footnote).foregroundStyle(Theme.secondaryText)
                    Button("Not now") { dismiss() }.frame(minHeight: 44)
                }
                .padding(24)
            }
            .background(Theme.canvas).foregroundStyle(Theme.ink)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .principal) { DoddyWordmark() } }
        }
        .task { await store.reload() }
    }
}

/// Settings › Morning check-in: off by default; time, weekdays only, and a receipt read back from iOS.
struct MorningCheckInSettingsSection: View {
    @State private var settings = MorningCheckInSettings.stored()
    @State private var outcome: MorningCheckInScheduler.Outcome?
    @State private var isApplying = false

    private var time: Binding<Date> {
        Binding(
            get: { Calendar.current.date(from: DateComponents(hour: settings.hour, minute: settings.minute)) ?? .now },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                settings.hour = parts.hour ?? 8
                settings.minute = parts.minute ?? 0
            })
    }

    var body: some View {
        Section("Morning check-in") {
            Toggle("Morning check-in", isOn: $settings.isOn).accessibilityIdentifier("settings.checkinOn")
            if settings.isOn {
                DatePicker("Time", selection: time, displayedComponents: .hourAndMinute)
                Toggle("Weekdays only", isOn: $settings.weekdaysOnly)
            }
            if let outcome { Text(message(outcome)).font(.footnote).foregroundStyle(outcome == .failed || outcome == .needsPermission ? Theme.error : Theme.secondaryText) }
            Text("A notification at this time says only \"A quick look at your day?\". Tap it to see today's Doddy reminders and lists on this iPhone, then talk it through if you like.")
                .font(.footnote).foregroundStyle(Theme.secondaryText)
            Button("Open the check-in now") { ShortcutRouter.shared.morningCheckInOpened() }
                .accessibilityIdentifier("settings.checkinOpen")
        }
        .onChange(of: settings) { apply() }
    }

    private func apply() {
        settings.store()
        isApplying = true
        let wanted = settings
        Task {
            let result = await MorningCheckInScheduler.apply(wanted)
            if wanted == settings { outcome = result }
            isApplying = false
        }
    }

    private func message(_ outcome: MorningCheckInScheduler.Outcome) -> String {
        let time = String(format: "%02d:%02d", settings.hour, settings.minute)
        switch outcome {
        case .scheduled: return "Set for \(time) \(settings.weekdaysOnly ? "on weekdays" : "every day")."
        case .off: return NSLocalizedString("Off. Nothing is scheduled.", comment: "")
        case .needsPermission: return NSLocalizedString("Notifications are off for Doddy, so the check-in can't ring. Turn them on in iOS Settings.", comment: "")
        case .failed: return NSLocalizedString("The check-in couldn't be set. Try again.", comment: "")
        }
    }
}
