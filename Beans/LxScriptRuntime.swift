import Foundation
import JavaScriptCore

enum LxScriptRuntime {
    static func looksLikeLxScript(_ script: String) -> Bool {
        let value = script.lowercased()
        let hasLX = value.contains("globalthis.lx")
            || value.contains("globalthis['lx']")
            || value.contains("globalthis[\"lx\"]")
        let hasRequestProtocol = value.contains("request")
            && (value.contains("event_names") || value.contains("on(") || value.contains(".on("))
        return hasLX && hasRequestProtocol
    }

    static func resolve(
        source: LxScriptSource,
        name: String,
        artists: String,
        durationMS: Int,
        neteaseID: Int,
        qqMid: String?,
        kugouHash: String?
    ) async -> URL? {
        await withCheckedContinuation { continuation in
            let runner = LxScriptRunner(
                source: source,
                name: name,
                artists: artists,
                durationMS: durationMS,
                neteaseID: neteaseID,
                qqMid: qqMid,
                kugouHash: kugouHash
            ) { url in
                continuation.resume(returning: url)
            }
            runner.start()
        }
    }
}

private final class LxScriptRunner {
    private let source: LxScriptSource
    private let name: String
    private let artists: String
    private let durationMS: Int
    private let neteaseID: Int
    private let qqMid: String?
    private let kugouHash: String?
    private let completion: (URL?) -> Void
    private let queue = DispatchQueue(label: "com.beans.lx-script-runtime")
    private let session: URLSession

    private var context: JSContext?
    private var finished = false
    private var sourceIndex = 0
    private var qualityIndex = 0
    private var handlerWaitCount = 0
    private let sourceIDs: [String]
    private let qualities = ["320k", "128k", "flac"]

