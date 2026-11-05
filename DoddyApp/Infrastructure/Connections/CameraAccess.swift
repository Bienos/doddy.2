import AVFoundation
import Foundation

/// Camera permission for Doddy's camera (ADR-569): whether there is a camera, iOS's answer, and
/// iOS's prompt. Nothing else: the photo itself is taken on iOS's own camera screen
/// (`CameraCapture`, Features/Photos), and there is no capture session anywhere in the app. The
/// guard script allows AVFoundation here only for these calls.
@MainActor
enum CameraAccess {
    static var isAvailable: Bool { AVCaptureDevice.default(for: .video) != nil }

    static func access() -> DeviceConnections.Access {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    static func request() async -> DeviceConnections.Access {
        guard access() == .notDetermined else { return access() }
        _ = await AVCaptureDevice.requestAccess(for: .video)
        return access()
    }
}
