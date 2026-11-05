import DoddyCore
import SwiftUI
import UIKit

/// Success is backed by a committed repository record, never a simulated timer.
/// `sharedText` comes from the "Save to Doddy" shortcut: it fills the editor and is still only
/// saved when the user taps Save (ADR-179).
struct CaptureView: View {
    @Environment(MemoryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var isShared: Bool
    @State private var category: MemoryCategory = .other
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var saved: MemoryRecord?
    @State private var confirmDiscard = false
    /// A saved note with the same words (ADR-184). Shown instead of saving until the user picks.
    @State private var duplicate: MemoryRecord?
    @State private var allowDuplicate = false
    /// A picked photo, prepared and read (ADR-218). Linked to the note only after the note saves.
    @State private var photo: PhotoTextReader.Prepared?
    @State private var photoProblem: String?
    /// A recording made here (ADR-230). Linked to the note only after the note saves.
    @State private var memo: VoiceMemoDraft?
    @State private var memoProblem: String?
    @FocusState private var editorFocused: Bool
    /// Unfinished notes (ADR-362): this screen's draft, kept on the iPhone until Save or Discard.
    private let drafts = UnfinishedNoteStore.shared
    private let sharedText: String?
    @State private var draftID = UUID()
    @State private var draftStartedAt = Date()
    @State private var started = false
    /// The unfinished note this screen opened with.
    @State private var resumed: UnfinishedNote?
    /// Another unfinished note, kept, when this screen opened with shortcut text.
    @State private var otherWaiting: UnfinishedNote?
    /// A photo taken with Doddy's camera in a conversation (ADR-569), read when the screen opens.
    private let takenPhoto: Data?
    @State private var takenPhotoProblem: String?
    @State private var takenPhotoRead = false

    init(sharedText: String? = nil, takenPhoto: Data? = nil) {
        self.sharedText = sharedText
        self.takenPhoto = takenPhoto
        _text = State(initialValue: sharedText ?? "")
        _isShared = State(initialValue: sharedText != nil)
    }

    private var hasDraft: Bool { !text.allSatisfy(\.isWhitespace) || photo != nil || memo != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let saved {
                        if store.record(id: saved.id) != nil || store.loadError != nil {
                            SaveReceiptView(record: store.record(id: saved.id) ?? saved, onDone: { dismiss() }, onAnother: startAnother)
                            if let photoProblem {
                                ProblemView(message: photoProblem).accessibilityIdentifier("capture.photoNotKept")
                            }
                            if let memoProblem {
                                ProblemView(message: memoProblem).accessibilityIdentifier("capture.memoNotKept")
                            }
                            if let loadError = store.loadError {
                                ProblemView(message: "The note was saved, but the list couldn't refresh. \(loadError)")
                            }
                        } else {
                            Text("This note has been removed.")
                            Button("Save another detail", action: startAnother).buttonStyle(PrimaryButtonStyle())
                            Button("Done") { dismiss() }
                        }
                    } else {
                        JourneyHeading(eyebrow: "Before it slips away", title: "One less thing\nto remember.",
                                       subtitle: "A thought, a recommendation, where you put the spare keys.")
                        if let resumed {
                            ResumedDraftNotice(note: resumed, onStartNew: startNewInstead)
                        }
                        if let otherWaiting {
                            Label(String(format: NSLocalizedString("You also have an unfinished note from %@. It's kept; it opens the next time you start a new note.", comment: ""),
                                         otherWaiting.updatedAt.formatted(date: .abbreviated, time: .shortened)),
                                  systemImage: "doc.badge.clock")
                                .font(.footnote).foregroundStyle(Theme.secondaryText)
                                .accessibilityIdentifier("capture.otherDraft")
                        }
                        if let problem = drafts.problem {
                            ProblemView(message: problem).accessibilityIdentifier("capture.draftProblem")
                        }
                        if isShared {
                            Label("Shared into Doddy from a shortcut. Check it, change it if you like, then tap Save. Nothing is saved until you do.", systemImage: "square.and.arrow.down")
                                .font(.footnote).foregroundStyle(Theme.secondaryText)
                                .accessibilityIdentifier("capture.sharedNotice")
                        }
                        Text("What would you like to keep?").font(.subheadline)
                        MemoryTextEditor(text: $text, label: "The detail").focused($editorFocused)
                            .accessibilityIdentifier("capture.text")
                            .disabled(isSaving)
                        // Apple's own paste control: iOS asks nothing, and only a tap reads the clipboard.
                        // The copied text goes in exactly as copied, after what is already there (ADR-189).
                        PasteButton(payloadType: String.self) { items in
                            text = DraftText.pasting(items, into: text)
                        }
                        .labelStyle(.titleAndIcon)
                        .buttonBorderShape(.capsule)
                        .tint(Theme.ink)
                        .frame(minHeight: 44)
                        .disabled(isSaving)
                        .accessibilityIdentifier("capture.paste")
                        if let takenPhotoProblem {
                            ProblemView(message: takenPhotoProblem).accessibilityIdentifier("capture.takenPhotoProblem")
                        }
                        CapturePhotoPicker(text: $text, prepared: $photo, isDisabled: isSaving)
                        CaptureVoiceMemo(text: $text, draft: $memo, isDisabled: isSaving)
                        Text("No folders. Your words, exactly.").font(.caption).foregroundStyle(Theme.secondaryText)
                        DisclosureGroup("Optional note type") {
                            Picker("Type", selection: $category) {
                                ForEach(MemoryCategory.noteCategories, id: \.self) { Text($0.displayName).tag($0) }
                            }.pickerStyle(.menu)
                        }.font(.subheadline).disabled(isSaving)
                        Label("Only this detail is saved on this iPhone. You can edit or delete it later.", systemImage: "lock")
                            .font(.footnote).foregroundStyle(Theme.secondaryText)
                        if let errorMessage {
                            ProblemView(message: errorMessage, showsDoddy: true).accessibilityIdentifier("capture.error")
                        }
                        if let duplicate {
                            DuplicateNoticeView(record: duplicate) {
                                allowDuplicate = true
                                beginSave()
                            }
                        }
                        Button(action: beginSave) {
                            HStack { Text(isSaving ? "Saving…" : "Save this detail"); Spacer(); Image(systemName: "arrow.right") }
                        }
                        .buttonStyle(PrimaryButtonStyle()).disabled(isSaving || !store.isStorageAvailable)
                        .accessibilityIdentifier("capture.save")
                    }
                }.padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.canvas).foregroundStyle(Theme.ink)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { DoddyWordmark() }
                ToolbarItem(placement: .cancellationAction) {
                    Button(saved == nil ? "Cancel" : "Done", action: close)
                        .disabled(isSaving)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { editorFocused = false }.accessibilityIdentifier("capture.keyboardDone")
                }
            }
            .navigationDestination(for: UUID.self) { MemoryDetailView(memoryID: $0) }
            .onChange(of: text) {
                duplicate = nil
                allowDuplicate = false
                // Once the shared text is cleared, whatever is typed or pasted next is the user's
                // own, so it is saved as a typed note, not as "shared".
                if isShared && text.allSatisfy(\.isWhitespace) { isShared = false }
                keepDraft()
            }
            .onChange(of: category) { keepDraft() }
            .onChange(of: photo != nil) { keepDraft() }
            .onChange(of: memo != nil) { keepDraft() }
            .confirmationDialog("Discard this note?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) {
                    memo?.discardFile()
                    drafts.remove(id: draftID)
                    dismiss()
                }
                // Only offered while the copy on the iPhone is confirmed (ADR-362).
                if drafts.problem == nil && !text.allSatisfy(\.isWhitespace) {
                    Button("Keep it for later") {
                        drafts.flush()
                        memo?.discardFile()
                        dismiss()
                    }
                }
                Button("Keep editing", role: .cancel) {}
            } message: {
                if drafts.problem == nil && !text.allSatisfy(\.isWhitespace) {
                    Text("It hasn't been saved. Keep it for later and it opens the next time you start a new note; a photo or recording isn't kept with it.")
                } else {
                    Text("It hasn't been saved.")
                }
            }
        }
        .interactiveDismissDisabled((hasDraft && saved == nil) || isSaving)
        .onAppear {
            ShortcutRouter.shared.captureScreenAppeared()
            startDraft()
        }
        .task { await readTakenPhoto() }
        .onDisappear {
            drafts.flush()
            ShortcutRouter.shared.captureScreenDisappeared()
        }
    }

    /// The camera's photo (ADR-569), prepared and read like a picked one. Linked to the note only
    /// when the user saves it, as for any photo.
    private func readTakenPhoto() async {
        guard let takenPhoto, !takenPhotoRead else { return }
        takenPhotoRead = true
        do {
            let result = try await PhotoTextReader.prepare(takenPhoto)
            photo = result
            text = RecognizedText.adding(result.text.text, to: text)
            UIAccessibility.post(notification: .announcement, argument: PickedPhotoView.notice(for: result))
        } catch {
            takenPhotoProblem = NSLocalizedString("The photo couldn't be read, so it wasn't added. Try taking it again.", comment: "")
        }
    }

    /// Once per screen: opens with the newest unfinished note, or keeps shortcut text as one.
    private func startDraft() {
        guard !started else { return }
        started = true
        // A photo from the camera starts a new note; an unfinished one stays for later.
        if takenPhoto != nil {
            keepDraft()
            return
        }
        switch UnfinishedNoteResume.start(sharedText: sharedText, book: drafts.book) {
        case .fresh:
            keepDraft()
        case .resumed(let note):
            draftID = note.id
            draftStartedAt = note.startedAt
            resumed = note
            text = note.text
            category = note.category
            isShared = note.isSharedText
        case .sharedWithOtherWaiting(let note):
            otherWaiting = note
            keepDraft()
        }
    }

    /// The screen's words, kept on the iPhone until Save or Discard.
    private func keepDraft() {
        guard started, saved == nil else { return }
        drafts.keep(UnfinishedNote(id: draftID, text: text, category: category, isSharedText: isShared,
                                   hadPhoto: photo != nil, hadRecording: memo != nil,
                                   startedAt: draftStartedAt, updatedAt: Date()))
    }

    /// "Start a new note instead": the unfinished note stays kept for later.
    private func startNewInstead() {
        drafts.flush()
        resumed = nil
        draftID = UUID()
        draftStartedAt = Date()
        text = ""
        category = .other
        isShared = false
    }

    private func close() {
        guard !isSaving else { return }
        if saved == nil && hasDraft { confirmDiscard = true } else { dismiss() }
    }

    private func startAnother() {
        draftID = UUID(); draftStartedAt = Date(); resumed = nil; otherWaiting = nil
        text = ""; category = .other; saved = nil; errorMessage = nil; isShared = false
        duplicate = nil; allowDuplicate = false; photo = nil; photoProblem = nil
        memo?.discardFile(); memo = nil; memoProblem = nil
    }

    private func beginSave() {
        guard !isSaving else { return }
        if !allowDuplicate, let match = DuplicateNote.existing(for: text, in: store.memories) {
            duplicate = match
            UIAccessibility.post(notification: .announcement, argument: "You saved this already. View it, or save it again anyway.")
            editorFocused = false
            return
        }
        duplicate = nil
        editorFocused = false
        isSaving = true
        Task { await save() }
    }

    private func save() async {
        errorMessage = nil
        defer { isSaving = false }
        let record: MemoryRecord
        do { record = try await store.save(text: text, category: category, source: isShared ? .sharedContent : .explicitText) }
        catch { errorMessage = UserFacingError.message(for: error); return }
        // The note is saved either way; a photo that can't be kept is said plainly, never hidden.
        if let photo {
            do { try await store.attachPhoto(jpeg: photo.jpeg, width: photo.width, height: photo.height, to: record.id) }
            catch { photoProblem = NSLocalizedString("The note was saved, but its photo couldn't be kept on this iPhone. The note's words are all there.", comment: "") }
        }
        if let memo {
            do { try await store.attachRecording(from: memo.recording.url, durationMilliseconds: memo.recording.durationMilliseconds, to: record.id) }
            catch { memoProblem = NSLocalizedString("The note was saved, but its recording couldn't be kept on this iPhone. The note's words are all there.", comment: "") }
            memo.discardFile()
            self.memo = nil
        }
        // A note now: the draft goes (ADR-362).
        drafts.remove(id: draftID)
        saved = record
    }
}

