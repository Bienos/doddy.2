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
    /// Bumped when the app comes back to the foreground, so permission changes made in iPhone
    /// Settings show up without restarting.
    private var revision = 0

    init() {
        switches = Dictionary(uniqueKeysWithValues: VoiceConnection.allCases.map {
            ($0, UserDefaults.standard.bool(forKey: $0.preferenceKey))
        })
    }

    func state(of connection: VoiceConnection) -> State {
        _ = revision
        guard switches[connection] == true else { return .off }
        return devices.access(for: connection) == .granted ? .on : .blocked
    }

    /// Turning on asks iOS first. The switch stays off if iOS refuses. Returns the outcome.
    func setOn(_ connection: VoiceConnection, _ on: Bool) async -> DeviceConnections.Access? {
        guard on else {
            store(connection, false)
            return nil
        }
        let access = await devices.request(connection)
        store(connection, access == .granted)
        return access
    }

    func refresh() {
        revision += 1
    }

    private func store(_ connection: VoiceConnection, _ on: Bool) {
        UserDefaults.standard.set(on, forKey: connection.preferenceKey)
        switches[connection] = on
    }
}
