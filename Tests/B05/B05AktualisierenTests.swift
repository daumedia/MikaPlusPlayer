import XCTest
import SwiftUI
import SwiftData
import AppKit
@testable import MikaPlusPlayer

/// B05 · Erhalt der Favoriten beim Aktualisieren (AK-11 bis AK-19, EC-01 bis EC-05, EC-11). Aktualisieren über den
/// echten `PlaylistImporter.refresh` gegen den lokalen Mock (M3U und `player_api.php`), erfundene Listen und
/// Zugangsdaten (`qa-user` / `qa-pass-123`).
@MainActor
final class B05AktualisierenTests: B05TestCase {

    typealias E = B05QA.E
    private func u(_ n: Int) -> String { B05QA.stream(n) }

    // MARK: AK-11 · AK-12 · AK-13 · AK-14 (M3U)

    func testAK11_AK12_AK13_AK14_SchluesselUndVerlustM3U() async throws {
        let c = try B05QA.memoryContainer()
        let ctx = c.mainContext
        let path = "/b05/ak11.m3u"
        let v1: [E] = [
            E(name: "Alpha", tvg: "alpha.de", url: u(1)),
            E(name: "Beta", tvg: "beta.de", url: u(2)),
            E(name: "Gamma", tvg: "gamma.de", url: u(3)),
            E(name: "Sport1", url: u(4)),
            E(name: "München TV", url: u(5)),
            E(name: "Straße TV", url: u(6)),
            E(name: "İstanbul TV", url: u(7)),
            E(name: "Café Kanal", url: u(8)),
            E(name: "Kanal  Zwei", url: u(9)),
            E(name: "ARD", tvg: "ard.de", url: u(10)),
            E(name: "Tagesschau24", url: u(11)),
            E(name: "Phoenix", tvg: "phoenix.de", url: u(12)),
            E(name: "KiKA", tvg: "kika.de", url: u(13)),
            E(name: "Rand TV", url: u(14)),
        ]
        let pl = try await importM3U(ctx, path: path, name: "QA M3U", v1)
        let starred = ["Beta", "Sport1", "München TV", "Straße TV", "İstanbul TV", "Café Kanal", "Kanal  Zwei", "ARD",
                       "Tagesschau24", "Phoenix", "KiKA", "Rand TV"]
        for n in starred { try B05QA.setFavorite(pl, n, ctx: ctx) }
        let keys = pl.channels.filter(\.isFavorite).map(\.favoriteKey).sorted()
        B05QA.evidence("AK-11-14-m3u.txt", "stufe1|favoriten=\(try B05QA.favLabels(ctx).count)|schluessel=\(keys)")
        XCTAssertTrue(keys.contains("id:beta.de") && keys.contains("name:sport1") && keys.contains("name:münchen tv"), "\(keys)")

        // AK-12: gleiche Sender, umgekehrte Reihenfolge, neue Stream-Adressen; „Rand TV“ mit Leerzeichen am Rand (M3U trimmt)
        let oldIDs = Set(pl.channels.map(\.id))
        var v2 = Array(v1.reversed().enumerated().map { (i, e) -> E in var e = e; e.url = u(100 + i); return e })
        if let i = v2.firstIndex(where: { $0.name == "Rand TV" }) { v2[i].name = "  Rand TV  " }
        try await refreshM3U(ctx, pl, path: path, v2)
        let after2 = try B05QA.favLabels(ctx)
        B05QA.evidence("AK-11-14-m3u.txt", "stufe2-umsortiert-neue-adressen|\(after2)")
        XCTAssertEqual(after2, starred.map { "\($0)@QA M3U" }.sorted())
        XCTAssertTrue(oldIDs.isDisjoint(with: Set(pl.channels.map(\.id))), "alle Sender neu angelegt")

        // AK-12 Umbenennung mit gleicher tvg-id, AK-13 Namensvarianten, AK-14 Verlust
        let v3: [E] = [
            E(name: "Alpha", tvg: "alpha.de", url: u(201)),
            E(name: "Beta HD", tvg: "beta.de", url: u(202)),              // umbenannt, gleiche tvg-id → bleibt
            E(name: "Gamma", tvg: "gamma.de", url: u(203)),
            E(name: "SPORT1", url: u(204)),                               // nur Groß/Klein → bleibt
            E(name: "MÜNCHEN TV", url: u(205)),                           // Groß mit Umlaut → bleibt
            E(name: "STRASSE TV", url: u(206)),                           // ß → SS → verloren
            E(name: "ISTANBUL TV", url: u(207)),                          // İ → I → verloren
            E(name: "Cafe\u{0301} Kanal", url: u(208)),                   // zerlegte Form → bleibt
            E(name: "Kanal Zwei", url: u(209)),                           // ein Leerzeichen weniger → verloren
            E(name: "ARD", tvg: "ARD.de", url: u(210)),                   // tvg-id Groß/Klein → verloren
            E(name: "Tagesschau24", tvg: "tagesschau24.de", url: u(211)), // tvg-id neu → verloren
            E(name: "Phoenix", url: u(212)),                              // tvg-id weg → verloren
            // KiKA fehlt → verloren
            E(name: "Rand TV", url: u(214)),
        ]
        try await refreshM3U(ctx, pl, path: path, v3)
        let after3 = try B05QA.favLabels(ctx)
        B05QA.evidence("AK-11-14-m3u.txt", "stufe3-abgewandelt|\(after3)")
        XCTAssertEqual(after3, ["Beta HD@QA M3U", "Cafe\u{0301} Kanal@QA M3U", "MÜNCHEN TV@QA M3U", "Rand TV@QA M3U", "SPORT1@QA M3U"].sorted())

        // AK-14: KiKA kommt zurück → kein Favorit mehr
        try await refreshM3U(ctx, pl, path: path, v3 + [E(name: "KiKA", tvg: "kika.de", url: u(213))])
        let kika = try XCTUnwrap(pl.channels.first { $0.name == "KiKA" })
        B05QA.evidence("AK-11-14-m3u.txt", "stufe4-kika-zurueck|kikaFavorit=\(kika.isFavorite)|favoriten=\(try B05QA.favLabels(ctx).count)")
        XCTAssertFalse(kika.isFavorite)

        // AK-14: kein Sender passt → alle Favoriten weg, Aktualisieren gilt als Erfolg (kein Fehler)
        var thrown: Error?
        do { try await refreshM3U(ctx, pl, path: path, [E(name: "Völlig neu", url: u(300))]) } catch { thrown = error }
        B05QA.evidence("AK-11-14-m3u.txt", "stufe5-nichts-passt|fehler=\(thrown.map { "\($0)" } ?? "keiner")|favoriten=\(try B05QA.favLabels(ctx).count)|sender=\(pl.channelCount)")
        XCTAssertNil(thrown)
        XCTAssertEqual(try B05QA.favLabels(ctx).count, 0)

        XCTExpectFailure("BUG-05: Favorit geht beim Aktualisieren still verloren und kommt nicht zurück (wartet auf OF-03)") {
            XCTAssertTrue(kika.isFavorite, "zurückgekehrter Sender sollte wieder Favorit sein oder der Verlust gemeldet werden")
        }
    }

