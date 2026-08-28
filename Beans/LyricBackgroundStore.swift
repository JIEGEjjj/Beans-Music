import Foundation

enum LyricBackgroundStore {
    static let pathKey = "beans.lyricBackground.image"
    static let dataKey = "beans.lyricBackground.data"
    static let blurKey = "beans.lyricBackground.blur"

    private static var directory: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BeansLyricBackground", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @discardableResult
    static func save(_ data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        let url = directory.appendingPathComponent("lyric-background-\(Int(Date().timeIntervalSince1970)).jpg")
        do {
            try data.write(to: url, options: .atomic)
            UserDefaults.standard.set(url.path, forKey: pathKey)
            UserDefaults.standard.set(data.base64EncodedString(), forKey: dataKey)
            return url.path
        } catch {
            return nil
        }
    }

    static func clear() {
        if let path = UserDefaults.standard.string(forKey: pathKey), !path.isEmpty {
            try? FileManager.default.removeItem(atPath: path)
        }
        UserDefaults.standard.removeObject(forKey: pathKey)
        UserDefaults.standard.removeObject(forKey: dataKey)
    }

    static func refreshForExport() {
        guard let path = UserDefaults.standard.string(forKey: pathKey), !path.isEmpty,
              FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return }
        UserDefaults.standard.set(data.base64EncodedString(), forKey: dataKey)
    }

    static func restoreFromBackup() {
        guard let b64 = UserDefaults.standard.string(forKey: dataKey),
              let data = Data(base64Encoded: b64) else { return }
        let savedPath = UserDefaults.standard.string(forKey: pathKey) ?? ""
        if !savedPath.isEmpty, FileManager.default.fileExists(atPath: savedPath) {
            return
        }
        let url = directory.appendingPathComponent("lyric-background-restored.jpg")
        if (try? data.write(to: url, options: .atomic)) != nil {
            UserDefaults.standard.set(url.path, forKey: pathKey)
        }
    }
}