/// "Here is your unfinished note" at the top of a capture screen that opened with one (ADR-362).
private struct ResumedDraftNotice: View {
    let note: UnfinishedNote
    let onStartNew: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(String(format: NSLocalizedString("Here is your unfinished note from %@. It isn't saved until you tap Save.", comment: ""),
                         note.updatedAt.formatted(date: .abbreviated, time: .shortened)),
                  systemImage: "doc.badge.clock")
                .font(.footnote)
            if note.hadPhoto || note.hadRecording {
                Text("Its photo or recording wasn't kept with it. Add it again if you need it.")
                    .font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            Button("Start a new note instead", action: onStartNew)
                .frame(minHeight: 44)
                .accessibilityIdentifier("capture.startNewInstead")
        }
        .padding(14)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("capture.resumedDraft")
    }
}

/// "You saved this already" with the date, a link to that note and "Save anyway".
private struct DuplicateNoticeView: View {
    let record: MemoryRecord
    let onSaveAnyway: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("You saved this already, \(DateText.full(record.capturedAt)).", systemImage: "doc.on.doc")
                .font(.subheadline.weight(.medium))
            Text(record.currentText).font(.footnote).foregroundStyle(Theme.secondaryText).lineLimit(3)
            NavigationLink(value: record.id) {
                HStack { Text("View the saved note"); Spacer(); Image(systemName: "arrow.up.right") }
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityIdentifier("capture.viewDuplicate")
            Button("Save it again anyway", action: onSaveAnyway)
                .frame(minHeight: 44)
                .accessibilityIdentifier("capture.saveDuplicate")
        }
        .padding(14)
        .background(Theme.quietSurface, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("capture.duplicate")
    }
}

