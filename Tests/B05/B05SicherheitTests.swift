import XCTest
import SwiftUI
import SwiftData
import AppKit
@testable import MikaPlusPlayer

/// B05 · Angriffsdurchlauf, übertragen auf eine lokale App ohne Backend (Angriffe 1, 3, 7).
/// Angriffe 2, 4, 5, 8 stehen in `B05DatenschutzTests` bzw. `B05LoeschenTests`, Angriff 6 läuft außerhalb (git/strings).
@MainActor
final class B05SicherheitTests: B05TestCase {

    typealias E = B05QA.E

    // MARK: Angriff 1 · fremde IDs in Predicates

    /// Der Tab filtert nur `isFavorite == true`, ohne Bezug zu einer Playlist. Ein Sender, dessen Playlist fehlt bzw. dessen
    /// `playlistID` auf eine fremde Playlist zeigt (manipulierte oder beschädigte Datenbank), erscheint trotzdem und bleibt
    /// auch nach dem Löschen aller Playlists stehen. Aktualisieren und Löschen einer Playlist gehen über die Beziehung,
    /// nicht über `playlistID`.
    func testAngriff1_FremdeUndVerwaisteIDsImTab() async throws {
        let (c, store) = try fileContainer("angriff1")
        let ctx = c.mainContext
        let a = try await importM3U(ctx, path: "/b05/a.m3u", name: "Anbieter A", [E(name: "Alpha", tvg: "alpha.de", url: B05QA.stream(1))])
        let b = try await importM3U(ctx, path: "/b05/b.m3u", name: "Anbieter B", [E(name: "Beta", tvg: "beta.de", url: B05QA.stream(2))])
        try B05QA.setFavorite(a, "Alpha", ctx: ctx)
        // verwaist (keine Playlist) und mit fremder playlistID (zeigt auf B), aber an keiner Beziehung
        ctx.insert(Channel(name: "B05VERWAIST", streamURL: URL(string: "\(B05QA.dead)/x/1.m3u8")!, tvgID: "alpha.de", isFavorite: true,
                           playlist: nil, playlistID: UUID()))
        ctx.insert(Channel(name: "B05FREMD", streamURL: URL(string: "\(B05QA.dead)/x/2.m3u8")!, tvgID: "beta.de", isFavorite: true,
                           playlist: nil, playlistID: b.id))
        try ctx.save()

        let tab = window(NavigationStack { FavoritesView() }, c, size: CGSize(width: 760, height: 520))
        let before = tab.cardLabels
        // B aktualisieren: der fremde Sender (playlistID = B) wird weder gelöscht noch umgeschaltet
        try await refreshM3U(ctx, b, path: "/b05/b.m3u", [E(name: "Beta", tvg: "beta.de", url: B05QA.stream(3))])
        // A und B löschen
        try await PlaylistImporter(modelContext: ctx).delete(a)
        try await PlaylistImporter(modelContext: ctx).delete(b)
        B05QA.spin(0.8)
        let after = tab.cardLabels
        let orphanRows = B05QA.rows(store.path, "SELECT ZNAME, ZISFAVORITE, ZPLAYLIST FROM ZCHANNEL ORDER BY ZNAME")
        B05QA.evidence("Angriff-1.txt", "tab vorher=\(before) · nach Aktualisieren von B und Löschen von A und B=\(after) · zeilen=\(orphanRows)")
        tab.shot("Angriff-1-verwaiste-favoriten")
        XCTAssertEqual(after, ["B05FREMD", "B05VERWAIST"], "verwaiste Favoriten bleiben im Tab")
        // Nur über den Stern entfernbar
        XCTAssertTrue(tab.clickStar("B05VERWAIST", wait: 0.8))
        XCTAssertEqual(tab.cardLabels, ["B05FREMD"])
    }

    // MARK: Angriff 3 · Wiederholversuche

    func testAngriff3_VierzigSchnelleKlicks() throws {
        let (c, store) = try fileContainer("angriff3")
        let pl = try seed(c.mainContext, name: "QA Klicks", [("Kanal Klick", "News", nil, false, nil), ("Kanal Ruhe", nil, nil, false, nil)])
        let list = window(NavigationStack { ChannelListView(playlist: pl) }, c, size: CGSize(width: 760, height: 420))
        let tab = window(NavigationStack { FavoritesView() }, c, size: CGSize(width: 760, height: 420), origin: CGPoint(x: 860, y: 60))
        let pt = try XCTUnwrap(list.starPoint("Kanal Klick"))
        mock.resetLog()
        var dbValues: [String] = []
        let total = B05QA.ms {
            for _ in 0..<40 {
                list.clickScreen(pt)
                dbValues.append(B05QA.dbFavorite(store, name: "Kanal Klick"))
            }
        }
        B05QA.spin(1.0)
        let ch = try XCTUnwrap(pl.channels.first { $0.name == "Kanal Klick" })
        let alternating = dbValues.enumerated().allSatisfy { $0.element == ($0.offset % 2 == 0 ? "1" : "0") }
        B05QA.evidence("Angriff-3.txt", "40 Klicks in \(Int(total)) ms (\(B05QA.f1(total / 40)) ms je Klick)|db nach jedem Klick abwechselnd 1/0=\(alternating)|ende isFavorite=\(ch.isFavorite) db=\(B05QA.dbFavorite(store, name: "Kanal Klick"))|tab=\(tab.cardLabels)|hasChanges=\(c.mainContext.hasChanges)|netzanfragen=\(mock.requests.count)")
        XCTAssertTrue(alternating, "\(dbValues)")
        XCTAssertFalse(ch.isFavorite)
        XCTAssertEqual(tab.cardLabels, [])
        XCTAssertEqual(mock.requests.count, 0, "Umschalten erzeugt keinen Netzverkehr")
    }

