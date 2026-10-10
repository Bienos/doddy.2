import DoddyCore
import Foundation
import Observation
import UserNotifications

/// State for Settings → Updates. Every label reflects what the server or iOS reported;
/// nothing is shown as on until the server confirmed it.
@MainActor
@Observable
final class UpdatesModel {
    enum PushState: Equatable {
        case unknown, off, on, deniedInSettings
    }

    enum PhoneStep: Equatable {
        case enterNumber
        case enterCode(phone: String)
    }

    private(set) var client: DoddyServerClient?
    private(set) var pushState: PushState = .unknown
    private(set) var phone: PhoneStatus = .none
    private(set) var phoneStep: PhoneStep = .enterNumber
    private(set) var isWorking = false
    private(set) var message: String?
    private(set) var lastTest: UpdateStatus?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        client = ServerConfig.client(defaults: defaults)
    }

    var isServerConfigured: Bool { client != nil }

    /// Re-reads the server address (after the field changes) and the current state.
    func reconnect() async {
        client = ServerConfig.client(defaults: defaults)
        await refresh()
    }

    func refresh() async {
        guard let client else { return }
        let status = await PushRegistrar.shared.authorizationStatus()
        if status == .denied {
            pushState = .deniedInSettings
        } else {
            pushState = defaults.bool(forKey: PreferenceKey.pushUpdatesOn) && status == .authorized ? .on : .off
        }
        guard await client.hasAccount() else { return }
        await run { self.phone = try await client.phoneStatus() }
    }

    /// At launch: if the user turned push on earlier, upload the (possibly new) APNs token.
    func syncPushTokenIfOn() async {
        guard let client, defaults.bool(forKey: PreferenceKey.pushUpdatesOn),
              await PushRegistrar.shared.authorizationStatus() == .authorized,
              let token = try? await PushRegistrar.shared.currentDeviceToken()
        else { return }
        try? await client.registerPushToken(token, environment: ServerConfig.pushEnvironment)
    }

    func turnOnPush() async {
        guard let client else { return }
        await run {
            do {
                let token = try await PushRegistrar.shared.requestDeviceToken()
                try await client.registerPushToken(token, environment: ServerConfig.pushEnvironment)
                self.defaults.set(true, forKey: PreferenceKey.pushUpdatesOn)
                self.pushState = .on
            } catch PushRegistrationError.denied {
                self.pushState = .deniedInSettings
            } catch let error where !(error is ServerError) {
                // iOS refused to register: usually a build signed without the Push capability
                // (free Apple ID, DODDY_PUSH_ENTITLEMENTS empty). Say so instead of a raw error.
                self.message = "This build of Doddy can't receive notifications (it needs an Apple developer team with Push Notifications). Daily news still works in the app."
            }
        }
    }

    func turnOffPush() async {
        guard let client else { return }
        await run {
            try await client.removePushToken()
            self.defaults.set(false, forKey: PreferenceKey.pushUpdatesOn)
            self.pushState = .off
        }
    }

    func sendCode(to rawNumber: String) async {
        guard let client else { return }
        guard let e164 = PhoneNumberInput.normalize(rawNumber) else {
            message = "That doesn't look like a phone number. Include the country code, like +48 500 100 200."
            return
        }
        await run {
            try await client.startPhoneVerification(e164)
            self.phoneStep = .enterCode(phone: e164)
        }
    }

    func confirm(code: String) async {
        guard let client, case .enterCode(let e164) = phoneStep else { return }
        await run {
            try await client.confirmPhone(e164, code: code.filter(\.isNumber))
            self.phoneStep = .enterNumber
            self.phone = try await client.phoneStatus()
        }
    }

    func cancelVerification() {
        phoneStep = .enterNumber
        message = nil
    }

    func setTexts(on: Bool) async {
        guard let client else { return }
        await run {
            try await client.setSMSConsent(on)
            self.phone = try await client.phoneStatus()
        }
    }

    func removePhone() async {
        guard let client else { return }
        await run {
            try await client.removePhone()
            self.phone = .none
        }
    }

    /// Sends a real test update and follows its status for a few seconds.
    func sendTest(_ channel: UpdateChannel) async {
        guard let client else { return }
        lastTest = nil
        await run {
            let text = channel == .push
                ? "Test from Doddy: notifications are working."
                : "Test from Doddy: texts are working."
            let queued = try await client.sendUpdate(text, channels: [channel], idempotencyKey: UUID().uuidString)
            guard let id = queued.first?.id else { return }
            for _ in 0..<10 {
                let status = try await client.updateStatus(id)
                self.lastTest = status
                if !status.isPending { break }
                try await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// Deletes everything the server holds for this device. Memories on the iPhone stay.
    func deleteServerAccount() async {
        guard let client else { return }
        await run {
            try await client.deleteAccount()
            self.defaults.set(false, forKey: PreferenceKey.pushUpdatesOn)
            self.defaults.set(false, forKey: PreferenceKey.memoryCopyOn)
            MemoryCopySync.shared.stop()
            self.pushState = .off
            self.phone = .none
            self.phoneStep = .enterNumber
            self.lastTest = nil
            self.message = "Your Doddy messaging data was deleted. Memories on this iPhone were not touched."
        }
    }

    private func run(_ work: @MainActor () async throws -> Void) async {
        isWorking = true
        message = nil
        defer { isWorking = false }
        do {
            try await work()
        } catch {
            message = Self.text(for: error)
        }
    }

    static func text(for error: any Error) -> String {
        guard let error = error as? ServerError else {
            return "Something went wrong and nothing was changed. (\(error.localizedDescription))"
        }
        switch error {
        case .offline: return "Couldn't reach the Doddy messaging server. Check your connection and try again."
        case .notConfigured: return "The Doddy messaging server isn't set up for this yet (missing provider keys). Nothing was sent."
        case .notEnabled("sms_not_enabled"): return "Texts aren't on. Verify your number and turn on texts first."
        case .notEnabled("push_not_enabled"): return "Notifications aren't on for this iPhone yet."
        case .notEnabled: return "Verify your phone number first."
        case .wrongCode: return "That code isn't right. Check the text and try again."
        case .codeExpired: return "That code has expired. Ask for a new one."
        case .phoneRejected: return "That number can't receive codes. Check it and try again."
        case .unsafeURL: return "Doddy can't use that address. Use a public web address (https://…)."
        case .notAFeed: return "That address didn't return a news feed. Look for an RSS or Atom link on the site."
        case .weakPIN: return "Use 6 to 8 digits that are harder to guess: not one repeated digit or a run like 123456."
        case .invalidRequest: return "Something in that request wasn't accepted. Nothing was changed."
        case .rateLimited: return "Too many tries. Wait a while and try again."
        case .providerUnavailable: return "The text service didn't answer. Try again in a moment."
        case .accountMissing: return "This iPhone's Doddy messaging account no longer exists. Try again to start a new one."
        case .unexpected(let status): return "The Doddy messaging server answered with an error (\(status)). Nothing was changed."
        }
    }
}
