import AVFoundation
import DoddyCore
import Foundation
import Observation

/// Plays one recording, its parts back to back (ADR-588). Its position is on the recording's own
/// time, the one transcript lines are stamped with, so tapping a line plays from that line.
/// It never plays while a recording is being made: playing reconfigures the one audio session,
/// and that would break the recording.
@MainActor
@Observable
final class RecordingPlayer {
    private struct Piece {
        let url: URL
        let offsetMilliseconds: Int
        let durationMilliseconds: Int
    }

    private(set) var isPlaying = false
    private(set) var positionMilliseconds = 0
    private(set) var problem: String?

    @ObservationIgnored private var pieces: [Piece] = []
    @ObservationIgnored private var player: AVQueuePlayer?
    @ObservationIgnored private var items: [ObjectIdentifier: Int] = [:]
    @ObservationIgnored private var timeObserver: Any?

    var hasAudio: Bool { !pieces.isEmpty }
    var totalMilliseconds: Int { pieces.last.map { $0.offsetMilliseconds + $0.durationMilliseconds } ?? 0 }

    func load(parts: [RecordingPart], recordingID: UUID, files: RecordingFiles) {
        pieces = parts.compactMap { part in
            guard let duration = part.durationMilliseconds, let url = files.url(recordingID: recordingID, fileName: part.fileName),
                  FileManager.default.fileExists(atPath: url.path) else { return nil }
            return Piece(url: url, offsetMilliseconds: part.startOffsetMilliseconds, durationMilliseconds: duration)
        }
    }

    func toggle() {
        isPlaying ? pause() : play(from: nil)
    }

    /// Plays from `milliseconds` on the recording's own time, or from where it was.
    func play(from milliseconds: Int?) {
        guard hasAudio else { return }
        guard !RecordingCoordinator.shared.isActive else {
            problem = NSLocalizedString("Stop recording to play this.", comment: "")
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
        } catch {
            problem = NSLocalizedString("This recording couldn't be played.", comment: "")
            return
        }
        problem = nil
        let start = min(max(0, milliseconds ?? positionMilliseconds), max(0, totalMilliseconds - 1))
        rebuild(at: start)
        player?.play()
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
        release()
    }

    /// Moves the position. While playing the audio session is already set up, so this only moves the
    /// player (or, across a part boundary, rebuilds its queue): a drag calls this many times a second.
    func seek(toMilliseconds milliseconds: Int) {
        guard isPlaying, player != nil, hasAudio else {
            positionMilliseconds = min(max(0, milliseconds), totalMilliseconds)
            return
        }
        let target = min(max(0, milliseconds), max(0, totalMilliseconds - 1))
        if let item = player?.currentItem, let position = items[ObjectIdentifier(item)],
           pieces[position].offsetMilliseconds <= target,
           target < pieces[position].offsetMilliseconds + pieces[position].durationMilliseconds {
            let inside = target - pieces[position].offsetMilliseconds
            player?.seek(to: CMTime(value: CMTimeValue(inside), timescale: 1000), toleranceBefore: .zero, toleranceAfter: .zero)
            positionMilliseconds = target
        } else {
            rebuild(at: target)
            player?.play()
        }
    }

    func stop() {
        player?.pause()
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        player?.removeAllItems()
        player = nil
        items = [:]
        isPlaying = false
        release()
    }

    // MARK: -

    private func rebuild(at milliseconds: Int) {
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        player?.removeAllItems()
        items = [:]
        let index = pieces.lastIndex { $0.offsetMilliseconds <= milliseconds } ?? 0
        let queue = AVQueuePlayer()
        for position in index..<pieces.count {
            let item = AVPlayerItem(url: pieces[position].url)
            items[ObjectIdentifier(item)] = position
            queue.insert(item, after: nil)
        }
        let inside = max(0, milliseconds - pieces[index].offsetMilliseconds)
        queue.seek(to: CMTime(value: CMTimeValue(inside), timescale: 1000), toleranceBefore: .zero, toleranceAfter: .zero)
        timeObserver = queue.addPeriodicTimeObserver(forInterval: CMTime(value: 250, timescale: 1000), queue: .main) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        player = queue
        positionMilliseconds = milliseconds
    }

    private func tick() {
        guard let player else { return }
        guard let item = player.currentItem, let position = items[ObjectIdentifier(item)] else {
            // Past the last part.
            isPlaying = false
            positionMilliseconds = 0
            release()
            return
        }
        positionMilliseconds = pieces[position].offsetMilliseconds + Int(max(0, item.currentTime().seconds) * 1000)
    }

    private func release() {
        guard !RecordingCoordinator.shared.isActive else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
