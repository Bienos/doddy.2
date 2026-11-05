import SwiftUI
import UIKit

/// Doddy's camera (ADR-569): iOS's own camera screen, so iOS draws the shutter, Retake and Use
/// Photo. Doddy gets the one photo the user keeps, as JPEG data, and prepares it like a picked
/// photo (`PhotoTextReader`): scaled down, text read on this iPhone, saved only with the note the
/// user saves. Nothing is saved to the photo library. iOS asks for camera permission the first
/// time; `CameraAccess` says whether it was refused.
struct CameraCapture: UIViewControllerRepresentable {
    let onPhoto: (Data) -> Void
    let onCancel: () -> Void

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = ["public.image"]
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {
        context.coordinator.parent = self
    }

    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var parent: CameraCapture

        init(_ parent: CameraCapture) {
            self.parent = parent
        }

        nonisolated func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let data = (info[.originalImage] as? UIImage)?.jpegData(compressionQuality: 0.9)
            MainActor.assumeIsolated {
                if let data { parent.onPhoto(data) } else { parent.onCancel() }
            }
        }

        nonisolated func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            MainActor.assumeIsolated { parent.onCancel() }
        }
    }
}
