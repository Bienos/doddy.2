import DoddyCore
import Foundation
#if canImport(AlarmKit)
import AlarmKit
import SwiftUI
#endif

// Alarms (ADR-260). AlarmKit is used only in this folder (scripts/check_forbidden_capabilities.sh),
// and only on iOS 26 and later; built with an older SDK, or run on an older iOS, alarms report
// `needsNewerIOS` and the agent offers a timer or a reminder instead. An alarm is set only after
// the user taps Set alarm, and "set" means AlarmKit lists it afterwards.

/// One alarm Doddy set, as shown in Settings › Alarms and matched by voice (ADR-283).
typealias DoddyAlarm = AlarmEntry

@MainActor
enum AlarmScheduler {
    /// Before a card is shown: can this iPhone set an alarm at all?
    static func support() -> AlarmSupport {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) { return AlarmKitBackend.support() }
        #endif
        return .needsNewerIOS
    }

    /// Asks for permission the first time and sets the alarm under `id`. Whether it is set is
    /// read from AlarmKit's list afterwards, by AlarmSetAction (ADR-301).
    static func schedule(_ draft: AlarmDraft, id: UUID) async throws -> AlarmScheduleAttempt {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            return try await AlarmKitBackend.schedule(draft, id: id) ? .scheduled : .notAllowed
        }
        #endif
        return .needsNewerIOS
    }

    /// Every alarm id AlarmKit lists for Doddy.
    static func scheduledIDs() -> Set<UUID> {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) { return AlarmKitBackend.scheduledIDs() }
        #endif
        return []
    }

    static func remember(_ alarm: DoddyAlarm) { AlarmBook.remember(alarm) }
    static func forget(_ id: UUID) { AlarmBook.forget(id) }

    /// Doddy's alarms that AlarmKit still has. Alarms that rang once and are gone drop out.
    static func current() -> [DoddyAlarm] {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            let ids = AlarmKitBackend.scheduledIDs()
            AlarmBook.keepOnly(ids)
            return AlarmBook.all().filter { ids.contains($0.id) }
        }
        #endif
        return []
    }

    /// Turns one off. True only when AlarmKit no longer lists it.
    static func cancel(_ id: UUID) -> Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            AlarmKitBackend.cancel(id)
            let gone = !AlarmKitBackend.scheduledIDs().contains(id)
            if gone { AlarmBook.keepOnly(AlarmKitBackend.scheduledIDs()) }
            return gone
        }
        #endif
        return false
    }
}

/// AlarmScheduler as AlarmSetAction needs it (ADR-301).
@MainActor
final class AlarmKitWriter: AlarmWriter {
    func alarms() -> [AlarmEntry] { AlarmScheduler.current() }
    func scheduledAlarmIDs() -> Set<UUID> { AlarmScheduler.scheduledIDs() }
    func scheduleAlarm(_ draft: AlarmDraft, id: UUID) async throws -> AlarmScheduleAttempt { try await AlarmScheduler.schedule(draft, id: id) }
    func remember(_ alarm: AlarmEntry) { AlarmScheduler.remember(alarm) }
    func forget(_ id: UUID) { AlarmScheduler.forget(id) }
}

/// What Doddy remembers about its own alarms (the label and the time as asked), on this iPhone
/// only, so the list in Settings can name them. AlarmKit is the truth about whether one exists.
private enum AlarmBook {
    private static let key = "alarms.book"

    static func all() -> [DoddyAlarm] {
        let stored = UserDefaults.standard.dictionary(forKey: key) as? [String: [String: String]] ?? [:]
        return stored.compactMap { id, fields in
            guard let uuid = UUID(uuidString: id), let summary = fields["summary"] else { return nil }
            // Alarms set before ADR-283 kept no clock; their summary starts with it. Before ADR-301, no key.
            return DoddyAlarm(
                id: uuid, clock: fields["clock"] ?? String(summary.prefix(5)), label: fields["label"], summary: summary,
                key: fields["key"])
        }
        .sorted { $0.summary < $1.summary }
    }

