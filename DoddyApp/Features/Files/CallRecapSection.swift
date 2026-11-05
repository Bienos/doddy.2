import DoddyCore
import SwiftUI

/// Files › Calls: the recap of each call Doddy made for the person (owner, 2026-11-05). A recap is a
/// plain text file made on this iPhone from the brief the person approved and the answer card kept
/// here (`CallRecap`); nothing is fetched. It opens in Quick Look, whose Share button sends it,
/// for instance in Messages. The whole log, with the transcript, cost and deletion receipts, stays in
/// Settings › Phone calls › Calls for you.
///
/// The file goes to this app's temporary folder with complete file protection, and the folder is
/// emptied each time the sheet loads, like the files Doddy made (`MadeDocumentsModel`).
///
/// NOT COMPILED here (no Xcode in the session that wrote it); the text and file name rules are
/// `CallRecap` in DoddyCore.
struct CallRecapSection: View {
    @Environment(\.appEnvironment) private var environment
    @Binding var preview: URL?
    @State private var records: [StoredCallCase] = []
    @State private var problem: String?

    private static var folder: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("CallRecaps", isDirectory: true)
    }

    var body: some View {
        Group {
            if !records.isEmpty || problem != nil {
                Section {
                    ForEach(records) { record in
                        Button { open(record) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: record.brief.calleeName)
                                    .lineLimit(1)
                                if let summary = record.result?.summary {
                                    Text(verbatim: summary)
                                        .font(.footnote)
                                        .foregroundStyle(Theme.secondaryText)
                                        .lineLimit(2)
                                }
                            }
                            .frame(minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("files.callRecap")
                    }
                    if let problem {
                        Label(problem, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.error)
                    }
                } header: {
                    Text("Calls")
                } footer: {
                    Text("What Doddy found out on the calls he made for you. The whole log is in Settings › Phone calls.")
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        try? FileManager.default.removeItem(at: Self.folder)
        do {
            // Newest first; only calls with an answer card have a recap.
            records = try await environment.callCaseRepository.list()
                .filter { $0.result != nil }
                .sorted { $0.updatedAt > $1.updatedAt }
            problem = nil
        } catch {
            // A failed read is shown, never as "no calls".
            problem = NSLocalizedString("The calls kept on this iPhone couldn't be read.", comment: "Files: the call list failed")
        }
    }

    private func open(_ record: StoredCallCase) {
        guard let card = record.result,
              let text = CallRecap.text(for: record, labels: Self.labels, outcomeText: CallCaseText.outcome(card.outcome),
                                        whenText: record.createdAt.formatted(date: .abbreviated, time: .shortened)) else { return }
        do {
            let directory = Self.folder.appendingPathComponent(record.id.uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(CallRecap.fileName(for: record))
            try Data(text.utf8).write(to: url, options: [.atomic, .completeFileProtection])
            problem = nil
            preview = url
        } catch {
            problem = NSLocalizedString("The file couldn't be saved on this iPhone.", comment: "")
        }
    }

    private static var labels: CallRecap.Labels {
        CallRecap.Labels(
            title: NSLocalizedString("Call recap", comment: "Title line of a call recap file"),
            to: NSLocalizedString("To", comment: ""),
            goal: NSLocalizedString("Goal", comment: ""),
            question: NSLocalizedString("Question", comment: ""),
            outcome: NSLocalizedString("Outcome", comment: ""),
            when: NSLocalizedString("When", comment: ""),
            duration: NSLocalizedString("Duration", comment: ""),
            answer: NSLocalizedString("Answer", comment: "Heading of the answer in a call recap"),
            nextStep: NSLocalizedString("Next step", comment: ""),
            checkThis: NSLocalizedString("Worth a look", comment: "How many things in a call recap the person should check"))
    }
}
