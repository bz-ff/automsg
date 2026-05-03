import Foundation
import Network
import AppKit

final class RemoteServer {
    private var listener: NWListener?
    private let port: NWEndpoint.Port
    private let queue = DispatchQueue(label: "com.automsg.remoteserver")
    private weak var appState: AppState?

    var token: String
    private(set) var isRunning = false

    init(port: UInt16 = 8765, token: String, appState: AppState) {
        self.port = NWEndpoint.Port(rawValue: port)!
        self.token = token
        self.appState = appState
    }

    func start() {
        guard !isRunning else { return }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let listener = try NWListener(using: params, on: port)
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    print("[RemoteServer] listening on port \(self?.port.rawValue ?? 0)")
                    self?.isRunning = true
                case .failed(let err):
                    print("[RemoteServer] failed: \(err)")
                    self?.isRunning = false
                case .cancelled:
                    self?.isRunning = false
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] conn in
                self?.handleConnection(conn)
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            print("[RemoteServer] start error: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    private func handleConnection(_ conn: NWConnection) {
        conn.start(queue: queue)
        receiveRequest(conn, accumulated: Data())
    }

    private func receiveRequest(_ conn: NWConnection, accumulated: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = accumulated
            if let data { buffer.append(data) }

            if let request = HTTPRequest.parse(buffer) {
                Task { @MainActor in
                    let response = await self.route(request)
                    self.send(response, on: conn)
                }
            } else if isComplete || error != nil {
                conn.cancel()
            } else {
                self.receiveRequest(conn, accumulated: buffer)
            }
        }
    }

    private func send(_ response: HTTPResponse, on conn: NWConnection) {
        conn.send(content: response.serialize(), completion: .contentProcessed { _ in
            conn.cancel()
        })
    }

    @MainActor
    private func route(_ req: HTTPRequest) async -> HTTPResponse {
        guard let appState else { return .json(503, ["error": "no app state"]) }

        // Static UI route — no token required
        if req.path == "/" || req.path == "/index.html" {
            return RemoteUI.serve(token: token)
        }

        // All API routes require token
        let providedToken = req.query["token"] ?? req.headers["authorization"]?.replacingOccurrences(of: "Bearer ", with: "")
        guard providedToken == token else {
            return .json(401, ["error": "invalid or missing token"])
        }

        switch (req.method, req.path) {
        case ("GET", "/api/status"):
            return .json(200, [
                "ollama": appState.ollamaConnected,
                "messages": appState.messagesAvailable,
                "monitor": appState.monitor.isRunning,
                "globalEnabled": appState.isGlobalEnabled,
                "diskAccess": appState.diskAccessGranted,
                "contactCount": appState.contacts.count,
                "enabledCount": appState.contacts.filter { $0.isEnabled }.count
            ])

        case ("POST", "/api/global/toggle"):
            appState.isGlobalEnabled.toggle()
            return .json(200, ["globalEnabled": appState.isGlobalEnabled])

        case ("GET", "/api/contacts"):
            let payload = appState.contacts.map { c -> [String: Any] in
                [
                    "id": c.id,
                    "name": c.displayName,
                    "handles": c.handles,
                    "enabled": c.isEnabled,
                    "hasHistory": c.hasHistory,
                    "hasDraft": (c.currentDraft?.isEmpty == false),
                    "preferredHandle": c.preferredHandle as Any,
                    "smartMode": c.smartMode.rawValue,
                    "hasMemory": !c.memory.isEmpty
                ]
            }
            return .json(200, [
                "contacts": payload,
                "pendingReplies": appState.monitor.pendingAutoReplies
            ])

        case ("GET", "/api/models"):
            // Proxy Ollama's /api/tags so the mobile UI can show installed models + active one
            let tagsURL = URL(string: "http://localhost:11434/api/tags")!
            do {
                let (data, _) = try await URLSession.shared.data(from: tagsURL)
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let raw = (json?["models"] as? [[String: Any]]) ?? []
                let parsed = raw.compactMap { dict -> [String: Any]? in
                    guard let name = dict["name"] as? String else { return nil }
                    let size = (dict["size"] as? Int64) ?? 0
                    let mod = (dict["modified_at"] as? String) ?? ""
                    return [
                        "name": name,
                        "sizeGB": Double(size) / 1_073_741_824.0,
                        "modified": String(mod.prefix(10))
                    ]
                }.sorted { (($0["name"] as? String) ?? "") < (($1["name"] as? String) ?? "") }
                return .json(200, [
                    "active": Persistence.modelName,
                    "models": parsed
                ])
            } catch {
                return .json(500, ["error": "Couldn't reach Ollama: \(error.localizedDescription)"])
            }

        case ("POST", "/api/models/active"):
            let body = (try? JSONSerialization.jsonObject(with: req.body) as? [String: Any]) ?? [:]
            guard let name = body["name"] as? String, !name.isEmpty else {
                return .json(400, ["error": "missing name"])
            }
            Persistence.modelName = name
            return .json(200, [
                "active": name,
                "note": "Hit Restart in settings to apply"
            ])

        case ("POST", "/api/restart"):
            // Schedule the app to relaunch itself: spawn a detached helper that
            // waits for this process to exit, then re-opens the .app bundle.
            let bundlePath = Bundle.main.bundlePath
            let pid = ProcessInfo.processInfo.processIdentifier
            let script = """
            (while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; sleep 0.5; /usr/bin/open '\(bundlePath)') &
            """
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/sh")
            task.arguments = ["-c", script]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            do {
                try task.run()
            } catch {
                return .json(500, ["error": "failed to schedule restart: \(error.localizedDescription)"])
            }
            // Trigger a clean shutdown after we've sent the response.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                appState.shutdown()
                NSApplication.shared.terminate(nil)
            }
            return .json(200, ["restarting": true])

        case ("GET", "/api/activity"):
            let payload = appState.activityLog.prefix(50).map { e -> [String: Any] in
                [
                    "time": e.timeString,
                    "contactID": e.contactID,
                    "type": e.type == .autoReply ? "auto" : "manual",
                    "incoming": e.incomingText as Any,
                    "reply": e.replyText
                ]
            }
            return .json(200, ["activity": Array(payload)])

        default:
            // /api/contacts/:id/...
            if req.method == "GET", req.path.hasPrefix("/api/contacts/") {
                let id = decodeID(req.path.replacingOccurrences(of: "/api/contacts/", with: ""))
                guard let c = appState.contacts.first(where: { $0.id == id }) else {
                    return .json(404, ["error": "contact not found"])
                }
                var messages: [[String: Any]] = []
                if let history = try? appState.dbService.fetchUnifiedHistory(forHandles: c.handles, limit: 25) {
                    messages = history.map { m in
                        [
                            "text": m.displayText,
                            "isFromMe": m.isFromMe,
                            "service": m.service,
                            "date": ISO8601DateFormatter().string(from: m.date)
                        ]
                    }
                }
                return .json(200, [
                    "id": c.id,
                    "name": c.displayName,
                    "handles": c.handles,
                    "enabled": c.isEnabled,
                    "draft": c.currentDraft as Any,
                    "preferredHandle": c.preferredHandle as Any,    // user's manual pick (nullable)
                    "activeHandle": appState.activeHandle(for: c) as Any,  // what's actually used
                    "autoHandle": appState.autoPickedHandle(for: c) as Any, // what auto would pick
                    "smartMode": c.smartMode.rawValue,
                    "memory": [
                        "summary": c.memory.summary,
                        "facts": c.memory.facts,
                        "openLoops": c.memory.openLoops,
                        "preferences": c.memory.preferences
                    ],
                    "messages": messages
                ])
            }

            if req.method == "POST", req.path.hasSuffix("/handle/reset") {
                let id = decodeID(req.path.replacingOccurrences(of: "/api/contacts/", with: "").replacingOccurrences(of: "/handle/reset", with: ""))
                appState.resetPreferredHandle(for: id)
                return .json(200, ["preferredHandle": NSNull()])
            }

            if req.method == "POST", req.path.hasSuffix("/handle") {
                let id = decodeID(req.path.replacingOccurrences(of: "/api/contacts/", with: "").replacingOccurrences(of: "/handle", with: ""))
                let body = (try? JSONSerialization.jsonObject(with: req.body) as? [String: Any]) ?? [:]
                if let handle = body["handle"] as? String {
                    appState.setPreferredHandle(handle, for: id)
                    return .json(200, ["preferredHandle": handle])
                }
                return .json(400, ["error": "missing handle"])
            }

            if req.method == "POST", req.path.hasSuffix("/mode") {
                let id = decodeID(req.path.replacingOccurrences(of: "/api/contacts/", with: "").replacingOccurrences(of: "/mode", with: ""))
                let body = (try? JSONSerialization.jsonObject(with: req.body) as? [String: Any]) ?? [:]
                if let modeStr = body["mode"] as? String,
                   let mode = Contact.SmartMode(rawValue: modeStr) {
                    appState.setSmartMode(mode, for: id)
                    return .json(200, ["mode": mode.rawValue])
                }
                return .json(400, ["error": "invalid mode"])
            }

            if req.method == "POST", req.path.hasSuffix("/toggle") {
                let id = decodeID(req.path.replacingOccurrences(of: "/api/contacts/", with: "").replacingOccurrences(of: "/toggle", with: ""))
                appState.toggleContact(id)
                let enabled = appState.contacts.first(where: { $0.id == id })?.isEnabled ?? false
                return .json(200, ["enabled": enabled])
            }

            if req.method == "POST", req.path.hasSuffix("/regenerate") {
                let id = decodeID(req.path.replacingOccurrences(of: "/api/contacts/", with: "").replacingOccurrences(of: "/regenerate", with: ""))
                await appState.regenerateDraft(for: id)
                let draft = appState.contacts.first(where: { $0.id == id })?.currentDraft ?? ""
                return .json(200, ["draft": draft])
            }

            if req.method == "POST", req.path.hasSuffix("/send") {
                let id = decodeID(req.path.replacingOccurrences(of: "/api/contacts/", with: "").replacingOccurrences(of: "/send", with: ""))
                let body = (try? JSONSerialization.jsonObject(with: req.body) as? [String: Any]) ?? [:]
                if let text = body["text"] as? String, !text.isEmpty {
                    if let idx = appState.contacts.firstIndex(where: { $0.id == id }) {
                        appState.contacts[idx].currentDraft = text
                    }
                }
                await appState.sendDraft(for: id)
                if let err = appState.lastSendError {
                    return .json(400, ["error": err])
                }
                return .json(200, ["sent": true, "info": appState.lastSendInfo ?? ""])
            }

            return .json(404, ["error": "not found", "path": req.path])
        }
    }

    private func decodeID(_ s: String) -> String {
        s.removingPercentEncoding ?? s
    }
}

