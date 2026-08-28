import QuartzCore
import Foundation

/// 可选高刷新率保持器。默认不启用，避免静止页面也持续唤醒主线程导致发热。
final class HighRefreshKeeper {
    static let shared = HighRefreshKeeper()
    private var displayLink: CADisplayLink?

    private init() {}

    func configureFromDefaults() {
        configure(enabled: UserDefaults.standard.bool(forKey: "beans.enableHighRefresh"))
    }

    func configure(enabled: Bool) {
        if enabled {
            start()
        } else {
            stop()
        }
    }

    func start() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        if #available(iOS 15.0, *) {
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 90, maximum: 120)
        } else {
            link.preferredFramesPerSecond = 120
        }
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick() {}
}
