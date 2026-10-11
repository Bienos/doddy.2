import DoddyCore
import SwiftUI
import UserNotifications

/// Puts the evening wrap-up's daily notification in iOS and reads it back (ADR-256). The
/// notification says only "Good evening · Anything to move to tomorrow?".
enum EveningWrapUpScheduler {
    enum Outcome: Equatable { case scheduled, off, needsPermission, failed }

    static func apply(_ settings: EveningWrapUpSettings) async -> Outcome {
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
        var when = DateComponents()
        when.hour = settings.hour
        when.minute = settings.minute
        let request = UNNotificationRequest(
            identifier: EveningWrapUp.notificationID, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: true))
        do { try await center.add(request) } catch { return .failed }
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        return pending.contains(EveningWrapUp.notificationID) ? .scheduled : .failed
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
        var moved = 0, notMoved = 0
        for reminder in reminders {
            guard let due = reminder.due, let tomorrow = EveningWrapUp.tomorrow(due, now: .now, local: .current) else {
                notMoved += 1
                continue
            }
            let outcome = try? devices.changeReminder(reminder, .due(tomorrow))
            if outcome == .verified { moved += 1 } else { notMoved += 1 }
        }
        selected = []
        receipt = notMoved == 0
            ? String(format: NSLocalizedString("Moved %lld to tomorrow. Checked in Reminders.", comment: ""), moved)
            : String(format: NSLocalizedString("Moved %lld to tomorrow. %lld couldn't be moved (changed in Reminders, or the time doesn't exist tomorrow); check them there.", comment: ""), moved, notMoved)
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
                settings.hour = parts.hour ?? 21
                settings.minute = parts.minute ?? 0
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
