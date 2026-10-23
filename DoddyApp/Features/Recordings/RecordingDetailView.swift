import DoddyCore
import SwiftUI

// One recording (ADR-579): its audio, its words, a search over them, and the parts that answer a
// question. There is NO written summary and no written answer here, because no provider has been
// approved (docs/implementation/CAPTURE_AUDIT.md section 5); the page says so. What it does show is
// real: the words that were recognised on this iPhone, with their times, and where in them a
// question's words appear. Nothing here is saved as memory unless the user taps Save on a note.

@MainActor
@Observable
final class RecordingDetailModel {
    let id: UUID
    let player = RecordingPlayer()

    private(set) var recording: Recording?
    private(set) var parts: [RecordingPart] = []
    private(set) var segments: [TranscriptSegment] = []
    private(set) var quality: TranscriptQuality?
    private(set) var searchHits: [RecordingSearchHit] = []
    private(set) var searched = false
    private(set) var excerpts: [Excerpt] = []
    private(set) var asked = false
    private(set) var links: [RecordingMemoryLink] = []
    private(set) var problem: String?
    var query = ""
    var question = ""

    private let pageSize = 500
    private var repository: (any RecordingRepository)? { AppEnvironment.shared.recordingRepository }
    private var files: RecordingFiles { AppEnvironment.shared.recordingFiles }

    init(id: UUID) { self.id = id }

    var isWorking: Bool {
        guard let recording, recording.phase == .saved || recording.phase == .recovered else { return false }
        return recording.transcription == .running || recording.transcription == .notStarted
    }

    /// Reads the recording, its parts and all of its words (a page at a time, so no single read is large).
    func load() async {
        guard let repository else { return }
        do {
            recording = try await repository.recording(id: id)
            parts = try await repository.parts(recordingID: id)
            player.load(parts: parts, recordingID: id, files: files)
            try await loadWords()
            links = try await repository.memoryLinks(forRecording: id)
            problem = nil
        } catch {
            problem = NSLocalizedString("Doddy couldn't read this recording. Nothing was changed.", comment: "")
        }
    }

    private func loadWords() async throws {
        guard let repository else { return }
        var all: [TranscriptSegment] = []
        while true {
            let page = try await repository.segments(recordingID: id, offset: all.count, limit: pageSize)
            all += page
            if page.count < pageSize { break }
        }
        segments = all
        if let recording, recording.transcription == .done || recording.transcription == .noSpeech {
            quality = TranscriptQuality.assess(all, durationMilliseconds: recording.durationMilliseconds)
        } else {
            quality = nil
        }
    }

    func refresh() async {
        guard let repository, let fresh = try? await repository.recording(id: id) else { return }
        let changed = fresh.transcription != recording?.transcription
        recording = fresh
        if changed { try? await loadWords() }
    }

    func rename(_ title: String) async {
        guard let repository else { return }
        recording = (try? await repository.rename(id: id, title: title)) ?? recording
    }

    func setKind(_ kind: RecordingKind) async {
        guard let repository else { return }
        recording = (try? await repository.setKind(id: id, kind: kind)) ?? recording
    }

    func correct(_ index: Int, to text: String) async {
        guard let repository, segments.indices.contains(index),
              let edited = try? await repository.editSegment(recordingID: id, index: index, text: text) else { return }
        segments[index] = edited
    }

    func search() async {
        guard let repository else { return }
        searchHits = (try? await repository.search(query, in: id, limit: 50)) ?? []
        searched = true
    }

    func clearSearch() {
        query = ""
        searchHits = []
        searched = false
    }

    /// Where a question's words appear, with the lines around them. No model reads these, and nothing
    /// leaves the iPhone: this is the part of "Ask Doddy" that is real today.
    func ask() async {
        guard let repository else { return }
        let hits = (try? await repository.search(question, in: id, limit: 8)) ?? []
        excerpts = ExcerptBuilder.excerpts(hits: hits.map(\.segmentIndex), segments: segments)
        asked = true
    }

    /// Writes the transcript out as a Markdown file for the share sheet.
    func exportFile() -> URL? {
        guard let recording else { return nil }
        let language = NotificationLanguage.current
        let title = recording.displayTitle(language)
        let text = TranscriptFormat.markdown(
            title: title, startedAt: recording.startedAt, durationMilliseconds: recording.durationMilliseconds,
            languageCode: recording.languageCode, segments: segments, gaps: recording.gaps, language)
        let safe = title.filter { !"/\\:*?\"<>|".contains($0) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe.isEmpty ? "Recording" : safe).md")
        do {
            try Data(text.utf8).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return url
        } catch {
            problem = NSLocalizedString("Doddy couldn't prepare the transcript to share.", comment: "")
            return nil
        }
    }

