import XCTest
import SwiftUI
import SwiftData
import AppKit
@testable import MikaPlusPlayer

/// B05 · Reparatur (sdd-build, Fehlerauftrag, 2026-09-30): Belege für BUG-02, BUG-03 (geprüfter Teil) und BUG-09, die die
/// QA-Tests nicht abdecken. Temp-Datenbanken bzw. Datenbank im Speicher, Mock auf 127.0.0.1, erfundene Daten, tonlos.
@MainActor
final class B05ReparaturTests: B05TestCase {

    typealias E = B05QA.E

    private struct Simulated: Error {}

    private func channel(_ name: String, in pl: Playlist) throws -> Channel {
        try XCTUnwrap(pl.channels.first { $0.name == name }, name)
    }

    // MARK: BUG-02 · Speicherfehler beim Stern

    /// Scheitert das Speichern, ist der Stern zurückgesetzt, der Kontext ohne offene Änderung, die Datei unverändert, und
    /// der Fehler kommt beim Aufrufer an (vorher: `try?`). Speicherfehler hier nachgestellt (austauschbares Speichern); auf
    /// einem vollen Datenträger: `B05DatenschutzTests.testAK27_…`.
    func testBUG02_SpeicherfehlerSetztSternZurueckUndMeldetIhn() throws {
        let (c, store) = try fileContainer("bug02")
        let ctx = c.mainContext
        let pl = try seed(ctx, name: "QA BUG-02", [("Kanal A", nil, nil, false, nil), ("Kanal B", nil, nil, true, nil)])
        let a = try channel("Kanal A", in: pl)
        let b = try channel("Kanal B", in: pl)

        XCTAssertThrowsError(try FavoriteEdits.toggle(a, in: ctx, save: { _ in throw Simulated() })) { error in
            XCTAssertEqual(error as? PlaylistStoreError, .starNotSaved)
        }
        XCTAssertThrowsError(try FavoriteEdits.toggle(b, in: ctx, save: { _ in throw Simulated() }))
        B05QA.log("BUILD|BUG-02|nachgestellt|a=\(a.isFavorite)|b=\(b.isFavorite)|hasChanges=\(ctx.hasChanges)|dbA=\(B05QA.dbFavorite(store, name: "Kanal A"))|dbB=\(B05QA.dbFavorite(store, name: "Kanal B"))")
        XCTAssertFalse(a.isFavorite, "Setzen verworfen")
        XCTAssertTrue(b.isFavorite, "Entfernen verworfen")
        XCTAssertFalse(ctx.hasChanges, "nichts Ungespeichertes, das ein späteres Speichern mitschreiben könnte")
        XCTAssertEqual(B05QA.dbFavorite(store, name: "Kanal A"), "0")
        XCTAssertEqual(B05QA.dbFavorite(store, name: "Kanal B"), "1")
        XCTAssertEqual(PlaylistStoreError.starNotSaved.errorDescription,
                       "Der Stern konnte nicht gespeichert werden und ist zurückgesetzt. Bitte freien Speicherplatz prüfen und erneut versuchen.")

        // Danach speichert der nächste Stern nur sich selbst
        XCTAssertNoThrow(try FavoriteEdits.toggle(b, in: ctx))
        XCTAssertEqual(B05QA.dbFavorite(store, name: "Kanal A"), "0")
        XCTAssertEqual(B05QA.dbFavorite(store, name: "Kanal B"), "0")
        XCTAssertFalse(ctx.hasChanges)
    }