private struct SaveReceiptView: View {
    let record: MemoryRecord
    let onDone: () -> Void
    let onAnother: () -> Void

    @Environment(NoteReminderStore.self) private var noteReminders
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(PreferenceKey.hideCharacterArt) private var hideCharacterArt = false
    @State private var showReminder = false
    /// The pop has played (ADR-313); then the "kept" fist pump stays.
    @State private var popped = false

    var body: some View {
        VStack(spacing: 20) {
            // Shown only once the save is confirmed, so the pop never celebrates a failed save.
            if !hideCharacterArt {
                Group {
                    if popped || reduceMotion {
                        UploadedCharacterView(assetName: "UploadedDoddy_Kept", height: 170)
                    } else {
                        DoddyMotionView(motion: .pop, height: 145)
                            .padding(.bottom, 10)
                            .frame(height: 170, alignment: .bottom)
                    }
                }
                .transition(.opacity)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: popped)
                .task {
                    guard !reduceMotion, !popped else { return }
                    try? await Task.sleep(for: .seconds(DoddyMotion.pop.duration + 0.3))
                    if !Task.isCancelled { popped = true }
                }
            }
            Text("Got it.").font(.largeTitle.weight(.medium)).accessibilityAddTraits(.isHeader)
            Label("Saved on this iPhone", systemImage: "checkmark.circle")
                .font(.subheadline).foregroundStyle(Theme.confirmed).accessibilityIdentifier("capture.saved")
            MemoryPaperCard(record: record)
            // Remind me while saving (M4a): the same sheet and receipts as on the note itself.
            if let receipt = noteReminders.receipts[record.id] {
                NoteReminderReceiptView(receipt: receipt) { showReminder = true }
            } else if noteReminders.isAvailable {
                Button { showReminder = true } label: {
                    HStack { Text("Remind me about this"); Spacer(); Image(systemName: "bell") }
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityIdentifier("capture.remind")
            }
            NavigationLink(value: record.id) {
                HStack { Text("View the note"); Spacer(); Image(systemName: "arrow.up.right") }
            }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("capture.viewNote")
            Button("Save another detail", action: onAnother).frame(minHeight: 44)
            Button("Done", action: onDone).buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("capture.done")
        }.frame(maxWidth: .infinity)
        .sheet(isPresented: $showReminder) { NoteReminderSheet(memoryID: record.id) }
    }
}

#Preview("Local capture") {
    CaptureView().environment(MemoryStore(environment: .unavailable))
        .environment(NoteReminderStore(coordinator: nil))
}