    /// Saves one thing as a note, then links it to this recording. "Saved" only once the note is read back.
    func remember(text: String, kind: CaptureMemory.Kind, atMilliseconds: Int, store: MemoryStore) async -> String? {
        let record: MemoryRecord
        do {
            record = try await store.save(text: text, category: CaptureMemory.category(for: kind))
        } catch {
            return NSLocalizedString("Doddy couldn't save that note. Nothing was saved.", comment: "")
        }
        // The note is saved either way, and its last line says where it came from.
        try? await repository?.linkMemory(
            memoryID: record.id, recordingID: id, atMilliseconds: atMilliseconds,
            recordingTitle: recording?.displayTitle(.current) ?? "", linkedAt: .now)
        links = (try? await repository?.memoryLinks(forRecording: id)) ?? links
        return nil
    }

    func writeOutAgain(languageCode: String) async {
        await RecordingProcessor.shared.retry(id, languageCode: languageCode)
        await refresh()
    }

    func delete() async -> Bool {
        player.stop()
        guard let repository, RecordingCoordinator.shared.session?.id != id else { return false }
        do {
            _ = try await repository.delete(id: id)
            files.remove(recordingID: id)
            return true
        } catch {
            problem = NSLocalizedString("Doddy couldn't delete that recording. Nothing was changed.", comment: "")
            return false
        }
    }
}

