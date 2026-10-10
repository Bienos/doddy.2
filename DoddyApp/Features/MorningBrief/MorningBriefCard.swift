import DoddyCore
import SwiftUI

/// Home → the morning brief (ADR-212): from its time for a few hours, until closed for the day.
/// Built on this iPhone from Today's Calendar and Reminders (same switches) and Doddy's own note
/// reminders. Read aloud uses the iPhone's speech voice; nothing is sent anywhere.
struct MorningBriefCard: View {
    @Environment(MemoryStore.self) private var store
    @Environment(NoteReminderStore.self) private var noteReminders
    @Environment(ProfileStore.self) private var profiles
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(PreferenceKey.morningBriefOn) private var isOn = false
    @AppStorage(PreferenceKey.morningBriefClosedDay) private var closedDay = ""
    @State private var brief: MorningBrief?
    @State private var speaker = BriefSpeaker()
    @State private var devices = DeviceConnections()

    var body: some View {
        Group {
            if let brief {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Morning brief")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(Array(brief.lines.enumerated()), id: \.offset) { _, line in
                        Text(line.text)
                            .font(line.kind == .greeting ? .body.weight(.semibold) : .body)
                            .foregroundStyle(line.kind == .notice ? Theme.secondaryText : Theme.ink)
                    }
                    HStack {
                        Button(speaker.isSpeaking ? "Stop" : "Read aloud") {
                            if speaker.isSpeaking { speaker.stop() } else { speaker.speak(brief.spokenText) }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("brief.readAloud")
                        Button("Close for today") {
                            speaker.stop()
                            closedDay = MorningBriefSchedule.dayKey(.now, calendar: .current)
                            self.brief = nil
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("brief.close")
                    }
                    Text("Put together on this iPhone. Read aloud uses the iPhone's voice.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 18))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("home.morningBrief")
            }
        }
        .task(id: "\(isOn)|\(closedDay)|\(noteReminders.reminders.count)|\(store.revision)") { await load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await load() } } else { speaker.stop() }
        }
    }

    private func load(now: Date = .now, calendar: Calendar = .current) async {
        var schedule = MorningBriefNotifications.current()
        schedule.isOn = isOn
        guard schedule.isShowing(now: now, dismissedDay: closedDay.isEmpty ? nil : closedDay, calendar: calendar) else {
            brief = nil
            return
        }
        let source = await TodayReading.read(devices, now: now, calendar: calendar)
        let notes = noteReminders.reminders.compactMap { reminder -> BriefNoteReminder? in
            guard let fireAt = reminder.fireAt, let record = store.record(id: reminder.memoryID) else { return nil }
            return BriefNoteReminder(fireAt: fireAt, noteText: record.currentText)
        }
        brief = MorningBrief.compose(
            source: source, noteReminders: notes,
            name: Nickname.stored() ?? profiles.profile.value(.name),
            now: now, calendar: calendar,
            timeText: { $0.formatted(date: .omitted, time: .shortened) })
    }
}
