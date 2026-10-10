import DoddyCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Settings → Import notes (ADR-231).
struct NoteImportSettingsSection: View {
    @Environment(MemoryStore.self) private var store
    @State private var showImport = false

    var body: some View {
        Section("Import notes") {
            Button { showImport = true } label: { Label("Import from Google Keep or text files", systemImage: "tray.and.arrow.down") }
                .disabled(!store.isStorageAvailable)
                .accessibilityIdentifier("settings.importNotes")
            Text("You see every note before anything is saved. Files are read on this iPhone only.")
                .font(.footnote).foregroundStyle(Theme.secondaryText)
        }
        .sheet(isPresented: $showImport) { NoteImportView() }
    }
}

/// Pick files, review every note exactly as it will be saved, then import the ticked ones.
struct NoteImportView: View {
    @Environment(MemoryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var choosing = false
    @State private var files: [(name: String, data: Data?)] = []
    @State private var splitParagraphs = false
    @State private var candidates: [NoteImport.Candidate] = []
    @State private var ticked: Set<UUID> = []
    @State private var isImporting = false
    @State private var receipt: String?
    @State private var problem: String?

    private static let markdown = UTType(filenameExtension: "md", conformingTo: .plainText) ?? .plainText

    private var chosen: [NoteImport.Candidate] { candidates.filter { ticked.contains($0.id) && $0.canImport } }
    private var chosenNotes: Int { chosen.filter { if case .note = $0.content { true } else { false } }.count }
    private var chosenLists: Int { chosen.count - chosenNotes }

    var body: some View {
        NavigationStack {
            Form {
                if let receipt {
                    Section {
                        Label(receipt, systemImage: "checkmark.circle").foregroundStyle(Theme.confirmed)
                            .accessibilityIdentifier("import.receipt")
                        if let problem { Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.error) }
                        Button("Done") { dismiss() }
                    }
                } else {
                    intro
                    if !candidates.isEmpty { review }
                }
            }
            .navigationTitle("Import notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(receipt == nil ? "Cancel" : "Done") { dismiss() }.disabled(isImporting)
                }
            }
            .fileImporter(
                isPresented: $choosing, allowedContentTypes: [.json, .plainText, Self.markdown, .text],
                allowsMultipleSelection: true
            ) { result in read(result) }
            .onChange(of: splitParagraphs) { rebuild() }
        }
        .interactiveDismissDisabled(isImporting)
    }

    private var intro: some View {
        Section {
            Text("From Google Keep: in Google Takeout, export Keep. In the Files app, tap the .zip to unpack it, open the Keep folder and pick the .json files. You can also pick .txt and .md files.")
                .font(.subheadline)
            Button { choosing = true } label: { Label(candidates.isEmpty ? "Choose files" : "Choose other files", systemImage: "folder") }
                .disabled(isImporting)
                .accessibilityIdentifier("import.choose")
            if files.contains(where: { NoteImport.isTextFile($0.name) }) {
                Toggle("One note per paragraph in text files", isOn: $splitParagraphs)
            }
            Text("Words are kept exactly as in the file. Keep checklists become lists. Photos, recordings and labels from Keep aren't imported. Imported notes are marked “Imported from a file”.")
                .font(.footnote).foregroundStyle(Theme.secondaryText)
            if let problem { Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.error) }
        }
    }

    @ViewBuilder
    private var review: some View {
        let importable = candidates.filter(\.canImport)
        let refused = candidates.filter { !$0.canImport }
        if !importable.isEmpty {
            Section {
                ForEach(importable) { candidate in
                    Toggle(isOn: Binding(
                        get: { ticked.contains(candidate.id) },
                        set: { if $0 { ticked.insert(candidate.id) } else { ticked.remove(candidate.id) } })
                    ) {
                        CandidateRow(candidate: candidate)
                    }
                }
                Button {
                    Task { await runImport() }
                } label: {
                    Text(isImporting ? "Importing…" : "Import \(NoteImport.summary(notes: chosenNotes, lists: chosenLists))")
                }
                .disabled(chosen.isEmpty || isImporting)
                .accessibilityIdentifier("import.run")
            } header: {
                Text("Check before importing")
            } footer: {
                Text("Notes already in Doddy start unticked.")
            }
        }
        if !refused.isEmpty {
            Section("Can't be imported") {
                ForEach(refused) { candidate in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(candidate.fileName).font(.subheadline)
                        Text(Self.reason(candidate.problem)).font(.footnote).foregroundStyle(Theme.secondaryText)
                    }
                }
            }
        }
    }

    private func read(_ result: Result<[URL], any Error>) {
        problem = nil
        guard case .success(let urls) = result else {
            problem = "Those files couldn't be opened."
            return
        }
        guard urls.count <= NoteImport.maxFiles else {
            problem = "Pick at most \(NoteImport.maxFiles) files at a time."
            return
        }
        files = urls.map { url in
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            // A file too large isn't read at all; it is listed with the reason.
            let data = size > NoteImport.maxFileBytes ? Data(count: NoteImport.maxFileBytes + 1) : try? Data(contentsOf: url)
            return (url.lastPathComponent, data)
        }
        rebuild()
    }

    private func rebuild() {
        let read = files.flatMap { file -> [NoteImport.Candidate] in
            guard let data = file.data else {
                return [NoteImport.Candidate(fileName: file.name, origin: .textFile, content: nil, createdAt: nil, problem: .unreadable)]
            }
            return NoteImport.read(fileName: file.name, data: data, splitParagraphs: splitParagraphs)
        }
        candidates = NoteImport.checked(read, notes: store.memories, listNames: store.lists.map(\.name))
        ticked = Set(candidates.filter(\.startsTicked).map(\.id))
    }

    private func runImport() async {
        isImporting = true
        defer { isImporting = false }
        let selection = chosen
        let records = selection.compactMap { NoteImport.record(for: $0, now: Date()) }
        var notes = 0, lists = 0, notKept = 0
        if !records.isEmpty {
            do { notes = try await store.restore(records).count } catch { notKept += records.count }
        }
        for candidate in selection {
            guard case .list(let part)? = candidate.content else { continue }
            do {
                try await store.importList(part)
                lists += 1
            } catch {
                notKept += 1
            }
        }
        receipt = notes + lists == 0
            ? "Nothing was imported."
            : "Imported \(NoteImport.summary(notes: notes, lists: lists)), each checked in Doddy's storage."
        problem = notKept == 0 ? nil : "\(notKept == 1 ? "1 item" : "\(notKept) items") couldn't be imported. Nothing was half-saved; try those again."
        UIAccessibility.post(notification: .announcement, argument: receipt ?? "")
    }

    static func reason(_ problem: NoteImport.Problem?) -> String {
        switch problem {
        case .unreadable, .none: "This file couldn't be read."
        case .notAKeepNote: "This isn't a Google Keep note."
        case .notText: "This file isn't plain text Doddy can read."
        case .fileTooLarge: "This file is too large."
        case .empty: "There are no words in it."
        case .inTrash: "It was in Keep's trash."
        case .tooLong(let length): "It's \(length) characters; a note can be up to \(MemoryLimits.maxTextLength). Nothing is cut."
        case .listNameTooLong: "The list's name is longer than \(ListLimits.nameLength) characters."
        case .tooManyItems: "The list has more than \(ListLimits.itemsPerList) items, or an item longer than \(ListLimits.itemLength) characters."
        case .listNameTaken(let name): "You already have a list called “\(name)”."
        case .alreadySaved: "Already in Doddy."
        }
    }
}

/// One candidate exactly as it will be saved.
private struct CandidateRow: View {
    let candidate: NoteImport.Candidate

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch candidate.content {
            case .note(let text)?:
                Text(text).font(.body)
            case .list(let list)?:
                Label(list.name, systemImage: "checklist").font(.body.weight(.semibold))
                ForEach(Array(list.open.enumerated()), id: \.offset) { _, item in
                    Label(item, systemImage: "square").font(.subheadline)
                }
                ForEach(Array(list.ticked.enumerated()), id: \.offset) { _, item in
                    Label(item, systemImage: "checkmark.square").font(.subheadline).foregroundStyle(Theme.secondaryText)
                }
            case nil:
                EmptyView()
            }
            Text(details).font(.caption).foregroundStyle(Theme.secondaryText)
            if candidate.problem == .alreadySaved {
                Text("Already in Doddy.").font(.caption).foregroundStyle(Theme.secondaryText)
            }
            if !candidate.leftOut.isEmpty {
                Text("Not imported: \(candidate.leftOut.joined(separator: ", ")).").font(.caption).foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.vertical, 4)
    }

    private var details: String {
        let made = candidate.createdAt.map { "Made \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Date unknown"
        return "\(made) · \(candidate.fileName)"
    }
}
