import DoddyCore
import PhotosUI
import SwiftUI
import UIKit

/// "Add a photo" while writing a note (ADR-218). Apple's photo picker runs outside Doddy, so no
/// photo library permission is asked and Doddy sees only the one photo the user picks. Its text
/// is read on this iPhone and added to the editor for the user to check before saving.
struct CapturePhotoPicker: View {
    @Binding var text: String
    @Binding var prepared: PhotoTextReader.Prepared?
    let isDisabled: Bool
    @State private var item: PhotosPickerItem?
    @State private var isReading = false
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let prepared {
                PickedPhotoView(prepared: prepared) {
                    self.prepared = nil
                    item = nil
                }
            } else {
                PhotosPicker(selection: $item, matching: .images, photoLibrary: .shared()) {
                    HStack {
                        Text(isReading ? "Reading the photo…" : "Add a photo")
                        Spacer()
                        Image(systemName: "photo")
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(isDisabled || isReading)
                .accessibilityIdentifier("capture.addPhoto")
                Text("A receipt, a label, where you parked. Doddy reads its text on this iPhone; the photo is never sent anywhere.")
                    .font(.caption).foregroundStyle(Theme.secondaryText)
            }
            if let problem { ProblemView(message: problem).accessibilityIdentifier("capture.photoProblem") }
        }
        .onChange(of: item) {
            guard let item else { return }
            Task { await read(item) }
        }
    }

    private func read(_ item: PhotosPickerItem) async {
        isReading = true
        problem = nil
        defer { isReading = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw PhotoTextReader.ReadError.unreadable
            }
            let result = try await PhotoTextReader.prepare(data)
            prepared = result
            text = RecognizedText.adding(result.text.text, to: text)
            UIAccessibility.post(notification: .announcement, argument: PickedPhotoView.notice(for: result))
        } catch PhotoTextReader.ReadError.tooLarge {
            problem = NSLocalizedString("That photo is too large to add. Nothing was added.", comment: "")
            self.item = nil
        } catch {
            problem = NSLocalizedString("That photo couldn't be read, so nothing was added. Try another one.", comment: "")
            self.item = nil
        }
    }
}

/// The picked photo with what happened to its text, before the note is saved.
struct PickedPhotoView: View {
    let prepared: PhotoTextReader.Prepared
    let onRemove: () -> Void

    static func notice(for prepared: PhotoTextReader.Prepared) -> String {
        if prepared.text.text.isEmpty {
            return NSLocalizedString("No text was found in this photo. Add a few words so you can find the note later.", comment: "")
        }
        let check = NSLocalizedString("The photo's text was added below. Reading photos makes mistakes, so check it before saving.", comment: "")
        return prepared.text.wasCut ? check + " " + NSLocalizedString("It was long, so only the first part was added.", comment: "") : check
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let image = UIImage(data: prepared.jpeg) {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("The photo you picked")
            }
            Label(Self.notice(for: prepared), systemImage: "text.viewfinder")
                .font(.footnote).foregroundStyle(Theme.secondaryText)
                .accessibilityIdentifier("capture.photoNotice")
            Button("Don't add this photo", action: onRemove)
                .frame(minHeight: 44)
                .accessibilityIdentifier("capture.removePhoto")
            Text("The text already added stays in the note until you change it.")
                .font(.caption).foregroundStyle(Theme.secondaryText)
        }
        .padding(14)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// A saved note's photo, with Remove photo. The note's words stay when the photo goes.
struct NotePhotoSection: View {
    @Environment(MemoryStore.self) private var store
    let memoryID: UUID
    @State private var image: UIImage?
    @State private var isMissing = false
    @State private var confirmRemove = false
    @State private var isRemoving = false
    @State private var problem: String?

    var body: some View {
        if let photo = store.photo(for: memoryID) {
            VStack(alignment: .leading, spacing: 10) {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 360)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel("The note's photo")
                        .accessibilityIdentifier("detail.photo")
                } else if isMissing {
                    Label("This note's photo file is missing on this iPhone.", systemImage: "photo.badge.exclamationmark")
                        .font(.footnote).foregroundStyle(Theme.secondaryText)
                }
                Text("Kept only on this iPhone, never sent anywhere. Not in exports.")
                    .font(.caption).foregroundStyle(Theme.secondaryText)
                if let problem { ProblemView(message: problem) }
                Button(role: .destructive) { confirmRemove = true } label: {
                    Text(isRemoving ? "Removing…" : "Remove photo").frame(minHeight: 44)
                }
                .disabled(isRemoving)
                .accessibilityIdentifier("detail.removePhoto")
            }
            .task(id: photo.fileName) { await load(photo) }
            .confirmationDialog("Remove this photo?", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove photo", role: .destructive) { Task { await remove() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The photo is deleted from this iPhone. The note's words stay.")
            }
        }
    }

    private func load(_ photo: MemoryPhoto) async {
        image = await store.photoData(photo).flatMap(UIImage.init(data:))
        isMissing = image == nil
    }

    private func remove() async {
        isRemoving = true
        defer { isRemoving = false }
        do {
            try await store.removePhoto(from: memoryID)
            problem = nil
        } catch {
            problem = UserFacingError.message(for: error)
        }
    }
}
