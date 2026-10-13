import DoddyCore
import UIKit
import Vision

/// Prepares a picked photo for a photo note (ADR-218): scaled down to `PhotoLimits.maxPixels`,
/// stored as JPEG, and its text read on this iPhone with Vision. Nothing leaves the phone.
/// Language correction is off, so codes and passwords come back as printed, not "corrected".
enum PhotoTextReader {
    // `DoddyCore.` in full: the iOS 26 SDK's Vision has its own `RecognizedText`.
    struct Prepared: Sendable {
        let jpeg: Data
        let width: Int
        let height: Int
        let text: DoddyCore.RecognizedText.Result
    }

    enum ReadError: Error {
        case tooLarge, unreadable
    }

    static func prepare(_ data: Data) async throws -> Prepared {
        try await Task.detached(priority: .userInitiated) {
            guard data.count <= PhotoLimits.maxSourceBytes else { throw ReadError.tooLarge }
            guard let image = UIImage(data: data) else { throw ReadError.unreadable }
            let pixels = (Int(image.size.width * image.scale), Int(image.size.height * image.scale))
            let target = DoddyCore.RecognizedText.scaledSize(width: pixels.0, height: pixels.1)
            let size = CGSize(width: target.width, height: target.height)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let scaled = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
            guard let jpeg = scaled.jpegData(compressionQuality: 0.8), let cgImage = scaled.cgImage else {
                throw ReadError.unreadable
            }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.automaticallyDetectsLanguage = true
            try VNImageRequestHandler(cgImage: cgImage).perform([request])
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            return Prepared(jpeg: jpeg, width: target.width, height: target.height, text: DoddyCore.RecognizedText.join(lines))
        }.value
    }
}
