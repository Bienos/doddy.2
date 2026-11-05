import DoddyCore
import SwiftUI
import UniformTypeIdentifiers

// Encrypted backup file (ADR-222). Made on this iPhone, saved by the user where they choose
// (Files, iCloud Drive, a USB stick); restored by adding, never by overwriting. Doddy never
// stores, sends or remembers the passphrase.

extension UTType {
    static let doddyBackup = UTType(filenameExtension: BackupLimits.fileExtension, conformingTo: .data) ?? .data
}

/// The sealed bytes for the system's "Save to Files" sheet.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.doddyBackup, .data] }
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

enum BackupCopy {
    static func message(_ error: any Error) -> String {
        switch error as? BackupError {
        case .passphraseTooShort(let minimum)?:
            return "Use at least \(minimum) characters. A few words you'll remember works well."
        case .tooLarge?:
            return NSLocalizedString("This backup would be too large for one file. Make one without photos or voice memos.", comment: "")
        case .notABackup?:
            return NSLocalizedString("That file isn't a Doddy backup. Nothing was added.", comment: "")
        case .newerFormat?:
            return NSLocalizedString("That backup was made by a newer Doddy. Update Doddy, then try again. Nothing was added.", comment: "")
        case .wrongPassphraseOrDamaged?:
            return NSLocalizedString("That passphrase doesn't open this backup, or the file was changed. Nothing was added.", comment: "")
        case .weakFile?:
            return NSLocalizedString("This file isn't protected the way Doddy's backups are, so it wasn't opened. Nothing was added.", comment: "")
        case nil:
            if error is CancellationError {
                return NSLocalizedString("Opening the backup was stopped. Nothing was added.", comment: "")
            }
            if let restore = error as? MemoryRestoreError { return RestoreCopy.failure(restore) }
            return UserFacingError.message(for: error)
        }
    }
}

/// Settings › Encrypted backup.
struct BackupSettingsSection: View {
    @Environment(MemoryStore.self) private var store
    @State private var showMake = false
    @State private var showRestore = false

    var body: some View {
        Section("Encrypted backup") {
            Button { showMake = true } label: { Label("Make a backup file", systemImage: "lock.doc") }
                .disabled(!store.isStorageAvailable || (store.memories.isEmpty && store.lists.isEmpty))
                .accessibilityIdentifier("settings.makeBackup")
            Button { showRestore = true } label: { Label("Restore from a backup file", systemImage: "arrow.down.doc") }
                .disabled(!store.isStorageAvailable)
                .accessibilityIdentifier("settings.restoreBackup")
            Text("One file with your notes, lists, photos, voice memos, time reminders and About you answers, locked with a passphrase you choose. You keep it, in Files or iCloud Drive. Without the passphrase nobody can open it, and Doddy can't recover it for you.")
                .font(.footnote).foregroundStyle(Theme.secondaryText)
        }
        .sheet(isPresented: $showMake) { MakeBackupView() }
        .sheet(isPresented: $showRestore) { RestoreBackupView() }
        .coversDoddy(showMake || showRestore)
    }
}

struct MakeBackupView: View {
    @Environment(MemoryStore.self) private var store
    @Environment(NoteReminderStore.self) private var noteReminders
    @Environment(ProfileStore.self) private var profiles
    @Environment(\.dismiss) private var dismiss
    @State private var passphrase = ""
    @State private var again = ""
    @State private var includePhotos = true
    @State private var includeRecordings = true
    @State private var isWorking = false
    @State private var problem: String?
    @State private var document: BackupDocument?
    @State private var showExporter = false
    @State private var receipt: String?
    /// Photos or voice memos that are linked to a note but couldn't be read, so aren't in the file.
    @State private var leftOut: String?

    private var fileName: String {
        let day = Date.now.formatted(.iso8601.year().month().day())
        return "Doddy backup \(day).\(BackupLimits.fileExtension)"
    }

