import Foundation
import CoreData
import SwiftData
import SQLite3
import os

/// Speicherort der Datenbank und einmalige Umstellungen beim Start (B01).
///
/// - BUG-04: eigener Ordner `Application Support/<Bundle-ID>/MikaPlusPlayer.store` statt der
///   generischen `Application Support/default.store`. Eine vorhandene `default.store` wird nur
///   übernommen, wenn sie nachweislich das Schema dieser App hat (genau die Entitäten `Playlist` und
///   `Channel` mit passenden Versions-Hashes). Sie wird **kopiert**; gelöscht wird sie erst nach
///   geprüfter Kopie. Gehört sie nicht dieser App, bleibt sie unangetastet.
/// - BUG-01: Xtream-Zugangsdaten aus Altbeständen wandern in den Schlüsselbund; seit B02 · BUG-01 ebenso
///   Zugangsdaten aus M3U-Adressen (`username`/`password`, `user:pass@`).
/// - BUG-03: der alte HTTP-Plattencache der App wird einmalig geleert (seit B02 · BUG-02 erneut einmal, weil
///   M3U-Abrufe bis dahin wieder hineinschrieben; seitdem schreibt kein Importweg mehr hinein).
/// - B09 · BUG-13: geöffnet wird mit versioniertem Schema und Migrationsplan (`AppSchema`). Lässt sich die
///   Datei nicht öffnen, wird sie unverändert beiseitegelegt und eine neue angelegt – kein Absturz.
///
/// Die Datenbank wird **nicht** vom Backup ausgeschlossen: Nach BUG-01 (B01, B02) enthält sie keine
/// Zugangsdaten mehr, ein Ausschluss würde Nutzern beim Wiederherstellen nur ihre Playlists nehmen.
enum AppPersistence {
    static let storeFileName = "MikaPlusPlayer.store"
    static let legacyStoreFileName = "default.store"
    /// Merker für das einmalige Leeren. Neuer Name seit B02 · BUG-02: Wer eine Entwicklungsversion mit dem Merker
    /// `B01.legacyHTTPCachePurged` hatte, bekommt die seither von M3U-Abrufen geschriebenen Einträge ebenfalls entfernt.
    static let cachePurgeDefaultsKey = "B02.legacyHTTPCachePurged"

    static let setAsideFolderName = "Beiseitegelegt"

    /// Die Modelltypen des aktuellen Schemas (`AppSchema`).
    static var modelTypes: [any PersistentModel.Type] { AppSchema.current.models }

    enum LegacyStoreOutcome: Equatable {
        /// keine `default.store` vorhanden
        case noLegacyStore
        /// neue Datenbank existiert bereits; `default.store` wurde nicht angefasst
        case newStoreExists
        /// kopiert und geprüft, alte Datei gelöscht
        case adopted
        /// gehört nicht (nachweislich) zu dieser App; unangetastet
        case notOurs
        /// Kopie gescheitert; alte Datei unangetastet, Teilkopie entfernt
        case copyFailed
        /// andere Bundle-ID als die Release-App (Debug-Build, B09 · BF-119): `default.store` gehört der installierten
        /// App und bleibt unangetastet
        case otherBundleID
    }

    // MARK: - B09 · BUG-13 Öffnen beim Start

    /// Ergebnis des Öffnens der Datenbank beim Start.
    enum StoreOpenOutcome: Equatable {
        /// Datei geöffnet (bei künftigen Schema-Versionen: migriert)
        case opened
        /// Test-Host: nur im Speicher
        case inMemoryForTests
        /// Datei ließ sich nicht öffnen. Sie liegt unverändert unter `movedTo`; eine neue, leere Datenbank ist angelegt.
        case recovered(movedTo: URL, reason: String)
        /// Weder die Datei noch eine neue ließ sich öffnen. Diese Sitzung speichert nichts.
        /// `movedTo` ist gesetzt, wenn die alte Datei vorher beiseitegelegt wurde.
        /// `keptInPlace`: Die Datei war da, ließ sich aber nicht beiseitelegen und liegt unverändert am bisherigen Ort.
        case inMemoryFallback(movedTo: URL?, keptInPlace: Bool, reason: String)
    }