    // MARK: AK-11 · AK-12 · AK-13 (Xtream)

    func testAK11_AK12_AK13_SchluesselXtream() async throws {
        let c = try B05QA.memoryContainer()
        let ctx = c.mainContext
        installPanel([
            ["name": "DE: ZDF HD", "stream_id": 1, "epg_channel_id": "ZDF.de", "category_id": "1"],
            ["name": "DE: ARD HD", "stream_id": 2, "epg_channel_id": "ARD.de", "category_id": "1"],
            ["name": "DE: Sky Sport 1", "stream_id": 3, "epg_channel_id": "", "category_id": "2"],
            ["name": "DE: KiKA", "stream_id": 4, "epg_channel_id": "kika.de", "category_id": "1"],
            ["name": " Rand TV", "stream_id": 5, "epg_channel_id": NSNull(), "category_id": "2"],
            ["name": "Sport Extra", "stream_id": 6, "category_id": "2"],
            ["name": "Nicht markiert", "stream_id": 7, "epg_channel_id": "nm.de", "category_id": "2"],
        ])
        let pl = try await importXtream(ctx)
        for n in ["DE: ZDF HD", "DE: ARD HD", "DE: Sky Sport 1", "DE: KiKA", " Rand TV", "Sport Extra"] {
            try B05QA.setFavorite(pl, n, ctx: ctx)
        }
        let keys = pl.channels.filter(\.isFavorite).map(\.favoriteKey).sorted()
        B05QA.evidence("AK-11-13-xtream.txt", "vorher|schluessel=\(keys)")
        XCTAssertTrue(keys.contains("id:ZDF.de") && keys.contains("name:de: sky sport 1") && keys.contains("name: rand tv"))

        installPanel([
            ["name": "Nicht markiert", "stream_id": 107, "epg_channel_id": "nm.de", "category_id": "2"],
            ["name": "SPORT EXTRA", "stream_id": 106, "category_id": "2"],                         // Groß → bleibt
            ["name": "Rand TV", "stream_id": 105, "epg_channel_id": NSNull(), "category_id": "2"],   // ohne Leerzeichen → verloren
            ["name": "DE: KiKA", "stream_id": 104, "epg_channel_id": "KiKA.de", "category_id": "1"], // tvg-id Groß/Klein → verloren
            ["name": "DE | Sky Sport 1", "stream_id": 103, "epg_channel_id": "", "category_id": "2"], // umbenannt → verloren
            ["name": "Das Erste HD", "stream_id": 102, "epg_channel_id": "ARD.de", "category_id": "1"], // umbenannt, gleiche ID → bleibt
            ["name": "DE: ZDF HD", "stream_id": 101, "epg_channel_id": "ZDF.de", "category_id": "1"],
        ])
        try await refreshXtream(ctx, pl)
        let after = try B05QA.favLabels(ctx)
        B05QA.evidence("AK-11-13-xtream.txt", "nachher|\(after)|stream-ids neu=\(pl.channels.map(\.streamURL.lastPathComponent).sorted())")
        XCTAssertEqual(after, ["DE: ZDF HD@QA Xtream", "Das Erste HD@QA Xtream", "SPORT EXTRA@QA Xtream"])
    }

