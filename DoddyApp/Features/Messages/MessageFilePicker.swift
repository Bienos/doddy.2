import DoddyCore
import SwiftUI
import UniformTypeIdentifiers

/// "Attach a file" (owner, 7 Nov 2026: "Do all"): iOS's own file picker, so Doddy sees only the one file picked. A PDF
/// or a plain-text file (text, CSV, JSON) is read here and checked by `AssistantFile`; it is kept in memory until the
/// person taps Send, then goes with that one question to Doddy's server and on to Anthropic, and is not saved on this
/// iPhone or the server. Only its name stays in the conversation.
struct AttachFileImporter: ViewModifier {
    @Binding var isPresented: Bool
    let onFile: (AssistantFile) -> Void
    @State private var problem: String?

    static let types: [UTType] = [.pdf, .plainText, .commaSeparatedText, .json]

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $isPresented, allowedContentTypes: Self.types) { result in
                guard case .success(let url) = result else { return }
                switch Self.read(url) {
                case .success(let file): onFile(file)
                case .failure(let reason): problem = reason.message
                }
            }
            .alert(Text(verbatim: problem ?? ""), isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
                Button("OK", role: .cancel) {}
            }
    }

    enum Problem: Error {
        case tooLarge, unreadable

        var message: String {
            switch self {
            case .tooLarge: NSLocalizedString("This file is too large to send. Files up to 3 MB work.", comment: "")
            case .unreadable: NSLocalizedString("This file couldn't be read. Doddy can read PDFs and plain text files.", comment: "")
            }
        }
    }

    /// Reads the picked file within its security scope, refusing it before reading when it is too large.
    static func read(_ url: URL) -> Result<AssistantFile, Problem> {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
        if let size = values?.fileSize, size > AssistantFile.maxBytes { return .failure(.tooLarge) }
        guard let data = try? Data(contentsOf: url) else { return .failure(.unreadable) }
        guard data.count <= AssistantFile.maxBytes else { return .failure(.tooLarge) }
        let type = values?.contentType ?? UTType(filenameExtension: url.pathExtension)
        let kind: AssistantFile.Kind = type?.conforms(to: .pdf) == true ? .pdf : .text
        guard let file = AssistantFile(name: url.lastPathComponent, kind: kind, data: data) else { return .failure(.unreadable) }
        return .success(file)
    }
}

extension View {
    /// The file picker behind "Attach a file"; `onFile` gets a file ready to send.
    func attachFileImporter(isPresented: Binding<Bool>, onFile: @escaping (AssistantFile) -> Void) -> some View {
        modifier(AttachFileImporter(isPresented: isPresented, onFile: onFile))
    }
}

/// The picked file above the box, with a way to take it off before sending.
struct MessageFileChip: View {
    let file: AssistantFile
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: file.kind == .pdf ? "doc.richtext" : "doc.text")
                .font(.title3)
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 44, height: 44)
                .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: file.name)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("File goes with your next message")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 0)
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Theme.secondaryText)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Remove the file")
            .accessibilityIdentifier("messages.removeFile")
        }
        .padding(.horizontal, 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("messages.fileChip")
    }
}
