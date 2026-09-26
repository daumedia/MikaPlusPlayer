import XCTest
import SwiftUI
import SwiftData
import AppKit
@testable import MikaPlusPlayer

/// B05 · Favoriten-Tab (AK-06 bis AK-10, AK-21, EC-01 Anzeige). Echte `ContentView`/`FavoritesView` in Fenstern.
@MainActor
final class B05TabTests: B05TestCase {

    // MARK: AK-06

    func testAK06_TabLeisteKopfzeileFenstertitel() throws {
        let c = try B05QA.memoryContainer()
        let w = window(ContentView(), c, size: CGSize(width: 820, height: 600))
        let tabs = w.tabButtons
        B05QA.evidence("AK-06-tabs.txt", "tab-leiste=\(tabs.map { "\($0.title):\($0.selected ? "gewählt" : "-")" })")
        B05QA.evidence("AK-06-tabs.txt", "ax-baum=\n" + B05AX.tree(w.window).prefix(24).joined(separator: "\n"))
        XCTAssertEqual(tabs.map(\.title), ["Playlists", "Favoriten"], "zwei Tabs, „Favoriten“ neben „Playlists“")
        let segs = B05AX.views(w.window.contentView!.superview!, of: NSSegmentedControl.self)
        let symbol = segs.first.flatMap { $0.segmentCount > 1 ? $0.image(forSegment: 1)?.accessibilityDescription : nil } ?? "-"
        B05QA.evidence("AK-06-tabs.txt", "segmente=\(segs.map { seg in (0..<seg.segmentCount).map { i in seg.label(forSegment: i) ?? "-" } })|symbol-tab-2=\(symbol)")
        w.shotScreen("AK-06-contentview-tab-playlists")

        w.selectTab("Favoriten")  // AXPress meldet false, schaltet aber um (Zustand wird unten geprüft)
        XCTAssertEqual(w.tabButtons.first { $0.title == "Favoriten" }?.selected, true)
        let texts = w.staticTexts
        B05QA.evidence("AK-06-tabs.txt", "nach-wahl-favoriten|titel=\(w.window.title)|texte=\(texts)")
        XCTAssertTrue(texts.contains("MIKA+PLAYER · FAVORITEN"), "\(texts)")
        XCTAssertTrue(texts.contains("Favoriten"))
        XCTAssertEqual(w.window.title, "Favoriten")
        w.shotScreen("AK-06-contentview-tab-favoriten")

        // Kopfzeile in Akzentfarbe: Pixel der Subline
        if let sub = w.elements.first(where: { B05AX.label($0) == "MIKA+PLAYER · FAVORITEN" }) {
            let f = B05AX.frame(sub)
            var red = 0
            if let v = w.window.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                v.cacheDisplay(in: v.bounds, to: rep)
                let scale = CGFloat(rep.pixelsWide) / v.bounds.width
                let origin = v.convert(w.window.convertPoint(fromScreen: NSPoint(x: f.minX, y: f.minY)), from: nil)
                for x in stride(from: 0, to: Int(f.width), by: 1) {
                    for y in stride(from: 0, to: Int(f.height), by: 1) {
                        let px = Int((origin.x + CGFloat(x)) * scale)
                        let py = Int((v.bounds.height - (origin.y + CGFloat(y))) * scale)
                        if let col = rep.colorAt(x: px, y: py)?.usingColorSpace(.sRGB),
                           col.redComponent - max(col.greenComponent, col.blueComponent) > 0.25 { red += 1 }
                    }
                }
            }
            B05QA.evidence("AK-06-tabs.txt", "subline-akzent-pixel=\(red)")
            XCTAssertGreaterThan(red, 20, "Subline in Akzentfarbe")
        } else {
            XCTFail("Subline nicht gefunden")
        }
        // Wechsel zurück zu „Playlists“ zeigt deren Kopfzeile
        w.selectTab("Playlists")
        XCTAssertTrue(w.staticTexts.contains("MIKA+PLAYER · PLAYLISTS"), "\(w.staticTexts)")
    }

    // MARK: AK-07

    func testAK07_LeerzustandOhneUndMitPlaylists() throws {
        let (c, _) = try fileContainer("ak07")
        let w = window(NavigationStack { FavoritesView() }, c, size: CGSize(width: 760, height: 520))
        let expected = ["MIKA+PLAYER · FAVORITEN", "Favoriten", "Favourite", "Keine Favoriten",
                        "Markiere Sender mit dem Stern, um sie hier zu sammeln."]
        XCTAssertEqual(w.texts, expected)
        XCTAssertTrue(w.elements.filter { B05AX.role($0) == "AXButton" }.isEmpty, "kein Button, kein Verweis")
        w.shot("AK-07-leer-ohne-playlists")
        B05QA.evidence("AK-07-leerzustand.txt", "ohne-playlists|titel=\(w.window.title)|texte=\(w.texts)")

        try seed(c.mainContext, name: "QA Ohne Favoriten", [("Kanal A", "News", nil, false, nil), ("Kanal B", nil, "b.de", false, nil)])
        B05QA.spin(0.8)
        XCTAssertEqual(w.texts, expected)
        B05QA.evidence("AK-07-leerzustand.txt", "mit-playlist-ohne-favoriten|texte=\(w.texts)")
    }

    // MARK: AK-08

    func testAK08_AlleFavoritenAllerPlaylistsInEinerListe() throws {
        let (c, store) = try fileContainer("ak08")
        let ctx = c.mainContext
        try seed(ctx, name: "Anbieter A", [("Das Erste HD", "Deutschland", "daserste.de", true, nil),
                                          ("KiKA", "Kinder", "kika.de", true, nil),
                                          ("ZDF", "Deutschland", "zdf.de", false, nil)])
        try seed(ctx, name: "Anbieter B", [("3sat", nil, nil, true, nil), ("Phoenix", "Doku", nil, false, nil)])
        let w = window(NavigationStack { FavoritesView() }, c, size: CGSize(width: 760, height: 620))
        XCTAssertEqual(w.cardLabels, ["3sat", "Das Erste HD, Deutschland", "KiKA, Kinder"])
        let texts = w.staticTexts
        XCTAssertFalse(texts.contains { $0.contains("Anbieter") }, "keine Überschrift je Playlist: \(texts)")
        XCTAssertEqual(texts.filter { $0.hasPrefix("MIKA+PLAYER") }, ["MIKA+PLAYER · FAVORITEN"], "keine Anzahl")
        let inputs = w.elements.filter { ["AXTextField", "AXSearchField", "AXComboBox", "AXPopUpButton", "AXCheckBox", "AXRadioButton"].contains(B05AX.role($0)) }
        XCTAssertTrue(inputs.isEmpty, "keine Suche, kein Filter: \(inputs.map(B05AX.describe))")
        for card in w.cards {
            XCTAssertEqual(B05AX.customActions(card.element).map(\.name), ["Rectangle Split Two By Two", "Favourite"], card.label)
        }
        w.shot("AK-08-favoriten-zwei-playlists")

        // Stern im Tab entfernt die Karte
        XCTAssertTrue(w.clickStar("KiKA", wait: 0.8))
        XCTAssertEqual(w.cardLabels, ["3sat", "Das Erste HD, Deutschland"])
        XCTAssertEqual(B05QA.dbFavorite(store, name: "KiKA"), "0")
        w.shot("AK-08-nach-entfernen-kika")

        // Klick auf eine Karte öffnet den Player im Stapel des Tabs
        XCTAssertTrue(w.clickCardBody("3sat", wait: 2.0))
        XCTAssertEqual(w.window.title, "3sat")
        XCTAssertFalse(w.staticTexts.contains("MIKA+PLAYER · FAVORITEN"))
        w.shot("AK-08-klick-karte-player-im-tab")
        B05QA.evidence("AK-08-tab.txt", "karten=[3sat, Das Erste HD, KiKA] · nach Stern KiKA: \(["3sat", "Das Erste HD, Deutschland"]) db KiKA=0 · Klick 3sat → Titel \(w.window.title)")
    }

    // MARK: AK-09 · OF-02

    func testAK09_GleichnamigeFavoritenNichtUnterscheidbarReihenfolgeDerAnlage() async throws {
        let (c, store) = try fileContainer("ak09")
        let ctx = c.mainContext
        let la: [B05QA.E] = [B05QA.E(name: "Das Erste HD", tvg: "daserste.de", url: B05QA.stream(1), group: "Deutschland"),
                             B05QA.E(name: "ZDF", tvg: "zdf.de", url: B05QA.stream(2), group: "Deutschland")]
        let lb: [B05QA.E] = [B05QA.E(name: "Das Erste HD", tvg: "daserste.de", url: B05QA.stream(11), group: "Deutschland")]
        let a = try await importM3U(ctx, path: "/b05/a.m3u", name: "Anbieter A", la)
        let b = try await importM3U(ctx, path: "/b05/b.m3u", name: "Anbieter B", lb)
        try B05QA.setFavorite(a, "Das Erste HD", ctx: ctx)
        try B05QA.setFavorite(b, "Das Erste HD", ctx: ctx)

        let w = window(NavigationStack { FavoritesView() }, c, size: CGSize(width: 760, height: 520))
        XCTAssertEqual(w.cardLabels, ["Das Erste HD, Deutschland", "Das Erste HD, Deutschland"], "zwei gleich aussehende Karten")
        let texts = w.texts
        XCTAssertFalse(texts.contains { $0.contains("Anbieter") }, "nichts zeigt die Playlist: \(texts)")
        w.shot("AK-09-zwei-gleichnamige-karten")
        let pkA = B05QA.rows(store.path, "SELECT c.Z_PK, p.ZNAME FROM ZCHANNEL c JOIN ZPLAYLIST p ON c.ZPLAYLIST = p.Z_PK WHERE c.ZISFAVORITE = 1 ORDER BY c.ZNAME, c.Z_PK")
        B05QA.evidence("AK-09-reihenfolge.txt", "vor-aktualisieren|sql ORDER BY ZNAME, Z_PK=\(pkA)")

        // Oben den Stern entfernen → entmarkiert den Sender der älteren Playlist (A)
        XCTAssertTrue(w.clickStar("Das Erste HD", index: 0, wait: 0.8))
        let aCh = try XCTUnwrap(a.channels.first { $0.name == "Das Erste HD" })
        let bCh = try XCTUnwrap(b.channels.first { $0.name == "Das Erste HD" })
        XCTAssertFalse(aCh.isFavorite, "oben = ältere Playlist A")
        XCTAssertTrue(bCh.isFavorite)
        B05QA.evidence("AK-09-reihenfolge.txt", "oben entfernt → A=\(aCh.isFavorite) B=\(bCh.isFavorite)")

        // Wieder markieren und A aktualisieren: A's Sender bekommt einen neuen Z_PK und rückt nach unten
        try B05QA.setFavorite(a, "Das Erste HD", ctx: ctx)
        try await refreshM3U(ctx, a, path: "/b05/a.m3u", la)
        B05QA.spin(0.8)
        let pkAfter = B05QA.rows(store.path, "SELECT c.Z_PK, p.ZNAME FROM ZCHANNEL c JOIN ZPLAYLIST p ON c.ZPLAYLIST = p.Z_PK WHERE c.ZISFAVORITE = 1 ORDER BY c.ZNAME, c.Z_PK")
        B05QA.evidence("AK-09-reihenfolge.txt", "nach-aktualisieren-A|sql=\(pkAfter)")
        XCTAssertEqual(pkAfter.map { $0[1] }, ["Anbieter B", "Anbieter A"], "nach dem Aktualisieren steht A unten")
        XCTAssertTrue(w.clickStar("Das Erste HD", index: 0, wait: 0.8))
        let bNow = try XCTUnwrap(b.channels.first { $0.name == "Das Erste HD" })
        XCTAssertFalse(bNow.isFavorite, "jetzt trifft der obere Stern Playlist B")
        B05QA.evidence("AK-09-reihenfolge.txt", "oben entfernt nach Aktualisieren von A → B=\(bNow.isFavorite)")

        // Kehrseite (OF-02): Karten gleichnamiger Favoriten sollen unterscheidbar sein.
        XCTExpectFailure("BUG-06: gleichnamige Favoriten verschiedener Playlists nicht unterscheidbar (wartet auf OF-02)") {
            XCTAssertNotEqual(w.cardLabels.first, w.cardLabels.last)
        }
    }

    // MARK: AK-10 · OF-01

    static let sortNames = [
        "ARD", "ard alpha", "arte", "Ärger TV", "Zebra", "zdf", "Sport 2", "Sport 10", "1LIVE", "100% Hits",
        "Écran Plus", "ecran basic", "Straße TV", "Strasse 2", "Österreich 1", "Ö3", "#Hash TV", " Leerzeichen vorn",
        "Ελληνικά", "Первый канал", "😀 Emoji TV", "İstanbul TV", "istanbul 2", "ﬁlm ligature", "film normal", "Oe24 TV",
    ]
    static let expectedCodeOrder = [
        " Leerzeichen vorn", "#Hash TV", "100% Hits", "1LIVE", "ARD", "Oe24 TV", "Sport 10", "Sport 2", "Strasse 2",
        "Straße TV", "Zebra", "ard alpha", "arte", "ecran basic", "film normal", "istanbul 2", "zdf", "Ärger TV",
        "Écran Plus", "Ö3", "Österreich 1", "İstanbul TV", "Ελληνικά", "Первый канал", "ﬁlm ligature", "😀 Emoji TV",
    ]

    func testAK10_SortierungNachZeichencode() throws {
        let (c, _) = try fileContainer("ak10")
        let ctx = c.mainContext
        var items = Self.sortNames.map { (name: $0, group: String?.none, tvg: String?.none, fav: true, logo: String?.none) }
        items += (0..<3).map { (name: "Kein Favorit \($0)", group: String?.none, tvg: String?.none, fav: false, logo: String?.none) }
        let pl = try seed(ctx, name: "QA Sortierung", items)

        let w = window(NavigationStack { FavoritesView() }, c, size: CGSize(width: 700, height: 2700), origin: CGPoint(x: 40, y: 0), borderless: true)
        B05QA.spin(1.0)
        let set = Set(Self.sortNames)
        let shown = w.cardLabels.filter { set.contains($0) }
        B05QA.evidence("AK-10-sortierung.txt", "tab|anzahl=\(shown.count)|\(shown)")
        XCTAssertEqual(shown, Self.expectedCodeOrder, "Zeichencode-Reihenfolge (Spec AK-10)")
        XCTAssertEqual(try B05QA.tabQuery(ctx).map(\.name), Self.expectedCodeOrder, "Abfrage wie der Tab")

        // Zum Vergleich die Senderliste derselben Playlist (B04: sprachgerecht)
        let list = window(NavigationStack { ChannelListView(playlist: pl) }, c, size: CGSize(width: 700, height: 2900), origin: CGPoint(x: 760, y: 0), borderless: true)
        B05QA.spin(1.0)
        let listShown = list.cardLabels.filter { set.contains($0) }
        B05QA.evidence("AK-10-sortierung.txt", "senderliste|anzahl=\(listShown.count)|\(listShown)")
        XCTAssertNotEqual(listShown, shown, "Tab und Senderliste sortieren verschieden")

        // Kehrseite (OF-01): „Ärger TV“ steht hinter „zdf“, „Zebra“ vor „ard alpha“.
        XCTExpectFailure("BUG-07: Tab sortiert nach Zeichencode statt sprachgerecht wie die Senderliste (wartet auf OF-01)") {
            XCTAssertEqual(shown, listShown)
        }
    }

    // MARK: EC-01 (Anzeige)

    func testEC01_GleichnamigeInDerselbenPlaylistNachAktualisierenZweiKarten() async throws {
        let (c, _) = try fileContainer("ec01")
        let ctx = c.mainContext
        let es: [B05QA.E] = [B05QA.E(name: "Kanal X", url: B05QA.stream(1), group: "News"),
                             B05QA.E(name: "Kanal X", url: B05QA.stream(2), group: "News"),
                             B05QA.E(name: "Kanal Y", url: B05QA.stream(3), group: "News")]
        let pl = try await importM3U(ctx, path: "/b05/ec01.m3u", name: "QA EC01", es)
        try B05QA.setFavorite(pl, "Kanal X", index: 0, ctx: ctx)
        let w = window(NavigationStack { FavoritesView() }, c, size: CGSize(width: 760, height: 520))
        XCTAssertEqual(w.cardLabels, ["Kanal X, News"])
        w.shot("EC-01-vor-aktualisieren-eine-karte")
        try await refreshM3U(ctx, pl, path: "/b05/ec01.m3u", es)
        B05QA.spin(0.8)
        B05QA.evidence("EC-01.txt", "vorher=[Kanal X, News] · nach unverändertem Aktualisieren=\(w.cardLabels)")
        w.shot("EC-01-nach-aktualisieren-zwei-karten")
        XCTExpectFailure("BUG-01: ein Favorit wird beim Aktualisieren zu mehreren (gleicher Name ohne tvg-id)") {
            XCTAssertEqual(w.cardLabels, ["Kanal X, News"])
        }
    }

    // MARK: AK-21 · OF-05

    func testAK21_KeinAlleEntfernenKeinExport() throws {
        let (c, _) = try fileContainer("ak21")
        try seed(c.mainContext, name: "QA Menü", [("Kanal A", nil, nil, true, nil), ("Kanal B", nil, nil, true, nil)])
        let w = window(ContentView(), c, size: CGSize(width: 820, height: 600))
        w.selectTab("Favoriten")
        XCTAssertEqual(w.tabButtons.first { $0.title == "Favoriten" }?.selected, true)
        // Hauptmenü der App vollständig durchsuchen (ohne die Fensterliste im Menü „Window“)
        var titles: [String] = []
        func walk(_ menu: NSMenu, _ path: String) {
            for item in menu.items {
                titles.append(path + item.title)
                if let sub = item.submenu { walk(sub, path + item.title + " › ") }
            }
        }
        if let main = NSApp.mainMenu { walk(main, "") }
        let windowTitles = Set(NSApp.windows.map(\.title))
        titles = titles.filter { t in !(t.hasPrefix("Window › ") && windowTitles.contains(String(t.dropFirst("Window › ".count)))) }
        let hits = titles.filter { $0.localizedCaseInsensitiveContains("favorit") || $0.localizedCaseInsensitiveContains("export")
            || $0.localizedCaseInsensitiveContains("sicher") }
        B05QA.evidence("AK-21-menue.txt", "hauptmenue-eintraege=\(titles.count)|treffer favorit/export/sicher=\(hits)")
        XCTAssertTrue(hits.filter { $0.localizedCaseInsensitiveContains("favorit") }.isEmpty, "\(hits)")

        let buttons = w.elements.filter { ["AXButton", "AXMenuButton", "AXPopUpButton"].contains(B05AX.role($0)) }
            .map(B05AX.label).filter { !$0.hasPrefix("Kanal") }
        B05QA.evidence("AK-21-menue.txt", "buttons-im-tab=\(buttons)|karten=\(w.cardLabels)")
        XCTAssertFalse(buttons.contains { $0.localizedCaseInsensitiveContains("alle") || $0.localizedCaseInsensitiveContains("export") })
        w.shot("AK-21-favoriten-tab-ohne-sammelbefehl")
    }
}
