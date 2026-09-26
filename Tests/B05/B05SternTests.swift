import XCTest
import SwiftUI
import SwiftData
import AppKit
@testable import MikaPlusPlayer

/// B05 · Stern in der Senderkarte (AK-01 bis AK-05, EC-07, EC-08). Echte `ChannelListView`/`FavoritesView` in
/// Fenstern des Test-Hosts, synthetische Mausklicks, Zustand über Accessibility, Pixelfarbe und die SQLite-Datei.
@MainActor
final class B05SternTests: B05TestCase {

    private func threeChannels(_ label: String) throws -> (ModelContainer, URL, Playlist) {
        let (c, store) = try fileContainer(label)
        let pl = try seed(c.mainContext, name: "QA Stern", [
            ("Das Erste HD", "Vollprogramm", "daserste.de", false, nil),
            ("ZDF", "Vollprogramm", nil, false, nil),
            ("arte", nil, nil, false, nil),
        ])
        return (c, store, pl)
    }

    // MARK: AK-01

    func testAK01_SternRechtsGrauUndAkzentMitMultiviewDaneben() throws {
        let (c, _, pl) = try threeChannels("ak01")
        let zdf = try XCTUnwrap(pl.channels.first { $0.name == "ZDF" })
        zdf.isFavorite = true
        try c.mainContext.save()

        let list = window(NavigationStack { ChannelListView(playlist: pl) }, c, size: CGSize(width: 760, height: 520))
        XCTAssertEqual(list.cards.count, 3, "drei Karten: \(list.cardLabels)")
        XCTAssertEqual(list.starColor("Das Erste HD"), "grau")
        XCTAssertEqual(list.starColor("arte"), "grau")
        XCTAssertEqual(list.starColor("ZDF"), "akzent")
        list.shot("AK-01-senderliste-stern-grau-und-akzent")

        let tab = window(NavigationStack { FavoritesView() }, c, size: CGSize(width: 760, height: 420), origin: CGPoint(x: 860, y: 60))
        XCTAssertEqual(tab.cardLabels, ["ZDF, Vollprogramm"])
        XCTAssertEqual(tab.starColor("ZDF"), "akzent")
        tab.shot("AK-01-favoriten-tab-stern-akzent")

        // Reihenfolge der Bedienelemente in der Karte: ⊞ links vom Stern (Aktionen in Leserichtung),
        // ein Hilfetext nur vom ⊞-Button.
        for w in [list, tab] {
            let card = try XCTUnwrap(w.card("ZDF"))
            let actions = B05AX.customActions(card.element).map(\.name)
            XCTAssertEqual(actions, ["Rectangle Split Two By Two", "Favourite"], "Aktionen der Karte")
            XCTAssertEqual(B05AX.text(card.element, "accessibilityHelp"), "Zu Multiview hinzufügen")
            B05QA.evidence("AK-01-05-accessibility.txt", "AK-01|\(w === list ? "liste" : "tab")|\(B05AX.describe(card.element))")
        }
        // Stern liegt am rechten Rand: Pixel 24 pt vor dem Kartenrand ist Akzent, 60 pt davor (⊞) nicht.
        let card = try XCTUnwrap(list.card("ZDF"))
        let mvPoint = NSPoint(x: card.frame.maxX - 58, y: card.frame.midY)
        XCTAssertNotEqual(color(list, at: mvPoint), "akzent", "⊞ ist nicht in Akzentfarbe")
    }