    /// Zusammenspiel mit dem Festhalten während des Aktualisierens (Review R-01): Ein verworfener Stern hinterlässt keinen
    /// Eintrag, und ein vorher festgehaltener Stern desselben Senders bleibt, wie er war – sonst zöge `refresh` einen Stern
    /// nach, den die Oberfläche nie gezeigt hat.
    func testBUG02_VerworfenerSternBleibtAuchImFestgehaltenenAus() throws {
        let (c, _) = try fileContainer("bug02-journal")
        let ctx = c.mainContext
        let pl = try seed(ctx, name: "QA BUG-02 R-01", [("Kanal A", nil, nil, false, nil), ("Kanal B", nil, nil, false, nil)])
        let a = try channel("Kanal A", in: pl)
        let b = try channel("Kanal B", in: pl)
        let pid = pl.id
        FavoriteEdits.begin(pid)
        defer { FavoriteEdits.end(pid) }

        XCTAssertNoThrow(try FavoriteEdits.toggle(b, in: ctx))                                      // B gesetzt und festgehalten
        XCTAssertThrowsError(try FavoriteEdits.toggle(a, in: ctx, save: { _ in throw Simulated() }))  // A verworfen
        XCTAssertThrowsError(try FavoriteEdits.toggle(b, in: ctx, save: { _ in throw Simulated() }))  // Entfernen von B verworfen
        let journal = FavoriteEdits.take(pid)
        B05QA.log("BUILD|BUG-02|festgehalten=\(journal.map { "\($0.previous.name)=\($0.isFavorite)" })|a=\(a.isFavorite)|b=\(b.isFavorite)")
        XCTAssertEqual(journal.map(\.channelID), [b.id], "kein Eintrag für den verworfenen Stern von A")
        XCTAssertEqual(journal.map(\.isFavorite), [true], "B bleibt so festgehalten, wie er gespeichert ist")
        XCTAssertFalse(a.isFavorite)
        XCTAssertTrue(b.isFavorite)

        // Ein gelungener Stern wird weiter festgehalten
        XCTAssertNoThrow(try FavoriteEdits.toggle(a, in: ctx))
        XCTAssertEqual(FavoriteEdits.take(pid).map(\.channelID), [a.id])
    }

    // MARK: BUG-03 · was der gemeinsame Logo-Loader im Favoriten-Tab abdeckt

    /// Der Tab lädt Logos über denselben `ChannelLogoLoader` wie die Senderliste (B04). Geprüft im Tab: neutrale Kopfzeilen,
    /// keine Weiterleitung auf einen fremden Host, nichts im Plattencache, erneutes Öffnen ohne erneute Anfrage. Offen bleibt,
    /// dass der Logo-Host beim ersten Öffnen die Favoriten erfährt (Produktfrage, `spec.md` OF-08 bzw. B04 OF-07).
    func testBUG03_FavoritenTabNutztDenGemeinsamenLogoLoader() throws {
        let fremd = MockXtreamServer(handler: { _ in .raw(status: 200, contentType: "image/png", body: Data()) })
        try fremd.start()
        defer { fremd.stop() }
        let png = NSBitmapImageRep(data: NSImage(size: NSSize(width: 16, height: 16), flipped: false) { r in
            NSColor.systemGreen.setFill(); r.fill(); return true
        }.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        routes.setReply("/logos/a.png", .raw(status: 200, contentType: "image/png", body: png))
        routes.setReply("/logos/b.png", .raw(status: 200, contentType: "image/png", body: png))
        routes.setReply("/logos/weiter.png", .redirect(location: "http://\(fremd.hostPort)/ziel.png", status: 302))
        let c = try B05QA.memoryContainer()
        try seed(c.mainContext, name: "QA Logos BUG-03", [
            (name: "Logo A", group: nil, tvg: nil, fav: true, logo: url("/logos/a.png")),
            (name: "Logo B", group: nil, tvg: nil, fav: false, logo: url("/logos/b.png")),
            (name: "Logo Weiter", group: nil, tvg: nil, fav: true, logo: url("/logos/weiter.png")),
        ])
        mock.resetLog()

        let tab = window(NavigationStack { FavoritesView() }, c, size: CGSize(width: 760, height: 420))
        B05QA.wait(4.0) { self.mock.requests.count >= 2 }
        B05QA.spin(1.0)
        let first = mock.requests
        let logoA = try XCTUnwrap(first.first { $0.path == "/logos/a.png" }, "\(first.map(\.path))")
        let aURL = try XCTUnwrap(URL(string: url("/logos/a.png")))
        let inURLCache = URLCache.shared.cachedResponse(for: URLRequest(url: aURL)) != nil
        let inMemory = ChannelLogoLoader.shared.cachedImage(for: aURL) != nil
        B05QA.log("BUILD|BUG-03|erstesOeffnen|pfade=\(first.map(\.path).sorted())|fremderHost=\(fremd.requests.count)|kopfzeilen=\(logoA.headers.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" })|plattencache=\(inURLCache)|arbeitsspeicher=\(inMemory)")
        XCTAssertEqual(logoA.headers["user-agent"], "Mozilla/5.0", "kein App-Name, kein Build, keine Systemversion")
        XCTAssertEqual(logoA.headers["accept-language"], "*", "keine Systemsprache")
        XCTAssertNil(logoA.headers["cookie"])
        XCTAssertNil(logoA.headers["referer"])
        XCTAssertEqual(fremd.requests.count, 0, "Weiterleitung auf einen fremden Host wird nicht gefolgt")
        XCTAssertFalse(inURLCache, "kein Plattencache")
        XCTAssertTrue(inMemory, "Bild nur im Arbeitsspeicher")
        XCTAssertFalse(first.contains { $0.path == "/logos/b.png" }, "nur sichtbare Karten laden")

        tab.close()
        B05QA.spin(0.5)
        mock.resetLog()
        _ = window(NavigationStack { FavoritesView() }, c, size: CGSize(width: 760, height: 420))
        B05QA.spin(2.0)
        let again = mock.requests.map(\.path).sorted()
        B05QA.log("BUILD|BUG-03|erneutesOeffnen|pfade=\(again)|fremderHost=\(fremd.requests.count)")
        XCTAssertFalse(again.contains("/logos/a.png"), "geladenes Logo wird nicht erneut angefragt")
        XCTAssertEqual(fremd.requests.count, 0)
    }

