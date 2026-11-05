import DoddyCore
import ImageIO
import UIKit
import Vision

/// Reads a product's barcode from a photo on this iPhone (Shopping list+, ADR-631). The photo comes
/// from iOS's own camera screen (`CameraCapture`), is never saved and is dropped after reading.
/// Only EAN-13 (UPC-A is read as EAN-13 with a leading 0) and EAN-8; a code counts only when
/// `ProductBarcode` accepts its check digit. Nothing leaves the phone here.
enum PhotoBarcodeReader {
    enum ReadError: Error {
        case tooLarge, unreadable
    }

    /// The first valid product barcode in the photo, or nil when there is none.
    static func read(_ data: Data) async throws -> ProductBarcode? {
        try await Task.detached(priority: .userInitiated) {
            guard data.count <= PhotoLimits.maxSourceBytes else { throw ReadError.tooLarge }
            guard let image = UIImage(data: data), let cgImage = image.cgImage else { throw ReadError.unreadable }
            let request = VNDetectBarcodesRequest()
            request.symbologies = [.ean13, .ean8]
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: CGImagePropertyOrientation(image.imageOrientation))
            try handler.perform([request])
            let payloads = (request.results ?? []).compactMap(\.payloadStringValue)
            return payloads.lazy.compactMap { ProductBarcode($0) }.first
        }.value
    }
}

private extension CGImagePropertyOrientation {
    /// The camera's photo keeps its pixels as the sensor saw them; Vision needs to know which way is up.
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
