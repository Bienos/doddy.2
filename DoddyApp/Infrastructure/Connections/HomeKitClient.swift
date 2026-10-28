import Foundation
import HomeKit
import DoddyCore

/// What the voice controller needs from HomeKit. A fake in tests.
@MainActor
protocol HomeControlling {
    /// The primary home's lights, outlets, fans and scenes as HomeKit has them now, or nil when
    /// HomeKit didn't load in time. Scenes that touch anything but a light, outlet or fan are
    /// left out, so a scene can never unlock a door through Doddy.
    func snapshot() async -> HomeSnapshot?
    /// Runs one approved command and reports only what HomeKit confirmed.
    func run(_ command: HomeCommand) async -> HomeOutcome
}

/// The only file that talks to HomeKit (guard: check_forbidden_capabilities.sh). The rules for
/// what may be switched and what Doddy may claim are in DoddyCore `HomeCommand`; this file reads
/// the home and writes one characteristic or runs one scene, after the person's tap.
///
/// Needs the HomeKit entitlement (a paid Apple team); the free-team build has none, so iOS
/// reports no access there. NOT COMPILED OR RUN: written without Xcode (HOME_COMMANDS_STATUS.md).
@MainActor
final class HomeKitClient: NSObject, HomeControlling, HMHomeManagerDelegate {
    static let shared = HomeKitClient()

    /// Creating an `HMHomeManager` is what makes iOS ask. Until Allow has been tapped once, no manager
    /// exists, so merely listing Settings never shows the prompt.
    private static let askedKey = "homeKit.asked"

    private var manager: HMHomeManager?
    private var isLoaded = false
    private var waiters: [UUID: CheckedContinuation<Bool, Never>] = [:]

    private static let writeSeconds = 8.0

    // MARK: Permission

    static func access() -> DeviceConnections.Access {
        guard UserDefaults.standard.bool(forKey: askedKey) else { return .notDetermined }
        return map(shared.ensureManager().authorizationStatus)
    }

    static func request() async -> DeviceConnections.Access {
        UserDefaults.standard.set(true, forKey: askedKey)
        let manager = shared.ensureManager()
        // The prompt is up until the person answers; give it a minute.
        for _ in 0..<200 where !manager.authorizationStatus.contains(.determined) {
            try? await Task.sleep(for: .milliseconds(300))
        }
        return map(manager.authorizationStatus)
    }

    private static func map(_ status: HMHomeManagerAuthorizationStatus) -> DeviceConnections.Access {
        if status.contains(.authorized) { return .granted }
        if status.contains(.determined) || status.contains(.restricted) { return .denied }
        return .notDetermined
    }

    private func ensureManager() -> HMHomeManager {
        if let manager { return manager }
        let created = HMHomeManager()
        created.delegate = self
        manager = created
        return created
    }

    // MARK: Delegate

