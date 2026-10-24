import DoddyCore
import Foundation
#if canImport(AlarmKit)
import AlarmKit
import SwiftUI
#endif

// Important reminders that ring like an alarm (ADR-608). The user marks a note's reminder "Ring
// like an alarm" (the reminder sheet, or the voice card after the user's tap); the note reminder
// itself is unchanged, and an AlarmKit alarm rings at the same moment, through Silent mode and a
// Focus, with Stop and "In 10 min". `sync` makes AlarmKit match the database reminders whenever
// NoteReminderStore reloads them (DoddyCore `RingingReminderSync` decides what to do). The wish
// and the alarm's id are kept on this iPhone only (UserDefaults), like Doddy's alarms (ADR-260).

@MainActor
enum ReminderRinger {
    /// iOS 26 and alarms not refused (not asked yet counts: iOS asks when the first one is set).
    static var isAvailable: Bool { AlarmScheduler.support() == .available }

    static func wantsToRing(_ memoryID: UUID) -> Bool {
        RingingReminderBook.all().contains { $0.memoryID == memoryID }
    }

    static var hasWishes: Bool { !RingingReminderBook.all().isEmpty }

    /// Marks the note's reminder to ring, or not. Turning it off cancels the alarm at once.
    static func setWish(_ memoryID: UUID, rings: Bool) {
        var entries = RingingReminderBook.all()
        if rings {
            guard !entries.contains(where: { $0.memoryID == memoryID }) else { return }
            entries.append(RingingReminderEntry(memoryID: memoryID))
        } else {
            for entry in entries where entry.memoryID == memoryID { cancel(entry.alarmIDs) }
            entries.removeAll { $0.memoryID == memoryID }
        }
        RingingReminderBook.replace(with: entries)
    }

    /// Makes AlarmKit match `reminders` for every note that wants to ring. `title` gives each
    /// note's ringing-screen title. Returns the notes that ring now (read back from AlarmKit).
    @discardableResult
    static func sync(_ reminders: [MemoryReminder], title: (UUID) -> String, now: Date = Date()) async -> Set<UUID> {
        var entries = RingingReminderBook.all()
        guard !entries.isEmpty else { return [] }
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            for step in RingingReminderSync.steps(
                entries: entries, reminders: reminders, listed: ReminderKitBackend.listedIDs(), now: now, title: title) {
                switch step {
                case .cancel(let ids):
                    cancel(ids)
                case .forget(let memoryID):
                    entries.removeAll { $0.memoryID == memoryID }
                case .schedule(let memoryID, let plan):
                    guard let index = entries.firstIndex(where: { $0.memoryID == memoryID }) else { continue }
                    let id = UUID()
                    // Noted only when AlarmKit took it; a refusal leaves the wish to try again later.
                    if (try? await ReminderKitBackend.schedule(plan, id: id, title: title(memoryID))) == true {
                        entries[index].alarmIDs = [id]
                        entries[index].signature = RingingReminderSync.signature(plan, title: title(memoryID))
                    }
                }
            }
            RingingReminderBook.replace(with: entries)
            let listed = ReminderKitBackend.listedIDs()
            return Set(entries.compactMap { entry in
                let reminder = reminders.first { $0.memoryID == entry.memoryID }
                return RingingReminderSync.isRinging(entry, reminder: reminder, listed: listed, now: now, title: title(entry.memoryID))
                    ? entry.memoryID : nil
            })
        }
        #endif
        return []
    }

    private static func cancel(_ ids: [UUID]) {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) { ids.forEach(ReminderKitBackend.cancel) }
        #endif
    }
}

/// The notes that want to ring and their alarms, on this iPhone only.
@MainActor
private enum RingingReminderBook {
    private static let key = "noteReminders.ringing"

    static func all() -> [RingingReminderEntry] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([RingingReminderEntry].self, from: data)) ?? []
    }

    static func replace(with entries: [RingingReminderEntry]) {
        if entries.isEmpty { return UserDefaults.standard.removeObject(forKey: key) }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

#if canImport(AlarmKit)
@available(iOS 26.0, *)
@MainActor
private enum ReminderKitBackend {
    /// False when alarms aren't allowed (asked now if never asked).
    static func schedule(_ plan: ReminderRingPlan, id: UUID, title: String) async throws -> Bool {
        let manager = AlarmManager.shared
        switch manager.authorizationState {
        case .authorized: break
        case .notDetermined:
            guard try await manager.requestAuthorization() == .authorized else { return false }
        default: return false
        }
        let language = NotificationLanguage.current
        let text = { (words: String) in LocalizedStringResource(stringLiteral: words) }
        let schedule: Alarm.Schedule
        switch plan {
        case .once(let date):
            schedule = .fixed(date)
        case .weekly(let hour, let minute, let weekdays):
            schedule = .relative(.init(time: .init(hour: hour, minute: minute), repeats: .weekly(weekdays.compactMap(weekday))))
        }
        // Ringing: Stop, and "In 10 min" (the alarm's own snooze). Done stays on the notification.
        let snooze = AlarmButton(text: text(ReminderRing.snoozeButton(language)), textColor: .white, systemImageName: "zzz")
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(title: text(title), secondaryButton: snooze, secondaryButtonBehavior: .countdown)
        } else {
            alert = AlarmPresentation.Alert(
                title: text(title),
                stopButton: AlarmButton(text: text(ReminderRing.stopButton(language)), textColor: .white, systemImageName: "stop.fill"),
                secondaryButton: snooze, secondaryButtonBehavior: .countdown)
        }
        let attributes = AlarmAttributes<DoddyAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert, countdown: AlarmPresentation.Countdown(title: text(ReminderRing.snoozeButton(language)))),
            metadata: DoddyAlarmMetadata(kind: .reminder, language: language.rawValue), tintColor: .orange)
        let configuration = AlarmManager.AlarmConfiguration<DoddyAlarmMetadata>(
            countdownDuration: Alarm.CountdownDuration(preAlert: nil, postAlert: TimeInterval(ReminderRing.snoozeMinutes * 60)),
            schedule: schedule, attributes: attributes)
        _ = try await manager.schedule(id: id, configuration: configuration)
        return true
    }

    static func listedIDs() -> Set<UUID>? {
        (try? AlarmManager.shared.alarms).map { Set($0.map(\.id)) }
    }

    static func cancel(_ id: UUID) {
        try? AlarmManager.shared.cancel(id: id)
    }

    private static func weekday(_ number: Int) -> Locale.Weekday? {
        switch number {
        case 1: .sunday
        case 2: .monday
        case 3: .tuesday
        case 4: .wednesday
        case 5: .thursday
        case 6: .friday
        case 7: .saturday
        default: nil
        }
    }
}
#endif
