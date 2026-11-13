import DoddyCore
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

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // One delegate for every banner: timers, nudges and Doddy's updates show while the app is open.
        UNUserNotificationCenter.current().delegate = TimerBanners.shared
        // A voice token is fetched ahead when Doddy comes to the front, so Talk only has to connect
        // (decision 2026-11-10-action-button-start). Warms only in the foreground, never on a background launch.
        MainActor.assumeIsolated { VoiceTokenWarmer.shared.install() }
        // A picture of the screen left behind by the sharing extension is deleted now and whenever the app comes
        // to the front (`ScreenFrameRetention`).
        MainActor.assumeIsolated { ScreenFrameSweeper.shared.install() }
        return true
    }

    /// The scene delegate only receives shared-list links (ADR-263); SwiftUI still draws the window.
    func application(
        _ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = ShareAcceptSceneDelegate.self
        return configuration
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushRegistrar.shared.didRegister(deviceToken)
    }

    /// Pushes iOS hands the app in the background: iCloud saying a shared list changed (ADR-284), and Doddy's server
    /// saying a task finished (12 Nov 2026; the server marks that push `content-available`). For the task, its result
    /// is fetched and saved in Messages now, so it is there when the person taps the notification or opens Doddy.
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        if ServerPushKind.parse(userInfo) == .errandResult {
            return await Self.saveTaskResults() ? .newData : .noData
        }
        return await SharedListsController.shared.handleRemoteNotification(userInfo) ? .newData : .noData
    }

    @MainActor
    private static func saveTaskResults() async -> Bool {
        let finishedBefore = ErrandsModel.shared.errands.filter { $0.state.isFinished }.count
        await ErrandsModel.shared.refresh()
        return ErrandsModel.shared.errands.filter { $0.state.isFinished }.count > finishedBefore
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        PushRegistrar.shared.didFail(error)
    }
}
