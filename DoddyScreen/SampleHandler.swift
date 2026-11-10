import CoreImage
import CoreMedia
import DoddyCore
import Foundation
import ReplayKit

/// "Doddy, what's this on my screen?" (decision 2026-11-09-doddy-looks-at-the-screen): iOS's broadcast upload
/// extension. It runs only while the person shares their screen with Doddy, which they start themselves from
/// iOS's "Start Broadcast" sheet; iOS shows that the screen is being shared and lets them stop it any time.
///
/// It keeps one small JPEG of the screen in the App Group folder, replaced at most once a second, and sends
/// nothing anywhere: no network, no database. The app sends that one picture only when the person asks about
/// their screen in a conversation and says yes (ASK-01). When sharing ends, the picture is deleted.
///
/// iOS gives a broadcast extension about 50 MB of memory, so it holds one frame at a time, reuses one Core
/// Image context and drops frames instead of queueing them.
final class SampleHandler: RPBroadcastSampleHandler {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    private var startedAt = Date()
    private var lastFrameAt = Date.distantPast
    private var busy = false

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        startedAt = Date()
        lastFrameAt = .distantPast
        do {
            try ScreenShareFiles.markStarted(at: startedAt)
        } catch {
            // Without the App Group the app could never see a picture: stop with a reason iOS shows.
            finishBroadcastWithError(NSError(domain: "Doddy", code: 1, userInfo: [
                NSLocalizedDescriptionKey: NSLocalizedString("Screen sharing with Doddy isn't set up in this build.", comment: "Broadcast stopped: no App Group"),
            ]))
        }
    }

    override func broadcastPaused() {
        // Paused (a phone call, the screen locked): no picture of a screen nobody is looking at stays on disk.
        ScreenShareFiles.markEnded()
    }

    override func broadcastResumed() {
        startedAt = Date()
        lastFrameAt = .distantPast
        try? ScreenShareFiles.markStarted(at: startedAt)
    }

    override func broadcastFinished() {
        ScreenShareFiles.markEnded()
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        // Video only: the microphone and app audio are never read.
        guard sampleBufferType == .video, !busy else { return }
        let now = Date()
        guard now.timeIntervalSince(lastFrameAt) >= ScreenShare.frameInterval,
              let pixels = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }
        busy = true
        defer { busy = false }
        lastFrameAt = now
        autoreleasepool {
            guard let jpeg = jpeg(from: pixels, orientation: Self.orientation(of: sampleBuffer)) else { return }
            try? ScreenShareFiles.writeFrame(jpeg, capturedAt: now, startedAt: startedAt)
        }
    }

    /// The screen, upright, scaled to `ScreenShare.frameLongEdge`, as a JPEG under `ScreenShare.maxFrameBytes`.
    private func jpeg(from pixels: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> Data? {
        var image = CIImage(cvPixelBuffer: pixels).oriented(orientation)
        let size = image.extent.size
        let target = ScreenFrameSize.scaled(width: Int(size.width), height: Int(size.height))
        guard target.width > 0, size.width > 0 else { return nil }
        let scale = CGFloat(target.width) / size.width
        if scale < 1 { image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) }
        for quality in [0.6, 0.45, 0.3] {
            let options = [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality]
            guard let data = context.jpegRepresentation(of: image, colorSpace: colorSpace, options: options) else { return nil }
            if data.count <= ScreenShare.maxFrameBytes { return data }
        }
        return nil
    }

    private static func orientation(of sampleBuffer: CMSampleBuffer) -> CGImagePropertyOrientation {
        guard let value = CMGetAttachment(sampleBuffer, key: RPVideoSampleOrientationKey as CFString, attachmentModeOut: nil) as? NSNumber,
              let orientation = CGImagePropertyOrientation(rawValue: value.uint32Value)
        else { return .up }
        return orientation
    }
}
