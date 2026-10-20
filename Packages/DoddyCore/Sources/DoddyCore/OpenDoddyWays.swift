import Foundation

// "Ways to open Doddy": the screen that offers Double Back Tap, the Action Button, a Control Center
// or Lock Screen control, and Siri, each as one short way in. This file only decides which ways
// this iPhone can offer. The words on the screens are the app's; the steps are the user's.
//
// Nothing here can read or set any of them. iOS has no API for the Back Tap or Action Button
// assignment, and none that says a control was added. The screens say so.

/// One way to start "Talk to Doddy". All of them run the same App Intent (`TalkToDoddyIntent`).
public enum OpenDoddyWay: String, CaseIterable, Sendable, Identifiable {
    /// Accessibility › Touch › Back Tap, with the built-in "Talk to Doddy" shortcut. The only way
    /// with a guided test, because only it has a gesture the user has to set up and may doubt.
    case backTap
    /// Settings › Action Button, on iPhones that have one.
    case actionButton
    /// A Doddy control in Control Center or on the Lock Screen (iOS 18 or later).
    case control
    /// "Hey Siri, Talk to Doddy": the App Shortcut's phrases, with nothing to set up.
    case siri

    public var id: String { rawValue }

    /// Whether the user has to change something outside Doddy for this way to exist.
    public var needsSetup: Bool { self != .siri }
}

/// Whether an iPhone has the Action Button, from its model identifier ("iPhone16,1").
public enum ActionButtonSupport: Equatable, Sendable {
    case yes, no
    /// The model can't be read (the simulator, an unexpected identifier). The way is still shown,
    /// with "if your iPhone has one", instead of hiding something that may exist.
    case unknown

    /// The Action Button came with the iPhone 15 Pro, whose identifiers start at `iPhone16`, and every
    /// iPhone model since has it, so a major number of 16 or more means yes and an iPhone below it,
    /// including the iPhone 15 and 15 Plus (`iPhone15,4`, `iPhone15,5`), means no. From Apple's
    /// published lineup, not checked on a device here.
    public static func forModel(_ identifier: String?) -> ActionButtonSupport {
        guard let identifier, identifier.hasPrefix("iPhone") else { return .unknown }
        let digits = identifier.dropFirst("iPhone".count).prefix(while: \.isNumber)
        guard let major = Int(digits) else { return .unknown }
        return major >= 16 ? .yes : .no
    }
}

/// What this device can do, for choosing the ways to show.
public struct OpenDoddyDevice: Equatable, Sendable {
    public var isPhone: Bool
    /// iOS 18 or later: the controls Doddy offers exist from then on.
    public var supportsControls: Bool
    public var actionButton: ActionButtonSupport

    public init(isPhone: Bool, supportsControls: Bool, actionButton: ActionButtonSupport) {
        self.isPhone = isPhone
        self.supportsControls = supportsControls
        self.actionButton = actionButton
    }
}

public enum OpenDoddyWays {
    /// The ways this device can offer, in the order they are shown: the ones that take something
    /// in your hand first, Siri (which needs no setup) last. A way the device can't have isn't shown
    /// at all, so nobody follows steps that lead nowhere.
    public static func available(on device: OpenDoddyDevice) -> [OpenDoddyWay] {
        OpenDoddyWay.allCases.filter { way in
            switch way {
            case .backTap: device.isPhone
            case .actionButton: device.isPhone && device.actionButton != .no
            case .control: device.supportsControls
            case .siri: true
            }
        }
    }
}
