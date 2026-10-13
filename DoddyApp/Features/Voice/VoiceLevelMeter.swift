import AVFoundation
import Foundation
import LiveKit

/// How loud the turn that is on is, for the wave on the voice screen (ADR-464). One number per
/// audio buffer: the buffer's loudness, smoothed. The sound itself is not kept, copied, recorded
/// or sent anywhere; the buffer is only read here and let go. Works for the ElevenLabs
/// conversation, whose audio runs through LiveKit's shared audio manager; the OpenAI test voice
/// has its own audio engine and gives no level, so its wave shows the phase's pattern only.
final class VoiceLevelMeter: NSObject, AudioRenderer, @unchecked Sendable {
    private let lock = NSLock()
    private var smoothed = 0.0
    private var lastBuffer: TimeInterval?

    /// Called by LiveKit on its audio thread.
    func render(pcmBuffer: AVAudioPCMBuffer) {
        let next = VoiceWave.signal(rms: Self.rms(pcmBuffer))
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        smoothed = VoiceWave.smooth(previous: smoothed, next: next)
        lastBuffer = now
        lock.unlock()
    }

    /// 0 ... 1, or nil when no sound has arrived at all (so the wave doesn't claim to measure
    /// something it hasn't received). Sound that stopped arriving reads as 0.
    func signal(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Double? {
        lock.lock()
        defer { lock.unlock() }
        guard let lastBuffer else { return nil }
        return now - lastBuffer > VoiceWave.signalStaleAfter ? 0 : smoothed
    }

    func reset() {
        lock.lock()
        smoothed = 0
        lastBuffer = nil
        lock.unlock()
    }

    /// Linear root-mean-square of all channels, 0 ... 1 for full-scale audio.
    private static func rms(_ buffer: AVAudioPCMBuffer) -> Double {
        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        guard frames > 0, channels > 0 else { return 0 }
        var sum = 0.0
        if let data = buffer.floatChannelData {
            for channel in 0..<channels {
                let samples = data[channel]
                for index in 0..<frames {
                    let value = Double(samples[index])
                    sum += value * value
                }
            }
        } else if let data = buffer.int16ChannelData {
            for channel in 0..<channels {
                let samples = data[channel]
                for index in 0..<frames {
                    let value = Double(samples[index]) / 32768
                    sum += value * value
                }
            }
        } else {
            return 0
        }
        return (sum / Double(frames * channels)).squareRoot()
    }
}

/// The two meters of one conversation: your microphone and Doddy's voice. Started when an
/// ElevenLabs conversation starts and stopped when it is over, so nothing listens in between.
final class VoiceLevelMeters: @unchecked Sendable {
    let microphone = VoiceLevelMeter()
    let doddy = VoiceLevelMeter()
    private let lock = NSLock()
    private var running = false

    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard !running else { return }
        running = true
        microphone.reset()
        doddy.reset()
        AudioManager.shared.add(localAudioRenderer: microphone)
        AudioManager.shared.add(remoteAudioRenderer: doddy)
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard running else { return }
        running = false
        AudioManager.shared.remove(localAudioRenderer: microphone)
        AudioManager.shared.remove(remoteAudioRenderer: doddy)
        microphone.reset()
        doddy.reset()
    }

    /// The measured loudness for the turn the wave is showing; nil when there is none to show.
    func signal(for mode: VoiceWave.Mode) -> Double? {
        switch mode {
        case .listening: microphone.signal()
        case .speaking: doddy.signal()
        case .flat, .thinking: nil
        }
    }
}