    init(
        source: LxScriptSource,
        name: String,
        artists: String,
        durationMS: Int,
        neteaseID: Int,
        qqMid: String?,
        kugouHash: String?,
        completion: @escaping (URL?) -> Void
    ) {
        self.source = source
        self.name = name
        self.artists = artists
        self.durationMS = durationMS
        self.neteaseID = neteaseID
        self.qqMid = qqMid
        self.kugouHash = kugouHash
        self.completion = completion
        if let kugouHash, !kugouHash.isEmpty {
            sourceIDs = ["kg", "wy", "tx", "kw", "mg", "git"]
        } else if let qqMid, !qqMid.isEmpty {
            sourceIDs = ["tx", "wy", "kw", "kg", "mg", "git"]
        } else if neteaseID > 0 {
            sourceIDs = ["wy", "tx", "kw", "kg", "mg", "git"]
        } else {
            sourceIDs = ["wy", "tx", "kw", "kg", "mg", "git"]
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 18
        session = URLSession(configuration: configuration)
    }

    func start() {
        queue.async {
            self.installContext()
            self.queue.asyncAfter(deadline: .now() + 0.12) {
                self.dispatchNext()
            }
            self.queue.asyncAfter(deadline: .now() + 24) {
                self.finish(nil)
            }
        }
    }

    private func installContext() {
        let jsContext = JSContext()
        context = jsContext
        jsContext?.exceptionHandler = { _, _ in }

        let nativeRequest: @convention(block) (String, JSValue?, String) -> Void = { [weak self] url, options, requestID in
            guard let self else { return }
            let object = options?.toObject()
            self.startRequest(url: url, options: object, requestID: requestID)
        }
        let nativeSend: @convention(block) (String, JSValue?) -> Void = { _, _ in }

        jsContext?.setObject(nativeRequest, forKeyedSubscript: "__beansNativeRequest" as NSString)
        jsContext?.setObject(nativeSend, forKeyedSubscript: "__beansNativeSend" as NSString)

        let bootstrap = """
        (function(root) {
          if (typeof root.globalThis === 'undefined') root.globalThis = root;
          const pending = Object.create(null);
          const handlers = Object.create(null);
          let sequence = 0;
          root.__beansResolveRequest = function(id, ok, response) {
            const item = pending[String(id)];
            if (!item) return;
            delete pending[String(id)];
            if (item.callback) {
              return item.callback(ok ? null : ((response && response.error) || 'request failed'), response || null);
            }
            if (ok) item.resolve(response);
            else item.reject(new Error((response && response.error) || 'request failed'));
          };
          root.__beansDispatch = function(name, payload) {
            const handler = handlers[name];
            return typeof handler === 'function' ? handler(payload) : null;
          };
          root.__beansHasHandler = function(name) {
            return typeof handlers[name] === 'function';
          };
          root.lx = {
            EVENT_NAMES: {
              request: 'request',
              inited: 'inited',
              musicUrl: 'musicUrl',
              lyric: 'lyric',
              search: 'search'
            },
            on: function(name, handler) { handlers[name] = handler; },
            send: function(name, payload) { root.__beansNativeSend(name, payload); },
            request: function(url, options, callback) {
              if (typeof options === 'function') {
                callback = options;
                options = {};
              }
              const id = String(++sequence);
              const hasCallback = typeof callback === 'function';
              if (hasCallback) pending[id] = { callback: callback };
              else pending[id] = { resolve: null, reject: null };
              if (!hasCallback) {
                return new Promise(function(resolve, reject) {
                  pending[id].resolve = resolve;
                  pending[id].reject = reject;
                  root.__beansNativeRequest(String(url), options || {}, id);
                });
              }
              root.__beansNativeRequest(String(url), options || {}, id);
              return undefined;
            },
            utils: {},
            env: 'mobile',
            version: '0.0.0'
          };
          var consoleObject = root.console || {};
          ['log', 'warn', 'error', 'info', 'debug', 'group', 'groupEnd'].forEach(function(name) {
            if (typeof consoleObject[name] !== 'function') consoleObject[name] = function() {};
          });
          root.console = consoleObject;
        })(this);
        """

        guard jsContext?.evaluateScript(bootstrap) != nil else {
            finish(nil)
            return
        }
        guard jsContext?.evaluateScript(source.script) != nil else {
            finish(nil)
            return
        }
    }

    private func dispatchNext() {
        guard !finished else { return }
        guard sourceIndex < sourceIDs.count else {
            finish(nil)
            return
        }

        let sourceID = sourceIDs[sourceIndex]
        let quality = qualities[qualityIndex]
        var musicInfo: [String: Any] = [
            "name": name,
            "song": name,
            "artist": artists,
            "artists": artists,
            "duration": durationMS,
            "duration_ms": durationMS
        ]
        if neteaseID > 0 {
            musicInfo["id"] = neteaseID
            musicInfo["rid"] = neteaseID
        }
        if let qqMid, !qqMid.isEmpty {
            musicInfo["songmid"] = qqMid
            musicInfo["mid"] = qqMid
        }
        if let kugouHash, !kugouHash.isEmpty {
            musicInfo["hash"] = kugouHash
        }
        let info: [String: Any] = [
            "type": quality,
            "quality": quality,
            "musicInfo": musicInfo,
            "music": musicInfo
        ]
        let payload: [String: Any] = [
            "action": "musicUrl",
            "source": sourceID,
            "info": info
        ]

        guard let hasHandler = context?.objectForKeyedSubscript("__beansHasHandler")?.call(withArguments: ["request"]),
              hasHandler.toBool() else {
            if handlerWaitCount < 12 {
                handlerWaitCount += 1
                queue.asyncAfter(deadline: .now() + 0.25) {
                    self.dispatchNext()
                }
            } else {
                advance()
            }
            return
        }
        handlerWaitCount = 0

        guard let dispatch = context?.objectForKeyedSubscript("__beansDispatch"),
              let value = dispatch.call(withArguments: ["request", payload]),
              !value.isUndefined,
              !value.isNull else {
            advance()
            return
        }

        if value.hasProperty("then") {
            let success: @convention(block) (JSValue?) -> Void = { [weak self] result in
                self?.queue.async {
                    self?.handleResult(result)
                }
            }
            let failure: @convention(block) (JSValue?) -> Void = { [weak self] _ in
                self?.queue.async {
                    self?.advance()
                }
            }
            value.invokeMethod("then", withArguments: [success, failure])
        } else {
            handleResult(value)
        }
    }

    private func handleResult(_ value: JSValue?) {
        guard !finished else { return }
        let object = value?.toObject()
        let candidate: String?
        if let string = object as? String {
            candidate = string
        } else if let dictionary = object as? [String: Any] {
            candidate = (dictionary["url"] as? String)
                ?? (dictionary["audio_url"] as? String)
                ?? (dictionary["play_url"] as? String)
                ?? (dictionary["playUrl"] as? String)
        } else {
            candidate = value?.toString()
        }
        guard let candidate,
              let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              !candidate.isEmpty,
              candidate != "undefined",
              candidate != "null" else {
            advance()
            return
        }
        finish(url)
    }

    private func advance() {
        guard !finished else { return }
        qualityIndex += 1
        if qualityIndex >= qualities.count {
            qualityIndex = 0
            sourceIndex += 1
        }
        dispatchNext()
    }

    private func startRequest(url: String, options: Any?, requestID: String) {
        guard let requestURL = URL(string: url),
              let scheme = requestURL.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            completeRequest(requestID: requestID, response: ["error": "invalid request URL"], success: false)
            return
        }

        let optionsDictionary = dictionary(from: options)
        var request = URLRequest(url: requestURL)
        request.httpMethod = (optionsDictionary["method"] as? String ?? "GET").uppercased()
        if let timeout = number(optionsDictionary["timeout"]) {
            request.timeoutInterval = timeout > 100 ? timeout / 1000 : timeout
        }
        if let headers = optionsDictionary["headers"] {
            let headerValues = dictionary(from: headers)
            for (key, value) in headerValues {
                request.setValue(String(describing: value), forHTTPHeaderField: key)
            }
        }
        if let body = optionsDictionary["body"] {
            if let string = body as? String {
                request.httpBody = Data(string.utf8)
            } else if JSONSerialization.isValidJSONObject(body),
                      let data = try? JSONSerialization.data(withJSONObject: body) {
                request.httpBody = data
                if request.value(forHTTPHeaderField: "Content-Type") == nil {
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                }
            }
        }

        Task { [self] in
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    completeRequest(requestID: requestID, response: ["error": "invalid response"], success: false)
                    return
                }
                var headers: [String: String] = [:]
                for (key, value) in http.allHeaderFields {
                    headers[String(describing: key)] = String(describing: value)
                }
                let bodyText = String(data: data, encoding: .utf8) ?? ""
                let body: Any
                if let json = try? JSONSerialization.jsonObject(with: data, options: []) {
                    body = json
                } else {
                    body = bodyText
                }
                completeRequest(
                    requestID: requestID,
                    response: [
                        "statusCode": http.statusCode,
                        "status": http.statusCode,
                        "headers": headers,
                        "body": body
                    ],
                    success: true
                )
            } catch {
                completeRequest(
                    requestID: requestID,
                    response: [
                        "statusCode": 0,
                        "status": 0,
                        "headers": [String: String](),
                        "body": [String: Any](),
                        "error": error.localizedDescription
                    ],
                    success: true
                )
            }
        }
    }

    private func completeRequest(requestID: String, response: [String: Any], success: Bool) {
        queue.async {
            guard !self.finished,
                  let resolver = self.context?.objectForKeyedSubscript("__beansResolveRequest") else { return }
            resolver.call(withArguments: [requestID, success, response])
        }
    }

    private func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private func dictionary(from value: Any?) -> [String: Any] {
        if let value = value as? [String: Any] {
            return value
        }
        if let value = value as? NSDictionary {
            var result: [String: Any] = [:]
            for (key, item) in value {
                if let key = key as? String {
                    result[key] = item
                }
            }
            return result
        }
        return [:]
    }

    private func finish(_ url: URL?) {
        guard !finished else { return }
        finished = true
        context = nil
        completion(url)
    }
}