    // MARK: Angriff 7 · Eingaben

    func testAngriff7_UngewoehnlicheNamenUndTvgIDs() async throws {
        let (c, store) = try fileContainer("angriff7")
        let ctx = c.mainContext
        let long = "B05LANG " + String(repeating: "x", count: 10_000)
        let names = ["A", long, "📺😀 Emoji Sender", "'; DROP TABLE ZCHANNEL; --", "<script>alert(1)</script>", "../../etc/passwd",
                     "Rechts\u{202E}links", "Null\u{0000}Byte", "Tab\tName", "Komma, \"zitiert\""]
        var es: [E] = []
        for (i, n) in names.enumerated() {
            es.append(E(name: n, tvg: i % 2 == 0 ? nil : "tvg-" + n, url: B05QA.stream(700 + i), group: "Angriff"))
        }
        let path = "/b05/angriff7.m3u"
        let pl = try await importM3U(ctx, path: path, name: "QA Eingaben", es)
        let imported = pl.channels.map(\.name)
        for ch in pl.channels { ch.isFavorite = true }
        try ctx.save()
        let before = try B05QA.favLabels(ctx)
        try await refreshM3U(ctx, pl, path: path, es)
        let after = try B05QA.favLabels(ctx)
        let tableOK = B05QA.int(store.path, "SELECT COUNT(*) FROM ZCHANNEL")
        let tab = window(NavigationStack { FavoritesView() }, c, size: CGSize(width: 760, height: 1400), origin: CGPoint(x: 60, y: 0), borderless: true)
        B05QA.spin(1.0)
        let heights = tab.cards.map { Int($0.frame.height) }
        let longCard = tab.cards.first { $0.label.hasPrefix("B05LANG") }
        tab.shot("Angriff-7-eingaben-im-tab")
        B05QA.evidence("Angriff-7.txt", "importiert=\(imported.count) (\(imported.map { $0.count > 40 ? "\($0.prefix(12))…(\($0.count))" : $0.debugDescription }))")
        B05QA.evidence("Angriff-7.txt", "favoriten vor/nach unverändertem aktualisieren=\(before.count)/\(after.count)|gleich=\(before == after)|ZCHANNEL=\(tableOK)|kartenhöhen=\(heights)|lange karte label-länge=\(longCard?.label.count ?? -1)")
        func short(_ l: [String]) -> [String] { l.map { $0.count > 40 ? "\($0.prefix(12))…(\($0.count))" : $0 } }
        let lost = Set(before).subtracting(after)
        B05QA.evidence("Angriff-7.txt", "verloren beim aktualisieren=\(short(Array(lost)))")
        XCTAssertEqual(Set(before).subtracting(lost), Set(after), "außer dem NUL-Fall bleiben alle Favoriten")
        XCTAssertEqual(tableOK, pl.channelCount)
        XCTExpectFailure("BUG-09: NUL-Zeichen in Name/tvg-id – die Datenbank kürzt beim Speichern, der Favorit geht bei jedem Aktualisieren verloren") {
            XCTAssertTrue(lost.isEmpty, "\(short(Array(lost)))")
        }
        XCTAssertEqual(Set(heights).count, 1, "alle Karten gleich hoch (einzeilig)")
        // Stern auf der langen Karte funktioniert
        let longName = try XCTUnwrap(pl.channels.first { $0.name.hasPrefix("B05LANG") }?.name)
        XCTAssertTrue(tab.clickStar(longName, wait: 0.8))
        XCTAssertEqual(B05QA.dbFavorite(store, name: longName), "0")
    }

    /// Ursache von BUG-09: Der Parser behält das NUL-Zeichen, die SQLite-Datei speichert den Text nur bis dazu. Das
    /// Objekt im Speicher behält den vollen Wert bis zum nächsten Laden – danach passt der Schlüssel nicht mehr.
    func testAngriff7_NulZeichenWirdBeimSpeichernGekuerzt() throws {
        let parsed = M3UParser().parse("#EXTM3U\n#EXTINF:-1 tvg-id=\"tvg-Null\u{0000}Byte\",Null\u{0000}Byte\nhttp://127.0.0.1:9/n.m3u8\n")
        let (c, store) = try fileContainer("nul")
        let pl = Playlist(name: "QA NUL"); c.mainContext.insert(pl)
        let ch = Channel(name: "Null\u{0000}Byte", streamURL: URL(string: "\(B05QA.dead)/n.m3u8")!, tvgID: "tvg-Null\u{0000}Byte",
                         isFavorite: true, playlist: pl, playlistID: pl.id)
        c.mainContext.insert(ch)
        try c.mainContext.save()
        let keyInMemory = ch.favoriteKey
        let c2 = try B05QA.reopen(store)  // Container festhalten, sonst sind die Objekte ohne Kontext
        let reloaded = try XCTUnwrap(try c2.mainContext.fetch(FetchDescriptor<Channel>()).first)
        B05QA.evidence("Angriff-7.txt", "nul|parser name=\(parsed.first?.name.unicodeScalars.count ?? -1) zeichen, tvg=\(parsed.first?.tvgID?.unicodeScalars.count ?? -1)|im speicher schlüssel=\(keyInMemory.debugDescription)|nach neustart name=\(reloaded.name.debugDescription) schlüssel=\(reloaded.favoriteKey.debugDescription)")
        XCTAssertEqual(parsed.first?.name.unicodeScalars.count, 9)
        XCTExpectFailure("BUG-09: NUL-Zeichen wird beim Speichern abgeschnitten, der Favoriten-Schlüssel ändert sich") {
            XCTAssertEqual(reloaded.favoriteKey, keyInMemory)
        }
    }
}
