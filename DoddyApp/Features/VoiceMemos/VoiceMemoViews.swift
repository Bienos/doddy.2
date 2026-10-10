import DoddyCore
import SwiftUI
import UIKit

/// A recording made while writing a note, before the note is saved (ADR-230).
struct VoiceMemoDraft: Equatable {
    let recording: VoiceMemoRecorder.Recording
    /// The language it was last written out in, if it was.
    var language: Locale?
    /// The text last added to the editor, so writing it out again can swap it.
    var transcript: String?

    /// The temporary file goes once the note is saved or the recording is dropped.
    func discardFile() { try? FileManager.default.removeItem(at: recording.url) }
}

/// "Record a voice memo" while writing a note. The words are written out on this iPhone and
/// added to the editor for the user to check; the recording is kept with the note when saved.
struct CaptureVoiceMemo: View {
    @Binding var text: String
    @Binding var draft: VoiceMemoDraft?
    let isDisabled: Bool
    @State private var recorder = VoiceMemoRecorder()
    @State private var player = VoiceMemoPlayer()
    @State private var isWritingOut = false
    @State private var notice: String?
    @State private var problem: String?
    private let languages = VoiceMemoTranscriber.languages()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let draft {
                recorded(draft)
            } else if recorder.isRecording {
                recording
            } else {
                Button {
                    Task { await recorder.start() }
                } label: {
                    HStack { Text("Record a voice memo"); Spacer(); Image(systemName: "mic") }
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(isDisabled)
                .accessibilityIdentifier("capture.recordMemo")
                Text("Up to 5 minutes. Doddy writes it out on this iPhone; the recording is never sent anywhere.")
                    .font(.caption).foregroundStyle(Theme.secondaryText)
            }
            if case .failed(let message) = recorder.state { ProblemView(message: message) }
            if let problem { ProblemView(message: problem).accessibilityIdentifier("capture.memoProblem") }
        }
        .onChange(of: recorder.stoppedByItself) { _, stopped in
            if stopped { finishRecording() }
        }
        .onDisappear {
            recorder.cancel()
            player.stop()
        }
    }

    private var recording: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("Recording… \(VoiceMemoText.duration(milliseconds: Int(recorder.elapsed * 1000))) of 5:00")
                    .monospacedDigit()
            } icon: {
                Image(systemName: "record.circle").foregroundStyle(.red)
            }
            .accessibilityIdentifier("capture.memoRecording")
            Button(action: finishRecording) {
                HStack { Text("Stop"); Spacer(); Image(systemName: "stop.fill") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("capture.stopMemo")
            Button("Don't keep it") { recorder.cancel() }
                .frame(minHeight: 44)
        }
        .padding(14)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func recorded(_ draft: VoiceMemoDraft) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            PlayRow(player: player, url: draft.recording.url, durationMilliseconds: draft.recording.durationMilliseconds)
            if isWritingOut {
                Label("Writing it out on this iPhone…", systemImage: "waveform")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            } else if let notice {
                Label(notice, systemImage: "text.bubble")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
                    .accessibilityIdentifier("capture.memoNotice")
            }
            if languages.count > 1 && !isWritingOut {
                Menu {
                    ForEach(languages, id: \.identifier) { locale in
                        Button(Self.name(of: locale)) { Task { await writeOut(in: locale) } }
                    }
                } label: {
                    Text("Write it out in another language").frame(minHeight: 44)
                }
            }
            Button("Don't keep this recording") {
                player.stop()
                draft.discardFile()
                self.draft = nil
                notice = nil
            }
            .frame(minHeight: 44)
            .accessibilityIdentifier("capture.removeMemo")
            Text("Words already added stay in the note until you change them.")
                .font(.caption).foregroundStyle(Theme.secondaryText)
        }
        .padding(14)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func finishRecording() {
        problem = nil
        guard let recording = recorder.stop() else {
            problem = NSLocalizedString("That was too short to keep. Tap Record and speak, then Stop.", comment: "")
            return
        }
        draft = VoiceMemoDraft(recording: recording, language: nil, transcript: nil)
        if let first = languages.first {
            Task { await writeOut(in: first) }
        } else {
            notice = NSLocalizedString("This iPhone can't write out speech without sending it, so Doddy didn't. Type a few words so you can find the note later.", comment: "")
        }
    }

    private func writeOut(in locale: Locale) async {
        guard let current = draft else { return }
        isWritingOut = true
        defer { isWritingOut = false }
        let outcome = await VoiceMemoTranscriber.transcribe(current.recording.url, locale: locale)
        guard draft?.recording == current.recording else { return }
        switch outcome {
        case .text(let result):
            text = VoiceMemoText.replacing(current.transcript, with: result.text, in: text)
            draft?.transcript = result.text
            draft?.language = locale
            let check = NSLocalizedString("Its words were added below, written out on this iPhone. Speech-to-text makes mistakes, so check it before saving.", comment: "")
            notice = result.wasCut ? check + " " + NSLocalizedString("It was long, so only the first part was added.", comment: "") : check
        case .noSpeech:
            notice = NSLocalizedString("No words were heard. Add a few words so you can find the note later.", comment: "")
        case .notOnDevice:
            notice = "This iPhone can't write out \(Self.name(of: locale)) without sending it, so Doddy didn't. Type a few words so you can find the note later."
        case .notAllowed:
            notice = NSLocalizedString("Speech recognition is off for Doddy, so nothing was written out. You can turn it on in the Settings app, or type a few words.", comment: "")
        case .failed:
            notice = NSLocalizedString("It couldn't be written out. The recording is still here; type a few words so you can find the note later.", comment: "")
        }
        if let notice { UIAccessibility.post(notification: .announcement, argument: notice) }
    }

    static func name(of locale: Locale) -> String {
        Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }
}

