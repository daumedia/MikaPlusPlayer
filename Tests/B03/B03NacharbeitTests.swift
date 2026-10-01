import XCTest
import SwiftData
@testable import MikaPlusPlayer

/// B02+B03 · Nacharbeit nach dem Review vom 2026-09-27 (Funde R-01 bis R-11), Teil Aktualisieren/Löschen.
/// Temp-Datenbanken, Test-Schlüsselbunddienst dieses Laufs, Mock auf 127.0.0.1, erfundene Daten, tonlos.
///
/// Umgebungsvariablen (bei `xcodebuild` mit Präfix `TEST_RUNNER_`):
/// - `B03_R01_RUNDEN` (Standard 2) · `B03_R01_ARTEN` (Standard `m3u,xtream`) · `B03_R01_SENDER` (Standard 17000)
final class B03NacharbeitTests: B03QATestCase {

    private var env: [String: String] { ProcessInfo.processInfo.environment }

    // MARK: R-01 · Sterne während des Aktualisierens

    /// Setzt den Stern genau wie `ChannelRowView`.
    @MainActor private func tapStar(_ channel: Channel, _ ctx: ModelContext) {
        XCTAssertNoThrow(try FavoriteEdits.toggle(channel, in: ctx))
    }

    @MainActor private func channel(_ name: String, of pid: UUID, _ ctx: ModelContext) throws -> Channel {
        let found = try ctx.fetch(FetchDescriptor<Channel>(predicate: #Predicate { $0.playlistID == pid && $0.name == name }))
        return try XCTUnwrap(found.first, "Sender \(name)")
    }

    @MainActor private func importLarge(_ kind: String, _ n: Int, _ ctx: ModelContext) async throws -> Playlist {
        var cfg = B03QAPanel()
        if kind == "m3u" {
            cfg.m3u = B03QA.m3u((0..<n).map { ("Sender \($0)", "s.\($0)", "Gruppe \($0 % 40)", "\(B03QA.dead)/\($0).m3u8") })
            mock.handler = cfg.handler()
            return try await PlaylistImporter(modelContext: ctx).importFromURL(m3uAddress, name: "QA R-01")
        }
        cfg.streams = B03QA.streams((0..<n).map { ("Sender \($0)", $0, "s.\($0)", $0 % 2 == 0 ? "1" : "2") })
        mock.handler = cfg.handler()
        return try await PlaylistImporter(modelContext: ctx, loginThrottle: XtreamLoginThrottle()).importFromXtream(
            XtreamCredentials(host: mock.hostPort, username: "qa-user", password: "qa-pass-b03-r01"), output: .mpegts, name: "QA R-01")
    }

    /// R-01: 17.000 Sender, Aktualisieren im Hintergrund; währenddessen werden 10 Sterne gesetzt und einer entfernt.
    /// Soll: alle 10 Sterne und die Entfernung überstehen das Ersetzen, der Kontrollfavorit bleibt, die Oberfläche
    /// blockiert nicht (Wachhund ≤ 1 s wie AK-37).
    @MainActor func testR01_SterneWaehrendDesAktualisierensBleibenErhalten() async throws {
        let rounds = Int(env["B03_R01_RUNDEN"] ?? "") ?? 2
        let kinds = (env["B03_R01_ARTEN"] ?? "m3u,xtream").split(separator: ",").map(String.init)
        let n = Int(env["B03_R01_SENDER"] ?? "") ?? 17_000
        var summary: [String] = []
        for kind in kinds {
            for round in 1...(kind == "m3u" ? rounds : max(1, rounds - 1)) {
                let (container, storeURL) = try fileContainer("r01-\(kind)-\(round)")
                let ctx = container.mainContext
                let t0 = Date()
                let p = try await importLarge(kind, n, ctx)
                let tImport = Date().timeIntervalSince(t0)
                let pid = p.id
                XCTAssertEqual(p.channelCount, n)

                // vor dem Lauf: zwei Favoriten (einer wird während des Laufs entfernt, einer ist Kontrolle)
                let removeLater = try channel("Sender \(n - 1)", of: pid, ctx)
                let control = try channel("Sender \(n - 2)", of: pid, ctx)
                tapStar(removeLater, ctx)
                tapStar(control, ctx)
                // Sender, die gleich einen Stern bekommen – wie die Zeilen der Ansicht vorher geladen
                let targets = try (1...10).map { try channel("Sender \($0 * 97)", of: pid, ctx) }
                XCTAssertEqual(targets.filter(\.isFavorite).count, 0)
                try await Task.sleep(nanoseconds: 300_000_000)

                let finished = RVFlag()
                let wd = B03QAWatchdog(); wd.start()
                let tRefresh0 = Date()
                let refresh = Task { @MainActor in
                    defer { finished.set() }
                    try await PlaylistImporter(modelContext: ctx, loginThrottle: XtreamLoginThrottle()).refresh(p)
                }
                // Sterne über den Lauf verteilt (Abstand aus der Importdauer; das Ersetzen dauert länger als der Import):
                // ungerade Runden dicht am Anfang, gerade Runden bis in die zweite Hälfte des Laufs; der erste sofort
                let interval = max(0.05, round % 2 == 1 ? tImport / 14 : tImport / 6.5)
                var setDuring: [String] = []
                var timeline: [String] = []
                for (i, target) in targets.enumerated() {
                    if i > 0 { try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000)) }
                    guard !finished.value else { break }
                    tapStar(target, ctx)
                    setDuring.append(target.name)
                    timeline.append("\(target.name)@\(B03QA.f2(Date().timeIntervalSince(tRefresh0)))s")
                    if i == 4 {
                        tapStar(removeLater, ctx)   // Stern während des Laufs entfernen
                        timeline.append("-\(removeLater.name)@\(B03QA.f2(Date().timeIntervalSince(tRefresh0)))s")
                    }
                }
                try await refresh.value
                let tRefresh = Date().timeIntervalSince(tRefresh0)
                try await Task.sleep(nanoseconds: 300_000_000)
                let gap = wd.stop()

                // Ergebnis in der Datei (eigene Verbindung) und in einem frischen Kontext
                let inFile = Set(B03QA.rows(storeURL.path, "select ZNAME from ZCHANNEL where ZISFAVORITE = 1").map { $0[0] })
                let fresh = ModelContext(container)
                let freshFavorites = Set(try fresh.fetch(FetchDescriptor<Channel>(predicate: #Predicate { $0.playlistID == pid && $0.isFavorite == true })).map(\.name))
                let total = B03QA.int(storeURL.path, "select count(*) from ZCHANNEL")
                let orphans = B03QA.int(storeURL.path, "select count(*) from ZCHANNEL where ZPLAYLIST is null")
                let kept = setDuring.filter { inFile.contains($0) }
                let line = "R-01|\(kind)|runde=\(round)|sender=\(n)|import=\(B03QA.f2(tImport))s|aktualisieren=\(B03QA.f2(tRefresh))s|"
                    + "gesetztWaehrendDesLaufs=\(setDuring.count)|erhalten=\(kept.count)|entferntBleibtEntfernt=\(!inFile.contains(removeLater.name))|"
                    + "kontrolle=\(inFile.contains(control.name))|favoritenDatei=\(inFile.count)|sender=\(total)|ohnePlaylist=\(orphans)|"
                    + "mainThreadBlockade=\(B03QA.f2(gap))s|build=\(B03QA.buildConfiguration)|verlauf=\(timeline.joined(separator: ","))"
                B03QA.log(line)
                summary.append("\(kind)#\(round): \(kept.count)/\(setDuring.count)")

                XCTAssertEqual(setDuring.count, 10, "alle 10 Sterne fallen in den Lauf (\(line))")
                XCTAssertEqual(kept, setDuring, "Sterne während des Laufs verloren: \(Set(setDuring).subtracting(inFile).sorted())")
                XCTAssertFalse(inFile.contains(removeLater.name), "während des Laufs entfernter Stern ist zurück")
                XCTAssertTrue(inFile.contains(control.name), "Favorit von vorher verloren")
                XCTAssertEqual(inFile, Set(setDuring).union([control.name]), "genau diese Favoriten")
                XCTAssertEqual(freshFavorites, inFile)
                XCTAssertEqual(total, n)
                XCTAssertEqual(orphans, 0)
                XCTAssertLessThanOrEqual(gap, 1, "Oberfläche blockiert \(B03QA.f2(gap)) s")
                try await PlaylistImporter(modelContext: ctx).delete(p)
            }
        }
        B03QA.log("R-01|ergebnis|\(summary.joined(separator: " · "))")
    }

    /// R-01, engstes Fenster: Das Ersetzen ist schon gespeichert (die alten Sender sind in der Datei gelöscht), die
    /// Ansicht zeigt aber noch die alten Sender, weil das Aktualisieren noch nicht auf dem Main-Actor weitergelaufen ist.
    /// Sterne in genau diesem Moment (an alten Sendern) müssen ebenfalls auf die neuen Sender übergehen. Der Moment wird
    /// über den Test-Haken des Stores getroffen: Er läuft nach dem Speichern und wartet, bis die Sterne gesetzt sind.
    @MainActor func testR01b_SterneZwischenErsetzenUndAbholen() async throws {
        let n = 5_000
        let (container, storeURL) = try fileContainer("r01b")
        let ctx = container.mainContext
        let p = try await importLarge("m3u", n, ctx)
        let pid = p.id
        let unstar = try channel("Sender 4000", of: pid, ctx)
        tapStar(unstar, ctx)
        let targets = try [11, 22, 33].map { try channel("Sender \($0)", of: pid, ctx) }
        let oldID = targets[0].id.uuidString
        let probe = RVBox("")
        let captured = RVBox((targets: targets, unstar: unstar, ctx: ctx))
        let hook: @Sendable () -> Void = {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    let (targets, unstar, ctx) = captured.value
                    let oldRowsLeft = B03QA.rows(storeURL.path, "select count(*) from ZCHANNEL where ZNAME = 'Sender 11'").first?.first ?? "?"
                    for target in targets + [unstar] {
                        do { try FavoriteEdits.toggle(target, in: ctx) } catch { XCTFail("Stern nicht gespeichert: \(error)") }
                    }
                    probe.value = "senderMitNameInDatei=\(oldRowsLeft)|speichernDerAnsichtOhneFehler=\(!ctx.hasChanges)"
                }
            }
        }
        let store = PlaylistStore()
        await store.setAfterReplaceSavedForTesting(hook)
        try await PlaylistImporter(modelContext: ctx, loginThrottle: XtreamLoginThrottle(), store: store).refresh(p)

        let inFile = Set(B03QA.rows(storeURL.path, "select ZNAME from ZCHANNEL where ZISFAVORITE = 1").map { $0[0] })
        let total = B03QA.int(storeURL.path, "select count(*) from ZCHANNEL")
        let orphans = B03QA.int(storeURL.path, "select count(*) from ZCHANNEL where ZPLAYLIST is null")
        let oldLeft = B03QA.int(storeURL.path, "select count(*) from ZCHANNEL where hex(ZID) = '\(oldID.replacingOccurrences(of: "-", with: ""))'")
        B03QA.log("R-01b|\(probe.value)|favoritenDatei=\(inFile.sorted())|sender=\(total)|ohnePlaylist=\(orphans)|alterSenderInDatei=\(oldLeft)|kontextHatAenderungen=\(ctx.hasChanges)")
        XCTAssertFalse(probe.value.isEmpty, "Haken nicht gelaufen")
        XCTAssertEqual(inFile, Set(targets.map(\.name)), "Sterne aus dem Moment zwischen Ersetzen und Abholen")
        XCTAssertEqual(total, n)
        XCTAssertEqual(orphans, 0)
        XCTAssertEqual(oldLeft, 0, "alter Sender wieder in der Datei")
        XCTAssertFalse(ctx.hasChanges, "Ansicht hängt nicht auf ungespeicherten Änderungen")
        let shown = Set(try ctx.fetch(FetchDescriptor<Channel>(predicate: #Predicate { $0.playlistID == pid && $0.isFavorite == true })).map(\.name))
        XCTAssertEqual(shown, inFile, "Ansicht zeigt dieselben Sterne")
    }
}

extension B03NacharbeitTests {

    // MARK: R-04 · „Alle Daten entfernen" im B09-Rückfall

    /// R-04: Läuft die Sitzung im Speicher (B09 `inMemoryFallback`), liegt die beiseitegelegte Datenbank trotzdem am
    /// Speicherort der App. Soll: „Alle Daten entfernen" erreicht diesen Ordner (hier: Temp-Ordner als Speicherort).
    @MainActor func testR04_AlleDatenEntfernenImRueckfallErreichtBeiseitegelegt() async throws {
        let dir = try tempDir("r04")
        let appStore = dir.appendingPathComponent(AppPersistence.storeFileName)
        // wie `openStore` im Rückfall: alte Datei beiseitegelegt, Sitzung im Speicher
        try Data("kaputt".utf8).write(to: appStore)
        let movedTo = try AppPersistence.moveStoreAside(appStore, now: Date())
        let memory = AppPersistence.inMemoryContainer(schema: AppSchema.schema)
        XCTAssertNil(PlaylistStore.storeURL(of: memory))
        let folder = AppDataReset.Targets.setAsideFolder(container: memory, appStoreURL: appStore)
        let appTargets = AppDataReset.Targets.app(container: memory)
        B03QA.log("R-04|beiseitegelegt=\(movedTo.path.replacingOccurrences(of: dir.path, with: "…"))|ziel=\(folder?.path.replacingOccurrences(of: dir.path, with: "…") ?? "nil")|testHost(app)=\(appTargets.setAsideFolder?.path ?? "nil")")
        XCTAssertEqual(folder?.standardizedFileURL, movedTo.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL)
        XCTAssertNil(appTargets.setAsideFolder, "im Test-Host nie der Ordner der echten App")
        var targets = AppDataReset.Targets()
        targets.httpCache = URLCache(memoryCapacity: 0, diskCapacity: 0)
        targets.setAsideFolder = folder
        try await AppDataReset.eraseAll(context: memory.mainContext, targets: targets)
        XCTAssertFalse(FileManager.default.fileExists(atPath: movedTo.path), "beiseitegelegte Datenbank entfernt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder?.path ?? "/"), "Ordner Beiseitegelegt entfernt")
    }

    // MARK: R-11 · Gemeinsamer Cookie-Speicher

    /// R-11: „Alle Daten entfernen" leert auch den gemeinsamen Cookie-Speicher der App (dort legten M3U-Abrufe bis
    /// Version 1.1 Cookies ab). Geprüft mit einem eigenen Speicher im Arbeitsspeicher – der echte gehört der App.
    @MainActor func testR11_AlleDatenEntfernenLeertGemeinsamenCookieSpeicher() async throws {
        let jar = NBCookieJar()
        for (name, host) in [("nbqaAlt", "anbieter.example"), ("nbqaZwei", "127.0.0.1")] {
            jar.setCookie(try XCTUnwrap(HTTPCookie(properties: [.name: name, .value: "qa-pass-nb-r11", .domain: host, .path: "/",
                                                                 .expires: Date().addingTimeInterval(86_400)])))
        }
        XCTAssertEqual(jar.cookies?.count, 2)
        let memory = AppPersistence.inMemoryContainer(schema: AppSchema.schema)
        var targets = AppDataReset.Targets()
        targets.httpCache = URLCache(memoryCapacity: 0, diskCapacity: 0)
        targets.sharedCookies = jar
        try await AppDataReset.eraseAll(context: memory.mainContext, targets: targets)
        B03QA.log("R-11|cookiesDanach=\(jar.cookies?.count ?? -1)|testHost(app)=\(AppDataReset.Targets.app(container: memory).sharedCookies == nil ? "unangetastet" : "shared")")
        XCTAssertEqual(jar.cookies?.count, 0)
        XCTAssertNil(AppDataReset.Targets.app(container: memory).sharedCookies, "im Test-Host nie der Speicher der echten App")
        XCTAssertNil(AppDataReset.Targets().sharedCookies, "Standard lässt den gemeinsamen Speicher stehen")
    }
}

/// Cookie-Speicher nur im Arbeitsspeicher (für R-11).
final class NBCookieJar: HTTPCookieStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [HTTPCookie] = []
    override var cookies: [HTTPCookie]? { lock.withLock { stored } }
    override func setCookie(_ cookie: HTTPCookie) { lock.withLock { stored.append(cookie) } }
    override func deleteCookie(_ cookie: HTTPCookie) { lock.withLock { stored.removeAll { $0 == cookie } } }
}

final class RVBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T
    init(_ value: T) { _value = value }
    var value: T {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

final class RVFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false
    var value: Bool { lock.withLock { _value } }
    func set() { lock.withLock { _value = true } }
}