    // MARK: BUG-09 · Steuerzeichen beim Anlegen

    /// Xtream: Steuerzeichen in Name, `epg_channel_id` und Kategoriename werden beim Anlegen entfernt, Leerraum bleibt
    /// (Zeilenumbruch in einer Gruppe, B04 AK-11); der Favorit übersteht ein unverändertes Aktualisieren.
    func testBUG09_XtreamSteuerzeichenEntferntFavoritBleibt() async throws {
        let c = try B05QA.memoryContainer()  // Container festhalten, sonst verliert der Kontext ihn
        let ctx = c.mainContext
        let streams: [[String: Any]] = [
            ["name": "DE: Null\u{0000}Sender", "stream_id": 1, "epg_channel_id": "null\u{0000}.de", "category_id": "1"],
            ["name": "Esc\u{1B}[31mRot", "stream_id": 2, "epg_channel_id": "", "category_id": "2"],
            ["name": "Tab\tSender", "stream_id": 3, "epg_channel_id": "\u{0001}", "category_id": "3"],
        ]
        let categories: [[String: Any]] = [
            ["category_id": "1", "category_name": "Deutsch\u{0000}land"],
            ["category_id": "2", "category_name": "News\n"],
            ["category_id": "3", "category_name": "\u{0007}"],
        ]
        let r = routes
        let panel = MockXtreamServer.panel(streams: streams, categories: categories)
        mock.handler = { req in req.path == "/player_api.php" ? panel(req) : (r.get(req.path) ?? .raw(status: 404, contentType: "text/plain", body: Data())) }
        let pl = try await importXtream(ctx, name: "QA BUG-09 Xtream")
        let stored = pl.channels.sorted { $0.streamURL.absoluteString < $1.streamURL.absoluteString }
            .map { "\($0.name.debugDescription)|\($0.tvgID.debugDescription)|\($0.group.debugDescription)|\($0.favoriteKey.debugDescription)" }
        B05QA.log("BUILD|BUG-09|xtream|gespeichert=\(stored)")
        XCTAssertEqual(Set(pl.channels.map(\.name)), ["DE: NullSender", "Esc[31mRot", "Tab\tSender"])
        let null = try channel("DE: NullSender", in: pl)
        XCTAssertEqual(null.tvgID, "null.de")
        XCTAssertEqual(null.group, "Deutschland")
        XCTAssertEqual(try channel("Esc[31mRot", in: pl).group, "News\n", "Zeilenumbruch bleibt (B04 AK-11)")
        let tab = try channel("Tab\tSender", in: pl)
        XCTAssertNil(tab.tvgID, "nur aus Steuerzeichen → keine tvg-id")
        XCTAssertNil(tab.group, "nur aus Steuerzeichen → keine Gruppe")

        for name in ["DE: NullSender", "Esc[31mRot", "Tab\tSender"] { try B05QA.setFavorite(pl, name, ctx: ctx) }
        let before = try B05QA.favLabels(ctx)
        try await refreshXtream(ctx, pl)
        let after = try B05QA.favLabels(ctx)
        B05QA.log("BUILD|BUG-09|xtream|favoriten vorher=\(before)|nachher=\(after)")
        XCTAssertEqual(after, before, "alle drei Favoriten bleiben")
    }

