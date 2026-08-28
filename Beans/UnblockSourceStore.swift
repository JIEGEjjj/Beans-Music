import Foundation

/// 用户自定义的第三方解锁源（JSON / 落雪 API 服务器导入）
/// kind：netease-id、keyword、lx（落雪 API 服务器）或 lx-script（洛雪音源脚本转换配置）
/// template：请求 URL 模板，支持占位符 {id} {name} {keyword} {artist}
/// urlPath：响应 JSON 中播放地址的字段路径（支持点分，如 url / data.url / data.audioUrl）
/// headers：可选的附加请求头
/// enabled：导入后用户可自行选择开启 / 关闭
struct ThirdPartySource: Identifiable, Codable, Hashable, Sendable {
    var id = UUID().uuidString
    var name: String
    var kind: String = "keyword"
    var template: String
    var urlPath: String = "url"
    var headers: [String: String] = [:]
    var enabled: Bool = true

    enum CodingKeys: String, CodingKey { case id, name, kind, template, urlPath, headers, enabled }

    init(id: String = UUID().uuidString, name: String, kind: String = "keyword", template: String, urlPath: String = "url", headers: [String: String] = [:], enabled: Bool = true) {
        self.id = id
        self.name = name
        self.kind = kind
        self.template = template
        self.urlPath = urlPath
        self.headers = headers
        self.enabled = enabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "未命名音源"
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "keyword"
        template = try c.decodeIfPresent(String.self, forKey: .template) ?? ""
        urlPath = try c.decodeIfPresent(String.self, forKey: .urlPath) ?? "url"
        headers = try c.decodeIfPresent([String: String].self, forKey: .headers) ?? [:]
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}

/// 用户导入的落雪 LX JavaScript 音源。
/// 脚本保存在 UserDefaults 中，播放时由 LxScriptRuntime 在受限桥接环境里执行。
struct LxScriptSource: Identifiable, Codable, Hashable, Sendable {
    var id = UUID().uuidString
    var name: String
    var script: String

    enum CodingKeys: String, CodingKey { case id, name, script }

    init(id: String = UUID().uuidString, name: String, script: String) {
        self.id = id
        self.name = name
        self.script = script
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "未命名 LX 音源"
        script = try container.decodeIfPresent(String.self, forKey: .script) ?? ""
    }
}

/// 第三方解锁源管理：用户导入的自定义源（UserDefaults 持久化，导入后可选开启 / 关闭）
final class UnblockSourceStore: ObservableObject {
    static let shared = UnblockSourceStore()

    static let guoyuePresetSources: [ThirdPartySource] = [
        ThirdPartySource(
            name: "guoyue2010 · QQ 稳定源",
            kind: "template-api",
            template: "https://cyapi.top/API/qq_music.php?apikey=1ffdf5733f5d538760e63d7e46ba17438d9f7b9dfc18c51be1109386fd74c3a1&type=json&mid={id}",
            urlPath: "url",
            headers: ["source": "tx"]
        ),
        ThirdPartySource(
            name: "guoyue2010 · 网易云统一源",
            kind: "template-api",
            template: "https://music-api.gdstudio.xyz/api.php?types=url&source=netease&id={id}&br=999",
            urlPath: "url",
            headers: ["source": "wy"]
        ),
    ]

    /// 用户导入的自定义源
    @Published var customSources: [ThirdPartySource] {
        didSet { save() }
    }

    /// 用户导入的 LX 脚本。是否参与播放由“使用导入音源”总开关控制。
    @Published var lxScripts: [LxScriptSource] {
        didSet { saveLxScripts() }
    }

    private let defaults = UserDefaults.standard
    private let customKey = "beans.unblock.custom"
    private let presetSeedKey = "beans.unblock.guoyuePreset.v1"
    private let freeListenSeedKey = "beans.unblock.freeListenPreset.v1"
    private let lxScriptsKey = "beans.unblock.lxScripts"

    private init() {
        let savedSources: [ThirdPartySource]
        if let data = defaults.data(forKey: customKey),
           let list = try? JSONDecoder().decode([ThirdPartySource].self, from: data) {
            savedSources = list
        } else {
            savedSources = []
        }
        customSources = Self.seedGuoyuePresets(into: savedSources, defaults: defaults, seedKey: presetSeedKey)
        if let data = defaults.data(forKey: lxScriptsKey),
           let list = try? JSONDecoder().decode([LxScriptSource].self, from: data) {
            lxScripts = list
        } else {
            lxScripts = []
        }
        enableFreeListenForPresetIfNeeded()
        save()
    }

    func add(_ source: ThirdPartySource) {
        if let index = customSources.firstIndex(where: {
            $0.kind == source.kind
                && $0.template == source.template
                && $0.headers["source"] == source.headers["source"]
        }) {
            var updated = source
            updated.id = customSources[index].id
            customSources[index] = updated
        } else {
            // 后导入的音源优先尝试，便于替换已经失效的旧源。
            customSources.insert(source, at: 0)
        }
    }

    func remove(_ source: ThirdPartySource) {
        customSources.removeAll { $0.id == source.id }
    }

    func addLxScript(_ source: LxScriptSource) {
        lxScripts.removeAll { $0.name == source.name }
        lxScripts.append(source)
    }

    func removeLxScript(_ source: LxScriptSource) {
        lxScripts.removeAll { $0.id == source.id }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(customSources) {
            defaults.set(data, forKey: customKey)
        }
    }

    private func saveLxScripts() {
        if let data = try? JSONEncoder().encode(lxScripts) {
            defaults.set(data, forKey: lxScriptsKey)
        }
    }

    private static func seedGuoyuePresets(into savedSources: [ThirdPartySource], defaults: UserDefaults, seedKey: String) -> [ThirdPartySource] {
        guard !defaults.bool(forKey: seedKey) else { return savedSources }
        defaults.set(true, forKey: seedKey)
        var seeded = savedSources
        for preset in guoyuePresetSources.reversed() where !seeded.contains(where: {
            $0.kind == preset.kind
                && $0.template == preset.template
                && $0.headers["source"] == preset.headers["source"]
        }) {
            seeded.insert(preset, at: 0)
        }
        return seeded
    }

    private func enableFreeListenForPresetIfNeeded() {
        guard !defaults.bool(forKey: freeListenSeedKey) else { return }
        defaults.set(true, forKey: freeListenSeedKey)
        defaults.set(true, forKey: "beans.enableUnblock")
    }
}
