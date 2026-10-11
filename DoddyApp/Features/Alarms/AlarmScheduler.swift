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

/// One alarm Doddy set, as shown in Settings › Alarms.
struct DoddyAlarm: Identifiable, Equatable {
    let id: UUID
    let summary: String
    let label: String?
}

@MainActor
enum AlarmScheduler {
    enum Outcome: Equatable {
        case verified
        case unconfirmed
        case needsNewerIOS
        case notAllowed
    }

    /// Before a card is shown: can this iPhone set an alarm at all?
    static func support() -> AlarmSupport {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) { return AlarmKitBackend.support() }
        #endif
        return .needsNewerIOS
    }

    /// Asks for permission the first time, sets the alarm, then reads AlarmKit's list back.
    static func schedule(_ draft: AlarmDraft) async throws -> Outcome {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            let outcome = try await AlarmKitBackend.schedule(draft)
            if case .verified(let id) = outcome {
                AlarmBook.remember(DoddyAlarm(id: id, summary: draft.summary, label: draft.label))
                return .verified
            }
            return outcome == .notAllowed ? .notAllowed : .unconfirmed
        }
        #endif
        return .needsNewerIOS
    }

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

/// What Doddy remembers about its own alarms (the label and the time as asked), on this iPhone
/// only, so the list in Settings can name them. AlarmKit is the truth about whether one exists.
private enum AlarmBook {
    private static let key = "alarms.book"

    static func all() -> [DoddyAlarm] {
        let stored = UserDefaults.standard.dictionary(forKey: key) as? [String: [String: String]] ?? [:]
        return stored.compactMap { id, fields in
            guard let uuid = UUID(uuidString: id), let summary = fields["summary"] else { return nil }
            return DoddyAlarm(id: uuid, summary: summary, label: fields["label"])
        }
        .sorted { $0.summary < $1.summary }
    }

    static func remember(_ alarm: DoddyAlarm) {
        var stored = UserDefaults.standard.dictionary(forKey: key) as? [String: [String: String]] ?? [:]
        var fields = ["summary": alarm.summary]
        if let label = alarm.label { fields["label"] = label }
        stored[alarm.id.uuidString] = fields
        UserDefaults.standard.set(stored, forKey: key)
    }

    static func keepOnly(_ ids: Set<UUID>) {
        let stored = UserDefaults.standard.dictionary(forKey: key) as? [String: [String: String]] ?? [:]
        UserDefaults.standard.set(stored.filter { UUID(uuidString: $0.key).map(ids.contains) ?? false }, forKey: key)
    }
}

#if canImport(AlarmKit)
@available(iOS 26.0, *)
private struct DoddyAlarmMetadata: AlarmMetadata {}

@available(iOS 26.0, *)
@MainActor
private enum AlarmKitBackend {
    enum Result: Equatable {
        case verified(UUID)
        case unconfirmed
        case notAllowed
    }

    static func support() -> AlarmSupport {
        switch AlarmManager.shared.authorizationState {
        case .denied: .notAllowed
        default: .available
        }
    }

    static func schedule(_ draft: AlarmDraft) async throws -> Result {
        let manager = AlarmManager.shared
        switch manager.authorizationState {
        case .authorized: break
        case .notDetermined:
            guard try await manager.requestAuthorization() == .authorized else { return .notAllowed }
        default: return .notAllowed
        }
        let schedule: Alarm.Schedule
        if let repeats = draft.repeats {
            let days = repeats.weekdays.compactMap(weekday)
            schedule = .relative(.init(time: .init(hour: draft.hour, minute: draft.minute), repeats: .weekly(days)))
        } else {
            guard let date = draft.first.date else { return .unconfirmed }
            schedule = .fixed(date)
        }
        let title: LocalizedStringResource = draft.label.map { LocalizedStringResource(stringLiteral: $0) } ?? "Doddy alarm"
        let alert = AlarmPresentation.Alert(
            title: title,
            stopButton: AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.fill"))
        let attributes = AlarmAttributes<DoddyAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert), metadata: nil, tintColor: .orange)
        let id = UUID()
        _ = try await manager.schedule(id: id, configuration: .alarm(schedule: schedule, attributes: attributes))
        return scheduledIDs().contains(id) ? .verified(id) : .unconfirmed
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
