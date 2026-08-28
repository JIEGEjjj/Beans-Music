import Foundation

final class AuthStore: ObservableObject {
    @Published var user: NetEaseUser?
    @Published var isLoggedIn = false
    @Published var playlists: [Playlist] = []

    private let defaults = UserDefaults.standard
    private let userKey = "beans.user"

    init() {
        if let data = defaults.data(forKey: userKey),
           let saved = try? JSONDecoder().decode(NetEaseUser.self, from: data) {
            user = saved
            isLoggedIn = true
        }
    }

    @MainActor
    func finishLogin() async throws {
        var account: NetEaseUser?
        for attempt in 0..<3 {
            do {
                account = try await NetEaseAPI.shared.account()
                break
            } catch {
                if attempt == 2 { throw error }
                try? await Task.sleep(nanoseconds: 1_200_000_000)
            }
        }
        guard let account else { throw NetEaseError.unknown("获取账号信息失败") }
        let playlists = (try? await NetEaseAPI.shared.userPlaylists(uid: account.uid)) ?? []
        user = account
        self.playlists = playlists.filter { $0.name != "我喜欢的音乐" }
        isLoggedIn = true
        if let data = try? JSONEncoder().encode(account) {
            defaults.set(data, forKey: userKey)
        }
        NotificationCenter.default.post(name: .beansNeteaseLoginDidUpdate, object: nil)
    }

    /// 刷新账号资料（VIP 状态等），登录后保持最新会员标识
    @MainActor
    func refreshAccount() async {
        guard let current = user else { return }
        if let fresh = try? await NetEaseAPI.shared.account() {
            user = fresh
            if let data = try? JSONEncoder().encode(fresh) {
                defaults.set(data, forKey: userKey)
            }
            if fresh.uid != current.uid {
                isLoggedIn = true
            }
        }
    }

    @MainActor
    func loadLibrary() async {
        guard let user else { return }
        if let cached = try? await NetEaseAPI.shared.userPlaylists(uid: user.uid) {
            playlists = cached.filter { $0.name != "我喜欢的音乐" }
        }
    }

    func logout() {
        NetEaseAPI.shared.clearCookies()
        user = nil
        playlists = []
        isLoggedIn = false
        defaults.removeObject(forKey: userKey)
    }
}