    // MARK: AK-15 · EC-01 · EC-02 · EC-03 · FB-01

    func testAK15_EC01_EC03_DoppelteSchluesselVervielfachenFavoritenM3U() async throws {
        let c = try B05QA.memoryContainer()
        let ctx = c.mainContext
        let path = "/b05/ak15.m3u"
        let list: [E] = [
            E(name: "ZDF HD", tvg: "zdf.de", url: u(1), group: "Deutschland"),
            E(name: "ZDF SD", tvg: "zdf.de", url: u(2), group: "Deutschland"),
            E(name: "ZDF FHD", tvg: "zdf.de", url: u(3), group: "Deutschland"),
            E(name: "News", url: u(4), group: "News"),
            E(name: "News", url: u(5), group: "News"),
            E(name: "NEWS", url: u(6), group: "News"),
            E(name: "Leer-ID A", tvg: " ", url: u(7)),
            E(name: "Leer-ID B", tvg: " ", url: u(8)),
            E(name: "arte", tvg: "arte.de", url: u(9)),
        ]
        let pl = try await importM3U(ctx, path: path, name: "QA Dubletten", list)
        try B05QA.setFavorite(pl, "ZDF HD", ctx: ctx)
        try B05QA.setFavorite(pl, "News", index: 0, ctx: ctx)
        try B05QA.setFavorite(pl, "Leer-ID A", ctx: ctx)
        let before = try B05QA.favLabels(ctx)
        XCTAssertEqual(before.count, 3)

        // 1) Aktualisieren einer UNVERÄNDERTEN Liste
        try await refreshM3U(ctx, pl, path: path, list)
        let after1 = try B05QA.favLabels(ctx)
        B05QA.evidence("AK-15-dubletten.txt", "m3u|vorher=\(before.count) \(before)")
        B05QA.evidence("AK-15-dubletten.txt", "m3u|nach-aktualisieren-unveraendert=\(after1.count) \(after1)")

        // 2) Nutzer entfernt die zusätzlichen Sterne, dann erneut aktualisieren
        try B05QA.setFavorite(pl, "ZDF SD", false, ctx: ctx)
        try B05QA.setFavorite(pl, "ZDF FHD", false, ctx: ctx)
        try B05QA.setFavorite(pl, "News", false, index: 1, ctx: ctx)
        try B05QA.setFavorite(pl, "NEWS", false, ctx: ctx)
        try B05QA.setFavorite(pl, "Leer-ID B", false, ctx: ctx)
        let cleaned = try B05QA.favLabels(ctx)
        try await refreshM3U(ctx, pl, path: path, list)
        let after2 = try B05QA.favLabels(ctx)
        B05QA.evidence("AK-15-dubletten.txt", "m3u|nutzer-entfernt-dubletten=\(cleaned.count) → nach-aktualisieren=\(after2.count) \(after2)")

        // 3) Nur „ZDF SD“ markiert → nach dem Aktualisieren wieder alle drei
        for n in ["ZDF HD", "ZDF FHD"] { try B05QA.setFavorite(pl, n, false, ctx: ctx) }
        try B05QA.setFavorite(pl, "ZDF SD", ctx: ctx)
        try await refreshM3U(ctx, pl, path: path, list)
        let zdf = pl.channels.filter { $0.name.hasPrefix("ZDF") && $0.isFavorite }.map(\.name).sorted()
        B05QA.evidence("AK-15-dubletten.txt", "m3u|nur-ZDF-SD-markiert → \(zdf)")

        // Ist-Verhalten wie in der Spec (AK-15) …
        XCTAssertEqual(after1.count, 8, "3 → 8 bei unveränderter Liste")
        XCTAssertEqual(after2.count, 8, "entfernte Sterne kommen zurück")
        XCTAssertEqual(zdf, ["ZDF FHD", "ZDF HD", "ZDF SD"])
        // … und die Kehrseite: Die Auswahl des Nutzers bleibt NICHT erhalten.
        XCTExpectFailure("BUG-01: Aktualisieren vervielfacht Favoriten (nicht eindeutiger favoriteKey) und macht Entfernen rückgängig") {
            XCTAssertEqual(after1, before)
            XCTAssertEqual(after2, cleaned)
            XCTAssertEqual(zdf, ["ZDF SD"])
        }
    }

