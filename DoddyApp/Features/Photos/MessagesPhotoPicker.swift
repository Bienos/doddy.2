import PhotosUI
import SwiftUI

/// The photo row of Messages' attach sheet (ADR-594). Apple's photo picker runs outside Doddy, so
/// no photo library permission is asked and Doddy sees only the one photo the user picks. The
/// photo's bytes go to `onPicked` with a file extension, to be kept in the thread on this iPhone;
/// nothing is read from the picture and nothing is sent anywhere. Photo code stays in this
/// folder (scripts/check_forbidden_capabilities.sh).
struct MessagesPhotoPicker: View {
    let onPicked: (Data, String) -> Void
    let onFailed: () -> Void
    @State private var item: PhotosPickerItem?

    var body: some View {
        PhotosPicker(selection: $item, matching: .images, photoLibrary: .shared()) {
            Label("Photos", systemImage: "photo")
        }
        .onChange(of: item) { _, picked in
            guard let picked else { return }
            Task {
                defer { item = nil }
                guard let data = try? await picked.loadTransferable(type: Data.self) else {
                    onFailed()
                    return
                }
                onPicked(data, picked.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg")
            }
        }
    }
}
