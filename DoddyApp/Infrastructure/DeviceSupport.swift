import DoddyCore
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// What this device can do that the iPhone-only parts of Doddy need (ADR-337, ADR-349). The rules
/// are `HostDevice` in DoddyCore; this only says which device it is.
enum DeviceSupport {
    /// An iPhone, an iPad, or a Mac running the iPad app.
    @MainActor static var host: HostDevice {
        #if canImport(UIKit)
        if ProcessInfo.processInfo.isiOSAppOnMac { return .mac }
        return UIDevice.current.userInterfaceIdiom == .phone ? .phone : .pad
        #else
        return .phone
        #endif
    }

    /// Accessibility › Touch › Back Tap is an iPhone setting; iPad and Mac have none.
    @MainActor static var hasBackTap: Bool { host.supports(.backTap) }
}