    /// Ein vor der Reparatur gespeicherter Sender mit Steuerzeichen (hier ESC, das die Datei vollständig speichert) behält
    /// seinen Stern beim ersten Aktualisieren danach: Der Schlüssel ignoriert Steuerzeichen wie der Import.
    func testBUG09_AltbestandMitSteuerzeichenBehaeltDenStern() async throws {
        let (c, store) = try fileContainer("bug09-alt")
        let ctx = c.mainContext
        let path = "/b05/bug09-alt.m3u"
        let es = [E(name: "Alt\u{1B}[1mSender", url: B05QA.stream(1)), E(name: "Kontrolle", url: B05QA.stream(2))]
        let pl = try await importM3U(ctx, path: path, name: "QA BUG-09 Alt", es)
        // Stand vor der Reparatur nachstellen: Name mit ESC in der Datei
        let alt = try channel("Alt[1mSender", in: pl)
        alt.name = "Alt\u{1B}[1mSender"
        alt.isFavorite = true
        try ctx.save()
        let fileName = B05QA.rows(store.path, "SELECT ZNAME FROM ZCHANNEL WHERE ZISFAVORITE = 1").first?.first ?? "?"
        XCTAssertEqual(fileName, "Alt\u{1B}[1mSender")
        XCTAssertEqual(alt.favoriteKey, "name:alt[1msender")

        try await refreshM3U(ctx, pl, path: path, es)
        let after = try B05QA.favLabels(ctx)
        B05QA.log("BUILD|BUG-09|altbestand|dateiVorher=\(fileName.debugDescription)|favoritenNachher=\(after)")
        XCTAssertEqual(after, ["Alt[1mSender@QA BUG-09 Alt"], "Stern bleibt, Name jetzt ohne Steuerzeichen")
    }

    /// Nur Steuerzeichen U+0000–U+001F und U+007F außer Leerraum: Tabulator und Zeilenumbrüche bleiben, ebenso
    /// Formatzeichen (U+202E) und die Zeichen U+0080–U+009F aus dem Latin-1-Rückfall (B02 OF-06).
    func testBUG09_WelcheZeichenEntferntWerden() {
        XCTAssertEqual(Channel.removingControlCharacters("A\u{0000}B\u{0001}C\u{001F}D\u{007F}E\u{001B}[0m"), "ABCDE[0m")
        XCTAssertEqual(Channel.removingControlCharacters("Tab\tLF\nCR\rVT\u{0B}FF\u{0C}"), "Tab\tLF\nCR\rVT\u{0B}FF\u{0C}")
        XCTAssertEqual(Channel.removingControlCharacters("Rechts\u{202E}links Ã\u{84}rger \u{80}"), "Rechts\u{202E}links Ã\u{84}rger \u{80}")
        XCTAssertEqual(Channel.removingControlCharacters("📺 ZDF"), "📺 ZDF")
        XCTAssertEqual(Channel.favoriteKey(name: "X", tvgID: "\u{0000}"), "name:x", "tvg-id nur aus Steuerzeichen zählt als leer")
        XCTAssertEqual(Channel.favoriteKey(name: "X", tvgID: " "), "id: ", "Leerzeichen-tvg-id unverändert (EC-03)")
        let parsed = ParsedChannel(name: "N\u{0}", streamURL: URL(string: "http://h/a.ts")!, logoURL: nil, group: "", tvgID: "")
        let cleaned = parsed.withoutControlCharacters
        XCTAssertEqual(cleaned.name, "N")
        XCTAssertEqual(cleaned.group, "", "leer bleibt leer (nicht durch die Bereinigung entstanden)")
        XCTAssertEqual(cleaned.tvgID, "")
    }

    /// Review F-04 (B05-Abschluss): Mehrere Kandidaten mit demselben Schlüssel, neue Stream-Adressen, alter Favorit mit
    /// Steuerzeichen im gespeicherten Namen – der Stern geht an den Sender mit demselben Namen, unabhängig von der
    /// Reihenfolge des Anbieters (vorher: erster Kandidat, weil „ZDF HD\u{1B}“ ≠ „ZDF HD“).
    func testBUG09_NamensvergleichDerUebernahmeIgnoriertSteuerzeichenImAltbestand() {
        let alt = FavoriteCarryOver.Previous(key: Channel.favoriteKey(name: "ZDF HD\u{1B}", tvgID: "zdf.de"),
                                             streamURL: URL(string: B05QA.stream(1))!, name: "ZDF HD\u{1B}")
        let hd = ParsedChannel(name: "ZDF HD", streamURL: URL(string: B05QA.stream(11))!, logoURL: nil, group: nil, tvgID: "zdf.de")
        let sd = ParsedChannel(name: "ZDF SD", streamURL: URL(string: B05QA.stream(12))!, logoURL: nil, group: nil, tvgID: "zdf.de")
        XCTAssertEqual(FavoriteCarryOver.flags(previous: [alt], new: [sd, hd]), [false, true], "SD zuerst: Stern an „ZDF HD“")
        XCTAssertEqual(FavoriteCarryOver.flags(previous: [alt], new: [hd, sd]), [true, false], "HD zuerst: Stern an „ZDF HD“")
    }
}