    nonisolated func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        Task { @MainActor in self.markLoaded() }
    }

    private func markLoaded() {
        isLoaded = true
        let pending = waiters
        waiters = [:]
        for (_, waiter) in pending { waiter.resume(returning: true) }
    }

    /// True once HomeKit has loaded the homes, false after `seconds` without it.
    private func loaded(within seconds: Double = 8) async -> Bool {
        guard UserDefaults.standard.bool(forKey: Self.askedKey) else { return false }
        _ = ensureManager()
        if isLoaded { return true }
        let id = UUID()
        return await withCheckedContinuation { continuation in
            waiters[id] = continuation
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                // Resumed already when HomeKit loaded first; only a still-waiting one times out.
                if let waiter = self?.waiters.removeValue(forKey: id) { waiter.resume(returning: false) }
            }
        }
    }

    private var home: HMHome? { manager.flatMap { $0.primaryHome ?? $0.homes.first } }

    // MARK: Reading

    func snapshot() async -> HomeSnapshot? {
        guard await loaded(), let home else { return nil }
        let accessories = home.accessories.map { accessory in
            HomeAccessory(
                id: accessory.uniqueIdentifier.uuidString, name: accessory.name, room: accessory.room?.name,
                kind: Self.kind(of: accessory), reachable: accessory.isReachable)
        }
        let scenes = home.actionSets
            .filter { $0.actionSetType == HMActionSetTypeUserDefined && Self.isSafe($0) }
            .map { HomeScene(id: $0.uniqueIdentifier.uuidString, name: $0.name) }
        return HomeSnapshot(accessories: accessories, scenes: scenes)
    }

    private static func kind(of accessory: HMAccessory) -> HomeAccessoryKind {
        switch accessory.category.categoryType {
        case HMAccessoryCategoryTypeLightbulb: .light
        case HMAccessoryCategoryTypeOutlet: .outlet
        case HMAccessoryCategoryTypeFan: .fan
        case HMAccessoryCategoryTypeThermostat: .thermostat
        case HMAccessoryCategoryTypeDoorLock: .lock
        case HMAccessoryCategoryTypeGarageDoorOpener: .garageDoor
        case HMAccessoryCategoryTypeSecuritySystem: .securitySystem
        case HMAccessoryCategoryTypeIPCamera: .camera
        case HMAccessoryCategoryTypeVideoDoorbell: .doorbell
        default: .other
        }
    }

    /// A scene is offered only when every action in it writes to a light, outlet or fan. Anything
    /// else (a lock, a garage door, an alarm, a blind) or an action Doddy can't read keeps it out.
    private static func isSafe(_ scene: HMActionSet) -> Bool {
        guard !scene.actions.isEmpty else { return false }
        return scene.actions.allSatisfy { action in
            guard let write = action as? HMCharacteristicWriteAction<NSCopying>,
                  let accessory = write.characteristic.service?.accessory else { return false }
            return kind(of: accessory).isControllable
        }
    }

    // MARK: Running

    func run(_ command: HomeCommand) async -> HomeOutcome {
        guard await loaded(), let home else { return .failed("Home didn't load") }
        switch command {
        case let .power(on, id, _, _):
            guard let accessory = home.accessories.first(where: { $0.uniqueIdentifier.uuidString == id }) else {
                return .failed("that accessory is no longer in Home")
            }
            // Checked again here, not only when the card was made.
            guard Self.kind(of: accessory).isControllable else { return .failed("Doddy doesn't control that kind of accessory") }
            guard accessory.isReachable else { return .failed("it isn't responding") }
            return await setPower(accessory, on: on)
        case let .runScene(id, _):
            guard let scene = home.actionSets.first(where: { $0.uniqueIdentifier.uuidString == id }), Self.isSafe(scene) else {
                return .failed("that scene is no longer in Home, or does more than lights, outlets and fans")
            }
            let outcome: Error?? = await deadline(Self.writeSeconds) { done in
                home.executeActionSet(scene) { done($0) }
            }
            switch outcome {
            case .none: return .unknown
            case .some(.some(let error)): return .failed(error.localizedDescription)
            // HomeKit's own acknowledgement that the scene ran; scenes have nothing to read back.
            case .some(.none): return .confirmed
            }
        }
    }

    /// Writes the power state, then reads it back: only a matching read is `.confirmed`.
    private func setPower(_ accessory: HMAccessory, on: Bool) async -> HomeOutcome {
        guard let characteristic = Self.powerCharacteristic(of: accessory) else {
            return .failed("it has no on/off switch Doddy can use")
        }
        let isActive = characteristic.characteristicType == HMCharacteristicTypeActive
        // A power state is a Bool; "Active" (fans, newer accessories) is 0 or 1.
        let value: NSNumber = isActive ? NSNumber(value: on ? 1 : 0) : NSNumber(value: on)
        let written: Error?? = await deadline(Self.writeSeconds) { done in
            characteristic.writeValue(value) { done($0) }
        }
        switch written {
        case .none: return .unknown
        case .some(.some(let error)): return .failed(error.localizedDescription)
        case .some(.none): break
        }
        let read: Error?? = await deadline(Self.writeSeconds) { done in
            characteristic.readValue { done($0) }
        }
        guard case .some(.none) = read, let now = (characteristic.value as? NSNumber)?.boolValue else { return .unknown }
        return now == on ? .confirmed : .failed("HomeKit still reports it as \(now ? "on" : "off")")
    }

    private static func powerCharacteristic(of accessory: HMAccessory) -> HMCharacteristic? {
        for service in accessory.services {
            for type in [HMCharacteristicTypePowerState, HMCharacteristicTypeActive] {
                if let found = service.characteristics.first(where: { $0.characteristicType == type && $0.properties.contains(HMCharacteristicPropertyWritable) }) {
                    return found
                }
            }
        }
        return nil
    }

    // MARK: Deadline

    /// Runs `start`, which must call `done` once. Returns nil if `done` wasn't called within
    /// `seconds`; a late answer is ignored. Never resumes twice.
    private func deadline<T: Sendable>(_ seconds: Double, _ start: (@escaping @Sendable (T) -> Void) -> Void) async -> T? {
        await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            let gate = Gate()
            start { value in
                if gate.claim() { continuation.resume(returning: value) }
            }
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                if gate.claim() { continuation.resume(returning: nil) }
            }
        }
    }
}

private final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}
