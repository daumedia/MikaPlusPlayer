import XCTest
import SwiftData
import CoreData
import Network
import Security
import CryptoKit
@testable import MikaPlusPlayer

// MARK: - Hilfen QA-Durchlauf 2 (sdd-qa B01, 2026-09-16)

/// Roh-TCP-Server auf 127.0.0.1. Schreibt **alle** empfangenen Bytes je Verbindung mit (auch einen TLS-Handshake,
/// den `MockXtreamServer` nicht als Anfrage erkennt) und antwortet mit frei gebauten HTTP-Antworten
/// (eigene Kopfzeilen wie `Set-Cookie`, `Cache-Control`, `Content-Encoding`). Nur Loopback, nur erfundene Daten.
final class B01QA2RawServer: @unchecked Sendable {
    struct Connection {
        var bytes = Data()
        var requestLine: String?
    }
    /// Rückgabe `nil`: Verbindung offen lassen, nicht antworten.
    typealias Handler = @Sendable (_ requestLine: String) -> Data?

    private let queue = DispatchQueue(label: "b01qa2.raw")
    private let lock = NSLock()
    private var listener: NWListener?
    private var open: [ObjectIdentifier: NWConnection] = [:]
    private var logs: [ObjectIdentifier: Connection] = [:]
    private var order: [ObjectIdentifier] = []
    private let handler: Handler
    private(set) var port: UInt16 = 0

    init(handler: @escaping Handler) { self.handler = handler }

    var connections: [Connection] { lock.withLock { order.compactMap { logs[$0] } } }
    var hostPort: String { "127.0.0.1:\(port)" }

    func start() throws {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: params)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.signal() }
            if case .failed = state { ready.signal() }
        }
        listener.newConnectionHandler = { [weak self] c in self?.accept(c) }
        listener.start(queue: queue)
        _ = ready.wait(timeout: .now() + 5)
        self.listener = listener
        port = listener.port?.rawValue ?? 0
        if port == 0 { throw NSError(domain: "B01QA2RawServer", code: 1) }
    }

    func stop() {
        listener?.cancel()
        let conns = lock.withLock { () -> [NWConnection] in let c = Array(open.values); open.removeAll(); return c }
        conns.forEach { $0.cancel() }
    }

    private func accept(_ c: NWConnection) {
        let id = ObjectIdentifier(c)
        lock.withLock { open[id] = c; logs[id] = Connection(); order.append(id) }
        c.start(queue: queue)
        receive(c)
    }

    private func receive(_ c: NWConnection) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            guard let self else { return }
            let id = ObjectIdentifier(c)
            let head = self.lock.withLock { () -> String? in
                if let data { self.logs[id]?.bytes.append(data) }
                guard self.logs[id]?.requestLine == nil, let all = self.logs[id]?.bytes,
                      let end = all.range(of: Data("\r\n\r\n".utf8)) else { return nil }
                let text = String(decoding: all[all.startIndex..<end.lowerBound], as: UTF8.self)
                let line = text.components(separatedBy: "\r\n").first ?? ""
                self.logs[id]?.requestLine = line
                return line
            }
            if let head {
                if let response = self.handler(head) {
                    c.send(content: response, completion: .contentProcessed { _ in c.cancel() })
                }
                return
            }
            if complete || error != nil {
                c.cancel()
                return
            }
            self.receive(c)
        }
    }

    static func http(status: Int = 200, headers: [String: String] = [:], body: Data) -> Data {
        var head = "HTTP/1.1 \(status) QA2\r\n"
        for (k, v) in headers { head += "\(k): \(v)\r\n" }
        head += "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var d = Data(head.utf8)
        d.append(body)
        return d
    }

    /// Antwort eines funktionierenden Panels je nach `action` in der Request-Zeile.
    static func panelBody(_ requestLine: String) -> Data {
        let object: Any
        if requestLine.contains("action=get_live_categories") {
            object = MockXtreamServer.categories
        } else if requestLine.contains("action=get_live_streams") {
            object = MockXtreamServer.streams
        } else {
            object = MockXtreamServer.okAuth
        }
        return (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }
}

enum B01QA2 {
    /// Wie oft kommt `needle` in `data` vor?
    static func occurrences(of needle: String, in data: Data) -> Int {
        let n = Data(needle.utf8)
        var count = 0
        var range = data.startIndex..<data.endIndex
        while let found = data.range(of: n, options: [], in: range) {
            count += 1
            range = found.upperBound..<data.endIndex
        }
        return count
    }

    /// Vorkommen je Datei unter `dir` (rekursiv, auch versteckte Ordner wie `.<Name>_SUPPORT`).
    static func occurrences(of needles: [String], under dir: URL) -> [String: Int] {
        var result: [String: Int] = [:]
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey]) else { return result }
        for case let url as URL in e {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  let data = try? Data(contentsOf: url) else { continue }
            let hits = needles.map { occurrences(of: $0, in: data) }.reduce(0, +)
            let rel = url.path.replacingOccurrences(of: dir.path + "/", with: "")
            result[rel] = hits
        }
        return result
    }

    static func sha256(_ url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else { return "fehlt" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func tempDir(_ label: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("b01-qa2-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Anzahl Schlüsselbund-Einträge eines Dienstes (nur Attribute, nie Inhalte, keine Oberfläche).
    static func keychainCount(service: String) -> Int {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail
        ]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        if status == errSecItemNotFound { return 0 }
        return (out as? [[String: Any]])?.count ?? Int(status)
    }

    /// Legt eine Xtream-Playlist so an, wie v1.1 sie gespeichert hat (Code-Pfad von `c01f1cf` nachgebildet:
    /// `baseURL()` mit http-Zwang, `playerAPIURL()` über `URLQueryItem` ohne `+`-Kodierung, Stream-Adressen per
    /// String-Interpolation und `URL(string:)`).
    static func insertV11Xtream(into ctx: ModelContext, host: String, user: String, pass: String,
                                streams: [(id: String, name: String, favorite: Bool)], name: String) throws -> Playlist {
        var h = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.lowercased().hasPrefix("https://") { h = "http://" + h.dropFirst("https://".count) }
        if !h.lowercased().hasPrefix("http://") { h = "http://" + h }
        while h.hasSuffix("/") { h.removeLast() }
        var comps = try XCTUnwrap(URLComponents(string: h))
        comps.path = ""
        comps.query = nil
        let base = try XCTUnwrap(comps.url)
        var api = comps
        api.path = "/player_api.php"
        api.queryItems = [URLQueryItem(name: "username", value: user), URLQueryItem(name: "password", value: pass)]
        let playlist = Playlist(name: name, sourceURL: api.url, lastRefreshed: Date(), isXtream: true, xtreamOutput: "mpegts")
        ctx.insert(playlist)
        var channels: [Channel] = []
        for s in streams {
            let url = try XCTUnwrap(URL(string: "\(base.absoluteString)/live/\(user)/\(pass)/\(s.id).ts"))
            let channel = Channel(name: s.name, streamURL: url, tvgID: "tvg.\(s.id)", isFavorite: s.favorite, playlistID: playlist.id)
            ctx.insert(channel)
            channels.append(channel)
        }
        playlist.channels = channels
        playlist.channelCount = channels.count
        return playlist
    }

    /// Umgebung für Kindprozesse ohne die Einschleus-Variablen des Test-Hosts.
    static var childEnvironment: [String: String] {
        ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("DYLD_") && !$0.key.hasPrefix("XCTest") && !$0.key.hasPrefix("__XPC_DYLD") }
    }

    @discardableResult
    static func run(_ tool: String, _ args: [String], timeout: TimeInterval = 120) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.environment = childEnvironment
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, "\(error)") }
        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if p.isRunning { p.terminate(); return (-2, "TIMEOUT") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}

// MARK: - Tests

/// B01 · QA-Durchlauf 2: die ursprünglichen Reproduktionen aus Durchlauf 1 erneut und Angriffe auf die neuen
/// Bausteine (Schlüsselbund, Resolver, Persistenz/Migration, Loader, Bremse, Grenzen). Nur Temp-Dateien, eigene
/// Schlüsselbund-Dienste (`…qa2…`), Loopback-Server und erfundene Zugangsdaten.
final class B01QA2Tests: B01MockTestCase {

    private var dirs: [URL] = []
    private var stores: [XtreamCredentialStore] = []

    override func tearDown() {
        for s in stores { try? s.deleteAll() }
        for d in dirs { try? FileManager.default.removeItem(at: d) }
        super.tearDown()
    }

    private func dir(_ label: String) throws -> URL {
        let d = try B01QA2.tempDir(label)
        dirs.append(d)
        return d
    }

    private func store() -> XtreamCredentialStore {
        let s = XtreamCredentialStore(service: "lu.daumedia.MikaPlusPlayer.qa2.tests.\(UUID().uuidString)")
        stores.append(s)
        return s
    }

    // MARK: BUG-01 · ursprüngliche Reproduktion