    func testAK15_EC02_NamenloseUndVariantenXtream() async throws {
        let c = try B05QA.memoryContainer()
        let ctx = c.mainContext
        let streams: [[String: Any]] = [
            ["name": "DE: ZDF HD", "stream_id": 1, "epg_channel_id": "ZDF.de", "category_id": "1"],
            ["name": "DE: ZDF FHD", "stream_id": 2, "epg_channel_id": "ZDF.de", "category_id": "1"],
            ["name": "DE: ZDF SD", "stream_id": 3, "epg_channel_id": "ZDF.de", "category_id": "1"],
            ["name": "", "stream_id": 4, "epg_channel_id": NSNull(), "category_id": "2"],
            ["stream_id": 5, "epg_channel_id": "", "category_id": "2"],
            ["name": NSNull(), "stream_id": 6, "category_id": "2"],
            ["name": "DE: ARD HD", "stream_id": 7, "epg_channel_id": "ARD.de", "category_id": "1"],
        ]
        installPanel(streams)
        let pl = try await importXtream(ctx)
        XCTAssertEqual(pl.channelCount, 7)
        let nameless = pl.channels.filter { $0.name.isEmpty }
        XCTAssertEqual(nameless.count, 3, "leer, fehlend und null → leerer Name")
        XCTAssertEqual(Set(nameless.map(\.favoriteKey)), ["name:"], "alle teilen den Schlüssel „name:“")
        try B05QA.setFavorite(pl, "DE: ZDF HD", ctx: ctx)
        try B05QA.setFavorite(pl, "", index: 0, ctx: ctx)
        let before = try B05QA.favLabels(ctx)

        // Tab zeigt die namenlose Karte ohne Namen
        let w = window(NavigationStack { FavoritesView() }, c, size: CGSize(width: 760, height: 520))
        B05QA.evidence("AK-15-dubletten.txt", "xtream|tab-vorher=\(w.cardLabels)")
        w.shot("EC-02-namenloser-favorit-im-tab")

        installPanel(streams.reversed().map { s -> [String: Any] in
            var s = s; s["stream_id"] = (s["stream_id"] as! Int) + 100; return s
        })
        try await refreshXtream(ctx, pl)
        let after = try B05QA.favLabels(ctx)
        B05QA.spin(0.8)
        B05QA.evidence("AK-15-dubletten.txt", "xtream|vorher=\(before.count) \(before) → nach-aktualisieren=\(after.count) \(after)")
        B05QA.evidence("AK-15-dubletten.txt", "xtream|tab-nachher=\(w.cardLabels)")
        w.shot("EC-02-nach-aktualisieren-alle-namenlosen")
        XCTAssertEqual(after.count, 6, "2 → 6: drei ZDF-Varianten und drei namenlose Sender")
        XCTExpectFailure("BUG-01: HD/FHD/SD mit gleicher epg_channel_id und namenlose Sender werden alle Favorit") {
            XCTAssertEqual(after.count, before.count)
        }
    }