    struct LaunchStore {
        let container: ModelContainer
        let outcome: StoreOpenOutcome
        /// Umstellungen nach dem Öffnen, im Hintergrund (Review R-10); die Oberfläche wartet darauf.
        let maintenance: LaunchMaintenance
    }

    private static let log = Logger(subsystem: "lu.daumedia.MikaPlusPlayer", category: "Persistenz")

    /// Einziger Einstieg beim Start: Speicherort vorbereiten (B01), öffnen oder wiederherstellen (B09),
    /// danach die einmaligen Umstellungen (B01) – seit Review R-10 im Hintergrund, nicht mehr vor dem ersten Fenster.
    @MainActor
    static func openAppStore() -> LaunchStore {
        let schema = AppSchema.schema
        let config = configuration(schema: schema)
        guard !config.isStoredInMemoryOnly else {
            return LaunchStore(container: inMemoryContainer(schema: schema), outcome: .inMemoryForTests,
                               maintenance: LaunchMaintenance())
        }
        let (container, outcome) = openStore(at: config.url, schema: schema)
        let maintenance = LaunchMaintenance()
        switch outcome {
        case .opened, .recovered:
            if !AppEnvironment.isRunningTests {
                maintenance.start(container: container, storeURL: config.url, credentials: .standard, defaults: .standard)
            }
        case .inMemoryFallback, .inMemoryForTests:
            break
        }
        return LaunchStore(container: container, outcome: outcome, maintenance: maintenance)
    }

    /// Öffnet die Datei mit Migrationsplan. Scheitert das, wird sie samt `-wal`/`-shm` unverändert nach
    /// `<Ordner>/Beiseitegelegt/<Zeitstempel>/` verschoben und neu angelegt; gelingt auch das nicht, läuft die
    /// Sitzung im Speicher. Gelöscht wird nie etwas.
    static func openStore(at storeURL: URL, schema: Schema, now: Date = Date()) -> (ModelContainer, StoreOpenOutcome) {
        let reason: String
        do {
            return (try diskContainer(at: storeURL, schema: schema), .opened)
        } catch {
            reason = describe(error)
        }
        log.error("Datenbank ließ sich nicht öffnen: \(reason, privacy: .private)")

        var movedTo: URL?
        let filesExisted = storeFilesExist(at: storeURL)
        if filesExisted {
            do {
                movedTo = try moveStoreAside(storeURL, now: now)
            } catch {
                log.error("Beiseitelegen gescheitert: \(describe(error), privacy: .private)")
            }
        }
        if let movedTo, let container = try? diskContainer(at: storeURL, schema: schema) {
            log.notice("Datenbank beiseitegelegt und neu angelegt")
            return (container, .recovered(movedTo: movedTo, reason: reason))
        }
        return (inMemoryContainer(schema: schema), .inMemoryFallback(movedTo: movedTo, keptInPlace: filesExisted && movedTo == nil,
                                                                       reason: reason))
    }

    static func diskContainer(at storeURL: URL, schema: Schema) throws -> ModelContainer {
        let config = ModelConfiguration(schema: schema, url: storeURL)
        return try ModelContainer(for: schema, migrationPlan: MikaPlusPlayerMigrationPlan.self, configurations: [config])
    }

    static func inMemoryContainer(schema: Schema) -> ModelContainer {
        do {
            return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        } catch {
            // Nur bei einem ungültigen Modell erreichbar – dann scheitert schon jeder Testlauf, weil der Test-Host
            // genau diesen Container öffnet. Mit einer Datei auf der Platte hat das nichts zu tun.
            fatalError("SwiftData-Modell ungültig: \(error)")
        }
    }