    /// BUG-01 (AK-24), Reproduktion aus Durchlauf 1: Import in eine Store-Datei, SQLite und Bytefolgen in Store/-wal/-shm
    /// und allen Dateien des Ordners – für Passwort, Benutzername und die prozentkodierte Form. Danach Löschen.
    @MainActor func testQA2_BUG01_OriginalReproduktionKeinKlartextInDateien() async throws {
        let marker = "qa-pass-qa2b01-\(UInt32.random(in: 1000...9999))"
        let user = "qa-user-qa2b01-\(UInt32.random(in: 1000...9999))"
        let specialPass = "\(marker)+#?/%& ä"
        var folder: URL!
        var storeURL: URL!
        do {
            let (container, url, d) = try B01.tempFileContainer("qa2-bug01")
            folder = d; storeURL = url; dirs.append(d)
            let ctx = container.mainContext
            let p1 = try await B01.importXtream(host: mock.hostPort, user: user, pass: marker, context: ctx).get()
            let p2 = try await B01.importXtream(host: "http://qa-u:\(marker)@\(mock.hostPort)", user: user, pass: specialPass, context: ctx).get()
            try ctx.save()
            let encoded = specialPass.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? specialPass
            let needles = [marker, user, encoded, "qa-u:"]
            let sqlPass = B01.sqliteCount(url.path, "select count(*) from ZPLAYLIST where instr(cast(ZSOURCEURL as text), '\(marker)') > 0 or instr(cast(ZNAME as text), '\(marker)') > 0")
            let sqlUser = B01.sqliteCount(url.path, "select count(*) from ZCHANNEL where instr(cast(ZSTREAMURL as text), '\(user)') > 0 or instr(cast(ZSTREAMURL as text), '\(marker)') > 0")
            let files = B01QA2.occurrences(of: needles, under: d)
            print("B01QA2|BUG-01|offen|sqlPlaylist=\(sqlPass ?? -1)|sqlChannel=\(sqlUser ?? -1)|dateien=\(files)")
            XCTAssertEqual(sqlPass, 0)
            XCTAssertEqual(sqlUser, 0)
            XCTAssertEqual(files.values.reduce(0, +), 0, "Zugangsdaten als Bytefolge in \(files)")
            XCTAssertEqual(p1.sourceURL?.absoluteString, "http://\(mock.hostPort)/player_api.php")
            XCTAssertEqual(p2.sourceURL?.absoluteString, "http://\(mock.hostPort)/player_api.php", "Benutzerinfo nicht in der DB")
            let s2 = try XCTUnwrap(try XtreamCredentialStore.standard.load(for: p2.id))
            XCTAssertEqual(s2.password, specialPass)
            XCTAssertEqual(s2.host, "http://qa-u:\(marker)@\(mock.hostPort)")

            // Löschen über den App-Weg: Zeilen und Schlüsselbund-Eintrag weg
            let importer = PlaylistImporter(modelContext: ctx)
            try await importer.delete(p1)
            try await importer.delete(p2)
            XCTAssertNil(try XtreamCredentialStore.standard.load(for: p1.id))
            XCTAssertNil(try XtreamCredentialStore.standard.load(for: p2.id))
            XCTAssertEqual(B01.sqliteCount(url.path, "select count(*) from ZCHANNEL"), 0)
        }
        try await Task.sleep(nanoseconds: 1_500_000_000)
        let after = B01QA2.occurrences(of: [marker, user], under: folder)
        print("B01QA2|BUG-01|geschlossen|store=\(storeURL.lastPathComponent)|dateien=\(after)")
        XCTAssertEqual(after.values.reduce(0, +), 0)
    }

    // MARK: BUG-01/BUG-04 · Produktivpfad beim Start: Übernahme, versioniertes Schema (B09), Umstellung

