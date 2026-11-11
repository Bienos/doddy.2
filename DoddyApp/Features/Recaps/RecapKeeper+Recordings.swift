import DoddyCore
import Foundation

/// Recaps of Recordings (decision 2026-11-09-conversation-recaps, step 4). A recording's words are written
/// out on this iPhone and, until now, never left it (ADR-588). A recap is written from those words by
/// Apple's model on this iPhone, or, only if the person turned on "Recaps on Doddy's server", by Doddy's
/// server; this file is outside the Recordings folder, whose guard forbids any networking there.
///
/// Two ways in:
/// - the person taps "Write a recap" on a recording (`writeRecap`, then `saveRecap` on a second tap);
/// - with "Remember what we talked about" on, a recording that was written out after the switch was
///   turned on gets its recap saved without a tap (`rememberRecordings`).
extension RecapKeeper {
    enum RecordingRecapResult {
        /// Written and checked, not saved yet.
        case ready(ConversationRecap, noteText: String)
        case skipped(RecapPolicy.Skip)
        /// The model's answer broke a recap rule, or the model failed: nothing was kept.
        case refused
        /// The server couldn't write it (offline, cap reached, not set up).
        case serverFailed(ServerRecapClient.Failure)
    }

    /// The conversations being written or saved right now, so two screens never make the same recap twice.
    @MainActor private static var inFlight: Set<String> = []

    static func recordingKey(_ id: UUID) -> String { "recording:\(id.uuidString.lowercased())" }

    /// Whether this recording's recap is in the notes (saved and read back on this iPhone).
    static func hasRecap(recording id: UUID, defaults: UserDefaults = .standard) -> Bool {
        ledger(defaults).contains(recordingKey(id))
    }

    /// The recording's words as the recap's lines: nobody names who spoke, so none is guessed.
    static func lines(from segments: [TranscriptSegment]) -> [RecapModelIO.Line] {
        segments.map { RecapModelIO.Line(speaker: .other, text: $0.text) }
    }

    /// The two-letter code of a recording's language ("pl-PL" is "pl").
    static func language(of recording: Recording) -> String {
        String(recording.languageCode.prefix { $0 != "-" && $0 != "_" }).lowercased()
    }

    /// Writes a recap of a recording's words. `explicit` is the person's own tap: it stands in for the
    /// "Remember what we talked about" switch (and for "after the switch was turned on"), but never for the
    /// server yes: Doddy's server writes only with its own switch.
    static func writeRecap(for recording: Recording, segments: [TranscriptSegment], explicit: Bool,
                           defaults: UserDefaults = .standard) async -> RecordingRecapResult {
        let lines = lines(from: segments)
        let language = language(of: recording)
        let decision = RecapPolicy.decide(
            kind: .recording, rememberOn: explicit || isOn(defaults), isPrivate: false,
            wordsFromPerson: RecapPolicy.wordCount(RecapModelIO.plainText(lines)),
            onDeviceAvailable: OnDeviceRecapWriter.isAvailable(languageCode: language), serverYes: serverYes(defaults))
        guard case .recap(let writer) = decision else {
            if case .skip(let why) = decision { return .skipped(why) }
            return .refused
        }
        let endedAt = recording.endedAt ?? recording.startedAt
        do {
            let answer: Data
            if writer == .onDevice {
                answer = try await OnDeviceRecapWriter.write(kind: .recording, lines: lines, languageCode: language)
            } else {
                answer = try await ServerRecapClient(server: ServerConfig.client())
                    .write(kind: .recording, lines: lines, languageCode: language)
            }
            let recap = try RecapModelIO.read(answer, kind: .recording, with: nil, endedAt: endedAt, writtenBy: writer,
                                              conversation: RecapModelIO.plainText(lines))
            return .ready(recap, noteText: try RecapMemoryText.text(recap, labels: labels(for: recap)))
        } catch let failure as ServerRecapClient.Failure {
            return .serverFailed(failure)
        } catch {
            return .refused
        }
    }

    /// Saves a written recap as a note, links it to its recording and marks the recording done, in that
    /// order and only after the note was read back. False when the note couldn't be saved: nothing is
    /// marked, so it can be tried again.
    @MainActor
    static func saveRecap(_ recap: ConversationRecap, noteText: String, recordingID: UUID, recordingTitle: String,
                          store: MemoryStore, defaults: UserDefaults = .standard) async -> Bool {
        do {
            let record = try await store.save(text: noteText, category: .other, source: .conversationRecap,
                                              capturedAt: recap.endedAt)
            // The note is saved either way; the link says where it came from.
            try? await AppEnvironment.shared.recordingRepository?.linkMemory(
                memoryID: record.id, recordingID: recordingID, atMilliseconds: 0,
                recordingTitle: recordingTitle, linkedAt: .now)
            defaults.set(ledger(defaults).adding(recordingKey(recordingID)).stored, forKey: RecapSettings.ledgerKey)
            return true
        } catch {
            return false
        }
    }

    /// With the switch on, saves the recap of each recording written out after it was turned on and not
    /// recapped yet (at most `limit` per pass, so a pile of recordings doesn't start them all at once). A
    /// recording too short to recap is marked so it isn't read again; any other failure is tried again later.
    @MainActor
    @discardableResult
    static func rememberRecordings(_ items: [RecordingListItem], store: MemoryStore, limit: Int = 2,
                                   defaults: UserDefaults = .standard) async -> Int {
        guard isOn(defaults), let repository = AppEnvironment.shared.recordingRepository else { return 0 }
        var saved = 0
        var started = 0
        for item in items {
            let recording = item.recording
            let key = recordingKey(recording.id)
            guard started < limit,
                  recording.phase == .saved || recording.phase == .recovered, recording.transcription == .done,
                  RecapPolicy.endedAfterSwitchOn(recording.endedAt ?? recording.startedAt, since: since(defaults)),
                  !ledger(defaults).contains(key), !ledger(defaults).contains("skip:" + key),
                  !inFlight.contains(key) else { continue }
            inFlight.insert(key)
            defer { inFlight.remove(key) }
            started += 1
            guard let segments = try? await allSegments(of: recording.id, repository), !segments.isEmpty else { continue }
            switch await writeRecap(for: recording, segments: segments, explicit: false, defaults: defaults) {
            case .ready(let recap, let noteText):
                if await saveRecap(recap, noteText: noteText, recordingID: recording.id,
                                   recordingTitle: recording.displayTitle(.current), store: store, defaults: defaults) { saved += 1 }
            case .skipped(.tooShort):
                defaults.set(ledger(defaults).adding("skip:" + key).stored, forKey: RecapSettings.ledgerKey)
            case .skipped, .refused, .serverFailed:
                continue
            }
        }
        return saved
    }

    /// Every word of a recording, a page at a time.
    static func allSegments(of id: UUID, _ repository: any RecordingRepository, pageSize: Int = 500) async throws -> [TranscriptSegment] {
        var all: [TranscriptSegment] = []
        while true {
            let page = try await repository.segments(recordingID: id, offset: all.count, limit: pageSize)
            all += page
            if page.count < pageSize { return all }
        }
    }
}
