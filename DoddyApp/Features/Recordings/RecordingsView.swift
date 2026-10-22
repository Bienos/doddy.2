import DoddyCore
import SwiftUI

// Recordings (ADR-579): the list, the Record button, and the one-time notice. Everything shown is
// read from the store on this iPhone. A recording still being written out is never shown as ready,
// and the preview under a title is the start of the transcript, not a summary.

struct RecordingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model = RecordingsModel()
    @State private var opened: UUID?
    @State private var pendingDelete: UUID?
    @State private var showNotice = false
    @State private var confirmDeleteAll = false
    private let coordinator = RecordingCoordinator.shared
    private var language: NotificationLanguage { .current }

    var body: some View {
        NavigationStack {
            List {
                recorderSection
                if let problem = model.problem {
                    Section { Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.error) }
                }
                Section {
                    Picker("Show", selection: $model.category) {
                        ForEach(RecordingCategory.allCases, id: \.self) { category in
                            Text(verbatim: category.name(language)).tag(category)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("recordings.category")
                }
                if model.items.isEmpty, model.hasLoaded {
                    Section {
                        Text("No recordings yet. Tap Record to capture a meeting or a conversation. Doddy writes out the words on this iPhone, and you can search them.")
                            .foregroundStyle(Theme.secondaryText)
                            .accessibilityIdentifier("recordings.empty")
                    }
                } else {
                    Section {
                        ForEach(model.items, id: \.recording.id) { item in
                            Button { opened = item.recording.id } label: {
                                RecordingRow(item: item, capturing: coordinator.session?.id == item.recording.id, language: language)
                            }
                            .swipeActions {
                                Button(role: .destructive) { pendingDelete = item.recording.id } label: { Label("Delete", systemImage: "trash") }
                            }
                            .accessibilityIdentifier("recordings.row")
                        }
                        if model.hasMore {
                            Button("Show more") { Task { await model.loadMore() } }
                        }
                    }
                    Section {
                        Button("Delete all recordings", role: .destructive) { confirmDeleteAll = true }
                            .accessibilityIdentifier("recordings.deleteAll")
                    }
                }
            }
            .navigationTitle("Recordings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .navigationDestination(item: $opened) { id in RecordingDetailView(id: id) }
            .task {
                if let id = ShortcutRouter.shared.takeRecordingToOpen() { opened = id }
                // The list follows the work: a new recording, words being written out.
                while !Task.isCancelled {
                    await model.reload()
                    try? await Task.sleep(for: .seconds(3))
                }
            }
            .sheet(isPresented: $showNotice) {
                RecordingNoticeView { accepted in
                    showNotice = false
                    guard accepted else { return }
                    RecordingCoordinator.acceptNotice()
                    Task { await startRecording() }
                }
            }
            .confirmationDialog("Delete all recordings?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                Button("Delete all", role: .destructive) { Task { _ = await model.deleteAll() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Every recording on this iPhone is removed, with its audio and its words. A recording in progress is stopped first. Notes you saved from them stay. This can't be undone.")
            }
            .confirmationDialog("Delete this recording?", isPresented: Binding(
                get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let id = pendingDelete { Task { _ = await model.delete(id) } }
                    pendingDelete = nil
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("The audio and its words are removed from this iPhone. Notes you saved from it stay.")
            }
        }
    }

    // MARK: Recorder

    @ViewBuilder private var recorderSection: some View {
        Section {
            switch coordinator.machine.state {
            case .idle, .finished, .failed:
                Button { Task { await startRecording() } } label: {
                    Label("Record", systemImage: "record.circle.fill").font(.headline).foregroundStyle(Theme.orangeCue)
                }
                .accessibilityIdentifier("recordings.record")
                .accessibilityHint("Starts recording. Doddy shows it all the time it records.")
                if let notice = coordinator.notice {
                    Text(verbatim: notice).font(.footnote).foregroundStyle(Theme.secondaryText)
                        .accessibilityIdentifier("recordings.notice")
                }
            case .preparing:
                HStack { ProgressView(); Text("Starting…") }
            case .recording, .paused, .interrupted:
                activeControls
            case .finalizing:
                HStack { ProgressView(); Text("Saving…") }
            }
        } footer: {
            Text("Doddy records only when you start it. The audio and its words stay on this iPhone.")
        }
    }

    @ViewBuilder private var activeControls: some View {
        if let session = coordinator.session,
           let snapshot = CaptureActivitySnapshot.make(from: coordinator.machine.state, now: .now) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: CapturePresentation.symbol(snapshot))
                        .foregroundStyle(CapturePresentation.isRecordingCue(snapshot) ? Theme.orangeCue : Theme.secondaryText)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(verbatim: RecordingClock.string(milliseconds: session.capturedMilliseconds(at: context.date)))
                            .font(.title2.monospacedDigit())
                    }
                    Text(verbatim: CapturePresentation.status(snapshot, language)).font(.headline)
                }
                if let detail = CapturePresentation.detail(snapshot, language) {
                    Text(verbatim: detail).font(.footnote).foregroundStyle(Theme.secondaryText)
                }
                if let notice = coordinator.notice {
                    Text(verbatim: notice).font(.footnote).foregroundStyle(Theme.secondaryText)
                }
                HStack(spacing: 12) {
                    if CapturePresentation.canPause(snapshot) {
                        Button { Task { await coordinator.pause() } } label: {
                            Label(CapturePresentation.label(.pause, language), systemImage: "pause.fill")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("recordings.pause")
                    }
                    if CapturePresentation.canResume(snapshot) {
                        Button { Task { await coordinator.resume() } } label: {
                            Label(CapturePresentation.label(.resume, language), systemImage: "play.fill")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("recordings.resume")
                    }
                    if CapturePresentation.canStop(snapshot) {
                        Button { Task { _ = await coordinator.stop() } } label: {
                            Label(CapturePresentation.label(.stop, language), systemImage: "stop.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("recordings.stop")
                    }
                }
            }
        }
    }

    private func startRecording() async {
        guard RecordingCoordinator.noticeAccepted else {
            showNotice = true
            return
        }
        _ = await coordinator.start(origin: .app)
        await model.reload()
    }
}

