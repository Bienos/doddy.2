import DoddyCore
import PhotosUI
import SwiftUI
import UIKit

/// The photo button in Messages (owner, 28 Oct 2026: "Do all"). Apple's photo picker runs outside Doddy, so no photo
/// library permission is asked and Doddy sees only the one photo picked. It is made smaller here and kept in memory
/// until the person taps Send; then it goes with that one question to Doddy's server and on to Anthropic, and is not
/// saved on this iPhone or the server. It lives in this folder because the photo picker may only be used here.
struct MessagePhotoButton: View {
    @Binding var photo: AssistantImage?
    let isDisabled: Bool
    @State private var item: PhotosPickerItem?
    @State private var isPreparing = false
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            PhotosPicker(selection: $item, matching: .images, photoLibrary: .shared()) {
                Image(systemName: "photo")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 34, height: 34)
                    .background(Theme.quietSurface, in: Circle())
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .disabled(isDisabled || isPreparing)
            .accessibilityLabel("Add a photo")
            .accessibilityIdentifier("messages.addPhoto")
            if let problem {
                Text(problem)
                    .font(.caption2)
                    .foregroundStyle(Theme.error)
                    .fixedSize(horizontal: false, vertical: true)
                    .onTapGesture { self.problem = nil }
                    .accessibilityIdentifier("messages.photoProblem")
            }
        }
        .onChange(of: item) {
            guard let item else { return }
            Task { await prepare(item) }
        }
    }

    private func prepare(_ picked: PhotosPickerItem) async {
        isPreparing = true
        problem = nil
        defer {
            isPreparing = false
            item = nil
        }
        guard let data = try? await picked.loadTransferable(type: Data.self),
              let image = await Task.detached(priority: .userInitiated, operation: { MessagePhotoShrinker.jpeg(from: data) }).value
        else {
            problem = NSLocalizedString("This photo couldn't be read. Try another one.", comment: "")
            return
        }
        photo = image
    }
}

/// The picked photo above the box, with a way to take it off before sending.
struct MessagePhotoChip: View {
    let photo: AssistantImage
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if let image = UIImage(data: photo.jpeg) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)
            }
            Text("Photo goes with your next message")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
            Spacer(minLength: 0)
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Theme.secondaryText)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Remove the photo")
            .accessibilityIdentifier("messages.removePhoto")
        }
        .padding(.horizontal, 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("messages.photoChip")
    }
}

/// Makes a picked photo small enough to send: at most 1,600 points on its long side, JPEG, and under
/// `AssistantImage.maxBytes`, trying lower quality and then a smaller size. Nil when it can't be read or made small enough.
enum MessagePhotoShrinker {
    static func jpeg(from data: Data) -> AssistantImage? {
        guard let source = UIImage(data: data) else { return nil }
        for side in [1_600.0, 1_200.0, 900.0] {
            let resized = resize(source, longSide: side)
            for quality in [0.75, 0.6, 0.45] {
                if let jpeg = resized.jpegData(compressionQuality: quality), let image = AssistantImage(jpeg: jpeg) {
                    return image
                }
            }
        }
        return nil
    }

    private static func resize(_ image: UIImage, longSide: CGFloat) -> UIImage {
        let size = image.size
        let scale = min(1, longSide / max(size.width, size.height, 1))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        // Drawing it again also leaves out the photo's location and camera details (EXIF): only the picture is sent.
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
