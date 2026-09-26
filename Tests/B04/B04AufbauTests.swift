import XCTest
import SwiftUI
import SwiftData
import AppKit
@testable import MikaPlusPlayer

/// B04 · Senderliste — Aufbau der Seite und der Karten (QA Durchlauf 1).
/// Echte `PlaylistsView`/`ChannelListView` im Fenster des macOS-Test-Hosts, Bedienung über Accessibility und
/// synthetische Mausklicks, Nachweise als Fensteraufnahmen unter `features/B04-senderliste/qa/`.
final class B04AufbauTests: B04TestCase {

    private var basisItems: [B04QA.Item] {
        [
            .init("Alpha Eins", "Sport", logo: "\(host.base)/nocache/a.png"),
            .init("Beta Zwei", " Sport", logo: "\(host.base)/nocache/b.png"),
            .init("Gamma Drei", "News"),
            .init("Delta Vier", nil),
            .init("Epsilon Fünf", "   "),
        ]
    }

    // MARK: - AK-01

    func testAK01_KarteOeffnetSenderlisteMitKopfzeileTitelUndSuchfeld() throws {
        let (c, _) = try fileContainer("ak01")
        try B04QA.seed(c.mainContext, name: "QA Aufbau", items: basisItems)
        let w = window(c)
        B04QA.spin(0.8)
        // Wie der Nutzer: Karte in der Übersicht anklicken
        let card = try XCTUnwrap(w.rows.first { $0.label.hasPrefix("QA Aufbau") }, "Playlist-Karte in der Übersicht")
        B04QA.log("AK-01|uebersicht=\(w.cardNames)")
        w.click(card.element, wait: 1.5)

        B04QA.log("AK-01|titel=\(w.window.title)|kopf=\(w.header ?? "-")|texte=\(w.staticTexts)")
        B04QA.log("AK-01|toolbar=\(w.window.toolbar?.items.map(\.itemIdentifier.rawValue) ?? [])|suchfeld=\(w.searchField?.placeholderString ?? "nil")")
        w.shot("AK-01-senderliste")
        XCTAssertEqual(w.header, "MIKA+PLAYER · 5 SENDER")
        XCTAssertTrue(w.staticTexts.contains("QA Aufbau"), "Playlistname groß im Inhalt")
        XCTAssertEqual(w.window.title, "QA Aufbau", "Fenstertitel (macOS)")
        XCTAssertEqual(w.searchField?.placeholderString, "Sender suchen")
        XCTAssertEqual(windows.count, 1, "im selben Fenster, kein zweites")
        XCTAssertEqual(w.cardNames.count, 5, "fünf Senderkarten")

        // Kopfzeile in Akzentfarbe: Anteil roter Punkte im Bereich der Subline
        if let header = w.elements.first(where: { B04AX.label($0) == "MIKA+PLAYER · 5 SENDER" }) {
            let region = w.inWindow(B04AX.frame(header)).insetBy(dx: -2, dy: -2)
            let m = w.match(NSColor(Color.playerAccent), tolerance: 0.25, in: region)
            B04QA.log("AK-01|akzentpunkteInSubline=\(m.count)/\(m.total)")
            XCTAssertGreaterThan(m.count, 20, "Subline in Akzentfarbe")
        }
    }

    // MARK: - AK-02

    func testAK02_KopfzeileZeigtGesamtzahlTrotzFilter() throws {
        let (c, _) = try fileContainer("ak02")
        try B04QA.seed(c.mainContext, name: "QA Zahl", items: basisItems)
        let w = window(c)
        w.open(try XCTUnwrap(playlist(c)), wait: 1.5)
        XCTAssertEqual(w.header, "MIKA+PLAYER · 5 SENDER")
        XCTAssertTrue(w.pressChip("News"))
        B04QA.log("AK-02|chipNews|kopf=\(w.header ?? "-")|karten=\(w.cardNames)")
        XCTAssertEqual(w.cardNames.count, 1, "ein Treffer")
        XCTAssertEqual(w.header, "MIKA+PLAYER · 5 SENDER", "Gesamtzahl, nicht Trefferzahl")
        XCTAssertTrue(w.pressChip("Alle"))
        XCTAssertTrue(w.type("zzz-nichts"))
        B04QA.log("AK-02|sucheOhneTreffer|kopf=\(w.header ?? "-")|texte=\(w.staticTexts)")
        XCTAssertEqual(w.cardNames.count, 0)
        XCTAssertEqual(w.header, "MIKA+PLAYER · 5 SENDER")
    }

    // MARK: - AK-03 / EC-01 / EC-10

