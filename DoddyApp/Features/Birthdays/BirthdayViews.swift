import DoddyCore
import SwiftUI
import UserNotifications

/// Puts the picked birthdays in iOS as Doddy's own yearly notifications (ADR-288) and reads them
/// back. Replaces whatever birthday notifications Doddy had pending.
enum BirthdayScheduler {
    enum Outcome: Equatable { case scheduled(Int), off, needsPermission, failed }

    static var picked: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Birthdays.pickedKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue).sorted(), forKey: Birthdays.pickedKey) }
    }

    static func apply(_ contacts: [BirthdayContact], picked: Set<String>) async -> Outcome {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: pending.filter(Birthdays.isBirthday(notificationID:)))
        let chosen = Birthdays.toSchedule(contacts, picked: picked, now: .now, calendar: .current)
        guard !chosen.isEmpty else { return .off }
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            status = await center.notificationSettings().authorizationStatus
        }
        guard status == .authorized || status == .provisional || status == .ephemeral else { return .needsPermission }
        let language = NotificationLanguage.current
        let showNames = UserDefaults.standard.bool(forKey: PreferenceKey.showNoteTextInNotifications)
        for contact in chosen {
            let content = UNMutableNotificationContent()
            content.title = Birthdays.title(showNames ? contact.name : nil, language)
            content.body = Birthdays.body(language)
            // Doddy waving: "maybe say hello" (ADR-323). Each notification gets its own copy.
            if let art = NotificationArt.attachment(.wave) { content.attachments = [art] }
            content.sound = .default
            let day = Birthdays.scheduledDay(contact)
            let when = DateComponents(month: day.month, day: day.day, hour: Birthdays.hour)
            let request = UNNotificationRequest(
                identifier: Birthdays.notificationID(for: contact.id), content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: true))
            do { try await center.add(request) } catch { return .failed }
        }
        let wanted = Set(chosen.map { Birthdays.notificationID(for: $0.id) })
        let now = Set(await center.pendingNotificationRequests().map(\.identifier))
        return wanted.isSubset(of: now) ? .scheduled(wanted.count) : .failed
    }

    /// At launch, so names and dates follow Contacts and the words follow the iPhone's language.
    @MainActor
    static func refresh() async {
        guard !picked.isEmpty, let contacts = DeviceConnections().birthdays() else { return }
        _ = await apply(contacts, picked: picked)
    }
}

/// Settings › Birthdays: contacts with a birthday, each with its own switch, all off to start.
struct BirthdaysView: View {
    @State private var contacts: [BirthdayContact]?
    @State private var picked = BirthdayScheduler.picked
    @State private var outcome: BirthdayScheduler.Outcome?
    private let devices = DeviceConnections()

    var body: some View {
        List {
            Section {
                Text("Pick the people whose birthday Doddy should remind you of, at 9:00 on the day. Read from Contacts on this iPhone; nothing is sent anywhere or added to Calendar.")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
                if let outcome { Text(message(outcome)).font(.footnote) }
            }
            if let contacts {
                if contacts.isEmpty {
                    Text("None of your contacts has a birthday saved.").foregroundStyle(Theme.secondaryText)
                } else {
                    Section {
                        ForEach(contacts) { contact in
                            Toggle(isOn: binding(contact)) {
                                VStack(alignment: .leading) {
                                    Text(contact.name)
                                    Text(dayText(contact)).font(.caption).foregroundStyle(Theme.secondaryText)
                                }
                            }
                        }
                    } footer: {
                        Text(String(format: NSLocalizedString("Up to %lld people. The notification shows the name only if notifications may show note text (Settings, Privacy).", comment: ""), Birthdays.maxReminders))
                    }
                }
            } else {
                Text("Turn on Contacts in Settings, Connections, to see birthdays here.").foregroundStyle(Theme.secondaryText)
            }
        }
        .navigationTitle("Birthdays")
        .task {
            if let read = devices.birthdays() {
                contacts = Birthdays.upcoming(read, now: .now, calendar: .current)
            }
        }
    }

    private func binding(_ contact: BirthdayContact) -> Binding<Bool> {
        Binding(
            get: { picked.contains(contact.id) },
            set: { on in
                if on {
                    guard picked.count < Birthdays.maxReminders else { return }
                    picked.insert(contact.id)
                } else {
                    picked.remove(contact.id)
                }
                BirthdayScheduler.picked = picked
                let all = contacts ?? []
                let wanted = picked
                Task { outcome = await BirthdayScheduler.apply(all, picked: wanted) }
            })
    }

    private func dayText(_ contact: BirthdayContact) -> String {
        let date = Calendar.current.date(from: DateComponents(year: 2000, month: contact.month, day: contact.day)) ?? .now
        return date.formatted(.dateTime.day().month(.wide))
    }

    private func message(_ outcome: BirthdayScheduler.Outcome) -> String {
        switch outcome {
        case .scheduled(let count): String(format: NSLocalizedString("Set for %lld people. Checked.", comment: ""), count)
        case .off: NSLocalizedString("Off. Nothing is scheduled.", comment: "")
        case .needsPermission: NSLocalizedString("Notifications are off for Doddy, so birthdays can't be reminded. Turn them on in iOS Settings.", comment: "")
        case .failed: NSLocalizedString("The birthday reminders couldn't be set. Try again.", comment: "")
        }
    }
}
