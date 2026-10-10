import Foundation
import UIKit
import UserNotifications

enum PushRegistrationError: Error {
    case denied
}

/// Bridges iOS's delegate callbacks for the APNs device token into async calls.
@MainActor
final class PushRegistrar {
    static let shared = PushRegistrar()
    private var waiting: [CheckedContinuation<Data, any Error>] = []

    /// Asks permission (only when the user turns notifications on), then returns the token.
    func requestDeviceToken() async throws -> Data {
        let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        guard granted else { throw PushRegistrationError.denied }
        return try await currentDeviceToken()
    }

    /// Re-registers without prompting; used at launch when permission was already given.
    func currentDeviceToken() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            waiting.append(continuation)
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func didRegister(_ token: Data) {
        let continuations = waiting
        waiting = []
        continuations.forEach { $0.resume(returning: token) }
    }

    func didFail(_ error: any Error) {
        let continuations = waiting
        waiting = []
        continuations.forEach { $0.resume(throwing: error) }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushRegistrar.shared.didRegister(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        PushRegistrar.shared.didFail(error)
    }

    /// Shows Doddy's updates as banners even while the app is open.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