    // MARK: AK-16 · EC-11

    func testAK16_EC11_ZweiPlaylistsGleicheTvgIDUnabhaengig() async throws {
        let c = try B05QA.memoryContainer()
        let ctx = c.mainContext
        let la: [E] = [E(name: "Das Erste HD", tvg: "daserste.de", url: "\(B05QA.dead)/a/1.m3u8"),
                       E(name: "ZDF", tvg: "zdf.de", url: "\(B05QA.dead)/a/2.m3u8")]
        let lb: [E] = [E(name: "Das Erste", tvg: "daserste.de", url: "\(B05QA.dead)/b/1.m3u8"),
                       E(name: "ZDF", tvg: "zdf.de", url: "\(B05QA.dead)/b/2.m3u8")]
        let a = try await importM3U(ctx, path: "/b05/a.m3u", name: "Anbieter A", la)
        let b = try await importM3U(ctx, path: "/b05/b.m3u", name: "Anbieter B", lb)
        try B05QA.setFavorite(a, "Das Erste HD", ctx: ctx)
        let aFav = try XCTUnwrap(a.channels.first { $0.isFavorite })
        let aFavID = aFav.id

        // B aktualisieren → B bekommt keinen Stern, A unverändert (dasselbe Objekt)
        try await refreshM3U(ctx, b, path: "/b05/b.m3u", lb)
        XCTAssertEqual(try B05QA.favLabels(ctx), ["Das Erste HD@Anbieter A"])
        XCTAssertEqual(a.channels.first { $0.isFavorite }?.id, aFavID)

        // Umgekehrt: B markiert ZDF, A aktualisieren → B behält seinen Stern, A bekommt keinen für ZDF
        try B05QA.setFavorite(b, "ZDF", ctx: ctx)
        try await refreshM3U(ctx, a, path: "/b05/a.m3u", la)
        XCTAssertEqual(try B05QA.favLabels(ctx), ["Das Erste HD@Anbieter A", "ZDF@Anbieter B"])

        // EC-11: dieselbe Quelle als zweite Playlist importieren → keine Favoriten, erste unberührt
        let a2 = try await importM3U(ctx, path: "/b05/a.m3u", name: "Anbieter A (2)", la)
        XCTAssertEqual(a2.channels.filter(\.isFavorite).count, 0)
        XCTAssertEqual(try B05QA.favLabels(ctx), ["Das Erste HD@Anbieter A", "ZDF@Anbieter B"])
        B05QA.evidence("AK-16-ec11.txt", "B aktualisiert → A-Objekt gleich; A aktualisiert → [Das Erste HD@A, ZDF@B]; zweiter Import derselben Quelle → 0 Favoriten")
    }

    // MARK: AK-17 · EC-05

