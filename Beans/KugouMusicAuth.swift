import Foundation
import UIKit

final class KugouMusicAuth: ObservableObject {
    static let shared = KugouMusicAuth()

    @Published private(set) var isLoggedIn = false
    @Published private(set) var userId = ""
    @Published private(set) var nickname = ""
    @Published private(set) var avatarURL: URL?
    @Published private(set) var vipBadge: String?

    private let defaults = UserDefaults.standard
    private let key = "beans.kugou.auth.v2"
    private var auth: [String: String] = [:]

    private init() {
        if let saved = defaults.dictionary(forKey: key) as? [String: String] {
            auth = saved
            apply(saved)
        }
    }

    var token: String { auth["token"] ?? "" }
    var mid: String { auth["KUGOU_API_MID"] ?? auth["mid"] ?? Self.defaultMid }
    var dfid: String { auth["dfid"] ?? auth["DFID"] ?? "-" }
    var guid: String { auth["KUGOU_API_GUID"] ?? "" }
    var vipType: Int { Int(auth["vipType"] ?? auth["vip_type"] ?? "0") ?? 0 }
    var hasMembership: Bool { vipType > 0 }

    var cookieHeader: String {
        var items = [
            ("userid", userId),
            ("token", token),
            ("KUGOU_API_MID", mid),
            ("dfid", dfid),
        ]
        if vipType > 0 {
            items.append(("vipType", "\(vipType)"))
            items.append(("viptype", "\(vipType)"))
        }
        return items
            .filter { !$0.1.isEmpty }
            .map { "\($0.0)=\($0.1)" }
            .joined(separator: "; ")
    }

    func prepareDevice() {
        var next = auth
        _ = Self.ensureDevice(&next)
        save(next)
    }

    func saveLogin(userId: String, token: String, nickname: String, avatar: String, vipType: Int) {
        var next = auth
        _ = Self.ensureDevice(&next)
        next["userid"] = userId
        next["token"] = token
        next["nickname"] = nickname
        next["avatar"] = avatar
        next["vipType"] = "\(vipType)"
        save(next)
    }

    func saveDeviceDFID(_ dfid: String) {
        guard !dfid.isEmpty else { return }
        var next = auth
        next["dfid"] = dfid
        save(next)
    }

    func updateVIPType(_ vipType: Int) {
        guard vipType > self.vipType else { return }
        var next = auth
        next["vipType"] = "\(vipType)"
        save(next)
    }

    func logout() {
        auth = [:]
        isLoggedIn = false
        userId = ""
        nickname = ""
        avatarURL = nil
        vipBadge = nil
        defaults.removeObject(forKey: key)
        NotificationCenter.default.post(name: .beansKugouLoginDidUpdate, object: nil)
    }

    private func save(_ value: [String: String]) {
        auth = value
        defaults.set(value, forKey: key)
        apply(value)
        NotificationCenter.default.post(name: .beansKugouLoginDidUpdate, object: nil)
    }

    private func apply(_ value: [String: String]) {
        userId = (value["userid"] ?? value["user_id"] ?? "").filter(\.isNumber)
        let token = value["token"] ?? ""
        isLoggedIn = !userId.isEmpty && !token.isEmpty
        nickname = value["nickname"]?.removingPercentEncoding ?? value["nickname"] ?? ""
        avatarURL = URL(string: value["avatar"] ?? "")
        let vip = Int(value["vipType"] ?? value["vip_type"] ?? "0") ?? 0
        vipBadge = vip > 0 ? "VIP" : nil
    }

    @discardableResult
    static func ensureDevice(_ obj: inout [String: String]) -> [String: String] {
        let guid = obj["KUGOU_API_GUID"] ?? UUID().uuidString
        obj["KUGOU_API_GUID"] = guid
        obj["KUGOU_API_MID"] = obj["KUGOU_API_MID"] ?? calculateMid(seed: guid)
        obj["KUGOU_API_MAC"] = obj["KUGOU_API_MAC"] ?? randomString(12)
        obj["KUGOU_API_DEV"] = obj["KUGOU_API_DEV"] ?? randomString(16)
        return obj
    }

    private static var defaultMid: String {
        calculateMid(seed: UIDevice.current.identifierForVendor?.uuidString ?? "beans-kugou")
    }

    private static func calculateMid(seed: String) -> String {
        let hex = Data(seed.utf8).md5Hex()
        let prefix = String(hex.prefix(15))
        if let value = UInt64(prefix, radix: 16) { return "\(value)" }
        return hex
    }

    private static func randomString(_ length: Int) -> String {
        let chars = Array("1234567890ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        return String((0..<length).map { _ in chars[Int.random(in: 0..<chars.count)] })
    }
}