// MARK: - HTTP types

struct HTTPRequest {
    let method: String
    let path: String
    let query: [String: String]
    let headers: [String: String]
    let body: Data

    static func parse(_ data: Data) -> HTTPRequest? {
        guard let raw = String(data: data, encoding: .utf8) else { return nil }
        guard let headerEnd = raw.range(of: "\r\n\r\n") else { return nil }

        let headerBlock = String(raw[..<headerEnd.lowerBound])
        let lines = headerBlock.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { return nil }
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 3 else { return nil }

        let method = parts[0]
        let fullPath = parts[1]
        var path = fullPath
        var query: [String: String] = [:]
        if let qIdx = fullPath.firstIndex(of: "?") {
            path = String(fullPath[..<qIdx])
            let qs = String(fullPath[fullPath.index(after: qIdx)...])
            for pair in qs.components(separatedBy: "&") {
                let kv = pair.components(separatedBy: "=")
                if kv.count == 2 {
                    query[kv[0]] = kv[1].removingPercentEncoding ?? kv[1]
                }
            }
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if let colon = line.firstIndex(of: ":") {
                let k = String(line[..<colon]).lowercased().trimmingCharacters(in: .whitespaces)
                let v = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                headers[k] = v
            }
        }

        let bodyStartByte = (headerBlock.utf8.count) + 4
        let body: Data
        if bodyStartByte < data.count {
            body = data.subdata(in: bodyStartByte..<data.count)
        } else {
            body = Data()
        }

        // Check Content-Length to ensure body is complete
        if let cl = headers["content-length"], let expected = Int(cl), body.count < expected {
            return nil
        }

        return HTTPRequest(method: method, path: path, query: query, headers: headers, body: body)
    }
}

