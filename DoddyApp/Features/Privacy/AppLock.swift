import DoddyCore
import Foundation
import LocalAuthentication
import Observation
import SwiftUI

/// Face ID (or Touch ID, or the passcode) for Doddy (ADR-310): the optional lock on the whole app,
/// and the private notes' words. iOS does the checking; Doddy only learns yes or no. The only file
/// that uses LocalAuthentication (`scripts/check_forbidden_capabilities.sh`).
@MainActor
@Observable
final class AppLock {
    static let shared = AppLock()

    /// Set by a successful check; cleared when the app has been away long enough.
    private(set) var unlockedAt: Date?
    private var backgroundSince: Date?
    private(set) var problem: String?

    var lockOn: Bool { UserDefaults.standard.bool(forKey: PrivateNotes.appLockKey) }

    /// The whole app is covered until Face ID.
    var isLocked: Bool {
        PrivateNotes.needsUnlock(lockOn: lockOn, unlockedAt: unlockedAt, backgroundSince: backgroundSince, now: Date())
    }

    /// Private notes' words are shown after a check this session (and until the app is away).
    var privateUnlocked: Bool {
        unlockedAt != nil && !PrivateNotes.needsUnlock(lockOn: true, unlockedAt: unlockedAt, backgroundSince: backgroundSince, now: Date())
    }

    func wentToBackground() { backgroundSince = Date() }

    func cameBack() {
        if let backgroundSince, Date().timeIntervalSince(backgroundSince) >= PrivateNotes.relockAfter { unlockedAt = nil }
        backgroundSince = nil
    }

    /// Asks iOS. True only when iOS said yes.
    @discardableResult
    func unlock(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            problem = NSLocalizedString("This iPhone has no passcode or Face ID set up, so Doddy can't lock.", comment: "")
            return false
        }
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            if ok {
                unlockedAt = Date()
                backgroundSince = nil
                problem = nil
            }
            return ok
        } catch {
            return false
        }
    }

    /// Whether the lock can be turned on at all on this iPhone.
    static var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }
}

/// Which notes are private, on this iPhone only (ADR-310). Every change is read back.
enum PrivateNotesStore {
    static func current() -> PrivateNotes {
        PrivateNotes(stored: UserDefaults.standard.string(forKey: PrivateNotes.storageKey))
    }

    /// True only when the stored set reads back with the change.
    static func set(_ id: UUID, isPrivate: Bool) -> Bool {
        var notes = current()
        notes.set(id, isPrivate: isPrivate)
        UserDefaults.standard.set(notes.stored, forKey: PrivateNotes.storageKey)
        return current().contains(id) == isPrivate
    }
}

/// What covers Doddy while it is locked (ADR-310): nothing of the app shows through.
struct AppLockView: View {
    private let lock = AppLock.shared

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill").font(.largeTitle).accessibilityHidden(true)
            Text("Doddy is locked").font(.title2.weight(.medium))
            Button {
                Task { await lock.unlock(reason: NSLocalizedString("Open Doddy", comment: "")) }
            } label: {
                Label("Unlock", systemImage: "faceid").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.ink)
            .accessibilityIdentifier("lock.unlock")
            if let problem = lock.problem {
                Text(problem).font(.footnote).foregroundStyle(Theme.error).multilineTextAlignment(.center)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas)
        .foregroundStyle(Theme.ink)
        .task { await lock.unlock(reason: NSLocalizedString("Open Doddy", comment: "")) }
    }
}

/// Settings › Privacy › Lock Doddy with Face ID. Turning it on asks once, so it can't lock you out.
struct AppLockToggle: View {
    @AppStorage(PrivateNotes.appLockKey) private var lockOn = false
    @State private var message: String?

    var body: some View {
        Toggle("Lock Doddy with Face ID", isOn: Binding(get: { lockOn }, set: { wanted in
            Task {
                // Both ways need a check, so nobody else can switch the lock off.
                if await AppLock.shared.unlock(reason: NSLocalizedString("Change Doddy's lock", comment: "")) {
                    lockOn = wanted
                    message = nil
                } else {
                    message = AppLock.shared.problem ?? NSLocalizedString("Not changed: Face ID didn't confirm it.", comment: "")
                }
            }
        }))
        .frame(minHeight: 44)
        .accessibilityIdentifier("settings.appLock")
        Text("Asks for Face ID or your passcode when Doddy opens and after a minute away. Private notes always ask before showing their words.")
            .font(.footnote).foregroundStyle(Theme.secondaryText)
        if let message { Text(message).font(.footnote).foregroundStyle(Theme.error) }
    }
}
