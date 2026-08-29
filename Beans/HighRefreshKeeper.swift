import Foundation

/// 可选高刷新率保持器。配合 Info.plist 的 CADisableMinimumFrameDurationOnPhone 解开 60fps 上限。
final class HighRefreshKeeper {
    static let shared = HighRefreshKeeper()
    private var enabled = true

    private init() {}

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: ["beans.enableHighRefresh": true])
    }

    func configureFromDefaults() {
        configure(enabled: UserDefaults.standard.bool(forKey: "beans.enableHighRefresh"))
    }

    func configure(enabled: Bool) {
        self.enabled = enabled
    }

    func start() {
        enabled = true
    }

    func stop() {
        enabled = false
    }
}