private struct RecordingRow: View {
    let item: RecordingListItem
    let capturing: Bool
    let language: NotificationLanguage

    var body: some View {
        let recording = item.recording
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: recording.displayTitle(language)).font(.headline).foregroundStyle(Theme.ink)
            Text(verbatim: "\(DateText.full(recording.startedAt)) · \(RecordingClock.string(milliseconds: recording.durationMilliseconds)) · \(recording.kind.name(language))")
                .font(.footnote).foregroundStyle(Theme.secondaryText)
            Text(verbatim: RecordingStatusText.line(recording, isCapturingNow: capturing, language))
                .font(.footnote)
                .foregroundStyle(recording.phase == .lost ? Theme.error : Theme.secondaryText)
            if let preview = item.preview {
                Text(verbatim: preview).font(.subheadline).foregroundStyle(Theme.secondaryText).lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The notice before the first recording (`CaptureNotice`). Required before any start, from here or
/// from Siri, the Action Button or a control.
struct RecordingNoticeView: View {
    let onDecision: (Bool) -> Void
    private var language: NotificationLanguage { .current }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(CaptureNotice.points(language), id: \.self) { point in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(Theme.secondaryText)
                            Text(verbatim: point).foregroundStyle(Theme.ink)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(Text(verbatim: CaptureNotice.title(language)))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Button { onDecision(true) } label: {
                        Text(verbatim: CaptureNotice.accept(language)).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("recordings.notice.accept")
                    Button { onDecision(false) } label: { Text(verbatim: CaptureNotice.decline(language)) }
                        .accessibilityIdentifier("recordings.notice.decline")
                }
                .padding()
                .background(Theme.canvas)
            }
        }
    }
}