    var body: some View {
        NavigationStack {
            Form {
                if let receipt {
                    Section {
                        Label(receipt, systemImage: "checkmark.circle").foregroundStyle(Theme.confirmed)
                            .accessibilityIdentifier("backup.saved")
                        Button("Done") { dismiss() }
                    }
                } else {
                    Section {
                        SecureField("Passphrase", text: $passphrase).textContentType(.newPassword)
                        SecureField("Passphrase again", text: $again).textContentType(.newPassword)
                        Toggle("Include photos", isOn: $includePhotos)
                        Toggle("Include voice memos", isOn: $includeRecordings)
                    } footer: {
                        Text("At least \(BackupLimits.minimumPassphraseLength) characters. Write it down somewhere safe: if it's lost, this backup can't be opened by anyone, Doddy included.")
                    }
                    if let problem { Section { Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.error) } }
                    Section {
                        Button(isWorking ? "Locking the backup…" : "Make the backup file") { Task { await make() } }
                            .disabled(isWorking || passphrase.isEmpty || passphrase != again)
                            .accessibilityIdentifier("backup.make")
                        if !again.isEmpty && passphrase != again {
                            Text("The two passphrases don't match.").font(.footnote).foregroundStyle(Theme.error)
                        }
                    }
                }
            }
            .navigationTitle("Backup file")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isWorking) } }
            .fileExporter(isPresented: $showExporter, document: document, contentType: .doddyBackup, defaultFilename: fileName) { result in
                switch result {
                case .success(let url):
                    receipt = "Saved as \"\(url.lastPathComponent)\". Keep the passphrase safe; Doddy doesn't keep it."
                        + (leftOut.map { " " + $0 } ?? "")
                case .failure:
                    problem = NSLocalizedString("The backup wasn't saved. Nothing was changed on this iPhone.", comment: "")
                }
                document = nil
            }
        }
        .interactiveDismissDisabled(isWorking)
    }

    private func make() async {
        problem = nil
        do { try EncryptedBackup.checkPassphrase(passphrase) } catch { problem = BackupCopy.message(error); return }
        isWorking = true
        defer { isWorking = false }
        await store.reload()
        // A failed read would make a backup of whatever was loaded before, or of nothing.
        if let loadError = store.loadError {
            problem = loadError
            return
        }
        // Files that can't be read are counted and named in the receipt, never skipped silently (DOD-08).
        var unreadablePhotos = 0, unreadableRecordings = 0
        var photos: [BackupContents.Photo] = []
        if includePhotos {
            for note in store.memories {
                guard let photo = store.photo(for: note.id) else { continue }
                guard let jpeg = await store.photoData(photo) else {
                    unreadablePhotos += 1
                    continue
                }
                photos.append(.init(memoryID: note.id, width: photo.width, height: photo.height, addedAt: photo.addedAt, jpeg: jpeg))
            }
        }
        var recordings: [BackupContents.Recording] = []
        if includeRecordings {
            for note in store.memories {
                guard let audio = store.recording(for: note.id) else { continue }
                guard let m4a = await store.recordingData(audio) else {
                    unreadableRecordings += 1
                    continue
                }
                recordings.append(.init(memoryID: note.id, durationMilliseconds: audio.durationMilliseconds, addedAt: audio.addedAt, m4a: m4a))
            }
        }
        leftOut = unreadablePhotos + unreadableRecordings == 0 ? nil : String(
            format: NSLocalizedString("%lld photos and %lld voice memos couldn't be read on this iPhone, so they aren't in this backup.", comment: ""),
            unreadablePhotos, unreadableRecordings)
        do {
            let export = try MemoryExport.json(
                store.memories + store.lists.map(\.record), listItems: store.lists.flatMap(\.items),
                corrections: store.corrections, exportedAt: .now)
            let contents = BackupContents(
                createdAt: .now, memoriesExport: export,
                reminders: BackupContents.reminders(noteReminders.reminders, now: .now),
                profile: Dictionary(uniqueKeysWithValues: profiles.profile.fields.map { ($0.key.rawValue, $0.value.value) }),
                photos: photos, recordings: recordings)
            let words = passphrase
            // Sealed, then opened again with the same passphrase and compared, before it is offered.
            let sealed = try await Task.detached(priority: .userInitiated) { () throws -> Data in
                let data = try EncryptedBackup.encrypt(contents, passphrase: words)
                guard try EncryptedBackup.decrypt(data, passphrase: words) == contents else {
                    throw MemoryStoreError.verificationFailed
                }
                return data
            }.value
            document = BackupDocument(data: sealed)
            showExporter = true
        } catch {
            problem = BackupCopy.message(error)
        }
    }
}

struct RestoreBackupView: View {
    @Environment(MemoryStore.self) private var store
    @Environment(NoteReminderStore.self) private var noteReminders
    @Environment(ProfileStore.self) private var profiles
    @Environment(\.dismiss) private var dismiss
    @State private var fileData: Data?
    @State private var fileName = ""
    @State private var passphrase = ""
    @State private var plan: BackupRestorePlan?
    @State private var isWorking = false
    @State private var problem: String?
    @State private var receipt: String?
    @State private var choosing = true
    /// The running decryption. A crafted file can ask for slow key stretching, so leaving the
    /// screen cancels it instead of leaving it to run on.
    @State private var decrypting: Task<BackupContents, any Error>?

