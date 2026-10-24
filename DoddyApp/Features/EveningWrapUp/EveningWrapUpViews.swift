import DoddyCore
import SwiftUI
import UserNotifications

/// Puts the evening wrap-up's daily notification in iOS and reads it back (ADR-261). The
/// notification says only "Good evening · Anything to move to tomorrow?".
@MainActor
enum EveningWrapUpScheduler {
    enum Outcome: Equatable { case scheduled, off, needsPermission, failed }

    /// The apply still running, if any. Each apply waits for the one before it, so quick changes
    /// can't interleave their remove and add steps and leave a stale notification.
    private static var running: Task<Outcome, Never>?

    static func apply(_ settings: EveningWrapUpSettings) async -> Outcome {
        let previous = running
        let task = Task {
            _ = await previous?.value
            return await replace(with: settings)
        }
        running = task
        return await task.value
    }

    private static func replace(with settings: EveningWrapUpSettings) async -> Outcome {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [EveningWrapUp.notificationID])
        guard settings.isOn else { return .off }
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            status = await center.notificationSettings().authorizationStatus
        }
        guard status == .authorized || status == .provisional || status == .ephemeral else { return .needsPermission }
        let language = NotificationLanguage.current
        let content = UNMutableNotificationContent()
        content.title = EveningWrapUp.title(language)
        content.body = EveningWrapUp.body(language)
        // Doddy sitting cross-legged, winding down (ADR-323); the words are unchanged.
        if let art = NotificationArt.attachment(.crosslegged) { content.attachments = [art] }
        // A routine: no sound, never through a Focus (ADR-611).
        content.interruptionLevel = DoddyNotificationKind.eveningWrapUp.interruptionLevel
        var when = DateComponents()
        // Never in quiet hours (ADR-612).
        let time = QuietHours.adjusted(hour: settings.hour, minute: settings.minute)
        when.hour = time.hour
        when.minute = time.minute
        let request = UNNotificationRequest(
            identifier: EveningWrapUp.notificationID, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: true))
        do { try await center.add(request) } catch { return .failed }
        // Read back from iOS: the notification is there, at the wanted time.
        let isThere = await center.pendingNotificationRequests().contains { pendingRequest in
            guard pendingRequest.identifier == EveningWrapUp.notificationID,
                  let fires = (pendingRequest.trigger as? UNCalendarNotificationTrigger)?.dateComponents else { return false }
            return fires.hour == time.hour && fires.minute == time.minute
        }
        return isThere ? .scheduled : .failed
    }
}

/// The wrap-up screen: open reminders due today or earlier, none ticked to start with. Move
/// changes only the ticked ones, each checked and read back like a change by voice (ADR-229).
struct EveningWrapUpView: View {
    @Environment(\.dismiss) private var dismiss
    let openSettings: () -> Void

    private enum Content: Equatable {
        case loading
        case notConnected
        case paused
        case failed(String)
        case reminders([ReminderSnapshot])
    }

