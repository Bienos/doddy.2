import QuartzCore
import UIKit

/// Doddy's clock (motion v2, MV3): a CADisplayLink that runs only while he moves, at 80–120 Hz
/// (`CADisableMinimumFrameDurationOnPhone`, Q9), and nothing while he is still except one wake-up
/// when the engine has something due (a breath, a timer). Battery: stillness is the default.
@MainActor
final class DoddyClock: NSObject, DoddyClockDriving {
    private var link: CADisplayLink?
    private var wake: Task<Void, Never>?
    private unowned let director: DoddyDirector

    init(director: DoddyDirector) {
        self.director = director
    }

    /// Installs the clock on the director once.
    static func install(on director: DoddyDirector = .shared) {
        guard director.clock == nil else { return }
        let clock = DoddyClock(director: director)
        retained = clock
        director.now = { CACurrentMediaTime() }
        director.clock = clock
        // MV4: whether the keyboard is up (he rides Ask's composer with it for free; the engine
        // only needs to know, so playful moments wait).
        let center = NotificationCenter.default
        for (name, up) in [(UIResponder.keyboardWillShowNotification, true), (UIResponder.keyboardWillHideNotification, false)] {
            _ = center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { director.keyboardChanged(up: up) }
            }
        }
        // MV5: Low Power Mode turns off his breaths and glances.
        director.setLowPower(ProcessInfo.processInfo.isLowPowerModeEnabled)
        _ = center.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { director.setLowPower(ProcessInfo.processInfo.isLowPowerModeEnabled) }
        }
    }

    /// The director holds its clock weakly; this keeps the app's one alive.
    private static var retained: DoddyClock?

    func run() {
        wake?.cancel()
        wake = nil
        guard link == nil else { return }
        let l = CADisplayLink(target: self, selector: #selector(frame(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        l.add(to: .main, forMode: .common)
        link = l
    }

    func sleep(until uptime: Double?) {
        link?.invalidate()
        link = nil
        wake?.cancel()
        wake = nil
        guard let uptime else { return }
        let delay = max(0.02, uptime - CACurrentMediaTime())
        wake = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.wake = nil
            self.director.tick(at: CACurrentMediaTime())
        }
    }

    @objc private func frame(_ link: CADisplayLink) {
        director.tick(at: link.timestamp)
    }
}
