import AVFoundation
import DoddyCore
import Foundation
import LiveKit

/// Listens to how loud Doddy's voice is while he talks, for Home's island extension (ADR-655).
/// LiveKit hands it each buffer of the audio his track plays; it keeps one smoothed number from
/// 0 to 1 and the moment it was updated. The sound itself is never kept, copied or sent: only that
/// number, in memory, for a moment. It reads Doddy's output, never the microphone.
///
/// `render` is called on an audio thread, so the state sits behind a lock and the view reads it
/// from anywhere.
final class AgentVoiceMeter: NSObject, AudioRenderer, @unchecked Sendable {
    static let shared = AgentVoiceMeter()

    private let lock = NSLock()
    private var smoother = VoiceLevelSmoother()
    /// `systemUptime` of the last buffer, or nil when none has come since `reset`.
    private var updatedAt: TimeInterval?
    /// His audio track is being listened to, so no buffer for a moment means silence, not
    /// "no source".
    private var attached = false

    func render(pcmBuffer: AVAudioPCMBuffer) {
        let rate = pcmBuffer.format.sampleRate
        guard rate > 0 else { return }
        let seconds = Double(pcmBuffer.frameLength) / rate
        let level = VoiceLevel.level(rms: Self.rms(of: pcmBuffer))
        lock.lock()
        smoother.push(level, seconds: seconds)
        updatedAt = ProcessInfo.processInfo.systemUptime
        lock.unlock()
    }

    /// Whether his audio track is being listened to (set by the conversation that attached it).
    var hasSource: Bool {
        lock.lock()
        defer { lock.unlock() }
        return attached
    }

    func markAttached(_ isAttached: Bool) {
        lock.lock()
        attached = isAttached
        lock.unlock()
    }

    /// The level to draw, 0 to 1: how loud the audio is now, and 0 when none has come in the last
    /// half second (a pause between his sentences may deliver no buffers).
    func current() -> Double {
        lock.lock()
        defer { lock.unlock() }
        guard let updatedAt, ProcessInfo.processInfo.systemUptime - updatedAt < 0.5 else { return 0 }
        return smoother.value
    }

    /// At the end of a conversation.
    func reset() {
        lock.lock()
        smoother.reset()
        updatedAt = nil
        attached = false
        lock.unlock()
    }

    /// The root-mean-square of the first channel, with the samples scaled to -1...1.
    private static func rms(of buffer: AVAudioPCMBuffer) -> Double {
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        var sum = 0.0
        if let channels = buffer.floatChannelData {
            let samples = channels[0]
            for index in 0..<frames {
                let sample = Double(samples[index])
                sum += sample * sample
            }
        } else if let channels = buffer.int16ChannelData {
            let samples = channels[0]
            for index in 0..<frames {
                let sample = Double(samples[index]) / 32_768
                sum += sample * sample
            }
        } else {
            return 0
        }
        return (sum / Double(frames)).squareRoot()
    }
}
