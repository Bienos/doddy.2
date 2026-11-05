import DoddyCore
import Foundation
import UserNotifications

// The "price dropped" notification (docs/implementation/SHOPPING_WATCH.md) can only arrive if Doddy's server
// has this iPhone's push token. Asked here, once the user said yes to a watch, because this is when they
// want it, exactly as a handed-over task asks (ErrandsModel); a refusal just leaves the news in the list of
// watched prices, which shows the drop when it is opened. The notification has no product words.

@MainActor
enum WatchPush {
    static func register() async {
        guard let client = ServerConfig.client() else { return }
        let status = await PushRegistrar.shared.authorizationStatus()
        let token: Data?
        switch status {
        case .notDetermined: token = try? await PushRegistrar.shared.requestDeviceToken()
        case .authorized, .provisional, .ephemeral: token = try? await PushRegistrar.shared.currentDeviceToken()
        default: token = nil
        }
        guard let token else { return }
        try? await client.registerPushToken(token, environment: ServerConfig.pushEnvironment)
    }
}
