import Foundation
import Network

/// Lokaler HTTP-Mock für `player_api.php`, nur auf Loopback (127.0.0.1 bzw. ::1).
///
/// Wird von den B01-QA-Tests benutzt, um den **tatsächlichen Payload** der App mitzuschreiben:
/// Jede Anfrage wird so gespeichert, wie sie über TCP ankam (Request-Zeile, Kopfzeilen).
/// Ausschließlich erfundene Zugangsdaten (`qa-user` / `qa-pass-…`), kein echter Anbieter.
final class MockXtreamServer: @unchecked Sendable {

    struct Request: Sendable {
        /// Roh empfangene Request-Zeile, z. B. `GET /player_api.php?username=… HTTP/1.1`
        let requestLine: String
        let method: String
        /// Request-Target genau wie empfangen (Pfad + roher Query-String)
        let target: String
        let path: String
        let rawQuery: String?
        /// Kopfzeilen, Schlüssel kleingeschrieben
        let headers: [String: String]
        /// Lokaler Port, auf dem die Anfrage ankam
        let port: UInt16

        /// Query so dekodiert, wie ein PHP-Panel sie liest (`+` → Leerzeichen, `%XX`; letzter Wert gewinnt).
        var phpQuery: [String: String] {
            var result: [String: String] = [:]
            guard let rawQuery else { return result }
            for pair in rawQuery.split(separator: "&", omittingEmptySubsequences: true) {
                let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let key = Self.phpURLDecode(String(kv[0]))
                let value = kv.count > 1 ? Self.phpURLDecode(String(kv[1])) : ""
                result[key] = value
            }
            return result
        }

        /// Query nach RFC 3986 dekodiert (`+` bleibt `+`).
        var rfcQuery: [String: String] {
            var result: [String: String] = [:]
            guard let rawQuery else { return result }
            for pair in rawQuery.split(separator: "&", omittingEmptySubsequences: true) {
                let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let key = String(kv[0]).removingPercentEncoding ?? String(kv[0])
                let value = kv.count > 1 ? (String(kv[1]).removingPercentEncoding ?? String(kv[1])) : ""
                result[key] = value
            }
            return result
        }

        var action: String? { phpQuery["action"] }
        var username: String? { phpQuery["username"] }
        var password: String? { phpQuery["password"] }

        static func phpURLDecode(_ s: String) -> String {
            let plusDecoded = s.replacingOccurrences(of: "+", with: " ")
            return plusDecoded.removingPercentEncoding ?? plusDecoded
        }
    }

    indirect enum Reply {
        case json(Any, status: Int)
        case raw(status: Int, contentType: String, body: Data)
        case redirect(location: String, status: Int)
        /// Verbindung annehmen, nie antworten
        case hang
        /// Kopfzeilen sofort, danach der Body in `chunks` Stücken, je `interval` Sekunden eines
        case trickle(body: Data, chunks: Int, interval: TimeInterval)
        case delayed(TimeInterval, Reply)
        /// Antwort ohne `Content-Length`; der Body endet mit dem Schließen der Verbindung (Build B01, BUG-08)
        case unsized(body: Data)

        static func json(_ object: Any) -> Reply { .json(object, status: 200) }
    }

    // MARK: - Standardantworten eines funktionierenden Panels

    static let okAuth: [String: Any] = [
        "user_info": ["auth": 1, "status": "Active"],
        // Absichtlich fremder Host: Die App muss trotzdem den eingegebenen Host benutzen (AK-15).
        "server_info": ["url": "evil.example", "port": "80"]
    ]
    static let categories: [[String: Any]] = [
        ["category_id": "1", "category_name": "News"],
        ["category_id": "2", "category_name": "Sport"],
        ["category_id": "1", "category_name": "News-Duplikat"]
    ]
    static let streams: [[String: Any]] = [
        ["name": "Kanal Int", "stream_id": 101, "stream_icon": "http://logos.example/a.png",
         "epg_channel_id": "kanal.int", "category_id": "1"],
        ["name": "Kanal String", "stream_id": "102", "stream_icon": "", "epg_channel_id": "", "category_id": "2"],
        ["name": "Kanal ohne Kategorie", "stream_id": 103, "stream_icon": NSNull(), "epg_channel_id": NSNull(),
         "category_id": NSNull()],
        ["name": "Kanal unbekannte Kategorie", "stream_id": 104, "category_id": "99"]
    ]

    /// Verhalten eines funktionierenden Panels mit `streams`.
    static func panel(streams: [[String: Any]] = MockXtreamServer.streams,
                      categories: Any = MockXtreamServer.categories,
                      auth: Any = MockXtreamServer.okAuth) -> @Sendable (Request) -> Reply {
        let s = streams as NSArray
        let c = categories
        let a = auth
        return { req in
            guard req.path == "/player_api.php" else { return .raw(status: 404, contentType: "text/plain", body: Data()) }
            switch req.action {
            case nil: return .json(a, status: 200)
            case "get_live_categories": return .json(c, status: 200)
            case "get_live_streams": return .json(s, status: 200)
            default: return .json([Any](), status: 200)
            }
        }
    }

    // MARK: - Zustand

    private let queue = DispatchQueue(label: "b01.mockxtream")
    private let lock = NSLock()
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var _requests: [Request] = []
    private var _handler: @Sendable (Request) -> Reply
    private let bindHost: String
    private(set) var port: UInt16 = 0

    init(bindHost: String = "127.0.0.1", handler: @escaping @Sendable (Request) -> Reply = MockXtreamServer.panel()) {
        self.bindHost = bindHost
        self._handler = handler
    }

