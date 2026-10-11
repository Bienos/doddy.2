import Foundation

// Where Doddy is running (ADR-349). The same app runs on an iPhone, on an iPad and, as an iPad app,
// on a Mac with Apple silicon ("Designed for iPad"). A few things exist on one and not another;
// this is the single place that says which, so a screen or a voice reply never offers what the
// device can't do. Nothing here reads the device: the app passes in what it is.

public enum HostDevice: String, Equatable, Sendable, CaseIterable {
    case phone, pad, mac

    public enum Feature: Equatable, Sendable, CaseIterable {
        /// Accessibility › Touch › Back Tap, an iPhone setting.
        case backTap
        /// Lock Screen and Dynamic Island Live Activities (shopping mode, timers, leave-by).
        case liveActivities
        /// Alarms through AlarmKit.
        case alarms
        /// Notifications for reminders and renewals work everywhere; kept here so the list is whole.
        case notifications
    }

    public func supports(_ feature: Feature) -> Bool {
        switch (self, feature) {
        case (_, .notifications): true
        case (.phone, _): true
        case (.pad, .backTap): false
        case (.pad, .liveActivities): true  // iOS decides (areActivitiesEnabled); nothing changes on iPad.
        case (.pad, .alarms): true
        case (.mac, .backTap), (.mac, .liveActivities), (.mac, .alarms): false
        }
    }

    /// How a reply or screen names this device: "iPhone", "iPad" or "Mac".
    public var name: String {
        switch self {
        case .phone: "iPhone"
        case .pad: "iPad"
        case .mac: "Mac"
        }
    }
}

extension VoiceToolReply {
    /// An alarm was asked for on a device without AlarmKit.
    public static func alarmNotOnThisDevice(_ host: HostDevice) -> String {
        "failed: alarms can't be set on this \(host.name). Nothing was set. Offer a timer (up to 24 hours) or a reminder instead."
    }
}
