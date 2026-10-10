import DoddyCore
import SwiftUI

/// Home → the morning brief (ADR-212): from its time for a few hours, until closed for the day.
/// Built on this iPhone from Today's Calendar and Reminders (same switches) and Doddy's own note
/// reminders, plus, only if chosen in Settings, today's news, Todoist and unread Gmail fetched
/// through Doddy's server (ADR-213). Read aloud uses the iPhone's speech voice.
struct MorningBriefCard: View {
    @Environment(MemoryStore.self) private var store
    @Environment(NoteReminderStore.self) private var noteReminders
    @Environment(ProfileStore.self) private var profiles
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(PreferenceKey.morningBriefOn) private var isOn = false
    @AppStorage(PreferenceKey.morningBriefClosedDay) private var closedDay = ""
    @State private var brief: MorningBrief?
    @State private var isFetchingOnline = false
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
                        if let url = line.url.flatMap(URL.init(string:)), url.scheme == "https" {
                            // A news story: opens in the browser only when tapped.
                            Link(destination: url) {
                                Label(line.text, systemImage: "arrow.up.right.square")
                                    .multilineTextAlignment(.leading)
                            }
                            .font(.subheadline)
                        } else {
                            Text(line.text)
                                .font(line.kind == .greeting ? .body.weight(.semibold) : .body)
                                .foregroundStyle(line.kind == .notice ? Theme.secondaryText : Theme.ink)
                        }
                    }
                    if isFetchingOnline {
                        ProgressView("Checking your chosen accounts and news")
                            .font(.footnote)
                    }
                    HStack {
                        Button(speaker.isSpeaking ? "Stop" : "Read aloud") {
                            if speaker.isSpeaking { speaker.stop() } else { speaker.speak(brief.spokenText) }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("brief.readAloud")
                        if MorningBriefSections.stored().readsServer {
                            Button("Refresh") { Task { await load(refreshOnline: true) } }
                                .buttonStyle(SecondaryButtonStyle())
                                .disabled(isFetchingOnline)
                                .accessibilityIdentifier("brief.refresh")
                        }
                        Button("Close for today") {
                            speaker.stop()
                            MorningBriefOnlineCache.shared.clear()
                            closedDay = MorningBriefSchedule.dayKey(.now, calendar: .current)
                            self.brief = nil
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("brief.close")
                    }
                    Text(MorningBriefSections.stored().readsServer
                         ? "Put together on this iPhone; news, Todoist and Gmail come through Doddy's server. Read aloud uses the iPhone's voice."
                         : "Put together on this iPhone. Read aloud uses the iPhone's voice.")
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
        // Back from Settings with other choices: rebuild (the cache key includes the choices).
        .onAppear { Task { await load() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await load() } } else { speaker.stop() }
        }
    }

    private func load(now: Date = .now, calendar: Calendar = .current, refreshOnline: Bool = false) async {
        var schedule = MorningBriefNotifications.current()
        schedule.isOn = isOn
        guard schedule.isShowing(now: now, dismissedDay: closedDay.isEmpty ? nil : closedDay, calendar: calendar) else {
            brief = nil
            return
        }
        let sections = MorningBriefSections.stored()
        // Calendar and Reminders are read only when one of them is in the brief.
        let source = sections.readsDevice
            ? await TodayReading.read(devices, now: now, calendar: calendar)
            : .notConnected
        let notes = noteReminders.reminders.compactMap { reminder -> BriefNoteReminder? in
            guard let fireAt = reminder.fireAt, let record = store.record(id: reminder.memoryID) else { return nil }
            return BriefNoteReminder(fireAt: fireAt, noteText: record.currentText)
        }
        let compose = { (online: BriefOnline) in
            MorningBrief.compose(
                source: source, noteReminders: notes,
                name: Nickname.stored() ?? profiles.profile.value(.name),
                now: now, calendar: calendar,
                timeText: { $0.formatted(date: .omitted, time: .shortened) },
                sections: sections, online: online)
        }
        guard sections.readsServer else {
            brief = compose(.none)
            return
        }
        // At most one fetch per day and choice of sections, unless the user taps Refresh.
        let key = "\(MorningBriefSchedule.dayKey(now, calendar: calendar))|\(sections)"
        if !refreshOnline, let cached = MorningBriefOnlineCache.shared.value(for: key) {
            brief = compose(cached)
            return
        }
        // One fetch at a time; the one already running fills the card in.
        guard !isFetchingOnline else { return }
        brief = compose(.none)
        isFetchingOnline = true
        let online = await MorningBriefOnlineCache.fetch(sections, now: now, calendar: calendar)
        isFetchingOnline = false
        MorningBriefOnlineCache.shared.store(online, for: key)
        brief = compose(online)
    }
}