    @State private var content: Content = .loading
    @State private var selected: Set<String> = []
    @State private var isMoving = false
    @State private var receipt: String?
    private let devices = DeviceConnections()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    JourneyHeading(eyebrow: "Evening wrap-up", title: "Anything for\ntomorrow?")
                    if let receipt {
                        Label(receipt, systemImage: "checkmark.circle")
                            .font(.subheadline)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityIdentifier("wrapup.receipt")
                    }
                    switch content {
                    case .loading:
                        ProgressView()
                    case .notConnected:
                        Text("The wrap-up shows your open reminders from the Reminders app. Turn on Reminders in Settings, Connections; they're read on this iPhone only.")
                            .foregroundStyle(Theme.secondaryText)
                        Button("Open Settings") { dismiss(); openSettings() }
                            .buttonStyle(SecondaryButtonStyle())
                    case .paused:
                        Text("Connections are paused, so Doddy isn't reading your reminders. Turn them back on in Settings, Connections.")
                            .foregroundStyle(Theme.secondaryText)
                    case .failed(let message):
                        Text(message).foregroundStyle(Theme.error)
                    case .reminders(let reminders):
                        remindersSection(reminders)
                    }
                    Button("Not now") { dismiss() }.frame(minHeight: 44)
                }
                .padding(24)
            }
            .background(Theme.canvas).foregroundStyle(Theme.ink)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .principal) { DoddyWordmark() } }
        }
        .task { await load() }
    }

    @ViewBuilder
    private func remindersSection(_ reminders: [ReminderSnapshot]) -> some View {
        if reminders.isEmpty {
            Text("Nothing left from today. Good night.")
                .foregroundStyle(Theme.secondaryText)
                .accessibilityIdentifier("wrapup.empty")
        } else {
            Text("Still open from today or earlier. Tick the ones to move; each keeps its time.")
                .font(.subheadline).foregroundStyle(Theme.secondaryText)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(reminders, id: \.id) { reminder in
                    Button { toggle(reminder.id) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Image(systemName: selected.contains(reminder.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected.contains(reminder.id) ? Theme.accentText : Theme.secondaryText)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(reminder.title)
                                Text("\(reminder.listTitle) · \(ReminderText.due(reminder.due))")
                                    .font(.caption).foregroundStyle(Theme.secondaryText)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected.contains(reminder.id) ? .isSelected : [])
                }
            }
            Button {
                Task { await move(reminders.filter { selected.contains($0.id) }) }
            } label: {
                HStack {
                    Text(String(format: NSLocalizedString("Move %lld to tomorrow", comment: ""), selected.count))
                    Spacer()
                    Image(systemName: "arrow.right")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(selected.isEmpty || isMoving)
            .accessibilityIdentifier("wrapup.move")
        }
    }

    private func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func load() async {
        if UserDefaults.standard.bool(forKey: ConnectionPause.preferenceKey) {
            content = .paused
            return
        }
        guard UserDefaults.standard.bool(forKey: VoiceConnection.reminders.preferenceKey),
              devices.access(for: .reminders) == .granted else {
            content = .notConnected
            return
        }
        do {
            let open = try await devices.incompleteReminders()
            let shown = EveningWrapUp.movable(open, now: .now, local: .current)
            selected = selected.intersection(shown.map(\.id))
            content = .reminders(shown)
        } catch {
            content = .failed(UserFacingError.message(for: error))
        }
    }

    /// Each ticked reminder moves only if it still looks as shown; then it's read back.
    private func move(_ reminders: [ReminderSnapshot]) async {
        isMoving = true
        defer { isMoving = false }
        // Saved but not read back (`.unconfirmed`) may well have moved, so it is counted on its
        // own, never as "couldn't be moved" (DOD-08).
        var moved = 0, notMoved = 0, unconfirmed = 0
        for reminder in reminders {
            guard let due = reminder.due, let tomorrow = EveningWrapUp.tomorrow(due, now: .now, local: .current) else {
                notMoved += 1
                continue
            }
            switch try? devices.changeReminder(reminder, .due(tomorrow)) {
            case .verified: moved += 1
            case .unconfirmed: unconfirmed += 1
            case .changedElsewhere, nil: notMoved += 1
            }
        }
        selected = []
        var parts: [String] = []
        if notMoved > 0 {
            parts.append(String(format: NSLocalizedString("Moved %lld to tomorrow. %lld couldn't be moved (changed in Reminders, or the time doesn't exist tomorrow); check them there.", comment: ""), moved, notMoved))
        } else if moved > 0 || unconfirmed == 0 {
            parts.append(String(format: NSLocalizedString("Moved %lld to tomorrow. Checked in Reminders.", comment: ""), moved))
        }
        if unconfirmed > 0 {
            parts.append(String(format: NSLocalizedString("%lld were changed but couldn't be checked afterwards; look at them in Reminders.", comment: ""), unconfirmed))
        }
        receipt = parts.joined(separator: " ")
        await load()
    }
}

/// Settings › Evening wrap-up: off by default; the time; read back from iOS.
struct EveningWrapUpSettingsSection: View {
    @State private var settings = EveningWrapUpSettings.stored()
    @State private var outcome: EveningWrapUpScheduler.Outcome?

    private var time: Binding<Date> {
        Binding(
            get: { Calendar.current.date(from: DateComponents(hour: settings.hour, minute: settings.minute)) ?? .now },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                // Quiet hours (ADR-612): the picker shows where the time really goes.
                let time = QuietHours.adjusted(hour: parts.hour ?? 21, minute: parts.minute ?? 0)
                settings.hour = time.hour
                settings.minute = time.minute
            })
    }

    var body: some View {
        Section("Evening wrap-up") {
            Toggle("Evening wrap-up", isOn: $settings.isOn).accessibilityIdentifier("settings.wrapUpOn")
            if settings.isOn {
                DatePicker("Time", selection: time, displayedComponents: .hourAndMinute)
            }
            if let outcome {
                Text(message(outcome)).font(.footnote)
                    .foregroundStyle(outcome == .failed || outcome == .needsPermission ? Theme.error : Theme.secondaryText)
            }
            Text("A notification at this time says only \"Anything to move to tomorrow?\". Tap it to see open reminders from today and move the ones you pick. Needs Reminders on in Connections.")
                .font(.footnote).foregroundStyle(Theme.secondaryText)
            Button("Open the wrap-up now") { ShortcutRouter.shared.eveningWrapUpOpened() }
                .accessibilityIdentifier("settings.wrapUpOpen")
        }
        .onChange(of: settings) {
            settings.store()
            let wanted = settings
            Task {
                let result = await EveningWrapUpScheduler.apply(wanted)
                if wanted == settings { outcome = result }
            }
        }
    }

    private func message(_ outcome: EveningWrapUpScheduler.Outcome) -> String {
        switch outcome {
        case .scheduled: return NSLocalizedString("Set. The wrap-up notification comes every evening.", comment: "")
        case .off: return NSLocalizedString("Off. Nothing is scheduled.", comment: "")
        case .needsPermission: return NSLocalizedString("Notifications are off for Doddy, so the wrap-up can't ring. Turn them on in iOS Settings.", comment: "")
        case .failed: return NSLocalizedString("The wrap-up couldn't be set. Try again.", comment: "")
        }
    }
}