    /// Klartext-Datenbank wie v1.1 als `default.store` (drei Xtream-Playlists mit Sonderzeichen, eine in v1.1 gelöschte
    /// Xtream-Playlist in freigegebenen Seiten, M3U, Favoriten) → `prepareStore` → `openStore` (B09) →
    /// `migrateCredentials`. Danach: keine Passwort-/Benutzer-Bytefolge in irgendeiner Datei des Ordners, weder offen
    /// noch geschlossen; alte `default.store` samt -wal/-shm weg; Favoriten und abspielbare Adressen erhalten.
    @MainActor func testQA2_BUG01_BUG04_UmstellungKlartextDatenbankUeberStartpfad() async throws {
        let support = try dir("support")
        let bundleID = "lu.daumedia.MikaPlusPlayer"
        let legacy = support.appendingPathComponent("default.store")
        let tag = UInt32.random(in: 1000...9999)
        let marker = "qa-pass-qa2mig-\(tag)"
        let user = "qa-user-qa2mig-\(tag)"
        let passwords = [marker, "\(marker)+x&y=1 ä", "\(marker)%41/z"]
        var legacyPlayable: [String: String] = [:]
        var channelIDs: Set<UUID> = []
        do {
            let container = try ModelContainer(for: B01.schema, configurations: [ModelConfiguration(schema: B01.schema, url: legacy)])
            let ctx = ModelContext(container)
            // in v1.1 angelegt und wieder gelöscht → Klartext nur noch in freigegebenen Seiten / WAL
            let gone = try B01QA2.insertV11Xtream(into: ctx, host: "127.0.0.1:18765", user: user, pass: marker,
                                                   streams: (0..<800).map { ("\($0)", "Weg \($0)", false) }, name: "Gelöscht")
            try ctx.save()
            ctx.delete(gone)
            try ctx.save()
            for (i, pass) in passwords.enumerated() {
                let host = i == 2 ? "http://qa-u:qa-pw@127.0.0.1:18766" : "127.0.0.1:1876\(i)"
                let streams = (0..<300).map { ("\(i)\($0)", "S\(i)-\($0)", $0 % 50 == 0) }
                _ = try B01QA2.insertV11Xtream(into: ctx, host: host, user: user, pass: pass, streams: streams, name: "Alt \(i)")
            }
            let m3u = Playlist(name: "M3U", sourceURL: URL(string: "http://example.com/list.m3u"), lastRefreshed: Date())
            ctx.insert(m3u)
            let mc = Channel(name: "M", streamURL: URL(string: "http://example.com/s.m3u8")!, isFavorite: true, playlistID: m3u.id)
            ctx.insert(mc)
            m3u.channels = [mc]
            m3u.channelCount = 1
            try ctx.save()
            for c in try ctx.fetch(FetchDescriptor<Channel>()) {
                legacyPlayable["\(c.name)"] = c.streamURL.absoluteString
                channelIDs.insert(c.id)
            }
        }
        try await Task.sleep(nanoseconds: 1_500_000_000)
        let before = B01QA2.occurrences(of: [marker], under: support)
        print("B01QA2|MIG|ausgangslage|\(before)")
        XCTAssertGreaterThan(before.values.reduce(0, +), 0, "Ausgangslage: Klartext")

        let kc = store()
        let (storeURL, outcome) = AppPersistence.prepareStore(applicationSupport: support, bundleID: bundleID)
        XCTAssertEqual(outcome, .adopted)
        for suffix in ["", "-wal", "-shm"] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path + suffix), "default.store\(suffix) entfernt")
        }
        let afterCopy = B01QA2.occurrences(of: [marker], under: support)
        print("B01QA2|MIG|nachKopie|\(afterCopy)")

        var favoritesAfter = 0
        do {
            let (container, openOutcome) = AppPersistence.openStore(at: storeURL, schema: AppSchema.schema)
            XCTAssertEqual(openOutcome, .opened)
            let start = Date()
            let result = AppPersistence.migrateCredentials(container: container, storeURL: storeURL, store: kc)
            print("B01QA2|MIG|\(result)|dauer=\(String(format: "%.2f", Date().timeIntervalSince(start)))s")
            XCTAssertEqual(result, AppPersistence.CredentialMigrationResult(migratedPlaylists: 3, rewrittenChannels: 900, failedPlaylists: 0))
            let ctx = container.mainContext
            let channels = try ctx.fetch(FetchDescriptor<Channel>())
            XCTAssertEqual(Set(channels.map(\.id)), channelIDs, "dieselben Sender")
            favoritesAfter = channels.filter(\.isFavorite).count
            var mismatches: [String] = []
            for c in channels where c.playlist?.isXtream == true {
                let playable = try StreamURLResolver.playableURL(for: c, store: kc).absoluteString
                let old = legacyPlayable[c.name] ?? "-"
                // Alt 2: Passwort mit `%41` und `/` war in v1.1 zerlegt; jetzt ein korrekt kodierter Abschnitt
                if c.name.hasPrefix("S2-") {
                    if !playable.contains("/live/\(user)/\(marker)%2541%2Fz/") { mismatches.append(c.name) }
                } else if c.name.hasPrefix("S1-") {
                    // `+ & = ä` und Leerzeichen: v1.1 ließ `+` roh, jetzt je Abschnitt kodiert
                    if URL(string: playable)?.pathComponents.dropFirst(2).prefix(2) != [user, passwords[1]] { mismatches.append(c.name) }
                } else if playable != old {
                    mismatches.append(c.name)
                }
            }
            print("B01QA2|MIG|abweichendeAdressen=\(mismatches.count)|beispiel=\(mismatches.prefix(3))")
            XCTAssertEqual(mismatches, [])
            let open = B01QA2.occurrences(of: [marker, user], under: support)
            print("B01QA2|MIG|offen|\(open)")
            XCTAssertEqual(open.values.reduce(0, +), 0, "Klartext nach Umstellung bei offenem Container: \(open)")
        }
        XCTAssertEqual(favoritesAfter, 19, "18 Xtream-Favoriten + 1 M3U")
        try await Task.sleep(nanoseconds: 1_500_000_000)
        let closed = B01QA2.occurrences(of: [marker, user], under: support)
        print("B01QA2|MIG|geschlossen|\(closed)")
        XCTAssertEqual(closed.values.reduce(0, +), 0)
    }

    /// Angriff auf die Umstellung: In v1.1 wurden **alle** Xtream-Playlists gelöscht, nur eine M3U-Playlist blieb.
    /// Der Klartext steht dann nur noch in freigegebenen Seiten der alten Datei. Wird er bei Übernahme und Start entfernt?
    @MainActor func testQA2_BUG01_KlartextInFreigegebenenSeitenOhneXtreamPlaylist() async throws {
        let support = try dir("freepages")
        let legacy = support.appendingPathComponent("default.store")
        let marker = "qa-pass-qa2free-\(UInt32.random(in: 1000...9999))"
        do {
            let container = try ModelContainer(for: B01.schema, configurations: [ModelConfiguration(schema: B01.schema, url: legacy)])
            let ctx = ModelContext(container)
            let gone = try B01QA2.insertV11Xtream(into: ctx, host: "127.0.0.1:18765", user: "qa-user", pass: marker,
                                                   streams: (0..<2_000).map { ("\($0)", "Weg \($0)", false) }, name: "Gelöscht")
            let m3u = Playlist(name: "M3U bleibt", sourceURL: URL(string: "http://example.com/list.m3u"))
            ctx.insert(m3u)
            try ctx.save()
            ctx.delete(gone)
            try ctx.save()
        }
        try await Task.sleep(nanoseconds: 1_500_000_000)
        let legacyBytes = B01QA2.occurrences(of: [marker], under: support)
        let kc = store()
        let (storeURL, outcome) = AppPersistence.prepareStore(applicationSupport: support, bundleID: "lu.daumedia.MikaPlusPlayer")
        XCTAssertEqual(outcome, .adopted)
        var result = AppPersistence.CredentialMigrationResult()
        var openBytes: [String: Int] = [:]
        do {
            let (container, openOutcome) = AppPersistence.openStore(at: storeURL, schema: AppSchema.schema)
            XCTAssertEqual(openOutcome, .opened)
            result = AppPersistence.migrateCredentials(container: container, storeURL: storeURL, store: kc)
            XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Playlist>()), 1)
            openBytes = B01QA2.occurrences(of: [marker], under: support)
        }
        try await Task.sleep(nanoseconds: 1_500_000_000)
        let closedBytes = B01QA2.occurrences(of: [marker], under: support)
        print("B01QA2|FREEPAGES|vorher=\(legacyBytes)|umstellung=\(result)|offen=\(openBytes)|geschlossen=\(closedBytes)")
        let remaining = closedBytes.values.reduce(0, +)
        if remaining > 0 {
            XCTExpectFailure("BUG-13 · Klartext aus gelöschten v1.1-Xtream-Playlists bleibt nach Übernahme in der neuen Datenbank (kein Verdichten ohne umgestellte Playlist)") {
                XCTAssertEqual(remaining, 0, "Passwort-Bytefolgen nach Start: \(closedBytes)")
            }
        } else {
            XCTAssertEqual(remaining, 0)
        }
    }

    // MARK: BUG-04 · fremde default.store

    /// Fremde App mit Core-Data-Store, deren Entitäten **ebenfalls** `Playlist` und `Channel` heißen (andere Felder),
    /// sowie ein SQLite ohne Core-Data-Metadaten: Weder Übernahme noch der ganze Startpfad (openStore + Umstellung)
    /// verändern die Datei (SHA-256 und Änderungsdatum von default.store/-wal/-shm).
    @MainActor func testQA2_BUG04_FremdeDefaultStoreBleibtUnangetastet() async throws {
        for variant in ["gleicheEntitaetsnamen", "sqliteOhneMetadaten"] {
            let support = try dir("foreign-\(variant)")
            let legacy = support.appendingPathComponent("default.store")
            if variant == "gleicheEntitaetsnamen" {
                let model = NSManagedObjectModel()
                func entity(_ name: String, _ attrs: [String]) -> NSEntityDescription {
                    let e = NSEntityDescription()
                    e.name = name
                    e.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
                    e.properties = attrs.map { a in
                        let p = NSAttributeDescription()
                        p.name = a
                        p.attributeType = .stringAttributeType
                        p.isOptional = true
                        return p
                    }
                    return e
                }
                let playlist = entity("Playlist", ["title", "apiToken"])
                model.entities = [playlist, entity("Channel", ["url"])]
                let psc = NSPersistentStoreCoordinator(managedObjectModel: model)
                let ps = try psc.addPersistentStore(type: .sqlite, at: legacy)
                let ctx = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
                ctx.persistentStoreCoordinator = psc
                let o = NSManagedObject(entity: playlist, insertInto: ctx)
                o.setValue("Fremde App", forKey: "title")
                o.setValue("qa-fremdes-token", forKey: "apiToken")
                try ctx.save()
                try psc.remove(ps)
            } else {
                // SQLite-Datei mit Tabellen ZPLAYLIST/ZCHANNEL, aber ohne Core-Data-Metadaten
                var db: OpaquePointer?
                XCTAssertEqual(sqlite3_open(legacy.path, &db), SQLITE_OK)
                sqlite3_exec(db, "create table ZPLAYLIST(Z_PK integer primary key, ZNAME text); create table ZCHANNEL(Z_PK integer primary key, ZSTREAMURL text); insert into ZPLAYLIST values (1, 'fremd');", nil, nil, nil)
                sqlite3_close(db)
            }
            try await Task.sleep(nanoseconds: 500_000_000)
            let files = ["", "-wal", "-shm"].map { URL(fileURLWithPath: legacy.path + $0) }
            let hashBefore = files.map(B01QA2.sha256)
            let datesBefore = files.map { (try? FileManager.default.attributesOfItem(atPath: $0.path)[.modificationDate]) as? Date }

            let (storeURL, outcome) = AppPersistence.prepareStore(applicationSupport: support, bundleID: "lu.daumedia.MikaPlusPlayer")
            XCTAssertEqual(outcome, .notOurs, variant)
            XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path), "\(variant): keine Kopie")
            // restlicher Startpfad
            do {
                let (container, openOutcome) = AppPersistence.openStore(at: storeURL, schema: AppSchema.schema)
                XCTAssertEqual(openOutcome, .opened)
                _ = AppPersistence.migrateCredentials(container: container, storeURL: storeURL, store: store())
                XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Playlist>()), 0)
            }
            // zweiter Start
            XCTAssertEqual(AppPersistence.prepareStore(applicationSupport: support, bundleID: "lu.daumedia.MikaPlusPlayer").1, .newStoreExists)
            let hashAfter = files.map(B01QA2.sha256)
            let datesAfter = files.map { (try? FileManager.default.attributesOfItem(atPath: $0.path)[.modificationDate]) as? Date }
            print("B01QA2|BUG-04|\(variant)|outcome=\(outcome)|sha256vorher=\(hashBefore.map { String($0.prefix(12)) })|nachher=\(hashAfter.map { String($0.prefix(12)) })")
            // Datenbank und Write-Ahead-Log müssen byte-gleich bleiben. Die -shm-Datei ist SQLites gemeinsamer
            // Speicherindex; jeder lesende Zugriff (hier: Metadaten lesen) darf sie neu schreiben → nur protokolliert.
            XCTAssertEqual(Array(hashAfter.prefix(2)), Array(hashBefore.prefix(2)), "\(variant): default.store/-wal byte-gleich")
            XCTAssertEqual(Array(datesAfter.prefix(2)), Array(datesBefore.prefix(2)), "\(variant): Änderungsdatum unverändert")
            print("B01QA2|BUG-04|\(variant)|shmVeraendert=\(hashAfter[2] != hashBefore[2])")
        }
    }

    /// BUG-04 mit der echten v1.1-Vorlage aus B09 (nur als Temp-Kopie gelesen): Übernahme gelingt, der Startpfad öffnet sie.
    @MainActor func testQA2_BUG04_V11VorlageWirdUebernommen() async throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("B09/Fixtures/v1.1-schema.store")
        guard FileManager.default.fileExists(atPath: fixture.path) else { throw XCTSkip("B09-Vorlage fehlt") }
        let support = try dir("v11")
        try FileManager.default.copyItem(at: fixture, to: support.appendingPathComponent("default.store"))
        let (storeURL, outcome) = AppPersistence.prepareStore(applicationSupport: support, bundleID: "lu.daumedia.MikaPlusPlayer")
        let (container, openOutcome) = AppPersistence.openStore(at: storeURL, schema: AppSchema.schema)
        let names = try container.mainContext.fetch(FetchDescriptor<Playlist>()).map(\.name)
        print("B01QA2|BUG-04|v1.1-Vorlage|\(outcome)|\(openOutcome)|\(names)")
        XCTAssertEqual(outcome, .adopted)
        XCTAssertEqual(openOutcome, .opened)
        XCTAssertEqual(names, ["B09 v1.1 Testliste"])
    }

    // MARK: BUG-02 · ursprüngliche Reproduktion mit roher Mitschrift

    /// BUG-02 (AK-12): `HTTPS://127.0.0.1:<port>` gegen einen Server, der **jedes Byte** mitschreibt. Erwartet: TLS-Handshake
    /// (erstes Byte 0x16), kein Passwort und kein Benutzername im Klartext. Gegenprobe `http://` zeigt, dass die
    /// Mitschrift Klartext erkennt.
    @MainActor func testQA2_BUG02_HTTPSGegenKlartextServerRoheBytes() async throws {
        let raw = B01QA2RawServer { line in B01QA2RawServer.http(body: B01QA2RawServer.panelBody(line)) }
        try raw.start()
        defer { raw.stop() }
        let container = try B01.inMemoryContainer()
        let r = await B01.importXtream(host: "HTTPS://\(raw.hostPort)", user: "qa-user-qa2b02", pass: "qa-pass-qa2b02",
                                       context: container.mainContext, limits: B01.shortIdleLimits)
        try await Task.sleep(nanoseconds: 300_000_000)
        let conns = raw.connections
        let all = conns.reduce(into: Data()) { $0.append($1.bytes) }
        let firstBytes = conns.map { $0.bytes.first.map { String(format: "0x%02x", $0) } ?? "-" }
        print("B01QA2|BUG-02|https|verbindungen=\(conns.count)|ersteBytes=\(firstBytes)|bytes=\(all.count)|pass=\(B01QA2.occurrences(of: "qa-pass-qa2b02", in: all))|user=\(B01QA2.occurrences(of: "qa-user-qa2b02", in: all))|\(B01.message(r) ?? "ok")")
        XCTAssertGreaterThanOrEqual(conns.count, 1, "Verbindungsversuch")
        XCTAssertTrue(conns.allSatisfy { $0.bytes.first == 0x16 }, "TLS-ClientHello erwartet: \(firstBytes)")
        XCTAssertEqual(B01QA2.occurrences(of: "qa-pass-qa2b02", in: all), 0)
        XCTAssertEqual(B01QA2.occurrences(of: "qa-user-qa2b02", in: all), 0)
        XCTAssertEqual(B01QA2.occurrences(of: "player_api", in: all), 0)
        XCTAssertTrue(B01.message(r)?.hasPrefix("Netzwerkfehler: ") ?? false)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Playlist>()), 0)
        XCTAssertEqual(B01QA2.keychainCount(service: XtreamCredentialStore.standard.service), 0, "kein Schlüsselbund-Eintrag")

        // Gegenprobe: ohne Schema (http) liest dieselbe Mitschrift das Passwort
        let r2 = await B01.importXtream(host: raw.hostPort, user: "qa-user-qa2b02", pass: "qa-pass-qa2b02-http", context: container.mainContext)
        let all2 = raw.connections.reduce(into: Data()) { $0.append($1.bytes) }
        print("B01QA2|BUG-02|http-gegenprobe|\(B01.message(r2) ?? "ok")|pass=\(B01QA2.occurrences(of: "qa-pass-qa2b02-http", in: all2))")
        XCTAssertEqual(B01QA2.occurrences(of: "qa-pass-qa2b02-http", in: all2), 3)
    }

    // MARK: BUG-03 · Cache wirklich aus?

    /// BUG-03 (AK-25): Das Panel antwortet cachebar (`Cache-Control: max-age=3600`), setzt ein Cookie und schickt die
    /// Zugangsdaten in `user_info` zurück. Geprüft: ein eigener `URLCache.shared` (Temp-Ordner) bleibt leer, auf der Platte
    /// keine Bytefolge, kein Cookie im gemeinsamen Speicher; die Session des Loaders hat weder Cache noch Zugangsdatenspeicher.
    @MainActor func testQA2_BUG03_KeinCacheKeineCookiesBeimLoader() async throws {
        let marker = "qa-pass-qa2b03-\(UInt32.random(in: 1000...9999))"
        let raw = B01QA2RawServer { line in
            var body = B01QA2RawServer.panelBody(line)
            if !line.contains("action=") {
                body = (try? JSONSerialization.data(withJSONObject: ["user_info": ["auth": 1, "username": "qa-user", "password": marker]])) ?? body
            }
            return B01QA2RawServer.http(headers: ["Content-Type": "application/json", "Cache-Control": "public, max-age=3600",
                                                  "Set-Cookie": "qa2sess=\(marker); Path=/"], body: body)
        }
        try raw.start()
        defer { raw.stop() }
        // Das Test-Cookie lebt im Arbeitsspeicher des gemeinsamen Loaders und würde sonst späteren Tests für 127.0.0.1
        // mitgesendet (Gesamtlauf: B03 Angriff 5).
        defer { PlaylistHTTPLoader.shared.removeCookies(named: { $0 == "qa2sess" }) }
        let cacheDir = try dir("urlcache")
        let original = URLCache.shared
        let probeCache = URLCache(memoryCapacity: 4_000_000, diskCapacity: 20_000_000, directory: cacheDir)
        URLCache.shared = probeCache
        defer { URLCache.shared = original }

        let container = try B01.inMemoryContainer()
        _ = try await B01.importXtream(host: raw.hostPort, pass: marker, context: container.mainContext).get()
        _ = try await B01.importXtream(host: raw.hostPort, pass: marker, context: container.mainContext).get()
        try await Task.sleep(nanoseconds: 3_000_000_000)

        let urls = raw.connections.compactMap { $0.requestLine?.split(separator: " ").dropFirst().first }
            .compactMap { URL(string: "http://\(raw.hostPort)\($0)") }
        let cached = urls.filter { probeCache.cachedResponse(for: URLRequest(url: $0)) != nil }.count
        let diskHits = B01QA2.occurrences(of: [marker], under: cacheDir)
        let sharedCookies = HTTPCookieStorage.shared.cookies?.filter { $0.name == "qa2sess" }.count ?? 0
        let secondRunCookie = raw.connections.suffix(3).filter { String(decoding: $0.bytes, as: UTF8.self).lowercased().contains("cookie: qa2sess") }.count

        let mirror = Mirror(reflecting: XtreamHTTPLoader.shared)
        let session = mirror.children.first { $0.label == "session" }?.value as? URLSession
        let config = session?.configuration
        print("B01QA2|BUG-03|anfragen=\(urls.count)|probeCacheTreffer=\(cached)|probeCacheDiskUsage=\(probeCache.currentDiskUsage)|bytesImCacheOrdner=\(diskHits.values.reduce(0, +))|cookiesShared=\(sharedCookies)|cookieBeimZweitenImport=\(secondRunCookie)|urlCache=\(String(describing: config?.urlCache))|credentialStorage=\(String(describing: config?.urlCredentialStorage))|cookieStorageIstShared=\(config?.httpCookieStorage === HTTPCookieStorage.shared)")
        XCTAssertEqual(urls.count, 6)
        XCTAssertEqual(cached, 0)
        XCTAssertEqual(diskHits.values.reduce(0, +), 0)
        XCTAssertEqual(sharedCookies, 0, "kein Cookie des Panels im gemeinsamen Cookie-Speicher")
        XCTAssertNotNil(config)
        XCTAssertNil(config?.urlCache)
        XCTAssertNil(config?.urlCredentialStorage)
        XCTAssertFalse(config?.httpCookieStorage === HTTPCookieStorage.shared)
    }

    /// BUG-03, Altbestand: `purgeLegacyHTTPCacheOnce` auf einem Cache mit Zugangsdaten. Geprüft werden die **Bytes** in
    /// Cache.db, -wal, -shm und fsCachedData, nicht nur die API.
    func testQA2_BUG03_LeerenEntferntBytefolgenAufDerPlatte() async throws {
        let marker = "qa-pass-qa2purge-\(UInt32.random(in: 1000...9999))"
        let cacheDir = try dir("purge")
        let cache = URLCache(memoryCapacity: 0, diskCapacity: 50_000_000, directory: cacheDir)
        let suite = "lu.daumedia.MikaPlusPlayerTests.qa2.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var requests: [URLRequest] = []
        for (i, size) in [100, 200_000].enumerated() {
            let url = URL(string: "http://127.0.0.1:1/player_api.php?username=qa-user&password=\(marker)&n=\(i)")!
            let req = URLRequest(url: url)
            let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Cache-Control": "max-age=3600"])!
            var body = Data("{\"user_info\":{\"password\":\"\(marker)\"}}".utf8)
            body.append(Data(repeating: 0x20, count: size))
            cache.storeCachedResponse(CachedURLResponse(response: resp, data: body), for: req)
            requests.append(req)
        }
        for _ in 0..<60 where requests.contains(where: { cache.cachedResponse(for: $0) == nil }) {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        try await Task.sleep(nanoseconds: 1_000_000_000)
        let before = B01QA2.occurrences(of: [marker], under: cacheDir)
        XCTAssertTrue(AppPersistence.purgeLegacyHTTPCacheOnce(defaults: defaults, cache: cache))
        try await Task.sleep(nanoseconds: 3_000_000_000)
        let after = B01QA2.occurrences(of: [marker], under: cacheDir)
        let api = requests.filter { cache.cachedResponse(for: $0) != nil }.count
        print("B01QA2|BUG-03|leeren|vorher=\(before)|nachher=\(after)|apiTreffer=\(api)")
        XCTAssertGreaterThan(before.values.reduce(0, +), 0, "Ausgangslage")
        XCTAssertEqual(api, 0)
        XCTAssertEqual(after.values.reduce(0, +), 0, "Zugangsdaten als Bytefolge nach dem Leeren: \(after)")
    }

    // MARK: BUG-05 · ursprüngliche Reproduktion und weitere Sonderzeichen

    /// BUG-05 (AK-14): `qa+pass` gegen ein wie PHP dekodierendes Panel; `a#b`, `a?b`, `a/b` im Stream-Pfad; dazu `%2F`,
    /// `..`, `@`, `:`, `;`, Backslash, Emoji, Tabulator. Anfrage exakt, Stream-Pfad ein Abschnitt mit exakt dem Wert.
    @MainActor func testQA2_BUG05_SonderzeichenInAnfrageUndStreamPfad() async throws {
        let container = try B01.inMemoryContainer()
        var report: [String] = []
        for pass in ["qa+pass", "a#b", "a?b", "a/b", "a%2Fb", "..", "a@b:c;d", "a\\b", "😀 x", "a\tb", "+"] {
            mock.resetLog()
            let panel = MockXtreamServer.panel()
            mock.handler = { req in req.password == pass ? panel(req) : .json(["user_info": ["auth": 0]]) }
            let r = await B01.importXtream(host: mock.hostPort, pass: pass, context: container.mainContext)
            guard case .success(let p) = r else {
                report.append("\(pass.debugDescription): \(B01.message(r) ?? "")")
                continue
            }
            let url = try B01.playable(try XCTUnwrap(p.channels.first { $0.name == "Kanal Int" }))
            let encodedPath = url.absoluteString.replacingOccurrences(of: "http://\(mock.hostPort)", with: "")
            // Pfad so zerlegen, wie ein Server es tut: an rohen `/` trennen, dann je Abschnitt dekodieren
            let segments = encodedPath.split(separator: "/", omittingEmptySubsequences: false).map { $0.removingPercentEncoding ?? String($0) }
            let ok = segments == ["", "live", "qa-user", pass, "101.ts"] && url.query == nil && url.fragment == nil
            report.append("\(pass.debugDescription): \(ok ? "ok" : "FALSCH") \(encodedPath)")
            if pass == ".." {
                // `..` als Abschnitt: Server normalisieren Punktsegmente (RFC 3986 5.2.4) → /live/101.ts
                print("B01QA2|BUG-05|punktsegment|\(encodedPath)|normalisiert=\(URL(string: encodedPath, relativeTo: URL(string: "http://h"))?.standardized.path ?? "-")")
                continue
            }
            XCTAssertTrue(ok, "\(pass.debugDescription) → \(encodedPath)")
        }
        print("B01QA2|BUG-05|\(report)")
        XCTAssertFalse(report.contains { $0.contains("Anmeldung fehlgeschlagen") }, "\(report)")
    }

    // MARK: BUG-06 · ursprüngliche Reproduktion

    /// BUG-06 (EC-11, EC-12) wie in Durchlauf 1: `category_id` als Zahl; ein Stream mit `name: null` neben einem gültigen.
    @MainActor func testQA2_BUG06_OriginalReproduktion() async throws {
        let container = try B01.inMemoryContainer()
        mock.handler = MockXtreamServer.panel(categories: [["category_id": 1, "category_name": "News"]])
        let r1 = await B01.importXtream(host: mock.hostPort, pass: "qa-pass-qa2b06", context: container.mainContext)
        mock.handler = MockXtreamServer.panel(streams: [["name": NSNull(), "stream_id": 1], ["name": "Gültig", "stream_id": 2]])
        let r2 = await B01.importXtream(host: mock.hostPort, pass: "qa-pass-qa2b06", context: container.mainContext)
        print("B01QA2|BUG-06|\(B01.message(r1) ?? "ok")|\(B01.message(r2) ?? "ok")|sender2=\((try? r2.get())?.channelCount ?? -1)")
        XCTAssertEqual(try r1.get().channels.first { $0.name == "Kanal Int" }?.group, "News")
        XCTAssertEqual(try r2.get().channelCount, 2)
    }

    // MARK: BUG-07 · Bremse: Originalweg und Umgehungen

    /// BUG-07: zehn Fehlanmeldungen über den **Standardweg** der App (`PlaylistImporter(modelContext:)` mit
    /// `XtreamLoginThrottle.shared`). Danach Umgehungsversuche: andere Schreibweise des Hosts, Benutzerinfo,
    /// anderer Benutzer, neue Instanz (Neustart).
    @MainActor func testQA2_BUG07_BremseStandardwegUndUmgehungen() async throws {
        mock.handler = MockXtreamServer.panel(auth: ["user_info": ["auth": 0]])
        let container = try B01.inMemoryContainer()
        let importer = PlaylistImporter(modelContext: container.mainContext)
        func attempt(_ host: String, user: String = "qa-user", importer: PlaylistImporter) async -> String {
            do {
                _ = try await importer.importFromXtream(XtreamCredentials(host: host, username: user, password: "qa-pass-falsch"), output: .mpegts, name: "")
                return "ok"
            } catch { return error.localizedDescription }
        }
        var messages: [String] = []
        for _ in 1...10 { messages.append(await attempt(mock.hostPort, importer: importer)) }
        let atPanel = mock.requests.count
        print("B01QA2|BUG-07|standardweg|beimPanel=\(atPanel)|meldungen=\(Set(messages))")
        XCTAssertEqual(atPanel, 3)

        var bypass: [String: Int] = [:]
        for host in ["localhost:\(mock.port)", "LOCALHOST:\(mock.port)", "127.1:\(mock.port)", "http://qa-x@127.0.0.1:\(mock.port)",
                     "127.0.0.1.:\(mock.port)", "[::ffff:127.0.0.1]:\(mock.port)", "0x7f.0.0.1:\(mock.port)"] {
            mock.resetLog()
            let msg = await attempt(host, importer: importer)
            bypass[host] = mock.requests.count
            print("B01QA2|BUG-07|schreibweise|\(host)|beimPanel=\(mock.requests.count)|key=\(XtreamCredentials(host: host, username: "u", password: "p").baseURL().map(XtreamLoginThrottle.key(for:)) ?? "nil")|\(msg)")
        }
        mock.resetLog()
        let otherUser = await attempt(mock.hostPort, user: "qa-anderer-nutzer", importer: importer)
        print("B01QA2|BUG-07|andererBenutzer|beimPanel=\(mock.requests.count)|\(otherUser)")
        XCTAssertEqual(mock.requests.count, 0, "Sperre gilt je Panel, auch für andere Benutzer")
        XCTAssertEqual(bypass["http://qa-x@127.0.0.1:\(mock.port)"], 0, "Benutzerinfo umgeht die Bremse nicht")
        XCTAssertEqual(bypass["LOCALHOST:\(mock.port)"], bypass["localhost:\(mock.port)"])

        // „Neustart": neue Bremse (die App hält sie nur im Arbeitsspeicher)
        mock.resetLog()
        let fresh = PlaylistImporter(modelContext: container.mainContext, loginThrottle: XtreamLoginThrottle())
        _ = await attempt(mock.hostPort, importer: fresh)
        print("B01QA2|BUG-07|neustart|beimPanel=\(mock.requests.count)")
        XCTAssertEqual(mock.requests.count, 1, "nach Neustart wieder erlaubt (Annahme 10: nur im Arbeitsspeicher)")

        // Aufräumen: .shared für diesen Port zurücksetzen
        XtreamLoginThrottle.shared.recordSuccess(for: XtreamLoginThrottle.key(for: URL(string: "http://\(mock.hostPort)")!))
    }

    /// BUG-07 Grenzwerte mit steuerbarer Uhr: 2 frei, 3. → 30 s, 4. → 60, 5. → 120, 6. → 240, 7./8. → 300; bei genau
    /// 30,0 s wieder frei, bei 29,9 s gesperrt. Das Aktualisieren (B03) läuft durch dieselbe Bremse.
    @MainActor func testQA2_BUG07_GrenzwerteUndAktualisieren() async throws {
        let clock = B01TestClock()
        let throttle = XtreamLoginThrottle(now: { clock.now })
        let key = "http://qa.example:80"
        var locks: [Double] = []
        for _ in 1...8 {
            throttle.recordFailure(for: key)
            locks.append(throttle.remainingLock(for: key) ?? 0)
            clock.advance(throttle.remainingLock(for: key) ?? 0)
        }
        print("B01QA2|BUG-07|sperren=\(locks)")
        XCTAssertEqual(locks, [0, 0, 30, 60, 120, 240, 300, 300])
        throttle.recordFailure(for: key)
        clock.advance(299.9)
        XCTAssertNotNil(throttle.remainingLock(for: key))
        clock.advance(0.1)
        XCTAssertNil(throttle.remainingLock(for: key), "bei genau 300,0 s frei")

        // Aktualisieren einer bestehenden Playlist nach drei Fehlanmeldungen gegen dasselbe Panel
        let container = try B01.inMemoryContainer()
        let ctx = container.mainContext
        let shared = XtreamLoginThrottle()
        let p = try await B01.importXtream(host: mock.hostPort, pass: "qa-pass-qa2b07", context: ctx, throttle: shared).get()
        mock.handler = MockXtreamServer.panel(auth: ["user_info": ["auth": 0]])
        for _ in 1...3 { _ = await B01.importXtream(host: mock.hostPort, pass: "qa-pass-falsch", context: ctx, throttle: shared) }
        mock.resetLog()
        var refreshMessage = "ok"
        do { try await PlaylistImporter(modelContext: ctx, loginThrottle: shared).refresh(p) } catch { refreshMessage = error.localizedDescription }
        print("B01QA2|BUG-07|aktualisieren|beimPanel=\(mock.requests.count)|\(refreshMessage)")
        XCTAssertEqual(mock.requests.count, 0)
        XCTAssertTrue(refreshMessage.hasPrefix("Zu viele fehlgeschlagene Anmeldungen"))
    }

    // MARK: BUG-08 · Grenzen genau

    /// BUG-08: Textgrenze 512 Zeichen (Name, Gruppe, tvg-ID; auch mit Emoji), Logo-Adresse 2.048 Zeichen erlaubt, 2.049 verworfen.
    @MainActor func testQA2_BUG08_Textgrenzen() async throws {
        let n512 = String(repeating: "N", count: 512), n513 = String(repeating: "N", count: 513)
        let e513 = String(repeating: "📺", count: 513)
        let logoBase = "http://logos.example/"
        let logo2048 = logoBase + String(repeating: "a", count: 2_048 - logoBase.count)
        let logo2049 = logo2048 + "a"
        mock.handler = MockXtreamServer.panel(
            streams: [
                ["name": n512, "stream_id": 1, "category_id": "g", "epg_channel_id": n513, "stream_icon": logo2048],
                ["name": n513, "stream_id": 2, "stream_icon": logo2049],
                ["name": e513, "stream_id": 3]
            ],
            categories: [["category_id": "g", "category_name": n513]])
        let container = try B01.inMemoryContainer()
        let p = try await B01.importXtream(host: mock.hostPort, pass: "qa-pass-qa2b08", context: container.mainContext).get()
        let byID = Dictionary(uniqueKeysWithValues: p.channels.map { ($0.streamURL.lastPathComponent, $0) })
        let c1 = try XCTUnwrap(byID["1.ts"]), c2 = try XCTUnwrap(byID["2.ts"]), c3 = try XCTUnwrap(byID["3.ts"])
        print("B01QA2|BUG-08|name512=\(c1.name.count)|name513=\(c2.name.count)|emoji513=\(c3.name.count)|gruppe=\(c1.group?.count ?? -1)|tvg=\(c1.tvgID?.count ?? -1)|logo2048=\(c1.logoURL != nil)|logo2049=\(c2.logoURL != nil)")
        XCTAssertEqual(c1.name, n512)
        XCTAssertEqual(c2.name.count, 512)
        XCTAssertEqual(c3.name.count, 512)
        XCTAssertEqual(c1.group?.count, 512)
        XCTAssertEqual(c1.tvgID?.count, 512)
        XCTAssertEqual(c1.logoURL?.absoluteString.count, 2_048)
        XCTAssertNil(c2.logoURL)
    }

    // MARK: BUG-10 · Weiterleitungen angreifen

    /// BUG-10 (AK-26): Weiterleitung auf anderen Port (Originalreproduktion), 307, auf `https` desselben Hosts und Ports,
    /// schemarelativ, mit Benutzerinfo-Trick, auf `[::1]`, und eine Kette A → A (Pfad) → B. Das Ziel erhält nie etwas.
    @MainActor func testQA2_BUG10_WeiterleitungsVarianten() async throws {
        let target = MockXtreamServer()
        try target.start()
        defer { target.stop() }
        let v6 = MockXtreamServer(bindHost: "::1")
        try v6.start()
        defer { v6.stop() }
        let port = mock.port, tport = target.port
        let container = try B01.inMemoryContainer()
        let variants: [(String, @Sendable (MockXtreamServer.Request) -> MockXtreamServer.Reply)] = [
            ("302 anderer Port", { req in .redirect(location: "http://127.0.0.1:\(tport)\(req.target)", status: 302) }),
            ("307 anderer Port", { req in .redirect(location: "http://127.0.0.1:\(tport)\(req.target)", status: 307) }),
            ("308 https gleicher Port", { req in .redirect(location: "https://127.0.0.1:\(port)\(req.target)", status: 308) }),
            ("schemarelativ", { req in .redirect(location: "//127.0.0.1:\(tport)\(req.target)", status: 302) }),
            ("Benutzerinfo-Trick", { req in .redirect(location: "http://127.0.0.1:\(port)@127.0.0.1:\(tport)\(req.target)", status: 302) }),
            ("IPv6 [::1]", { req in .redirect(location: "http://[::1]:\(v6.port)\(req.target)", status: 302) }),
            ("Kette A→A→B", { req in
                req.path == "/player_api.php"
                    ? .redirect(location: "/hop?\(req.rawQuery ?? "")", status: 302)
                    : .redirect(location: "http://127.0.0.1:\(tport)/player_api.php?\(req.rawQuery ?? "")", status: 302)
            })
        ]
        for (label, handler) in variants {
            mock.resetLog(); target.resetLog(); v6.resetLog()
            mock.handler = handler
            let r = await B01.importXtream(host: mock.hostPort, pass: "qa-pass-qa2b10", context: container.mainContext)
            let leaked = target.requests.count + v6.requests.count
            print("B01QA2|BUG-10|\(label)|quelle=\(mock.requests.count)|ziel=\(leaked)|\(B01.message(r) ?? "ok")")
            XCTAssertEqual(leaked, 0, label)
            XCTAssertEqual(B01.message(r), XtreamClient.XtreamError.redirectBlocked.localizedDescription, label)
        }
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Playlist>()), 0)
    }

    // MARK: BUG-11 · Abbrechen im Dienst: auch Schlüsselbund und Bremse

    /// BUG-11: Abbruch während der Kategorien-Anfrage (Anmeldung schon erfolgreich) – keine Playlist, kein
    /// Schlüsselbund-Eintrag, keine Streams-Anfrage.
    @MainActor func testQA2_BUG11_AbbruchNachAnmeldungHinterlaesstNichts() async throws {
        let container = try B01.inMemoryContainer()
        let panel = MockXtreamServer.panel()
        mock.handler = { req in req.action == "get_live_categories" ? .delayed(3, panel(req)) : panel(req) }
        let host = mock.hostPort
        let task = Task { @MainActor () -> String in
            let r = await B01.importXtream(host: host, pass: "qa-pass-qa2b11", context: container.mainContext)
            if case .failure(let e) = r { return e is CancellationError ? "CancellationError" : e.localizedDescription }
            return "ok"
        }
        try await Task.sleep(nanoseconds: 800_000_000)
        task.cancel()
        let outcome = await task.value
        try await Task.sleep(nanoseconds: 3_500_000_000)
        print("B01QA2|BUG-11|nachAnmeldung|\(outcome)|anfragen=\(mock.requests.map { $0.action ?? "(ohne)" })|schluesselbund=\(B01QA2.keychainCount(service: XtreamCredentialStore.standard.service))")
        XCTAssertEqual(outcome, "CancellationError")
        XCTAssertEqual(mock.requests.map { $0.action ?? "(ohne)" }, ["(ohne)", "get_live_categories"])
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Playlist>()), 0)
        XCTAssertEqual(B01QA2.keychainCount(service: XtreamCredentialStore.standard.service), 0)
    }

    // MARK: StreamURLResolver angreifen

    /// Resolver: fehlender Eintrag, beschädigter Eintrag (kein JSON, JSON ohne Feld), manipulierte Datenbank-Adressen
    /// (Host darf nie aus der Datenbank kommen), M3U unverändert, Sonderzeichen und 10.000 Zeichen im Schlüsselbund.
    @MainActor func testQA2_Resolver_FehlendBeschaedigtManipuliertSonderzeichen() async throws {
        let kc = store()
        let container = try B01.inMemoryContainer()
        let ctx = container.mainContext
        let playlist = Playlist(name: "X", sourceURL: URL(string: "http://panel.example:8080/player_api.php"), isXtream: true, xtreamOutput: "mpegts")
        ctx.insert(playlist)
        let channel = Channel(name: "K", streamURL: URL(string: "http://panel.example:8080/live/101.ts")!, playlistID: playlist.id)
        ctx.insert(channel)
        playlist.channels = [channel]
        try ctx.save()

        // fehlt
        XCTAssertThrowsError(try StreamURLResolver.playableURL(for: channel, store: kc)) { e in
            XCTAssertEqual(e as? StreamURLResolver.ResolveError, .missingCredentials)
            print("B01QA2|RESOLVER|fehlt|\(e.localizedDescription)")
        }
        // beschädigt: kein JSON bzw. JSON ohne Passwort
        for (label, data) in [("keinJSON", Data("qa-kaputt".utf8)), ("ohnePasswort", Data("{\"host\":\"http://panel.example:8080\",\"username\":\"qa-user\"}".utf8))] {
            let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: kc.service,
                                    kSecAttrAccount as String: playlist.id.uuidString]
            SecItemDelete(q as CFDictionary)
            var add = q
            add[kSecValueData as String] = data
            XCTAssertEqual(SecItemAdd(add as CFDictionary, nil), errSecSuccess)
            XCTAssertThrowsError(try StreamURLResolver.playableURL(for: channel, store: kc)) { e in
                print("B01QA2|RESOLVER|\(label)|\(e.localizedDescription)")
                XCTAssertEqual(e.localizedDescription, "Die gespeicherten Zugangsdaten sind beschädigt. Bitte die Playlist neu importieren.")
            }
        }
        // gültig
        let secret = XtreamSecret(host: "http://panel.example:8080", username: "qa-user", password: "qa-pass-qa2res")
        try kc.save(secret, for: playlist.id)
        XCTAssertEqual(try StreamURLResolver.playableURL(for: channel, store: kc).absoluteString,
                       "http://panel.example:8080/live/qa-user/qa-pass-qa2res/101.ts")

        // manipulierte Datenbank-Adressen: der Host kommt immer aus dem Schlüsselbund
        var hosts: [String: String] = [:]
        for stored in ["http://evil.example/live/101.ts", "http://panel.example:8080/live/@evil.example/1.ts",
                       "http://panel.example:8080/live///evil.example/1.ts", "http://panel.example:8080/live/..%2F..%2Fevil/1.ts",
                       "http://evil.example/x/live/1.ts?u=http://evil.example", "http://panel.example:8080/live/1.ts#@evil.example"] {
            channel.streamURL = URL(string: stored)!
            let url = try StreamURLResolver.playableURL(for: channel, store: kc)
            hosts[stored] = "\(url.host ?? "-"):\(url.port ?? 0)"
            XCTAssertEqual(url.host, "panel.example", stored)
            XCTAssertEqual(url.port, 8080, stored)
        }
        print("B01QA2|RESOLVER|manipuliert|\(hosts)")
        // Datenbank ohne /live/ → ungültig statt Durchreichen
        channel.streamURL = URL(string: "http://evil.example/stream.ts")!
        XCTAssertThrowsError(try StreamURLResolver.playableURL(for: channel, store: kc)) { e in
            XCTAssertEqual(e as? StreamURLResolver.ResolveError, .invalidAddress)
        }
        // Altbestand-Weg: Datenbank täuscht eine alte Adresse vor → Durchreichen der gespeicherten Adresse, kein Geheimnis
        channel.streamURL = URL(string: "http://panel.example:8080/live/101.ts")!
        playlist.sourceURL = URL(string: "http://evil.example/player_api.php?username=a&password=b")
        let passthrough = try StreamURLResolver.playableURL(for: channel, store: kc)
        print("B01QA2|RESOLVER|altbestandVorgetaeuscht|\(passthrough.absoluteString)")
        XCTAssertFalse(passthrough.absoluteString.contains("qa-pass-qa2res"))
        playlist.sourceURL = URL(string: "http://panel.example:8080/player_api.php")

        // M3U unverändert, ohne Schlüsselbund
        let m3u = Playlist(name: "M", sourceURL: URL(string: "http://example.com/l.m3u"))
        ctx.insert(m3u)
        let mc = Channel(name: "M", streamURL: URL(string: "http://example.com/live/1.ts")!, playlistID: m3u.id)
        ctx.insert(mc)
        m3u.channels = [mc]
        XCTAssertEqual(try StreamURLResolver.playableURL(for: mc, store: kc).absoluteString, "http://example.com/live/1.ts")

        // Sonderzeichen und Länge im Schlüsselbund
        let printable = String((32...126).compactMap { UnicodeScalar($0).map(Character.init) })
        for (u, pw) in [(printable, printable), ("ä ö 😀", "\u{0}\n\r"), ("", ""), ("qa-user", String(repeating: "x", count: 10_000))] {
            try kc.save(XtreamSecret(host: "http://panel.example:8080", username: u, password: pw), for: playlist.id)
            let url = try StreamURLResolver.playableURL(for: channel, store: kc)
            let path = url.absoluteString.replacingOccurrences(of: "http://panel.example:8080", with: "")
            let segments = path.split(separator: "/", omittingEmptySubsequences: false).map { $0.removingPercentEncoding ?? String($0) }
            XCTAssertEqual(segments, ["", "live", u, pw, "101.ts"], "\(u.prefix(20).debugDescription)")
            XCTAssertEqual(url.host, "panel.example")
        }
    }

    // MARK: Schlüsselbund aus Sicht eines fremden Prozesses

    private static let probeSource = #"""
    import Foundation
    import Security
    let args = CommandLine.arguments
    let cmd = args[1], service = args[2]
    let account = args.count > 3 ? args[3] : ""
    precondition(service.contains(".qa2."), "nur QA-Testdienste")
    SecKeychainSetUserInteractionAllowed(false)
    func base() -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail]
        if !account.isEmpty { q[kSecAttrAccount as String] = account }
        return q
    }
    switch cmd {
    case "add":
        var q = base()
        q[kSecValueData as String] = try! Data(contentsOf: URL(fileURLWithPath: args[4]))
        q[kSecAttrLabel as String] = "Mika+Player – Xtream-Zugang"
        print("ADD status=\(SecItemAdd(q as CFDictionary, nil))")
    case "read":
        var q = base()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let st = SecItemCopyMatching(q as CFDictionary, &out)
        let text = (out as? Data).map { String(decoding: $0, as: UTF8.self) } ?? ""
        print("READ status=\(st) bytes=\((out as? Data)?.count ?? 0) marker=\(text.contains(args[4]))")
    case "attrs":
        var q = base()
        q[kSecReturnAttributes as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitAll
        var out: CFTypeRef?
        let st = SecItemCopyMatching(q as CFDictionary, &out)
        for item in (out as? [[String: Any]]) ?? [] {
            print("ATTR keys=\(item.keys.sorted().joined(separator: ",")) label=\(item[kSecAttrLabel as String] ?? "-") pdmn=\(item[kSecAttrAccessible as String] ?? "-")")
        }
        print("ATTRS status=\(st)")
    case "delete":
        print("DELETE status=\(SecItemDelete(base() as CFDictionary))")
    case "acl":
        var q = base()
        q[kSecReturnRef as String] = true
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let ref = out else { print("ACL none"); exit(0) }
        var access: SecAccess?
        guard SecKeychainItemCopyAccess(ref as! SecKeychainItem, &access) == errSecSuccess, let access else { print("ACL noaccess"); exit(0) }
        var list: CFArray?
        SecAccessCopyACLList(access, &list)
        for acl in (list as? [SecACL]) ?? [] {
            var apps: CFArray?; var desc: CFString?; var sel = SecKeychainPromptSelector()
            SecACLCopyContents(acl, &apps, &desc, &sel)
            let auths = ((SecACLCopyAuthorizations(acl) as? [String]) ?? []).map { $0.replacingOccurrences(of: "ACLAuthorization", with: "") }
            var paths: [String] = ["<alle>"]
            if let apps = apps as? [SecTrustedApplication] {
                paths = apps.map { a in var d: CFData?; SecTrustedApplicationCopyData(a, &d); return (d as Data?).map { String(decoding: $0, as: UTF8.self).trimmingCharacters(in: CharacterSet(charactersIn: "\u{0}")) } ?? "?" }
            }
            print("ACL auths=\(auths) apps=\(paths)")
        }
    default: exit(2)
    }
    """#

    /// Übersetzt die Sonde (eigenes, ad hoc signiertes Programm = „fremder Prozess" bzw. „anderer Build").
    private func compileProbe() throws -> URL {
        let xcrun = "/usr/bin/xcrun"
        guard FileManager.default.isExecutableFile(atPath: xcrun) else { throw XCTSkip("xcrun fehlt") }
        let work = try dir("kcprobe")
        let src = work.appendingPathComponent("kcprobe.swift")
        try Self.probeSource.write(to: src, atomically: true, encoding: .utf8)
        let exe = work.appendingPathComponent("kcprobe")
        let compile = B01QA2.run(xcrun, ["swiftc", "-O", "-o", exe.path, src.path], timeout: 300)
        guard compile.status == 0 else { throw XCTSkip("Sonde nicht übersetzbar: \(compile.output.prefix(300))") }
        return exe
    }

    /// nur die Ergebniszeilen der Sonde (stderr-Rauschen des Systems herausfiltern)
    private func probe(_ exe: URL, _ args: String...) -> String {
        B01QA2.run(exe.path, args, timeout: 30).output.split(separator: "\n")
            .filter { ["READ", "ATTR", "ACL", "ADD", "DELETE"].contains(where: $0.hasPrefix) }
            .joined(separator: "\n")
    }

    /// Update-Szenario (OF-08, ad hoc signiert): Der Schlüsselbund-Eintrag einer Playlist stammt von einem **anderen Build**
    /// (hier: die Sonde). Die App löscht die Playlist über ihren Weg (`PlaylistImporter.delete`, aus `PlaylistsView`
    /// mit `try?`). Die Freigabe-Oberfläche bleibt **erlaubt** (Normalfall der App). Wird der Eintrag entfernt?
    @MainActor func testQA2_Schluesselbund_A_LoeschenEintragAndererBuild() async throws {
        let exe = try compileProbe()
        let kc = store()
        let container = try B01.inMemoryContainer()
        let ctx = container.mainContext
        let playlist = Playlist(name: "Update", sourceURL: URL(string: "http://panel.example/player_api.php"), isXtream: true, xtreamOutput: "mpegts")
        ctx.insert(playlist)
        let channel = Channel(name: "K", streamURL: URL(string: "http://panel.example/live/1.ts")!, playlistID: playlist.id)
        ctx.insert(channel)
        playlist.channels = [channel]
        try ctx.save()
        let marker = "qa-pass-qa2upd-\(UInt32.random(in: 1000...9999))"
        let json = try dir("kcjson").appendingPathComponent("secret.json")
        try JSONEncoder().encode(XtreamSecret(host: "http://panel.example", username: "qa-user", password: marker)).write(to: json)
        let added = probe(exe, "add", kc.service, playlist.id.uuidString, json.path)
        print("B01QA2|KC|andererBuildAnlegen|\(added)")
        XCTAssertEqual(added, "ADD status=0")
        defer { print("B01QA2|KC|aufraeumenSonde|\(probe(exe, "delete", kc.service, playlist.id.uuidString))") }

        var deleteError = "ok"
        do { try await PlaylistImporter(modelContext: ctx, credentialStore: kc).delete(playlist) } catch { deleteError = error.localizedDescription }
        let left = B01QA2.keychainCount(service: kc.service)
        let playlists = try ctx.fetchCount(FetchDescriptor<Playlist>())
        print("B01QA2|KC|loeschenPlaylistEintragAndererBuild|\(deleteError)|verbleibendeEintraege=\(left)|playlists=\(playlists)")
        XCTAssertEqual(playlists, 0, "Playlist ist aus der Datenbank verschwunden")
        if left > 0 {
            XCTExpectFailure("BUG-14 · Löschen einer Xtream-Playlist entfernt den Schlüsselbund-Eintrag eines anderen Builds nicht (-25244); PlaylistsView verwirft den Fehler, das Passwort bleibt verwaist im Schlüsselbund") {
                XCTAssertEqual(left, 0)
            }
        }
    }

    /// Schlüsselbund aus Sicht eines **fremden Prozesses** desselben Nutzers (Sonde ohne Oberfläche): Was steht wo
    /// (Attribute, Zugriffsliste, Zugriffsklasse)? Lesen ohne Freigabe? Löschen? Dazu: Die App liest einen Eintrag eines
    /// anderen Builds ohne Freigabe nicht (OF-08) und meldet das ohne Zugangsdaten.
    @MainActor func testQA2_Schluesselbund_FremderProzessUndAndererBuild() async throws {
        let exe = try compileProbe()
        let kc = store()

        // 1) Eintrag der App (Test-Host) – fremder Prozess liest, listet, prüft Zugriffsliste, löscht
        let id = UUID()
        let marker = "qa-pass-qa2kc-\(UInt32.random(in: 1000...9999))"
        try kc.save(XtreamSecret(host: "http://panel.example", username: "qa-user", password: marker), for: id)
        let read = probe(exe, "read", kc.service, id.uuidString, marker)
        let attrs = probe(exe, "attrs", kc.service)
        let acl = probe(exe, "acl", kc.service, id.uuidString)
        print("B01QA2|KC|fremdLesen|\(read)")
        print("B01QA2|KC|fremdAttribute|\(attrs.replacingOccurrences(of: "\n", with: " ¶ "))")
        print("B01QA2|KC|zugriffsliste|\(acl.replacingOccurrences(of: "\n", with: " ¶ ").replacingOccurrences(of: Bundle.main.bundlePath, with: "<Test-Host>"))")
        XCTAssertTrue(read.hasPrefix("READ status=-"), "fremder Prozess darf ohne Freigabe nicht lesen: \(read)")
        XCTAssertTrue(read.contains("marker=false"))
        XCTAssertFalse(attrs.contains(marker))
        XCTAssertFalse(attrs.contains("panel.example"), "Host steht nicht in den lesbaren Attributen")
        XCTAssertTrue(attrs.contains("pdmn=-"), "Zugriffsklasse wird im Anmelde-Schlüsselbund nicht gespeichert")
        XCTAssertTrue(acl.contains("Decrypt"))
        let del = probe(exe, "delete", kc.service, id.uuidString)
        print("B01QA2|KC|fremdLoeschenOhneOberflaeche|\(del)|danachLadbar=\((try? kc.load(for: id)) != nil)")

        // 2) Eintrag eines anderen Builds: App liest ohne Oberfläche
        let other = UUID()
        let json = try dir("kcjson2").appendingPathComponent("secret.json")
        try JSONEncoder().encode(XtreamSecret(host: "http://panel.example", username: "qa-user", password: marker)).write(to: json)
        XCTAssertEqual(probe(exe, "add", kc.service, other.uuidString, json.path), "ADD status=0")
        defer { _ = probe(exe, "delete", kc.service, other.uuidString) }
        let container = try B01.inMemoryContainer()
        let ctx = container.mainContext
        let playlist = Playlist(id: other, name: "Update", sourceURL: URL(string: "http://panel.example/player_api.php"), isXtream: true, xtreamOutput: "mpegts")
        ctx.insert(playlist)
        let channel = Channel(name: "K", streamURL: URL(string: "http://panel.example/live/1.ts")!, playlistID: playlist.id)
        ctx.insert(channel)
        playlist.channels = [channel]
        var resolverMessage = "ok"
        SecKeychainSetUserInteractionAllowed(false)
        do { _ = try StreamURLResolver.playableURL(for: channel, store: kc) } catch { resolverMessage = error.localizedDescription }
        SecKeychainSetUserInteractionAllowed(true)
        print("B01QA2|KC|appLiestEintragAndererBuildOhneOberflaeche|\(resolverMessage)")
        XCTAssertTrue(resolverMessage.hasPrefix("Der Schlüsselbund hat den Zugriff auf die Zugangsdaten verweigert"), resolverMessage)
        XCTAssertFalse(resolverMessage.contains(marker))
    }

    // MARK: B09-Wiederherstellung × B01-Schlüsselbund

    /// Lässt sich die Datenbank beim Start nicht öffnen (B09 · BUG-13), wird sie beiseitegelegt. Was passiert mit den
    /// Zugangsdaten der darin enthaltenen Xtream-Playlists? Und enthält die beiseitegelegte Datei Klartext?
    @MainActor func testQA2_B09Wiederherstellung_ZugangsdatenUndBeiseitegelegteDatei() async throws {
        let support = try dir("recovery")
        let storeURL = AppPersistence.storeURL(applicationSupport: support, bundleID: "lu.daumedia.MikaPlusPlayer")
        try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let kc = store()
        let marker = "qa-pass-qa2rec-\(UInt32.random(in: 1000...9999))"
        var playlistID = UUID()
        do {
            let (container, outcome) = AppPersistence.openStore(at: storeURL, schema: AppSchema.schema)
            XCTAssertEqual(outcome, .opened)
            let importer = PlaylistImporter(modelContext: container.mainContext, credentialStore: kc, loginThrottle: XtreamLoginThrottle())
            playlistID = try await importer.importFromXtream(XtreamCredentials(host: mock.hostPort, username: "qa-user", password: marker),
                                                              output: .mpegts, name: "Vor Beschädigung").id
        }
        try await Task.sleep(nanoseconds: 1_500_000_000)
        // Datei beschädigen (Kopf überschreiben)
        let handle = try FileHandle(forWritingTo: storeURL)
        try handle.write(contentsOf: Data(repeating: 0x42, count: 100))
        try handle.close()

        let (container, outcome) = AppPersistence.openStore(at: storeURL, schema: AppSchema.schema)
        guard case .recovered(let movedTo, _) = outcome else { return XCTFail("erwartet recovered, war \(outcome)") }
        _ = AppPersistence.migrateCredentials(container: container, storeURL: storeURL, store: kc)
        let playlists = try container.mainContext.fetchCount(FetchDescriptor<Playlist>())
        let orphan = (try? kc.load(for: playlistID)) != nil
        let setAside = B01QA2.occurrences(of: [marker], under: movedTo.deletingLastPathComponent())
        print("B01QA2|B09xB01|playlistsNachWiederherstellung=\(playlists)|schluesselbundEintragDerAltenPlaylist=\(orphan)|klartextImBeiseitegelegten=\(setAside)")
        XCTAssertEqual(playlists, 0)
        XCTAssertEqual(setAside.values.reduce(0, +), 0, "beiseitegelegte Datei ohne Klartext")
        // Hinweis (kein Fehler): Die Einträge bleiben, damit eine zurückgeholte beiseitegelegte Datenbank spielbar bleibt;
        // die App bietet aber keinen Weg, sie zu entfernen.
        print("B01QA2|B09xB01|verwaisterSchluesselbundEintrag=\(orphan)")
    }
    // MARK: Aufräumen / Rückstände im Schlüsselbund

    /// Rückstände: Einträge mit dem Label der App unter **Test**-Diensten (`…xtream.tests.…`, `…b01-build-tests…`,
    /// `…qa2…`), die frühere Testläufe hinterlassen haben. Gelesen werden nur Attribute; gezählt und ausgegeben werden
    /// ausschließlich Test-Dienste, der Dienst der App wird nicht angefasst.
    func testQA2_ZZ_KeineSchluesselbundRueckstaendeVonTests() throws {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrLabel as String: "Mika+Player – Xtream-Zugang",
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail
        ]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        let services = ((out as? [[String: Any]]) ?? []).compactMap { $0[kSecAttrService as String] as? String }
        let current = XtreamCredentialStore.standard.service
        let testServices = services.filter { $0 != "lu.daumedia.MikaPlusPlayer.xtream" && $0 != current }
        let grouped = Dictionary(grouping: testServices) { svc -> String in
            if svc.contains(".xtream.tests.") { return "xtream.tests" }
            if svc.contains("b01-build-tests") { return "b01-build-tests" }
            if svc.contains(".qa2.") { return "qa2" }
            return "sonstige"
        }.mapValues(\.count)
        print("B01QA2|KC|rueckstaende|status=\(status)|testdienste=\(grouped)|dieserLauf=\(B01QA2.keychainCount(service: current))")
        XCTAssertEqual(grouped["sonstige"] ?? 0, 0)
    }
}

import SQLite3