    var handler: @Sendable (Request) -> Reply {
        get { lock.withLock { _handler } }
        set { lock.withLock { _handler = newValue } }
    }

    var requests: [Request] { lock.withLock { _requests } }
    var apiRequests: [Request] { requests.filter { $0.path == "/player_api.php" } }

    /// `127.0.0.1:<port>` bzw. `[::1]:<port>`
    var hostPort: String {
        bindHost.contains(":") ? "[\(bindHost)]:\(port)" : "\(bindHost):\(port)"
    }

    func resetLog() { lock.withLock { _requests.removeAll() } }

    func start() throws {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(bindHost), port: .any)
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params)
        let ready = DispatchSemaphore(value: 0)
        var failure: Error?
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: ready.signal()
            case .failed(let e): failure = e; ready.signal()
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 5) == .success else {
            throw NSError(domain: "MockXtreamServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Listener nicht bereit"])
        }
        if let failure { throw failure }
        self.listener = listener
        self.port = listener.port?.rawValue ?? 0
    }

    func stop() {
        listener?.cancel()
        listener = nil
        let conns = lock.withLock { () -> [NWConnection] in
            let c = Array(connections.values); connections.removeAll(); return c
        }
        conns.forEach { $0.cancel() }
    }

    // MARK: - Verbindung

    private func accept(_ conn: NWConnection) {
        lock.withLock { connections[ObjectIdentifier(conn)] = conn }
        conn.start(queue: queue)
        receive(conn, buffer: Data())
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buf = buffer
            if let data { buf.append(data) }
            if let end = buf.range(of: Data("\r\n\r\n".utf8)) {
                self.handle(conn, head: buf.subdata(in: buf.startIndex..<end.lowerBound))
            } else if isComplete || error != nil {
                self.close(conn)
            } else {
                self.receive(conn, buffer: buf)
            }
        }
    }

    private func handle(_ conn: NWConnection, head: Data) {
        let text = String(decoding: head, as: UTF8.self)
        var lines = text.components(separatedBy: "\r\n")
        let requestLine = lines.isEmpty ? "" : lines.removeFirst()
        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        let method = parts.first ?? ""
        let target = parts.count > 1 ? parts[1] : ""
        var headers: [String: String] = [:]
        for line in lines {
            guard let idx = line.firstIndex(of: ":") else { continue }
            headers[line[..<idx].lowercased()] = line[line.index(after: idx)...].trimmingCharacters(in: .whitespaces)
        }
        let path: String
        let rawQuery: String?
        if let q = target.firstIndex(of: "?") {
            path = String(target[..<q])
            rawQuery = String(target[target.index(after: q)...])
        } else {
            path = target
            rawQuery = nil
        }
        var localPort: UInt16 = port
        if case .hostPort(_, let p)? = conn.currentPath?.localEndpoint { localPort = p.rawValue }
        let req = Request(requestLine: requestLine, method: method, target: target, path: path,
                          rawQuery: rawQuery, headers: headers, port: localPort)
        lock.withLock { _requests.append(req) }
        respond(conn, handler(req))
    }

    private func respond(_ conn: NWConnection, _ reply: Reply) {
        switch reply {
        case .hang:
            return
        case .delayed(let seconds, let inner):
            queue.asyncAfter(deadline: .now() + seconds) { [weak self] in self?.respond(conn, inner) }
        case .json(let object, let status):
            let body = (try? JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed])) ?? Data()
            send(conn, status: status, headers: ["Content-Type": "application/json"], body: body)
        case .raw(let status, let contentType, let body):
            send(conn, status: status, headers: ["Content-Type": contentType], body: body)
        case .unsized(let body):
            var data = Data("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n".utf8)
            data.append(body)
            conn.send(content: data, completion: .contentProcessed { [weak self] _ in self?.close(conn) })
        case .redirect(let location, let status):
            send(conn, status: status, headers: ["Location": location], body: Data())
        case .trickle(let body, let chunks, let interval):
            let head = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            conn.send(content: Data(head.utf8), completion: .contentProcessed { _ in })
            let size = max(1, Int((Double(body.count) / Double(max(chunks, 1))).rounded(.up)))
            trickle(conn, body: body, offset: 0, size: size, interval: interval)
        }
    }

    private func trickle(_ conn: NWConnection, body: Data, offset: Int, size: Int, interval: TimeInterval) {
        guard offset < body.count else {
            queue.asyncAfter(deadline: .now() + 2) { [weak self] in self?.close(conn) }
            return
        }
        queue.asyncAfter(deadline: .now() + interval) { [weak self] in
            guard let self, self.lock.withLock({ self.connections[ObjectIdentifier(conn)] != nil }) else { return }
            let end = min(body.count, offset + size)
            let piece = body.subdata(in: (body.startIndex + offset)..<(body.startIndex + end))
            conn.send(content: piece, completion: .contentProcessed { _ in })
            self.trickle(conn, body: body, offset: end, size: size, interval: interval)
        }
    }

    private func send(_ conn: NWConnection, status: Int, headers: [String: String], body: Data) {
        var head = "HTTP/1.1 \(status) Mock\r\n"
        for (k, v) in headers { head += "\(k): \(v)\r\n" }
        head += "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var data = Data(head.utf8)
        data.append(body)
        conn.send(content: data, completion: .contentProcessed { [weak self] _ in self?.close(conn) })
    }

    private func close(_ conn: NWConnection) {
        lock.withLock { _ = connections.removeValue(forKey: ObjectIdentifier(conn)) }
        conn.cancel()
    }
}