    var body: some View {
        NavigationStack {
            Form {
                if let receipt {
                    Section {
                        Label(receipt, systemImage: "checkmark.circle").foregroundStyle(Theme.confirmed)
                            .accessibilityIdentifier("backup.restored")
                        Button("Done") { dismiss() }
                    }
                } else if let plan {
                    Section("This adds to this iPhone") {
                        Text(summary(plan))
                        if plan.notes.alreadyHere + plan.notes.keptOnPhone > 0 {
                            Text("\(plan.notes.alreadyHere + plan.notes.keptOnPhone) notes are already here and stay as they are.")
                                .font(.footnote).foregroundStyle(Theme.secondaryText)
                        }
                    }
                    Section {
                        Button(isWorking ? "Adding…" : "Add to this iPhone") { Task { await apply(plan) } }
                            .disabled(isWorking || plan.isEmpty)
                            .accessibilityIdentifier("backup.apply")
                    } footer: { Text("Nothing on this iPhone is changed or removed.") }
                } else if fileData != nil {
                    Section {
                        Text(fileName).font(.footnote)
                        SecureField("Passphrase", text: $passphrase).textContentType(.password)
                        Button(isWorking ? "Opening…" : "Open the backup") { Task { await open() } }
                            .disabled(isWorking || passphrase.isEmpty)
                            .accessibilityIdentifier("backup.open")
                    }
                } else {
                    Section { Button("Choose a backup file") { choosing = true } }
                }
                if let problem { Section { Label(problem, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.error) } }
            }
            .navigationTitle("Restore a backup")
            .navigationBarTitleDisplayMode(.inline)
            // While a backup is being opened, nothing is written yet, so Cancel stays available
            // and stops the decryption; while adding, it waits.
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        decrypting?.cancel()
                        dismiss()
                    }
                    .disabled(isWorking && decrypting == nil)
                }
            }
            .fileImporter(isPresented: $choosing, allowedContentTypes: [.doddyBackup, .data]) { result in read(result) }
        }
        .interactiveDismissDisabled(isWorking && decrypting == nil)
        .onDisappear { decrypting?.cancel() }
    }

    private func read(_ result: Result<URL, any Error>) {
        problem = nil
        guard let url = try? result.get() else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= BackupLimits.maxFileBytes, let data = try? Data(contentsOf: url) else {
            problem = NSLocalizedString("That file couldn't be read, or is too large. Nothing was added.", comment: "")
            return
        }
        fileData = data
        fileName = url.lastPathComponent
    }

    private func open() async {
        guard let fileData else { return }
        problem = nil
        isWorking = true
        let words = passphrase
        let task = Task.detached(priority: .userInitiated) { () throws -> BackupContents in
            try EncryptedBackup.decrypt(fileData, passphrase: words)
        }
        decrypting = task
        defer {
            isWorking = false
            decrypting = nil
        }
        do {
            let contents = try await task.value
            await store.reload()
            plan = try BackupRestorePlan.make(
                contents, existing: store.memories + store.lists.map(\.record),
                profileIsEmpty: profiles.profile.isEmpty, now: .now)
            if plan?.isEmpty == true { problem = NSLocalizedString("Everything in this backup is already on this iPhone. Nothing to add.", comment: "") }
        } catch {
            problem = BackupCopy.message(error)
        }
    }

    private func summary(_ plan: BackupRestorePlan) -> String {
        var parts = ["\(plan.notes.toAdd.count) notes and lists"]
        if !plan.listItems.isEmpty { parts.append("\(plan.listItems.count) list items") }
        if !plan.photos.isEmpty { parts.append("\(plan.photos.count) photos") }
        if !plan.recordings.isEmpty { parts.append("\(plan.recordings.count) voice memos") }
        if !plan.reminders.isEmpty { parts.append("\(plan.reminders.count) reminders") }
        if plan.profile != nil { parts.append("your About you answers") }
        return parts.joined(separator: ", ") + "."
    }

    /// Adds in order and counts only what was read back: notes and items, then photos, reminders
    /// and the profile for the notes that were really added.
    private func apply(_ plan: BackupRestorePlan) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let added = try await store.restore(plan.notes.toAdd, corrections: plan.notes.corrections, listItems: plan.listItems)
            let addedIDs = Set(added.map(\.id))
            var photos = 0, recordings = 0, reminders = 0, notKept = 0
            for photo in plan.photos where addedIDs.contains(photo.memoryID) {
                if (try? await store.attachPhoto(jpeg: photo.jpeg, width: photo.width, height: photo.height, to: photo.memoryID)) != nil {
                    photos += 1
                } else { notKept += 1 }
            }
            for recording in plan.recordings where addedIDs.contains(recording.memoryID) {
                if (try? await store.attachRecording(m4a: recording.m4a, durationMilliseconds: recording.durationMilliseconds, to: recording.memoryID)) != nil {
                    recordings += 1
                } else { notKept += 1 }
            }
            for reminder in plan.reminders where addedIDs.contains(reminder.memoryID) {
                guard let when = reminder.nextFire(after: .now) else { continue }
                await noteReminders.set(
                    memoryID: reminder.memoryID, at: when,
                    timeZone: TimeZone(identifier: reminder.timeZoneID) ?? .autoupdatingCurrent, repeats: reminder.repeatRule)
                if noteReminders.reminder(forMemory: reminder.memoryID) != nil { reminders += 1 } else { notKept += 1 }
            }
            var profileAdded = false
            if let draft = plan.profile, profiles.profile.isEmpty {
                profileAdded = (try? await profiles.commit(draft)) != nil
                if !profileAdded { notKept += 1 }
            }
            var lines = ["Added \(added.count) notes and lists"]
            if photos > 0 { lines.append("\(photos) photos") }
            if recordings > 0 { lines.append("\(recordings) voice memos") }
            if reminders > 0 { lines.append("\(reminders) reminders") }
            if profileAdded { lines.append("your About you answers") }
            receipt = lines.joined(separator: ", ") + "."
                + (notKept > 0 ? " \(notKept) other things couldn't be added; the rest is all here." : "")
        } catch {
            problem = BackupCopy.message(error)
        }
    }
}
