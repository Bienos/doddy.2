import DoddyCore
import Foundation
import Photos
import UIKit

/// What a photo search found: the summary the agent hears, and which photos to show on screen.
struct PhotoSearchFound: Equatable, Sendable {
    let summary: PhotoSearchSummary
    /// The newest photos and videos first, at most `PhotoLibrarySearch.shownOnScreen`. Shown on
    /// the user's screen only; never sent anywhere.
    let identifiers: [String]

    static let empty = PhotoSearchFound(summary: PhotoSearchSummary(photos: 0, videos: 0, first: nil, last: nil, limited: false), identifiers: [])
}

/// The only code that reads the photo library (ADR-565). It counts photos and videos by when they
/// were taken and draws small pictures for the user's screen. It never writes to the library, never
/// reads where a photo was taken, and nothing it reads leaves the iPhone except the counts and
/// times in `VoiceToolReply.photosFound`. The guard script keeps PhotoKit in this folder.
@MainActor
enum PhotoLibrarySearch {
    /// How many photos the result card shows.
    static let shownOnScreen = 60

    /// Limited access (the user picked some photos) counts as allowed; the reply says it is partial.
    static func access() -> DeviceConnections.Access {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    static func request() async -> DeviceConnections.Access {
        guard access() == .notDetermined else { return access() }
        _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return access()
    }

    static func find(_ request: PhotoSearchRequest, now: Date) -> PhotoSearchFound {
        guard access() == .granted else { return .empty }
        let range = request.range(now: now, calendar: .current)
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", range.start as NSDate, range.end as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let assets = PHAsset.fetchAssets(with: options)
        var photos = 0, videos = 0
        var first: Date?, last: Date?
        var identifiers: [String] = []
        for index in 0..<assets.count {
            let asset = assets.object(at: index)
            switch asset.mediaType {
            case .image: photos += 1
            case .video: videos += 1
            default: continue
            }
            if first == nil { first = asset.creationDate }
            last = asset.creationDate ?? last
            identifiers.append(asset.localIdentifier)
        }
        let limited = PHPhotoLibrary.authorizationStatus(for: .readWrite) == .limited
        return PhotoSearchFound(
            summary: PhotoSearchSummary(photos: photos, videos: videos, first: first, last: last, limited: limited),
            identifiers: Array(identifiers.suffix(shownOnScreen).reversed()))
    }

    /// A small square picture for the result card, from the copy on this iPhone (nothing is
    /// downloaded from iCloud). Nil when there is none.
    static func thumbnail(_ identifier: String, side: CGFloat) async -> UIImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject else { return nil }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        let once = ResumeOnce()
        let box: ThumbnailBox = await withCheckedContinuation { continuation in
            once.set(continuation)
            // Photos calls back on its own queue: @Sendable so the closure isn't main-actor code.
            PHImageManager.default().requestImage(
                for: asset, targetSize: CGSize(width: side, height: side), contentMode: .aspectFill, options: options
            ) { @Sendable image, _ in
                once.resume(ThumbnailBox(image))
            }
        }
        return box.image
    }
}

/// Carries a picture across Photos' callback queue.
private final class ThumbnailBox: @unchecked Sendable {
    let image: UIImage?
    init(_ image: UIImage?) { self.image = image }
}

/// Resumes the continuation once, however often Photos calls back.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<ThumbnailBox, Never>?

    func set(_ continuation: CheckedContinuation<ThumbnailBox, Never>) {
        lock.withLock { self.continuation = continuation }
    }

    func resume(_ box: ThumbnailBox) {
        let pending: CheckedContinuation<ThumbnailBox, Never>? = lock.withLock {
            defer { continuation = nil }
            return continuation
        }
        pending?.resume(returning: box)
    }
}