    func testAK03_EC01_EC10_KartenaufbauLogoNameBadge() throws {
        let (c, _) = try fileContainer("ak03")
        let longName = "QA Langer Name " + String(repeating: "Überlänge ", count: 30)
        var items = basisItems
        items.append(.init(longName, "Sport"))
        try B04QA.seed(c.mainContext, name: "QA Karten", items: items)
        let w = window(c, size: CGSize(width: 900, height: 760))
        w.open(try XCTUnwrap(playlist(c)), wait: 3.0)
        w.shot("AK-03-karten")
        let rows = w.rows
        B04QA.log("AK-03|karten=\(rows.map { "\($0.label)@\(Int($0.frame.height))" })")

        // Badge: Gruppe wird unverändert gezeigt (auch mit Leerzeichen am Rand), fehlt ohne Gruppe
        XCTAssertTrue(rows.contains { $0.label == "Alpha Eins, Sport" })
        XCTAssertTrue(rows.contains { $0.label == "Beta Zwei,  Sport" }, "Badge zeigt „ Sport“ ungekürzt")
        XCTAssertTrue(rows.contains { $0.label == "Delta Vier" }, "ohne Gruppe kein Badge")
        // EC-01: Gruppe nur aus Leerzeichen erzeugt ein Badge mit unsichtbarem Text
        let leer = rows.first { $0.label.hasPrefix("Epsilon Fünf") }
        B04QA.log("EC-01|badgeBeiLeerzeichenGruppe=\(leer?.label.debugDescription ?? "-")")
        XCTAssertEqual(leer?.label, "Epsilon Fünf,    ", "Badge mit unsichtbarem Text (drei Leerzeichen)")

        // EC-10: langer Name bleibt einzeilig -> gleiche Kartenhöhe
        let heights = Set(rows.map { Int($0.frame.height.rounded()) })
        B04QA.log("EC-10|kartenhoehen=\(heights.sorted())|langerName=\(rows.first { $0.label.hasPrefix("QA Langer Name") }?.frame.height ?? -1)")
        XCTAssertEqual(heights.count, 1, "alle Karten gleich hoch, Name einzeilig")

        // Logofeld: das 64×64-Logo des Mocks (220,60,60) erscheint links in der Karte, eingepasst mit 4 pt Rand
        let alpha = try XCTUnwrap(rows.first { $0.label == "Alpha Eins, Sport" })
        let region = w.inWindow(alpha.frame)
        let logoColor = NSColor(srgbRed: 220 / 255, green: 60 / 255, blue: 60 / 255, alpha: 1)
        let ganz = w.match(logoColor, tolerance: 0.2)
        B04QA.log("AK-03|diag|fenster=\(w.window.frame)|karte(screen)=\(alpha.frame)|karte(fenster)=\(region)|ganzesFenster=\(ganz.count)/\(ganz.total) box=\(ganz.box.map { "\($0)" } ?? "-")|punktMitte=\(w.color(atTopLeft: CGPoint(x: region.minX + 44, y: region.midY)).map { "\($0)" } ?? "-")")
        let m = w.match(logoColor, tolerance: 0.2, in: region)
        B04QA.log("AK-03|logoblock=\(m.box.map { "x=\(Int($0.minX - region.minX)) y=\(Int($0.minY - region.minY)) \(Int($0.width))x\(Int($0.height))" } ?? "nicht gefunden")")
        let box = try XCTUnwrap(m.box, "Logo im Kartenbild gefunden")
        XCTAssertEqual(box.width, 40, accuracy: 2, "48 pt Feld mit 4 pt Innenabstand")
        XCTAssertEqual(box.height, 40, accuracy: 2)
        XCTAssertLessThan(box.minX - region.minX, 40, "Logo links in der Karte")
    }

    // MARK: - AK-04

    func testAK04_KarteOeffnetPlayerSternNicht() throws {
        let (c, _) = try fileContainer("ak04")
        // Stream auf den geschlossenen Port 9: kein Ton, keine Wiedergabe
        try B04QA.seed(c.mainContext, name: "QA Player", items: [
            .init("Alpha Eins", "Sport", stream: "\(B04QA.dead)/live/1.m3u8"),
            .init("Beta Zwei", "Sport", stream: "\(B04QA.dead)/live/2.m3u8"),
        ])
        let w = window(c)
        w.open(try XCTUnwrap(playlist(c)), wait: 1.5)

        // Stern rechts: schaltet Favorit, öffnet keinen Player (B05)
        XCTAssertTrue(w.clickRow("Alpha Eins", atRightInset: 16, wait: 1.2))
        let favoriten = try c.mainContext.fetch(FetchDescriptor<Channel>()).filter(\.isFavorite).map(\.name)
        B04QA.log("AK-04|nachSternklick|titel=\(w.window.title)|favoriten=\(favoriten)|karten=\(w.cardNames.count)")
        XCTAssertEqual(w.window.title, "QA Player", "kein Player nach Klick auf den Stern")

        // Karte links: öffnet den Player im selben Stapel
        XCTAssertTrue(w.clickRow("Alpha Eins", wait: 2.0))
        B04QA.log("AK-04|nachKartenklick|titel=\(w.window.title)|texte=\(w.staticTexts.prefix(8))")
        w.shot("AK-04-player")
        XCTAssertEqual(windows.count, 1, "kein zweites Fenster")
        XCTAssertEqual(w.window.title, "Alpha Eins", "Player des angetippten Senders (Fenstertitel)")
        XCTAssertNil(w.rows.first { $0.label.hasPrefix("Beta Zwei") }, "Senderliste ist nicht mehr sichtbar")
    }

