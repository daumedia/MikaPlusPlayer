import CoreData
import SwiftData
import XCTest
@testable import MikaPlusPlayer

/// B09 · BUG-13 — Schema-Versionierung und Wiederherstellung beim Öffnen der Datenbank.
///
/// Alle Tests arbeiten in eigenen Temp-Ordnern. Die Datenbank des Nutzers wird weder gelesen noch beschrieben.
@MainActor
final class B09PersistenzTests: XCTestCase {
    private var tempDirs: [URL] = []

    override func tearDown() async throws {
        for dir in tempDirs {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
            try? FileManager.default.removeItem(at: dir)
        }
        tempDirs.removeAll()
        try await super.tearDown()
    }

    private func tempDir(_ label: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("b09-build-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDirs.append(dir)
        return dir
    }

    /// Vorlage `Tests/B09/Fixtures/v1.1-schema.store`: erzeugt am 2026-09-16 von einem Kommandozeilenprogramm, das die
    /// Modelldateien aus `git show v1.1:Sources/Models/` und exakt den Container-Aufruf von v1.1
    /// (`Schema([Playlist.self, Channel.self])`, ohne VersionedSchema) nutzte. Inhalt: 1 Playlist, 3 Sender, 1 Favorit,
    /// nur erfundene Daten.
    private func fixtureCopy(into dir: URL) throws -> URL {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/v1.1-schema.store")
        guard FileManager.default.fileExists(atPath: fixture.path) else {
            throw XCTSkip("Vorlage fehlt: \(fixture.path)")
        }
        let target = dir.appendingPathComponent(AppPersistence.storeFileName)
        try FileManager.default.copyItem(at: fixture, to: target)
        return target
    }

    private func setAsideFolder(for storeURL: URL) -> URL {
        storeURL.deletingLastPathComponent().appendingPathComponent(AppPersistence.setAsideFolderName)
    }

    // MARK: - Datenbank aus v1.1

    func testBUG13_DatenbankAusV11OeffnetUnveraendert() throws {
        let dir = try tempDir("v11")
        let storeURL = try fixtureCopy(into: dir)

        let (container, outcome) = AppPersistence.openStore(at: storeURL, schema: AppSchema.schema)
        print("B09BUILD|BUG-13|v1.1-Vorlage|\(outcome)")
        XCTAssertEqual(outcome, .opened)
        let context = container.mainContext
        let playlists = try context.fetch(FetchDescriptor<Playlist>())
        XCTAssertEqual(playlists.map(\.name), ["B09 v1.1 Testliste"])
        XCTAssertEqual(playlists.first?.channelCount, 3)
        let channels = try context.fetch(FetchDescriptor<Channel>(sortBy: [SortDescriptor(\.name)]))
        XCTAssertEqual(channels.map(\.name), ["Sender 1", "Sender 2", "Sender 3"])
        XCTAssertEqual(channels.filter(\.isFavorite).map(\.name), ["Sender 2"])
        XCTAssertTrue(channels.allSatisfy { $0.playlistID == playlists.first?.id && $0.playlist?.id == playlists.first?.id })
        XCTAssertFalse(FileManager.default.fileExists(atPath: setAsideFolder(for: storeURL).path), "nichts beiseitegelegt")

        // weiter beschreibbar
        context.insert(Playlist(name: "Nach dem Update"))
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Playlist>()), 2)
    }

    /// Die Vorlage hat genau die Modell-Hashes des aktuellen Schemas – sonst wäre sie keine v1.1-Datenbank für V1.
    func testBUG13_V11VorlagePasstZuSchemaVersion1() throws {
        let dir = try tempDir("v11-meta")
        let storeURL = try fixtureCopy(into: dir)
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: storeURL)
        let model = try XCTUnwrap(NSManagedObjectModel.makeManagedObjectModel(for: MikaPlusPlayerSchemaV1.models))
        XCTAssertTrue(model.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata))
        XCTAssertEqual(entityNames(metadata), ["Playlist", "Channel"])
    }

    /// Dieselbe Prüfung mit einer im Test angelegten unversionierten Datei und größerem Inhalt.
    func testBUG13_UnversionierteDateiOeffnetMitMigrationsplan() async throws {
        let dir = try tempDir("unversioniert")
        let storeURL = dir.appendingPathComponent(AppPersistence.storeFileName)
        let legacySchema = Schema([Playlist.self, Channel.self])
        do {
            let container = try ModelContainer(for: legacySchema, configurations: [ModelConfiguration(schema: legacySchema, url: storeURL)])
            let context = ModelContext(container)
            for p in 0..<3 {
                let playlist = Playlist(name: "Liste \(p)", channelCount: 50)
                context.insert(playlist)
                for c in 0..<50 {
                    context.insert(Channel(name: "S\(p)-\(c)", streamURL: URL(string: "http://127.0.0.1:9/\(p)/\(c).ts")!,
                                           isFavorite: c % 10 == 0, playlist: playlist, playlistID: playlist.id))
                }
            }
            try context.save()
        }
        try await Task.sleep(nanoseconds: 500_000_000)

        let (container, outcome) = AppPersistence.openStore(at: storeURL, schema: AppSchema.schema)
        XCTAssertEqual(outcome, .opened)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Playlist>()), 3)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Channel>()), 150)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Channel>(predicate: #Predicate { $0.isFavorite })), 15)
    }

    // MARK: - Wiederherstellung statt fatalError

    func testBUG13_BeschaedigteDateiWirdBeiseitegelegtUndNeuAngelegt() throws {
        let dir = try tempDir("kaputt")
        let storeURL = dir.appendingPathComponent(AppPersistence.storeFileName)
        let garbage = Data(String(repeating: "Keine SQLite-Datei. ", count: 400).utf8)
        try garbage.write(to: storeURL)
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let (container, outcome) = AppPersistence.openStore(at: storeURL, schema: AppSchema.schema, now: now)
        print("B09BUILD|BUG-13|kaputt|\(outcome)")
        guard case .recovered(let movedTo, let reason) = outcome else {
            return XCTFail("erwartet .recovered, erhalten \(outcome)")
        }
        XCTAssertFalse(reason.isEmpty)
        XCTAssertEqual(movedTo.deletingLastPathComponent().deletingLastPathComponent().path, setAsideFolder(for: storeURL).path)
        XCTAssertEqual(movedTo.lastPathComponent, AppPersistence.storeFileName)
        XCTAssertEqual(try Data(contentsOf: movedTo), garbage, "beiseitegelegte Datei unverändert")

        // neue Datei am alten Ort, voll nutzbar und nach erneutem Öffnen noch da
        let context = container.mainContext
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Playlist>()), 0)
        context.insert(Playlist(name: "Neu nach Wiederherstellung"))
        try context.save()
        let (reopened, secondOutcome) = AppPersistence.openStore(at: storeURL, schema: AppSchema.schema)
        XCTAssertEqual(secondOutcome, .opened)
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<Playlist>()).map(\.name), ["Neu nach Wiederherstellung"])

        let notice = try XCTUnwrap(outcome.notice)
        XCTAssertEqual(notice.title, "Datenbank neu angelegt")
        XCTAssertTrue(notice.message.contains(movedTo.deletingLastPathComponent().path), "Hinweis nennt den Ordner")
        XCTAssertEqual(notice.folder, movedTo.deletingLastPathComponent())
        XCTAssertNil(AppPersistence.StoreOpenOutcome.opened.notice)
    }

    /// Ein Update, dessen Schema die vorhandene Datei nicht migrieren kann (hier: andere Entität, anderer Feldtyp),
    /// stürzt nicht ab: Datei beiseite, neue Datenbank, Hinweis.
    func testBUG13_NichtMigrierbareDateiWirdBeiseitegelegt() async throws {
        let dir = try tempDir("inkompatibel")
        let storeURL = dir.appendingPathComponent(AppPersistence.storeFileName)
        let model = incompatibleModel()
        try makeIncompatibleStore(at: storeURL, model: model)

        let (container, outcome) = AppPersistence.openStore(at: storeURL, schema: AppSchema.schema)
        print("B09BUILD|BUG-13|inkompatibel|\(outcome)")
        guard case .recovered(let movedTo, _) = outcome else {
            return XCTFail("erwartet .recovered, erhalten \(outcome)")
        }
        // Inhalt der beiseitegelegten Datei ist vollständig erhalten (die Kopfbytes kann der gescheiterte
        // Öffnungsversuch von Core Data verändern, deshalb wird der Inhalt geprüft, nicht die Bytes).
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: movedTo)
        XCTAssertEqual(entityNames(metadata), ["Playlist"], "alte Datei trägt weiter das fremde Schema")
        XCTAssertEqual(try readIncompatibleRows(at: movedTo, model: model), ["42|aus einer künftigen Version"],
                       "Datensatz der alten Datei unverändert lesbar")
        container.mainContext.insert(Playlist(name: "neu"))
        try container.mainContext.save()
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Playlist>()), 1)
    }

    /// Lässt sich weder die Datei beiseitelegen noch eine neue anlegen (Ordner schreibgeschützt), läuft die Sitzung im
    /// Speicher; die Datei bleibt unangetastet.
    func testBUG13_OhneSchreibrechtLaeuftSitzungImSpeicher() throws {
        let dir = try tempDir("schreibgeschuetzt")
        let storeURL = dir.appendingPathComponent(AppPersistence.storeFileName)
        let garbage = Data("kaputt".utf8)
        try garbage.write(to: storeURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)

        let (container, outcome) = AppPersistence.openStore(at: storeURL, schema: AppSchema.schema)
        print("B09BUILD|BUG-13|schreibgeschuetzt|\(outcome)")
        guard case .inMemoryFallback(let movedTo, let keptInPlace, _) = outcome else {
            return XCTFail("erwartet .inMemoryFallback, erhalten \(outcome)")
        }
        XCTAssertNil(movedTo)
        XCTAssertTrue(keptInPlace, "Beiseitelegen gescheitert: Datei liegt am bisherigen Ort (OF-08)")
        XCTAssertEqual(try Data(contentsOf: storeURL), garbage, "Datei unangetastet")
        XCTAssertFalse(FileManager.default.fileExists(atPath: setAsideFolder(for: storeURL).path))
        container.mainContext.insert(Playlist(name: "nur im Speicher"))
        try container.mainContext.save()
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Playlist>()), 1)
        XCTAssertEqual(outcome.notice?.title, "Datenbank nicht verfügbar")
        XCTAssertTrue(outcome.notice?.message.contains("am bisherigen Ort") ?? false, "Hinweis sagt, wo die Datei liegt (OF-08)")
    }

    // MARK: - Plan

    func testBUG13_MigrationsplanUndAktuellesSchemaPassen() {
        let schemas = MikaPlusPlayerMigrationPlan.schemas
        XCTAssertEqual(ObjectIdentifier(schemas.last!), ObjectIdentifier(AppSchema.current), "aktuelles Schema ist das letzte im Plan")
        XCTAssertEqual(MikaPlusPlayerMigrationPlan.stages.count, schemas.count - 1, "je Übergang genau eine Stufe")
        let versions = schemas.map { $0.versionIdentifier }
        XCTAssertEqual(versions, versions.sorted(), "Versionen aufsteigend")
        XCTAssertEqual(Set(versions).count, versions.count, "Versionen eindeutig")
        XCTAssertEqual(MikaPlusPlayerSchemaV1.versionIdentifier, Schema.Version(1, 0, 0),
                       "V1 muss 1.0.0 bleiben: so steht es in Datenbanken aus v1.1 (NSStoreModelVersionIdentifiers)")
        XCTAssertEqual(AppPersistence.modelTypes.map { String(describing: $0) }, ["Playlist", "Channel"])
    }

    // MARK: - Hilfen

    private func entityNames(_ metadata: [String: Any]) -> Set<String> {
        Set((metadata[NSStoreModelVersionHashesKey] as? [String: Any]).map { Array($0.keys) } ?? [])
    }

    /// Modell mit Entität `Playlist`, deren Feld `name` eine Zahl ist, und einem Pflichtfeld ohne Gegenstück.
    private func incompatibleModel() -> NSManagedObjectModel {
        let entity = NSEntityDescription()
        entity.name = "Playlist"
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        let name = NSAttributeDescription()
        name.name = "name"
        name.attributeType = .integer64AttributeType
        name.isOptional = false
        name.defaultValue = 0
        let future = NSAttributeDescription()
        future.name = "zukunftsfeld"
        future.attributeType = .stringAttributeType
        future.isOptional = false
        future.defaultValue = ""
        entity.properties = [name, future]
        let model = NSManagedObjectModel()
        model.entities = [entity]
        return model
    }

    private func makeIncompatibleStore(at url: URL, model: NSManagedObjectModel) throws {
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let store = try coordinator.addPersistentStore(type: .sqlite, at: url)
        let context = NSManagedObjectContext(.mainQueue)
        context.persistentStoreCoordinator = coordinator
        let entity = try XCTUnwrap(model.entitiesByName["Playlist"])
        let object = NSManagedObject(entity: entity, insertInto: context)
        object.setValue(42, forKey: "name")
        object.setValue("aus einer künftigen Version", forKey: "zukunftsfeld")
        try context.save()
        try coordinator.remove(store)
    }

    private func readIncompatibleRows(at url: URL, model: NSManagedObjectModel) throws -> [String] {
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let store = try coordinator.addPersistentStore(type: .sqlite, at: url, options: [NSReadOnlyPersistentStoreOption: true])
        defer { try? coordinator.remove(store) }
        let context = NSManagedObjectContext(.mainQueue)
        context.persistentStoreCoordinator = coordinator
        let rows = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "Playlist"))
        return rows.map { "\($0.value(forKey: "name") ?? "-")|\($0.value(forKey: "zukunftsfeld") ?? "-")" }
    }
}
