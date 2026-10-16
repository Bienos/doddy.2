import DoddyCore
import Foundation
import Observation

/// Turns the Settings, Connections switches on and off and reports what each one really is.
/// The switch is a per-device preference; iOS permission is checked again whenever it matters,
/// because the user can change it in iPhone Settings at any time.
@MainActor
@Observable
final class ConnectionController {
    enum State: Equatable {
        case off
        case on
        /// Switched on in Doddy, but iOS no longer allows it.
        case blocked
    }

    private let devices = DeviceConnections()
    private var switches: [VoiceConnection: Bool]
    /// Notification permission is asynchronous, so the last answer is kept for the cards.
    private var notificationAccess: DeviceConnections.Access = .notDetermined
    /// Bumped when permission may have changed, so cards redraw.
    private var revision = 0

    init() {
        switches = Dictionary(uniqueKeysWithValues: VoiceConnection.allCases.map {
            ($0, UserDefaults.standard.bool(forKey: $0.preferenceKey))
        })
        Task { await refresh() }
    }

    func state(of connection: VoiceConnection) -> State {
        _ = revision
        guard switches[connection] == true else { return .off }
        let access = connection == .timers ? notificationAccess : devices.access(for: connection)
        return access == .granted ? .on : .blocked
    }

    /// Turning on asks iOS first. The switch stays off if iOS refuses. Returns the outcome.
    func setOn(_ connection: VoiceConnection, _ on: Bool) async -> DeviceConnections.Access? {
        guard on else {
            store(connection, false)
            return nil
        }
        let access = await devices.request(connection)
        if connection == .timers { notificationAccess = access }
        // Turning on Timers also enables its on-device countdown. Notification access controls
        // the alert only; a denied alert permission must not disable the timer itself.
        store(connection, connection == .timers || access == .granted)
        return access
    }

    /// Re-reads the switches and notification permission and redraws. Called when the app comes
    /// forward, when a sheet closes and when Settings reappears, because another screen's
    /// controller or iPhone Settings may have changed them.
    func refresh() async {
        switches = Dictionary(uniqueKeysWithValues: VoiceConnection.allCases.map {
            ($0, UserDefaults.standard.bool(forKey: $0.preferenceKey))
        })
        notificationAccess = await devices.notificationAccess()
        revision += 1
    }

    private func store(_ connection: VoiceConnection, _ on: Bool) {
        UserDefaults.standard.set(on, forKey: connection.preferenceKey)
        switches[connection] = on
    }
}
