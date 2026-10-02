import Foundation
import SwiftData
import XCTest
@testable import MikaPlusPlayer

/// B09 · Auto-Update — Bau Durchlauf 2 (2026-10-02): eigene Debug-Bundle-ID (BF-119, OF-10) und Hinweistexte (OF-08).
///
/// Reine Logik in Temp-Ordnern: kein echter Schlüsselbund-Dienst, keine Datenbank des Nutzers.
final class B09Bau2Tests: XCTestCase {
    private var tempDirs: [URL] = []

    override func tearDown() {
        for dir in tempDirs {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
            try? FileManager.default.removeItem(at: dir)
        }
        tempDirs.removeAll()
        super.tearDown()
    }

    private func tempDir(_ label: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("b09-bau2-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDirs.append(dir)
        return dir
    }

    // MARK: - BF-119 · Test-Host-Erkennung

    /// Die Umgebungsmarke der Testaktion (`project.yml`) allein genügt, um den Test-Host zu erkennen.
    func testBF119_TestHostErkennungUeberUmgebungsmarke() {
        XCTAssertTrue(AppEnvironment.detectTests(environment: ["MIKA_TEST_HOST": "1"], xcTestLoaded: false), "Marke")
        XCTAssertTrue(AppEnvironment.detectTests(environment: ["XCTestConfigurationFilePath": "/x"], xcTestLoaded: false), "XCTest-Variable")
        XCTAssertTrue(AppEnvironment.detectTests(environment: [:], xcTestLoaded: true), "XCTest geladen")
        XCTAssertFalse(AppEnvironment.detectTests(environment: ["MIKA_TEST_HOST": "0"], xcTestLoaded: false), "Marke aus")
        XCTAssertFalse(AppEnvironment.detectTests(environment: [:], xcTestLoaded: false), "normaler Start")
        XCTAssertTrue(AppEnvironment.isRunningTests)
    }

    // MARK: - BF-119 · Schlüsselbund-Dienst aus der Bundle-ID

    func testBF119_SchluesselbundDienstAusBundleID() {
        XCTAssertEqual(XtreamCredentialStore.serviceName(bundleID: "lu.daumedia.MikaPlusPlayer", isRunningTests: false),
                       "lu.daumedia.MikaPlusPlayer.xtream", "Release unverändert (keine Migration)")
        XCTAssertEqual(XtreamCredentialStore.serviceName(bundleID: "lu.daumedia.MikaPlusPlayer.debug", isRunningTests: false),
                       "lu.daumedia.MikaPlusPlayer.debug.xtream", "Debug-Build eigener Dienst")
        let a = XtreamCredentialStore.serviceName(bundleID: "lu.daumedia.MikaPlusPlayer.debug", isRunningTests: true)
        let b = XtreamCredentialStore.serviceName(bundleID: "lu.daumedia.MikaPlusPlayer.debug", isRunningTests: true)
        XCTAssertTrue(a.hasPrefix("lu.daumedia.MikaPlusPlayer.xtream.tests."), "Test-Host: unverändertes Präfix, auf das die Wächter prüfen")
        XCTAssertNotEqual(a, b, "je Lauf eigener Dienst")
        XCTAssertTrue(XtreamCredentialStore.standard.service.hasPrefix("lu.daumedia.MikaPlusPlayer.xtream.tests."))
    }

    // MARK: - BF-119 · Altbestand nur für die Release-ID

    /// Eine alte `Application Support/default.store` wird nur übernommen, wenn die übergebene Bundle-ID die Release-ID
    /// ist; ein Debug-Build lässt sie liegen (sonst zöge er die Daten der installierten App zu sich).
    func testBF119_AltbestandNurFuerReleaseIDUebernommen() async throws {
        let support = try tempDir("altbestand")
        let legacy = support.appendingPathComponent(AppPersistence.legacyStoreFileName)
        do {
            let container = try AppPersistence.diskContainer(at: legacy, schema: AppSchema.schema)
            let context = ModelContext(container)
            context.insert(Playlist(name: "Altbestand"))
            try context.save()
        }
        try await Task.sleep(nanoseconds: 800_000_000)
        let vorher = try Data(contentsOf: legacy)

        let (debugURL, debugOutcome) = AppPersistence.prepareStore(applicationSupport: support,
                                                                   bundleID: "lu.daumedia.MikaPlusPlayer.debug")
        print("B09BAU2|BF-119|altbestand|debug=\(debugOutcome)")
        XCTAssertEqual(debugOutcome, .otherBundleID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: debugURL.path), "Debug legt keine Kopie an")
        XCTAssertEqual(try Data(contentsOf: legacy), vorher, "Altbestand unverändert")

        let (_, releaseOutcome) = AppPersistence.prepareStore(applicationSupport: support, bundleID: AppEnvironment.releaseBundleID)
        XCTAssertEqual(releaseOutcome, .adopted, "Release übernimmt weiterhin")
    }

