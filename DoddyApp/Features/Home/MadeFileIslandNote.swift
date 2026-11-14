import DoddyCore
import SwiftUI

/// A file Doddy has started making, as a small note that drops out of the island at the top of Home (owner,
/// 13 Nov 2026: "mały pop-up z Dynamic Island … z pokazaniem, co ogólnie on będzie robił"). It replaces the pop-up
/// card for a file still being made: there is nothing to open yet, so it has no buttons and asks for nothing. It goes
/// away by itself after `MadeFileStart.noteSeconds`; a tap puts it away sooner. The file arrives in Messages when the
/// server says it is ready. Black like the island, in light and dark. Decision 2026-11-13-file-being-made-island-note.
struct MadeFileIslandNote: View {
    let document: RunDocument
    /// False in a private conversation: the file opens from the transcript, not from Messages.
    var keptInMessages = true
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: Self.symbol(document.kind))
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.orangeCue)
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Self.title(document.kind)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                let name = MadeFileStart.shownName(document)
                if !name.isEmpty {
                    Text(verbatim: name)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(2)
                }
                Group {
                    if keptInMessages {
                        Text("It lands in Messages in a minute or two.")
                    } else {
                        Text("Open it from the transcript when it's ready.")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.65))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ProgressView()
                .tint(.white)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 360)
        .background(.black, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onTapGesture(perform: onDismiss)
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: Text("Close"), onDismiss)
        .accessibilityIdentifier("home.fileBeingMade")
        .padding(.horizontal, 16)
        .padding(.top, 2)
    }

    /// What Doddy is making, by the file's kind (`RunDocument.kind`).
    static func title(_ kind: String) -> Text {
        switch kind {
        case "deck": Text("Making your deck")
        case "doc": Text("Making your document")
        case "spreadsheet": Text("Making your spreadsheet")
        case "pdf": Text("Making your PDF")
        default: Text("Making your text")
        }
    }

    static func symbol(_ kind: String) -> String {
        switch kind {
        case "deck": "play.rectangle"
        case "spreadsheet": "tablecells"
        case "pdf": "doc.richtext"
        case "text": "text.alignleft"
        default: "doc.text"
        }
    }
}