struct HTTPResponse {
    let status: Int
    let headers: [String: String]
    let body: Data

    static func json(_ status: Int, _ obj: [String: Any]) -> HTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: obj, options: .fragmentsAllowed)) ?? Data()
        return HTTPResponse(
            status: status,
            headers: [
                "Content-Type": "application/json; charset=utf-8",
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Headers": "Authorization, Content-Type"
            ],
            body: data
        )
    }

    static func html(_ status: Int, _ body: String) -> HTTPResponse {
        let data = body.data(using: .utf8) ?? Data()
        return HTTPResponse(
            status: status,
            headers: ["Content-Type": "text/html; charset=utf-8"],
            body: data
        )
    }

    func serialize() -> Data {
        let statusText = HTTPResponse.statusMessage(status)
        var head = "HTTP/1.1 \(status) \(statusText)\r\n"
        var allHeaders = headers
        allHeaders["Content-Length"] = "\(body.count)"
        allHeaders["Connection"] = "close"
        for (k, v) in allHeaders {
            head += "\(k): \(v)\r\n"
        }
        head += "\r\n"
        var data = head.data(using: .utf8) ?? Data()
        data.append(body)
        return data
    }

    private static func statusMessage(_ code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        case 500: return "Internal Server Error"
        default: return "Status"
        }
    }
}