/// Play/pause with the position and length.
private struct PlayRow: View {
    let player: VoiceMemoPlayer
    let url: URL
    let durationMilliseconds: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                player.toggle(url)
            } label: {
                HStack {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    if player.isPlaying || player.position > 0 {
                        Text("\(VoiceMemoText.duration(milliseconds: Int(player.position * 1000))) / \(VoiceMemoText.duration(milliseconds: durationMilliseconds))")
                            .monospacedDigit()
                    } else {
                        Text("Voice memo, \(VoiceMemoText.duration(milliseconds: durationMilliseconds))")
                            .monospacedDigit()
                    }
                    Spacer()
                }
                .frame(minHeight: 44)
            }
            .accessibilityLabel(player.isPlaying ? "Pause the voice memo" : "Play the voice memo")
            .accessibilityIdentifier("memo.play")
            if let problem = player.problem {
                Text(problem).font(.footnote).foregroundStyle(Theme.secondaryText)
            }
        }
    }
}

/// A saved note's recording, with Remove recording. The note's words stay when it goes.
struct NoteRecordingSection: View {
    @Environment(MemoryStore.self) private var store
    let memoryID: UUID
    @State private var player = VoiceMemoPlayer()
    @State private var confirmRemove = false
    @State private var isRemoving = false
    @State private var problem: String?

    var body: some View {
        if let audio = store.recording(for: memoryID) {
            VStack(alignment: .leading, spacing: 10) {
                if let url = store.recordingURL(audio) {
                    PlayRow(player: player, url: url, durationMilliseconds: audio.durationMilliseconds)
                } else {
                    Label("This note's recording is missing on this iPhone.", systemImage: "waveform.slash")
                        .font(.footnote).foregroundStyle(Theme.secondaryText)
                }
                Text("Kept only on this iPhone, never sent anywhere. Not in exports or backup files.")
                    .font(.caption).foregroundStyle(Theme.secondaryText)
                if let problem { ProblemView(message: problem) }
                Button(role: .destructive) { confirmRemove = true } label: {
                    Text(isRemoving ? "Removing…" : "Remove recording").frame(minHeight: 44)
                }
                .disabled(isRemoving)
                .accessibilityIdentifier("detail.removeRecording")
            }
            .onDisappear { player.stop() }
            .confirmationDialog("Remove this recording?", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove recording", role: .destructive) { Task { await remove() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The recording is deleted from this iPhone. The note's words stay.")
            }
        }
    }

    private func remove() async {
        isRemoving = true
        defer { isRemoving = false }
        player.stop()
        do {
            try await store.removeRecording(from: memoryID)
            problem = nil
        } catch {
            problem = UserFacingError.message(for: error)
        }
    }
}