    private func color(_ w: B05Window, at pt: NSPoint) -> String {
        guard let v = w.window.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return "?" }
        v.cacheDisplay(in: v.bounds, to: rep)
        let pView = v.convert(w.window.convertPoint(fromScreen: pt), from: nil)
        let scale = CGFloat(rep.pixelsWide) / v.bounds.width
        var red = 0
        for dx in -8...8 {
            for dy in -8...8 {
                let x = Int((pView.x + CGFloat(dx)) * scale)
                let y = Int((v.isFlipped ? pView.y + CGFloat(dy) : v.bounds.height - (pView.y + CGFloat(dy))) * scale)
                guard x >= 0, y >= 0, x < rep.pixelsWide, y < rep.pixelsHigh, let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if c.redComponent - max(c.greenComponent, c.blueComponent) > 0.25 { red += 1 }
            }
        }
        return red > 8 ? "akzent" : "kein-akzent"
    }

    // MARK: AK-02

    func testAK02_KlickSpeichertSofortDauerhaftUndDoppelklickSchaltetZweimal() throws {
        let (c, store, pl) = try threeChannels("ak02")
        let zdf = try XCTUnwrap(pl.channels.first { $0.name == "ZDF" })
        let list = window(NavigationStack { ChannelListView(playlist: pl) }, c, size: CGSize(width: 760, height: 520))
        XCTAssertEqual(B05QA.dbFavorite(store, name: "ZDF"), "0")

        // Klick: synchron gespeichert (Datei direkt nach dem Ereignis, ohne Run-Loop-Durchlauf)
        let pt = try XCTUnwrap(list.starPoint("ZDF"))
        list.clickScreen(pt)
        let dbDirect = B05QA.dbFavorite(store, name: "ZDF")
        let hasChanges = c.mainContext.hasChanges
        B05QA.spin(0.6)
        XCTAssertTrue(zdf.isFavorite)
        XCTAssertEqual(dbDirect, "1", "Wert steht im selben Moment in der Datei")
        XCTAssertFalse(hasChanges)
        XCTAssertEqual(list.starColor("ZDF"), "akzent")
        list.shot("AK-02-nach-klick-akzent")

        // „Neustart“: zweiter Container auf dieselbe Datei
        let c2 = try B05QA.reopen(store)
        XCTAssertEqual(try B05QA.tabQuery(c2.mainContext).map(\.name), ["ZDF"])

        // Zweiter Klick: aufgehoben, ebenso sofort
        list.clickScreen(pt)
        let dbDirect2 = B05QA.dbFavorite(store, name: "ZDF")
        B05QA.spin(0.6)
        XCTAssertFalse(zdf.isFavorite)
        XCTAssertEqual(dbDirect2, "0")
        XCTAssertEqual(list.starColor("ZDF"), "grau")
        let c3 = try B05QA.reopen(store)
        XCTAssertEqual(try B05QA.tabQuery(c3.mainContext).count, 0)

        // Schneller Doppelklick (zwei Klicks ohne Pause, zweiter mit clickCount 2)
        list.clickScreen(pt, clickCount: 1)
        list.clickScreen(pt, clickCount: 2)
        B05QA.spin(0.6)
        XCTAssertFalse(zdf.isFavorite, "zweimal umgeschaltet → Ausgangszustand")
        XCTAssertEqual(B05QA.dbFavorite(store, name: "ZDF"), "0")
        B05QA.evidence("AK-02-speichern.txt",
                       "klick1: db sofort=\(dbDirect) hasChanges=\(hasChanges) · neustart=[ZDF] · klick2: db sofort=\(dbDirect2) · doppelklick: isFavorite=\(zdf.isFavorite) db=\(B05QA.dbFavorite(store, name: "ZDF"))")
    }

    // MARK: AK-03

    func testAK03_SternOeffnetKeinenPlayerKarteSchon() throws {
        let (c, _, pl) = try threeChannels("ak03")
        let list = window(NavigationStack { ChannelListView(playlist: pl) }, c, size: CGSize(width: 760, height: 520))
        let before = list.staticTexts
        XCTAssertTrue(before.contains("MIKA+PLAYER · 3 SENDER"), "\(before)")

        XCTAssertTrue(list.clickStar("arte", wait: 1.5))
        let arte = try XCTUnwrap(pl.channels.first { $0.name == "arte" })
        XCTAssertTrue(arte.isFavorite)
        XCTAssertTrue(list.staticTexts.contains("MIKA+PLAYER · 3 SENDER"), "Liste bleibt stehen")
        XCTAssertEqual(list.window.title, "QA Stern")
        XCTAssertEqual(list.cards.count, 3)

        // Klick auf den Namen der Karte „Das Erste HD“ öffnet den Player, Stern unverändert
        let erste = try XCTUnwrap(pl.channels.first { $0.name == "Das Erste HD" })
        XCTAssertTrue(list.clickCardBody("Das Erste HD", wait: 2.0))
        XCTAssertFalse(erste.isFavorite, "Stern unverändert")
        XCTAssertEqual(list.window.title, "Das Erste HD", "Player im Stapel, Fenstertitel = Sendername")
        XCTAssertFalse(list.staticTexts.contains("MIKA+PLAYER · 3 SENDER"))
        list.shot("AK-03-klick-auf-karte-player")
        B05QA.evidence("AK-03-navigation.txt", "stern: arte=\(arte.isFavorite), titel danach=QA Stern · karte: titel=\(list.window.title), texte=\(list.texts.prefix(6))")
    }

    // MARK: AK-04 · EC-07

    func testAK04_EC07_TabInZweitemFensterFolgtSofort() throws {
        let (c, _, pl) = try threeChannels("ak04")
        let list = window(NavigationStack { ChannelListView(playlist: pl) }, c, size: CGSize(width: 700, height: 460))
        let tab = window(NavigationStack { FavoritesView() }, c, size: CGSize(width: 700, height: 460), origin: CGPoint(x: 800, y: 60))
        XCTAssertTrue(tab.staticTexts.contains("Keine Favoriten"))

        list.clickStar("ZDF", wait: 0)
        let appeared = B05QA.wait(1.0) { tab.cardLabels == ["ZDF, Vollprogramm"] }
        XCTAssertTrue(appeared, "Karte erscheint ohne Neuladen: \(tab.cardLabels)")
        list.clickStar("Das Erste HD", wait: 0)
        XCTAssertTrue(B05QA.wait(1.0) { tab.cardLabels == ["Das Erste HD, Vollprogramm", "ZDF, Vollprogramm"] }, "\(tab.cardLabels)")
        tab.shot("AK-04-tab-zweites-fenster-zwei-favoriten")

        list.clickStar("ZDF", wait: 0)
        XCTAssertTrue(B05QA.wait(1.0) { tab.cardLabels == ["Das Erste HD, Vollprogramm"] }, "\(tab.cardLabels)")
        list.clickStar("Das Erste HD", wait: 0)
        XCTAssertTrue(B05QA.wait(1.0) { tab.staticTexts.contains("Keine Favoriten") })
        B05QA.evidence("AK-04-zwei-fenster.txt", "erscheinen/verschwinden je < 1 s ohne Neuladen, Endzustand leer=\(tab.staticTexts.contains("Keine Favoriten"))")
    }

    // MARK: EC-08

    func testEC08_EntfernenImTabGrautSternInOffenerListe() throws {
        let (c, _, pl) = try threeChannels("ec08")
        let zdf = try XCTUnwrap(pl.channels.first { $0.name == "ZDF" })
        zdf.isFavorite = true
        try c.mainContext.save()
        let list = window(NavigationStack { ChannelListView(playlist: pl) }, c, size: CGSize(width: 700, height: 460))
        let tab = window(NavigationStack { FavoritesView() }, c, size: CGSize(width: 700, height: 460), origin: CGPoint(x: 800, y: 60))
        XCTAssertEqual(list.starColor("ZDF"), "akzent")
        XCTAssertTrue(tab.clickStar("ZDF", wait: 0.8))
        XCTAssertTrue(tab.staticTexts.contains("Keine Favoriten"))
        XCTAssertEqual(list.starColor("ZDF"), "grau", "Senderliste folgt ohne Neuladen")
        list.shot("EC-08-liste-nach-entfernen-im-tab")
    }

    // MARK: AK-05 · VoiceOver

    func testAK05_VoiceOverKarteEinElementSternNurAlsAktionOhneZustand() throws {
        let (c, _, pl) = try threeChannels("ak05")
        let zdf = try XCTUnwrap(pl.channels.first { $0.name == "ZDF" })
        let list = window(NavigationStack { ChannelListView(playlist: pl) }, c, size: CGSize(width: 760, height: 520))

        let card = try XCTUnwrap(list.card("ZDF"))
        let kids = B05AX.kids(card.element).count
        let before = B05AX.describe(card.element)
        XCTAssertEqual(B05AX.labelOnly(card.element), "ZDF, Vollprogramm")
        XCTAssertEqual(kids, 0, "Karte ist ein einziges Element")
        XCTAssertEqual(list.card("arte").map { B05AX.labelOnly($0.element) }, "arte", "ohne Gruppe nur der Name")

        // Aktion „Favourite“ wie aus dem VoiceOver-Aktionen-Menü
        let fav = try XCTUnwrap(B05AX.customActions(card.element).first { $0.name == "Favourite" })
        XCTAssertTrue(B05AX.perform(fav))
        B05QA.spin(0.8)
        XCTAssertTrue(zdf.isFavorite, "Aktion schaltet um")
        let cardAfter = try XCTUnwrap(list.card("ZDF"))
        let after = B05AX.describe(cardAfter.element)
        XCTAssertEqual(list.starColor("ZDF"), "akzent")

        // „Drücken“ öffnet den Player (nicht den Stern)
        let erste = try XCTUnwrap(list.card("Das Erste HD"))
        B05AX.press(erste.element)
        B05QA.spin(2.0)
        XCTAssertEqual(list.window.title, "Das Erste HD")
        XCTAssertFalse(pl.channels.first { $0.name == "Das Erste HD" }!.isFavorite)

        // Leerzustand des Tabs: Symbol heißt ebenfalls „Favourite“
        let tab = window(NavigationStack { FavoritesView() }, try B05QA.memoryContainer(), size: CGSize(width: 600, height: 400),
                         origin: CGPoint(x: 820, y: 60))
        let tabTexts = tab.texts
        B05QA.evidence("AK-01-05-accessibility.txt", "AK-05|vorher|\(before)|kinder=\(kids)")
        B05QA.evidence("AK-01-05-accessibility.txt", "AK-05|nach-aktion-favourite|\(after)|isFavorite=\(zdf.isFavorite)")
        B05QA.evidence("AK-01-05-accessibility.txt", "AK-05|leerzustand-texte|\(tabTexts)")
        XCTAssertTrue(tabTexts.contains("Favourite"), "\(tabTexts)")

        // Kehrseite (FB-04): Der Zustand muss für VoiceOver wahrnehmbar sein – irgendein Accessibility-Merkmal der
        // Karte (Label, Wert, Aktionsname, Auswahl) muss sich zwischen „kein Favorit“ und „Favorit“ unterscheiden.
        XCTExpectFailure("BUG-04: Favoriten-Zustand für VoiceOver nicht wahrnehmbar – Karte vor und nach dem Umschalten identisch") {
            XCTAssertNotEqual(before, after, "Accessibility der Karte ändert sich nicht mit dem Favoriten-Zustand")
        }
    }
}