    // MARK: - OF-08 · Hinweistexte

    private let movedTo = URL(fileURLWithPath: "/Users/qa/Library/Application Support/x/Beiseitegelegt/2026-10-02_10-00-00/MikaPlusPlayer.store")
    private var folder: URL { movedTo.deletingLastPathComponent() }

    func testOF08_HinweisNeuAngelegtMacOS() throws {
        let notice = try XCTUnwrap(AppPersistence.StoreOpenOutcome.recovered(movedTo: movedTo, reason: "r").notice(for: .macOS))
        XCTAssertEqual(notice.title, "Datenbank neu angelegt")
        XCTAssertTrue(notice.message.contains(folder.path), "macOS nennt den Ordner")
        XCTAssertTrue(notice.message.contains("Schlüsselbund"), "Zugangsdaten im Schlüsselbund genannt")
        XCTAssertTrue(notice.message.contains("„Alle Daten entfernen …“ im App-Menü"), "Löschweg macOS")
        XCTAssertEqual(notice.folder, folder, "„Im Finder zeigen“")
    }

    func testOF08_HinweisNeuAngelegtIOSOhnePfad() throws {
        let notice = try XCTUnwrap(AppPersistence.StoreOpenOutcome.recovered(movedTo: movedTo, reason: "r").notice(for: .iOS))
        XCTAssertEqual(notice.title, "Datenbank neu angelegt")
        XCTAssertFalse(notice.message.contains("/Users/qa"), "iOS ohne Pfad")
        XCTAssertTrue(notice.message.contains("beiseitegelegt"))
        XCTAssertTrue(notice.message.contains("Schlüsselbund"))
        XCTAssertTrue(notice.message.contains("„Alle Daten entfernen …“ im Menü der Playlist-Übersicht"), "Löschweg iOS")
        XCTAssertNil(notice.folder)
    }

    func testOF08_HinweisNichtVerfuegbar() throws {
        typealias O = AppPersistence.StoreOpenOutcome
        let verschoben = try XCTUnwrap(O.inMemoryFallback(movedTo: movedTo, keptInPlace: false, reason: "r").notice(for: .macOS))
        XCTAssertEqual(verschoben.title, "Datenbank nicht verfügbar")
        XCTAssertTrue(verschoben.message.contains(folder.path))
        XCTAssertTrue(verschoben.message.contains("Schlüsselbund"))
        XCTAssertTrue(verschoben.message.contains("„Alle Daten entfernen …“"))

        let verschobenIOS = try XCTUnwrap(O.inMemoryFallback(movedTo: movedTo, keptInPlace: false, reason: "r").notice(for: .iOS))
        XCTAssertFalse(verschobenIOS.message.contains("/Users/qa"), "iOS ohne Pfad")
        XCTAssertNil(verschobenIOS.folder)

        let liegtNoch = try XCTUnwrap(O.inMemoryFallback(movedTo: nil, keptInPlace: true, reason: "r").notice(for: .macOS))
        XCTAssertTrue(liegtNoch.message.contains("liegt unverändert am bisherigen Ort"), "Beiseitelegen gescheitert")

        let keineDatei = try XCTUnwrap(O.inMemoryFallback(movedTo: nil, keptInPlace: false, reason: "r").notice(for: .macOS))
        XCTAssertFalse(keineDatei.message.contains("bisherige Datenbank"), "ohne alte Datei keine Aussage über sie")
    }

    /// Ordner ohne Schreibrecht und **ohne** vorhandene Datei: nichts beiseitezulegen, also keine Aussage über eine alte Datei.
    func testOF08_OhneDateiKeineAussageUeberBisherigeDatenbank() throws {
        let dir = try tempDir("ohnedatei")
        let storeURL = dir.appendingPathComponent(AppPersistence.storeFileName)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        let (_, outcome) = AppPersistence.openStore(at: storeURL, schema: AppSchema.schema)
        guard case .inMemoryFallback(let movedTo, let keptInPlace, _) = outcome else {
            return XCTFail("erwartet .inMemoryFallback, erhalten \(outcome)")
        }
        XCTAssertNil(movedTo)
        XCTAssertFalse(keptInPlace)
    }
}