    // MARK: - AK-05

    func testAK05_NurSichtbareKartenUndLogosWerdenGeladen() throws {
        let (c, _) = try fileContainer("ak05")
        let items = (0..<2_000).map { i in
            B04QA.Item("Sender \(String(format: "%04d", i))", "Alle", logo: "\(host.base)/nocache/\(i).png")
        }
        try B04QA.seed(c.mainContext, name: "QA Lazy", items: items)
        let w = window(c, size: CGSize(width: 900, height: 700))
        w.open(try XCTUnwrap(playlist(c)), wait: 4.0)
        let ersteKarten = w.cardNames
        let ersteAnfragen = host.requests.map(\.path)
        B04QA.log("AK-05|nachOeffnen|karten=\(ersteKarten.count)|anfragen=\(ersteAnfragen.count)|dokumenthoehe=\(Int(w.scrollView?.documentView?.bounds.height ?? -1))")
        XCTAssertLessThan(ersteKarten.count, 40, "nur die sichtbaren Karten und ein Vorlauf")
        XCTAssertLessThan(ersteAnfragen.count, 40, "nur Logos der aufgebauten Karten")
        XCTAssertGreaterThan(ersteKarten.count, 3)

        let doc = w.scrollView?.documentView?.bounds.height ?? 0
        w.scroll(toY: doc / 2, wait: 3.0)
        let spaeter = host.requests.map(\.path)
        let neueKarten = w.cardNames
        B04QA.log("AK-05|nachScrollenZurMitte|karten=\(neueKarten.prefix(3))|anfragenGesamt=\(spaeter.count)")
        XCTAssertGreaterThan(spaeter.count, ersteAnfragen.count, "weitere Logos erst beim Scrollen")
        XCTAssertFalse(neueKarten.contains(ersteKarten.first ?? "-"), "andere Karten sichtbar")
        XCTAssertLessThan(spaeter.count, 200, "nicht alle 2.000 Logos")
        B04QA.evidence("AK-05-lazy.txt",
                       "AK-05 2.000 Sender: nach Öffnen \(ersteKarten.count) Karten / \(ersteAnfragen.count) Logo-Anfragen, "
                       + "nach Scrollen zur Mitte \(spaeter.count) Anfragen (Dokumenthöhe \(Int(doc)) pt)")
    }

    // MARK: - AK-30 (keine Adressen, keine Zugangsdaten)

    func testAK30_ListeZeigtWederStreamAdressenNochZugangsdaten() throws {
        let (c, _) = try fileContainer("ak30")
        let mock = MockXtreamServer()
        try mock.start()
        defer { B01.removeCachedResponses(for: mock); mock.stop() }
        let ctx = c.mainContext
        let importer = PlaylistImporter(modelContext: ctx, loginThrottle: XtreamLoginThrottle())
        let pass = "qa-pass-b04-ak30"
        let playlist = try B04QA.run(60) {
            try await importer.importFromXtream(
                XtreamCredentials(host: mock.hostPort, username: "qa-user", password: pass),
                output: .hls, name: "QA Xtream")
        }
        defer { try? XtreamCredentialStore.standard.deleteAll() }
        let w = window(c)
        w.open(playlist, wait: 2.0)
        let alle = w.texts.joined(separator: " | ") + " | " + w.window.title
        B04QA.log("AK-30|texte=\(w.texts)")
        w.shot("AK-30-xtream-liste")
        for verboten in ["qa-user", pass, "127.0.0.1", "player_api", "/live/", "http", ".m3u8"] {
            XCTAssertFalse(alle.contains(verboten), "AK-30: „\(verboten)“ steht nicht in der Liste")
        }
        // Gegenprobe: die Sender sind da, und ihre Adressen tragen keine Zugangsdaten mehr (B01-Reparatur)
        let channels = try ctx.fetch(FetchDescriptor<Channel>())
        B04QA.log("AK-30|adressen=\(channels.map(\.streamURL.absoluteString).prefix(4))")
        XCTAssertGreaterThan(w.cardNames.count, 0)
        XCTAssertFalse(channels.contains { $0.streamURL.absoluteString.contains(pass) })
    }

    // MARK: - EC-03 (gleiche Namen)

    func testEC03_SenderMitGleichemNamenErscheinenAlle() throws {
        let (c, _) = try fileContainer("ec03")
        try B04QA.seed(c.mainContext, name: "QA Dubletten", items: [
            .init("Doppel", "A"), .init("Doppel", "B"), .init("Doppel", "C"), .init("Andere", "A"),
        ])
        let w = window(c)
        w.open(try XCTUnwrap(playlist(c)), wait: 1.5)
        let doppel = w.cardNames.filter { $0.hasPrefix("Doppel") }
        B04QA.log("EC-03|karten=\(w.cardNames)")
        XCTAssertEqual(doppel.count, 3, "alle drei Sender mit gleichem Namen erscheinen")
    }

    // MARK: - Hilfen

    private func playlist(_ c: ModelContainer) throws -> Playlist? {
        try c.mainContext.fetch(FetchDescriptor<Playlist>()).first
    }
}