    static func storeFilesExist(at storeURL: URL) -> Bool {
        storeItemNames(for: storeURL).contains {
            FileManager.default.fileExists(atPath: storeURL.deletingLastPathComponent().appendingPathComponent($0).path)
        }
    }

    /// `MikaPlusPlayer.store`, `-wal`, `-shm` und Core Datas Ordner für externe Daten.
    private static func storeItemNames(for storeURL: URL) -> [String] {
        let name = storeURL.lastPathComponent
        return [name, name + "-wal", name + "-shm", "." + storeURL.deletingPathExtension().lastPathComponent + "_SUPPORT"]
    }

    /// Verschiebt die Dateien der Datenbank gemeinsam; scheitert ein Teil, wird zurückverschoben.
    /// - Returns: neuer Ort der Hauptdatei
    static func moveStoreAside(_ storeURL: URL, now: Date) throws -> URL {
        let fileManager = FileManager.default
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd'_'HH-mm-ss"
        let parent = storeURL.deletingLastPathComponent().appendingPathComponent(setAsideFolderName, isDirectory: true)
        var folder = parent.appendingPathComponent(formatter.string(from: now), isDirectory: true)
        var counter = 1
        while fileManager.fileExists(atPath: folder.path) {
            counter += 1
            folder = parent.appendingPathComponent("\(formatter.string(from: now))-\(counter)", isDirectory: true)
        }
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        var moved: [(from: URL, to: URL)] = []
        do {
            for item in storeItemNames(for: storeURL) {
                let source = storeURL.deletingLastPathComponent().appendingPathComponent(item)
                guard fileManager.fileExists(atPath: source.path) else { continue }
                let target = folder.appendingPathComponent(item)
                try fileManager.moveItem(at: source, to: target)
                moved.append((source, target))
            }
        } catch {
            for step in moved.reversed() {
                try? fileManager.moveItem(at: step.to, to: step.from)
            }
            try? fileManager.removeItem(at: folder)
            throw error
        }
        return folder.appendingPathComponent(storeURL.lastPathComponent)
    }

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain) \(nsError.code): \(nsError.localizedDescription)"
    }

    // MARK: - Konfiguration beim Start

    /// Konfiguration für den App-Container. Als Test-Host immer im Speicher.
    static func configuration(schema: Schema) -> ModelConfiguration {
        if AppEnvironment.isRunningTests {
            return ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        }
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let (storeURL, _) = prepareStore(applicationSupport: applicationSupport, bundleID: AppEnvironment.bundleID)
        return ModelConfiguration(schema: schema, url: storeURL)
    }

    /// Speicherort der Datenbank der App, ohne etwas anzulegen oder zu übernehmen (für „Alle Daten entfernen" im
    /// B09-Rückfall, Review R-04).
    static func appStoreURL() -> URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return storeURL(applicationSupport: applicationSupport, bundleID: AppEnvironment.bundleID)
    }

    /// Einmalige Umstellungen nach dem Öffnen des Containers (Review R-10: aufgerufen von `LaunchMaintenance`, abseits
    /// des Main-Threads): unfertige Playlists entfernen (R-02), Zugangsdaten umstellen und verdichten (B01/B02 · BUG-01,
    /// R-08), alten HTTP-Cache einmal leeren (B01 · BUG-03). Läuft auf `PlaylistStore`, also nie gleichzeitig mit
    /// Anlegen, Aktualisieren oder Löschen.
    @discardableResult
    static func finishLaunch(container: ModelContainer, storeURL: URL, store: PlaylistStore = .shared,
                             credentials: XtreamCredentialStore, defaults: UserDefaults?,
                             cache: URLCache? = nil) async -> CredentialMigrationResult {
        let result = await store.launchMaintenance(container: container, storeURL: storeURL, credentials: credentials,
                                                   defaults: defaults)
        if let defaults, let cache { purgeLegacyHTTPCacheOnce(defaults: defaults, cache: cache) }
        return result
    }

    // MARK: - BUG-04 Speicherort

    static func storeURL(applicationSupport: URL, bundleID: String) -> URL {
        applicationSupport
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent(storeFileName)
    }

    /// Legt den App-Ordner an und übernimmt bei Bedarf die alte `default.store` – nur, wenn die **übergebene**
    /// Bundle-ID die der Release-App ist (B09 · BF-119: ein Debug-Build zieht die Daten der installierten App nicht an
    /// sich; die Regel hängt am Parameter, damit die Übernahme-Tests mit übergebener Release-ID gültig bleiben).
    @discardableResult
    static func prepareStore(applicationSupport: URL, bundleID: String) -> (URL, LegacyStoreOutcome) {
        let fileManager = FileManager.default
        let storeURL = storeURL(applicationSupport: applicationSupport, bundleID: bundleID)
        try? fileManager.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let legacyURL = applicationSupport.appendingPathComponent(legacyStoreFileName)
        guard fileManager.fileExists(atPath: legacyURL.path) else { return (storeURL, .noLegacyStore) }
        guard bundleID == AppEnvironment.releaseBundleID else { return (storeURL, .otherBundleID) }
        guard !fileManager.fileExists(atPath: storeURL.path) else { return (storeURL, .newStoreExists) }
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: modelTypes),
              isStoreOfThisApp(at: legacyURL, model: model) else { return (storeURL, .notOurs) }

        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        do {
            try coordinator.replacePersistentStore(at: storeURL, withPersistentStoreFrom: legacyURL, type: .sqlite)
        } catch {
            removeStoreFiles(at: storeURL)
            return (storeURL, .copyFailed)
        }
        guard isStoreOfThisApp(at: storeURL, model: model) else {
            removeStoreFiles(at: storeURL)
            return (storeURL, .copyFailed)
        }
        // Die alte Datei enthält ausschließlich Playlist/Channel (geprüft) → entfernen.
        try? coordinator.destroyPersistentStore(at: legacyURL, type: .sqlite)
        removeStoreFiles(at: legacyURL)
        return (storeURL, .adopted)
    }

    /// Liest nur die Metadaten: genau die Entitäten `Playlist` und `Channel`, kompatibel zum Modell.
    static func isStoreOfThisApp(at url: URL, model: NSManagedObjectModel) -> Bool {
        guard let metadata = try? NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: url),
              let hashes = metadata[NSStoreModelVersionHashesKey] as? [String: Any] else { return false }
        let expected = Set(model.entities.compactMap(\.name))
        return Set(hashes.keys) == expected
            && model.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata)
    }

    private static func removeStoreFiles(at url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }

    // MARK: - BUG-01 Zugangsdaten aus Altbeständen

    struct CredentialMigrationResult: Equatable {
        var migratedPlaylists = 0
        var rewrittenChannels = 0
        var failedPlaylists = 0
    }

    /// Merker „Umstellung gespeichert, Verdichten steht noch aus" (Review R-08): gesetzt vor dem ersten Speichern einer
    /// Umstellung, entfernt nach gelungenem Verdichten. Endet die App dazwischen, verdichtet der nächste Start.
    static let compactionPendingDefaultsKey = "B02.credentialCompactionPending"

    /// Stellt Xtream-Playlists mit Zugangsdaten in `sourceURL`/`streamURL` um: Zugangsdaten in den
    /// Schlüsselbund, Adressen ohne Geheimnis. Sender bleiben dieselben Objekte, Favoriten bleiben.
    /// Seit B02 · BUG-01 ebenso M3U-Playlists, deren Adresse Zugangsdaten trägt (`M3UCredentials`).
    /// Danach wird die Datei verdichtet und das Write-Ahead-Log geleert, damit weder freigegebene Seiten
    /// noch alte Log-Einträge den Klartext behalten. Mit `defaults` (App) wird ein ausstehendes Verdichten gemerkt und
    /// beim nächsten Aufruf nachgeholt, auch wenn dann nichts mehr umzustellen ist (Review R-08).
    /// Gelingt der Schlüsselbund-Eintrag nicht, bleibt die Playlist unverändert und spielbar.
    @discardableResult
    static func migrateCredentials(container: ModelContainer, storeURL: URL?,
                                   store: XtreamCredentialStore, defaults: UserDefaults? = nil) -> CredentialMigrationResult {
        var result = CredentialMigrationResult()
        var compactionPending = defaults?.bool(forKey: compactionPendingDefaultsKey) ?? false
        let willSave = {
            guard !compactionPending, let defaults else { return }
            defaults.set(true, forKey: compactionPendingDefaultsKey)
            compactionPending = true
        }
        let finish = {
            guard result.migratedPlaylists > 0 || compactionPending, let storeURL else { return }
            if compactStore(at: storeURL) { defaults?.removeObject(forKey: compactionPendingDefaultsKey) }
        }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        migrateM3UCredentials(context: context, store: store, willSave: willSave, result: &result)
        let descriptor = FetchDescriptor<Playlist>(predicate: #Predicate { $0.isXtream == true })
        guard let playlists = try? context.fetch(descriptor) else {
            finish()
            return result
        }

        for playlist in playlists {
            guard let source = playlist.sourceURL,
                  let legacy = XtreamCredentials(legacyPlayerAPIURL: source) else { continue }
            guard let secret = legacy.secret(),
                  let storedBase = legacy.storedBaseURL(),
                  let storedSource = legacy.storedSourceURL() else {
                result.failedPlaylists += 1
                continue
            }
            do {
                try store.save(secret, for: playlist.id)
            } catch {
                result.failedPlaylists += 1
                continue
            }
            let prefixes = legacyStreamPrefixes(secret: secret)
            var rewritten = 0
            for channel in playlist.channels {
                if let cleaned = credentialFreeStreamURL(channel.streamURL, legacyPrefixes: prefixes,
                                                         storedBase: storedBase) {
                    channel.streamURL = cleaned
                    rewritten += 1
                }
            }
            playlist.sourceURL = storedSource
            willSave()
            do {
                try context.save()
                result.migratedPlaylists += 1
                result.rewrittenChannels += rewritten
            } catch {
                context.rollback()
                result.failedPlaylists += 1
            }
        }

        finish()
        return result
    }

    /// B02 · BUG-01: M3U-Playlists mit Zugangsdaten in der Adresse → Schlüsselbund, Adresse und Stream-Adressen mit
    /// Platzhaltern. Dieselben Sender-Objekte, Favoriten bleiben.
    private static func migrateM3UCredentials(context: ModelContext, store: XtreamCredentialStore, willSave: () -> Void,
                                              result: inout CredentialMigrationResult) {
        let descriptor = FetchDescriptor<Playlist>(predicate: #Predicate { $0.isXtream == false })
        guard let playlists = try? context.fetch(descriptor) else { return }
        for playlist in playlists {
            guard let source = playlist.sourceURL, let split = M3UCredentials.split(source) else { continue }
            do {
                try store.saveM3U(split.secret, for: playlist.id)
            } catch {
                result.failedPlaylists += 1
                continue
            }
            var rewritten = 0
            for channel in playlist.channels {
                let cleaned = M3UCredentials.redact(channel.streamURL, secret: split.secret)
                if cleaned != channel.streamURL {
                    channel.streamURL = cleaned
                    rewritten += 1
                }
            }
            playlist.sourceURL = split.stored
            willSave()
            do {
                try context.save()
                result.migratedPlaylists += 1
                result.rewrittenChannels += rewritten
            } catch {
                context.rollback()
                result.failedPlaylists += 1
            }
        }
    }

    /// Anfänge alter Stream-Adressen: `"\(base)/live/\(user)/\(pass)/"`, roh und so, wie `URL(string:)`
    /// sie beim alten Import kodiert hat.
    static func legacyStreamPrefixes(secret: XtreamSecret) -> [String] {
        let raw = secret.host + "/live/" + secret.username + "/" + secret.password + "/"
        var prefixes = [raw]
        if let encoded = URL(string: raw + "0")?.absoluteString, encoded.hasSuffix("0") {
            let prefix = String(encoded.dropLast())
            if prefix != raw { prefixes.append(prefix) }
        }
        return prefixes
    }

    /// Alte Stream-Adresse → `<Basis ohne Benutzerinfo>/live/<stream_id>.<ext>`.
    static func credentialFreeStreamURL(_ url: URL, legacyPrefixes: [String], storedBase: URL) -> URL? {
        let address = url.absoluteString
        let base = storedBase.absoluteString + XtreamStreamAddress.liveMarker
        for prefix in legacyPrefixes where address.hasPrefix(prefix) {
            return URL(string: base + address.dropFirst(prefix.count))
        }
        // Rückfall: die beiden Abschnitte nach /live/ (Benutzer, Passwort) verwerfen.
        if let suffix = XtreamStreamAddress.liveSuffix(of: address) {
            let parts = suffix.split(separator: "/", maxSplits: 2, omittingEmptySubsequences: false)
            if parts.count == 3 { return URL(string: base + parts[2]) }
        }
        return URL(string: base + url.lastPathComponent)
    }

    /// `VACUUM` und `PRAGMA wal_checkpoint(TRUNCATE)` über eine eigene Verbindung (dieselbe
    /// SQLite-Bibliothek wie Core Data). `Z_PK` ist `INTEGER PRIMARY KEY`, die Objekt-IDs bleiben erhalten.
    /// - Returns: true, wenn `VACUUM` gelungen ist.
    @discardableResult
    static func compactStore(at storeURL: URL) -> Bool {
        var db: OpaquePointer?
        guard sqlite3_open_v2(storeURL.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return false
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 2_000)
        let vacuum = sqlite3_exec(db, "VACUUM;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE);", nil, nil, nil)
        return vacuum == SQLITE_OK
    }

    // MARK: - BUG-03 alter HTTP-Plattencache

    /// Leert einmalig den HTTP-Cache der App (`URLCache.shared` liegt im Cache-Ordner der Bundle-ID).
    /// Darin stehen aus Versionen bis 1.1 die player_api-Anfragen mit Zugangsdaten samt Antworten.
    @discardableResult
    static func purgeLegacyHTTPCacheOnce(defaults: UserDefaults, cache: URLCache) -> Bool {
        guard !defaults.bool(forKey: cachePurgeDefaultsKey) else { return false }
        cache.removeAllCachedResponses()
        defaults.set(true, forKey: cachePurgeDefaultsKey)
        return true
    }
}

// MARK: - B09 · BUG-13 Hinweis an den Nutzer

extension AppPersistence {
    struct StoreNotice: Equatable {
        let title: String
        let message: String
        /// Ordner mit der beiseitegelegten Datenbank
        let folder: URL?
    }
}

extension AppPersistence.StoreOpenOutcome {
    /// Plattform des Hinweises: macOS nennt den Ordner, iOS nicht (Ordner im App-Container, für Nutzer unerreichbar).
    enum NoticePlatform {
        case macOS, iOS

        static var current: NoticePlatform {
            #if os(macOS)
            .macOS
            #else
            .iOS
            #endif
        }
    }

    /// Hinweis für den Nutzer auf dieser Plattform; `nil`, wenn nichts zu melden ist.
    var notice: AppPersistence.StoreNotice? { notice(for: .current) }

    /// Hinweis für den Nutzer; `nil`, wenn nichts zu melden ist.
    ///
    /// B09 · OF-08 (2026-10-01): Beiseitegelegte Datenbanken bleiben bis „Alle Daten entfernen …“ liegen. Der Hinweis
    /// sagt deshalb auch, dass die Zugangsdaten im Schlüsselbund erhalten bleiben, und nennt den Löschweg.
    func notice(for platform: NoticePlatform) -> AppPersistence.StoreNotice? {
        let keychain = "Die Zugangsdaten der bisherigen Playlists bleiben im Schlüsselbund gespeichert."
        let menu = platform == .macOS ? "im App-Menü" : "im Menü der Playlist-Übersicht"
        switch self {
        case .opened, .inMemoryForTests:
            return nil
        case .recovered(let movedTo, _):
            let folder = movedTo.deletingLastPathComponent()
            let location = platform == .macOS
                ? "sondern unverändert nach „\(folder.path)“ verschoben"
                : "sondern unverändert beiseitegelegt"
            return AppPersistence.StoreNotice(
                title: "Datenbank neu angelegt",
                message: "Die gespeicherten Playlists ließen sich nicht öffnen. Die bisherige Datenbank wurde nicht gelöscht, "
                    + "\(location). Die App startet mit einer leeren Datenbank; Playlists müssen neu importiert werden. "
                    + "\(keychain) Beides entfernt „Alle Daten entfernen …“ \(menu).",
                folder: platform == .macOS ? folder : nil)
        case .inMemoryFallback(let movedTo, let keptInPlace, _):
            let folder = movedTo?.deletingLastPathComponent()
            var message = "Die Datenbank ließ sich weder öffnen noch neu anlegen. Änderungen in dieser Sitzung werden nicht gespeichert."
            if let folder {
                message += platform == .macOS
                    ? " Die bisherige Datenbank liegt unverändert in „\(folder.path)“."
                    : " Die bisherige Datenbank wurde unverändert beiseitegelegt."
            } else if keptInPlace {
                message += " Die bisherige Datenbank liegt unverändert am bisherigen Ort."
            }
            message += " \(keychain) Gespeicherte Daten entfernt „Alle Daten entfernen …“ \(menu)."
            return AppPersistence.StoreNotice(title: "Datenbank nicht verfügbar", message: message,
                                              folder: platform == .macOS ? folder : nil)
        }
    }
}

// MARK: - Review R-10 · Umstellungen beim Start im Hintergrund

/// Einmalige Umstellungen beim Start (`AppPersistence.finishLaunch`) laufen im Hintergrund auf `PlaylistStore`, statt
/// den Main-Thread vor dem ersten Fenster zu blockieren (Review R-10: 11 s bei 90.000 Sendern mit Zugangsdaten). Bis sie
/// fertig sind, zeigt das Fenster einen Hinweis statt der Playlists; Importe, Aktualisieren und Löschen warten ohnehin
/// hinter ihnen, weil sie über denselben Actor laufen.
@MainActor
@Observable
final class LaunchMaintenance {
    private(set) var isRunning = false
    /// Ergebnis der Umstellung, sobald fertig (Protokoll/Tests).
    private(set) var result: AppPersistence.CredentialMigrationResult?

    func start(container: ModelContainer, storeURL: URL, store: PlaylistStore = .shared,
               credentials: XtreamCredentialStore, defaults: UserDefaults?, cache: URLCache? = .shared) {
        guard !isRunning else { return }
        isRunning = true
        let defaultsBox = UncheckedSendableBox(defaults)
        let cacheBox = UncheckedSendableBox(cache)
        Task.detached(priority: .userInitiated) {
            let result = await AppPersistence.finishLaunch(container: container, storeURL: storeURL, store: store,
                                                           credentials: credentials, defaults: defaultsBox.value,
                                                           cache: cacheBox.value)
            await self.finish(result)
        }
    }

    private func finish(_ result: AppPersistence.CredentialMigrationResult) {
        self.result = result
        isRunning = false
    }
}

/// `UserDefaults`/`URLCache` sind threadsicher, aber nicht als `Sendable` markiert.
private struct UncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