struct RecordingDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MemoryStore.self) private var store
    @State private var model: RecordingDetailModel
    @State private var renaming = false
    @State private var titleDraft = ""
    @State private var correcting: TranscriptSegment?
    @State private var correctionDraft = ""
    @State private var remembering: RememberDraft?
    @State private var exportURL: ExportFile?
    @State private var confirmDelete = false
    @State private var scrollTarget: Int?
    private var language: NotificationLanguage { .current }

    init(id: UUID) { _model = State(initialValue: RecordingDetailModel(id: id)) }

    var body: some View {
        Group {
            if let recording = model.recording {
                content(recording)
            } else if model.problem != nil {
                Text(verbatim: model.problem ?? "").foregroundStyle(Theme.error).padding()
            } else {
                ProgressView()
            }
        }
        .navigationTitle(Text(verbatim: model.recording?.displayTitle(language) ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        // While the words are being written out, the page follows; it starts again for "Write out again".
        .task(id: model.isWorking) {
            while !Task.isCancelled, model.isWorking {
                try? await Task.sleep(for: .seconds(2))
                await model.refresh()
            }
        }
        .onDisappear { model.player.stop() }
    }

    @ViewBuilder
    private func content(_ recording: Recording) -> some View {
        ScrollViewReader { proxy in
            List {
                headerSection(recording)
                if model.player.hasAudio { playerSection }
                summarySection(recording)
                askSection
                transcriptSection(recording)
                actionsSection(recording)
            }
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                withAnimation { proxy.scrollTo(target, anchor: .center) }
                scrollTarget = nil
            }
        }
        .alert("Name this recording", isPresented: $renaming) {
            TextField("Name", text: $titleDraft)
            Button("Save") { Task { await model.rename(titleDraft) } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Correct the words", isPresented: Binding(get: { correcting != nil }, set: { if !$0 { correcting = nil } })) {
            TextField("Words", text: $correctionDraft)
            Button("Save") {
                if let line = correcting { Task { await model.correct(line.index, to: correctionDraft) } }
                correcting = nil
            }
            Button("Cancel", role: .cancel) { correcting = nil }
        } message: {
            Text("What Doddy first wrote stays kept. This only changes what you see and search.")
        }
        .sheet(item: $remembering) { draft in
            RememberSheet(draft: draft) { text in
                await model.remember(text: text, kind: draft.kind, atMilliseconds: draft.atMilliseconds, store: store)
            }
        }
        .sheet(item: $exportURL) { file in FileShareSheet(url: file.url) }
        .confirmationDialog("Delete this recording?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { if await model.delete() { dismiss() } } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The audio and its words are removed from this iPhone. Notes you saved from it stay.")
        }
    }

    // MARK: Sections

    private func headerSection(_ recording: Recording) -> some View {
        Section {
            Button { titleDraft = recording.title; renaming = true } label: {
                Text(verbatim: recording.displayTitle(language)).font(.title3.weight(.semibold)).foregroundStyle(Theme.ink)
            }
            .accessibilityHint("Renames the recording")
            .accessibilityIdentifier("recording.title")
            Text(verbatim: "\(DateText.full(recording.startedAt)) · \(RecordingClock.string(milliseconds: recording.durationMilliseconds)) · \(CaptureLanguage.displayName(recording.languageCode))")
                .font(.footnote).foregroundStyle(Theme.secondaryText)
            Menu {
                ForEach(RecordingKind.allCases, id: \.self) { kind in
                    Button { Task { await model.setKind(kind) } } label: {
                        if kind == recording.kind { Label(kind.name(language), systemImage: "checkmark") } else { Text(verbatim: kind.name(language)) }
                    }
                }
            } label: {
                Label(recording.kind.name(language), systemImage: "tag")
            }
            .accessibilityIdentifier("recording.kind")
            Text(verbatim: RecordingStatusText.line(recording, isCapturingNow: false, language))
                .font(.footnote).foregroundStyle(recording.phase == .lost ? Theme.error : Theme.secondaryText)
            if let note = recording.endReason?.note(language) {
                Text(verbatim: note).font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            ForEach(Array(recording.gaps.filter(\.isNoticeable).enumerated()), id: \.offset) { _, gap in
                Label(gap.note(language), systemImage: "exclamationmark.circle")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            if let problem = model.problem {
                Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.error)
            }
        }
    }

    private var playerSection: some View {
        Section {
            HStack(spacing: 12) {
                Button { model.player.toggle() } label: {
                    Image(systemName: model.player.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.largeTitle)
                }
                .accessibilityLabel(model.player.isPlaying ? "Pause" : "Play")
                .accessibilityIdentifier("recording.play")
                VStack(alignment: .leading) {
                    Slider(
                        value: Binding(
                            get: { Double(model.player.positionMilliseconds) },
                            set: { model.player.seek(toMilliseconds: Int($0)) }),
                        in: 0...Double(max(1, model.player.totalMilliseconds)))
                    HStack {
                        Text(verbatim: RecordingClock.string(milliseconds: model.player.positionMilliseconds))
                        Spacer()
                        Text(verbatim: RecordingClock.string(milliseconds: model.player.totalMilliseconds))
                    }
                    .font(.caption.monospacedDigit()).foregroundStyle(Theme.secondaryText)
                }
            }
            if let problem = model.player.problem {
                Text(verbatim: problem).font(.footnote).foregroundStyle(Theme.error)
            }
        }
    }

    private func summarySection(_ recording: Recording) -> some View {
        Section("Summary") {
            if let message = model.quality?.message(language) {
                Label(message, systemImage: "waveform.badge.exclamationmark").foregroundStyle(Theme.secondaryText)
            }
            Text("No summary yet. Doddy can't write summaries of recordings yet. The words below were written out on this iPhone, and you can search them.")
                .foregroundStyle(Theme.secondaryText)
                .accessibilityIdentifier("recording.summary.none")
        }
    }

    private var askSection: some View {
        Section("Ask about this recording") {
            HStack {
                TextField("What do you want to find?", text: $model.question)
                    .submitLabel(.search)
                    .onSubmit { Task { await model.ask() } }
                    .accessibilityIdentifier("recording.ask.field")
                Button("Find") { Task { await model.ask() } }
                    .disabled(model.question.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("recording.ask.button")
            }
            if model.asked {
                if model.excerpts.isEmpty {
                    Text("Those words aren't in this recording.").foregroundStyle(Theme.secondaryText)
                } else {
                    Text("Doddy can't write answers about recordings yet. These are the parts that mention it:")
                        .font(.footnote).foregroundStyle(Theme.secondaryText)
                    ForEach(Array(model.excerpts.enumerated()), id: \.offset) { _, excerpt in
                        Button {
                            model.player.seek(toMilliseconds: excerpt.startMilliseconds)
                            scrollTarget = excerpt.firstSegment
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: excerpt.text).foregroundStyle(Theme.ink)
                                Text(verbatim: RecordingClock.string(milliseconds: excerpt.startMilliseconds))
                                    .font(.caption.monospacedDigit()).foregroundStyle(Theme.accentText)
                            }
                        }
                    }
                }
            }
        }
    }

    private func transcriptSection(_ recording: Recording) -> some View {
        Section("Transcript") {
            HStack {
                TextField("Search the words", text: $model.query)
                    .submitLabel(.search)
                    .onSubmit { Task { await model.search() } }
                    .accessibilityIdentifier("recording.search.field")
                if model.searched {
                    Button("Clear") { model.clearSearch() }
                }
            }
            if model.searched {
                if model.searchHits.isEmpty {
                    Text("No match.").foregroundStyle(Theme.secondaryText)
                }
                ForEach(model.searchHits, id: \.segmentIndex) { hit in
                    Button {
                        model.player.seek(toMilliseconds: hit.startMilliseconds)
                        scrollTarget = hit.segmentIndex
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(verbatim: RecordingClock.string(milliseconds: hit.startMilliseconds))
                                .font(.caption.monospacedDigit()).foregroundStyle(Theme.accentText)
                            Text(verbatim: hit.text).foregroundStyle(Theme.ink)
                        }
                    }
                }
            }
            if model.segments.isEmpty {
                Text(verbatim: emptyTranscriptText(recording)).foregroundStyle(Theme.secondaryText)
            }
            // The rows are drawn lazily by the List; the words were read in pages of 500.
            ForEach(model.segments) { line in
                transcriptLine(line)
                    .id(line.index)
            }
        }
    }

    private func transcriptLine(_ line: TranscriptSegment) -> some View {
        let current = model.player.isPlaying
            && model.player.positionMilliseconds >= line.startMilliseconds && model.player.positionMilliseconds < line.endMilliseconds
        return Button {
            model.player.seek(toMilliseconds: line.startMilliseconds)
            if !model.player.isPlaying { model.player.play(from: line.startMilliseconds) }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: RecordingClock.string(milliseconds: line.startMilliseconds))
                    .font(.caption.monospacedDigit()).foregroundStyle(Theme.accentText)
                Text(verbatim: line.text)
                    .foregroundStyle(Theme.ink)
                    .fontWeight(current ? .semibold : .regular)
            }
        }
        .contextMenu {
            Button { correctionDraft = line.text; correcting = line } label: { Label("Correct the words", systemImage: "pencil") }
            Button {
                let recording = model.recording
                remembering = RememberDraft(
                    text: CaptureMemory.draft(item: line.text, recordingTitle: recording?.displayTitle(language) ?? "",
                                              atMilliseconds: line.startMilliseconds, language),
                    kind: .excerpt, atMilliseconds: line.startMilliseconds)
            } label: { Label("Remember this", systemImage: "bookmark") }
        }
        .accessibilityElement(children: .combine)
    }

    private func actionsSection(_ recording: Recording) -> some View {
        Section {
            if recording.phase == .saved || recording.phase == .recovered {
                Menu {
                    ForEach(languageChoices(for: recording), id: \.self) { code in
                        Button { Task { await model.writeOutAgain(languageCode: code) } } label: {
                            Text(verbatim: "\(NSLocalizedString("Write out again in", comment: "")) \(CaptureLanguage.displayName(code))")
                        }
                    }
                } label: {
                    Label("Write the words out again", systemImage: "arrow.clockwise")
                }
                .accessibilityIdentifier("recording.rewrite")
            }
            if !model.segments.isEmpty {
                Button {
                    if let url = model.exportFile() { exportURL = ExportFile(url: url) }
                } label: {
                    Label("Export the transcript", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("recording.export")
            }
            Button(role: .destructive) { confirmDelete = true } label: { Label("Delete this recording", systemImage: "trash") }
                .accessibilityIdentifier("recording.delete")
        } footer: {
            Text("Audio export isn't available yet.")
        }
    }

    // MARK: -

    private func emptyTranscriptText(_ recording: Recording) -> String {
        switch recording.transcription {
        case .running, .notStarted: NSLocalizedString("The words are being written out on this iPhone. This can take a while for a long recording.", comment: "")
        case .noSpeech: NSLocalizedString("No speech was found in this recording.", comment: "")
        case .unsupportedLanguage: NSLocalizedString("This iPhone can't write this language out on the device, so nothing was written out and nothing was sent. Try another language below.", comment: "")
        case .notAllowed: NSLocalizedString("Speech recognition is off for Doddy. Turn it on in the iPhone Settings.", comment: "")
        case .failed: NSLocalizedString("The words couldn't be written out. The audio is kept. Try again below.", comment: "")
        case .done: NSLocalizedString("There are no words to show.", comment: "")
        }
    }

    /// This recording's own language first, then Polish and English: one language per pass.
    private func languageChoices(for recording: Recording) -> [String] {
        var seen = Set<String>()
        return [recording.languageCode, "pl-PL", "en-GB"].filter { seen.insert($0.lowercased().prefix(2).description).inserted }
    }
}

private struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct RememberDraft: Identifiable {
    let id = UUID()
    var text: String
    let kind: CaptureMemory.Kind
    let atMilliseconds: Int
}

/// "Remember this": the note as it will be saved, for the user to read and change first. Nothing is
/// saved until Save, and "Saved" appears only after the note is read back.
struct RememberSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var saving = false
    @State private var problem: String?
    let draft: RememberDraft
    let save: (String) async -> String?

    init(draft: RememberDraft, save: @escaping (String) async -> String?) {
        self.draft = draft
        self.save = save
        _text = State(initialValue: draft.text)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text).frame(minHeight: 140)
                        .accessibilityIdentifier("recording.remember.text")
                } footer: {
                    Text("This becomes a note Doddy can remember in later conversations. Its last line says which recording it came from. You can edit or delete it like any note.")
                }
                if let problem {
                    Section { Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.error) }
                }
            }
            .navigationTitle("Remember this")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saving = true
                        Task {
                            let result = await save(text)
                            saving = false
                            if let result { problem = result } else { dismiss() }
                        }
                    }
                    .disabled(saving || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("recording.remember.save")
                }
            }
        }
    }
}