    func testAK17_EC05_FehlschlagLaesstFavoritenUnveraendert() async throws {
        let (c, store) = try fileContainer("ak17")
        let ctx = c.mainContext
        let path = "/b05/ak17.m3u"
        let list: [E] = [E(name: "Alpha", tvg: "alpha.de", url: u(1)), E(name: "Beta", url: u(2)), E(name: "Gamma", url: u(3))]
        let pl = try await importM3U(ctx, path: path, name: "QA Fehler", list)
        try B05QA.setFavorite(pl, "Alpha", ctx: ctx)
        try B05QA.setFavorite(pl, "Gamma", ctx: ctx)
        let favBefore = try B05QA.favLabels(ctx)
        let idsBefore = Set(pl.channels.map(\.id))

        func attempt(_ label: String, _ reply: MockXtreamServer.Reply) async -> String {
            routes.setReply(path, reply)
            do { try await PlaylistImporter(modelContext: ctx).refresh(pl); return "kein Fehler" } catch { return error.localizedDescription }
        }
        var lines: [String] = []
        for (label, reply) in [
            ("http500", MockXtreamServer.Reply.raw(status: 500, contentType: "text/plain", body: Data())),
            ("http404", .raw(status: 404, contentType: "text/plain", body: Data())),
            ("leer", .raw(status: 200, contentType: "audio/x-mpegurl", body: Data("#EXTM3U\n".utf8))),
            ("html", .raw(status: 200, contentType: "text/html", body: Data("<html>Wartung</html>".utf8))),
        ] {
            let msg = await attempt(label, reply)
            let same = (try B05QA.favLabels(ctx)) == favBefore && Set(pl.channels.map(\.id)) == idsBefore
            let dbFav = B05QA.int(store.path, "SELECT COUNT(*) FROM ZCHANNEL WHERE ZISFAVORITE = 1")
            lines.append("\(label)|meldung=\(msg)|favoriten+objekte gleich=\(same)|db-favoriten=\(dbFav)")
            XCTAssertNotEqual(msg, "kein Fehler", label)
            XCTAssertTrue(same, label)
            XCTAssertEqual(dbFav, 2, label)
        }

        // Xtream: fehlende Zugangsdaten (wie nach Wiederherstellung auf neuem Gerät), leere Senderliste
        installPanel([["name": "Kanal Int", "stream_id": 1, "epg_channel_id": "kanal.int", "category_id": "1"],
                      ["name": "Kanal Zwei", "stream_id": 2, "category_id": "1"]])
        let x = try await importXtream(ctx, name: "QA Xtream Fehler")
        try B05QA.setFavorite(x, "Kanal Zwei", ctx: ctx)
        let xIDs = Set(x.channels.map(\.id))
        installPanel([])
        var emptyMsg = "kein Fehler"
        do { try await refreshXtream(ctx, x) } catch { emptyMsg = error.localizedDescription }
        lines.append("xtream-leer|meldung=\(emptyMsg)|objekte gleich=\(Set(x.channels.map(\.id)) == xIDs)|favorit=\(x.channels.first { $0.name == "Kanal Zwei" }?.isFavorite ?? false)")
        XCTAssertEqual(Set(x.channels.map(\.id)), xIDs)

        try XtreamCredentialStore.standard.delete(for: x.id)
        var missingMsg = "kein Fehler"
        do { try await refreshXtream(ctx, x) } catch { missingMsg = error.localizedDescription }
        lines.append("xtream-zugangsdaten-fehlen|meldung=\(missingMsg)|objekte gleich=\(Set(x.channels.map(\.id)) == xIDs)")
        XCTAssertTrue(missingMsg.contains("Zugangsdaten"), missingMsg)
        XCTAssertEqual(Set(x.channels.map(\.id)), xIDs)
        XCTAssertTrue(x.channels.first { $0.name == "Kanal Zwei" }?.isFavorite ?? false)

        // EC-05: Wer der Meldung folgt (löschen, neu importieren), verliert die Favoriten dieser Playlist
        try PlaylistImporter(modelContext: ctx).delete(x)
        installPanel([["name": "Kanal Int", "stream_id": 1, "epg_channel_id": "kanal.int", "category_id": "1"],
                      ["name": "Kanal Zwei", "stream_id": 2, "category_id": "1"]])
        let x2 = try await importXtream(ctx, name: "QA Xtream Fehler")
        lines.append("ec05-dem-rat-gefolgt|favoriten-neu=\(x2.channels.filter(\.isFavorite).count)")
        XCTAssertEqual(x2.channels.filter(\.isFavorite).count, 0)
        for l in lines { B05QA.evidence("AK-17-fehlschlag.txt", l) }
    }

