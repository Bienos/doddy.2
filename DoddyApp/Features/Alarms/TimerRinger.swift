import DoddyCore
import Foundation
#if canImport(AlarmKit)
import AlarmKit
import SwiftUI
#endif

// Timers that ring like the Clock app's (ADR-611). On iOS 26 a timer the user tapped Start for is
// handed to AlarmKit: it rings through Silent mode and a Focus, with Stop and Repeat, and its
// countdown shows on the Lock Screen and in the Dynamic Island (`AlarmLiveActivity`, with Pause
// and Resume). AlarmKit gets the UUID in the timer's identifier, so the action status model
// (ADR-320) reads the same timer back. On an older iOS, or when alarms were refused, the caller
// (`DeviceConnections.scheduleTimer`) falls back to a Time Sensitive notification.

@MainActor
enum TimerRinger {
    enum Attempt: Equatable {
        /// AlarmKit took it; whether it runs is read back from AlarmKit's list.
        case ringing
        /// No AlarmKit (older iOS), or alarms not allowed: nothing was set; use a notification.
        case unavailable
    }

    /// True when a timer can go to AlarmKit (iOS 26, alarms not refused). Not asked yet counts:
    /// iOS asks at the Start tap, and a no then falls back to a notification.
    static var canRing: Bool { AlarmScheduler.support() == .available }

    /// Hands the timer to AlarmKit under the UUID in `identifier`. Noted first, so a retry finds
    /// it even if AlarmKit lists it late. A throw does not prove nothing was set.
    static func start(_ draft: TimerDraft, identifier: String, now: Date = Date()) async throws -> Attempt {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *), let id = TimerIdempotency.alarmID(fromIdentifier: identifier) {
            let note = RingingTimer(
                alarmID: id, identifier: identifier, firesAt: now.addingTimeInterval(TimeInterval(draft.seconds)),
                label: draft.label, noted: now)
            TimerBook.remember(note)
            do {
                if try await TimerKitBackend.start(draft, id: id) { return .ringing }
            } catch {
                if TimerKitBackend.listedIDs()?.contains(id) != true { TimerBook.forget(id) }
                throw error
            }
            TimerBook.forget(id)
            return .unavailable
        }
        #endif
        return .unavailable
    }

    /// Doddy's timers AlarmKit is running, with the ring time asked for. Empty when AlarmKit's
    /// list can't be read; the notes are then kept, not dropped.
    static func pending(now: Date = Date()) -> [PendingTimer] {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            guard let listed = TimerKitBackend.listedIDs() else { return [] }
            let notes = TimerBook.all()
            TimerBook.replace(with: RingingTimerBook.kept(notes, listed: listed, now: now))
            return RingingTimerBook.pending(notes, listed: listed)
        }
        #endif
        return []
    }

    /// True when AlarmKit lists the timer named by `identifier`.
    static func isListed(_ identifier: String) -> Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *), let id = TimerIdempotency.alarmID(fromIdentifier: identifier) {
            return TimerKitBackend.listedIDs()?.contains(id) == true
        }
        #endif
        return false
    }
}

/// What Doddy noted about the timers it gave AlarmKit, on this iPhone only (UserDefaults).
@MainActor
private enum TimerBook {
    private static let key = "timers.ringing"

    static func all() -> [RingingTimer] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([RingingTimer].self, from: data)) ?? []
    }

    static func replace(with notes: [RingingTimer]) {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func remember(_ note: RingingTimer) {
        replace(with: all().filter { $0.alarmID != note.alarmID } + [note])
    }

    static func forget(_ id: UUID) {
        replace(with: all().filter { $0.alarmID != id })
    }
}

#if canImport(AlarmKit)
@available(iOS 26.0, *)
@MainActor
private enum TimerKitBackend {
    /// False when alarms aren't allowed (asked now if never asked). A return doesn't prove it is listed.
    static func start(_ draft: TimerDraft, id: UUID) async throws -> Bool {
        let manager = AlarmManager.shared
        switch manager.authorizationState {
        case .authorized: break
        case .notDetermined:
            guard try await manager.requestAuthorization() == .authorized else { return false }
        default: return false
        }
        let language = NotificationLanguage.current
        let text = { (words: String) in LocalizedStringResource(stringLiteral: words) }
        let title = text(TimerCopy.title(label: draft.label, language))
        // Ringing: Stop, and Repeat, which runs the same length again (the Clock app's pair).
        // From iOS 26.1 iOS draws Stop itself; before that the app gives it.
        let repeatButton = AlarmButton(
            text: text(TimerCopy.button(.repeatTimer, language)), textColor: .white, systemImageName: "arrow.clockwise")
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(title: title, secondaryButton: repeatButton, secondaryButtonBehavior: .countdown)
        } else {
            alert = AlarmPresentation.Alert(
                title: title,
                stopButton: AlarmButton(text: text(TimerCopy.button(.stop, language)), textColor: .white, systemImageName: "stop.fill"),
                secondaryButton: repeatButton, secondaryButtonBehavior: .countdown)
        }
        // Counting down and paused: drawn by the widget extension (AlarmLiveActivity) with these words.
        let countdown = AlarmPresentation.Countdown(
            title: title,
            pauseButton: AlarmButton(text: text(TimerCopy.button(.pause, language)), textColor: .white, systemImageName: "pause.fill"))
        let paused = AlarmPresentation.Paused(
            title: text(TimerCopy.paused(language)),
            resumeButton: AlarmButton(text: text(TimerCopy.button(.resume, language)), textColor: .white, systemImageName: "play.fill"))
        let attributes = AlarmAttributes<DoddyAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert, countdown: countdown, paused: paused),
            metadata: DoddyAlarmMetadata(kind: .timer, language: language.rawValue), tintColor: .orange)
        let seconds = TimeInterval(draft.seconds)
        let configuration = AlarmManager.AlarmConfiguration<DoddyAlarmMetadata>(
            countdownDuration: Alarm.CountdownDuration(preAlert: seconds, postAlert: seconds),
            schedule: nil, attributes: attributes)
        _ = try await manager.schedule(id: id, configuration: configuration)
        return true
    }

    /// Nil when AlarmKit's list can't be read; an empty set only when it really is empty.
    static func listedIDs() -> Set<UUID>? {
        (try? AlarmManager.shared.alarms).map { Set($0.map(\.id)) }
    }
}
#endif