    static func remember(_ alarm: DoddyAlarm) {
        var stored = UserDefaults.standard.dictionary(forKey: key) as? [String: [String: String]] ?? [:]
        var fields = ["summary": alarm.summary, "clock": alarm.clock]
        if let label = alarm.label { fields["label"] = label }
        if let alarmKey = alarm.key { fields["key"] = alarmKey }
        fields["noted"] = String(Date().timeIntervalSince1970)
        stored[alarm.id.uuidString] = fields
        UserDefaults.standard.set(stored, forKey: key)
    }

    static func forget(_ id: UUID) {
        var stored = UserDefaults.standard.dictionary(forKey: key) as? [String: [String: String]] ?? [:]
        stored[id.uuidString] = nil
        UserDefaults.standard.set(stored, forKey: key)
    }

    /// Drops notes of alarms AlarmKit no longer lists, except one noted in the last 10 minutes:
    /// AlarmKit may list a just-set alarm late, and a retry must still find it (ADR-301).
    static func keepOnly(_ ids: Set<UUID>, now: Date = Date()) {
        let stored = UserDefaults.standard.dictionary(forKey: key) as? [String: [String: String]] ?? [:]
        UserDefaults.standard.set(stored.filter { id, fields in
            if UUID(uuidString: id).map(ids.contains) ?? false { return true }
            guard let noted = fields["noted"].flatMap(Double.init) else { return false }
            return now.timeIntervalSince1970 - noted < 600
        }, forKey: key)
    }
}

#if canImport(AlarmKit)
@available(iOS 26.0, *)
@MainActor
private enum AlarmKitBackend {
    static func support() -> AlarmSupport {
        switch AlarmManager.shared.authorizationState {
        case .denied: .notAllowed
        default: .available
        }
    }

    /// False when alarms aren't allowed. A schedule that returns doesn't prove the alarm is listed.
    static func schedule(_ draft: AlarmDraft, id: UUID) async throws -> Bool {
        let manager = AlarmManager.shared
        switch manager.authorizationState {
        case .authorized: break
        case .notDetermined:
            guard try await manager.requestAuthorization() == .authorized else { return false }
        default: return false
        }
        let schedule: Alarm.Schedule
        if let repeats = draft.repeats {
            let days = repeats.weekdays.compactMap(weekday)
            schedule = .relative(.init(time: .init(hour: draft.hour, minute: draft.minute), repeats: .weekly(days)))
        } else {
            guard let date = draft.first.date else { throw AlarmDateUnreadable() }
            schedule = .fixed(date)
        }
        let title: LocalizedStringResource = draft.label.map { LocalizedStringResource(stringLiteral: $0) } ?? "Doddy alarm"
        // Stop, and Snooze (ADR-283): rings again after `snoozeMinutes`, with a countdown on the
        // Lock Screen drawn by the widget extension (AlarmLiveActivity).
        let alert = AlarmPresentation.Alert(
            title: title,
            stopButton: AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.fill"),
            secondaryButton: AlarmButton(text: "Snooze", textColor: .white, systemImageName: "zzz"),
            secondaryButtonBehavior: .countdown)
        let countdown = AlarmPresentation.Countdown(title: "Snoozed")
        let attributes = AlarmAttributes<DoddyAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert, countdown: countdown), metadata: nil, tintColor: .orange)
        let configuration = AlarmManager.AlarmConfiguration<DoddyAlarmMetadata>(
            countdownDuration: Alarm.CountdownDuration(preAlert: nil, postAlert: TimeInterval(AlarmDraft.snoozeMinutes * 60)),
            schedule: schedule, attributes: attributes)
        _ = try await manager.schedule(id: id, configuration: configuration)
        return true
    }

    struct AlarmDateUnreadable: LocalizedError {
        var errorDescription: String? { "The alarm's time couldn't be read." }
    }

    static func scheduledIDs() -> Set<UUID> {
        Set(((try? AlarmManager.shared.alarms) ?? []).map(\.id))
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
