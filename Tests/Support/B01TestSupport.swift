import Foundation
import SQLite3
import SwiftData
import XCTest
@testable import MikaPlusPlayer

/// Gemeinsame Hilfen der B01-QA-Tests.
///
/// Wichtig: Der Test-Host ist die echte App. Seit der Reparatur (BUG-04) öffnet sie als Test-Host nur
/// einen In-Memory-Container und einen eigenen Schlüsselbunddienst je Lauf. Diese Tests schreiben
/// **nie** in die Datenbank des Nutzers, sondern nur in einen In-Memory-Container oder eine
/// Store-Datei im Temp-Verzeichnis.
enum B01 {
    static let schema = Schema([Playlist.self, Channel.self])

    @MainActor
    static func inMemoryContainer() throws -> ModelContainer {
        try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }

    /// Store-Datei in einem eigenen Temp-Ordner. Rückgabe: Container und Datei-URL.
    @MainActor
    static func tempFileContainer(_ label: String) throws -> (ModelContainer, URL, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("b01-qa-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("b01-qa.store")
        let config = ModelConfiguration(schema: schema, url: url)
        return (try ModelContainer(for: schema, configurations: [config]), url, dir)
    }

    /// Führt den Import über den echten Pfad aus (`PlaylistImporter` → `XtreamClient` → `XtreamHTTPLoader`).
    /// Jeder Aufruf bekommt standardmäßig eine eigene Anmeldebremse (BUG-07), damit Fehlerfall-Serien gegen
    /// denselben Mock nicht gedrosselt werden; Tests der Bremse reichen eine gemeinsame hinein.
    /// Zugangsdaten landen im Test-Schlüsselbunddienst dieses Laufs (`XtreamCredentialStore.standard`).
    @MainActor
    static func importXtream(host: String, user: String = "qa-user", pass: String, output: XtreamOutput = .mpegts,
                             name: String = "", context: ModelContext,
                             limits: XtreamClient.Limits = .standard,
                             throttle: XtreamLoginThrottle = XtreamLoginThrottle()) async -> Result<Playlist, Error> {
        let importer = PlaylistImporter(modelContext: context, xtreamLimits: limits, loginThrottle: throttle)
        do {
            let p = try await importer.importFromXtream(
                XtreamCredentials(host: host, username: user, password: pass), output: output, name: name)
            return .success(p)
        } catch {
            return .failure(error)
        }
    }

    /// Abspielbare Adresse eines Senders über den einzigen Weg der App (`StreamURLResolver`).
    @MainActor
    static func playable(_ channel: Channel) throws -> URL {
        try StreamURLResolver.playableURL(for: channel)
    }

    /// Kurze Leerlaufzeit für Tests, die eine TLS-Verbindung gegen den Klartext-Mock versuchen.
    static var shortIdleLimits: XtreamClient.Limits {
        var limits = XtreamClient.Limits.standard
        limits.idleTimeout = 3
        return limits
    }

    /// Fehlermeldung, wie sie das Sheet anzeigt (`error.localizedDescription`).
    static func message(_ result: Result<Playlist, Error>) -> String? {
        if case .failure(let e) = result { return e.localizedDescription }
        return nil
    }

    // MARK: - SQLite (nur Test-Datenbanken)

    /// Führt eine Zähl-Abfrage auf einer SQLite-Datei aus. Nur für Dateien, die ein Test selbst angelegt
    /// hat, oder mit einem LIKE-Filter auf die eigene Testmarke.
    static func sqliteCount(_ path: String, _ sql: String) -> Int? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { sqlite3_close(db); return nil }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    /// Wie oft kommt `marker` als Bytefolge in den Dateien vor (Store, -wal, -shm)?
    static func rawOccurrences(of marker: String, inFilesWithPrefix url: URL) -> [String: Int] {
        var result: [String: Int] = [:]
        let needle = Data(marker.utf8)
        for suffix in ["", "-wal", "-shm"] {
            let file = URL(fileURLWithPath: url.path + suffix)
            guard let data = try? Data(contentsOf: file) else { continue }
            var count = 0
            var range = data.startIndex..<data.endIndex
            while let found = data.range(of: needle, options: [], in: range) {
                count += 1
                range = found.upperBound..<data.endIndex
            }
            result[file.lastPathComponent] = count
        }
        return result
    }
}

/// Basisklasse: startet je Test einen frischen Mock auf 127.0.0.1.
class B01MockTestCase: XCTestCase {
    var mock: MockXtreamServer!

    override func setUpWithError() throws {
        try super.setUpWithError()
        mock = MockXtreamServer()
        try mock.start()
    }

    override func tearDown() {
        if let mock {
            B01.removeCachedResponses(for: mock)
            mock.stop()
        }
        mock = nil
        // Schlüsselbund-Einträge dieses Testlaufs (eigener Dienstname je Lauf) entfernen.
        XCTAssertNoThrow(try XtreamCredentialStore.standard.deleteAll())
        super.tearDown()
    }
}

extension B01 {
    /// Entfernt die HTTP-Cache-Einträge, die ein Test über `URLSession.shared` gegen den Mock erzeugt hat
    /// (FB-03: die App schreibt sie in den Plattencache des Test-Hosts).
    static func removeCachedResponses(for mock: MockXtreamServer) {
        for req in mock.requests {
            guard let url = URL(string: "http://\(mock.hostPort)\(req.target)") else { continue }
            URLCache.shared.removeCachedResponse(for: URLRequest(url: url))
        }
    }

    /// Pfad der Plattencache-Datenbank des Test-Hosts (`~/Library/Caches/<Bundle-ID>/Cache.db`).
    static var hostCacheDB: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "lu.daumedia.MikaPlusPlayer")
            .appendingPathComponent("Cache.db")
    }
}

/// Steuerbare Uhr für die Anmeldebremse (BUG-07).
final class B01TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_800_000_000)
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
}
