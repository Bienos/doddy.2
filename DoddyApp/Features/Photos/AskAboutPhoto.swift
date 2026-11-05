import DoddyCore
import PhotosUI
import SwiftUI

/// Home's + menu (owner, 5 Nov 2026): "Take a photo" and "Choose a photo" both end in Messages with the
/// photo above the box, so Doddy can say what it is or use it as context. This is only the way in; the
/// photo is the same one `MessagePhotoButton` makes: made smaller here, its location and camera details
/// left out, kept in memory until the person taps Send, then sent with that one question and kept nowhere
/// (`docs/implementation/MESSAGES_PHOTOS.md`). Apple's picker runs outside Doddy (no photo-library
/// permission); iOS asks for the camera the first time. It lives in this folder because the photo
/// picker may only be used here (`scripts/check_forbidden_capabilities.sh`).
struct AskAboutPhotoSources: ViewModifier {
    @Binding var showCamera: Bool
    @Binding var showLibrary: Bool
    let onPhoto: (AssistantImage) -> Void
    @State private var item: PhotosPickerItem?
    @State private var unreadable = false

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: $showLibrary, selection: $item, matching: .images, photoLibrary: .shared())
            .onChange(of: item) { _, picked in
                guard let picked else { return }
                Task {
                    let data = try? await picked.loadTransferable(type: Data.self)
                    item = nil
                    await prepare(data)
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraCapture(
                    onPhoto: { data in
                        showCamera = false
                        Task { await prepare(data) }
                    },
                    onCancel: { showCamera = false })
                    .ignoresSafeArea()
            }
            .alert("This photo couldn't be read. Try another one.", isPresented: $unreadable) {
                Button("OK", role: .cancel) {}
            }
    }

    private func prepare(_ data: Data?) async {
        guard let data,
              let image = await Task.detached(priority: .userInitiated, operation: { MessagePhotoShrinker.jpeg(from: data) }).value
        else {
            unreadable = true
            return
        }
        onPhoto(image)
    }
}

extension View {
    /// The camera and the photo picker behind Home's + menu; `onPhoto` gets the photo ready to send.
    func askAboutPhotoSources(showCamera: Binding<Bool>, showLibrary: Binding<Bool>,
                              onPhoto: @escaping (AssistantImage) -> Void) -> some View {
        modifier(AskAboutPhotoSources(showCamera: showCamera, showLibrary: showLibrary, onPhoto: onPhoto))
    }
}