    /// Randfall zu AK-17: Das abschließende `save()` des Aktualisierens scheitert (Datenträger voll).
    /// Braucht `TEST_RUNNER_B05_FULL_VOLUME=<Mountpoint>`.
    func testAK17_Randfall_SpeicherfehlerBeimAktualisieren() async throws {
        guard let volPath = B05QA.env("B05_FULL_VOLUME"), FileManager.default.fileExists(atPath: volPath) else {
            throw XCTSkip("kein Datenträgerabbild (TEST_RUNNER_B05_FULL_VOLUME)")
        }
        let vol = URL(fileURLWithPath: volPath)
        let filler = vol.appendingPathComponent("filler-refresh")
        let dir = vol.appendingPathComponent("ak17r-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: filler); try? FileManager.default.removeItem(at: dir) }
        let store = dir.appendingPathComponent("MikaPlusPlayer.store")
        let c = try AppPersistence.diskContainer(at: store, schema: AppSchema.schema)
        let ctx = c.mainContext
        let path = "/b05/ak17r.m3u"
        let list: [E] = [E(name: "ZDF HD", tvg: "zdf.de", url: u(1), group: "Deutschland"),
                         E(name: "ZDF SD", tvg: "zdf.de", url: u(2), group: "Deutschland"),
                         E(name: "arte", url: u(3), group: "Kultur")]
        let pl = try await importM3U(ctx, path: path, name: "QA Voll Aktualisieren", list)
        try B05QA.setFavorite(pl, "ZDF HD", ctx: ctx)
        let tab = window(NavigationStack { FavoritesView() }, c, size: CGSize(width: 760, height: 520))
        let before = tab.cardLabels
        let idsBefore = Set(pl.channels.map(\.id))

        let fd = Darwin.open(filler.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        for size in [1 << 20, 65_536, 4_096, 512, 1] {
            let buf = [UInt8](repeating: 0, count: size)
            while buf.withUnsafeBytes({ Darwin.write(fd, $0.baseAddress, size) }) > 0 {}
        }
        Darwin.close(fd)

        var message = "kein Fehler"
        do { try await refreshM3U(ctx, pl, path: path, list) } catch { message = error.localizedDescription }
        B05QA.spin(0.8)
        let uiAfter = tab.cardLabels
        let ctxFavs = try B05QA.favLabels(ctx)
        let sameObjects = Set(pl.channels.map(\.id)) == idsBefore
        var disk = "-"
        do { let c2 = try B05QA.reopen(store); disk = try B05QA.favLabels(c2.mainContext).description } catch { disk = "fehler" }
        B05QA.evidence("AK-17-randfall-speicherfehler.txt", "tab vorher=\(before)|meldung=\(message)|tab danach=\(uiAfter)|kontext-favoriten=\(ctxFavs)|dieselben objekte=\(sameObjects)|hasChanges=\(ctx.hasChanges)|datei (neustart)=\(disk)")
        tab.shot("AK-17-randfall-tab-nach-gescheitertem-speichern")
        try? FileManager.default.removeItem(at: filler)
        B05QA.spin(0.5)
        // Nächstes erfolgreiches Speichern irgendwo im Kontext
        try B05QA.setFavorite(pl, "arte", ctx: ctx)
        var disk2 = "-"
        do { let c3 = try B05QA.reopen(store); disk2 = try B05QA.favLabels(c3.mainContext).description } catch { disk2 = "fehler" }
        B05QA.evidence("AK-17-randfall-speicherfehler.txt", "nach platz + nächstem stern|datei=\(disk2)|sender in datei=\(B05QA.int(store.path, "SELECT COUNT(*) FROM ZCHANNEL"))")
        XCTAssertNotEqual(message, "kein Fehler")
        XCTAssertEqual(disk, "[\"ZDF HD@QA Voll Aktualisieren\"]", "in der Datei steht der alte Stand")
        XCTExpectFailure("BUG-11: gescheitertes Speichern beim Aktualisieren – Oberfläche zeigt den neuen, ungespeicherten Stand, technische Meldung") {
            XCTAssertEqual(uiAfter, before, "Tab soll den gespeicherten Stand zeigen")
            XCTAssertTrue(sameObjects, "Sender sollen unverändert bleiben (AK-17)")
        }
    }

    // MARK: AK-18

    func testAK18_LokaleDateiNichtAktualisierbarFavoritenBleiben() async throws {
        let c = try B05QA.memoryContainer()
        let ctx = c.mainContext
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("b05-qa-ak18-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dirs.append(dir)
        let file = dir.appendingPathComponent("QA Datei.m3u")
        try B05QA.m3u([E(name: "Datei Eins", tvg: "eins.de", url: u(1)), E(name: "Datei Zwei", url: u(2))])
            .write(to: file, atomically: true, encoding: .utf8)
        let pl = try await PlaylistImporter(modelContext: ctx).importFromFile(file)
        try B05QA.setFavorite(pl, "Datei Zwei", ctx: ctx)
        let ids = Set(pl.channels.map(\.id))
        // Datei ändern, dann „aktualisieren“
        try B05QA.m3u([E(name: "Datei Drei", url: u(3))]).write(to: file, atomically: true, encoding: .utf8)
        mock.resetLog()
        try await PlaylistImporter(modelContext: ctx).refresh(pl)
        XCTAssertFalse(pl.isRemote)
        XCTAssertEqual(Set(pl.channels.map(\.id)), ids, "wirkungslos")
        XCTAssertEqual(try B05QA.favLabels(ctx), ["Datei Zwei@QA Datei"])
        XCTAssertEqual(mock.requests.count, 0)
        // bis der Nutzer ihn ändert
        try B05QA.setFavorite(pl, "Datei Zwei", false, ctx: ctx)
        XCTAssertEqual(try B05QA.favLabels(ctx), [])
        B05QA.evidence("AK-18-datei.txt", "isRemote=false · refresh ohne Wirkung (IDs gleich, 0 Anfragen) · Favorit bleibt bis zum Entfernen")
    }

    // MARK: AK-19

    func testAK19_TabUndPlayerWaehrendAktualisieren() async throws {
        let (c, _) = try fileContainer("ak19")
        let ctx = c.mainContext
        let path = "/b05/ak19.m3u"
        let es: [E] = [E(name: "ZDF HD", tvg: "zdf.de", url: u(1), group: "Deutschland"),
                       E(name: "ZDF SD", tvg: "zdf.de", url: u(2), group: "Deutschland"),
                       E(name: "arte", url: u(3), group: "Kultur")]
        let pl = try await importM3U(ctx, path: path, name: "QA Offen", es)
        try B05QA.setFavorite(pl, "ZDF HD", ctx: ctx)
        try B05QA.setFavorite(pl, "arte", ctx: ctx)

        let tab = window(NavigationStack { FavoritesView() }, c, size: CGSize(width: 760, height: 520))
        XCTAssertEqual(tab.cardLabels, ["ZDF HD, Deutschland", "arte, Kultur"])
        tab.shot("AK-19-tab-vor-aktualisieren")
        let playerTab = window(NavigationStack { FavoritesView() }, c, size: CGSize(width: 760, height: 520), origin: CGPoint(x: 860, y: 60))
        XCTAssertTrue(playerTab.clickCardBody("arte", wait: 2.0))
        XCTAssertEqual(playerTab.window.title, "arte")

        try await refreshM3U(ctx, pl, path: path, es)
        B05QA.spin(1.5)
        let now = tab.cardLabels
        B05QA.evidence("AK-19-offen.txt", "tab vorher=[ZDF HD, arte] nachher=\(now) · player-fenster titel=\(playerTab.window.title) texte=\(playerTab.texts.prefix(4))")
        tab.shot("AK-19-tab-nach-aktualisieren")
        playerTab.shot("AK-19-player-aus-tab-nach-aktualisieren")
        XCTAssertEqual(now, ["ZDF HD, Deutschland", "ZDF SD, Deutschland", "arte, Kultur"], "neuer Stand ohne Neuladen, einschließlich AK-15")
        XCTAssertEqual(playerTab.window.title, "arte", "Player bleibt offen")
    }

    // MARK: EC-04

    func testEC04_SternWaehrendDesWartensAufDenAnbieter() async throws {
        let (c, store) = try fileContainer("ec04")
        let ctx = c.mainContext
        let path = "/b05/ec04.m3u"
        let es: [E] = [E(name: "Alpha", tvg: "alpha.de", url: u(1)), E(name: "Beta", url: u(2)), E(name: "Gamma", url: u(3))]
        let pl = try await importM3U(ctx, path: path, name: "QA Warten", es)
        try B05QA.setFavorite(pl, "Alpha", ctx: ctx)
        let list = window(NavigationStack { ChannelListView(playlist: pl) }, c, size: CGSize(width: 760, height: 520))

        routes.set(path, 200, B05QA.m3u(es), delay: 3.0)
        let task = Task { @MainActor in try await PlaylistImporter(modelContext: ctx).refresh(pl) }
        B05QA.spin(1.0)
        XCTAssertTrue(list.clickStar("Beta", wait: 0.3), "Klick während der Anbieter antwortet")
        let dbDuring = B05QA.dbFavorite(store, name: "Beta")
        try await task.value
        B05QA.spin(0.8)
        let after = try B05QA.favLabels(ctx)
        B05QA.evidence("EC-04.txt", "klick nach 1 s von 3 s Wartezeit|db sofort=\(dbDuring)|nach aktualisieren=\(after)|liste=\(list.cardLabels)")
        XCTAssertEqual(dbDuring, "1")
        XCTAssertEqual(after, ["Alpha@QA Warten", "Beta@QA Warten"])
        XCTAssertEqual(list.starColor("Beta"), "akzent")
    }
}
